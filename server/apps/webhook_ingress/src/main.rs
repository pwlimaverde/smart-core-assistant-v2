use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Router,
};
use serde::Deserialize;
use std::env;
use transport::bus;

#[derive(Clone)]
struct AppState {
    redis: redis::aio::ConnectionManager,
}

#[derive(Deserialize, Debug)]
struct WebhookPath {
    provider: String,
    tenant_id: uuid::Uuid,
    instance_id: i32,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("webhook_ingress", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;

    let redis_url =
        env::var("SMARTCORE_REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let client = redis::Client::open(redis_url)?;
    let redis = redis::aio::ConnectionManager::new(client).await?;
    let state = AppState { redis };

    let app = Router::new()
        // axum 0.8 sintaxe: chaves {param}
        .route(
            "/webhook/{provider}/{tenant_id}/{instance_id}",
            post(handle_webhook),
        )
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:9200").await?;
    tracing::info!("webhook_ingress ouvindo em 0.0.0.0:9200");
    axum::serve(listener, app).await?;
    Ok(())
}

#[tracing::instrument(
    skip(state, body),
    fields(
        provider    = %params.provider,
        tenant_id   = %params.tenant_id,
        instance_id = params.instance_id,
        event_type  = tracing::field::Empty
    )
)]
async fn handle_webhook(
    Path(params): Path<WebhookPath>,
    State(mut state): State<AppState>,
    body: Bytes,
) -> Result<impl IntoResponse, StatusCode> {
    let raw: serde_json::Value = serde_json::from_slice(&body).map_err(|e| {
        tracing::error!("Falha ao parsear body do webhook: {:?}", e);
        StatusCode::BAD_REQUEST
    })?;

    let event_type = raw.get("event").and_then(|e| e.as_str()).unwrap_or("");
    tracing::Span::current().record("event_type", event_type);

    let normalizado = match params.provider.as_str() {
        "evolution" => normalize_evolution(event_type, &raw, params.tenant_id, params.instance_id),
        outro => {
            tracing::warn!(provider = outro, "Provedor desconhecido no path do webhook");
            None
        }
    };

    if let Some((topic, envelope)) = normalizado {
        bus::publicar_evento(&mut state.redis, &envelope)
            .await
            .map_err(|e| {
                tracing::error!("Falha ao publicar evento no barramento: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        tracing::info!(topico = topic, "Evento normalizado publicado no barramento");
    } else {
        tracing::debug!(
            event = event_type,
            "Evento ignorado (não mapeado para este provedor)"
        );
    }

    Ok(StatusCode::ACCEPTED)
}

fn normalize_evolution(
    event: &str,
    raw: &serde_json::Value,
    tenant_id: uuid::Uuid,
    instance_id: i32,
) -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)> {
    let (topic, payload) = match event {
        "messages.upsert" => (
            "whatsapp.message.received",
            build_message_payload(raw, instance_id),
        ),
        "connection.update" => (
            "whatsapp.connection.updated",
            build_connection_payload(raw, instance_id),
        ),
        _ => return None,
    };
    Some((
        topic,
        contracts::TenantEnvelope::novo(tenant_id, topic.to_string(), payload),
    ))
}

fn build_message_payload(raw: &serde_json::Value, instance_id: i32) -> serde_json::Value {
    serde_json::json!({
        "instance_id": instance_id,
        "provider": "evolution",
        "raw_event": raw
    })
}

fn build_connection_payload(raw: &serde_json::Value, instance_id: i32) -> serde_json::Value {
    let state = raw
        .get("data")
        .and_then(|d| d.get("state").or_else(|| d.get("status")))
        .and_then(|s| s.as_str())
        .unwrap_or("unknown");

    let normalized_state = match state {
        "open" | "connected" => "connected",
        "close" | "disconnected" => "disconnected",
        "connecting" => "connecting",
        _ => "unknown",
    };

    serde_json::json!({
        "instance_id": instance_id,
        "provider": "evolution",
        "state": normalized_state,
        "raw_event": raw
    })
}
