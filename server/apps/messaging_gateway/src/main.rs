//! Serviço messaging_gateway: Ingestão de webhooks e publicação de eventos no barramento.

use contracts::{Envelope, MessageKind, TenantEnvelope};
use redis::aio::ConnectionManager;
use transport::Server;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {
    redis_conn: ConnectionManager,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("messaging_gateway", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço messaging_gateway...");

    // 2. Conecta ao Redis para publicação de eventos
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    let state = AppState { redis_conn };

    // 3. Inicia o Servidor RPC síncrono nos 3 protocolos
    let state_clone = state.clone();
    let server = Server::from_env("MESSAGING_GATEWAY").route("ReceiveWebhook", move |env| {
        let state = state_clone.clone();
        Box::pin(async move { handler_receive_webhook(state.redis_conn, env).await })
    });

    tracing::info!("Servidor RPC do messaging_gateway configurado e pronto.");

    if let Err(e) = server.run().await {
        tracing::error!(
            "Servidor RPC do messaging_gateway parou com erro crítico: {:?}",
            e
        );
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use uuid::Uuid;

    static MESSAGING_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    /// Sobe um stub TCP mínimo que fala RESP suficiente para XADD + PING.
    async fn fake_redis(porta: u16) -> ConnectionManager {
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", porta))
            .await
            .unwrap();
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    break;
                };
                tokio::spawn(async move {
                    use tokio::io::{AsyncReadExt, AsyncWriteExt};
                    let mut buf = [0u8; 4096];
                    while let Ok(n) = socket.read(&mut buf).await {
                        if n == 0 {
                            break;
                        }
                        let req = String::from_utf8_lossy(&buf[..n]).to_uppercase();
                        for parte in req.split('*') {
                            if parte.is_empty() {
                                continue;
                            }
                            if parte.contains("PING") {
                                let _ = socket.write_all(b"+PONG\r\n").await;
                            } else {
                                // XADD retorna um ID como bulk string; +OK é aceito como String
                                let _ = socket.write_all(b"+OK\r\n").await;
                            }
                        }
                    }
                });
            }
        });
        let client = redis::Client::open(format!("redis://127.0.0.1:{porta}")).unwrap();
        ConnectionManager::new(client).await.unwrap()
    }

    #[tokio::test]
    async fn test_handler_receive_webhook_payload_valido() {
        let _guard = MESSAGING_TEST_MUTEX.lock().await;
        let redis_conn = fake_redis(29201).await;

        let payload = serde_json::json!({
            "sender_id": "whatsapp:5511999999999",
            "content": "Olá, preciso de ajuda!"
        });
        let tenant_id = Uuid::new_v4().to_string();
        let env = Envelope {
            tenant_id: tenant_id.clone(),
            traceparent: "00-trace-msg-01-01".to_string(),
            method: "ReceiveWebhook".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        let resp = handler_receive_webhook(redis_conn, env).await;

        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "ReceiveWebhookReply");
        assert_eq!(resp.tenant_id, tenant_id);
        let resp_payload: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(
            resp_payload.get("status").and_then(|v| v.as_str()),
            Some("success")
        );
        assert!(resp_payload.get("event_id").is_some());
    }

    #[tokio::test]
    async fn test_handler_receive_webhook_json_invalido_usa_defaults() {
        let _guard = MESSAGING_TEST_MUTEX.lock().await;
        let redis_conn = fake_redis(29202).await;

        let env = Envelope {
            tenant_id: Uuid::new_v4().to_string(),
            method: "ReceiveWebhook".to_string(),
            payload: b"nao_e_json!!!".to_vec(),
            ..Default::default()
        };

        // JSON inválido: fallback para json!({}) — campos sender_id/"content" ficam com defaults
        let resp = handler_receive_webhook(redis_conn, env).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "ReceiveWebhookReply");
    }

    #[tokio::test]
    async fn test_handler_receive_webhook_tenant_uuid_invalido_usa_nil() {
        let _guard = MESSAGING_TEST_MUTEX.lock().await;
        let redis_conn = fake_redis(29203).await;

        let payload = serde_json::json!({ "content": "mensagem" });
        let env = Envelope {
            tenant_id: "nao-eh-um-uuid-valido".to_string(),
            method: "ReceiveWebhook".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        };

        // tenant_id inválido: fallback para Uuid::nil() — handler ainda publica o evento
        let resp = handler_receive_webhook(redis_conn, env).await;
        assert_eq!(resp.kind, MessageKind::Reply as i32);
    }
}

/// Handler que simula o recebimento de uma mensagem via Webhook e a despacha como evento assíncrono no barramento.
async fn handler_receive_webhook(mut redis_conn: ConnectionManager, env: Envelope) -> Envelope {
    let payload_json: serde_json::Value = match serde_json::from_slice(&env.payload) {
        Ok(v) => v,
        Err(_) => serde_json::json!({}),
    };

    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());

    // Monta o envelope de domínio
    let event_payload = serde_json::json!({
        "sender_id": payload_json.get("sender_id").and_then(|v| v.as_str()).unwrap_or("externo"),
        "content": payload_json.get("content").and_then(|v| v.as_str()).unwrap_or(""),
        "timestamp": chrono::Utc::now().timestamp_millis(),
    });

    // Propaga o traceparent recebido na chamada RPC para o evento do barramento,
    // mantendo a cadeia de trace distribuído viva no salto síncrono → assíncrono.
    let envelope_evento = TenantEnvelope::novo(tenant_id, "message.received", event_payload)
        .com_traceparent(env.traceparent.clone());

    // Publica no barramento de eventos principal
    match transport::bus::publicar_evento(&mut redis_conn, &envelope_evento).await {
        Ok(id) => {
            tracing::info!(stream_id = %id, "Mensagem de webhook publicada no barramento de eventos.");
            let res =
                serde_json::json!({ "status": "success", "event_id": envelope_evento.event_id });
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "ReceiveWebhookReply".to_string(),
                payload: serde_json::to_vec(&res).unwrap_or_default(),
                error: None,
                ..env
            }
        }
        Err(e) => {
            let app_err = error_core::AppError::Cache(e.to_string());
            let err_env = app_err.to_error_envelope(&env.traceparent, "messaging_gateway");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "ReceiveWebhookReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}
