//! Tipo agregador `AppError` — converte erros de crate em um tipo único
//! para uso na camada `application` e nos handlers gRPC.

use thiserror::Error;

use crate::code::ErrorCode;

/// Severidade do erro — determina o nível de log (`error!` vs `warn!`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Severity {
    /// Problema esperado / recuperável (ex.: recurso não encontrado, token expirado).
    Warn,
    /// Problema inesperado / crítico (ex.: falha de conexão, erro interno).
    Error,
}

/// Agregador de erros da aplicação.
///
/// Converte automaticamente os erros de crate de infraestrutura via `From<>`.
/// Usado em todo `Result<_, AppError>` na camada `application` e nos apps.
///
/// **Nunca** expor detalhes internos ao cliente — use `public_message()`.
#[derive(Debug, Error)]
pub enum AppError {
    #[error("Erro de banco de dados: {0}")]
    Database(String),

    #[error("Erro de cache: {0}")]
    Cache(String),

    #[error("Erro de armazenamento: {0}")]
    Storage(String),

    #[error("Erro de autenticação: {0}")]
    Auth(String),

    #[error("Erro de validação: {0}")]
    Validation(String),

    #[error("Conflito de estado: {0}")]
    Conflict(String),

    #[error("Limite de requisições excedido: {0}")]
    RateLimit(String),

    #[error("Erro interno: {0}")]
    Internal(String),
}

// Nota: os `From<DbError>`, `From<RedisError>`, `From<StorageError>`, `From<AuthError>`
// são implementados aqui com stubs. Quando as crates existirem no workspace, os tipos
// concretos substituem os stubs e os `#[from]` podem ser usados diretamente via thiserror.
//
// Exemplo com crate real:
//
//   use infrastructure_postgres::DbError;
//
//   impl From<DbError> for AppError {
//       fn from(err: DbError) -> Self {
//           AppError::Database(err.to_string())
//       }
//   }

impl AppError {
    /// Código estável que identifica este erro em logs e métricas.
    pub fn code(&self) -> ErrorCode {
        match self {
            Self::Auth(msg) if msg.contains("expirado") || msg.contains("expired") => {
                ErrorCode::AuthExpiredToken
            }
            Self::Auth(msg) if msg.contains("ausente") || msg.contains("missing") => {
                ErrorCode::AuthMissingToken
            }
            Self::Auth(msg) if msg.contains("permissão") || msg.contains("scope") => {
                ErrorCode::AuthInsufficientScope
            }
            Self::Auth(_) => ErrorCode::AuthInvalidToken,

            Self::Database(msg) if msg.contains("conexão") || msg.contains("connection") => {
                ErrorCode::DbConnectionFailed
            }
            Self::Database(msg) if msg.contains("não encontrado") || msg.contains("not found") => {
                ErrorCode::DbRecordNotFound
            }
            Self::Database(msg) if msg.contains("constraint") || msg.contains("duplicado") => {
                ErrorCode::DbConstraintViolation
            }
            Self::Database(_) => ErrorCode::DbQueryFailed,

            Self::Cache(msg) if msg.contains("indisponível") || msg.contains("unavailable") => {
                ErrorCode::CacheUnavailable
            }
            Self::Cache(_) => ErrorCode::CacheKeyNotFound,

            Self::Storage(msg) if msg.contains("não encontrado") || msg.contains("not found") => {
                ErrorCode::StorageNotFound
            }
            Self::Storage(msg) if msg.contains("upload") => ErrorCode::StorageUploadFailed,
            Self::Storage(_) => ErrorCode::StorageDeleteFailed,

            Self::Validation(_) => ErrorCode::ValidationFailed,
            Self::Conflict(_) => ErrorCode::Conflict,
            Self::RateLimit(_) => ErrorCode::RateLimitExceeded,
            Self::Internal(_) => ErrorCode::InternalError,
        }
    }

    /// Severidade do erro — define o nível de log.
    pub fn severity(&self) -> Severity {
        match self {
            // Erros esperados / recuperáveis → Warn
            Self::Auth(_) | Self::Validation(_) | Self::Conflict(_) | Self::RateLimit(_) => {
                Severity::Warn
            }
            Self::Storage(msg) if msg.contains("não encontrado") => Severity::Warn,
            Self::Database(msg) if msg.contains("não encontrado") => Severity::Warn,
            Self::Cache(msg) if msg.contains("não encontrado") => Severity::Warn,

            // Falhas de infraestrutura e internos → Error
            _ => Severity::Error,
        }
    }

    /// Indica se o cliente pode tentar novamente.
    pub fn retryable(&self) -> bool {
        matches!(
            self.code(),
            ErrorCode::DbConnectionFailed
                | ErrorCode::CacheUnavailable
                | ErrorCode::StorageUploadFailed
                | ErrorCode::InternalError
        )
    }

    /// Mensagem segura para o cliente — **nunca** vaza detalhe interno, stack trace ou PII.
    pub fn public_message(&self) -> &str {
        match self {
            Self::Auth(_) => "Credencial inválida ou ausente.",
            Self::Database(msg) if msg.contains("não encontrado") || msg.contains("not found") => {
                "Recurso não encontrado."
            }
            Self::Database(_) => "Erro ao acessar o banco de dados.",
            Self::Cache(_) => "Erro ao acessar o cache.",
            Self::Storage(msg) if msg.contains("não encontrado") || msg.contains("not found") => {
                "Arquivo não encontrado."
            }
            Self::Storage(_) => "Erro ao acessar o armazenamento.",
            Self::Validation(_) => "Dados de entrada inválidos.",
            Self::Conflict(_) => "Conflito com o estado atual do recurso.",
            Self::RateLimit(_) => "Limite de requisições excedido. Tente novamente mais tarde.",
            Self::Internal(_) => "Erro interno do servidor.",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_app_error_codes() {
        // Valida mapeamento de código do AppError::Auth
        assert_eq!(
            AppError::Auth("token expirado".to_string()).code(),
            ErrorCode::AuthExpiredToken
        );
        assert_eq!(
            AppError::Auth("expired token".to_string()).code(),
            ErrorCode::AuthExpiredToken
        );
        assert_eq!(
            AppError::Auth("token ausente".to_string()).code(),
            ErrorCode::AuthMissingToken
        );
        assert_eq!(
            AppError::Auth("missing token".to_string()).code(),
            ErrorCode::AuthMissingToken
        );
        assert_eq!(
            AppError::Auth("permissão insuficiente".to_string()).code(),
            ErrorCode::AuthInsufficientScope
        );
        assert_eq!(
            AppError::Auth("scope insufficient".to_string()).code(),
            ErrorCode::AuthInsufficientScope
        );
        assert_eq!(
            AppError::Auth("outro erro".to_string()).code(),
            ErrorCode::AuthInvalidToken
        );

        // Valida mapeamento de código do AppError::Database
        assert_eq!(
            AppError::Database("conexão falhou".to_string()).code(),
            ErrorCode::DbConnectionFailed
        );
        assert_eq!(
            AppError::Database("connection error".to_string()).code(),
            ErrorCode::DbConnectionFailed
        );
        assert_eq!(
            AppError::Database("recurso não encontrado".to_string()).code(),
            ErrorCode::DbRecordNotFound
        );
        assert_eq!(
            AppError::Database("not found".to_string()).code(),
            ErrorCode::DbRecordNotFound
        );
        assert_eq!(
            AppError::Database("constraint violation".to_string()).code(),
            ErrorCode::DbConstraintViolation
        );
        assert_eq!(
            AppError::Database("registro duplicado".to_string()).code(),
            ErrorCode::DbConstraintViolation
        );
        assert_eq!(
            AppError::Database("outro".to_string()).code(),
            ErrorCode::DbQueryFailed
        );

        // Valida mapeamento de código do AppError::Cache
        assert_eq!(
            AppError::Cache("indisponível".to_string()).code(),
            ErrorCode::CacheUnavailable
        );
        assert_eq!(
            AppError::Cache("unavailable".to_string()).code(),
            ErrorCode::CacheUnavailable
        );
        assert_eq!(
            AppError::Cache("outro".to_string()).code(),
            ErrorCode::CacheKeyNotFound
        );

        // Valida mapeamento de código do AppError::Storage
        assert_eq!(
            AppError::Storage("não encontrado".to_string()).code(),
            ErrorCode::StorageNotFound
        );
        assert_eq!(
            AppError::Storage("not found".to_string()).code(),
            ErrorCode::StorageNotFound
        );
        assert_eq!(
            AppError::Storage("falha no upload".to_string()).code(),
            ErrorCode::StorageUploadFailed
        );
        assert_eq!(
            AppError::Storage("outro".to_string()).code(),
            ErrorCode::StorageDeleteFailed
        );

        // Valida outros enums
        assert_eq!(
            AppError::Validation("invalido".to_string()).code(),
            ErrorCode::ValidationFailed
        );
        assert_eq!(
            AppError::Conflict("conflito".to_string()).code(),
            ErrorCode::Conflict
        );
        assert_eq!(
            AppError::RateLimit("rate limit".to_string()).code(),
            ErrorCode::RateLimitExceeded
        );
        assert_eq!(
            AppError::Internal("erro".to_string()).code(),
            ErrorCode::InternalError
        );
    }

    #[test]
    fn test_app_error_severity() {
        // Valida severidades esperadas
        assert_eq!(
            AppError::Auth("invalido".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::Validation("erro".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::Conflict("conflito".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::RateLimit("excedido".to_string()).severity(),
            Severity::Warn
        );

        assert_eq!(
            AppError::Storage("não encontrado".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::Storage("upload falhou".to_string()).severity(),
            Severity::Error
        );

        assert_eq!(
            AppError::Database("não encontrado".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::Database("connection failed".to_string()).severity(),
            Severity::Error
        );

        assert_eq!(
            AppError::Cache("não encontrado".to_string()).severity(),
            Severity::Warn
        );
        assert_eq!(
            AppError::Cache("indisponível".to_string()).severity(),
            Severity::Error
        );
    }

    #[test]
    fn test_app_error_retryable() {
        // Valida se os erros marcados como retryable são reconhecidos
        assert!(AppError::Database("conexão falhou".to_string()).retryable());
        assert!(AppError::Cache("indisponível".to_string()).retryable());
        assert!(AppError::Storage("falha no upload".to_string()).retryable());
        assert!(AppError::Internal("erro".to_string()).retryable());

        assert!(!AppError::Auth("invalido".to_string()).retryable());
        assert!(!AppError::Validation("erro".to_string()).retryable());
    }

    #[test]
    fn test_app_error_public_message() {
        // Valida as mensagens públicas retornadas (que ocultam detalhes de infraestrutura)
        assert_eq!(
            AppError::Auth("segredo".to_string()).public_message(),
            "Credencial inválida ou ausente."
        );
        assert_eq!(
            AppError::Database("not found".to_string()).public_message(),
            "Recurso não encontrado."
        );
        assert_eq!(
            AppError::Database("segredo sql".to_string()).public_message(),
            "Erro ao acessar o banco de dados."
        );
        assert_eq!(
            AppError::Cache("segredo redis".to_string()).public_message(),
            "Erro ao acessar o cache."
        );
        assert_eq!(
            AppError::Storage("not found".to_string()).public_message(),
            "Arquivo não encontrado."
        );
        assert_eq!(
            AppError::Storage("segredo s3".to_string()).public_message(),
            "Erro ao acessar o armazenamento."
        );
        assert_eq!(
            AppError::Validation("erro".to_string()).public_message(),
            "Dados de entrada inválidos."
        );
        assert_eq!(
            AppError::Conflict("erro".to_string()).public_message(),
            "Conflito com o estado atual do recurso."
        );
        assert_eq!(
            AppError::RateLimit("erro".to_string()).public_message(),
            "Limite de requisições excedido. Tente novamente mais tarde."
        );
        assert_eq!(
            AppError::Internal("erro".to_string()).public_message(),
            "Erro interno do servidor."
        );
    }
}
