//! Adapter concreto do domínio Auth: reusa PostgresAuthUserRepository e
//! PostgresTenantUserRepository de infrastructure_postgres. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::auth::users::{
    AuthUser, AuthUserRepository, PostgresAuthUserRepository,
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
}

impl PgAuthStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
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
}
