use crate::common::TEST_MUTEX;
use application::auth::login::login;
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::runtime::{Endpoint, Server};
use uuid::Uuid;

#[tokio::test]
async fn test_login_flow_success() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    // 1. Configura as portas locais TCP para os stubs
    let pg_addr = "tcp://127.0.0.1:29101";
    let redis_addr = "tcp://127.0.0.1:29102";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    // 2. Subir o stub do data_postgres
    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_superuser": false,
                "tenant_id": Uuid::new_v4().to_string()
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "VerifyCredentialsReply".to_string(),
                payload: serde_json::to_vec(&user_payload).unwrap(),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    // 3. Subir o stub do data_redis
    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers")
        .route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("StoreRefreshToken", |env| {
            Box::pin(async move {
                let reply_payload = serde_json::json!({
                    "status": "success"
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "StoreRefreshTokenReply".to_string(),
                    payload: serde_json::to_vec(&reply_payload).unwrap(),
                    ..env
                }
            })
        });

    let redis_handle = tokio::spawn(async move {
        redis_server.run().await.unwrap();
    });

    // Aguarda stubs iniciarem
    tokio::time::sleep(Duration::from_millis(200)).await;

    // Conecta clientes multiplexados
    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    // 4. Executa o login
    let result = login(
        &deps,
        "00-trace-123-span-456-01",
        "test@domain.com",
        "senha123",
    )
    .await;

    assert!(
        result.is_ok(),
        "Falha ao realizar login: {:?}",
        result.err()
    );

    let tokens = result.unwrap();
    assert!(tokens.get("access_token").is_some());
    assert!(tokens.get("refresh_token").is_some());

    // Limpa tasks
    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_invalid_credentials() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29103";
    let redis_addr = "tcp://127.0.0.1:29104";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    // Stub do data_postgres que retorna erro gRPC/Envelope
    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let error_env = contracts::ErrorEnvelope {
                code: "AUTH_INVALID_TOKEN".to_string(),
                category: contracts::ErrorCategory::Auth as i32,
                severity: contracts::Severity::Error as i32,
                message: "Senha inválida".to_string(),
                user_message: "errors.auth.invalid.token".to_string(),
                user_message_fallback: "Credenciais inválidas".to_string(),
                retryable: false,
                trace_id: env.traceparent.clone(),
                source_svc: "data_postgres_stub".to_string(),
                details: vec![],
                occurred_at: 0,
            };
            Envelope {
                kind: MessageKind::Error as i32,
                method: "VerifyCredentialsReply".to_string(),
                error: Some(error_env),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    // Subir stub do data_redis
    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
    let redis_handle = tokio::spawn(async move {
        let _ = redis_server.run().await;
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    let result = login(
        &deps,
        "00-trace-abc-span-def-01",
        "test@domain.com",
        "senha_errada",
    )
    .await;

    assert!(result.is_err());
    let err = result.err().unwrap();
    assert_eq!(err.code(), error_core::ErrorCode::AuthInvalidToken);

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_usuario_sem_tenant() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29105";
    let redis_addr = "tcp://127.0.0.1:29106";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_superuser": false,
                "tenant_id": "" // Sem tenant
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "VerifyCredentialsReply".to_string(),
                payload: serde_json::to_vec(&user_payload).unwrap(),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
    let redis_handle = tokio::spawn(async move {
        let _ = redis_server.run().await;
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    let result = login(
        &deps,
        "00-trace-789-span-012-01",
        "test@domain.com",
        "senha123",
    )
    .await;
    assert!(result.is_err());

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_superuser_deriva_escopos() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29107";
    let redis_addr = "tcp://127.0.0.1:29108";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 1,
                "username": "superuser",
                "email": "super@domain.com",
                "is_superuser": true,
                "tenant_id": ""
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "VerifyCredentialsReply".to_string(),
                payload: serde_json::to_vec(&user_payload).unwrap(),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers")
        .route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("StoreRefreshToken", |env| {
            Box::pin(async move {
                let reply_payload = serde_json::json!({ "status": "success" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "StoreRefreshTokenReply".to_string(),
                    payload: serde_json::to_vec(&reply_payload).unwrap(),
                    ..env
                }
            })
        });
    let redis_handle = tokio::spawn(async move {
        redis_server.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    let result = login(
        &deps,
        "00-trace-789-span-012-01",
        "super@domain.com",
        "senha123",
    )
    .await;
    assert!(result.is_ok());

    let tokens = result.unwrap();
    let access = tokens.get("access_token").unwrap().as_str().unwrap();
    let claims = application::jwt::validar_access_token(access).unwrap();

    assert_eq!(claims.scopes, vec!["*".to_string()]);
    assert!(claims.is_superuser);
    assert_eq!(claims.tenant_id, "");

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_module_permissions_e_fallbacks() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29109";
    let redis_addr = "tcp://127.0.0.1:29110";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    // Stub mutável que altera a resposta conforme o payload
    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let req_payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap();
            let email = req_payload.get("email").unwrap().as_str().unwrap();

            let mut user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": email,
                "is_superuser": false,
                "tenant_id": Uuid::new_v4().to_string()
            });

            if email.contains("array") {
                user_payload["module_permissions"] = serde_json::json!(["perm1", "perm2"]);
            } else if email.contains("object") {
                user_payload["module_permissions"] = serde_json::json!({
                    "perm_ok1": true,
                    "perm_false": false,
                    "perm_ok2": true
                });
            } else if email.contains("admin") {
                user_payload["role"] = serde_json::json!("admin");
            } else {
                user_payload["role"] = serde_json::json!("atendente");
            }

            Envelope {
                kind: MessageKind::Reply as i32,
                method: "VerifyCredentialsReply".to_string(),
                payload: serde_json::to_vec(&user_payload).unwrap(),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers")
        .route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("StoreRefreshToken", |env| {
            Box::pin(async move {
                let reply_payload = serde_json::json!({ "status": "success" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "StoreRefreshTokenReply".to_string(),
                    payload: serde_json::to_vec(&reply_payload).unwrap(),
                    ..env
                }
            })
        });
    let redis_handle = tokio::spawn(async move {
        redis_server.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    // 1. Testa permissões em array
    let res = login(&deps, "00-trace-1-01", "array@domain.com", "senha123")
        .await
        .unwrap();
    let claims =
        application::jwt::validar_access_token(res.get("access_token").unwrap().as_str().unwrap())
            .unwrap();
    assert_eq!(
        claims.scopes,
        vec!["perm1".to_string(), "perm2".to_string()]
    );

    // 2. Testa permissões em objeto
    let res = login(&deps, "00-trace-2-01", "object@domain.com", "senha123")
        .await
        .unwrap();
    let claims =
        application::jwt::validar_access_token(res.get("access_token").unwrap().as_str().unwrap())
            .unwrap();
    assert!(claims.scopes.contains(&"perm_ok1".to_string()));
    assert!(claims.scopes.contains(&"perm_ok2".to_string()));
    assert!(!claims.scopes.contains(&"perm_false".to_string()));

    // 3. Testa role fallback admin
    let res = login(&deps, "00-trace-3-01", "admin@domain.com", "senha123")
        .await
        .unwrap();
    let claims =
        application::jwt::validar_access_token(res.get("access_token").unwrap().as_str().unwrap())
            .unwrap();
    assert!(claims.scopes.contains(&"tenant:admin".to_string()));

    // 4. Testa role fallback padrão (atendente)
    let res = login(&deps, "00-trace-4-01", "atendente@domain.com", "senha123")
        .await
        .unwrap();
    let claims =
        application::jwt::validar_access_token(res.get("access_token").unwrap().as_str().unwrap())
            .unwrap();
    assert!(claims.scopes.contains(&"atendimentos:read".to_string()));
    assert!(!claims.scopes.contains(&"tenant:admin".to_string()));

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_rate_limit_excedido() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29111";
    let redis_addr = "tcp://127.0.0.1:29112";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    // Stub do data_postgres: se VerifyCredentials for chamada, o corte do rate limit falhou.
    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |_env| {
        Box::pin(async move {
            panic!("VerifyCredentials não deveria ser chamada com rate limit estourado")
        })
    });
    let pg_handle = tokio::spawn(async move {
        let _ = pg_server.run().await;
    });

    // Stub do data_redis: devolve tentativas acima do limite configurado (5)
    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 6 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
    let redis_handle = tokio::spawn(async move {
        redis_server.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    let result = login(
        &deps,
        "00-trace-rate-limit-01",
        "test@domain.com",
        "senha123",
    )
    .await;

    assert!(result.is_err());
    let err = result.err().unwrap();
    assert!(
        matches!(err, error_core::AppError::RateLimit(_)),
        "esperava RateLimit, veio: {:?}",
        err
    );

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_login_flow_username_success() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");

    // 1. Configura as portas locais TCP para os stubs
    let pg_addr = "tcp://127.0.0.1:29201";
    let redis_addr = "tcp://127.0.0.1:29202";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    // 2. Subir o stub do data_postgres que valida o recebimento do username no campo email do envelope
    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("VerifyCredentials", |env| {
        Box::pin(async move {
            let req_payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap();
            let email_or_user = req_payload.get("email").unwrap().as_str().unwrap();

            // Garante que o valor recebido no payload é o username
            assert_eq!(email_or_user, "usuario_teste");

            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_superuser": false,
                "tenant_id": Uuid::new_v4().to_string()
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "VerifyCredentialsReply".to_string(),
                payload: serde_json::to_vec(&user_payload).unwrap(),
                ..env
            }
        })
    });

    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    // 3. Subir o stub do data_redis
    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers")
        .route("RegisterLoginAttempt", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "attempts": 1 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RegisterLoginAttemptReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("StoreRefreshToken", |env| {
            Box::pin(async move {
                let reply_payload = serde_json::json!({
                    "status": "success"
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "StoreRefreshTokenReply".to_string(),
                    payload: serde_json::to_vec(&reply_payload).unwrap(),
                    ..env
                }
            })
        });

    let redis_handle = tokio::spawn(async move {
        redis_server.run().await.unwrap();
    });

    // Aguarda stubs iniciarem
    tokio::time::sleep(Duration::from_millis(200)).await;

    // Conecta clientes multiplexados
    let pg_client = transport::conectar_cliente("data_postgres").await.unwrap();
    let redis_client = transport::conectar_cliente("data_redis").await.unwrap();

    let deps = application::auth::login::AuthDeps {
        pg: pg_client,
        redis: redis_client,
        access_ttl_s: 900,
        refresh_ttl_s: 604800,
        login_rate_max: 5,
        login_rate_window_s: 60,
    };

    // 4. Executa o login passando o username
    let result = login(
        &deps,
        "00-trace-123-span-456-01",
        "usuario_teste",
        "senha123",
    )
    .await;

    assert!(
        result.is_ok(),
        "Falha ao realizar login com username: {:?}",
        result.err()
    );

    let tokens = result.unwrap();
    assert!(tokens.get("access_token").is_some());
    assert!(tokens.get("refresh_token").is_some());

    // Limpa tasks
    pg_handle.abort();
    redis_handle.abort();
}
