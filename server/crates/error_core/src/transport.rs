//! Mapeamento de `AppError` para `tonic::Status` — usado na borda dos handlers gRPC.
//!
//! Habilitado apenas com a feature `grpc`. Quem não usa gRPC não carrega `tonic`.

#[cfg(feature = "grpc")]
use tonic::{Code, Status};

#[cfg(feature = "grpc")]
use crate::{code::ErrorCode, error::AppError};

/// Converte um `AppError` em `tonic::Status` para retorno nos handlers gRPC.
///
/// A mensagem do status usa `public_message()` — nunca detalhes internos.
#[cfg(feature = "grpc")]
pub fn to_status(err: &AppError) -> Status {
    let code = match err.code() {
        ErrorCode::AuthInvalidToken | ErrorCode::AuthExpiredToken | ErrorCode::AuthMissingToken => {
            Code::Unauthenticated
        }

        ErrorCode::AuthInsufficientScope => Code::PermissionDenied,

        ErrorCode::StorageNotFound | ErrorCode::DbRecordNotFound | ErrorCode::CacheKeyNotFound => {
            Code::NotFound
        }

        ErrorCode::DbConnectionFailed
        | ErrorCode::CacheUnavailable
        | ErrorCode::StorageUploadFailed
        | ErrorCode::StorageDeleteFailed
        | ErrorCode::DbQueryFailed
        | ErrorCode::InternalError => Code::Internal,

        ErrorCode::ValidationFailed => Code::InvalidArgument,

        ErrorCode::DbConstraintViolation | ErrorCode::Conflict => Code::AlreadyExists,

        ErrorCode::RateLimitExceeded => Code::ResourceExhausted,
    };

    Status::new(code, err.public_message())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tonic::Code;

    #[test]
    fn test_to_status_mapping() {
        // Unauthenticated
        let err = AppError::Auth("token expirado".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::Unauthenticated);
        assert_eq!(status.message(), err.public_message());

        // PermissionDenied
        let err = AppError::Auth("permissão insuficiente".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::PermissionDenied);

        // NotFound
        let err = AppError::Database("not found".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::NotFound);

        // Internal
        let err = AppError::Database("conexão falhou".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::Internal);

        // InvalidArgument
        let err = AppError::Validation("dados inválidos".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::InvalidArgument);

        // AlreadyExists
        let err = AppError::Database("constraint violation".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::AlreadyExists);

        // ResourceExhausted
        let err = AppError::RateLimit("limite de taxa excedido".to_string());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::ResourceExhausted);
        assert_eq!(status.message(), err.public_message());
    }
}


