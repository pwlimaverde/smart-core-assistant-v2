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


