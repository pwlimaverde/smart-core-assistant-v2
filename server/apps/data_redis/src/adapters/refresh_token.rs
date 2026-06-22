//! Adapter Redis de refresh tokens: reusa infrastructure_redis::RefreshTokenStore.
//! NUNCA loga `token_hash` (material de credencial).

use async_trait::async_trait;
use redis::aio::ConnectionManager;
use uuid::Uuid;

use infrastructure_redis::{RedisError, RegistroRefresh};

use crate::ports::RefreshTokenPort;

#[derive(Clone)]
pub struct RedisRefreshTokenStore {
    conn: ConnectionManager,
}

impl RedisRefreshTokenStore {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl RefreshTokenPort for RedisRefreshTokenStore {
    #[tracing::instrument(skip_all, fields(user_id = user_id, family_id = family_id))]
    async fn store(
        &self,
        token_hash: &str,
        user_id: i32,
        tenant_id: Option<Uuid>,
        family_id: &str,
        ttl: u64,
    ) -> Result<(), RedisError> {
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store
            .armazenar(token_hash, user_id, tenant_id, family_id, ttl)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn validate_and_rotate(&self, token_hash: &str) -> Result<RegistroRefresh, RedisError> {
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store.validar_e_rotacionar(token_hash).await
    }

    #[tracing::instrument(skip_all, fields(family_id = family_id))]
    async fn revoke_family(&self, family_id: &str) -> Result<(), RedisError> {
        // WARN: revogação de família indica possível comprometimento.
        tracing::warn!(family_id, "revogando família de refresh tokens");
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store.revogar_familia(family_id).await
    }
}
