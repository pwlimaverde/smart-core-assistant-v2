use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct AppInstance {
    pub id: i32,
    pub tenant_id: Uuid,
    pub api_key: String,
    pub channel: String,
    pub display_name: Option<String>,
    pub departamento_id: Option<i32>,
    pub owner_id: Option<i32>,
    pub active: bool,
    pub resposta_bot: bool,
    pub metadata: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

#[async_trait]
pub trait AppInstanceRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
        channel: &str,
        display_name: Option<&str>,
        departamento_id: Option<i32>,
    ) -> Result<AppInstance, DbError>;

    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<AppInstance>, DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<AppInstance>, DbError>;
}

pub struct PostgresAppInstanceRepository;

#[async_trait]
impl AppInstanceRepository for PostgresAppInstanceRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
        channel: &str,
        display_name: Option<&str>,
        departamento_id: Option<i32>,
    ) -> Result<AppInstance, DbError> {
        if !ctx.has_permission("operacional:admin") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            AppInstance,
            r#"INSERT INTO oraculo_app_instance
                   (tenant_id, api_key, channel, display_name, departamento_id)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, tenant_id, api_key, channel, display_name,
                         departamento_id, owner_id, active, resposta_bot, metadata, created_at"#,
            ctx.tenant_id,
            api_key,
            channel,
            display_name,
            departamento_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<AppInstance>, DbError> {
        let row = sqlx::query_as!(
            AppInstance,
            r#"SELECT id, tenant_id, api_key, channel, display_name,
                      departamento_id, owner_id, active, resposta_bot, metadata, created_at
               FROM oraculo_app_instance
               WHERE tenant_id = $1 AND api_key = $2"#,
            ctx.tenant_id,
            api_key
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<AppInstance>, DbError> {
        if !ctx.has_permission("operacional:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            AppInstance,
            r#"SELECT id, tenant_id, api_key, channel, display_name,
                      departamento_id, owner_id, active, resposta_bot, metadata, created_at
               FROM oraculo_app_instance
               WHERE tenant_id = $1 AND active = true
               ORDER BY created_at DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
