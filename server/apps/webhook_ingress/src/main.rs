use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Router,
};
use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use transport::bus;

pub trait WebhookNormalizer: Send + Sync {
    fn provider_name(&self) -> &'static str;
    fn normalize(
        &self,
        event: &str,
        raw: &serde_json::Value,
        tenant_id: uuid::Uuid,
        instance_id: i32,
    ) -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)>;
}

#[derive(Clone)]
struct AppState {
    redis: redis::aio::ConnectionManager,
    normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>>,
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
        env::var("REDIS_BUS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());

    let client = redis::Client::open(redis_url)?;
    let redis = redis::aio::ConnectionManager::new(client).await?;

    let mut normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>> = HashMap::new();
    let evo_norm = Arc::new(EvolutionNormalizer);
    normalizers.insert(evo_norm.provider_name(), evo_norm);

    let state = AppState { redis, normalizers };

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

    let normalizado = if let Some(normalizer) = state.normalizers.get(params.provider.as_str()) {
        normalizer.normalize(event_type, &raw, params.tenant_id, params.instance_id)
    } else {
        tracing::warn!(provider = %params.provider, "Provedor desconhecido no path do webhook");
        None
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

fn canonical_event(raw: &str) -> Option<&'static str> {
    match raw {
        "MESSAGE" | "messages.upsert" | "Message" | "MESSAGES_UPSERT" | "MESSAGE_UPSERT" => {
            Some("MESSAGE")
        }
        "CONNECTION" | "connection.update" | "Connection" | "CONNECTION_UPDATE" | "CONNECTED"
        | "DISCONNECTED" | "LOGGEDOUT" | "LOGGED_OUT" | "LOGOUT" => Some("CONNECTION"),
        "MESSAGE_UPDATE" | "messages.update" | "MESSAGE_UPDATE_RAW" => Some("MESSAGE_UPDATE"),
        "PRESENCE" | "presence.update" | "Presence" | "PRESENCE_UPDATE" => Some("PRESENCE"),
        "CONTACTS" | "contacts.update" | "Contacts" | "CONTACTS_UPDATE" => Some("CONTACTS"),
        "QRCODE" | "qrcode.updated" | "QRCode" | "QRCODE_UPDATED" => Some("QRCODE"),
        _ => {
            let normalized = raw.to_uppercase().replace('.', "_");
            let normalized_singular = if normalized.ends_with('S') {
                normalized[..normalized.len() - 1].to_string()
            } else {
                normalized.clone()
            };

            match normalized.as_str() {
                "MESSAGE" | "MESSAGES_UPSERT" | "MESSAGE_UPSERT" => Some("MESSAGE"),
                "CONNECTION" | "CONNECTION_UPDATE" | "CONNECTED" | "DISCONNECTED" | "LOGGEDOUT"
                | "LOGGED_OUT" | "LOGOUT" => Some("CONNECTION"),
                "MESSAGE_UPDATE" | "MESSAGES_UPDATE" => Some("MESSAGE_UPDATE"),
                "PRESENCE" | "PRESENCE_UPDATE" => Some("PRESENCE"),
                "CONTACTS" | "CONTACTS_UPDATE" => Some("CONTACTS"),
                "QRCODE" | "QRCODE_UPDATED" => Some("QRCODE"),
                _ => match normalized_singular.as_str() {
                    "MESSAGE" => Some("MESSAGE"),
                    "CONNECTION" => Some("CONNECTION"),
                    "MESSAGE_UPDATE" => Some("MESSAGE_UPDATE"),
                    "PRESENCE" => Some("PRESENCE"),
                    "CONTACTS" => Some("CONTACTS"),
                    "QRCODE" => Some("QRCODE"),
                    _ => None,
                },
            }
        }
    }
}

fn translate_go_payload(payload: &serde_json::Value) -> serde_json::Value {
    let Some(data) = payload.get("data").and_then(|d| d.as_object()) else {
        return payload.clone();
    };
    let Some(info) = data.get("Info").and_then(|i| i.as_object()) else {
        return payload.clone();
    };

    let chat = info.get("Chat").and_then(|c| c.as_str()).unwrap_or("");
    let sender = info.get("Sender").and_then(|s| s.as_str()).unwrap_or("");
    let alt = info
        .get("SenderAlt")
        .or_else(|| info.get("RecipientAlt"))
        .and_then(|a| a.as_str())
        .unwrap_or("");

    let ts_raw = info.get("Timestamp");
    let ts_val = if let Some(ts_str) = ts_raw.and_then(|t| t.as_str()) {
        if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(ts_str) {
            serde_json::json!(dt.timestamp())
        } else {
            ts_raw.cloned().unwrap_or(serde_json::Value::Null)
        }
    } else {
        ts_raw.cloned().unwrap_or(serde_json::Value::Null)
    };

    let go_message = data.get("Message").unwrap_or(&serde_json::Value::Null);
    let media_type = info.get("MediaType").and_then(|m| m.as_str()).unwrap_or("");

    let mut message_out = go_message.clone();
    let mut message_type_out = serde_json::Value::Null;

    if !media_type.is_empty() {
        let sub_key = format!("{}Message", media_type);
        if let Some(sub_val) = go_message.get(&sub_key).and_then(|s| s.as_object()) {
            let mut sub = sub_val.clone();

            if let Some(url_val) = sub.get("URL") {
                if !sub.contains_key("url") {
                    sub.insert("url".to_string(), url_val.clone());
                }
            }
            if let Some(sha_val) = sub.get("fileSHA256") {
                if !sub.contains_key("fileSha256") {
                    sub.insert("fileSha256".to_string(), sha_val.clone());
                }
            }
            if let Some(enc_sha_val) = sub.get("fileEncSHA256") {
                if !sub.contains_key("fileEncSha256") {
                    sub.insert("fileEncSha256".to_string(), enc_sha_val.clone());
                }
            }

            if let Some(top_b64) = go_message.get("base64") {
                if !sub.contains_key("base64") {
                    sub.insert("base64".to_string(), top_b64.clone());
                }
            }

            message_out = serde_json::json!({
                &sub_key: sub
            });
            message_type_out = serde_json::json!(sub_key);
        }
    }

    serde_json::json!({
        "event": payload.get("event"),
        "instance": payload.get("instanceName").or_else(|| payload.get("instance")),
        "sender": if !sender.is_empty() { sender } else { chat },
        "apikey": payload.get("instanceToken").or_else(|| payload.get("apikey")),
        "data": {
            "key": {
                "remoteJid": chat,
                "remoteJidAlt": alt,
                "fromMe": info.get("IsFromMe").and_then(|f| f.as_bool()).unwrap_or(false),
                "id": info.get("ID"),
                "addressingMode": info.get("AddressingMode"),
            },
            "pushName": info.get("PushName"),
            "message": message_out,
            "messageType": message_type_out,
            "messageTimestamp": ts_val,
            "instanceId": payload.get("instanceId"),
            "isGroup": info.get("IsGroup").and_then(|g| g.as_bool()).unwrap_or(false),
            "mediaType": media_type,
        }
    })
}

struct EvolutionNormalizer;

impl WebhookNormalizer for EvolutionNormalizer {
    fn provider_name(&self) -> &'static str {
        "evolution"
    }

    fn normalize(
        &self,
        event: &str,
        raw: &serde_json::Value,
        tenant_id: uuid::Uuid,
        instance_id: i32,
    ) -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)> {
        let canonical = canonical_event(event)?;

        let translated = if raw.get("data").and_then(|d| d.get("Info")).is_some() {
            translate_go_payload(raw)
        } else {
            raw.clone()
        };

        let (topic, payload) = match canonical {
            "MESSAGE" => (
                "whatsapp.message.received",
                build_message_payload(&translated, instance_id),
            ),
            "CONNECTION" => (
                "whatsapp.connection.updated",
                build_connection_payload(&translated, instance_id),
            ),
            "MESSAGE_UPDATE" => (
                "whatsapp.message.status",
                build_message_payload(&translated, instance_id),
            ),
            "PRESENCE" => (
                "whatsapp.presence.updated",
                build_message_payload(&translated, instance_id),
            ),
            "CONTACTS" => (
                "whatsapp.contact.updated",
                build_message_payload(&translated, instance_id),
            ),
            _ => return None,
        };

        Some((
            topic,
            contracts::TenantEnvelope::novo(tenant_id, topic.to_string(), payload),
        ))
    }
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
        "close" | "disconnected" | "loggedOut" => "disconnected",
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

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use serde_json::json;
    use tower::ServiceExt;

    async fn fake_bus(porta: u16) -> redis::aio::ConnectionManager {
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
                        let req = String::from_utf8_lossy(&buf[..n]);
                        for parte in req.split('*') {
                            if parte.is_empty() {
                                continue;
                            }
                            if parte.to_uppercase().contains("PING") {
                                let _ = socket.write_all(b"+PONG\r\n").await;
                            } else {
                                let _ = socket.write_all(b"+OK\r\n").await;
                            }
                        }
                    }
                });
            }
        });
        let client = redis::Client::open(format!("redis://127.0.0.1:{porta}")).unwrap();
        redis::aio::ConnectionManager::new(client).await.unwrap()
    }

    async fn setup_test_app() -> Router {
        let redis = fake_bus(29257).await;
        let mut normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>> = HashMap::new();
        let evo_norm = Arc::new(EvolutionNormalizer);
        normalizers.insert(evo_norm.provider_name(), evo_norm);

        let state = AppState { redis, normalizers };

        Router::new()
            .route(
                "/webhook/{provider}/{tenant_id}/{instance_id}",
                post(handle_webhook),
            )
            .with_state(state)
    }

    #[tokio::test]
    async fn test_webhook_invalid_json() {
        let app = setup_test_app().await;

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/evolution/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from("{invalid json"))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn test_webhook_unknown_provider() {
        let app = setup_test_app().await;

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/unknown_prov/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from(
                        json!({ "event": "messages.upsert" }).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn test_webhook_evolution_message_received() {
        let app = setup_test_app().await;

        let payload = json!({
            "event": "messages.upsert",
            "data": {
                "message": {
                    "conversation": "Olá mundo"
                }
            }
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/evolution/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from(payload.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn test_webhook_evolution_go_message_received() {
        let app = setup_test_app().await;

        let payload = json!({
            "event": "Message",
            "instanceName": "atendimento",
            "instanceToken": "token-123",
            "instanceId": "00000000-0000-0000-0000-000000000001",
            "data": {
                "Info": {
                    "Chat": "5511999998888@s.whatsapp.net",
                    "Sender": "5511999998888@s.whatsapp.net",
                    "ID": "3EB0123456789",
                    "IsFromMe": false,
                    "IsGroup": false,
                    "PushName": "João",
                    "Timestamp": "2026-06-25T19:13:57-03:00",
                    "Type": "text",
                    "MediaType": ""
                },
                "Message": {
                    "conversation": "Olá de volta"
                }
            }
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/evolution/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from(payload.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn test_webhook_evolution_connection_updated() {
        let app = setup_test_app().await;

        let payload = json!({
            "event": "connection.update",
            "data": {
                "state": "open"
            }
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/evolution/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from(payload.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }

    #[tokio::test]
    async fn test_webhook_evolution_ignored_event() {
        let app = setup_test_app().await;

        let payload = json!({
            "event": "ignored.event",
            "data": {}
        });

        let response = app
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/webhook/evolution/00000000-0000-0000-0000-000000000001/42")
                    .header("content-type", "application/json")
                    .body(Body::from(payload.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }
}
