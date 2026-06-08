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
    Permission,
    RateLimit,
    Timeout,
    Dependency,
    NotFound,
    Conflict,
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

            Self::Conflict => ErrorCategory::Conflict,
            Self::RateLimitExceeded => ErrorCategory::RateLimit,
            Self::InternalError => ErrorCategory::Internal,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_and_deserializes_all_error_categories() {
        // Lista todas as variantes de ErrorCategory para validar a serialização/desserialização
        let categorias = vec![
            (ErrorCategory::Auth, "\"AUTH\""),
            (ErrorCategory::Storage, "\"STORAGE\""),
            (ErrorCategory::Database, "\"DATABASE\""),
            (ErrorCategory::Cache, "\"CACHE\""),
            (ErrorCategory::Validation, "\"VALIDATION\""),
            (ErrorCategory::Internal, "\"INTERNAL\""),
            (ErrorCategory::Permission, "\"PERMISSION\""),
            (ErrorCategory::RateLimit, "\"RATE_LIMIT\""),
            (ErrorCategory::Timeout, "\"TIMEOUT\""),
            (ErrorCategory::Dependency, "\"DEPENDENCY\""),
            (ErrorCategory::NotFound, "\"NOT_FOUND\""),
            (ErrorCategory::Conflict, "\"CONFLICT\""),
        ];

        for (categoria, json_esperado) in categorias {
            // Act — Serialização
            let json = serde_json::to_string(&categoria).unwrap();
            // Assert — Serialização
            assert_eq!(json, json_esperado);

            // Act — Desserialização
            let decoded: ErrorCategory = serde_json::from_str(json_esperado).unwrap();
            // Assert — Desserialização
            assert_eq!(decoded, categoria);
        }
    }

    #[test]
    fn serializes_and_deserializes_error_code() {
        // Arrange
        let code = ErrorCode::AuthInvalidToken;
        // Act
        let json = serde_json::to_string(&code).unwrap();
        // Assert
        assert_eq!(json, "\"AUTH_INVALID_TOKEN\"");

        // Act
        let decoded: ErrorCode = serde_json::from_str("\"AUTH_INVALID_TOKEN\"").unwrap();
        // Assert
        assert_eq!(decoded, ErrorCode::AuthInvalidToken);
    }

    #[test]
    fn maps_each_error_code_to_its_correct_high_level_category() {
        // Valida se cada código mapeia para a categoria esperada (100% dos ramos do match)
        assert_eq!(ErrorCode::AuthInvalidToken.category(), ErrorCategory::Auth);
        assert_eq!(ErrorCode::AuthExpiredToken.category(), ErrorCategory::Auth);
        assert_eq!(ErrorCode::AuthMissingToken.category(), ErrorCategory::Auth);
        assert_eq!(
            ErrorCode::AuthInsufficientScope.category(),
            ErrorCategory::Auth
        );

        assert_eq!(
            ErrorCode::StorageNotFound.category(),
            ErrorCategory::Storage
        );
        assert_eq!(
            ErrorCode::StorageUploadFailed.category(),
            ErrorCategory::Storage
        );
        assert_eq!(
            ErrorCode::StorageDeleteFailed.category(),
            ErrorCategory::Storage
        );

        assert_eq!(
            ErrorCode::DbConnectionFailed.category(),
            ErrorCategory::Database
        );
        assert_eq!(
            ErrorCode::DbRecordNotFound.category(),
            ErrorCategory::Database
        );
        assert_eq!(
            ErrorCode::DbConstraintViolation.category(),
            ErrorCategory::Database
        );
        assert_eq!(ErrorCode::DbQueryFailed.category(), ErrorCategory::Database);

        assert_eq!(ErrorCode::CacheUnavailable.category(), ErrorCategory::Cache);
        assert_eq!(ErrorCode::CacheKeyNotFound.category(), ErrorCategory::Cache);

        assert_eq!(
            ErrorCode::ValidationFailed.category(),
            ErrorCategory::Validation
        );
        assert_eq!(ErrorCode::Conflict.category(), ErrorCategory::Conflict);
        assert_eq!(
            ErrorCode::RateLimitExceeded.category(),
            ErrorCategory::RateLimit
        );
        assert_eq!(ErrorCode::InternalError.category(), ErrorCategory::Internal);
    }

    #[test]
    fn formats_each_error_code_correctly_as_screaming_snake_case_string() {
        // Valida a formatação de string (Display) de todos os códigos de erro
        assert_eq!(
            ErrorCode::AuthInvalidToken.to_string(),
            "AUTH_INVALID_TOKEN"
        );
        assert_eq!(
            ErrorCode::AuthExpiredToken.to_string(),
            "AUTH_EXPIRED_TOKEN"
        );
        assert_eq!(
            ErrorCode::AuthMissingToken.to_string(),
            "AUTH_MISSING_TOKEN"
        );
        assert_eq!(
            ErrorCode::AuthInsufficientScope.to_string(),
            "AUTH_INSUFFICIENT_SCOPE"
        );
        assert_eq!(ErrorCode::StorageNotFound.to_string(), "STORAGE_NOT_FOUND");
        assert_eq!(
            ErrorCode::StorageUploadFailed.to_string(),
            "STORAGE_UPLOAD_FAILED"
        );
        assert_eq!(
            ErrorCode::StorageDeleteFailed.to_string(),
            "STORAGE_DELETE_FAILED"
        );
        assert_eq!(
            ErrorCode::DbConnectionFailed.to_string(),
            "DB_CONNECTION_FAILED"
        );
        assert_eq!(
            ErrorCode::DbRecordNotFound.to_string(),
            "DB_RECORD_NOT_FOUND"
        );
        assert_eq!(
            ErrorCode::DbConstraintViolation.to_string(),
            "DB_CONSTRAINT_VIOLATION"
        );
        assert_eq!(ErrorCode::DbQueryFailed.to_string(), "DB_QUERY_FAILED");
        assert_eq!(ErrorCode::CacheUnavailable.to_string(), "CACHE_UNAVAILABLE");
        assert_eq!(
            ErrorCode::CacheKeyNotFound.to_string(),
            "CACHE_KEY_NOT_FOUND"
        );
        assert_eq!(ErrorCode::ValidationFailed.to_string(), "VALIDATION_FAILED");
        assert_eq!(ErrorCode::Conflict.to_string(), "CONFLICT");
        assert_eq!(
            ErrorCode::RateLimitExceeded.to_string(),
            "RATE_LIMIT_EXCEEDED"
        );
        assert_eq!(ErrorCode::InternalError.to_string(), "INTERNAL_ERROR");
    }
}
