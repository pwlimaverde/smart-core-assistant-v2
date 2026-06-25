use crate::client::{
    AvatarResp, ConnStateResp, CreateInstanceResp, DownloadMediaResp, EvolutionProvider,
    QrCodeResp, SendMessageResp,
};
use async_trait::async_trait;
use infrastructure_messaging::{
    AdvancedSettings, AdvancedSettingsControl, ConnectionState, CreateInstanceResult,
    InstanceManager, MediaDownloadResult, MediaDownloader, MediaType, MessageSender,
    MessagingProvider, MessagingProviderError, PresenceControl, PresenceState, ProfileQuery,
    Reactions, ReadReceipts, SendMessageResult, WebhookConfig,
};
use secrecy::{ExposeSecret, SecretString};

fn map_state(s: &str) -> ConnectionState {
    match s {
        "open" | "connected" => ConnectionState::Connected,
        "close" | "disconnected" | "loggedOut" => ConnectionState::Disconnected,
        "connecting" => ConnectionState::Connecting,
        _ => ConnectionState::Unknown,
    }
}

#[async_trait]
impl InstanceManager for EvolutionProvider {
    fn provider_name(&self) -> &'static str {
        "evolution"
    }

    #[tracing::instrument(err, skip(self, custom_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn create_instance(
        &self,
        instance_name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError> {
        let token = match custom_token {
            Some(t) => t.expose_secret().to_string(),
            None => uuid::Uuid::new_v4().simple().to_string(),
        };

        let body = serde_json::json!({
            "name": instance_name,
            "token": token
        });

        let resp = self
            .http
            .post(format!("{}/instance/create", self.base_url))
            .header("apikey", self.global_api_key.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: CreateInstanceResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let resolved_token = parsed
            .token
            .or_else(|| parsed.instance.token.clone())
            .or_else(|| {
                parsed.hash.as_ref().and_then(|h| {
                    if let Some(s) = h.as_str() {
                        Some(s.to_string())
                    } else if let Some(obj) = h.as_object() {
                        obj.get("apikey")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())
                    } else {
                        None
                    }
                })
            })
            .unwrap_or(token);

        Ok(CreateInstanceResult {
            provider_instance_id: parsed.instance.instance_name,
            instance_token: resolved_token,
        })
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution", instance_name = %instance_name))]
    async fn delete_instance(&self, instance_name: &str) -> Result<(), MessagingProviderError> {
        let resp = self
            .http
            .delete(format!(
                "{}/instance/delete/{}",
                self.base_url, instance_name
            ))
            .header("apikey", self.global_api_key.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn connect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        webhook: &WebhookConfig,
    ) -> Result<(), MessagingProviderError> {
        let body = serde_json::json!({
            "instanceName": instance_name,
            "webhookUrl": webhook.url,
            "subscribe": webhook.subscribe,
            "immediate": true
        });

        let resp = self
            .http
            .post(format!("{}/instance/connect", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn disconnect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError> {
        let resp = self
            .http
            .delete(format!("{}/instance/logout", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn reconnect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError> {
        let resp = self
            .http
            .post(format!("{}/instance/reconnect", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn get_qr_code(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<String, MessagingProviderError> {
        let resp = self
            .http
            .get(format!("{}/instance/qr", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: QrCodeResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        if let Some(code) = parsed.code {
            return Ok(code);
        }
        if let Some(base64) = parsed.base64 {
            return Ok(base64);
        }
        if let Some(qr) = parsed.qrcode {
            if let Some(code) = qr.code {
                return Ok(code);
            }
            if let Some(base64) = qr.base64 {
                return Ok(base64);
            }
        }

        Err(MessagingProviderError::Deserialization(
            "Não foi possível extrair o QR code da resposta".into(),
        ))
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn get_connection_state(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<ConnectionState, MessagingProviderError> {
        let resp = self
            .http
            .get(format!("{}/instance/status", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: ConnStateResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        Ok(map_state(&parsed.state))
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution"))]
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError> {
        let resp = self
            .http
            .get(format!("{}/instance/all", self.base_url))
            .header("apikey", self.global_api_key.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let mut names = Vec::new();
        let items = if let Some(arr) = v.as_array() {
            Some(arr)
        } else {
            v.get("data").and_then(|d| d.as_array())
        };

        if let Some(arr) = items {
            for item in arr {
                if let Some(name) = item.get("instanceName").and_then(|n| n.as_str()) {
                    names.push(name.to_string());
                } else if let Some(name) = item.get("name").and_then(|n| n.as_str()) {
                    names.push(name.to_string());
                }
            }
        }

        Ok(names)
    }
}

#[async_trait]
impl MessageSender for EvolutionProvider {
    #[tracing::instrument(err, skip(self, instance_token, text), fields(provider = "evolution", instance_name = %instance_name))]
    async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let body = serde_json::json!({
            "number": to_number,
            "text": text
        });

        let resp = self
            .http
            .post(format!("{}/send/text", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: SendMessageResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let id = parsed
            .id
            .or_else(|| parsed.key.map(|k| k.id))
            .ok_or_else(|| {
                MessagingProviderError::Deserialization("ID da mensagem ausente na resposta".into())
            })?;

        Ok(SendMessageResult { message_id: id })
    }

    #[tracing::instrument(err, skip(self, instance_token, caption), fields(provider = "evolution", instance_name = %instance_name))]
    async fn send_media(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        media_type: MediaType,
        media_url: &str,
        caption: Option<&str>,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let media_type_str = match media_type {
            MediaType::Image => "image",
            MediaType::Video => "video",
            MediaType::Audio => "audio",
            MediaType::Document => "document",
        };

        let mut body = serde_json::json!({
            "number": to_number,
            "type": media_type_str,
            "url": media_url,
        });

        if let Some(c) = caption {
            body["caption"] = serde_json::Value::String(c.to_string());
        }

        let resp = self
            .http
            .post(format!("{}/send/media", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: SendMessageResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let id = parsed
            .id
            .or_else(|| parsed.key.map(|k| k.id))
            .ok_or_else(|| {
                MessagingProviderError::Deserialization(
                    "ID da mensagem de mídia ausente na resposta".into(),
                )
            })?;

        Ok(SendMessageResult { message_id: id })
    }
}

#[async_trait]
impl PresenceControl for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn set_presence(
        &self,
        instance_name: &str,
        token: &SecretString,
        chat: &str,
        state: PresenceState,
        is_audio: bool,
    ) -> Result<(), MessagingProviderError> {
        let state_str = match state {
            PresenceState::Composing => "composing",
            PresenceState::Recording => "recording",
            PresenceState::Paused => "paused",
        };

        let body = serde_json::json!({
            "number": chat,
            "state": state_str,
            "isAudio": is_audio
        });

        let resp = self
            .http
            .post(format!("{}/message/presence", self.base_url))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }
}

#[async_trait]
impl ReadReceipts for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn mark_read(
        &self,
        instance_name: &str,
        token: &SecretString,
        chat: &str,
        message_ids: &[String],
    ) -> Result<(), MessagingProviderError> {
        let body = serde_json::json!({
            "number": chat,
            "id": message_ids
        });

        let resp = self
            .http
            .post(format!("{}/message/markread", self.base_url))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }
}

#[async_trait]
impl Reactions for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn send_reaction(
        &self,
        instance_name: &str,
        token: &SecretString,
        chat: &str,
        message_id: &str,
        emoji: &str,
        from_me: bool,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let body = serde_json::json!({
            "number": chat,
            "reaction": emoji,
            "id": message_id,
            "fromMe": from_me
        });

        let resp = self
            .http
            .post(format!("{}/message/react", self.base_url))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: SendMessageResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let id = parsed
            .id
            .or_else(|| parsed.key.map(|k| k.id))
            .unwrap_or_else(|| message_id.to_string());

        Ok(SendMessageResult { message_id: id })
    }
}

#[async_trait]
impl MediaDownloader for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token, message), fields(provider = "evolution", instance_name = %instance_name))]
    async fn download_media(
        &self,
        instance_name: &str,
        token: &SecretString,
        message: &serde_json::Value,
    ) -> Result<MediaDownloadResult, MessagingProviderError> {
        let body = serde_json::json!({
            "message": message
        });

        let resp = self
            .http
            .post(format!("{}/message/downloadmedia", self.base_url))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: DownloadMediaResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        Ok(MediaDownloadResult {
            base64: parsed.base64,
            mime_type: parsed.mimetype,
        })
    }
}

#[async_trait]
impl ProfileQuery for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn get_profile_picture(
        &self,
        instance_name: &str,
        token: &SecretString,
        number: &str,
    ) -> Result<Option<String>, MessagingProviderError> {
        let body = serde_json::json!({
            "number": number,
            "preview": false
        });

        let resp = self
            .http
            .post(format!("{}/user/avatar", self.base_url))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await;

        match resp {
            Ok(r) => {
                if r.status().is_success() {
                    let parsed: AvatarResp = r.json().await.unwrap_or(AvatarResp {
                        profile_picture_url: None,
                        url: None,
                    });
                    Ok(parsed.profile_picture_url.or(parsed.url))
                } else {
                    Ok(None)
                }
            }
            Err(_) => Ok(None),
        }
    }
}

#[async_trait]
impl AdvancedSettingsControl for EvolutionProvider {
    #[tracing::instrument(err, skip(self, token), fields(provider = "evolution", instance_id = %instance_id))]
    async fn set_advanced_settings(
        &self,
        instance_id: &str,
        token: &SecretString,
        settings: AdvancedSettings,
    ) -> Result<(), MessagingProviderError> {
        let body = serde_json::json!({
            "alwaysOnline": settings.always_online,
            "readMessages": settings.read_messages,
            "rejectCall": settings.reject_call,
            "msgRejectCall": settings.msg_reject_call,
            "ignoreGroups": settings.ignore_groups,
            "ignoreStatus": settings.ignore_status,
        });

        let resp = self
            .http
            .put(format!(
                "{}/instance/{}/advanced-settings",
                self.base_url, instance_id
            ))
            .header("apikey", token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }
}

impl MessagingProvider for EvolutionProvider {
    fn presence(&self) -> Option<&dyn PresenceControl> {
        Some(self)
    }
    fn read_receipts(&self) -> Option<&dyn ReadReceipts> {
        Some(self)
    }
    fn reactions(&self) -> Option<&dyn Reactions> {
        Some(self)
    }
    fn media_downloader(&self) -> Option<&dyn MediaDownloader> {
        Some(self)
    }
    fn profiles(&self) -> Option<&dyn ProfileQuery> {
        Some(self)
    }
    fn advanced_settings(&self) -> Option<&dyn AdvancedSettingsControl> {
        Some(self)
    }
}
