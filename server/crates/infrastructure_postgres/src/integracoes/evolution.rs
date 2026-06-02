use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct EvolutionInstance {
    pub id: i32,
    pub tenant_id: Uuid,
    pub name: String,
    pub instance_id: Option<String>,
    pub api_key: String,
    pub phone_number: Option<String>,
    pub active: bool,
    pub connection_state: String,
    pub last_state_check: Option<DateTime<Utc>>,
    pub media_storage_backend: String,
    pub subscribed_events: serde_json::Value,
    pub last_connection_state: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct EvolutionContact {
    pub id: i32,
    pub tenant_id: Uuid,
    pub contact_id: Option<i32>,
    pub instance_id: i32,
    pub jid: Option<String>,
    pub lid: Option<String>,
    pub addressing_mode: Option<String>,
    pub active: bool,
    pub metadados: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[async_trait]
pub trait EvolutionInstanceRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
    ) -> Result<EvolutionInstance, DbError>;

    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
    ) -> Result<Option<EvolutionInstance>, DbError>;

    async fn atualizar_estado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id_str: &str,
        connection_state: &str,
    ) -> Result<(), DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<EvolutionInstance>, DbError>;
}

#[async_trait]
pub trait EvolutionContactRepository: Send + Sync {
    async fn criar_ou_atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contact_id: Option<i32>,
    ) -> Result<EvolutionContact, DbError>;

    async fn buscar_por_jid(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        jid: &str,
    ) -> Result<Option<EvolutionContact>, DbError>;
}

pub struct PostgresEvolutionInstanceRepository;
pub struct PostgresEvolutionContactRepository;

#[async_trait]
impl EvolutionInstanceRepository for PostgresEvolutionInstanceRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
    ) -> Result<EvolutionInstance, DbError> {
        if !ctx.has_permission("operacional:admin") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            EvolutionInstance,
            r#"INSERT INTO evolution_sync_instance (tenant_id, name, api_key)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, name, instance_id, api_key, phone_number, active,
                         connection_state, last_state_check, media_storage_backend,
                         subscribed_events, last_connection_state, created_at"#,
            ctx.tenant_id,
            name,
            api_key
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
    ) -> Result<Option<EvolutionInstance>, DbError> {
        let row = sqlx::query_as!(
            EvolutionInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                      connection_state, last_state_check, media_storage_backend,
                      subscribed_events, last_connection_state, created_at
               FROM evolution_sync_instance
               WHERE tenant_id = $1 AND name = $2"#,
            ctx.tenant_id,
            name
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn atualizar_estado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id_str: &str,
        connection_state: &str,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE evolution_sync_instance
               SET connection_state = $1,
                   last_connection_state = $1,
                   last_state_check = NOW()
               WHERE tenant_id = $2 AND instance_id = $3"#,
            connection_state,
            ctx.tenant_id,
            instance_id_str
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<EvolutionInstance>, DbError> {
        let rows = sqlx::query_as!(
            EvolutionInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                      connection_state, last_state_check, media_storage_backend,
                      subscribed_events, last_connection_state, created_at
               FROM evolution_sync_instance
               WHERE tenant_id = $1 AND active = true
               ORDER BY created_at DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

#[async_trait]
impl EvolutionContactRepository for PostgresEvolutionContactRepository {
    async fn criar_ou_atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contact_id: Option<i32>,
    ) -> Result<EvolutionContact, DbError> {
        let row = sqlx::query_as!(
            EvolutionContact,
            r#"INSERT INTO evolution_sync_contact (tenant_id, instance_id, jid, contact_id)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (tenant_id, instance_id, jid) DO UPDATE
                   SET contact_id = COALESCE(EXCLUDED.contact_id, evolution_sync_contact.contact_id),
                       updated_at = NOW()
               RETURNING id, tenant_id, contact_id, instance_id, jid, lid,
                         addressing_mode, active, metadados, created_at, updated_at"#,
            ctx.tenant_id, instance_id, jid, contact_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn buscar_por_jid(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        jid: &str,
    ) -> Result<Option<EvolutionContact>, DbError> {
        let row = sqlx::query_as!(
            EvolutionContact,
            r#"SELECT id, tenant_id, contact_id, instance_id, jid, lid,
                      addressing_mode, active, metadados, created_at, updated_at
               FROM evolution_sync_contact
               WHERE tenant_id = $1 AND jid = $2
               ORDER BY updated_at DESC LIMIT 1"#,
            ctx.tenant_id,
            jid
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}
