//! Entrada da WhatsApp Cloud API (Meta).
//!
//! Diferenças para a Evolution, e por que esta rota é separada:
//! - **um app da Meta por ambiente**, não um webhook por instância: o caminho
//!   (`/webhook/meta/{app}`) não traz tenant nem instância. A conexão é achada
//!   pelo `phone_number_id` de cada evento (`ResolverCanalPorIdExterno`);
//! - **autenticação por assinatura**: `X-Hub-Signature-256` = HMAC-SHA256 do
//!   corpo com o segredo do app (`META_APP_SECRET`). Sem segredo configurado a
//!   rota responde 503 — nunca aceita evento sem conferir;
//! - **aperto de mão por GET** (`hub.challenge`), com o token de verificação do
//!   ambiente (`META_WEBHOOK_VERIFY_TOKEN`);
//! - formato próprio do corpo, traduzido aqui para o formato canônico do
//!   barramento antes do pipeline comum (`processar_evento`).

use axum::{
    body::Bytes,
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::collections::HashMap;
use std::time::Duration;

use crate::{processar_evento, AppState, WebhookNormalizer, WebhookPath};

/// Chave do provedor (a mesma de `infrastructure_meta_cloud::PROVIDER` e de
/// `whatsapp_instance.provider`).
pub const PROVIDER: &str = "meta_cloud";

/// Evento interno de status traduzido de `statuses[]`.
const EVENTO_STATUS: &str = "meta.status";

fn variavel(nome: &str) -> Option<String> {
    std::env::var(nome)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// Confere `sha256=<hex>` contra o HMAC-SHA256 do corpo. `verify_slice` compara
/// em tempo constante.
pub fn assinatura_confere(segredo: &[u8], corpo: &[u8], cabecalho: Option<&str>) -> bool {
    let Some(hex_recebido) = cabecalho.and_then(|c| c.trim().strip_prefix("sha256=")) else {
        return false;
    };
    let Ok(recebido) = hex::decode(hex_recebido) else {
        return false;
    };
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(segredo) else {
        return false;
    };
    mac.update(corpo);
    mac.verify_slice(&recebido).is_ok()
}

/// O segmento `{app}` serve para distinguir apps quando houver mais de um.
/// Com `META_APP_ID` configurado, outro valor é 404.
fn app_confere(app: &str) -> bool {
    match variavel("META_APP_ID") {
        Some(esperado) => esperado == app,
        None => true,
    }
}

/// GET do aperto de mão: devolve `hub.challenge` quando o token confere.
pub async fn handle_verificacao(
    Path(app): Path<String>,
    Query(q): Query<HashMap<String, String>>,
) -> Response {
    if !app_confere(&app) {
        return StatusCode::NOT_FOUND.into_response();
    }
    let Some(esperado) = variavel("META_WEBHOOK_VERIFY_TOKEN") else {
        tracing::error!("META_WEBHOOK_VERIFY_TOKEN ausente: aperto de mão da Meta recusado");
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    resposta_da_verificacao(&esperado, &q).into_response()
}

/// Parte pura de [`handle_verificacao`].
fn resposta_da_verificacao(esperado: &str, q: &HashMap<String, String>) -> (StatusCode, String) {
    use subtle::ConstantTimeEq;
    let modo = q.get("hub.mode").map(String::as_str);
    let token = q
        .get("hub.verify_token")
        .map(String::as_bytes)
        .unwrap_or_default();
    let confere = token.len() == esperado.len() && bool::from(token.ct_eq(esperado.as_bytes()));
    match (modo, confere, q.get("hub.challenge")) {
        (Some("subscribe"), true, Some(desafio)) => (StatusCode::OK, desafio.clone()),
        _ => (StatusCode::FORBIDDEN, String::new()),
    }
}

/// Um evento já separado por número: a mensagem (ou o status) no formato
/// canônico e o `phone_number_id` que diz de qual conexão ele é.
#[derive(Debug, PartialEq)]
pub struct EventoMeta {
    pub phone_number_id: String,
    pub evento: &'static str,
    pub raw: serde_json::Value,
}

/// Separa o corpo da Meta em eventos canônicos. Um POST pode trazer vários
/// números (`entry[]`) e várias mensagens por número.
pub fn extrair_eventos(corpo: &serde_json::Value) -> Vec<EventoMeta> {
    let mut saida = Vec::new();
    let entradas = corpo.get("entry").and_then(|e| e.as_array());
    for entrada in entradas.into_iter().flatten() {
        let mudancas = entrada.get("changes").and_then(|c| c.as_array());
        for mudanca in mudancas.into_iter().flatten() {
            if mudanca.get("field").and_then(|f| f.as_str()) != Some("messages") {
                continue;
            }
            let Some(valor) = mudanca.get("value") else {
                continue;
            };
            let Some(phone_number_id) = valor
                .pointer("/metadata/phone_number_id")
                .and_then(|v| v.as_str())
            else {
                continue;
            };
            let nomes: HashMap<&str, &str> = valor
                .get("contacts")
                .and_then(|c| c.as_array())
                .into_iter()
                .flatten()
                .filter_map(|c| {
                    Some((
                        c.get("wa_id")?.as_str()?,
                        c.pointer("/profile/name")?.as_str()?,
                    ))
                })
                .collect();
            for msg in valor
                .get("messages")
                .and_then(|m| m.as_array())
                .into_iter()
                .flatten()
            {
                if let Some(raw) = traduzir_mensagem(msg, &nomes) {
                    saida.push(EventoMeta {
                        phone_number_id: phone_number_id.to_string(),
                        evento: "messages.upsert",
                        raw,
                    });
                }
            }
            for st in valor
                .get("statuses")
                .and_then(|s| s.as_array())
                .into_iter()
                .flatten()
            {
                if let Some(raw) = traduzir_status(st) {
                    saida.push(EventoMeta {
                        phone_number_id: phone_number_id.to_string(),
                        evento: EVENTO_STATUS,
                        raw,
                    });
                }
            }
        }
    }
    saida
}

/// Uma mensagem da Cloud API no formato canônico do barramento (o mesmo que
/// a Evolution produz e o `NormalizedMessage::parse` do worker lê).
///
/// Mídia: o sub-objeto leva o `id` da mídia na Meta. O download pela Cloud API
/// ainda não existe (o adaptador não declara `download_midia`), então a
/// mensagem chega com tipo e legenda, sem o arquivo.
pub fn traduzir_mensagem(
    msg: &serde_json::Value,
    nomes: &HashMap<&str, &str>,
) -> Option<serde_json::Value> {
    let de = msg.get("from")?.as_str()?;
    let id = msg.get("id")?.as_str()?;
    let tipo = msg.get("type").and_then(|t| t.as_str()).unwrap_or("");
    let ts = msg.get("timestamp").and_then(|t| {
        t.as_str()
            .and_then(|s| s.parse::<i64>().ok())
            .or(t.as_i64())
    });
    let resposta_a = msg.pointer("/context/id").and_then(|v| v.as_str());
    let contexto = resposta_a.map(|r| serde_json::json!({ "stanzaId": r }));

    let midia = |chave: &str, sub: &serde_json::Value| {
        let mut m = serde_json::json!({
            "id": sub.get("id"),
            "mimetype": sub.get("mime_type"),
            "sha256": sub.get("sha256"),
        });
        if let Some(c) = sub.get("caption") {
            m["caption"] = c.clone();
        }
        if let Some(f) = sub.get("filename") {
            m["fileName"] = f.clone();
        }
        if let Some(ctx) = &contexto {
            m["contextInfo"] = ctx.clone();
        }
        serde_json::json!({ chave: m })
    };

    let mensagem = match tipo {
        "text" => {
            let corpo = msg
                .pointer("/text/body")
                .and_then(|b| b.as_str())
                .unwrap_or("");
            match &contexto {
                Some(ctx) => serde_json::json!({
                    "extendedTextMessage": { "text": corpo, "contextInfo": ctx }
                }),
                None => serde_json::json!({ "conversation": corpo }),
            }
        }
        "image" => midia("imageMessage", msg.get("image")?),
        "audio" | "voice" => midia("audioMessage", msg.get(tipo)?),
        "video" => midia("videoMessage", msg.get("video")?),
        "document" => midia("documentMessage", msg.get("document")?),
        "sticker" => midia("stickerMessage", msg.get("sticker")?),
        "location" => serde_json::json!({
            "locationMessage": {
                "degreesLatitude": msg.pointer("/location/latitude"),
                "degreesLongitude": msg.pointer("/location/longitude"),
            }
        }),
        "contacts" => {
            let nome = msg
                .pointer("/contacts/0/name/formatted_name")
                .and_then(|n| n.as_str())
                .unwrap_or("");
            serde_json::json!({ "contactMessage": { "displayName": nome } })
        }
        "reaction" => serde_json::json!({
            "reactionMessage": {
                "text": msg.pointer("/reaction/emoji").and_then(|e| e.as_str()).unwrap_or(""),
                "key": { "id": msg.pointer("/reaction/message_id") },
            }
        }),
        // Resposta a botão/lista: o que importa para o atendimento é o texto
        // escolhido pela pessoa.
        "interactive" | "button" => {
            let texto = msg
                .pointer("/interactive/button_reply/title")
                .or_else(|| msg.pointer("/interactive/list_reply/title"))
                .or_else(|| msg.pointer("/button/text"))
                .and_then(|t| t.as_str())
                .unwrap_or("");
            serde_json::json!({ "conversation": texto })
        }
        // `unsupported`, `system` (troca de número), `order`, `request_welcome`…
        // não têm conteúdo que o atendimento interprete; publicar um objeto
        // vazio abriria conversa e faria o bot responder ao nada.
        outro => {
            tracing::info!(
                tipo = outro,
                "tipo de mensagem da Meta sem tradução; descartado"
            );
            return None;
        }
    };

    let mut data = serde_json::json!({
        "key": {
            "remoteJid": format!("{de}@s.whatsapp.net"),
            "fromMe": false,
            "id": id,
        },
        "pushName": nomes.get(de).copied().unwrap_or(""),
        "message": mensagem,
        "isGroup": false,
    });
    if let Some(ts) = ts {
        data["messageTimestamp"] = serde_json::json!(ts);
    }
    Some(serde_json::json!({ "event": "messages.upsert", "data": data }))
}

/// `statuses[]` no formato de status que o worker aplica. `sent` e `failed`
/// não mudam o ✓ do que já está gravado.
pub fn traduzir_status(st: &serde_json::Value) -> Option<serde_json::Value> {
    let id = st.get("id")?.as_str()?;
    let status = match st.get("status")?.as_str()? {
        "delivered" => "delivered",
        "read" => "read",
        _ => return None,
    };
    Some(serde_json::json!({
        "data": { "status": status, "key": { "id": id }, "ids": [id] }
    }))
}

/// Normalizador da Meta: recebe o evento JÁ traduzido por [`extrair_eventos`].
pub struct MetaNormalizer;

impl WebhookNormalizer for MetaNormalizer {
    fn provider_name(&self) -> &'static str {
        PROVIDER
    }

    fn aceita_rota_por_token(&self) -> bool {
        false
    }

    fn normalize(
        &self,
        event: &str,
        raw: &serde_json::Value,
        tenant_id: uuid::Uuid,
        instance_id: i32,
    ) -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)> {
        let topic = match event {
            "messages.upsert" => "whatsapp.message.received",
            EVENTO_STATUS => "whatsapp.message.status",
            _ => return None,
        };
        Some((
            topic,
            contracts::TenantEnvelope::novo(
                tenant_id,
                topic.to_string(),
                serde_json::json!({
                    "instance_id": instance_id,
                    "provider": PROVIDER,
                    "raw_event": raw,
                }),
            ),
        ))
    }
}

/// Acha a conexão (id e tenant) pelo `phone_number_id`.
async fn resolver_conexao(
    state: &AppState,
    phone_number_id: &str,
) -> Result<Option<(i32, uuid::Uuid)>, StatusCode> {
    let req = contracts::Envelope {
        kind: contracts::MessageKind::Request as i32,
        method: "ResolverCanalPorIdExterno".to_string(),
        payload: serde_json::to_vec(&serde_json::json!({
            "provider": PROVIDER,
            "id_externo": phone_number_id,
        }))
        .unwrap_or_default(),
        ..Default::default()
    };
    let resp = state
        .pg_client
        .call(req, Duration::from_secs(5))
        .await
        .map_err(|e| {
            tracing::error!("falha no RPC ResolverCanalPorIdExterno: {e:?}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    if resp.kind == contracts::MessageKind::Error as i32 {
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }
    let corpo: serde_json::Value =
        serde_json::from_slice(&resp.payload).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if corpo.get("encontrado").and_then(|v| v.as_bool()) != Some(true) {
        return Ok(None);
    }
    let id = corpo.get("id").and_then(|v| v.as_i64());
    let tenant = corpo
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| uuid::Uuid::parse_str(s).ok());
    Ok(id.zip(tenant).map(|(i, t)| (i as i32, t)))
}

/// POST dos eventos. Assinatura antes de tudo; depois cada evento segue o
/// pipeline comum com a conexão resolvida pelo número.
///
/// Falha transitória (RPC fora) em qualquer evento devolve 500 de propósito:
/// a Meta reentrega, e a idempotência pelo `wamid` impede duplicar o que já
/// entrou. Número sem conexão é descartado com aviso (200): reentregar não
/// faria a conexão aparecer.
pub async fn handle_webhook(
    Path(app): Path<String>,
    headers: HeaderMap,
    State(mut state): State<AppState>,
    body: Bytes,
) -> Response {
    if !app_confere(&app) {
        return StatusCode::NOT_FOUND.into_response();
    }
    let Some(segredo) = variavel("META_APP_SECRET") else {
        tracing::error!("META_APP_SECRET ausente: webhook da Meta recusado sem conferir");
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    let assinatura = headers
        .get("x-hub-signature-256")
        .and_then(|h| h.to_str().ok());
    if !assinatura_confere(segredo.as_bytes(), &body, assinatura) {
        tracing::warn!(app, "assinatura do webhook da Meta inválida");
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let Ok(corpo) = serde_json::from_slice::<serde_json::Value>(&body) else {
        return StatusCode::BAD_REQUEST.into_response();
    };

    let mut falhou = false;
    for ev in extrair_eventos(&corpo) {
        let conexao = match resolver_conexao(&state, &ev.phone_number_id).await {
            Ok(Some(c)) => c,
            Ok(None) => {
                tracing::warn!(
                    phone_number_id = %ev.phone_number_id,
                    "evento da Meta para número sem conexão ativa; descartado"
                );
                continue;
            }
            Err(_) => {
                falhou = true;
                continue;
            }
        };
        let params = WebhookPath {
            provider: PROVIDER.to_string(),
            tenant_id: conexao.1,
            instance_id: conexao.0,
        };
        match processar_evento(&mut state, &params, ev.evento, &ev.raw).await {
            Ok(_) => {}
            // Só falha transitória (barramento, RPC) pede reentrega. Recusa de
            // um tenant (402 por inadimplência) é decisão tomada: devolver 500
            // faria a Meta reentregar o lote de todos os tenants sem fim, e
            // ela acaba desativando o webhook do app inteiro.
            Err(status) if status.is_server_error() => falhou = true,
            Err(status) => tracing::info!(
                status = status.as_u16(),
                instance_id = params.instance_id,
                "evento da Meta recusado para o tenant; não reentregar"
            ),
        }
    }

    if falhou {
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    } else {
        StatusCode::OK.into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn assinar(segredo: &str, corpo: &[u8]) -> String {
        let mut mac = Hmac::<Sha256>::new_from_slice(segredo.as_bytes()).unwrap();
        mac.update(corpo);
        format!("sha256={}", hex::encode(mac.finalize().into_bytes()))
    }

    #[test]
    fn assinatura_valida_passa_e_qualquer_desvio_recusa() {
        let corpo = br#"{"object":"whatsapp_business_account"}"#;
        let ok = assinar("segredo", corpo);
        assert!(assinatura_confere(b"segredo", corpo, Some(&ok)));
        assert!(!assinatura_confere(b"outro", corpo, Some(&ok)));
        assert!(!assinatura_confere(b"segredo", b"{}", Some(&ok)));
        assert!(!assinatura_confere(b"segredo", corpo, None));
        assert!(!assinatura_confere(b"segredo", corpo, Some("sha1=abc")));
        assert!(!assinatura_confere(b"segredo", corpo, Some("sha256=zz")));
    }

    #[test]
    fn aperto_de_mao_devolve_o_desafio_so_com_o_token_certo() {
        let mut q = HashMap::new();
        q.insert("hub.mode".to_string(), "subscribe".to_string());
        q.insert("hub.verify_token".to_string(), "tok".to_string());
        q.insert("hub.challenge".to_string(), "123".to_string());
        assert_eq!(
            resposta_da_verificacao("tok", &q),
            (StatusCode::OK, "123".into())
        );
        assert_eq!(
            resposta_da_verificacao("outro", &q).0,
            StatusCode::FORBIDDEN
        );
        q.insert("hub.mode".to_string(), "unsubscribe".to_string());
        assert_eq!(resposta_da_verificacao("tok", &q).0, StatusCode::FORBIDDEN);
    }

    fn corpo_meta(mensagens: serde_json::Value, statuses: serde_json::Value) -> serde_json::Value {
        json!({
            "object": "whatsapp_business_account",
            "entry": [{
                "id": "WABA",
                "changes": [{
                    "field": "messages",
                    "value": {
                        "messaging_product": "whatsapp",
                        "metadata": { "display_phone_number": "558898106", "phone_number_id": "555000" },
                        "contacts": [{ "profile": { "name": "João" }, "wa_id": "5588999990000" }],
                        "messages": mensagens,
                        "statuses": statuses
                    }
                }]
            }]
        })
    }

    #[test]
    fn texto_da_meta_vira_o_formato_canonico_que_o_worker_le() {
        let corpo = corpo_meta(
            json!([{
                "from": "5588999990000",
                "id": "wamid.X",
                "timestamp": "1719260000",
                "type": "text",
                "text": { "body": "quanto custa?" }
            }]),
            json!([]),
        );
        let eventos = extrair_eventos(&corpo);
        assert_eq!(eventos.len(), 1);
        let ev = &eventos[0];
        assert_eq!(ev.phone_number_id, "555000");
        assert_eq!(ev.evento, "messages.upsert");

        // O mesmo parser que o worker usa para a Evolution.
        let msg = domain_whatsapp::NormalizedMessage::parse(&ev.raw, uuid::Uuid::nil(), 7).unwrap();
        assert_eq!(msg.message_id, "wamid.X");
        assert_eq!(msg.sender, "5588999990000");
        assert_eq!(msg.push_name, "João");
        assert_eq!(msg.content, "quanto custa?");
        assert_eq!(msg.timestamp.timestamp(), 1719260000);
        assert!(!msg.is_group);

        // E os extratores do pipeline comum (whitelist, idempotência).
        assert_eq!(
            crate::extrair_sender(ev.evento, &ev.raw).as_deref(),
            Some("5588999990000")
        );
        assert_eq!(
            crate::extrair_message_id(ev.evento, &ev.raw).as_deref(),
            Some("wamid.X")
        );
    }

    #[test]
    fn resposta_e_midia_preservam_contexto_e_legenda() {
        let corpo = corpo_meta(
            json!([
                {
                    "from": "55", "id": "wamid.R", "timestamp": "1", "type": "text",
                    "text": { "body": "sim" }, "context": { "id": "wamid.ANTES" }
                },
                {
                    "from": "55", "id": "wamid.I", "timestamp": "1", "type": "image",
                    "image": { "id": "MID", "mime_type": "image/jpeg", "caption": "é esse?" }
                }
            ]),
            json!([]),
        );
        let ev = extrair_eventos(&corpo);
        let r =
            domain_whatsapp::NormalizedMessage::parse(&ev[0].raw, uuid::Uuid::nil(), 1).unwrap();
        assert_eq!(r.reply_to.as_deref(), Some("wamid.ANTES"));
        assert_eq!(r.content, "sim");
        let i =
            domain_whatsapp::NormalizedMessage::parse(&ev[1].raw, uuid::Uuid::nil(), 1).unwrap();
        assert_eq!(i.media_type, domain_whatsapp::MediaType::Image);
        assert_eq!(i.content, "é esse?");
        assert_eq!(i.media_mime.as_deref(), Some("image/jpeg"));
    }

    #[test]
    fn status_entregue_e_lido_viram_status_e_enviado_e_descartado() {
        let corpo = corpo_meta(
            json!([]),
            json!([
                { "id": "wamid.A", "status": "delivered" },
                { "id": "wamid.B", "status": "read" },
                { "id": "wamid.C", "status": "sent" }
            ]),
        );
        let ev = extrair_eventos(&corpo);
        assert_eq!(ev.len(), 2);
        assert_eq!(ev[0].evento, EVENTO_STATUS);
        assert_eq!(ev[0].raw["data"]["status"], "delivered");
        assert_eq!(ev[1].raw["data"]["ids"], json!(["wamid.B"]));
    }

    #[test]
    fn tipo_sem_traducao_nao_vira_mensagem_vazia() {
        let corpo = corpo_meta(
            json!([
                { "from": "55", "id": "wamid.S", "timestamp": "1", "type": "system",
                  "system": { "body": "trocou de número" } },
                { "from": "55", "id": "wamid.U", "timestamp": "1", "type": "unsupported" }
            ]),
            json!([]),
        );
        assert!(extrair_eventos(&corpo).is_empty());
    }

    #[test]
    fn campo_que_nao_e_messages_e_ignorado() {
        let corpo = json!({
            "entry": [{ "changes": [{ "field": "account_update", "value": {} }] }]
        });
        assert!(extrair_eventos(&corpo).is_empty());
    }

    #[test]
    fn normalizador_da_meta_publica_com_o_provedor_dela_e_nao_aceita_token() {
        let n = MetaNormalizer;
        assert!(!n.aceita_rota_por_token());
        let (topico, env) = n
            .normalize("messages.upsert", &json!({}), uuid::Uuid::nil(), 9)
            .unwrap();
        assert_eq!(topico, "whatsapp.message.received");
        assert_eq!(env.payload["provider"], PROVIDER);
        assert_eq!(env.payload["instance_id"], 9);
        assert!(n
            .normalize("QRCODE", &json!({}), uuid::Uuid::nil(), 9)
            .is_none());
    }
}
