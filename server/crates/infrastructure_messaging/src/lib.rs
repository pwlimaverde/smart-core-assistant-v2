//! Contrato genérico de mensageria por canal. Sem runtime, sem I/O, sem logs.
//!
//! Núcleo obrigatório de todo canal: [`ChannelLifecycle`] (ciclo de vida da
//! conexão) + [`MessageSender`] (envio) + o [`ChannelDescriptor`] que o
//! provedor declara. Tudo o mais — QR, conexão por credenciais, presença,
//! recibos, reações, mídia — é capacidade opcional descoberta pela fachada
//! [`MessagingProvider`], com `None` como padrão. Ver o guia em
//! `doc_dev/arquitetura/guia-novo-provedor-de-canal.md`.
pub mod canal;
pub mod errors;
pub mod registry;

pub use canal::{
    catalogo_planejado, descritor_efetivo, CampoConfiguracao, Capacidade, ChannelDescriptor,
    ChannelKind, ConnectionMode, EnderecoNoProvedor, Estagio, TipoCampo,
};

use async_trait::async_trait;
pub use errors::MessagingProviderError;
pub use registry::{ProviderRegistry, ProviderRegistryBuilder};
use secrecy::SecretString;

/// Estado de conexão normalizado (independente de provedor).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState {
    Connected,
    Disconnected,
    Connecting,
    Unknown,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreateInstanceResult {
    pub provider_instance_id: String,
    pub instance_token: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SendMessageResult {
    pub message_id: String,
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum MediaType {
    Image,
    Video,
    Audio,
    Document,
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PresenceState {
    Composing,
    Recording,
    Paused,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MediaDownloadResult {
    pub base64: String,
    pub mime_type: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WebhookConfig {
    pub url: String,
    pub subscribe: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AdvancedSettings {
    pub always_online: bool, // true: mantém sessão whatsmeow viva
    pub read_messages: bool, // false: recibo explícito via markread
    pub reject_call: bool,
    pub msg_reject_call: String,
    pub ignore_groups: bool,
    pub ignore_status: bool,
}

impl Default for AdvancedSettings {
    fn default() -> Self {
        Self {
            always_online: true,
            read_messages: false,
            reject_call: false,
            msg_reject_call: String::new(),
            ignore_groups: false,
            ignore_status: false,
        }
    }
}

// ---------- Núcleo OBRIGATÓRIO ----------
/// Ciclo de vida da conexão no provedor. `ChannelLifecycle` é o nome genérico
/// (contrato de canal); `InstanceManager` fica como nome histórico, porque é
/// assim que os adaptadores e testes já o implementam.
///
/// Provedor que não tem uma operação devolve
/// [`MessagingProviderError::Unsupported`] — nunca `Ok` de mentira. Quem chama
/// consulta o descritor antes, e o erro é a rede de segurança.
#[async_trait]
pub trait InstanceManager: Send + Sync {
    fn provider_name(&self) -> &'static str;
    async fn create_instance(
        &self,
        name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError>;
    async fn delete_instance(&self, name: &str) -> Result<(), MessagingProviderError>;
    async fn connect_instance(
        &self,
        name: &str,
        token: &SecretString,
        webhook: &WebhookConfig,
    ) -> Result<(), MessagingProviderError>;
    async fn disconnect_instance(
        &self,
        name: &str,
        token: &SecretString,
    ) -> Result<(), MessagingProviderError>;
    async fn reconnect_instance(
        &self,
        name: &str,
        token: &SecretString,
    ) -> Result<(), MessagingProviderError>;
    async fn get_connection_state(
        &self,
        name: &str,
        token: &SecretString,
    ) -> Result<ConnectionState, MessagingProviderError>;
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}

// P2b: `send_media` passou a levar o nome do arquivo; a assinatura espelha o
// corpo do `/send/media` do provedor, por isso a lista larga de argumentos.
#[allow(clippy::too_many_arguments)]
#[async_trait]
pub trait MessageSender: Send + Sync {
    async fn send_text(
        &self,
        name: &str,
        token: &SecretString,
        to: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError>;
    async fn send_media(
        &self,
        name: &str,
        token: &SecretString,
        to: &str,
        media: MediaType,
        url: &str,
        caption: Option<&str>,
        // P2b: nome exibido ao destinatário; o provedor só o usa em documento.
        file_name: Option<&str>,
    ) -> Result<SendMessageResult, MessagingProviderError>;
}

pub use InstanceManager as ChannelLifecycle;

/// Uma credencial digitada no formulário do provedor (`config_schema`).
pub struct CredencialInformada {
    pub chave: String,
    pub valor: SecretString,
}

/// Uma conexão aceita pelo provedor a partir de credenciais.
pub struct CanalConectado {
    /// Id da conexão no provedor (o `phone_number_id` na Cloud API). Vai para
    /// `whatsapp_instance.instance_id` e é a chave de roteamento do webhook.
    pub id_externo: String,
    pub telefone: Option<String>,
    pub nome_exibicao: Option<String>,
    /// O que o adaptador recebe como `token` nas próximas chamadas. Vai cifrado
    /// para `whatsapp_instance.api_key`.
    pub token: SecretString,
    /// Configuração NÃO secreta do provedor (ex.: `waba_id`). Vai para
    /// `whatsapp_instance.provider_config`.
    pub config: serde_json::Value,
}

// ---------- Capacidades OPCIONAIS ----------

/// Pareamento por QR (Evolution Go). Pedir o QR pode reiniciar o cliente no
/// provedor — quem chama controla a frequência (ver o cache do `data_whatsapp`).
#[async_trait]
pub trait QrPairing: Send + Sync {
    async fn get_qr_code(
        &self,
        name: &str,
        token: &SecretString,
    ) -> Result<String, MessagingProviderError>;
}

/// Conexão por credenciais (Cloud API da Meta, bot do Telegram). O adaptador
/// VALIDA as credenciais no provedor antes de devolver: credencial errada é
/// erro aqui, não uma conexão morta gravada no banco.
#[async_trait]
pub trait TokenConnect: Send + Sync {
    async fn conectar_com_credenciais(
        &self,
        campos: &[CredencialInformada],
    ) -> Result<CanalConectado, MessagingProviderError>;
}

#[async_trait]
pub trait PresenceControl: Send + Sync {
    async fn set_presence(
        &self,
        name: &str,
        token: &SecretString,
        chat: &str,
        state: PresenceState,
        is_audio: bool,
    ) -> Result<(), MessagingProviderError>;
}

#[async_trait]
pub trait ReadReceipts: Send + Sync {
    async fn mark_read(
        &self,
        name: &str,
        token: &SecretString,
        chat: &str,
        message_ids: &[String],
    ) -> Result<(), MessagingProviderError>;
}

#[async_trait]
pub trait Reactions: Send + Sync {
    async fn send_reaction(
        &self,
        name: &str,
        token: &SecretString,
        chat: &str,
        message_id: &str,
        emoji: &str,
        from_me: bool,
    ) -> Result<SendMessageResult, MessagingProviderError>;
}

#[async_trait]
pub trait MediaDownloader: Send + Sync {
    async fn download_media(
        &self,
        name: &str,
        token: &SecretString,
        message: &serde_json::Value,
    ) -> Result<MediaDownloadResult, MessagingProviderError>;
}

#[async_trait]
pub trait ProfileQuery: Send + Sync {
    async fn get_profile_picture(
        &self,
        name: &str,
        token: &SecretString,
        number: &str,
    ) -> Result<Option<String>, MessagingProviderError>;
}

#[async_trait]
pub trait AdvancedSettingsControl: Send + Sync {
    async fn set_advanced_settings(
        &self,
        instance_id: &str,
        token: &SecretString,
        settings: AdvancedSettings,
    ) -> Result<(), MessagingProviderError>;
}

// ---------- Fachada: núcleo + DESCOBERTA de capacidades (default None) ----------
pub trait MessagingProvider: InstanceManager + MessageSender {
    /// O que o provedor declara de si. Obrigatório: sem descritor a tela não
    /// sabe como conectar. A borda usa [`descritor_efetivo`], que corrige as
    /// capacidades opcionais pelo que os traits realmente implementam.
    fn descritor(&self) -> ChannelDescriptor;
    fn qr_pairing(&self) -> Option<&dyn QrPairing> {
        None
    }
    fn token_connect(&self) -> Option<&dyn TokenConnect> {
        None
    }
    fn presence(&self) -> Option<&dyn PresenceControl> {
        None
    }
    fn read_receipts(&self) -> Option<&dyn ReadReceipts> {
        None
    }
    fn reactions(&self) -> Option<&dyn Reactions> {
        None
    }
    fn media_downloader(&self) -> Option<&dyn MediaDownloader> {
        None
    }
    fn profiles(&self) -> Option<&dyn ProfileQuery> {
        None
    }
    fn advanced_settings(&self) -> Option<&dyn AdvancedSettingsControl> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_state_serialization() {
        let cases = vec![
            (ConnectionState::Connected, "\"connected\""),
            (ConnectionState::Disconnected, "\"disconnected\""),
            (ConnectionState::Connecting, "\"connecting\""),
            (ConnectionState::Unknown, "\"unknown\""),
        ];

        for (state, json) in cases {
            let serialized = serde_json::to_string(&state).unwrap();
            assert_eq!(serialized, json);

            let deserialized: ConnectionState = serde_json::from_str(json).unwrap();
            assert_eq!(deserialized, state);
        }
    }

    #[test]
    fn test_media_type_serialization() {
        let cases = vec![
            (MediaType::Image, "\"image\""),
            (MediaType::Video, "\"video\""),
            (MediaType::Audio, "\"audio\""),
            (MediaType::Document, "\"document\""),
        ];

        for (media, json) in cases {
            let serialized = serde_json::to_string(&media).unwrap();
            assert_eq!(serialized, json);

            let deserialized: MediaType = serde_json::from_str(json).unwrap();
            let serialized_back = serde_json::to_string(&deserialized).unwrap();
            assert_eq!(serialized_back, json);
        }
    }

    #[test]
    fn test_presence_state_serialization() {
        let cases = vec![
            (PresenceState::Composing, "\"composing\""),
            (PresenceState::Recording, "\"recording\""),
            (PresenceState::Paused, "\"paused\""),
        ];

        for (presence, json) in cases {
            let serialized = serde_json::to_string(&presence).unwrap();
            assert_eq!(serialized, json);

            let deserialized: PresenceState = serde_json::from_str(json).unwrap();
            let serialized_back = serde_json::to_string(&deserialized).unwrap();
            assert_eq!(serialized_back, json);
        }
    }

    #[test]
    fn test_error_formatting() {
        let err = MessagingProviderError::Network("falha de rede".to_string());
        assert_eq!(
            err.to_string(),
            "Erro de conexão/rede no provedor: falha de rede"
        );

        let err = MessagingProviderError::ProviderApi {
            status: 400,
            body: "bad request".to_string(),
        };
        assert_eq!(
            err.to_string(),
            "O provedor retornou erro HTTP (status 400): bad request"
        );

        let err = MessagingProviderError::Deserialization("invalid json".to_string());
        assert_eq!(
            err.to_string(),
            "Falha ao processar resposta do provedor: invalid json"
        );

        let err = MessagingProviderError::Config("url invalida".to_string());
        assert_eq!(
            err.to_string(),
            "Erro de configuração do provedor: url invalida"
        );

        let err = MessagingProviderError::InvalidState("ja conectado".to_string());
        assert_eq!(
            err.to_string(),
            "Operação inválida no estado atual: ja conectado"
        );

        let err = MessagingProviderError::Unsupported("reactions");
        assert_eq!(
            err.to_string(),
            "Operação não suportada pelo provedor: reactions"
        );
    }
}
