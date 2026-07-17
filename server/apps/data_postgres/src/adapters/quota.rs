//! Adapter concreto da port de quota (N4.2): roda sobre a role de runtime
//! (`pool`, RLS respeitado) via `run_in_tenant_transaction` — nunca sobre
//! `admin_pool`, pois é uma verificação escopada a um único tenant.

use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::{
    connection::run_in_tenant_transaction,
    tenants::quota::{verificar_inadimplencia, verificar_quota, RecursoQuota},
    DbError,
};

use crate::ports::QuotaStore;

#[derive(Clone)]
pub struct PgQuotaStore {
    pub pool: PgPool,
}

impl PgQuotaStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl QuotaStore for PgQuotaStore {
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id, recurso))]
    async fn verificar_quota(
        &self,
        tenant_id: Uuid,
        recurso: &str,
    ) -> Result<serde_json::Value, DbError> {
        let recurso_enum = RecursoQuota::parse(recurso).ok_or_else(|| {
            DbError::ConfigError(format!("recurso de quota desconhecido: {recurso}"))
        })?;

        let recurso_owned = recurso.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| {
            let recurso_owned = recurso_owned;
            async move {
                let status = verificar_quota(&mut tx, tenant_id, recurso_enum).await?;
                let inadimplente = verificar_inadimplencia(&mut tx, tenant_id).await?;
                let json = serde_json::json!({
                    "recurso": recurso_owned,
                    "uso_atual": status.uso_atual,
                    "limite": status.limite,
                    "excedido": status.excedido,
                    "inadimplente": inadimplente.is_some(),
                    "subscription_status": inadimplente,
                });
                Ok((json, tx))
            }
        })
        .await
    }
}
