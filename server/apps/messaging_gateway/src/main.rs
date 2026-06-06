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

    let envelope_evento = TenantEnvelope::novo(tenant_id, "message.received", event_payload);

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
