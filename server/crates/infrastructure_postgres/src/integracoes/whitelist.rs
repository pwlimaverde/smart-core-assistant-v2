use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct WhiteList {
    pub id: i32,
    pub tenant_id: Uuid,
    pub contact_id: Option<i32>,
    pub name: String,
    pub phone_number: String,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[async_trait]
pub trait WhiteListRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        phone_number: &str,
        contact_id: Option<i32>,
    ) -> Result<WhiteList, DbError>;

    /// Verifica se um número está na whitelist do tenant.
    async fn esta_na_lista(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError>;
}

pub struct PostgresWhiteListRepository;

#[async_trait]
impl WhiteListRepository for PostgresWhiteListRepository {
    #[tracing::instrument(skip_all)]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        phone_number: &str,
        contact_id: Option<i32>,
    ) -> Result<WhiteList, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as!(
            WhiteList,
            r#"INSERT INTO evolution_sync_whitelist (tenant_id, name, phone_number, contact_id)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, contact_id, name, phone_number, active, created_at"#,
            ctx.tenant_id,
            name,
            phone_number,
            contact_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn esta_na_lista(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError> {
        let count = sqlx::query_scalar!(
            r#"SELECT COUNT(*) FROM evolution_sync_whitelist
               WHERE tenant_id = $1 AND phone_number = $2 AND active = true"#,
            ctx.tenant_id,
            phone_number
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(count.unwrap_or(0) > 0)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError> {
        let rows = sqlx::query_as!(
            WhiteList,
            r#"SELECT id, tenant_id, contact_id, name, phone_number, active, created_at
               FROM evolution_sync_whitelist
               WHERE tenant_id = $1 AND active = true
               ORDER BY name"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
