//! Adaptador da WhatsApp Cloud API (Meta) atrás do contrato de canal.
//!
//! Estágio EXPERIMENTAL. O que está implementado de verdade:
//! - conexão por credenciais (`phone_number_id` + token de acesso), validada
//!   no Graph API antes de gravar qualquer coisa;
//! - consulta de saúde da conexão (o mesmo GET da validação);
//! - envio de texto e de mídia por link;
//! - recibo de leitura.
//!
//! O que NÃO existe e responde `Unsupported` (nunca `Ok` de mentira): criar
//! instância, QR, registrar webhook (na Cloud API o webhook é do app da Meta,
//! um por ambiente, configurado no painel), desconectar/religar sessão (não há
//! sessão de aparelho), download de mídia, templates, presença e reações.
//!
//! Endereçamento: o adaptador recebe o `phone_number_id` onde a Evolution
//! recebe o nome da instância (`EnderecoNoProvedor::IdExterno`), e o token de
//! acesso onde a Evolution recebe o token da instância.

use async_trait::async_trait;
use infrastructure_messaging::{
    CampoConfiguracao, CanalConectado, Capacidade, ChannelDescriptor, ChannelKind, ConnectionMode,
    ConnectionState, CreateInstanceResult, CredencialInformada, EnderecoNoProvedor, Estagio,
    InstanceManager, MediaType, MessageSender, MessagingProvider, MessagingProviderError,
    ReadReceipts, SendMessageResult, TipoCampo, TokenConnect, WebhookConfig,
};
use secrecy::{ExposeSecret, SecretString};
use std::time::Duration;

/// Chave do provedor no registro e em `whatsapp_instance.provider`.
pub const PROVIDER: &str = "meta_cloud";

/// Versão do Graph API usada quando `META_GRAPH_API_URL` não é informada.
pub const GRAPH_API_PADRAO: &str = "https://graph.facebook.com/v21.0";

const TIMEOUT_REQUISICAO: Duration = Duration::from_secs(30);
const TIMEOUT_CONEXAO: Duration = Duration::from_secs(5);

/// Cliente da Cloud API. Não guarda credencial nenhuma: o token de cada
/// conexão chega por chamada, vindo do banco (cifrado em repouso).
#[derive(Clone)]
pub struct MetaCloudProvider {
    http: reqwest::Client,
    base_url: String,
}

impl MetaCloudProvider {
    pub fn new(base_url: impl Into<String>) -> Self {
        // Sem timeout, um Graph API que aceita a conexão e não responde
        // prenderia o handler do `data_whatsapp` para sempre.
        let http = reqwest::Client::builder()
            .timeout(TIMEOUT_REQUISICAO)
            .connect_timeout(TIMEOUT_CONEXAO)
            .build()
            .unwrap_or_else(|e| {
                tracing::warn!(erro = %e, "cliente HTTP da Cloud API sem timeout");
                reqwest::Client::new()
            });
        Self {
            http,
            base_url: base_url.into().trim_end_matches('/').to_string(),
        }
    }

    /// Lê `META_GRAPH_API_URL` (vazio ou ausente cai no padrão).
    pub fn do_ambiente() -> Self {
        let base = std::env::var("META_GRAPH_API_URL")
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| GRAPH_API_PADRAO.to_string());
        Self::new(base)
    }

    /// Status != 2xx vira `ProviderApi` com a mensagem do Graph (`error.message`)
    /// truncada: o corpo pode ecoar dados do número, e o log não precisa dele.
    async fn ok_or_api(
        resp: reqwest::Response,
    ) -> Result<serde_json::Value, MessagingProviderError> {
        let status = resp.status();
        let corpo: serde_json::Value = resp.json().await.unwrap_or(serde_json::Value::Null);
        if status.is_success() {
            return Ok(corpo);
        }
        let msg = corpo
            .pointer("/error/message")
            .and_then(|m| m.as_str())
            .unwrap_or("erro sem mensagem")
            .chars()
            .take(200)
            .collect();
        Err(MessagingProviderError::ProviderApi {
            status: status.as_u16(),
            body: msg,
        })
    }

    /// `GET /{phone_number_id}` — prova que o token enxerga o número.
    async fn consultar_numero(
        &self,
        phone_number_id: &str,
        token: &SecretString,
    ) -> Result<serde_json::Value, MessagingProviderError> {
        let resp = self
            .http
            .get(format!("{}/{}", self.base_url, phone_number_id))
            .query(&[("fields", "display_phone_number,verified_name")])
            .bearer_auth(token.expose_secret())
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        Self::ok_or_api(resp).await
    }

    async fn postar_mensagem(
        &self,
        phone_number_id: &str,
        token: &SecretString,
        corpo: serde_json::Value,
    ) -> Result<serde_json::Value, MessagingProviderError> {
        let resp = self
            .http
            .post(format!("{}/{}/messages", self.base_url, phone_number_id))
            .bearer_auth(token.expose_secret())
            .json(&corpo)
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        Self::ok_or_api(resp).await
    }
}

/// O destinatário no formato da Cloud API: só dígitos. O resto do sistema às
/// vezes carrega o JID (`5511…@s.whatsapp.net`); o sufixo não é aceito lá.
pub fn destinatario(to: &str) -> String {
    let sem_sufixo = to.split('@').next().unwrap_or(to);
    sem_sufixo.chars().filter(|c| c.is_ascii_digit()).collect()
}

fn id_enviado(corpo: &serde_json::Value) -> Result<SendMessageResult, MessagingProviderError> {
    corpo
        .pointer("/messages/0/id")
        .and_then(|v| v.as_str())
        .map(|id| SendMessageResult {
            message_id: id.to_string(),
        })
        .ok_or_else(|| {
            MessagingProviderError::Deserialization("resposta sem messages[0].id".into())
        })
}

fn valor<'a>(campos: &'a [CredencialInformada], chave: &str) -> Option<&'a SecretString> {
    campos
        .iter()
        .find(|c| c.chave == chave)
        .map(|c| &c.valor)
        .filter(|v| !v.expose_secret().trim().is_empty())
}

#[async_trait]
impl InstanceManager for MetaCloudProvider {
    fn provider_name(&self) -> &'static str {
        PROVIDER
    }

    async fn create_instance(
        &self,
        _name: &str,
        _custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError> {
        Err(MessagingProviderError::Unsupported(
            "a Cloud API não cria instância: conecte por credenciais",
        ))
    }

    /// Não há nada a apagar do lado da Meta: o número continua no WhatsApp
    /// Business da empresa. Remover a conexão aqui é só deixar de usá-la, e o
    /// `Ok` diz exatamente isso.
    async fn delete_instance(&self, _name: &str) -> Result<(), MessagingProviderError> {
        Ok(())
    }

    async fn connect_instance(
        &self,
        _name: &str,
        _token: &SecretString,
        _webhook: &WebhookConfig,
    ) -> Result<(), MessagingProviderError> {
        Err(MessagingProviderError::Unsupported(
            "o webhook da Cloud API é configurado no app da Meta (um por ambiente)",
        ))
    }

    async fn disconnect_instance(
        &self,
        _name: &str,
        _token: &SecretString,
    ) -> Result<(), MessagingProviderError> {
        Err(MessagingProviderError::Unsupported(
            "a Cloud API não tem sessão de aparelho para desconectar; remova a conexão",
        ))
    }

    async fn reconnect_instance(
        &self,
        _name: &str,
        _token: &SecretString,
    ) -> Result<(), MessagingProviderError> {
        Err(MessagingProviderError::Unsupported(
            "a Cloud API não tem sessão para religar; troque o token se ele expirou",
        ))
    }

    /// Saúde = o token ainda enxerga o número. 401/403 é token revogado ou sem
    /// permissão (desconectada de fato); outro erro é "não sei".
    async fn get_connection_state(
        &self,
        phone_number_id: &str,
        token: &SecretString,
    ) -> Result<ConnectionState, MessagingProviderError> {
        match self.consultar_numero(phone_number_id, token).await {
            Ok(_) => Ok(ConnectionState::Connected),
            Err(MessagingProviderError::ProviderApi {
                status: 401 | 403, ..
            }) => Ok(ConnectionState::Disconnected),
            Err(e) => Err(e),
        }
    }

    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError> {
        Err(MessagingProviderError::Unsupported(
            "a Cloud API não lista instâncias",
        ))
    }
}

#[async_trait]
impl MessageSender for MetaCloudProvider {
    async fn send_text(
        &self,
        phone_number_id: &str,
        token: &SecretString,
        to: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let corpo = serde_json::json!({
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": destinatario(to),
            "type": "text",
            "text": { "preview_url": false, "body": text },
        });
        id_enviado(&self.postar_mensagem(phone_number_id, token, corpo).await?)
    }

    async fn send_media(
        &self,
        phone_number_id: &str,
        token: &SecretString,
        to: &str,
        media: MediaType,
        url: &str,
        caption: Option<&str>,
        file_name: Option<&str>,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let tipo = match media {
            MediaType::Image => "image",
            MediaType::Video => "video",
            MediaType::Audio => "audio",
            MediaType::Document => "document",
        };
        let mut objeto = serde_json::json!({ "link": url });
        // A Cloud API recusa legenda em áudio; nome de arquivo só em documento.
        if let (Some(c), false) = (caption, media == MediaType::Audio) {
            objeto["caption"] = serde_json::json!(c);
        }
        if let (Some(f), MediaType::Document) = (file_name, media) {
            objeto["filename"] = serde_json::json!(f);
        }
        let mut corpo = serde_json::json!({
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": destinatario(to),
            "type": tipo,
        });
        corpo[tipo] = objeto;
        id_enviado(&self.postar_mensagem(phone_number_id, token, corpo).await?)
    }
}

#[async_trait]
impl ReadReceipts for MetaCloudProvider {
    /// A Cloud API marca uma mensagem por chamada; o chat não é usado.
    async fn mark_read(
        &self,
        phone_number_id: &str,
        token: &SecretString,
        _chat: &str,
        message_ids: &[String],
    ) -> Result<(), MessagingProviderError> {
        for id in message_ids {
            let corpo = serde_json::json!({
                "messaging_product": "whatsapp",
                "status": "read",
                "message_id": id,
            });
            self.postar_mensagem(phone_number_id, token, corpo).await?;
        }
        Ok(())
    }
}

#[async_trait]
impl TokenConnect for MetaCloudProvider {
    async fn conectar_com_credenciais(
        &self,
        campos: &[CredencialInformada],
    ) -> Result<CanalConectado, MessagingProviderError> {
        let phone_number_id = valor(campos, "phone_number_id")
            .map(|v| v.expose_secret().trim().to_string())
            .ok_or_else(|| MessagingProviderError::Config("informe o phone_number_id".into()))?;
        if !phone_number_id.chars().all(|c| c.is_ascii_digit()) {
            return Err(MessagingProviderError::Config(
                "phone_number_id tem só dígitos (é o id do número, não o telefone)".into(),
            ));
        }
        let token = valor(campos, "access_token")
            .map(|v| SecretString::from(v.expose_secret().trim().to_string()))
            .ok_or_else(|| MessagingProviderError::Config("informe o token de acesso".into()))?;
        let waba_id = valor(campos, "waba_id").map(|v| v.expose_secret().trim().to_string());

        // Valida antes de gravar: credencial errada volta como erro aqui, não
        // como uma conexão morta no banco.
        let numero = self.consultar_numero(&phone_number_id, &token).await?;
        let telefone = numero
            .get("display_phone_number")
            .and_then(|v| v.as_str())
            .map(destinatario);
        let nome_exibicao = numero
            .get("verified_name")
            .and_then(|v| v.as_str())
            .map(str::to_string);

        let mut config = serde_json::json!({ "phone_number_id": phone_number_id });
        if let Some(w) = waba_id {
            config["waba_id"] = serde_json::json!(w);
        }
        if let Some(n) = &nome_exibicao {
            config["verified_name"] = serde_json::json!(n);
        }

        Ok(CanalConectado {
            id_externo: phone_number_id,
            telefone,
            nome_exibicao,
            token,
            config,
        })
    }
}

impl MessagingProvider for MetaCloudProvider {
    fn descritor(&self) -> ChannelDescriptor {
        ChannelDescriptor {
            provider: PROVIDER.into(),
            kind: ChannelKind::Whatsapp,
            nome: "WhatsApp Business (API oficial)".into(),
            descricao: "Conecta um número da WhatsApp Cloud API da Meta com o id do \
                        número e um token de acesso permanente. Sem QR code. Em \
                        desenvolvimento: recebimento depende do app da Meta do ambiente."
                .into(),
            estagio: Estagio::Experimental,
            connection_mode: ConnectionMode::Token,
            endereco: EnderecoNoProvedor::IdExterno,
            config_schema: vec![
                CampoConfiguracao::novo(
                    "phone_number_id",
                    "ID do número de telefone",
                    TipoCampo::Texto,
                    true,
                    "Meta for Developers > WhatsApp > Configuração da API: \"Identificação do número de telefone\".",
                ),
                CampoConfiguracao::novo(
                    "waba_id",
                    "ID da conta do WhatsApp Business",
                    TipoCampo::Texto,
                    false,
                    "Mesma tela. Necessário para modelos de mensagem (templates).",
                ),
                CampoConfiguracao::novo(
                    "access_token",
                    "Token de acesso permanente",
                    TipoCampo::Segredo,
                    true,
                    "Token de usuário do sistema com as permissões whatsapp_business_messaging e whatsapp_business_management.",
                ),
            ],
            capacidades: vec![
                Capacidade::Health,
                Capacidade::EnvioTexto,
                Capacidade::EnvioMidia,
            ],
            // Webhook do app da Meta: assinatura do campo `messages`, feita no
            // painel da Meta, não pelo servidor.
            eventos_webhook: vec![],
        }
    }

    fn read_receipts(&self) -> Option<&dyn ReadReceipts> {
        Some(self)
    }

    fn token_connect(&self) -> Option<&dyn TokenConnect> {
        Some(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{body_json, header, method, path, query_param};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    fn segredo(v: &str) -> SecretString {
        SecretString::from(v.to_string())
    }

    fn campos(pares: &[(&str, &str)]) -> Vec<CredencialInformada> {
        pares
            .iter()
            .map(|(k, v)| CredencialInformada {
                chave: k.to_string(),
                valor: segredo(v),
            })
            .collect()
    }

    #[test]
    fn descritor_declara_so_o_que_existe() {
        let p = MetaCloudProvider::new("http://x");
        let d = infrastructure_messaging::descritor_efetivo(&p);
        assert_eq!(d.provider, PROVIDER);
        assert_eq!(d.connection_mode, ConnectionMode::Token);
        assert_eq!(d.endereco, EnderecoNoProvedor::IdExterno);
        assert_eq!(d.estagio, Estagio::Experimental);
        assert!(d.suporta(Capacidade::TokenConnect));
        assert!(d.suporta(Capacidade::Recibos));
        for nao in [
            Capacidade::QrPairing,
            Capacidade::Reconexao,
            Capacidade::Desconectar,
            Capacidade::RegistraWebhook,
            Capacidade::Presenca,
            Capacidade::Reacoes,
            Capacidade::DownloadMidia,
            Capacidade::Templates,
        ] {
            assert!(!d.suporta(nao), "{nao:?}");
        }
        let segredos: Vec<&str> = d
            .config_schema
            .iter()
            .filter(|c| c.tipo == TipoCampo::Segredo)
            .map(|c| c.chave.as_str())
            .collect();
        assert_eq!(segredos, vec!["access_token"]);
    }

    #[test]
    fn destinatario_fica_so_com_digitos() {
        assert_eq!(
            destinatario("5588999990000@s.whatsapp.net"),
            "5588999990000"
        );
        assert_eq!(destinatario("+55 88 99999-0000"), "5588999990000");
    }

    #[tokio::test]
    async fn conectar_valida_no_graph_e_devolve_o_numero() {
        let srv = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/123456"))
            .and(query_param("fields", "display_phone_number,verified_name"))
            .and(header("authorization", "Bearer tok"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "display_phone_number": "+55 88 98106-1874",
                "verified_name": "Loja",
                "id": "123456"
            })))
            .expect(1)
            .mount(&srv)
            .await;

        let p = MetaCloudProvider::new(srv.uri());
        let c = p
            .conectar_com_credenciais(&campos(&[
                ("phone_number_id", "123456"),
                ("access_token", "tok"),
                ("waba_id", "999"),
            ]))
            .await
            .unwrap();
        assert_eq!(c.id_externo, "123456");
        assert_eq!(c.telefone.as_deref(), Some("5588981061874"));
        assert_eq!(c.token.expose_secret(), "tok");
        assert_eq!(c.config["waba_id"], "999");
        assert_eq!(c.config["verified_name"], "Loja");
    }

    #[tokio::test]
    async fn token_recusado_nao_vira_conexao() {
        let srv = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/123456"))
            .respond_with(ResponseTemplate::new(401).set_body_json(serde_json::json!({
                "error": { "message": "Invalid OAuth access token", "code": 190 }
            })))
            .mount(&srv)
            .await;
        let p = MetaCloudProvider::new(srv.uri());
        let err = p
            .conectar_com_credenciais(&campos(&[
                ("phone_number_id", "123456"),
                ("access_token", "ruim"),
            ]))
            .await
            .err()
            .unwrap();
        match err {
            MessagingProviderError::ProviderApi { status, body } => {
                assert_eq!(status, 401);
                assert!(body.contains("Invalid OAuth"));
            }
            outro => panic!("esperava ProviderApi, veio {outro:?}"),
        }
    }

    #[tokio::test]
    async fn campo_obrigatorio_ausente_recusa_sem_chamar_o_graph() {
        let srv = MockServer::start().await;
        Mock::given(method("GET"))
            .respond_with(ResponseTemplate::new(200))
            .expect(0)
            .mount(&srv)
            .await;
        let p = MetaCloudProvider::new(srv.uri());
        assert!(p
            .conectar_com_credenciais(&campos(&[("phone_number_id", "123")]))
            .await
            .is_err());
        assert!(p
            .conectar_com_credenciais(&campos(&[
                ("phone_number_id", "+55 88"),
                ("access_token", "t")
            ]))
            .await
            .is_err());
    }

    #[tokio::test]
    async fn envia_texto_pelo_phone_number_id() {
        let srv = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/123456/messages"))
            .and(header("authorization", "Bearer tok"))
            .and(body_json(serde_json::json!({
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": "5588999990000",
                "type": "text",
                "text": { "preview_url": false, "body": "oi" }
            })))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "messages": [{ "id": "wamid.ABC" }]
            })))
            .expect(1)
            .mount(&srv)
            .await;
        let p = MetaCloudProvider::new(srv.uri());
        let r = p
            .send_text(
                "123456",
                &segredo("tok"),
                "5588999990000@s.whatsapp.net",
                "oi",
            )
            .await
            .unwrap();
        assert_eq!(r.message_id, "wamid.ABC");
    }

    #[tokio::test]
    async fn audio_nao_leva_legenda_e_documento_leva_nome() {
        let srv = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/1/messages"))
            .and(body_json(serde_json::json!({
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": "55",
                "type": "audio",
                "audio": { "link": "https://x/a.ogg" }
            })))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "messages": [{ "id": "wamid.A" }]
            })))
            .expect(1)
            .mount(&srv)
            .await;
        Mock::given(method("POST"))
            .and(path("/1/messages"))
            .and(body_json(serde_json::json!({
                "messaging_product": "whatsapp",
                "recipient_type": "individual",
                "to": "55",
                "type": "document",
                "document": { "link": "https://x/d.pdf", "caption": "c", "filename": "d.pdf" }
            })))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "messages": [{ "id": "wamid.D" }]
            })))
            .expect(1)
            .mount(&srv)
            .await;
        let p = MetaCloudProvider::new(srv.uri());
        let t = segredo("t");
        let a = p
            .send_media(
                "1",
                &t,
                "55",
                MediaType::Audio,
                "https://x/a.ogg",
                Some("c"),
                None,
            )
            .await
            .unwrap();
        assert_eq!(a.message_id, "wamid.A");
        let d = p
            .send_media(
                "1",
                &t,
                "55",
                MediaType::Document,
                "https://x/d.pdf",
                Some("c"),
                Some("d.pdf"),
            )
            .await
            .unwrap();
        assert_eq!(d.message_id, "wamid.D");
    }

    #[tokio::test]
    async fn saude_distingue_token_revogado_de_falha_do_graph() {
        let srv = MockServer::start().await;
        Mock::given(method("GET"))
            .and(path("/ok"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({})))
            .mount(&srv)
            .await;
        Mock::given(method("GET"))
            .and(path("/revogado"))
            .respond_with(ResponseTemplate::new(401).set_body_json(serde_json::json!({})))
            .mount(&srv)
            .await;
        Mock::given(method("GET"))
            .and(path("/caiu"))
            .respond_with(ResponseTemplate::new(500).set_body_json(serde_json::json!({})))
            .mount(&srv)
            .await;
        let p = MetaCloudProvider::new(srv.uri());
        let t = segredo("t");
        assert_eq!(
            p.get_connection_state("ok", &t).await.unwrap(),
            ConnectionState::Connected
        );
        assert_eq!(
            p.get_connection_state("revogado", &t).await.unwrap(),
            ConnectionState::Disconnected
        );
        assert!(p.get_connection_state("caiu", &t).await.is_err());
    }

    #[tokio::test]
    async fn operacoes_sem_equivalente_respondem_unsupported() {
        let p = MetaCloudProvider::new("http://127.0.0.1:9");
        let t = segredo("t");
        let hook = WebhookConfig {
            url: "x".into(),
            subscribe: vec![],
        };
        assert!(matches!(
            p.create_instance("x", None).await,
            Err(MessagingProviderError::Unsupported(_))
        ));
        assert!(matches!(
            p.connect_instance("x", &t, &hook).await,
            Err(MessagingProviderError::Unsupported(_))
        ));
        assert!(matches!(
            p.disconnect_instance("x", &t).await,
            Err(MessagingProviderError::Unsupported(_))
        ));
        assert!(matches!(
            p.reconnect_instance("x", &t).await,
            Err(MessagingProviderError::Unsupported(_))
        ));
        assert!(matches!(
            p.list_all_instances().await,
            Err(MessagingProviderError::Unsupported(_))
        ));
    }
}
