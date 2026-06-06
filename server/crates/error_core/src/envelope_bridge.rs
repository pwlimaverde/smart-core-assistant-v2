//! Ponte de conversão entre erros locais da aplicação e o envelope de erros do contrato.
//! Permite serializar e desserializar erros na fronteira de comunicação de serviços.

use crate::code::ErrorCategory;
use crate::error::{AppError, Severity};

impl AppError {
    /// Retorna a chave de internacionalização correspondente ao código do erro.
    pub fn i18n_key(&self) -> String {
        format!(
            "errors.{}",
            self.code().to_string().to_lowercase().replace('_', ".")
        )
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
            "RATE_LIMIT_EXCEEDED" => AppError::RateLimit(msg),

            _ => AppError::Internal(msg),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{ErrorCategory as ProtoCategory, Severity as ProtoSeverity};

    #[test]
    fn test_i18n_keys() {
        assert_eq!(AppError::Auth("token expirado".to_string()).i18n_key(), "errors.auth.expired.token");
        assert_eq!(AppError::Database("conexão".to_string()).i18n_key(), "errors.db.connection.failed");
        assert_eq!(AppError::Validation("erro".to_string()).i18n_key(), "errors.validation.failed");
    }

    #[test]
    fn test_to_error_envelope() {
        let err = AppError::Auth("token expirado".to_string());
        let env = err.to_error_envelope("trace-1", "src-svc");

        assert_eq!(env.code, "AUTH_EXPIRED_TOKEN");
        assert_eq!(env.category, ProtoCategory::Auth as i32);
        assert_eq!(env.severity, ProtoSeverity::Warning as i32);
        assert_eq!(env.message, "Erro de autenticação: token expirado");
        assert_eq!(env.user_message, "errors.auth.expired.token");
        assert_eq!(env.user_message_fallback, "Credencial inválida ou ausente.");
        assert_eq!(env.trace_id, "trace-1");
        assert_eq!(env.source_svc, "src-svc");
        assert_eq!(env.details.len(), 1);
        assert_eq!(env.details[0].key, "original_error");
        assert_eq!(env.details[0].value, "Erro de autenticação: token expirado");
        assert!(!env.retryable);

        // Testa conversão de categorias para garantir cobertura de todos os braços do match
        assert_eq!(
            AppError::Validation("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Validation as i32
        );
        assert_eq!(
            AppError::Auth("permissão".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Auth as i32
        );
        assert_eq!(
            AppError::Conflict("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Conflict as i32
        );

        assert_eq!(
            AppError::RateLimit("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::RateLimit as i32
        );
        assert_eq!(
            AppError::Database("não encontrado".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Internal as i32
        );
        assert_eq!(
            AppError::Storage("upload".to_string()).to_error_envelope("", "").category,
            ProtoCategory::NotFound as i32
        );
        assert_eq!(
            AppError::Database("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Internal as i32
        );
        assert_eq!(
            AppError::Cache("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Internal as i32
        );
        assert_eq!(
            AppError::Internal("".to_string()).to_error_envelope("", "").category,
            ProtoCategory::Internal as i32
        );
    }

    #[test]
    fn test_from_envelope() {
        let mut env = contracts::ErrorEnvelope {
            code: "AUTH_INVALID_TOKEN".to_string(),
            category: ProtoCategory::Auth as i32,
            severity: ProtoSeverity::Error as i32,
            message: "msg".to_string(),
            user_message: "".to_string(),
            user_message_fallback: "".to_string(),
            retryable: false,
            trace_id: "".to_string(),
            source_svc: "".to_string(),
            details: vec![],
            occurred_at: 0,
        };

        // Testa mapeamento reverso
        assert!(matches!(AppError::from_envelope(&env), AppError::Auth(_)));

        env.code = "STORAGE_NOT_FOUND".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Storage(_)));

        env.code = "DB_CONNECTION_FAILED".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Database(_)));

        env.code = "CACHE_UNAVAILABLE".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Cache(_)));

        env.code = "VALIDATION_FAILED".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Validation(_)));

        env.code = "CONFLICT".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Conflict(_)));

        env.code = "RATE_LIMIT_EXCEEDED".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::RateLimit(_)));

        env.code = "OUTRO_CODIGO".to_string();
        assert!(matches!(AppError::from_envelope(&env), AppError::Internal(_)));
    }
}

