use error_core::{AppError, ErrorCode};
use thiserror::Error;

/// Único enum de erro exposto pela crate de cache/barramento.
///
/// É o erro **específico** desta camada, mas todo `RedisError` deriva do núcleo
/// (`error_core`): expõe um [`ErrorCode`] estável via [`RedisError::code`] e converte
/// para [`AppError`] via `From`, padronizando os dados de erro em todo o workspace.
#[derive(Debug, Error)]
pub enum RedisError {
    #[error("erro do redis: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("erro de serialização: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("erro de configuração: {0}")]
    ConfigError(String),

    #[error("registro não encontrado")]
    NotFound,

    /// Reuso de um refresh token já rotacionado — indica possível roubo de token.
    /// A família inteira é revogada antes de retornar este erro.
    #[error("reuso de refresh token detectado — família revogada")]
    TokenReuse,
}

impl RedisError {
    /// Código estável do núcleo (`error_core`) que identifica este erro de forma
    /// rastreável em logs, métricas e alertas. É a fonte autoritativa da classificação
    /// e mantém-se coerente com a conversão para [`AppError`].
    pub fn code(&self) -> ErrorCode {
        match self {
            // Falhas de conexão/IO/timeout indicam cache indisponível (retryable).
            Self::Redis(e)
                if e.is_connection_refusal()
                    || e.is_connection_dropped()
                    || e.is_timeout()
                    || e.is_io_error() =>
            {
                ErrorCode::CacheUnavailable
            }
            Self::Redis(_) | Self::NotFound => ErrorCode::CacheKeyNotFound,
            Self::Serde(_) | Self::ConfigError(_) => ErrorCode::InternalError,
            // Reuso de refresh token é um evento de segurança de autenticação.
            Self::TokenReuse => ErrorCode::AuthInvalidToken,
        }
    }
}

/// Ponte para o agregador do núcleo. A mensagem é construída de modo que
/// `AppError::code()` reclassifique para o **mesmo** [`ErrorCode`] de [`RedisError::code`],
/// garantindo coerência ponta a ponta.
impl From<RedisError> for AppError {
    fn from(err: RedisError) -> Self {
        match err.code() {
            ErrorCode::CacheUnavailable => AppError::Cache(format!("cache indisponível: {err}")),
            ErrorCode::CacheKeyNotFound => AppError::Cache(err.to_string()),
            ErrorCode::AuthInvalidToken => AppError::Auth(err.to_string()),
            // Serde/Config caem em erro interno.
            _ => AppError::Internal(err.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_redis_error_display() {
        assert_eq!(
            RedisError::ConfigError("REDIS_URL ausente".into()).to_string(),
            "erro de configuração: REDIS_URL ausente"
        );
        assert_eq!(RedisError::NotFound.to_string(), "registro não encontrado");
        assert_eq!(
            RedisError::TokenReuse.to_string(),
            "reuso de refresh token detectado — família revogada"
        );
    }

    /// Cada variante deve expor o `ErrorCode` esperado do núcleo.
    #[test]
    fn test_redis_error_code_mapeia_para_core() {
        assert_eq!(RedisError::NotFound.code(), ErrorCode::CacheKeyNotFound);
        assert_eq!(
            RedisError::ConfigError("x".into()).code(),
            ErrorCode::InternalError
        );
        assert_eq!(RedisError::TokenReuse.code(), ErrorCode::AuthInvalidToken);
    }

    /// A conversão para `AppError` deve preservar o `ErrorCode` (coerência ponta a ponta).
    #[test]
    fn test_redis_error_para_app_error_preserva_code() {
        let casos = [
            RedisError::NotFound,
            RedisError::ConfigError("cfg".into()),
            RedisError::TokenReuse,
        ];
        for caso in casos {
            let code_origem = caso.code();
            let app: AppError = caso.into();
            assert_eq!(
                app.code(),
                code_origem,
                "AppError::code() divergiu de RedisError::code() para {code_origem}"
            );
        }
    }
}
