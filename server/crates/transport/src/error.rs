// transport/src/error.rs  (comentários em pt-br)
use thiserror::Error;

#[derive(Debug, Error)]
pub enum TransportError {
    #[error("Conexão fechada")]
    Closed,

    #[error("Operação expirou (timeout)")]
    Timeout,

    #[error("Erro de E/S: {0}")]
    Io(#[from] std::io::Error),

    #[error("Erro de codificação/decodificação: {0}")]
    Codec(String),

    #[error("Erro de canal de comunicação interno: {0}")]
    InternalChannel(String),

    #[error("Erro no bus (Redis): {0}")]
    Bus(String),
}
