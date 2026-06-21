use crate::client::{ConnStateResp, CreateInstanceResp, EvolutionProvider};
use async_trait::async_trait;
use infrastructure_messaging::{
    ConnectionState, CreateInstanceResult, MediaType, MessagingProvider, MessagingProviderError,
    SendMessageResult,
};
use secrecy::{ExposeSecret, SecretString};

#[async_trait]
impl MessagingProvider for EvolutionProvider {
    fn provider_name(&self) -> &'static str {
        "evolution"
    }

    #[tracing::instrument(err, skip(self, custom_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn create_instance(
        &self,
        instance_name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError> {
        let mut body = serde_json::json!({
            "instanceName": instance_name,
            "qrcode": true,
            "integration": "WHATSAPP-BAILEYS"
        });
        if let Some(tok) = custom_token {
            body["token"] = serde_json::Value::String(tok.expose_secret().to_string());
        }

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

        let token = parsed.hash.or(parsed.instance.hash).ok_or_else(|| {
            MessagingProviderError::Deserialization("hash/token ausente na resposta".into())
        })?;

        Ok(CreateInstanceResult {
            provider_instance_id: parsed.instance.instance_name,
            instance_token: token,
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
    ) -> Result<(), MessagingProviderError> {
        let resp = self
            .http
            .get(format!(
                "{}/instance/connect/{}",
                self.base_url, instance_name
            ))
            .header("apikey", instance_token.expose_secret())
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
            .post(format!(
                "{}/instance/logout/{}",
                self.base_url, instance_name
            ))
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
            .get(format!(
                "{}/instance/connect/{}",
                self.base_url, instance_name
            ))
            .header("apikey", instance_token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        // Tenta achar em "code" ou "qrcode" -> "code" ou retornar o JSON todo como string se falhar
        if let Some(code) = v.get("code").and_then(|c| c.as_str()) {
            return Ok(code.to_string());
        }
        if let Some(qrcode) = v.get("qrcode") {
            if let Some(code) = qrcode.get("code").and_then(|c| c.as_str()) {
                return Ok(code.to_string());
            }
            if let Some(base64) = qrcode.get("base64").and_then(|b| b.as_str()) {
                return Ok(base64.to_string());
            }
        }
        if let Some(base64) = v.get("base64").and_then(|b| b.as_str()) {
            return Ok(base64.to_string());
        }

        Err(MessagingProviderError::Deserialization(format!(
            "Não foi possível extrair o QR code da resposta: {:?}",
            v
        )))
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn pair_by_phone(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        phone_number: &str,
    ) -> Result<String, MessagingProviderError> {
        let resp = self
            .http
            .post(format!(
                "{}/instance/pairingCode/{}",
                self.base_url, instance_name
            ))
            .header("apikey", instance_token.expose_secret())
            .json(&serde_json::json!({ "number": phone_number }))
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let code = v.get("code").and_then(|c| c.as_str()).ok_or_else(|| {
            MessagingProviderError::Deserialization(
                "code ausente na resposta de emparelhamento".into(),
            )
        })?;

        Ok(code.to_string())
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
    async fn configure_webhook(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        webhook_url: &str,
        events: &[String],
    ) -> Result<(), MessagingProviderError> {
        let resp = self
            .http
            .put(format!("{}/webhook/set/{}", self.base_url, instance_name))
            .header("apikey", instance_token.expose_secret())
            .json(&serde_json::json!({
                "enabled": true,
                "url": webhook_url,
                "webhookByEvents": false,
                "events": events
            }))
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        Self::ok_or_api(resp).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution", instance_name = %instance_name))]
    async fn get_connection_state(
        &self,
        instance_name: &str,
    ) -> Result<ConnectionState, MessagingProviderError> {
        let resp = self
            .http
            .get(format!(
                "{}/instance/connectionState/{}",
                self.base_url, instance_name
            ))
            .header("apikey", self.global_api_key.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let parsed: ConnStateResp = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        Ok(map_state(&parsed.instance.state))
    }

    #[tracing::instrument(err, skip(self, instance_token, text), fields(provider = "evolution", instance_name = %instance_name))]
    async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let resp = self
            .http
            .post(format!(
                "{}/message/sendText/{}",
                self.base_url, instance_name
            ))
            .header("apikey", instance_token.expose_secret())
            .json(&serde_json::json!({ "number": to_number, "text": text }))
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let id = v
            .get("key")
            .and_then(|k| k.get("id"))
            .and_then(|i| i.as_str())
            .ok_or_else(|| {
                MessagingProviderError::Deserialization(
                    "key.id ausente na resposta de envio".into(),
                )
            })?;

        Ok(SendMessageResult {
            message_id: id.to_string(),
        })
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
            "media": media_url,
            "mediatype": media_type_str,
        });

        if let Some(c) = caption {
            body["caption"] = serde_json::Value::String(c.to_string());
        }

        let resp = self
            .http
            .post(format!(
                "{}/message/sendMedia/{}",
                self.base_url, instance_name
            ))
            .header("apikey", instance_token.expose_secret())
            .json(&body)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;

        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

        let id = v
            .get("key")
            .and_then(|k| k.get("id"))
            .and_then(|i| i.as_str())
            .ok_or_else(|| {
                MessagingProviderError::Deserialization(
                    "key.id ausente na resposta de envio de mídia".into(),
                )
            })?;

        Ok(SendMessageResult {
            message_id: id.to_string(),
        })
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution"))]
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError> {
        let resp = self
            .http
            .get(format!("{}/instance/fetchInstances", self.base_url))
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
        if let Some(arr) = v.as_array() {
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

fn map_state(s: &str) -> ConnectionState {
    match s {
        "open" => ConnectionState::Connected,
        "close" => ConnectionState::Disconnected,
        "connecting" => ConnectionState::Connecting,
        _ => ConnectionState::Unknown,
    }
}
