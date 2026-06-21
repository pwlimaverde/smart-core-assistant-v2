//! Contrato genérico de mensageria (WhatsApp). Sem runtime, sem I/O, sem logs.
pub mod errors;

use async_trait::async_trait;
pub use errors::MessagingProviderError;
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

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MediaType {
    Image,
    Video,
    Audio,
    Document,
}

/// Fronteira única entre regra de negócio e provedor de WhatsApp.
#[async_trait]
pub trait MessagingProvider: Send + Sync {
    fn provider_name(&self) -> &'static str;
    async fn create_instance(
        &self,
        instance_name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError>;
    async fn delete_instance(&self, instance_name: &str) -> Result<(), MessagingProviderError>;
    async fn connect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError>;
    async fn disconnect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError>;
    async fn get_qr_code(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<String, MessagingProviderError>;
    async fn pair_by_phone(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        phone_number: &str,
    ) -> Result<String, MessagingProviderError>;
    async fn configure_webhook(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        webhook_url: &str,
        events: &[String],
    ) -> Result<(), MessagingProviderError>;
    async fn get_connection_state(
        &self,
        instance_name: &str,
    ) -> Result<ConnectionState, MessagingProviderError>;
    async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError>;
    async fn send_media(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        media_type: MediaType,
        media_url: &str,
        caption: Option<&str>,
    ) -> Result<SendMessageResult, MessagingProviderError>;
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}
