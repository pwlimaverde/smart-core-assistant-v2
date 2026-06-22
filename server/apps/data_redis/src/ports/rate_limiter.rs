//! Port de rate limiting de login (capacidade isolada — ISP).
//! O handler depende SOMENTE desta trait.

use async_trait::async_trait;
use infrastructure_redis::RedisError;

/// Contador de tentativas de login por janela (chave já hasheada, nunca o e-mail cru).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait LoginRateLimiter: Send + Sync {
    /// Registra uma tentativa e devolve o total acumulado na janela.
    async fn register_login_attempt(
        &self,
        key_hash: &str,
        window_s: u64,
    ) -> Result<u64, RedisError>;
}
