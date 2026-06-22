//! Adapter Redis da blocklist de tokens: reusa infrastructure_redis::TokenBlocklist.

use async_trait::async_trait;
use redis::aio::ConnectionManager;

use infrastructure_redis::RedisError;

use crate::ports::TokenBlocklist;

#[derive(Clone)]
pub struct RedisTokenBlocklist {
    conn: ConnectionManager,
}

impl RedisTokenBlocklist {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl TokenBlocklist for RedisTokenBlocklist {
    #[tracing::instrument(skip_all, fields(jti = jti))]
    async fn block(&self, jti: &str, ttl: u64) -> Result<(), RedisError> {
        let mut blocklist = infrastructure_redis::TokenBlocklist::new(self.conn.clone());
        blocklist.bloquear(jti, ttl).await
    }

    #[tracing::instrument(skip_all, fields(jti = jti))]
    async fn is_blocked(&self, jti: &str) -> Result<bool, RedisError> {
        let mut blocklist = infrastructure_redis::TokenBlocklist::new(self.conn.clone());
        blocklist.esta_bloqueado(jti).await
    }
}
