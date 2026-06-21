#[derive(Debug, thiserror::Error)]
pub enum MessagingProviderError {
    #[error("Erro de conexão/rede no provedor: {0}")]
    Network(String),
    #[error("O provedor retornou erro HTTP (status {status}): {body}")]
    ProviderApi { status: u16, body: String },
    #[error("Falha ao processar resposta do provedor: {0}")]
    Deserialization(String),
    #[error("Erro de configuração do provedor: {0}")]
    Config(String),
    #[error("Operação inválida no estado atual: {0}")]
    InvalidState(String),
}
