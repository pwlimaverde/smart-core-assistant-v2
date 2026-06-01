use thiserror::Error;

/// Único enum de erro exposto pela crate de persistência.
#[derive(Debug, Error)]
pub enum DbError {
    #[error("erro do banco de dados: {0}")]
    SqlxError(#[from] sqlx::Error),

    #[error("erro de migração: {0}")]
    MigrateError(#[from] sqlx::migrate::MigrateError),

    #[error("permissão negada para a operação solicitada")]
    PermissionDenied,

    #[error("registro não encontrado")]
    NotFound,

    #[error("violação de restrição de unicidade: {0}")]
    UniqueViolation(String),

    #[error("erro de criptografia: {0}")]
    CryptoError(String),

    #[error("erro de configuração: {0}")]
    ConfigError(String),
}

impl DbError {
    /// Converte erros de constraint do PostgreSQL em variantes semânticas.
    pub fn from_sqlx_unique(e: sqlx::Error) -> Self {
        if let sqlx::Error::Database(ref db_err) = e {
            if db_err.code().as_deref() == Some("23505") {
                return Self::UniqueViolation(db_err.message().to_string());
            }
        }
        Self::SqlxError(e)
    }
}
