//! Port de blocklist de tokens (capacidade isolada — ISP).
//! O handler depende SOMENTE desta trait.

use async_trait::async_trait;
use infrastructure_redis::RedisError;

/// Blocklist de JTIs (token ids) revogados, com TTL.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait TokenBlocklist: Send + Sync {
    /// Bloqueia um `jti` por `ttl` segundos.
    async fn block(&self, jti: &str, ttl: u64) -> Result<(), RedisError>;

    /// Indica se um `jti` está bloqueado.
    async fn is_blocked(&self, jti: &str) -> Result<bool, RedisError>;
}
