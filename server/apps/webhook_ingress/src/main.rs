use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Router,
};
use secrecy::{ExposeSecret, SecretString};
use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::Duration;
use transport::bus;

/// Mascara um telefone para auditoria/log, preservando apenas os 4 últimos dígitos.
/// Ex.: `5511999998888` → `*********8888`. Evita expor PII completa na trilha.
fn mascarar_telefone(phone: &str) -> String {
    let digitos: Vec<char> = phone.chars().collect();
    if digitos.len() <= 4 {
        return "*".repeat(digitos.len());
    }
    let visiveis: String = digitos[digitos.len() - 4..].iter().collect();
    format!("{}{}", "*".repeat(digitos.len() - 4), visiveis)
}

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
    #[allow(dead_code)]
    audit_logger: observability::AuditLogger,
    pg_client: Arc<transport::MuxClient>,
    /// N7.3: cliente RPC do `data_redis`, para o rate-limit unificado (mesma fonte
    /// usada pelo `runtime_api`, via `RegisterRateLimitAttempt`).
    redis_client: Arc<transport::MuxClient>,
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

    let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await?);
    let redis_client = Arc::new(transport::conectar_cliente("data_redis").await?);
    let audit_logger = observability::AuditLogger::new_with_redis(redis.clone(), "webhook_ingress");
    let state = AppState {
        redis,
        normalizers,
        audit_logger,
        pg_client,
        redis_client,
    };

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

fn extrair_sender(event_type: &str, raw: &serde_json::Value) -> Option<String> {
    let jid = match event_type {
        "messages.upsert" => raw
            .get("data")
            .and_then(|d| d.get("key"))
            .and_then(|k| k.get("remoteJid"))
            .and_then(|j| j.as_str()),
        "Message" => raw
            .get("data")
            .and_then(|d| d.get("Info"))
            .and_then(|i| i.get("Sender"))
            .and_then(|s| s.as_str()),
        _ => None,
    };

    jid.map(|s| {
        s.split('@')
            .next()
            .unwrap_or(s)
            .split('-')
            .next()
            .unwrap_or(s)
            .to_string()
    })
}

fn extrair_message_id(event_type: &str, raw: &serde_json::Value) -> Option<String> {
    match event_type {
        "messages.upsert" => raw
            .get("data")
            .and_then(|d| d.get("key"))
            .and_then(|k| k.get("id"))
            .and_then(|id| id.as_str())
            .map(|s| s.to_string()),
        "Message" => raw
            .get("data")
            .and_then(|d| d.get("Info"))
            .and_then(|i| i.get("ID"))
            .and_then(|id| id.as_str())
            .map(|s| s.to_string()),
        _ => None,
    }
}

/// N4.2 — consulta `CheckQuota` no data_postgres só para ler `inadimplente`
/// (o recurso "instancias" é irrelevante aqui, descartado). Fail-open: qualquer
/// falha na checagem não bloqueia a ingestão.
async fn verificar_bloqueio_inadimplencia(
    pg_client: &transport::MuxClient,
    tenant_id: uuid::Uuid,
) -> bool {
    let req_payload = serde_json::json!({ "recurso": "instancias" });
    let req_envelope = contracts::Envelope {
        kind: contracts::MessageKind::Request as i32,
        method: "CheckQuota".to_string(),
        tenant_id: tenant_id.to_string(),
        payload: serde_json::to_vec(&req_payload).unwrap_or_default(),
        ..Default::default()
    };
    let resp = match pg_client.call(req_envelope, Duration::from_secs(5)).await {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!(
                "falha ao verificar quota/inadimplência (fail-open): {:?}",
                e
            );
            return false;
        }
    };
    if resp.kind == contracts::MessageKind::Error as i32 {
        tracing::warn!("CheckQuota retornou erro (fail-open)");
        return false;
    }
    let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
    body.get("inadimplente")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// N7.3 — contadores de rate-limit unificados: chama `RegisterRateLimitAttempt`
/// no `data_redis` (mesma fonte usada pelo `runtime_api`), em vez de manter um
/// contador próprio na conexão de bus do webhook (independente da política de
/// eviction do bus). Mesma chave/namespace (`recurso`+`id`) do contador antigo —
/// upgrade transparente, sem descontinuidade na janela em curso.
async fn registrar_rate_limit_unificado(
    redis_client: &transport::MuxClient,
    recurso: &str,
    id: &str,
    window_s: u64,
) -> Result<u64, error_core::AppError> {
    let req_payload = serde_json::json!({ "recurso": recurso, "id": id, "window_s": window_s });
    let req_envelope = contracts::Envelope {
        kind: contracts::MessageKind::Request as i32,
        method: "RegisterRateLimitAttempt".to_string(),
        payload: serde_json::to_vec(&req_payload).unwrap_or_default(),
        ..Default::default()
    };
    let resp = redis_client
        .call(req_envelope, Duration::from_secs(3))
        .await
        .map_err(|e| error_core::AppError::Internal(format!("Falha ao chamar data_redis: {e}")))?;

    if resp.kind == contracts::MessageKind::Error as i32 {
        let msg = resp
            .error
            .map(|err| err.message)
            .unwrap_or_else(|| "Erro desconhecido".to_string());
        return Err(error_core::AppError::Internal(msg));
    }

    let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap_or_default();
    Ok(body.get("attempts").and_then(|v| v.as_u64()).unwrap_or(0))
}

#[tracing::instrument(
    skip(state, headers, body),
    fields(
        provider    = %params.provider,
        tenant_id   = %params.tenant_id,
        instance_id = params.instance_id,
        event_type  = tracing::field::Empty
    )
)]
async fn handle_webhook(
    Path(params): Path<WebhookPath>,
    headers: axum::http::HeaderMap,
    State(mut state): State<AppState>,
    body: Bytes,
) -> Result<impl IntoResponse, StatusCode> {
    let raw: serde_json::Value = serde_json::from_slice(&body).map_err(|e| {
        tracing::error!("Falha ao parsear body do webhook: {:?}", e);
        StatusCode::BAD_REQUEST
    })?;

    let event_type = raw.get("event").and_then(|e| e.as_str()).unwrap_or("");
    tracing::Span::current().record("event_type", event_type);

    // 1. Extração do Token
    let token = headers
        .get("apikey")
        .or_else(|| headers.get("x-api-key"))
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string())
        .or_else(|| {
            raw.get("instanceToken")
                .or_else(|| raw.get("apikey"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
        });

    // Carrega o token em SecretString para impedir vazamento acidental em log/Debug.
    let token: SecretString = match token {
        Some(t) => SecretString::from(t),
        None => {
            state.audit_logger.warn(
                params.tenant_id,
                "webhook.rejected",
                "Token de autenticação do webhook ausente",
                serde_json::json!({
                    "provider": params.provider,
                    "instance_id": params.instance_id,
                    "reason": "missing_token"
                }),
                None,
                None,
                None,
            );
            return Err(StatusCode::UNAUTHORIZED);
        }
    };

    // 2. Chamada RPC VerifyWhatsappInstanceToken
    let req_payload = serde_json::json!({
        "id": params.instance_id,
        "token": token.expose_secret()
    });
    let req_envelope = contracts::Envelope {
        kind: contracts::MessageKind::Request as i32,
        method: "VerifyWhatsappInstanceToken".to_string(),
        tenant_id: params.tenant_id.to_string(),
        payload: serde_json::to_vec(&req_payload).unwrap(),
        ..Default::default()
    };
    let resp = state
        .pg_client
        .call(req_envelope, Duration::from_secs(5))
        .await
        .map_err(|e| {
            tracing::error!("Falha na chamada RPC VerifyWhatsappInstanceToken: {:?}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if resp.kind == contracts::MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro interno");
        tracing::error!("Erro RPC ao verificar token: {}", err_msg);
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let resp_payload: serde_json::Value =
        serde_json::from_slice(&resp.payload).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let is_valid = resp_payload
        .get("valid")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !is_valid {
        state.audit_logger.warn(
            params.tenant_id,
            "webhook.rejected",
            "Token de autenticação do webhook inválido",
            serde_json::json!({
                "provider": params.provider,
                "instance_id": params.instance_id,
                "reason": "invalid_token"
            }),
            None,
            None,
            None,
        );
        return Err(StatusCode::UNAUTHORIZED);
    }

    // 2c. Rate limiting amplo por instância/tenant (N4.4). N7.3: contador
    // unificado via RPC no data_redis (mesma fonte do runtime_api), não mais um
    // contador próprio na conexão de bus deste serviço. Fail-open: erro na
    // checagem não derruba a ingestão (mesmo espírito do QuotaGuard).
    {
        let max = env::var("WEBHOOK_RATE_LIMIT_MAX")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(120);
        let window_s = env::var("WEBHOOK_RATE_LIMIT_WINDOW_S")
            .ok()
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(60);
        let id = format!("{}:{}", params.tenant_id, params.instance_id);
        match registrar_rate_limit_unificado(&state.redis_client, "webhook", &id, window_s).await {
            Ok(total) if total > max => {
                state.audit_logger.warn(
                    params.tenant_id,
                    "webhook.rejected",
                    "Rate limit do webhook excedido",
                    serde_json::json!({
                        "provider": params.provider,
                        "instance_id": params.instance_id,
                        "reason": "rate_limited",
                        "attempts": total,
                        "max": max
                    }),
                    None,
                    None,
                    None,
                );
                return Err(StatusCode::TOO_MANY_REQUESTS);
            }
            Ok(_) => {}
            Err(e) => {
                tracing::warn!(
                    "falha ao registrar rate limit do webhook (fail-open): {:?}",
                    e
                );
            }
        }
    }

    let normalizado = if let Some(normalizer) = state.normalizers.get(params.provider.as_str()) {
        normalizer.normalize(event_type, &raw, params.tenant_id, params.instance_id)
    } else {
        tracing::warn!(provider = %params.provider, "Provedor desconhecido no path do webhook");
        None
    };

    if let Some((topic, envelope)) = normalizado {
        let is_msg_event = topic == "whatsapp.message.received" || topic == "message.received";

        // 2b. QuotaGuard — bloqueio por inadimplência (N4.2). Log-only por padrão
        // (SMARTCORE_QUOTA_ENFORCE=false); vira 402 real quando a flag é true.
        if is_msg_event {
            let inadimplente =
                verificar_bloqueio_inadimplencia(&state.pg_client, params.tenant_id).await;
            if inadimplente {
                let enforce = env::var("SMARTCORE_QUOTA_ENFORCE")
                    .map(|v| v.eq_ignore_ascii_case("true"))
                    .unwrap_or(false);
                if enforce {
                    // Rejeição real: evento pontual na trilha de auditoria.
                    state.audit_logger.warn(
                        params.tenant_id,
                        "webhook.rejected",
                        "Ingestão rejeitada: assinatura inadimplente",
                        serde_json::json!({
                            "provider": params.provider,
                            "instance_id": params.instance_id,
                            "reason": "inadimplencia",
                            "enforced": true
                        }),
                        None,
                        None,
                        None,
                    );
                    return Err(StatusCode::PAYMENT_REQUIRED);
                }
                // Log-only: não auditar por-mensagem (inundaria a trilha para um
                // tenant inadimplente com tráfego). Apenas sinaliza no log; as
                // métricas de uso captam o volume.
                tracing::warn!(
                    tenant_id = %params.tenant_id,
                    instance_id = params.instance_id,
                    "assinatura inadimplente detectada (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
                );
            }
        }

        // 3. Verificação de Whitelist para mensagens recebidas
        if is_msg_event {
            if let Some(phone) = extrair_sender(event_type, &raw) {
                let wl_payload = serde_json::json!({
                    "phone": phone
                });
                let wl_envelope = contracts::Envelope {
                    kind: contracts::MessageKind::Request as i32,
                    method: "IsPhoneWhitelisted".to_string(),
                    tenant_id: params.tenant_id.to_string(),
                    payload: serde_json::to_vec(&wl_payload).unwrap(),
                    ..Default::default()
                };

                let wl_resp = state
                    .pg_client
                    .call(wl_envelope, Duration::from_secs(5))
                    .await
                    .map_err(|e| {
                        tracing::error!("Falha RPC IsPhoneWhitelisted: {:?}", e);
                        StatusCode::INTERNAL_SERVER_ERROR
                    })?;

                if wl_resp.kind == contracts::MessageKind::Error as i32 {
                    return Err(StatusCode::INTERNAL_SERVER_ERROR);
                }

                let wl_body: serde_json::Value = serde_json::from_slice(&wl_resp.payload)
                    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

                let whitelisted = wl_body
                    .get("whitelisted")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                if !whitelisted {
                    state.audit_logger.warn(
                        params.tenant_id,
                        "webhook.rejected",
                        "Mensagem rejeitada: remetente não está na whitelist",
                        serde_json::json!({
                            "provider": params.provider,
                            "instance_id": params.instance_id,
                            "phone": mascarar_telefone(&phone),
                            "reason": "not_whitelisted"
                        }),
                        None,
                        None,
                        None,
                    );
                    return Err(StatusCode::FORBIDDEN);
                }
            }
        }

        // 4. Verificação de Idempotência
        if is_msg_event {
            if let Some(msg_id) = extrair_message_id(event_type, &raw) {
                let key = format!("webhook:idempotency:{}:{}", params.tenant_id, msg_id);
                let set_res: Result<bool, _> = redis::cmd("SET")
                    .arg(&key)
                    .arg("1")
                    .arg("NX")
                    .arg("EX")
                    .arg(86400)
                    .query_async(&mut state.redis)
                    .await;

                match set_res {
                    Ok(inserted) => {
                        if !inserted {
                            state.audit_logger.info(
                                params.tenant_id,
                                "webhook.duplicated",
                                "Webhook duplicado rejeitado",
                                serde_json::json!({
                                    "provider": params.provider,
                                    "instance_id": params.instance_id,
                                    "message_id": msg_id
                                }),
                                None,
                                None,
                                None,
                            );
                            return Ok(StatusCode::ACCEPTED);
                        }
                    }
                    Err(e) => {
                        tracing::error!("Erro de Redis na idempotência: {:?}", e);
                    }
                }
            }
        }

        // 5. Publicação no barramento.
        // Semeia o traceparent W3C a partir do span atual para fechar a cadeia de trace
        // distribuído webhook → bus → worker → RPC data_*.
        let mut carrier = std::collections::HashMap::new();
        observability::injetar_contexto_atual(&mut carrier);
        let envelope = if let Some(tp) = carrier.get("traceparent") {
            envelope.com_traceparent(tp.clone())
        } else {
            envelope
        };

        bus::publicar_evento(&mut state.redis, &envelope)
            .await
            .map_err(|e| {
                tracing::error!("Falha ao publicar evento no barramento: {:?}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        tracing::info!(topico = topic, "Evento normalizado publicado no barramento");

        if is_msg_event {
            observability::usage_metrics::registrar_mensagem(
                &params.tenant_id.to_string(),
                observability::usage_metrics::DirecaoMensagem::Recebida,
            );
        }
    } else {
        tracing::debug!(
            event = event_type,
            "Evento ignorado (não mapeado para este provedor)"
        );
    }

    state.audit_logger.info(
        params.tenant_id,
        "webhook.received",
        "Webhook recebido e processado com sucesso",
        serde_json::json!({
            "provider": params.provider,
            "instance_id": params.instance_id,
            "event_type": event_type
        }),
        None,
        None,
        None,
    );

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
        // Inicializa o gRPC mock local do data_postgres
        let pg_addr = "tcp://127.0.0.1:29259";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = transport::runtime::Endpoint::parse(pg_addr).unwrap();
        let pg_server = transport::runtime::Server::new(pg_endpoint, "flatbuffers")
            .route("VerifyWhatsappInstanceToken", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "valid": true,
                        "phone_number": "5511999998888",
                    });
                    contracts::Envelope {
                        kind: contracts::MessageKind::Reply as i32,
                        method: "VerifyWhatsappInstanceTokenReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("IsPhoneWhitelisted", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "whitelisted": true,
                    });
                    contracts::Envelope {
                        kind: contracts::MessageKind::Reply as i32,
                        method: "IsPhoneWhitelistedReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });

        // Roda o servidor em background
        tokio::spawn(async move {
            let _ = pg_server.run().await;
        });

        // N7.3: mock do data_redis para o rate-limit unificado (RegisterRateLimitAttempt).
        let redis_rpc_addr = "tcp://127.0.0.1:29261";
        std::env::set_var("SMARTCORE_DATA_REDIS_ENDPOINT", redis_rpc_addr);
        let redis_rpc_endpoint = transport::runtime::Endpoint::parse(redis_rpc_addr).unwrap();
        let redis_rpc_server = transport::runtime::Server::new(redis_rpc_endpoint, "flatbuffers")
            .route("RegisterRateLimitAttempt", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "attempts": 1 });
                    contracts::Envelope {
                        kind: contracts::MessageKind::Reply as i32,
                        method: "RegisterRateLimitAttemptReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        tokio::spawn(async move {
            let _ = redis_rpc_server.run().await;
        });

        // Espera um pouco para o servidor iniciar
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let redis_client = Arc::new(transport::conectar_cliente("data_redis").await.unwrap());

        let redis = fake_bus(29257).await;
        let mut normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>> = HashMap::new();
        let evo_norm = Arc::new(EvolutionNormalizer);
        normalizers.insert(evo_norm.provider_name(), evo_norm);

        let audit_logger = observability::AuditLogger::new_dummy("webhook_ingress");
        let state = AppState {
            redis,
            normalizers,
            audit_logger,
            pg_client,
            redis_client,
        };

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
                    .header("apikey", "token-123")
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
                    .header("apikey", "token-123")
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
                    .header("apikey", "token-123")
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
                    .header("apikey", "token-123")
                    .body(Body::from(payload.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::ACCEPTED);
    }
}
