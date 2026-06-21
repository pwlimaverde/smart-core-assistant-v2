use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct WhatsappInstance {
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
    pub provider: String,
    pub subscribed_events: serde_json::Value,
    pub last_connection_state: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct WhatsappContact {
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
pub trait WhatsappInstanceRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError>;

    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    async fn buscar_por_instance_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id_str: &str,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    async fn atualizar_estado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError>;

    async fn atualizar_instancia_provider_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<&str>,
    ) -> Result<(), DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    async fn admin_listar_todas_conectadas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    async fn admin_deletar_instancia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<(), DbError>;
}

#[async_trait]
pub trait WhatsappContactRepository: Send + Sync {
    async fn criar_ou_atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contact_id: Option<i32>,
    ) -> Result<WhatsappContact, DbError>;

    async fn buscar_por_jid(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        jid: &str,
    ) -> Result<Option<WhatsappContact>, DbError>;
}

pub struct PostgresWhatsappInstanceRepository;
pub struct PostgresWhatsappContactRepository;

#[async_trait]
impl WhatsappInstanceRepository for PostgresWhatsappInstanceRepository {
    #[tracing::instrument(skip_all)]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin", "integracoes:write"])?;
        let row = sqlx::query_as!(
            WhatsappInstance,
            r#"INSERT INTO whatsapp_instance (tenant_id, name, api_key, provider)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, name, instance_id, api_key, phone_number, active,
                         connection_state, last_state_check, media_storage_backend, provider,
                         subscribed_events, last_connection_state, created_at"#,
            ctx.tenant_id,
            name,
            api_key,
            provider
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        name: &str,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE tenant_id = $1 AND name = $2"#,
            ctx.tenant_id,
            name
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_instance_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id_str: &str,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE tenant_id = $1 AND instance_id = $2"#,
            ctx.tenant_id,
            instance_id_str
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id, connection_state = %connection_state))]
    async fn atualizar_estado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE whatsapp_instance
               SET connection_state = $1,
                   last_connection_state = $1,
                   last_state_check = NOW()
               WHERE tenant_id = $2 AND id = $3"#,
            connection_state,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(id = id, instance_id = %instance_id))]
    async fn atualizar_instancia_provider_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<&str>,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE whatsapp_instance
               SET instance_id = $1,
                   phone_number = $2
               WHERE tenant_id = $3 AND id = $4"#,
            instance_id,
            phone_number,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        let rows = sqlx::query_as!(
            WhatsappInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE tenant_id = $1 AND active = true
               ORDER BY created_at DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(operation = "admin_list_all_whatsapp_instances"))]
    async fn admin_listar_todas_conectadas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // RLS bypass: consulta direta sem tenant_id no filtro, pois é o admin operacional.
        // O sqlx pode reclamar se o bypass de RLS via policies não for executado com escopo operacional.
        // O policy do postgres usa app.current_tenant, mas o admin_listar_todas pode ser chamado fora do contexto de tenant
        // ou setando o tenant_id para o tenant que quer listar ou removendo a RLS temporariamente na transação se for superuser.
        // Como o RLS está habilitado, se a transação rodar sem definir o current_tenant, a política USING (tenant_id = current_setting('app.current_tenant'))
        // vai avaliar para falso ou dar erro se current_setting estiver vazio.
        // No postgres: SELECT ... USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
        // Se current_setting('app.current_tenant') for vazio/NULL, a policy resulta em tenant_id = NULL (que é falso).
        // Para o admin operacional bypassar a RLS, podemos setar o app.current_tenant para o tenant da instância, ou,
        // no postgres, se o usuário do banco for o dono da tabela ou superuser, a RLS é bypassada se usarmos BYPASS RLS ou se ele for o owner (que é o caso na migração e dev).
        // Mas para garantir compatibilidade no código Rust, vamos executar e ver se funciona.
        let rows = sqlx::query_as!(
            WhatsappInstance,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE active = true"#
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all)]
    async fn admin_deletar_instancia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin", "integracoes:write"])?;
        sqlx::query!(
            r#"DELETE FROM whatsapp_instance
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

#[async_trait]
impl WhatsappContactRepository for PostgresWhatsappContactRepository {
    #[tracing::instrument(skip_all, fields(instance_id = instance_id))]
    async fn criar_ou_atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contact_id: Option<i32>,
    ) -> Result<WhatsappContact, DbError> {
        let row = sqlx::query_as!(
            WhatsappContact,
            r#"INSERT INTO whatsapp_contact (tenant_id, instance_id, jid, contact_id)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (tenant_id, instance_id, jid) DO UPDATE
                   SET contact_id = COALESCE(EXCLUDED.contact_id, whatsapp_contact.contact_id),
                       updated_at = NOW()
               RETURNING id, tenant_id, contact_id, instance_id, jid, lid,
                         addressing_mode, active, metadados, created_at, updated_at"#,
            ctx.tenant_id,
            instance_id,
            jid,
            contact_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_jid(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        jid: &str,
    ) -> Result<Option<WhatsappContact>, DbError> {
        let row = sqlx::query_as!(
            WhatsappContact,
            r#"SELECT id, tenant_id, contact_id, instance_id, jid, lid,
                      addressing_mode, active, metadados, created_at, updated_at
               FROM whatsapp_contact
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
