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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_db_error_display() {
        let err = DbError::PermissionDenied;
        assert_eq!(
            err.to_string(),
            "permissão negada para a operação solicitada"
        );

        let err = DbError::NotFound;
        assert_eq!(err.to_string(), "registro não encontrado");

        let err = DbError::UniqueViolation("campo duplicado".into());
        assert_eq!(
            err.to_string(),
            "violação de restrição de unicidade: campo duplicado"
        );

        let err = DbError::CryptoError("falha na tag".into());
        assert_eq!(err.to_string(), "erro de criptografia: falha na tag");

        let err = DbError::ConfigError("porta inválida".into());
        assert_eq!(err.to_string(), "erro de configuração: porta inválida");
    }

    #[test]
    fn test_db_error_from_sqlx_non_unique() {
        let sqlx_err = sqlx::Error::RowNotFound;
        let db_err = DbError::from_sqlx_unique(sqlx_err);
        match db_err {
            DbError::SqlxError(sqlx::Error::RowNotFound) => {}
            _ => panic!("Esperado DbError::SqlxError(RowNotFound)"),
        }
    }
}
