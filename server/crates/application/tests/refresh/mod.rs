use crate::common::TEST_MUTEX;
use application::auth::refresh::refresh;
use contracts::{Envelope, MessageKind};
use error_core::AppError;
use std::time::Duration;
use transport::runtime::{Endpoint, Server};
use uuid::Uuid;

#[tokio::test]
async fn test_refresh_flow_feliz() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29121";
    let redis_addr = "tcp://127.0.0.1:29122";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let tenant_id = Uuid::new_v4().to_string();

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("GetUserIdentity", move |env| {
        let tenant_id = tenant_id.clone();
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_active": true,
                "is_superuser": false,
                "tenant_id": tenant_id,
                "module_permissions": ["atendimentos:read"]
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "GetUserIdentityReply".to_string(),
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
        .route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "user_id": 42,
                    "tenant_id": Uuid::new_v4().to_string(),
                    "family_id": Uuid::new_v4().to_string(),
                    "rotacionado": false
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "ValidateAndRotateReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("StoreRefreshToken", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "status": "success" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "StoreRefreshTokenReply".to_string(),
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
        storage: None,
    };

    let result = refresh(
        &deps,
        "00-trace-refresh1-span1-01",
        "meu_refresh_token_atual",
    )
    .await;
    assert!(result.is_ok(), "Erro no refresh: {:?}", result.err());

    let tokens = result.unwrap();
    assert!(tokens.get("access_token").is_some());
    assert!(tokens.get("refresh_token").is_some());

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_refresh_flow_reuso_token_rotacionado() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29123";
    let redis_addr = "tcp://127.0.0.1:29124";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers");
    let pg_handle = tokio::spawn(async move {
        let _ = pg_server.run().await;
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let error_env = contracts::ErrorEnvelope {
                    code: "AUTH_TOKEN_REUSE".to_string(),
                    category: contracts::ErrorCategory::Auth as i32,
                    severity: contracts::Severity::Error as i32,
                    message: "token_reuse_detected".to_string(),
                    user_message: "errors.auth.token.reuse".to_string(),
                    user_message_fallback: "Alerta de segurança: token já reutilizado".to_string(),
                    retryable: false,
                    trace_id: env.traceparent.clone(),
                    source_svc: "data_redis_stub".to_string(),
                    details: vec![],
                    occurred_at: 0,
                };
                Envelope {
                    kind: MessageKind::Error as i32,
                    method: "ValidateAndRotateReply".to_string(),
                    error: Some(error_env),
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
        storage: None,
    };

    let result = refresh(&deps, "00-trace-refresh2-span2-01", "token_reutilizado").await;
    assert!(result.is_err());

    let err = result.err().unwrap();
    if let AppError::Auth(msg) = err {
        assert_eq!(msg, "token_reuse_detected");
    } else {
        panic!("Deveria retornar AppError::Auth(token_reuse_detected)");
    }

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_refresh_flow_usuario_desativado() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29125";
    let redis_addr = "tcp://127.0.0.1:29126";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("GetUserIdentity", |env| {
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_active": false, // Inativo!
                "is_superuser": false,
                "tenant_id": Uuid::new_v4().to_string(),
                "module_permissions": []
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "GetUserIdentityReply".to_string(),
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
        Server::new(redis_endpoint, "flatbuffers").route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "user_id": 42,
                    "tenant_id": Uuid::new_v4().to_string(),
                    "family_id": Uuid::new_v4().to_string(),
                    "rotacionado": false
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "ValidateAndRotateReply".to_string(),
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
        storage: None,
    };

    let result = refresh(
        &deps,
        "00-trace-refresh3-span3-01",
        "meu_refresh_token_atual",
    )
    .await;
    assert!(result.is_err());

    let err = result.err().unwrap();
    if let AppError::Auth(msg) = err {
        assert_eq!(msg, "usuário desativado");
    } else {
        panic!("Deveria retornar AppError::Auth(usuário desativado)");
    }

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_refresh_flow_usuario_sem_tenant() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29127";
    let redis_addr = "tcp://127.0.0.1:29128";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("GetUserIdentity", |env| {
        Box::pin(async move {
            let user_payload = serde_json::json!({
                "id": 42,
                "username": "usuario_teste",
                "email": "test@domain.com",
                "is_active": true,
                "is_superuser": false,
                "tenant_id": "", // Sem tenant!
                "module_permissions": []
            });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "GetUserIdentityReply".to_string(),
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
        Server::new(redis_endpoint, "flatbuffers").route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "user_id": 42,
                    "tenant_id": Uuid::nil().to_string(),
                    "family_id": Uuid::new_v4().to_string(),
                    "rotacionado": false
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "ValidateAndRotateReply".to_string(),
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
        storage: None,
    };

    let result = refresh(
        &deps,
        "00-trace-refresh4-span4-01",
        "meu_refresh_token_atual",
    )
    .await;
    assert!(result.is_err());

    let err = result.err().unwrap();
    if let AppError::Auth(msg) = err {
        assert_eq!(msg, "usuário sem tenant associado");
    } else {
        panic!(
            "Deveria retornar AppError::Auth(usuário sem tenant associado), obteve: {:?}",
            err
        );
    }

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_refresh_flow_erro_get_user_identity() {
    let _guard = TEST_MUTEX.lock().await;
    let _ = application::jwt::inicializar_chaves("segredo_de_teste_de_pelo_menos_32_bytes_longo");
    let pg_addr = "tcp://127.0.0.1:29129";
    let redis_addr = "tcp://127.0.0.1:29130";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers").route("GetUserIdentity", |env| {
        Box::pin(async move {
            let error_env = contracts::ErrorEnvelope {
                code: "DATABASE_ERROR".to_string(),
                category: contracts::ErrorCategory::Internal as i32,
                severity: contracts::Severity::Error as i32,
                message: "Conexão perdida".to_string(),
                user_message: "errors.db".to_string(),
                user_message_fallback: "Erro de banco".to_string(),
                retryable: true,
                trace_id: env.traceparent.clone(),
                source_svc: "data_postgres_stub".to_string(),
                details: vec![],
                occurred_at: 0,
            };
            Envelope {
                kind: MessageKind::Error as i32,
                method: "GetUserIdentityReply".to_string(),
                error: Some(error_env),
                ..env
            }
        })
    });
    let pg_handle = tokio::spawn(async move {
        pg_server.run().await.unwrap();
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "user_id": 42,
                    "tenant_id": Uuid::new_v4().to_string(),
                    "family_id": Uuid::new_v4().to_string(),
                    "rotacionado": false
                });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "ValidateAndRotateReply".to_string(),
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
        storage: None,
    };

    let result = refresh(
        &deps,
        "00-trace-refresh5-span5-01",
        "meu_refresh_token_atual",
    )
    .await;
    assert!(result.is_err());

    let err = result.err().unwrap();
    if let AppError::Auth(msg) = err {
        assert_eq!(msg, "sessão inválida");
    } else {
        panic!("Deveria retornar AppError::Auth(sessão inválida)");
    }

    pg_handle.abort();
    redis_handle.abort();
}
