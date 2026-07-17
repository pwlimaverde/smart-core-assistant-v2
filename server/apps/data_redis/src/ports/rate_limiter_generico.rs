//! Port de rate limiting amplo (N4.4 — capacidade isolada, ISP): generaliza o
//! `LoginRateLimiter` para outros recursos (webhook por instância/tenant, rotas
//! quentes do `runtime_api`). O handler depende SOMENTE desta trait.

use async_trait::async_trait;
use infrastructure_redis::RedisError;

/// Contador de tentativas por janela para um recurso genérico (chave já opaca,
/// nunca PII em claro).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait RateLimiter: Send + Sync {
    /// Registra uma tentativa de `recurso`/`id` e devolve o total acumulado na janela.
    async fn register_attempt(
        &self,
        recurso: &str,
        id: &str,
        window_s: u64,
    ) -> Result<u64, RedisError>;
}
