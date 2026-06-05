//! Taxonomia estável de códigos de erro da aplicação.
//! Cada código é serializável para string `SCREAMING_SNAKE_CASE` (uso em logs e métricas).

use serde::{Deserialize, Serialize};

/// Categoria de alto nível do erro — usada para agrupamento em métricas.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCategory {
    Auth,
    Storage,
    Database,
    Cache,
    Validation,
    Internal,
}

/// Código estável que identifica o erro de forma rastreável em logs, métricas e alertas.
///
/// Novos códigos devem ser adicionados aqui — **nunca** remover ou renomear existentes
/// sem deprecação explícita, pois clientes e alertas dependem dessas strings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    // Autenticação
    AuthInvalidToken,
    AuthExpiredToken,
    AuthMissingToken,
    AuthInsufficientScope,

    // Armazenamento (object storage)
    StorageNotFound,
    StorageUploadFailed,
    StorageDeleteFailed,

    // Banco de dados
    DbConnectionFailed,
    DbRecordNotFound,
    DbConstraintViolation,
    DbQueryFailed,

    // Cache
    CacheUnavailable,
    CacheKeyNotFound,

    // Validação
    ValidationFailed,

    // Conflito / negócio
    Conflict,
    RateLimitExceeded,

    // Catch-all
    InternalError,
}

impl ErrorCode {
    /// Retorna a categoria de alto nível do código.
    pub fn category(&self) -> ErrorCategory {
        match self {
            Self::AuthInvalidToken
            | Self::AuthExpiredToken
            | Self::AuthMissingToken
            | Self::AuthInsufficientScope => ErrorCategory::Auth,

            Self::StorageNotFound | Self::StorageUploadFailed | Self::StorageDeleteFailed => {
                ErrorCategory::Storage
            }

            Self::DbConnectionFailed
            | Self::DbRecordNotFound
            | Self::DbConstraintViolation
            | Self::DbQueryFailed => ErrorCategory::Database,

            Self::CacheUnavailable | Self::CacheKeyNotFound => ErrorCategory::Cache,

            Self::ValidationFailed => ErrorCategory::Validation,

            Self::Conflict | Self::RateLimitExceeded | Self::InternalError => {
                ErrorCategory::Internal
            }
        }
    }
}

use std::fmt;

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Self::AuthInvalidToken => "AUTH_INVALID_TOKEN",
            Self::AuthExpiredToken => "AUTH_EXPIRED_TOKEN",
            Self::AuthMissingToken => "AUTH_MISSING_TOKEN",
            Self::AuthInsufficientScope => "AUTH_INSUFFICIENT_SCOPE",
            Self::StorageNotFound => "STORAGE_NOT_FOUND",
            Self::StorageUploadFailed => "STORAGE_UPLOAD_FAILED",
            Self::StorageDeleteFailed => "STORAGE_DELETE_FAILED",
            Self::DbConnectionFailed => "DB_CONNECTION_FAILED",
            Self::DbRecordNotFound => "DB_RECORD_NOT_FOUND",
            Self::DbConstraintViolation => "DB_CONSTRAINT_VIOLATION",
            Self::DbQueryFailed => "DB_QUERY_FAILED",
            Self::CacheUnavailable => "CACHE_UNAVAILABLE",
            Self::CacheKeyNotFound => "CACHE_KEY_NOT_FOUND",
            Self::ValidationFailed => "VALIDATION_FAILED",
            Self::Conflict => "CONFLICT",
            Self::RateLimitExceeded => "RATE_LIMIT_EXCEEDED",
            Self::InternalError => "INTERNAL_ERROR",
        };
        write!(f, "{}", s)
    }
}


