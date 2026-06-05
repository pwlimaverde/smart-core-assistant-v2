use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Tenant {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub api_key: String,
    pub owner_id: i32,
    pub email: String,
    pub phone: Option<String>,
    pub active: bool,
    pub setup_completed: bool,
    pub onboarding_step: i32,
    pub access_code: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct TenantUser {
    pub id: i32,
    pub user_id: i32,
    pub tenant_id: Uuid,
    pub role: String,
    pub module_permissions: serde_json::Value,
    pub flow_permissions: serde_json::Value,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub created_by_id: Option<i32>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct TenantInvite {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub email: String,
    pub name: String,
    pub role: String,
    pub module_permissions: serde_json::Value,
    pub flow_permissions: serde_json::Value,
    pub token: String,
    pub expires_at: DateTime<Utc>,
    pub used: bool,
    pub created_at: DateTime<Utc>,
    pub created_by_id: Option<i32>,
}

#[async_trait]
pub trait TenantRepository: Send + Sync {
    /// Busca um tenant pelo ID dentro de uma transação com RLS configurado.
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tenant_id: Uuid,
    ) -> Result<Option<Tenant>, DbError>;

    /// Busca um tenant pelo slug dentro de uma transação com RLS configurado.
    async fn buscar_por_slug(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        slug: &str,
    ) -> Result<Option<Tenant>, DbError>;

    /// Cria um novo tenant dentro de uma transação.
    /// Gera UUID e api_key automaticamente e configura app.current_tenant para satisfazer RLS.
    /// owner_id padrão é 1 (auth_user de testes/admin) quando None.
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        name: &str,
        slug: &str,
        owner_id: Option<i32>,
        email: Option<&str>,
        phone: Option<&str>,
    ) -> Result<Tenant, DbError>;

    /// Ativa ou desativa um tenant.
    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tenant_id: Uuid,
        active: bool,
    ) -> Result<(), DbError>;

    async fn atualizar_setup(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        setup_completed: bool,
        onboarding_step: i32,
    ) -> Result<(), DbError>;
}

#[async_trait]
pub trait TenantUserRepository: Send + Sync {
    /// Resolve o vínculo TenantUser a partir do `user_id` antes de qualquer contexto
    /// de tenant existir (bootstrap de autenticação). Requer `admin_pool` com
    /// BYPASSRLS, pois `tenants_tenantuser` tem FORCE RLS e sem `app.current_tenant`
    /// a policy fail-closed retornaria sempre None.
    async fn buscar_por_user_id(
        &self,
        admin_pool: &PgPool,
        user_id: i32,
    ) -> Result<Option<TenantUser>, DbError>;

    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        user_id: i32,
        role: &str,
    ) -> Result<TenantUser, DbError>;
}

#[async_trait]
pub trait TenantInviteRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        email: &str,
        name: &str,
        role: &str,
        token: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<TenantInvite, DbError>;

    /// Resolve um convite pelo `token` antes de o convidado ter contexto de tenant
    /// (fluxo de aceite de convite é pré-autenticação). Requer `admin_pool` com
    /// BYPASSRLS pelo mesmo motivo de `buscar_por_user_id`.
    async fn buscar_por_token(
        &self,
        admin_pool: &PgPool,
        token: &str,
    ) -> Result<Option<TenantInvite>, DbError>;

    /// Marca o convite como usado. Requer `admin_pool` com BYPASSRLS — o invite_id
    /// é resolvido fora do contexto de tenant.
    async fn marcar_usado(&self, admin_pool: &PgPool, invite_id: Uuid) -> Result<(), DbError>;
}

// ---- Implementações concretas ----

pub struct PostgresTenantRepository;
pub struct PostgresTenantUserRepository;
pub struct PostgresTenantInviteRepository;

#[async_trait]
impl TenantRepository for PostgresTenantRepository {
    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        _ctx: &RequestContext,
        tenant_id: Uuid,
    ) -> Result<Option<Tenant>, DbError> {
        let row = sqlx::query_as!(
            Tenant,
            r#"SELECT id, name, slug, api_key, owner_id, email, phone,
                      active, setup_completed, onboarding_step, access_code,
                      created_at, updated_at
               FROM tenants_tenant
               WHERE id = $1"#,
            tenant_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(slug = %slug))]
    async fn buscar_por_slug(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        _ctx: &RequestContext,
        slug: &str,
    ) -> Result<Option<Tenant>, DbError> {
        let row = sqlx::query_as!(
            Tenant,
            r#"SELECT id, name, slug, api_key, owner_id, email, phone,
                      active, setup_completed, onboarding_step, access_code,
                      created_at, updated_at
               FROM tenants_tenant WHERE slug = $1"#,
            slug
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(slug = %slug))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        name: &str,
        slug: &str,
        owner_id: Option<i32>,
        email: Option<&str>,
        phone: Option<&str>,
    ) -> Result<Tenant, DbError> {
        let new_id = Uuid::new_v4();
        let api_key = Uuid::new_v4().to_string();
        let owner = owner_id.unwrap_or(1);
        let email_val = email.unwrap_or("");

        // Configura app.current_tenant para o novo ID antes do INSERT (satisfaz RLS FORCE)
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(new_id.to_string())
            .execute(&mut **tx)
            .await?;

        let row = sqlx::query_as!(
            Tenant,
            r#"INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id, email, phone)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               RETURNING id, name, slug, api_key, owner_id, email, phone,
                         active, setup_completed, onboarding_step, access_code,
                         created_at, updated_at"#,
            new_id,
            name,
            slug,
            api_key,
            owner,
            email_val,
            phone
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, active = active))]
    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tenant_id: Uuid,
        active: bool,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["tenant:admin"])?;
        sqlx::query!(
            "UPDATE tenants_tenant SET active = $1, updated_at = NOW() WHERE id = $2",
            active,
            tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(setup_completed = setup_completed, onboarding_step = onboarding_step))]
    async fn atualizar_setup(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        setup_completed: bool,
        onboarding_step: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE tenants_tenant
               SET setup_completed = $1, onboarding_step = $2, updated_at = NOW()
               WHERE id = $3"#,
            setup_completed,
            onboarding_step,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

#[async_trait]
impl TenantUserRepository for PostgresTenantUserRepository {
    #[tracing::instrument(skip_all, fields(user_id = user_id))]
    async fn buscar_por_user_id(
        &self,
        admin_pool: &PgPool,
        user_id: i32,
    ) -> Result<Option<TenantUser>, DbError> {
        let row = sqlx::query_as!(
            TenantUser,
            r#"SELECT id, user_id, tenant_id, role, module_permissions,
                      flow_permissions, is_active, created_at, created_by_id
               FROM tenants_tenantuser WHERE user_id = $1"#,
            user_id
        )
        .fetch_optional(admin_pool)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(user_id = user_id, role = %role))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        user_id: i32,
        role: &str,
    ) -> Result<TenantUser, DbError> {
        ctx.exigir_qualquer(&["tenant:admin"])?;
        let row = sqlx::query_as!(
            TenantUser,
            r#"INSERT INTO tenants_tenantuser (user_id, tenant_id, role, created_by_id)
               VALUES ($1, $2, $3, $4)
               RETURNING id, user_id, tenant_id, role, module_permissions,
                         flow_permissions, is_active, created_at, created_by_id"#,
            user_id,
            ctx.tenant_id,
            role,
            ctx.user_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }
}

#[async_trait]
impl TenantInviteRepository for PostgresTenantInviteRepository {
    // `email`/`token` são sensíveis: `skip_all`.
    #[tracing::instrument(skip_all, fields(role = %role))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        email: &str,
        name: &str,
        role: &str,
        token: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<TenantInvite, DbError> {
        ctx.exigir_qualquer(&["tenant:admin"])?;
        let row = sqlx::query_as!(
            TenantInvite,
            r#"INSERT INTO tenants_tenantinvite
                   (tenant_id, email, name, role, token, expires_at, created_by_id)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               RETURNING id, tenant_id, email, name, role, module_permissions,
                         flow_permissions, token, expires_at, used, created_at, created_by_id"#,
            ctx.tenant_id,
            email,
            name,
            role,
            token,
            expires_at,
            ctx.user_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    // `token` é o segredo do convite: `skip_all`.
    #[tracing::instrument(skip_all)]
    async fn buscar_por_token(
        &self,
        admin_pool: &PgPool,
        token: &str,
    ) -> Result<Option<TenantInvite>, DbError> {
        let row = sqlx::query_as!(
            TenantInvite,
            r#"SELECT id, tenant_id, email, name, role, module_permissions,
                      flow_permissions, token, expires_at, used, created_at, created_by_id
               FROM tenants_tenantinvite WHERE token = $1"#,
            token
        )
        .fetch_optional(admin_pool)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(invite_id = %invite_id))]
    async fn marcar_usado(&self, admin_pool: &PgPool, invite_id: Uuid) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE tenants_tenantinvite SET used = true WHERE id = $1",
            invite_id
        )
        .execute(admin_pool)
        .await?;
        Ok(())
    }
}
