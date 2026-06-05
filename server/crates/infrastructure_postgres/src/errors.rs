use error_core::{AppError, ErrorCode};
use thiserror::Error;

/// Único enum de erro exposto pela crate de persistência.
///
/// É o erro **específico** desta camada, mas todo `DbError` deriva do núcleo
/// (`error_core`): expõe um [`ErrorCode`] estável via [`DbError::code`] e converte
/// para [`AppError`] via `From`, padronizando os dados de erro em todo o workspace.
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

    /// Código estável do núcleo (`error_core`) que identifica este erro de forma
    /// rastreável em logs, métricas e alertas. É a fonte autoritativa da classificação
    /// (sem depender de casamento de string), e mantém-se coerente com a conversão
    /// para [`AppError`].
    pub fn code(&self) -> ErrorCode {
        match self {
            Self::SqlxError(e) => classificar_sqlx(e),
            Self::MigrateError(_) => ErrorCode::DbQueryFailed,
            // Guarda de autorização RLS: o tenant não é dono do recurso.
            Self::PermissionDenied => ErrorCode::AuthInsufficientScope,
            Self::NotFound => ErrorCode::DbRecordNotFound,
            Self::UniqueViolation(_) => ErrorCode::DbConstraintViolation,
            Self::CryptoError(_) | Self::ConfigError(_) => ErrorCode::InternalError,
        }
    }
}

/// Classifica um [`sqlx::Error`] no [`ErrorCode`] do núcleo.
fn classificar_sqlx(e: &sqlx::Error) -> ErrorCode {
    match e {
        sqlx::Error::RowNotFound => ErrorCode::DbRecordNotFound,
        // Falhas de pool/IO indicam indisponibilidade de conexão (são retryable).
        sqlx::Error::PoolTimedOut | sqlx::Error::PoolClosed | sqlx::Error::Io(_) => {
            ErrorCode::DbConnectionFailed
        }
        // SQLSTATE classe 23 = violação de integridade (unique/foreign key/check).
        sqlx::Error::Database(db_err)
            if db_err.code().as_deref().is_some_and(|c| c.starts_with("23")) =>
        {
            ErrorCode::DbConstraintViolation
        }
        _ => ErrorCode::DbQueryFailed,
    }
}

/// Ponte para o agregador do núcleo. A mensagem é construída de modo que
/// `AppError::code()` reclassifique para o **mesmo** [`ErrorCode`] de [`DbError::code`],
/// garantindo coerência ponta a ponta.
impl From<DbError> for AppError {
    fn from(err: DbError) -> Self {
        match err.code() {
            ErrorCode::DbRecordNotFound => AppError::Database("registro não encontrado".into()),
            ErrorCode::DbConnectionFailed => {
                AppError::Database(format!("falha de conexão: {err}"))
            }
            ErrorCode::DbConstraintViolation => {
                AppError::Database(format!("violação de constraint: {err}"))
            }
            ErrorCode::AuthInsufficientScope => {
                AppError::Auth("permissão negada para a operação solicitada".into())
            }
            ErrorCode::InternalError => AppError::Internal(err.to_string()),
            // Demais falhas de banco caem em consulta genérica.
            _ => AppError::Database(err.to_string()),
        }
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

    /// Cada variante deve expor o `ErrorCode` esperado do núcleo.
    #[test]
    fn test_db_error_code_mapeia_para_core() {
        assert_eq!(
            DbError::PermissionDenied.code(),
            ErrorCode::AuthInsufficientScope
        );
        assert_eq!(DbError::NotFound.code(), ErrorCode::DbRecordNotFound);
        assert_eq!(
            DbError::UniqueViolation("x".into()).code(),
            ErrorCode::DbConstraintViolation
        );
        assert_eq!(
            DbError::CryptoError("x".into()).code(),
            ErrorCode::InternalError
        );
        assert_eq!(
            DbError::ConfigError("x".into()).code(),
            ErrorCode::InternalError
        );
        assert_eq!(
            DbError::SqlxError(sqlx::Error::RowNotFound).code(),
            ErrorCode::DbRecordNotFound
        );
        assert_eq!(
            DbError::SqlxError(sqlx::Error::PoolTimedOut).code(),
            ErrorCode::DbConnectionFailed
        );
    }

    /// A conversão para `AppError` deve preservar o `ErrorCode` (coerência ponta a ponta).
    #[test]
    fn test_db_error_para_app_error_preserva_code() {
        let casos = [
            DbError::PermissionDenied,
            DbError::NotFound,
            DbError::UniqueViolation("dup".into()),
            DbError::CryptoError("falha".into()),
            DbError::ConfigError("cfg".into()),
            DbError::SqlxError(sqlx::Error::RowNotFound),
            DbError::SqlxError(sqlx::Error::PoolTimedOut),
        ];
        for caso in casos {
            let code_origem = caso.code();
            let app: AppError = caso.into();
            assert_eq!(
                app.code(),
                code_origem,
                "AppError::code() divergiu de DbError::code() para {code_origem}"
            );
        }
    }
}
