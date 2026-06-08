use error_core::{ErrorCategory, ErrorCode};

#[test]
fn error_code_formats_correctly_as_screaming_snake_case_string() {
    // Valida se a conversão do Display do ErrorCode retorna o formato SCREAMING_SNAKE_CASE correto.
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

#[test]
fn maps_each_error_code_to_its_correct_high_level_category() {
    // Valida se o agrupamento em categorias de erro está correto.
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
fn serializes_and_deserializes_error_codes_and_categories_correctly() {
    // Valida que a serialização em JSON de ErrorCode gera a string em SCREAMING_SNAKE_CASE esperada.
    let code = ErrorCode::AuthExpiredToken;
    let serialized = serde_json::to_string(&code).unwrap();
    assert_eq!(serialized, "\"AUTH_EXPIRED_TOKEN\"");

    let deserialized: ErrorCode = serde_json::from_str(&serialized).unwrap();
    assert_eq!(deserialized, ErrorCode::AuthExpiredToken);

    let category = ErrorCategory::Database;
    let serialized_cat = serde_json::to_string(&category).unwrap();
    assert_eq!(serialized_cat, "\"DATABASE\"");

    let deserialized_cat: ErrorCategory = serde_json::from_str(&serialized_cat).unwrap();
    assert_eq!(deserialized_cat, ErrorCategory::Database);
}
