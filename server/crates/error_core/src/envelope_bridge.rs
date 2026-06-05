//! Ponte de conversão entre erros locais da aplicação e o envelope de erros do contrato.
//! Permite serializar e desserializar erros na fronteira de comunicação de serviços.

use crate::error::{AppError, Severity};
use crate::code::ErrorCategory;

impl AppError {
    /// Retorna a chave de internacionalização correspondente ao código do erro.
    pub fn i18n_key(&self) -> String {
        format!("errors.{}", self.code().to_string().to_lowercase().replace('_', "."))
    }

    /// Converte o erro nativo no envelope de fronteira (dado serializável).
    pub fn to_error_envelope(&self, trace_id: &str, source_svc: &str) -> contracts::ErrorEnvelope {
        let proto_category = match self.code().category() {
            ErrorCategory::Validation => contracts::ErrorCategory::Validation,
            ErrorCategory::Auth => contracts::ErrorCategory::Auth,
            ErrorCategory::Permission => contracts::ErrorCategory::Permission,
            ErrorCategory::Conflict => contracts::ErrorCategory::Conflict,
            ErrorCategory::NotFound => contracts::ErrorCategory::NotFound,
            ErrorCategory::RateLimit => contracts::ErrorCategory::RateLimit,
            ErrorCategory::Timeout => contracts::ErrorCategory::Timeout,
            ErrorCategory::Dependency => contracts::ErrorCategory::Dependency,
            ErrorCategory::Internal => contracts::ErrorCategory::Internal,
            ErrorCategory::Storage => contracts::ErrorCategory::NotFound,
            ErrorCategory::Database => contracts::ErrorCategory::Internal,
            ErrorCategory::Cache => contracts::ErrorCategory::Internal,
        };

        let proto_severity = match self.severity() {
            Severity::Warn => contracts::Severity::Warning,
            Severity::Error => contracts::Severity::Error,
        };

        contracts::ErrorEnvelope {
            code: self.code().to_string(),
            category: proto_category as i32,
            severity: proto_severity as i32,
            message: self.to_string(),
            user_message: self.i18n_key(),
            user_message_fallback: self.public_message().to_string(),
            retryable: self.retryable(),
            trace_id: trace_id.to_string(),
            source_svc: source_svc.to_string(),
            details: vec![contracts::KeyValue {
                key: "original_error".to_string(),
                value: self.to_string(),
            }],
            occurred_at: chrono::Utc::now().timestamp_millis(),
        }
    }

    /// Reconstrói um AppError equivalente a partir do envelope recebido de outro processo.
    pub fn from_envelope(env: &contracts::ErrorEnvelope) -> Self {
        let msg = env.message.clone();
        match env.code.as_str() {
            "AUTH_INVALID_TOKEN" => AppError::Auth(msg),
            "AUTH_EXPIRED_TOKEN" => AppError::Auth(msg),
            "AUTH_MISSING_TOKEN" => AppError::Auth(msg),
            "AUTH_INSUFFICIENT_SCOPE" => AppError::Auth(msg),

            "STORAGE_NOT_FOUND" => AppError::Storage(msg),
            "STORAGE_UPLOAD_FAILED" => AppError::Storage(msg),
            "STORAGE_DELETE_FAILED" => AppError::Storage(msg),

            "DB_CONNECTION_FAILED" => AppError::Database(msg),
            "DB_RECORD_NOT_FOUND" => AppError::Database(msg),
            "DB_CONSTRAINT_VIOLATION" => AppError::Database(msg),
            "DB_QUERY_FAILED" => AppError::Database(msg),

            "CACHE_UNAVAILABLE" => AppError::Cache(msg),
            "CACHE_KEY_NOT_FOUND" => AppError::Cache(msg),

            "VALIDATION_FAILED" => AppError::Validation(msg),
            "CONFLICT" => AppError::Conflict(msg),

            _ => AppError::Internal(msg),
        }
    }
}
