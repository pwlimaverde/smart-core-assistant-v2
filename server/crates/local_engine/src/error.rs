//! Camada de erro client-local do `local_engine`.
//!
//! Deliberadamente **não** reexpõe o `error_core` do servidor: este crate roda
//! dentro do processo do app Flutter e tem um domínio de falha próprio (I/O de
//! disco, SQLite local, download de mídia, sync). Segue a mesma filosofia de
//! Result Pattern, mas com um `enum` enxuto e independente.

use thiserror::Error;

/// Falhas do motor local.
#[derive(Debug, Error)]
pub enum LocalEngineError {
    /// Falha no índice local (SQLite): abertura, migração ou query.
    #[error("erro de armazenamento local (SQLite): {0}")]
    Storage(String),

    /// Falha ao sincronizar a fila offline com o servidor.
    #[error("erro de sincronização com o servidor: {0}")]
    Sync(String),

    /// Registro ausente no índice local.
    #[error("recurso não encontrado no índice local: {0}")]
    NotFound(String),

    /// Falha de I/O no cache de mídia em disco.
    #[error("erro de I/O no cache local: {0}")]
    Io(String),

    /// Falha ao baixar ou validar a integridade de uma mídia.
    #[error("erro de mídia: {0}")]
    Media(String),
}

/// Alias de conveniência para resultados do crate.
pub type LocalResult<T> = Result<T, LocalEngineError>;

impl From<sqlx::Error> for LocalEngineError {
    fn from(e: sqlx::Error) -> Self {
        match e {
            sqlx::Error::RowNotFound => LocalEngineError::NotFound("linha inexistente".to_string()),
            outro => LocalEngineError::Storage(outro.to_string()),
        }
    }
}

impl From<sqlx::migrate::MigrateError> for LocalEngineError {
    fn from(e: sqlx::migrate::MigrateError) -> Self {
        LocalEngineError::Storage(format!("migração: {e}"))
    }
}

impl From<std::io::Error> for LocalEngineError {
    fn from(e: std::io::Error) -> Self {
        LocalEngineError::Io(e.to_string())
    }
}
