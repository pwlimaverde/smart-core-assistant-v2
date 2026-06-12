use crate::common::TEST_MUTEX;
use application::auth::logout::logout;
use application::jwt::Claims;
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::runtime::{Endpoint, Server};
use uuid::Uuid;

#[tokio::test]
async fn test_logout_completo_com_refresh() {
    let _guard = TEST_MUTEX.lock().await;
    let pg_addr = "tcp://127.0.0.1:29131";
    let redis_addr = "tcp://127.0.0.1:29132";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers");
    let pg_handle = tokio::spawn(async move {
        let _ = pg_server.run().await;
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers")
        .route("ValidateAndRotate", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({
                    "user_id": 42,
                    "tenant_id": Uuid::new_v4().to_string(),
                    "family_id": "minha_familia_123",
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
        .route("RevokeFamily", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "status": "revoked" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "RevokeFamilyReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        })
        .route("BlockToken", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "status": "blocked" });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "BlockTokenReply".to_string(),
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

    let claims = Claims {
        sub: "42".to_string(),
        tenant_id: Uuid::new_v4().to_string(),
        scopes: vec![],
        is_superuser: false,
        jti: "meu_jti_original".to_string(),
        iat: chrono::Utc::now().timestamp() as usize,
        exp: (chrono::Utc::now().timestamp() + 900) as usize,
    };

    let result = logout(
        &deps,
        "00-trace-logout1-span1-01",
        &claims,
        Some("refresh_token_valido"),
    )
    .await;
    assert!(result.is_ok(), "Erro no logout: {:?}", result.err());

    let payload = result.unwrap();
    assert_eq!(payload.get("status").unwrap().as_str().unwrap(), "success");

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_logout_apenas_com_access_token() {
    let _guard = TEST_MUTEX.lock().await;
    let pg_addr = "tcp://127.0.0.1:29133";
    let redis_addr = "tcp://127.0.0.1:29134";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers");
    let pg_handle = tokio::spawn(async move {
        let _ = pg_server.run().await;
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers").route("BlockToken", |env| {
        Box::pin(async move {
            let reply = serde_json::json!({ "status": "blocked" });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "BlockTokenReply".to_string(),
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

    let claims = Claims {
        sub: "42".to_string(),
        tenant_id: Uuid::new_v4().to_string(),
        scopes: vec![],
        is_superuser: false,
        jti: "meu_jti_original".to_string(),
        iat: chrono::Utc::now().timestamp() as usize,
        exp: (chrono::Utc::now().timestamp() + 900) as usize,
    };

    let result = logout(&deps, "00-trace-logout2-span2-01", &claims, None).await;
    assert!(result.is_ok(), "Erro no logout: {:?}", result.err());

    let payload = result.unwrap();
    assert_eq!(payload.get("status").unwrap().as_str().unwrap(), "success");

    pg_handle.abort();
    redis_handle.abort();
}

#[tokio::test]
async fn test_logout_falha_bloquear_token() {
    let _guard = TEST_MUTEX.lock().await;
    let pg_addr = "tcp://127.0.0.1:29135";
    let redis_addr = "tcp://127.0.0.1:29136";

    std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
    std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_addr);

    let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
    let pg_server = Server::new(pg_endpoint, "flatbuffers");
    let pg_handle = tokio::spawn(async move {
        let _ = pg_server.run().await;
    });

    let redis_endpoint = Endpoint::parse(redis_addr).unwrap();
    let redis_server = Server::new(redis_endpoint, "flatbuffers").route("BlockToken", |env| {
        Box::pin(async move {
            let error_env = contracts::ErrorEnvelope {
                code: "REDIS_ERROR".to_string(),
                category: contracts::ErrorCategory::Internal as i32,
                severity: contracts::Severity::Error as i32,
                message: "Erro no cache".to_string(),
                user_message: "errors.cache".to_string(),
                user_message_fallback: "Erro de cache".to_string(),
                retryable: true,
                trace_id: env.traceparent.clone(),
                source_svc: "data_redis_stub".to_string(),
                details: vec![],
                occurred_at: 0,
            };
            Envelope {
                kind: MessageKind::Error as i32,
                method: "BlockTokenReply".to_string(),
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
    };

    let claims = Claims {
        sub: "42".to_string(),
        tenant_id: Uuid::new_v4().to_string(),
        scopes: vec![],
        is_superuser: false,
        jti: "meu_jti_original".to_string(),
        iat: chrono::Utc::now().timestamp() as usize,
        exp: (chrono::Utc::now().timestamp() + 900) as usize,
    };

    let result = logout(&deps, "00-trace-logout3-span3-01", &claims, None).await;
    assert!(result.is_err());

    pg_handle.abort();
    redis_handle.abort();
}
