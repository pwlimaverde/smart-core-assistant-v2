use crate::client::{AvatarResp, DownloadMediaResp, EvolutionProvider, SendMessageResp};
use async_trait::async_trait;
use infrastructure_messaging::{
    AdvancedSettings, AdvancedSettingsControl, ConnectionState, CreateInstanceResult,
    InstanceManager, MediaDownloadResult, MediaDownloader, MediaType, MessageSender,
    MessagingProvider, MessagingProviderError, PresenceControl, PresenceState, ProfileQuery,
    Reactions, ReadReceipts, SendMessageResult, WebhookConfig,
};
use secrecy::{ExposeSecret, SecretString};
use std::time::Duration;

fn map_state(s: &str) -> ConnectionState {
    match s {
        "open" | "connected" => ConnectionState::Connected,
        "close" | "disconnected" | "loggedOut" => ConnectionState::Disconnected,
        "connecting" => ConnectionState::Connecting,
        _ => ConnectionState::Unknown,
    }
}

/// Nome e token da instância recém-criada, nas duas formas que o provedor usa.
///
/// Quando esta função roda a instância JÁ existe do lado do provedor — por isso
/// ela não falha: um formato inesperado deixaria uma instância órfã lá e um
/// "erro inesperado" na tela de quem está conectando o WhatsApp.
///
///   evolution-go: `{"id":…, "name":…, "token":…}` (já desembrulhado de `data`)
///   Evolution v2: `{"instance":{"instanceName":…}, "hash":{"apikey":…}}`
fn identidade_da_instancia(
    corpo: &serde_json::Value,
    nome_pedido: &str,
    token_gerado: String,
) -> (String, String) {
    let interno = corpo.get("instance").unwrap_or(corpo);
    let nome = interno
        .get("instanceName")
        .or_else(|| interno.get("name"))
        .and_then(|v| v.as_str())
        .map(str::to_string)
        // O nome que pedimos é a última defesa: é com ele que o provedor acabou
        // de criar a instância, e por ele que as chamadas seguintes a encontram.
        .unwrap_or_else(|| nome_pedido.to_string());

    let token = corpo
        .get("token")
        .or_else(|| interno.get("token"))
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .or_else(|| {
            corpo.get("hash").and_then(|h| {
                h.as_str()
                    .map(str::to_string)
                    .or_else(|| h.get("apikey").and_then(|v| v.as_str()).map(str::to_string))
            })
        })
        .unwrap_or(token_gerado);

    (nome, token)
}

/// Estado da conexão nas duas formas que o provedor usa.
///
/// Evolution v2 diz numa palavra (`{"state":"open"}`); a evolution-go diz em
/// dois booleanos: `Connected` é o socket de pé, `LoggedIn` é a sessão pareada.
/// Para quem está no onboarding só o segundo significa "conectado" — com o
/// primeiro sozinho o QR ainda está por ler.
fn estado_do_corpo(corpo: &serde_json::Value) -> ConnectionState {
    if let Some(estado) = corpo.get("state").and_then(|v| v.as_str()) {
        return map_state(estado);
    }
    let bool_de = |chaves: [&str; 2]| {
        chaves
            .iter()
            .find_map(|c| corpo.get(*c).and_then(|v| v.as_bool()))
            .unwrap_or(false)
    };
    match (
        bool_de(["LoggedIn", "loggedIn"]),
        bool_de(["Connected", "connected"]),
    ) {
        (true, _) => ConnectionState::Connected,
        (false, true) => ConnectionState::Connecting,
        (false, false) => ConnectionState::Disconnected,
    }
}

/// Extrai o QR da resposta, **preferindo a imagem** ao texto.
///
/// A tela de conexão exibe a imagem (`Image.memory` sobre o base64); ela não
/// desenha um QR a partir do texto. Por isso a ordem importa: a evolution-go
/// 0.7.2 devolve os dois — `qrcode` com a imagem pronta
/// (`data:image/png;base64,…`) e `code` com o link `wa.me/settings/…` do
/// pareamento. Devolver o `code` primeiro, como antes, entregaria à tela um
/// texto que ela tentaria decodificar como imagem.
///
/// Formatos aceitos:
///   evolution-go: `{"qrcode": "data:image/png;base64,…", "code": "https://wa.me/…"}`
///   Evolution v2: `{"base64": "…"}` ou `{"qrcode": {"base64": "…", "code": "…"}}`
fn qr_do_corpo(corpo: &serde_json::Value) -> Option<String> {
    let texto = |v: Option<&serde_json::Value>| {
        v.and_then(|x| x.as_str())
            .filter(|s| !s.is_empty())
            .map(str::to_string)
    };

    let qrcode = corpo.get("qrcode");
    // 1. imagem, onde quer que ela esteja
    texto(qrcode.filter(|v| v.is_string()))
        .or_else(|| texto(corpo.get("base64")))
        .or_else(|| texto(qrcode.and_then(|q| q.get("base64"))))
        // 2. só então o texto do pareamento
        .or_else(|| texto(corpo.get("code")))
        .or_else(|| texto(qrcode.and_then(|q| q.get("code"))))
}

/// `true` quando o texto tem cara de UUID — o suficiente para decidir se ainda
/// precisamos traduzir nome → id antes de remover.
fn parece_uuid(s: &str) -> bool {
    s.len() == 36 && s.split('-').map(str::len).eq([8, 4, 4, 4, 12])
}

impl EvolutionProvider {
    /// Busca o registro da instância na listagem do provedor.
    ///
    /// Best-effort: devolve `None` quando a consulta falha ou o nome não
    /// aparece. Quem chama trata a ausência como "não sei", nunca como erro.
    async fn buscar_instancia(&self, instance_name: &str) -> Option<serde_json::Value> {
        let resp = self
            .http
            .get(format!("{}/instance/all", self.base_url))
            .header("apikey", self.global_api_key.expose_secret())
            .send()
            .await
            .ok()?;
        if !resp.status().is_success() {
            return None;
        }
        let corpo = Self::json_do_provedor(resp).await.ok()?;
        corpo
            .as_array()?
            .iter()
            .find(|i| {
                i.get("name").and_then(|v| v.as_str()) == Some(instance_name)
                    || i.get("instanceName").and_then(|v| v.as_str()) == Some(instance_name)
            })
            .cloned()
    }

    /// `true` quando existe aparelho vinculado à instância.
    ///
    /// O `jid` é o identificador do dispositivo pareado. Ele é o sinal confiável
    /// de "já conectou": a evolution-go mantém `LoggedIn: false` no
    /// `/instance/status` mesmo depois de registrar
    /// "Client successfully validated - Connected: true" no próprio log.
    async fn tem_aparelho_vinculado(&self, instance_name: &str) -> bool {
        self.buscar_instancia(instance_name)
            .await
            .and_then(|i| {
                i.get("jid")
                    .and_then(|v| v.as_str())
                    .map(|s| !s.trim().is_empty())
            })
            .unwrap_or(false)
    }

    /// Traduz o nome da instância no UUID que as rotas com `{instanceId}` na
    /// URL exigem (remoção, configurações avançadas, proxy, forcereconnect).
    ///
    /// Best-effort de propósito: se a consulta falhar ou o nome não aparecer na
    /// lista, devolve o que recebeu — que é o identificador aceito pela
    /// Evolution v2. Uma falha aqui não deve virar uma segunda falha; no pior
    /// caso a operação não acontece, exatamente como antes.
    async fn resolver_id_da_instancia(&self, instance_name: &str) -> String {
        if parece_uuid(instance_name) {
            return instance_name.to_string();
        }
        self.buscar_instancia(instance_name)
            .await
            .and_then(|i| i.get("id").and_then(|v| v.as_str()).map(str::to_string))
            .unwrap_or_else(|| instance_name.to_string())
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
        let corpo = Self::json_do_provedor(resp).await?;

        let (nome, instance_token) = identidade_da_instancia(&corpo, instance_name, token);

        Ok(CreateInstanceResult {
            provider_instance_id: nome,
            instance_token,
        })
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution", instance_name = %instance_name))]
    async fn delete_instance(&self, instance_name: &str) -> Result<(), MessagingProviderError> {
        // A evolution-go identifica a instância na URL por **UUID** e responde
        // 500 ("invalid UUID format") quando recebe o nome; a Evolution v2
        // aceita o nome. Resolver antes custa uma chamada e evita o pior caso:
        // o rollback do `create_instance` falhar em silêncio e deixar a
        // instância órfã no provedor — com o nome ocupado para a próxima
        // tentativa de quem está conectando o WhatsApp.
        let alvo = self.resolver_id_da_instancia(instance_name).await;

        let resp = self
            .http
            .delete(format!("{}/instance/delete/{}", self.base_url, alvo))
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
        let corpo = Self::json_do_provedor(resp).await?;

        qr_do_corpo(&corpo).ok_or_else(|| {
            MessagingProviderError::Deserialization(
                "Não foi possível extrair o QR code da resposta".into(),
            )
        })
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
        let corpo = Self::json_do_provedor(resp).await?;
        let estado = estado_do_corpo(&corpo);
        if estado == ConnectionState::Connected {
            return Ok(estado);
        }

        // A evolution-go mantém `LoggedIn: false` no `/instance/status` mesmo
        // depois de anotar "Client successfully validated - Connected: true" no
        // próprio log. Quem sabe a verdade é o `jid` — o aparelho vinculado.
        //
        // Isso não é purismo: enquanto o estado não for `Connected` seguimos
        // pedindo o QR, e **pedir o QR reinicia o cliente**. Ao fim de cinco
        // códigos a Evolution força logout ("Maximum QR code count reached (5),
        // forcing logout") e derruba a sessão recém-pareada — o usuário lia o
        // código, conectava, e via o QR reaparecer.
        //
        // MAS o `jid` sozinho não prova conexão: ele CONTINUA no registro depois
        // que o WhatsApp desvincula o aparelho. Aplicar o atalho com o socket
        // fechado fazia o servidor responder `Connected` para uma instância
        // morta — para sempre. Nada reconectava, o painel mentia, e ao fim de
        // ~14 dias offline o WhatsApp cortava o vínculo de vez, obrigando um QR
        // novo. Por isso o atalho vale só em `Connecting`, que é o estado que o
        // comentário acima descreve: socket ABERTO, sessão ainda não confirmada.
        // Socket fechado é desconexão de verdade, com ou sem `jid`.
        if estado == ConnectionState::Connecting && self.tem_aparelho_vinculado(instance_name).await
        {
            return Ok(ConnectionState::Connected);
        }

        Ok(estado)
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

        let mut attempts = 0;
        let mut last_error = None;
        let max_attempts = 3;
        let mut backoff = Duration::from_millis(500);

        while attempts < max_attempts {
            attempts += 1;
            let resp_res = self
                .http
                .post(format!("{}/send/text", self.base_url))
                .header("apikey", instance_token.expose_secret())
                .json(&body)
                .send()
                .await;

            match resp_res {
                Ok(resp) => {
                    let status = resp.status();
                    if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS
                    {
                        last_error = Some(MessagingProviderError::Network(format!(
                            "HTTP status {}",
                            status
                        )));
                        if attempts < max_attempts {
                            tokio::time::sleep(backoff).await;
                            backoff *= 2;
                            continue;
                        }
                    } else {
                        let resp = Self::ok_or_api(resp).await?;
                        let parsed: SendMessageResp = resp
                            .json()
                            .await
                            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

                        let id =
                            parsed
                                .id
                                .or_else(|| parsed.key.map(|k| k.id))
                                .ok_or_else(|| {
                                    MessagingProviderError::Deserialization(
                                        "ID da mensagem ausente na resposta".into(),
                                    )
                                })?;

                        return Ok(SendMessageResult { message_id: id });
                    }
                }
                Err(e) => {
                    last_error = Some(MessagingProviderError::Network(e.to_string()));
                    if attempts < max_attempts {
                        tokio::time::sleep(backoff).await;
                        backoff *= 2;
                        continue;
                    }
                }
            }
        }

        Err(last_error.unwrap_or_else(|| {
            MessagingProviderError::Network("Falha de envio desconhecida".into())
        }))
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

        let mut attempts = 0;
        let mut last_error = None;
        let max_attempts = 3;
        let mut backoff = Duration::from_millis(500);

        while attempts < max_attempts {
            attempts += 1;
            let resp_res = self
                .http
                .post(format!("{}/send/media", self.base_url))
                .header("apikey", instance_token.expose_secret())
                .json(&body)
                .send()
                .await;

            match resp_res {
                Ok(resp) => {
                    let status = resp.status();
                    if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS
                    {
                        last_error = Some(MessagingProviderError::Network(format!(
                            "HTTP status {}",
                            status
                        )));
                        if attempts < max_attempts {
                            tokio::time::sleep(backoff).await;
                            backoff *= 2;
                            continue;
                        }
                    } else {
                        let resp = Self::ok_or_api(resp).await?;
                        let parsed: SendMessageResp = resp
                            .json()
                            .await
                            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;

                        let id =
                            parsed
                                .id
                                .or_else(|| parsed.key.map(|k| k.id))
                                .ok_or_else(|| {
                                    MessagingProviderError::Deserialization(
                                        "ID da mensagem de mídia ausente na resposta".into(),
                                    )
                                })?;

                        return Ok(SendMessageResult { message_id: id });
                    }
                }
                Err(e) => {
                    last_error = Some(MessagingProviderError::Network(e.to_string()));
                    if attempts < max_attempts {
                        tokio::time::sleep(backoff).await;
                        backoff *= 2;
                        continue;
                    }
                }
            }
        }

        Err(last_error.unwrap_or_else(|| {
            MessagingProviderError::Network("Falha de envio desconhecida".into())
        }))
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

        // Mesma armadilha do `delete_instance`: a rota traz `{instanceId}` e a
        // evolution-go quer o UUID ali, não o nome — com o nome responde 500
        // ("invalid UUID format"). O erro era engolido como aviso, então as
        // configurações simplesmente não eram aplicadas, em silêncio.
        let alvo = self.resolver_id_da_instancia(instance_id).await;

        let resp = self
            .http
            .put(format!(
                "{}/instance/{}/advanced-settings",
                self.base_url, alvo
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

#[cfg(test)]
mod tests {
    use super::*;

    // `map_state` é lógica pura de normalização dos vários rótulos de estado que a
    // Evolution API retorna para o enum canônico `ConnectionState`. Testável sem HTTP.

    #[test]
    fn map_state_open_e_connected_viram_connected() {
        assert_eq!(map_state("open"), ConnectionState::Connected);
        assert_eq!(map_state("connected"), ConnectionState::Connected);
    }

    #[test]
    fn map_state_variantes_de_desconexao_viram_disconnected() {
        assert_eq!(map_state("close"), ConnectionState::Disconnected);
        assert_eq!(map_state("disconnected"), ConnectionState::Disconnected);
        assert_eq!(map_state("loggedOut"), ConnectionState::Disconnected);
    }

    #[test]
    fn map_state_connecting_vira_connecting() {
        assert_eq!(map_state("connecting"), ConnectionState::Connecting);
    }

    #[test]
    fn map_state_desconhecido_vira_unknown() {
        // Qualquer rótulo fora do conjunto conhecido cai em Unknown (fail-safe).
        assert_eq!(map_state("qualquer-coisa"), ConnectionState::Unknown);
        assert_eq!(map_state(""), ConnectionState::Unknown);
        // Sensível a maiúsculas: "OPEN" não é "open".
        assert_eq!(map_state("OPEN"), ConnectionState::Unknown);
    }

    // --- Formato de resposta do provedor -----------------------------------
    //
    // Os JSONs abaixo foram capturados da `evolution-go:0.7.1` em execucao, nao
    // escritos de memoria: foi justamente a divergencia entre o formato real e o
    // esperado que fez a criacao de instancia falhar com "erro inesperado",
    // deixando a instancia criada do lado do provedor e nada do nosso.

    #[test]
    fn create_da_evolution_go_entrega_nome_e_token() {
        // Ja desembrulhado de {"data": ..., "message": "success"}.
        let corpo = serde_json::json!({
            "id": "73a4873b-2fe6-40e6-a1b0-bb9b488ba98a",
            "name": "atendimento",
            "token": "25a8cecd6ffd4b36b7cdb0e077bdf139",
            "connected": false,
            "client_name": "smartcore"
        });
        let (nome, token) = identidade_da_instancia(&corpo, "atendimento", "gerado".into());
        assert_eq!(nome, "atendimento");
        assert_eq!(token, "25a8cecd6ffd4b36b7cdb0e077bdf139");
    }

    #[test]
    fn create_da_evolution_v2_continua_funcionando() {
        let corpo = serde_json::json!({
            "instance": { "instanceName": "atendimento", "instanceId": "abc" },
            "hash": { "apikey": "chave-v2" }
        });
        let (nome, token) = identidade_da_instancia(&corpo, "atendimento", "gerado".into());
        assert_eq!(nome, "atendimento");
        assert_eq!(token, "chave-v2");
    }

    #[test]
    fn create_com_formato_desconhecido_cai_no_que_pedimos() {
        // A instancia ja existe no provedor quando chegamos aqui: melhor seguir
        // com o nome que pedimos e o token que geramos do que falhar e deixar
        // uma instancia orfa.
        let corpo = serde_json::json!({ "algo": "inesperado" });
        let (nome, token) = identidade_da_instancia(&corpo, "atendimento", "gerado".into());
        assert_eq!(nome, "atendimento");
        assert_eq!(token, "gerado");
    }

    #[test]
    fn status_da_evolution_go_distingue_socket_de_sessao() {
        // Socket de pe, QR ainda por ler: nao e "conectado" para quem esta no
        // onboarding esperando a leitura do codigo.
        let subindo = serde_json::json!({ "Connected": true, "LoggedIn": false, "Name": "" });
        assert_eq!(estado_do_corpo(&subindo), ConnectionState::Connecting);

        let pareado = serde_json::json!({ "Connected": true, "LoggedIn": true, "Name": "5511..." });
        assert_eq!(estado_do_corpo(&pareado), ConnectionState::Connected);

        let fora = serde_json::json!({ "Connected": false, "LoggedIn": false });
        assert_eq!(estado_do_corpo(&fora), ConnectionState::Disconnected);
    }

    #[test]
    fn status_da_evolution_v2_continua_pela_palavra() {
        assert_eq!(
            estado_do_corpo(&serde_json::json!({ "state": "open" })),
            ConnectionState::Connected
        );
        assert_eq!(
            estado_do_corpo(&serde_json::json!({ "state": "connecting" })),
            ConnectionState::Connecting
        );
    }

    #[test]
    fn envelope_data_e_desembrulhado_so_quando_e_envelope() {
        use crate::client::desembrulhar;
        // Envelope da evolution-go.
        let v = desembrulhar(serde_json::json!({
            "data": { "name": "x" }, "message": "success"
        }));
        assert_eq!(v, serde_json::json!({ "name": "x" }));

        // Sem envelope (Evolution v2): passa direto.
        let v = desembrulhar(serde_json::json!({ "state": "open" }));
        assert_eq!(v, serde_json::json!({ "state": "open" }));

        // `data` escalar e conteudo, nao envelope — desembrulhar aqui perderia
        // o resto do objeto.
        let v = desembrulhar(serde_json::json!({ "data": "base64...", "mimetype": "image/png" }));
        assert_eq!(
            v,
            serde_json::json!({ "data": "base64...", "mimetype": "image/png" })
        );
    }

    #[test]
    fn qr_da_evolution_go_devolve_a_imagem_nao_o_link() {
        // Capturado da 0.7.2: os dois campos vem juntos, e a tela so sabe exibir
        // a imagem. Devolver o `code` daria a ela um link para decodificar como
        // PNG.
        let corpo = serde_json::json!({
            "qrcode": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg",
            "code": "https://wa.me/settings/linked_devices#2@ZKKW4qIwIwBvaGPh9gIq"
        });
        assert_eq!(
            qr_do_corpo(&corpo).unwrap(),
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg"
        );
    }

    #[test]
    fn qr_da_evolution_v2_nos_dois_formatos() {
        let raiz = serde_json::json!({ "base64": "iVBORw0KG" });
        assert_eq!(qr_do_corpo(&raiz).unwrap(), "iVBORw0KG");

        let aninhado = serde_json::json!({
            "qrcode": { "base64": "iVBORw0KG", "code": "2@abc" }
        });
        assert_eq!(qr_do_corpo(&aninhado).unwrap(), "iVBORw0KG");
    }

    #[test]
    fn qr_cai_para_o_texto_so_quando_nao_ha_imagem() {
        let so_texto = serde_json::json!({ "code": "2@abc" });
        assert_eq!(qr_do_corpo(&so_texto).unwrap(), "2@abc");
    }

    #[test]
    fn qr_ausente_ou_vazio_nao_vira_string_vazia() {
        // String vazia chegaria a tela como imagem invalida, sem dizer por que.
        assert!(qr_do_corpo(&serde_json::json!({ "qrcode": "", "code": "" })).is_none());
        assert!(qr_do_corpo(&serde_json::json!({})).is_none());
    }

    // --- Estado da conexão: o que o  significa ---
    //
    // Estes testes fixam a leitura crua do corpo. A regra de negócio que usa o
    // `jid` como desempate vive em `get_connection_state` (que faz HTTP), mas
    // ela depende inteiramente do que sai daqui: o atalho do aparelho vinculado
    // só pode valer em `Connecting` — socket aberto, sessão não confirmada.

    #[test]
    fn socket_fechado_e_sessao_ausente_e_desconexao() {
        // O caso que quebrou em produção: a instância cai, o `jid` CONTINUA no
        // registro do provedor, e tratar isso como "conectado" fazia o servidor
        // jurar que estava tudo bem enquanto nenhuma mensagem chegava. Aqui o
        // corpo tem de dizer "desconectado" — sem meio-termo.
        let corpo = serde_json::json!({ "Connected": false, "LoggedIn": false });
        assert_eq!(estado_do_corpo(&corpo), ConnectionState::Disconnected);
    }

    #[test]
    fn socket_aberto_sem_login_confirmado_e_connecting() {
        // É o estado em que o desempate pelo `jid` é legítimo: a evolution-go
        // mantém `LoggedIn: false` mesmo depois de validar o cliente.
        let corpo = serde_json::json!({ "Connected": true, "LoggedIn": false });
        assert_eq!(estado_do_corpo(&corpo), ConnectionState::Connecting);
    }

    #[test]
    fn login_confirmado_e_conexao_independente_do_socket() {
        let corpo = serde_json::json!({ "Connected": false, "LoggedIn": true });
        assert_eq!(estado_do_corpo(&corpo), ConnectionState::Connected);
    }

    #[test]
    fn campo_state_textual_tem_precedencia_sobre_os_booleanos() {
        // Provedores diferentes respondem de formas diferentes; quando vem
        // `state`, é ele que manda.
        let corpo = serde_json::json!({ "state": "open", "Connected": false });
        assert_eq!(estado_do_corpo(&corpo), ConnectionState::Connected);
    }
}
