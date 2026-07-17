//! Adapter Redis do rate limiting amplo (N4.4): reusa `registrar_tentativa_recurso`.

use async_trait::async_trait;
use redis::aio::ConnectionManager;

use infrastructure_redis::RedisError;

use crate::ports::RateLimiter;

#[derive(Clone)]
pub struct RedisRateLimiter {
    conn: ConnectionManager,
}

impl RedisRateLimiter {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl RateLimiter for RedisRateLimiter {
    #[tracing::instrument(skip_all, fields(recurso = recurso))]
    async fn register_attempt(
        &self,
        recurso: &str,
        id: &str,
        window_s: u64,
    ) -> Result<u64, RedisError> {
        // NUNCA logar `id` (pode ser tenant_id/instance_id, mas mantemos a mesma
        // disciplina do LoginRateLimiter por padrão de segurança).
        let mut conn = self.conn.clone();
        infrastructure_redis::registrar_tentativa_recurso(&mut conn, recurso, id, window_s).await
    }
}
