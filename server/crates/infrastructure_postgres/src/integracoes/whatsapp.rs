use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{crypto::CipherManager, errors::DbError, security::RequestContext};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct WhatsappInstance {
    pub id: i32,
    pub tenant_id: Uuid,
    pub name: String,
    pub instance_id: Option<String>,
    /// Sempre o token em claro (decifrado na leitura) — a coluna no banco é
    /// jsonb {ciphertext,nonce,tag}, ver `CipherManager`.
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

/// Linha bruta do banco — `api_key` ainda cifrada (jsonb {ciphertext,nonce,tag}).
#[derive(Debug, Clone, sqlx::FromRow)]
struct WhatsappInstanceRow {
    id: i32,
    tenant_id: Uuid,
    name: String,
    instance_id: Option<String>,
    api_key: serde_json::Value,
    phone_number: Option<String>,
    active: bool,
    connection_state: String,
    last_state_check: Option<DateTime<Utc>>,
    media_storage_backend: String,
    provider: String,
    subscribed_events: serde_json::Value,
    last_connection_state: Option<String>,
    created_at: DateTime<Utc>,
}

impl WhatsappInstanceRow {
    /// Decifra `api_key` e monta o struct público.
    fn decrypt(self, cipher: &CipherManager) -> Result<WhatsappInstance, DbError> {
        Ok(WhatsappInstance {
            id: self.id,
            tenant_id: self.tenant_id,
            name: self.name,
            instance_id: self.instance_id,
            api_key: cipher.decrypt_json_entry(&self.api_key)?,
            phone_number: self.phone_number,
            active: self.active,
            connection_state: self.connection_state,
            last_state_check: self.last_state_check,
            media_storage_backend: self.media_storage_backend,
            provider: self.provider,
            subscribed_events: self.subscribed_events,
            last_connection_state: self.last_connection_state,
            created_at: self.created_at,
        })
    }
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
        cipher: &CipherManager,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError>;

    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
        name: &str,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    async fn buscar_por_instance_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
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
        cipher: &CipherManager,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    async fn admin_listar_todas_conectadas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
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
        cipher: &CipherManager,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin", "integracoes:write"])?;
        let api_key_json = cipher.encrypt_to_json(api_key.as_bytes())?;
        let row = sqlx::query_as!(
            WhatsappInstanceRow,
            r#"INSERT INTO whatsapp_instance (tenant_id, name, api_key, provider)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, name, instance_id, api_key, phone_number, active,
                         connection_state, last_state_check, media_storage_backend, provider,
                         subscribed_events, last_connection_state, created_at"#,
            ctx.tenant_id,
            name,
            api_key_json,
            provider
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        // Reaproveita o plaintext já em mãos em vez de decifrar de novo.
        let mut inst = row.decrypt(cipher)?;
        inst.api_key = api_key.to_string();
        Ok(inst)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_name(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
        name: &str,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstanceRow,
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
        row.map(|r| r.decrypt(cipher)).transpose()
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstanceRow,
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
        row.map(|r| r.decrypt(cipher)).transpose()
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_instance_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
        instance_id_str: &str,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let row = sqlx::query_as!(
            WhatsappInstanceRow,
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
        row.map(|r| r.decrypt(cipher)).transpose()
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
        cipher: &CipherManager,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        let rows = sqlx::query_as!(
            WhatsappInstanceRow,
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
        rows.into_iter().map(|r| r.decrypt(cipher)).collect()
    }

    #[tracing::instrument(skip_all, fields(operation = "admin_list_all_whatsapp_instances"))]
    async fn admin_listar_todas_conectadas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cipher: &CipherManager,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // Requer pool com BYPASSRLS (admin pool, DATABASE_ADMIN_URL).
        // Com pool de app (RLS ativa), esta query retorna 0 linhas pois a policy
        // USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)
        // avalia para FALSE quando app.current_tenant não está definido.
        let rows = sqlx::query_as!(
            WhatsappInstanceRow,
            r#"SELECT id, tenant_id, name, instance_id, api_key, phone_number, active,
                       connection_state, last_state_check, media_storage_backend, provider,
                       subscribed_events, last_connection_state, created_at
               FROM whatsapp_instance
               WHERE active = true"#
        )
        .fetch_all(&mut **tx)
        .await?;
        rows.into_iter().map(|r| r.decrypt(cipher)).collect()
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
