//! Port de cache de permissões (capacidade isolada — ISP).
//! O handler depende SOMENTE desta trait; o acesso ao Redis vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_redis::RedisError;
use uuid::Uuid;

/// Cache das `flow_permissions` por usuário/tenant.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait CacheStore: Send + Sync {
    /// Lê as permissões em cache. `Ok(None)` em cache miss.
    async fn get_flow_permissions(
        &self,
        tenant_id: Uuid,
        user_id: i32,
    ) -> Result<Option<Vec<i32>>, RedisError>;

    /// Grava as permissões com TTL (segundos).
    async fn set_flow_permissions(
        &self,
        tenant_id: Uuid,
        user_id: i32,
        permissions: Vec<i32>,
        ttl: u64,
    ) -> Result<(), RedisError>;
}
