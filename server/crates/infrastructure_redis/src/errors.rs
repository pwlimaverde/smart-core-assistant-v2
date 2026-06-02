use thiserror::Error;

/// Único enum de erro exposto pela crate de cache/barramento.
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
}
