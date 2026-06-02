use sqlx::{postgres::PgPoolOptions, PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Cria o pool global de conexões a partir da DATABASE_URL de ambiente.
/// Nunca conectar como superuser ou owner das tabelas (bypassa RLS).
pub async fn criar_pool(max_connections: u32) -> Result<PgPool, DbError> {
    let url = std::env::var("DATABASE_URL")
        .map_err(|_| DbError::ConfigError("DATABASE_URL não configurada".into()))?;
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .connect(&url)
        .await?;
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
pub async fn run_in_tenant_transaction<F, T, Fut>(
    pool: &PgPool,
    tenant_id: Uuid,
    callback: F,
) -> Result<T, DbError>
where
    F: FnOnce(Transaction<'static, Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<(T, Transaction<'static, Postgres>), DbError>>,
{
    let mut tx = pool.begin().await?;

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;

    let (result, tx_final) = callback(tx).await?;
    tx_final.commit().await?;
    Ok(result)
}

/// Aplica as migrations embutidas na inicialização da aplicação.
/// Migrations ficam em `migrations/` relativo ao Cargo.toml desta crate.
pub async fn inicializar_banco_dados(pool: &PgPool) -> Result<(), DbError> {
    sqlx::migrate!("./migrations").run(pool).await?;
    Ok(())
}
