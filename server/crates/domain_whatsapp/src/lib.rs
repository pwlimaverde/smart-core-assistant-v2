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
    /// Sub-objeto bruto da mídia (`imageMessage`/`audioMessage`/`videoMessage`/
    /// `documentMessage`) do webhook, quando a mensagem é de mídia. Presença deste
    /// campo é o sinal para o pipeline de mídia do worker (download/análise); em
    /// mensagens de texto é `None`. Mantém-se puro (sem I/O): é só o recorte do payload.
    pub media_payload: Option<serde_json::Value>,
    pub media_mime: Option<String>,
    pub media_file_size: Option<i64>,
    /// Texto que a pessoa realmente escreveu: corpo da mensagem de texto ou legenda
    /// de imagem/vídeo. `None` quando não há texto nenhum — caso em que `content`
    /// carrega um substituto técnico (a URL da CDN do WhatsApp, o nome do arquivo,
    /// coordenadas formatadas).
    ///
    /// Existe porque `content` não distingue os dois: um áudio sem legenda tem
    /// `content` = URL da CDN, e mandar essa URL à IA como se fosse a pergunta do
    /// cliente produz resposta sem sentido (e gasta token). Quem fala com a IA usa
    /// [`Self::texto_para_ia`]; quem grava o histórico segue usando `content`.
    pub legenda: Option<String>,
}

/// Extrai `mimetype` e `fileLength` do sub-objeto de mídia. O `fileLength` do
/// WhatsApp costuma vir como string (mas às vezes número), então tratamos os dois.
fn extrair_meta_midia(sub: &serde_json::Value) -> (Option<String>, Option<i64>) {
    let mime = sub
        .get("mimetype")
        .and_then(|m| m.as_str())
        .map(|s| s.to_string());
    let size = sub.get("fileLength").and_then(|v| {
        v.as_i64()
            .or_else(|| v.as_str().and_then(|s| s.parse::<i64>().ok()))
    });
    (mime, size)
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
        let mut media_payload: Option<serde_json::Value> = None;
        let mut media_mime: Option<String> = None;
        let mut media_file_size: Option<i64> = None;
        // Preenchido só nos ramos em que `content` vem de um campo textual escrito
        // pela pessoa (corpo do texto ou legenda) — nunca de URL/nome de arquivo.
        let mut legenda: Option<String> = None;

        if let Some(msg_obj) = data.get("message").and_then(|m| m.as_object()) {
            if let Some(text) = msg_obj.get("conversation").and_then(|t| t.as_str()) {
                media_type = MediaType::Text;
                content = text.to_string();
                legenda = Some(content.clone());
            } else if let Some(ext_text) = msg_obj.get("extendedTextMessage") {
                media_type = MediaType::Text;
                content = ext_text
                    .get("text")
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_string();
                legenda = Some(content.clone());
            } else if let Some(img) = msg_obj.get("imageMessage") {
                media_type = MediaType::Image;
                content = img
                    .get("caption")
                    .and_then(|c| c.as_str())
                    .unwrap_or("")
                    .to_string();
                if !content.is_empty() {
                    legenda = Some(content.clone());
                }
                if content.is_empty() {
                    content = img
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                }
                let (mime, size) = extrair_meta_midia(img);
                media_payload = Some(img.clone());
                media_mime = mime;
                media_file_size = size;
            } else if let Some(audio) = msg_obj.get("audioMessage") {
                media_type = MediaType::Audio;
                content = audio
                    .get("url")
                    .and_then(|u| u.as_str())
                    .unwrap_or("")
                    .to_string();
                let (mime, size) = extrair_meta_midia(audio);
                media_payload = Some(audio.clone());
                media_mime = mime;
                media_file_size = size;
            } else if let Some(video) = msg_obj.get("videoMessage") {
                media_type = MediaType::Video;
                content = video
                    .get("caption")
                    .and_then(|c| c.as_str())
                    .unwrap_or("")
                    .to_string();
                if !content.is_empty() {
                    legenda = Some(content.clone());
                }
                if content.is_empty() {
                    content = video
                        .get("url")
                        .and_then(|u| u.as_str())
                        .unwrap_or("")
                        .to_string();
                }
                let (mime, size) = extrair_meta_midia(video);
                media_payload = Some(video.clone());
                media_mime = mime;
                media_file_size = size;
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
                let (mime, size) = extrair_meta_midia(doc);
                media_payload = Some(doc.clone());
                media_mime = mime;
                media_file_size = size;
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
            media_payload,
            media_mime,
            media_file_size,
            legenda,
        })
    }

    /// Texto a enviar para a IA (resposta do bot, análise de sentimento), ou `None`
    /// quando a mensagem não tem texto algum — mídia sem legenda, sticker,
    /// localização. Nesses casos não há pergunta a responder: chamar a IA com o
    /// substituto técnico de `content` (URL da CDN) só gastaria token e produziria
    /// resposta fora de contexto.
    pub fn texto_para_ia(&self) -> Option<&str> {
        self.legenda
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
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

    fn payload_com_message(message: serde_json::Value) -> serde_json::Value {
        json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": false,
                    "id": "MSGID"
                },
                "pushName": "Fulano",
                "messageTimestamp": 1719260000,
                "message": message
            }
        })
    }

    #[test]
    fn parse_falha_quando_campo_data_esta_ausente() {
        let payload = json!({});
        let err = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap_err();
        assert!(err.contains("data"));
    }

    #[test]
    fn parse_falha_quando_campo_key_esta_ausente() {
        let payload = json!({ "data": {} });
        let err = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap_err();
        assert!(err.contains("key"));
    }

    #[test]
    fn parse_falha_quando_campo_id_esta_ausente_em_key() {
        let payload = json!({
            "data": {
                "key": { "remoteJid": "5511999998888@s.whatsapp.net" }
            }
        });
        let err = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap_err();
        assert!(err.contains("id"));
    }

    #[test]
    fn parse_falha_quando_remetente_e_vazio() {
        let payload = json!({
            "data": {
                "key": { "remoteJid": "", "id": "MSG1" }
            }
        });
        let err = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap_err();
        assert!(err.contains("remetente") || err.contains("sender"));
    }

    #[test]
    fn parse_mensagem_de_grupo_usa_participant_como_remetente() {
        let payload = json!({
            "data": {
                "key": {
                    "remoteJid": "12036300@g.us",
                    "fromMe": false,
                    "id": "MSGGRP",
                    "participant": "5511977776666@s.whatsapp.net"
                },
                "isGroup": true,
                "message": { "conversation": "oi grupo" }
            }
        });
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert!(msg.is_group);
        assert_eq!(msg.sender, "5511977776666");
    }

    #[test]
    fn parse_mensagem_de_grupo_sem_participant_cai_no_remote_jid() {
        let payload = json!({
            "data": {
                "key": {
                    "remoteJid": "12036300@g.us",
                    "fromMe": false,
                    "id": "MSGGRP2"
                },
                "isGroup": true,
                "message": { "conversation": "oi grupo" }
            }
        });
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.sender, "12036300");
    }

    #[test]
    fn parse_extended_text_message() {
        let payload = payload_com_message(json!({
            "extendedTextMessage": { "text": "texto estendido" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Text);
        assert_eq!(msg.content, "texto estendido");
    }

    #[test]
    fn parse_image_message_sem_caption_cai_para_url() {
        let payload = payload_com_message(json!({
            "imageMessage": { "url": "http://example.com/img.jpg" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Image);
        assert_eq!(msg.content, "http://example.com/img.jpg");
    }

    #[test]
    fn parse_audio_message_usa_url_como_conteudo() {
        let payload = payload_com_message(json!({
            "audioMessage": { "url": "http://example.com/audio.ogg" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Audio);
        assert_eq!(msg.content, "http://example.com/audio.ogg");
    }

    #[test]
    fn parse_audio_preenche_media_payload_mime_e_tamanho() {
        let payload = payload_com_message(json!({
            "audioMessage": {
                "url": "http://example.com/audio.ogg",
                "mimetype": "audio/ogg; codecs=opus",
                "fileLength": "20480"
            }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Audio);
        assert!(msg.media_payload.is_some());
        assert_eq!(msg.media_mime.as_deref(), Some("audio/ogg; codecs=opus"));
        assert_eq!(msg.media_file_size, Some(20480));
    }

    #[test]
    fn parse_image_preenche_media_payload_com_file_length_numerico() {
        let payload = payload_com_message(json!({
            "imageMessage": {
                "url": "http://example.com/img.jpg",
                "caption": "foto",
                "mimetype": "image/jpeg",
                "fileLength": 51200
            }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Image);
        assert_eq!(msg.media_mime.as_deref(), Some("image/jpeg"));
        assert_eq!(msg.media_file_size, Some(51200));
        // O sub-objeto bruto é preservado inteiro para o download posterior.
        assert_eq!(
            msg.media_payload
                .as_ref()
                .and_then(|p| p.get("caption"))
                .and_then(|c| c.as_str()),
            Some("foto")
        );
    }

    #[test]
    fn parse_texto_nao_preenche_media_payload() {
        let payload = payload_com_message(json!({ "conversation": "só texto" }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert!(msg.media_payload.is_none());
        assert!(msg.media_mime.is_none());
        assert!(msg.media_file_size.is_none());
    }

    #[test]
    fn parse_video_message_com_caption() {
        let payload = payload_com_message(json!({
            "videoMessage": { "caption": "olha o video", "url": "http://x/v.mp4" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Video);
        assert_eq!(msg.content, "olha o video");
    }

    #[test]
    fn parse_video_message_sem_caption_cai_para_url() {
        let payload = payload_com_message(json!({
            "videoMessage": { "url": "http://x/v.mp4" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Video);
        assert_eq!(msg.content, "http://x/v.mp4");
    }

    #[test]
    fn parse_document_message_usa_title_quando_presente() {
        let payload = payload_com_message(json!({
            "documentMessage": {
                "title": "Contrato.pdf",
                "fileName": "outro_nome.pdf",
                "url": "http://x/doc.pdf"
            }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Document);
        assert_eq!(msg.content, "Contrato.pdf");
    }

    #[test]
    fn parse_document_message_sem_title_usa_file_name() {
        let payload = payload_com_message(json!({
            "documentMessage": { "fileName": "outro_nome.pdf", "url": "http://x/doc.pdf" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.content, "outro_nome.pdf");
    }

    #[test]
    fn parse_document_message_sem_title_nem_file_name_cai_para_url() {
        let payload = payload_com_message(json!({
            "documentMessage": { "url": "http://x/doc.pdf" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.content, "http://x/doc.pdf");
    }

    #[test]
    fn parse_location_message_formata_latitude_e_longitude() {
        let payload = payload_com_message(json!({
            "locationMessage": { "degreesLatitude": -23.5, "degreesLongitude": -46.6 }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Location);
        assert_eq!(msg.content, "Latitude: -23.5, Longitude: -46.6");
    }

    #[test]
    fn parse_sticker_message() {
        let payload = payload_com_message(json!({
            "stickerMessage": { "url": "http://x/sticker.webp" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Sticker);
        assert_eq!(msg.content, "http://x/sticker.webp");
    }

    #[test]
    fn parse_contact_message_usa_display_name() {
        let payload = payload_com_message(json!({
            "contactMessage": { "displayName": "Maria" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Contact);
        assert_eq!(msg.content, "Maria");
    }

    #[test]
    fn parse_tipo_desconhecido_cai_em_media_type_other() {
        let payload = payload_com_message(json!({
            "reactionMessage": { "caption": "👍" }
        }));
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Other("reaction".to_string()));
        assert_eq!(msg.content, "👍");
    }

    #[test]
    fn parse_sem_campo_message_usa_texto_vazio_por_padrao() {
        let payload = json!({
            "data": {
                "key": { "remoteJid": "5511999998888@s.whatsapp.net", "id": "MSGX" }
            }
        });
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert_eq!(msg.media_type, MediaType::Text);
        assert_eq!(msg.content, "");
        assert_eq!(msg.push_name, "");
    }

    #[test]
    fn parse_sem_timestamp_usa_o_horario_atual() {
        // `messageTimestamp` ausente cai no fallback `Utc::now().timestamp()`, que
        // trunca para a resolução de segundo — por isso comparamos truncando
        // `antes` da mesma forma, em vez de comparar com precisão de nanosegundos.
        let antes = Utc::now().timestamp();
        let payload = json!({
            "data": {
                "key": { "remoteJid": "5511999998888@s.whatsapp.net", "id": "MSGY" },
                "message": { "conversation": "oi" }
            }
        });
        let msg = NormalizedMessage::parse(&payload, Uuid::new_v4(), 1).unwrap();
        assert!(msg.timestamp.timestamp() >= antes);
    }

    #[test]
    fn parse_propaga_tenant_id_e_instance_id_informados() {
        let tenant_id = Uuid::new_v4();
        let payload = payload_com_message(json!({ "conversation": "oi" }));
        let msg = NormalizedMessage::parse(&payload, tenant_id, 99).unwrap();
        assert_eq!(msg.tenant_id, tenant_id);
        assert_eq!(msg.instance_id, 99);
    }

    /// `legenda`/`texto_para_ia` só existem quando a pessoa escreveu algo. É o que
    /// impede a URL da CDN de virar "pergunta do cliente" na chamada à IA.
    #[test]
    fn texto_para_ia_so_existe_quando_ha_texto_escrito() {
        let texto = NormalizedMessage::parse(
            &payload_com_message(json!({ "conversation": "quanto custa?" })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(texto.texto_para_ia(), Some("quanto custa?"));

        let estendido = NormalizedMessage::parse(
            &payload_com_message(json!({ "extendedTextMessage": { "text": "e o prazo?" } })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(estendido.texto_para_ia(), Some("e o prazo?"));

        let com_legenda = NormalizedMessage::parse(
            &payload_com_message(json!({
                "imageMessage": { "url": "http://x/i.jpg", "caption": "é esse o modelo?" }
            })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(com_legenda.texto_para_ia(), Some("é esse o modelo?"));

        // Áudio sem legenda: `content` é a URL da CDN, mas não há texto do usuário.
        let audio = NormalizedMessage::parse(
            &payload_com_message(json!({ "audioMessage": { "url": "http://x/a.ogg" } })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(audio.content, "http://x/a.ogg");
        assert_eq!(audio.legenda, None);
        assert_eq!(audio.texto_para_ia(), None);

        // Imagem sem legenda: idem — `content` cai para a URL.
        let imagem = NormalizedMessage::parse(
            &payload_com_message(json!({ "imageMessage": { "url": "http://x/i.jpg" } })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(imagem.texto_para_ia(), None);

        // Documento: o nome do arquivo é metadado, não mensagem.
        let doc = NormalizedMessage::parse(
            &payload_com_message(json!({ "documentMessage": { "title": "Contrato.pdf" } })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(doc.texto_para_ia(), None);
    }

    /// Texto só com espaços não é pergunta: `texto_para_ia` filtra o vazio útil,
    /// senão o bot responderia a um turno em branco.
    #[test]
    fn texto_para_ia_ignora_conteudo_em_branco() {
        let msg = NormalizedMessage::parse(
            &payload_com_message(json!({ "conversation": "   " })),
            Uuid::new_v4(),
            1,
        )
        .unwrap();
        assert_eq!(msg.texto_para_ia(), None);
    }

    #[test]
    fn media_type_enum_suporta_clone_debug_e_eq() {
        // Garante que as derives (Clone/Debug/PartialEq) seguem válidas para
        // todas as variantes, incluindo a variante com dado associado.
        let a = MediaType::Other("custom".to_string());
        let b = a.clone();
        assert_eq!(a, b);
        assert_ne!(MediaType::Text, MediaType::Image);
        assert!(format!("{:?}", MediaType::Audio).contains("Audio"));
    }
}
