//! Adapter Redis do rate limiting de login: reusa registrar_tentativa_login.

use async_trait::async_trait;
use redis::aio::ConnectionManager;

use infrastructure_redis::RedisError;

use crate::ports::LoginRateLimiter;

#[derive(Clone)]
pub struct RedisLoginRateLimiter {
    conn: ConnectionManager,
}

impl RedisLoginRateLimiter {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl LoginRateLimiter for RedisLoginRateLimiter {
    #[tracing::instrument(skip_all)]
    async fn register_login_attempt(
        &self,
        key_hash: &str,
        window_s: u64,
    ) -> Result<u64, RedisError> {
        // NUNCA logar `key_hash` nem credenciais.
        let mut conn = self.conn.clone();
        infrastructure_redis::registrar_tentativa_login(&mut conn, key_hash, window_s).await
    }
}
