//! Adapter concreto do domínio Tenant: reusa o PostgresTenantRepository de
//! infrastructure_postgres e encapsula a transação/SQL (antes vivia no handler).
//! As operações administrativas são cross-tenant; o SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::tenants::tenants::{
    PostgresTenantRepository, Tenant, TenantRepository,
};
use infrastructure_postgres::DbError;

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
}
