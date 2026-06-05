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
            Self::Internal(_) => ErrorCode::InternalError,
        }
    }

    /// Severidade do erro — define o nível de log.
    pub fn severity(&self) -> Severity {
        match self {
            // Erros esperados / recuperáveis → Warn
            Self::Auth(_) | Self::Validation(_) | Self::Conflict(_) => Severity::Warn,
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
            Self::Database(msg) if msg.contains("não encontrado") || msg.contains("not found") => "Recurso não encontrado.",
            Self::Database(_) => "Erro ao acessar o banco de dados.",
            Self::Cache(_) => "Erro ao acessar o cache.",
            Self::Storage(msg) if msg.contains("não encontrado") || msg.contains("not found") => "Arquivo não encontrado.",
            Self::Storage(_) => "Erro ao acessar o armazenamento.",
            Self::Validation(_) => "Dados de entrada inválidos.",
            Self::Conflict(_) => "Conflito com o estado atual do recurso.",
            Self::Internal(_) => "Erro interno do servidor.",
        }
    }
}


