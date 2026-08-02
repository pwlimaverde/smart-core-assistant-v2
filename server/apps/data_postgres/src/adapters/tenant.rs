//! Adapter concreto do domínio Tenant: reusa o PostgresTenantRepository de
//! infrastructure_postgres e encapsula a transação/SQL (antes vivia no handler).
//! As operações administrativas são cross-tenant; o SQL não muda.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::tenants::tenants::{
    PostgresTenantInviteRepository, PostgresTenantRepository, PostgresTenantUserRepository, Tenant,
    TenantInvite, TenantInviteListItem, TenantInviteRepository, TenantRepository, TenantUser,
    TenantUserRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError};

use crate::ports::TenantStore;

/// Implementação Postgres da port Tenant (operações administrativas).
#[derive(Clone)]
pub struct PgTenantStore {
    pub pool: PgPool,
}

impl PgTenantStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl TenantStore for PgTenantStore {
    #[tracing::instrument(skip_all, fields(slug = slug))]
    async fn criar(
        &self,
        name: &str,
        slug: &str,
        email: Option<String>,
        phone: Option<String>,
    ) -> Result<Tenant, DbError> {
        let repo = PostgresTenantRepository;
        let mut tx = self.pool.begin().await?;
        let tenant = repo
            .criar(
                &mut tx,
                name,
                slug,
                None,
                email.as_deref(),
                phone.as_deref(),
            )
            .await?;
        tx.commit().await?;
        Ok(tenant)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_todos(&self) -> Result<Vec<Tenant>, DbError> {
        let rows = sqlx::query_as::<_, Tenant>(
            "SELECT id, name, slug, api_key, owner_id, email, phone, active, \
             setup_completed, onboarding_step, access_code, created_at, updated_at \
             FROM tenants_tenant ORDER BY name",
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %id))]
    async fn buscar_por_id(&self, id: Uuid) -> Result<Option<Tenant>, DbError> {
        let row = sqlx::query_as::<_, Tenant>(
            "SELECT id, name, slug, api_key, owner_id, email, phone, active, \
             setup_completed, onboarding_step, access_code, created_at, updated_at \
             FROM tenants_tenant WHERE id = $1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %id))]
    async fn atualizar_cadastro(
        &self,
        id: Uuid,
        name: &str,
        slug: &str,
        owner_id: i32,
        email: &str,
        phone: Option<String>,
    ) -> Result<bool, DbError> {
        let res = sqlx::query(
            "UPDATE tenants_tenant \
             SET name = $1, slug = $2, owner_id = $3, email = $4, phone = $5, updated_at = NOW() \
             WHERE id = $6",
        )
        .bind(name)
        .bind(slug)
        .bind(owner_id)
        .bind(email)
        .bind(phone)
        .bind(id)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %id, active = active))]
    async fn definir_ativo(&self, id: Uuid, active: bool) -> Result<bool, DbError> {
        let res =
            sqlx::query("UPDATE tenants_tenant SET active = $1, updated_at = NOW() WHERE id = $2")
                .bind(active)
                .bind(id)
                .execute(&self.pool)
                .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %id))]
    async fn gerar_access_code(&self, id: Uuid, code: &str) -> Result<bool, DbError> {
        let res = sqlx::query(
            "UPDATE tenants_tenant SET access_code = $1, updated_at = NOW() WHERE id = $2",
        )
        .bind(code)
        .bind(id)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, passo, concluido))]
    async fn atualizar_progresso_onboarding(
        &self,
        tenant_id: Uuid,
        passo: i32,
        concluido: bool,
    ) -> Result<bool, DbError> {
        // `GREATEST` para o passo nunca andar para trás: o tenant pode voltar
        // uma tela para revisar o que preencheu, e isso não pode fazer o
        // progresso regredir na próxima abertura do app.
        //
        // A conclusão zera o `access_code` — o `signup_token` do wizard. Este é
        // o ponto certo para aposentá-lo: aqui o cliente já entrou com as
        // credenciais próprias, então o token de cadastro não autoriza mais
        // nada que a sessão não autorize melhor. Fazê-lo antes (na ativação da
        // assinatura) travava o passo 4 do cadastro.
        let res = sqlx::query(
            "UPDATE tenants_tenant \
                SET onboarding_step = GREATEST(onboarding_step, $1), \
                    setup_completed = setup_completed OR $2, \
                    access_code = CASE WHEN $2 THEN NULL ELSE access_code END, \
                    updated_at = NOW() \
              WHERE id = $3",
        )
        .bind(passo)
        .bind(concluido)
        .bind(tenant_id)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, email = %email))]
    async fn criar_convite(
        &self,
        ctx: &RequestContext,
        email: &str,
        name: &str,
        role: &str,
        module_permissions: serde_json::Value,
        flow_permissions: serde_json::Value,
        token: &str,
        expires_at: DateTime<Utc>,
    ) -> Result<TenantInvite, DbError> {
        let repo = PostgresTenantInviteRepository;
        let mut tx = self.pool.begin().await?;

        // Configura o tenant_id na transação para satisfazer RLS (usa set_config com bind param)
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(ctx.tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let invite = repo
            .criar(
                &mut tx,
                ctx,
                email,
                name,
                role,
                module_permissions,
                flow_permissions,
                token,
                expires_at,
            )
            .await?;
        tx.commit().await?;
        Ok(invite)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_convite_por_token(&self, token: &str) -> Result<Option<TenantInvite>, DbError> {
        let repo = PostgresTenantInviteRepository;
        repo.buscar_por_token(&self.pool, token).await
    }

    #[tracing::instrument(skip_all, fields(invite_id = %invite_id))]
    async fn aceitar_convite(
        &self,
        invite_id: Uuid,
        username: &str,
        email: &str,
        password_hash: &str,
        tenant_id: Uuid,
        role: &str,
        module_permissions: serde_json::Value,
        flow_permissions: serde_json::Value,
    ) -> Result<TenantUser, DbError> {
        let mut tx = self.pool.begin().await?;

        // 1. Configura o tenant_id na transação (RLS do TenantInvite/TenantUser)
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        // 2. Consumir o convite ANTES de criar qualquer registro, com guarda
        //    `used = FALSE`: dois aceites concorrentes do mesmo token disputam esta
        //    linha e só um prossegue — o outro sai com UniqueViolation (convite usado).
        let consumido = sqlx::query(
            "UPDATE tenants_tenantinvite SET used = true WHERE id = $1 AND used = FALSE",
        )
        .bind(invite_id)
        .execute(&mut *tx)
        .await?;
        if consumido.rows_affected() == 0 {
            return Err(DbError::UniqueViolation("convite já utilizado".to_string()));
        }

        // 3. Criar o usuário auth_user (query runtime — evita cache offline do sqlx)
        let row = sqlx::query(
            "INSERT INTO auth_user (username, email, password_hash, is_superuser) \
             VALUES ($1, $2, $3, false) \
             RETURNING id",
        )
        .bind(username)
        .bind(email)
        .bind(password_hash)
        .fetch_one(&mut *tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;

        let user_id: i32 = row.get("id");

        // 4. Criar o TenantUser herdando as permissões definidas no convite —
        //    sem isso o usuário nasce com module_permissions '{}' e loga sem
        //    nenhum escopo (derivar_escopos lê a lista direto do campo).
        let tenant_user = sqlx::query_as::<_, TenantUser>(
            "INSERT INTO tenants_tenantuser \
                 (user_id, tenant_id, role, module_permissions, flow_permissions) \
             VALUES ($1, $2, $3, $4, $5) \
             RETURNING id, user_id, tenant_id, role, module_permissions, \
                       flow_permissions, is_active, created_at, created_by_id",
        )
        .bind(user_id)
        .bind(tenant_id)
        .bind(role)
        .bind(module_permissions)
        .bind(flow_permissions)
        .fetch_one(&mut *tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;

        tx.commit().await?;
        Ok(tenant_user)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_usuarios(&self, ctx: &RequestContext) -> Result<Vec<TenantUser>, DbError> {
        let repo = PostgresTenantUserRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let users = repo.listar_por_tenant(&mut tx, &ctx).await?;
            Ok((users, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = user_id))]
    async fn atualizar_usuario(
        &self,
        ctx: &RequestContext,
        user_id: i32,
        role: Option<String>,
        module_permissions: Option<serde_json::Value>,
        flow_permissions: Option<serde_json::Value>,
    ) -> Result<bool, DbError> {
        let repo = PostgresTenantUserRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let afetou = repo
                .atualizar(
                    &mut tx,
                    &ctx,
                    user_id,
                    role.as_deref(),
                    module_permissions,
                    flow_permissions,
                )
                .await?;
            Ok((afetou, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_convites(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<TenantInviteListItem>, DbError> {
        let repo = PostgresTenantInviteRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let convites = repo.listar_por_tenant(&mut tx, &ctx).await?;
            Ok((convites, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, invite_id = %invite_id))]
    async fn revogar_convite(
        &self,
        ctx: &RequestContext,
        invite_id: Uuid,
    ) -> Result<bool, DbError> {
        let repo = PostgresTenantInviteRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let afetou = repo.marcar_revogado(&mut tx, &ctx, invite_id).await?;
            Ok((afetou, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, owner_id = owner_id))]
    async fn criar_primeiro_admin(
        &self,
        tenant_id: Uuid,
        owner_id: i32,
        module_permissions: serde_json::Value,
    ) -> Result<TenantUser, DbError> {
        let repo = PostgresTenantUserRepository;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let tu = repo
                .criar_admin_bootstrap(&mut tx, tenant_id, owner_id, module_permissions)
                .await?;
            Ok((tu, tx))
        })
        .await
    }
}
