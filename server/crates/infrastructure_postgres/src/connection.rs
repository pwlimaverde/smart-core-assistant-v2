use sqlx::{postgres::PgPoolOptions, PgPool, Postgres, Transaction};
use std::time::Duration;
use uuid::Uuid;

use crate::errors::DbError;

/// Parâmetros do pool, lidos do ambiente com prefixo (ex.: "SMARTCORE_PG").
#[derive(Debug, Clone)]
pub struct PoolConfig {
    pub max_connections: u32,
    pub min_connections: u32,
    pub acquire_timeout: Duration,
    pub idle_timeout: Duration,
    pub max_lifetime: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: 5,
            min_connections: 1,
            acquire_timeout: Duration::from_millis(3000), // fail-fast (vs. 30s default)
            idle_timeout: Duration::from_secs(300),
            max_lifetime: Duration::from_secs(1800),
        }
    }
}

impl PoolConfig {
    /// Lê a config do ambiente. Variáveis ausentes caem no default.
    pub fn from_env(prefix: &str) -> Self {
        let d = Self::default();
        let u32v = |suf: &str, def: u32| {
            std::env::var(format!("{prefix}_{suf}"))
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(def)
        };
        let ms = |suf: &str, def: Duration| {
            std::env::var(format!("{prefix}_{suf}"))
                .ok()
                .and_then(|s| s.parse().ok())
                .map(Duration::from_millis)
                .unwrap_or(def)
        };
        let s = |suf: &str, def: Duration| {
            std::env::var(format!("{prefix}_{suf}"))
                .ok()
                .and_then(|s| s.parse().ok())
                .map(Duration::from_secs)
                .unwrap_or(def)
        };
        Self {
            max_connections: u32v("POOL_MAX", d.max_connections),
            min_connections: u32v("POOL_MIN", d.min_connections),
            acquire_timeout: ms("ACQUIRE_TIMEOUT_MS", d.acquire_timeout),
            idle_timeout: s("IDLE_TIMEOUT_S", d.idle_timeout),
            max_lifetime: s("MAX_LIFETIME_S", d.max_lifetime),
        }
    }
}

/// Cria o pool com a config externa. Loga a config efetiva no boot.
#[tracing::instrument(fields(?cfg), err)]
pub async fn criar_pool_config(cfg: PoolConfig) -> Result<PgPool, DbError> {
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| DbError::ConfigError("DATABASE_URL não configurada".into()))?;
    let pool = PgPoolOptions::new()
        .max_connections(cfg.max_connections)
        .min_connections(cfg.min_connections) // pool quente
        .acquire_timeout(cfg.acquire_timeout) // fail-fast
        .idle_timeout(cfg.idle_timeout)
        .max_lifetime(cfg.max_lifetime)
        .connect(&url)
        .await?;
    tracing::info!(
        max = cfg.max_connections,
        min = cfg.min_connections,
        acquire_ms = cfg.acquire_timeout.as_millis() as u64,
        "pool PostgreSQL criado com config efetiva"
    );
    Ok(pool)
}

/// Compatibilidade: a antiga `criar_pool(n)` passa a delegar para a versão configurável.
pub async fn criar_pool(max_connections: u32) -> Result<PgPool, DbError> {
    let mut cfg = PoolConfig::from_env("SMARTCORE_PG");
    cfg.max_connections = max_connections; // respeita o argumento explícito
    criar_pool_config(cfg).await
}

/// Cria um pool com privilégios administrativos a partir da `DATABASE_ADMIN_URL`.
///
/// Uso restrito a operações que exigem DDL/elevação (ex.: rodar migrations) e a
/// lookups pré-tenant que precisam contornar o RLS. O runtime de negócio usa
/// sempre [`criar_pool`] (role da aplicação + RLS).
#[tracing::instrument(fields(max_connections), err)]
pub async fn criar_admin_pool(max_connections: u32) -> Result<PgPool, DbError> {
    let url = std::env::var("DATABASE_ADMIN_URL")
        .map_err(|_| DbError::ConfigError("DATABASE_ADMIN_URL não configurada".into()))?;
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .connect(&url)
        .await?;
    tracing::info!("pool administrativo PostgreSQL criado");
    Ok(pool)
}

/// Executa um bloco de código sob transação configurada com o tenant_id para RLS.
///
/// CORREÇÃO CRÍTICA vs. documentação:
/// O comando `SET LOCAL app.current_tenant = $1` NÃO aceita bind via prepared statement
/// (o PostgreSQL rejeita placeholders no comando SET). Usamos `set_config(..., true)` que:
/// - Aceita parâmetros bindados normalmente.
/// - O terceiro argumento `true` (`is_local = true`) equivale a SET LOCAL — o valor é
///   revertido automaticamente ao fim da transação.
// Span por transação de tenant: todas as queries executadas dentro do `callback`
// herdam o `tenant_id`, dando correlação automática nos logs/traces de toda a camada.
// Sem `err`: a transação carrega erros de domínio esperados (não encontrado, permissão,
// constraint) que NÃO são `error` — quem consome registra com a severidade correta via
// `error_core::registrar`. Falhas de begin/commit propagam normalmente.
#[tracing::instrument(skip(pool, callback), fields(tenant_id = %tenant_id))]
pub async fn run_in_tenant_transaction<F, T, Fut>(
    pool: &PgPool,
    tenant_id: Uuid,
    callback: F,
) -> Result<T, DbError>
where
    F: FnOnce(Transaction<'static, Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<(T, Transaction<'static, Postgres>), DbError>>,
{
    // Medição do tempo de acquire do pool (M3)
    let inicio = std::time::Instant::now();
    let mut tx = pool.begin().await?;
    let acquire_ms = inicio.elapsed().as_secs_f64() * 1000.0;
    if acquire_ms > 100.0 {
        tracing::warn!(target: "metrics::pg_acquire", acquire_ms, "acquire de pool lento");
    }
    tracing::trace!(target: "metrics::pg_acquire", acquire_ms, "acquire de pool");

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;
    tracing::trace!("contexto RLS do tenant configurado na transação");

    let (result, tx_final) = callback(tx).await?;
    tx_final.commit().await?;
    Ok(result)
}

/// Aplica as migrations embutidas na inicialização da aplicação.
/// Migrations ficam em `migrations/` relativo ao Cargo.toml desta crate.
#[tracing::instrument(skip(pool), err)]
pub async fn inicializar_banco_dados(pool: &PgPool) -> Result<(), DbError> {
    sqlx::migrate!("./migrations").run(pool).await?;
    tracing::info!("migrations aplicadas com sucesso");
    Ok(())
}
