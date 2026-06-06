use error_core::{AppError, ErrorCode, Severity};

#[test]
fn test_app_error_code_mapping() {
    // Testando erros de Autenticação
    assert_eq!(
        AppError::Auth("token expired".to_owned()).code(),
        ErrorCode::AuthExpiredToken
    );
    assert_eq!(
        AppError::Auth("chave expirado".to_owned()).code(),
        ErrorCode::AuthExpiredToken
    );
    assert_eq!(
        AppError::Auth("token missing".to_owned()).code(),
        ErrorCode::AuthMissingToken
    );
    assert_eq!(
        AppError::Auth("token ausente".to_owned()).code(),
        ErrorCode::AuthMissingToken
    );
    assert_eq!(
        AppError::Auth("insufficient scope".to_owned()).code(),
        ErrorCode::AuthInsufficientScope
    );
    assert_eq!(
        AppError::Auth("sem permissão".to_owned()).code(),
        ErrorCode::AuthInsufficientScope
    );
    assert_eq!(
        AppError::Auth("invalid format".to_owned()).code(),
        ErrorCode::AuthInvalidToken
    );

    // Testando erros de Banco de Dados
    assert_eq!(
        AppError::Database("connection failed".to_owned()).code(),
        ErrorCode::DbConnectionFailed
    );
    assert_eq!(
        AppError::Database("falha de conexão".to_owned()).code(),
        ErrorCode::DbConnectionFailed
    );
    assert_eq!(
        AppError::Database("record not found".to_owned()).code(),
        ErrorCode::DbRecordNotFound
    );
    assert_eq!(
        AppError::Database("não encontrado".to_owned()).code(),
        ErrorCode::DbRecordNotFound
    );
    assert_eq!(
        AppError::Database("constraint violation".to_owned()).code(),
        ErrorCode::DbConstraintViolation
    );
    assert_eq!(
        AppError::Database("registro duplicado".to_owned()).code(),
        ErrorCode::DbConstraintViolation
    );
    assert_eq!(
        AppError::Database("select error".to_owned()).code(),
        ErrorCode::DbQueryFailed
    );

    // Testando erros de Cache
    assert_eq!(
        AppError::Cache("redis unavailable".to_owned()).code(),
        ErrorCode::CacheUnavailable
    );
    assert_eq!(
        AppError::Cache("indisponível".to_owned()).code(),
        ErrorCode::CacheUnavailable
    );
    assert_eq!(
        AppError::Cache("key missing".to_owned()).code(),
        ErrorCode::CacheKeyNotFound
    );

    // Testando erros de Armazenamento
    assert_eq!(
        AppError::Storage("file not found".to_owned()).code(),
        ErrorCode::StorageNotFound
    );
    assert_eq!(
        AppError::Storage("não encontrado".to_owned()).code(),
        ErrorCode::StorageNotFound
    );
    assert_eq!(
        AppError::Storage("upload failed".to_owned()).code(),
        ErrorCode::StorageUploadFailed
    );
    assert_eq!(
        AppError::Storage("delete failed".to_owned()).code(),
        ErrorCode::StorageDeleteFailed
    );

    // Testando outros erros
    assert_eq!(
        AppError::Validation("invalid email".to_owned()).code(),
        ErrorCode::ValidationFailed
    );
    assert_eq!(
        AppError::Conflict("already exists".to_owned()).code(),
        ErrorCode::Conflict
    );
    assert_eq!(
        AppError::Internal("something broke".to_owned()).code(),
        ErrorCode::InternalError
    );
}

#[test]
fn test_app_error_severity() {
    // Valida se os erros esperados possuem severidade Warn e erros críticos possuem severidade Error.
    assert_eq!(
        AppError::Auth("invalid token".to_owned()).severity(),
        Severity::Warn
    );
    assert_eq!(
        AppError::Validation("bad input".to_owned()).severity(),
        Severity::Warn
    );
    assert_eq!(
        AppError::Conflict("conflict state".to_owned()).severity(),
        Severity::Warn
    );
    assert_eq!(
        AppError::Database("não encontrado".to_owned()).severity(),
        Severity::Warn
    );
    assert_eq!(
        AppError::Storage("não encontrado".to_owned()).severity(),
        Severity::Warn
    );
    assert_eq!(
        AppError::Cache("não encontrado".to_owned()).severity(),
        Severity::Warn
    );

    assert_eq!(
        AppError::Database("connection lost".to_owned()).severity(),
        Severity::Error
    );
    assert_eq!(
        AppError::Internal("fatal crash".to_owned()).severity(),
        Severity::Error
    );
    assert_eq!(
        AppError::Cache("indisponível".to_owned()).severity(),
        Severity::Error
    );
}

#[test]
fn test_app_error_retryable() {
    // Valida se a sinalização de retentativa corresponde ao código correto.
    assert!(AppError::Database("connection failed".to_owned()).retryable());
    assert!(AppError::Cache("indisponível".to_owned()).retryable());
    assert!(AppError::Storage("upload failed".to_owned()).retryable());
    assert!(AppError::Internal("error".to_owned()).retryable());

    assert!(!AppError::Auth("invalid".to_owned()).retryable());
    assert!(!AppError::Validation("bad".to_owned()).retryable());
    assert!(!AppError::Conflict("dup".to_owned()).retryable());
}

#[test]
fn test_app_error_public_message() {
    // Garante que mensagens públicas são seguras e omitam detalhes internos.
    assert_eq!(
        AppError::Auth("secret user pass error".to_owned()).public_message(),
        "Credencial inválida ou ausente."
    );
    assert_eq!(
        AppError::Database("não encontrado".to_owned()).public_message(),
        "Recurso não encontrado."
    );
    assert_eq!(
        AppError::Database("SELECT * FROM users WHERE password = '123'".to_owned())
            .public_message(),
        "Erro ao acessar o banco de dados."
    );
    assert_eq!(
        AppError::Validation("username must be non-empty".to_owned()).public_message(),
        "Dados de entrada inválidos."
    );
    assert_eq!(
        AppError::Internal("Null pointer in core library".to_owned()).public_message(),
        "Erro interno do servidor."
    );
}
