//! Port de refresh tokens (capacidade isolada — ISP): segrega a rotação/revogação
//! do restante do cache. O handler depende SOMENTE desta trait.
//!
//! Nome distinto (`RefreshTokenPort`) para evitar ambiguidade com a struct concreta
//! `infrastructure_redis::RefreshTokenStore` reusada pelo adapter.

use async_trait::async_trait;
use infrastructure_redis::{RedisError, RegistroRefresh};
use uuid::Uuid;

/// Operações de ciclo de vida de refresh tokens (hash do token, nunca o token cru).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait RefreshTokenPort: Send + Sync {
    /// Armazena um novo refresh token (hash) vinculado a usuário/tenant/família.
    async fn store(
        &self,
        token_hash: &str,
        user_id: i32,
        tenant_id: Option<Uuid>,
        family_id: &str,
        ttl: u64,
    ) -> Result<(), RedisError>;

    /// Valida e rotaciona o token; `RedisError::TokenReuse` em reuso (família comprometida).
    async fn validate_and_rotate(&self, token_hash: &str) -> Result<RegistroRefresh, RedisError>;

    /// Revoga toda a família (em caso de reuso detectado).
    async fn revoke_family(&self, family_id: &str) -> Result<(), RedisError>;
}
