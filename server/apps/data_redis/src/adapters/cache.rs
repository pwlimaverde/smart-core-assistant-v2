//! Adapter Redis do cache de permissões: reusa infrastructure_redis::CachePermissoes.

use async_trait::async_trait;
use redis::aio::ConnectionManager;
use uuid::Uuid;

use infrastructure_redis::RedisError;

use crate::ports::CacheStore;

#[derive(Clone)]
pub struct RedisCacheStore {
    conn: ConnectionManager,
}

impl RedisCacheStore {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl CacheStore for RedisCacheStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, user_id = user_id))]
    async fn get_flow_permissions(
        &self,
        tenant_id: Uuid,
        user_id: i32,
    ) -> Result<Option<Vec<i32>>, RedisError> {
        let mut store = infrastructure_redis::CachePermissoes::new(self.conn.clone());
        store.obter_flow_permissions(tenant_id, user_id).await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, user_id = user_id))]
    async fn set_flow_permissions(
        &self,
        tenant_id: Uuid,
        user_id: i32,
        permissions: Vec<i32>,
        ttl: u64,
    ) -> Result<(), RedisError> {
        let mut store = infrastructure_redis::CachePermissoes::new(self.conn.clone());
        store
            .definir_flow_permissions(tenant_id, user_id, &permissions, ttl)
            .await
    }
}
