use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum MediaType {
    Text,
    Image,
    Audio,
    Video,
    Document,
    Location,
    Sticker,
    Contact,
    Other(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NormalizedMessage {
    pub message_id: String,
    pub tenant_id: Uuid,
    pub instance_id: i32,
    pub sender: String,
    pub push_name: String,
    pub timestamp: DateTime<Utc>,
    pub media_type: MediaType,
    pub content: String,
    pub reply_to: Option<String>,
    pub is_from_me: bool,
    pub is_group: bool,
}

impl NormalizedMessage {
    pub fn parse(
        raw: &serde_json::Value,
        tenant_id: Uuid,
        instance_id: i32,
    ) -> Result<Self, String> {
        let data = raw
            .get("data")
            .ok_or_else(|| "Campo 'data' ausente no payload".to_string())?;
        let key = data
            .get("key")
            .ok_or_else(|| "Campo 'key' ausente em data".to_string())?;

        let message_id = key
            .get("id")
            .and_then(|id| id.as_str())
            .ok_or_else(|| "Campo 'id' ausente em key".to_string())?
            .to_string();

        let is_group = data
            .get("isGroup")
            .and_then(|g| g.as_bool())
            .unwrap_or(false);
        let remote_jid = key.get("remoteJid").and_then(|j| j.as_str()).unwrap_or("");

        let sender_jid = if is_group {
            data.get("participant")
                .and_then(|p| p.as_str())
                .or_else(|| key.get("participant").and_then(|p| p.as_str()))
                .unwrap_or(remote_jid)
        } else {
            remote_jid
        };

        // Pega apenas a parte numérica do remetente
        let sender = sender_jid
            .split('@')
            .next()
            .unwrap_or(sender_jid)
            .split('-')
            .next()
            .unwrap_or(sender_jid)
            .to_string();

        if sender.is_empty() {
            return Err(
                "Identificador do remetente (sender/remoteJid) inválido ou vazio".to_string(),
            );
        }

        let push_name = data
            .get("pushName")
            .and_then(|n| n.as_str())
            .unwrap_or("")
            .to_string();

        let ts_sec = data
            .get("messageTimestamp")
            .and_then(|t| t.as_i64())
            .unwrap_or_else(|| Utc::now().timestamp());

        let timestamp = DateTime::<Utc>::from_timestamp(ts_sec, 0).unwrap_or_else(Utc::now);

        let is_from_me = key.get("fromMe").and_then(|f| f.as_bool()).unwrap_or(false);

        // Extrai o reply_to se houver
        let mut reply_to = None;
        if let Some(msg_obj) = data.get("message").and_then(|m| m.as_object()) {
            for val in msg_obj.values() {
                if let Some(ctx_info) = val.get("contextInfo") {
                    if let Some(stanza_id) = ctx_info.get("stanzaId").and_then(|s| s.as_str()) {
                        reply_to = Some(stanza_id.to_string());
                        break;
                    }
                }
            }
        }

        // Determina o tipo de mídia e conteúdo
        let mut media_type = MediaType::Text;
        let mut content = String::new();

        if let Some(msg_obj) = data.get("message").and_then(|m| m.as_object()) {
            if let Some(text) = msg_obj.get("conversation").and_then(|t| t.as_str()) {
                media_type = MediaType::Text;
                content = text.to_string();
            } else if let Some(ext_text) = msg_obj.get("extendedTextMessage") {
                media_type = MediaType::Text;
                content = ext_text
                    .get("text")
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_string();
            } else if let Some(img) = msg_obj.get("imageMessage") {
                media_type = MediaType::Image;
                content = img
                    .get("caption")
                    .and_then(|c| c.as_str())
                    .unwrap_or("")
                    .to_string();
                if content.is_empty() {
                    content = img
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                }
            } else if let Some(audio) = msg_obj.get("audioMessage") {
                media_type = MediaType::Audio;
                content = audio
                    .get("url")
                    .and_then(|u| u.as_str())
                    .unwrap_or("")
                    .to_string();
            } else if let Some(video) = msg_obj.get("videoMessage") {
                media_type = MediaType::Video;
                content = video
                    .get("caption")
                    .and_then(|c| c.as_str())
                    .unwrap_or("")
                    .to_string();
                if content.is_empty() {
                    content = video
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                }
            } else if let Some(doc) = msg_obj.get("documentMessage") {
                media_type = MediaType::Document;
                content = doc
                    .get("title")
                    .or_else(|| doc.get("fileName"))
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_string();
                if content.is_empty() {
                    content = doc
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                }
            } else if let Some(loc) = msg_obj.get("locationMessage") {
                media_type = MediaType::Location;
                let lat = loc
                    .get("degreesLatitude")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                let lng = loc
                    .get("degreesLongitude")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                content = format!("Latitude: {}, Longitude: {}", lat, lng);
            } else if let Some(sticker) = msg_obj.get("stickerMessage") {
                media_type = MediaType::Sticker;
                content = sticker
                    .get("url")
                    .and_then(|u| u.as_str())
                    .unwrap_or("")
                    .to_string();
            } else if let Some(contact) = msg_obj.get("contactMessage") {
                media_type = MediaType::Contact;
                content = contact
                    .get("displayName")
                    .and_then(|n| n.as_str())
                    .unwrap_or("")
                    .to_string();
            } else {
                // Outro formato desconhecido
                for (key, val) in msg_obj {
                    if key.ends_with("Message") {
                        let name = key.strip_suffix("Message").unwrap_or(key).to_lowercase();
                        media_type = MediaType::Other(name);
                        content = val
                            .get("url")
                            .or_else(|| val.get("caption"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        break;
                    }
                }
            }
        }

        Ok(Self {
            message_id,
            tenant_id,
            instance_id,
            sender,
            push_name,
            timestamp,
            media_type,
            content,
            reply_to,
            is_from_me,
            is_group,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_text_message() {
        let payload = json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": false,
                    "id": "MSG1234"
                },
                "pushName": "João Silva",
                "messageTimestamp": 1719260000,
                "message": {
                    "conversation": "Olá, tudo bem?"
                }
            }
        });

        let tenant_id = Uuid::new_v4();
        let msg = NormalizedMessage::parse(&payload, tenant_id, 42).unwrap();

        assert_eq!(msg.message_id, "MSG1234");
        assert_eq!(msg.sender, "5511999998888");
        assert_eq!(msg.push_name, "João Silva");
        assert_eq!(msg.media_type, MediaType::Text);
        assert_eq!(msg.content, "Olá, tudo bem?");
        assert!(!msg.is_from_me);
        assert!(!msg.is_group);
        assert_eq!(msg.reply_to, None);
    }

    #[test]
    fn test_parse_image_message_with_reply() {
        let payload = json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": true,
                    "id": "MSG5678"
                },
                "pushName": "João Silva",
                "messageTimestamp": 1719260000,
                "message": {
                    "imageMessage": {
                        "url": "http://example.com/image.jpg",
                        "caption": "Olha essa foto",
                        "contextInfo": {
                            "stanzaId": "MSG1234"
                        }
                    }
                }
            }
        });

        let tenant_id = Uuid::new_v4();
        let msg = NormalizedMessage::parse(&payload, tenant_id, 42).unwrap();

        assert_eq!(msg.message_id, "MSG5678");
        assert_eq!(msg.media_type, MediaType::Image);
        assert_eq!(msg.content, "Olha essa foto");
        assert!(msg.is_from_me);
        assert_eq!(msg.reply_to, Some("MSG1234".to_string()));
    }
}
