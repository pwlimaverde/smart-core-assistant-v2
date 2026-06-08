use application::auth::login::login;
use application::RequestContext;
use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::runtime::{Endpoint, Server};
use uuid::Uuid;

#[tokio::test]
async fn test_login_flow_success() {
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
                "is_superuser": false
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
    let redis_server =
        Server::new(redis_endpoint, "flatbuffers").route("StoreRefreshToken", |env| {
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

    // 4. Executa o login
    let ctx = RequestContext {
        tenant_id: Uuid::new_v4(),
        user_id: 0,
        user_scopes: vec![],
        traceparent: "00-trace-123-span-456-01".to_string(),
    };

    let result = login(&ctx, "test@domain.com", "senha123").await;

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

    tokio::time::sleep(Duration::from_millis(200)).await;

    let ctx = RequestContext {
        tenant_id: Uuid::new_v4(),
        user_id: 0,
        user_scopes: vec![],
        traceparent: "".to_string(),
    };

    let result = login(&ctx, "test@domain.com", "senha_errada").await;

    assert!(result.is_err());
    let err = result.err().unwrap();
    assert_eq!(err.code(), error_core::ErrorCode::AuthInvalidToken);

    pg_handle.abort();
}
