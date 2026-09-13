//! Adapter concreto do domínio Auth: reusa PostgresAuthUserRepository e
//! PostgresTenantUserRepository de infrastructure_postgres. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::auth::users::{
    AuthUser, AuthUserRepository, PostgresAuthUserRepository, UsuarioGlobal,
};
use infrastructure_postgres::tenants::tenants::{
    PostgresTenantUserRepository, TenantUser, TenantUserRepository,
};
use infrastructure_postgres::DbError;

use crate::ports::AuthStore;

/// Implementação Postgres da port Auth. `auth_user` é tabela global (sem RLS).
#[derive(Clone)]
pub struct PgAuthStore {
    pub pool: PgPool,
    /// Pool com BYPASSRLS, para a listagem global do superusuário (D7).
    ///
    /// O login não precisa dele — `auth_user` não tem RLS. A listagem precisa,
    /// porque junta `tenants_tenant` e `tenants_tenantuser`, que têm RLS com
    /// FORCE: sem BYPASSRLS os LEFT JOIN devolveriam NULL em toda linha e a tela
    /// mostraria todo mundo "sem tenant" — um dado errado com cara de certo.
    pub admin_pool: Option<PgPool>,
}

impl PgAuthStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }
}

#[async_trait]
impl AuthStore for PgAuthStore {
    #[tracing::instrument(skip_all)]
    async fn buscar_por_login(&self, login: &str) -> Result<Option<AuthUser>, DbError> {
        let repo = PostgresAuthUserRepository;
        match repo.buscar_por_email(&self.pool, login).await? {
            Some(u) => Ok(Some(u)),
            None => repo.buscar_por_username(&self.pool, login).await,
        }
    }

    /// `skip_all`: o termo de busca é nome ou e-mail de gente.
    #[tracing::instrument(skip_all, fields(limite = limite, offset = offset))]
    async fn listar_usuarios_global(
        &self,
        busca: &str,
        limite: i64,
        offset: i64,
    ) -> Result<Vec<UsuarioGlobal>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_usuarios_global sem DATABASE_ADMIN_URL: a RLS de \
                 tenants_tenant esconderá o vínculo e todo usuário aparecerá \
                 sem tenant"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        PostgresAuthUserRepository
            .listar_global(effective_pool, busca, limite, offset)
            .await
    }

    #[tracing::instrument(skip_all, fields(user_id = user_id, ativo = ativo))]
    async fn definir_usuario_ativo(&self, user_id: i32, ativo: bool) -> Result<bool, DbError> {
        PostgresAuthUserRepository
            .definir_ativo(&self.pool, user_id, ativo)
            .await
    }

    #[tracing::instrument(skip_all, fields(user_id = id))]
    async fn buscar_por_id(&self, id: i32) -> Result<Option<AuthUser>, DbError> {
        PostgresAuthUserRepository
            .buscar_por_id(&self.pool, id)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_username(&self, username: &str) -> Result<Option<AuthUser>, DbError> {
        PostgresAuthUserRepository
            .buscar_por_username(&self.pool, username)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_email(&self, email: &str) -> Result<Option<AuthUser>, DbError> {
        PostgresAuthUserRepository
            .buscar_por_email(&self.pool, email)
            .await
    }

    #[tracing::instrument(skip_all, fields(user_id = user_id))]
    async fn buscar_tenant_user(&self, user_id: i32) -> Result<Option<TenantUser>, DbError> {
        PostgresTenantUserRepository
            .buscar_por_user_id(&self.pool, user_id)
            .await
    }

    #[tracing::instrument(skip_all, fields(user_id = user_id))]
    async fn registrar_ultimo_login(&self, user_id: i32) -> Result<(), DbError> {
        PostgresAuthUserRepository
            .atualizar_ultimo_login(&self.pool, user_id)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn criar_superuser(
        &self,
        username: &str,
        email: &str,
        password_hash: &str,
    ) -> Result<AuthUser, DbError> {
        // O último argumento (is_superuser) é `true`.
        PostgresAuthUserRepository
            .criar(&self.pool, username, email, password_hash, true)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn listar_superusers(&self) -> Result<Vec<AuthUser>, DbError> {
        PostgresAuthUserRepository
            .listar_superusers(&self.pool)
            .await
    }

    #[tracing::instrument(skip_all, fields(user_id = user_id))]
    async fn deletar_superuser(&self, user_id: i32) -> Result<u64, DbError> {
        PostgresAuthUserRepository
            .deletar_superuser(&self.pool, user_id)
            .await
    }

    // O hash do token fica fora do span: `skip_all`.
    #[tracing::instrument(skip_all, fields(user_id = user_id))]
    async fn registrar_redefinicao_senha(
        &self,
        user_id: i32,
        token_hash: &str,
        expira_em: chrono::DateTime<chrono::Utc>,
    ) -> Result<(), DbError> {
        infrastructure_postgres::auth::password_reset::registrar(
            &self.pool, user_id, token_hash, expira_em,
        )
        .await
    }

    #[tracing::instrument(skip_all)]
    async fn redefinir_senha(
        &self,
        token_hash: &str,
        password_hash: &str,
    ) -> Result<Option<i32>, DbError> {
        infrastructure_postgres::auth::password_reset::consumir_e_trocar_senha(
            &self.pool,
            token_hash,
            password_hash,
        )
        .await
    }
}
