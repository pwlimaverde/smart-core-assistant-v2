//! Adapter concreto do domínio Plans/Billing: encapsula o SQL (planos, assinaturas,
//! pagamentos). O SQL não muda em relação aos handlers originais.

use async_trait::async_trait;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use infrastructure_postgres::DbError;

use crate::ports::PlansStore;

/// Implementação Postgres da port Plans/Billing.
///
/// N4.1: todos os consumidores desta port são rotas admin (`exigir_superuser=true`,
/// ver `ROTAS_ADMIN`) que leem/escrevem `tenants_subscription`/`tenants_paymentrecord`
/// (RLS FORCE, sem contexto de tenant setado nesta camada) — por isso as operações
/// cross-tenant usam `admin_pool` (BYPASSRLS). `tenants_plan` não tem RLS (tabela
/// global do SaaS), então `listar_planos`/`criar_plano`/`atualizar_plano` continuam
/// em `pool` sem prejuízo.
#[derive(Clone)]
pub struct PgPlansStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgPlansStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }

    /// Pool efetivo para operações cross-tenant (assinaturas/pagamentos, RLS FORCE).
    fn cross_tenant_pool(&self) -> &PgPool {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "PgPlansStore sem DATABASE_ADMIN_URL: a RLS bloqueará consultas/gravações \
                 cross-tenant de assinaturas/pagamentos e o resultado virá vazio ou a \
                 gravação será rejeitada"
            );
        }
        self.admin_pool.as_ref().unwrap_or(&self.pool)
    }
}

/// Converte uma linha de `tenants_plan` no JSON estável de plano.
fn plan_row_to_json(row: &sqlx::postgres::PgRow) -> serde_json::Value {
    serde_json::json!({
        "id": row.get::<i32, _>("id"),
        "name": row.get::<String, _>("name"),
        "description": row.get::<String, _>("description"),
        "price": row.get::<Option<Decimal>, _>("price").map(|p| p.to_string()).unwrap_or_default(),
        "max_instances": row.get::<i32, _>("max_instances"),
        "max_departments": row.get::<i32, _>("max_departments"),
        "active": row.get::<bool, _>("active"),
        "created_at": row.get::<chrono::DateTime<chrono::Utc>, _>("created_at").timestamp_millis(),
    })
}

/// Converte uma linha de `tenants_paymentrecord` no JSON estável de pagamento.
fn payment_row_to_json(row: &sqlx::postgres::PgRow) -> serde_json::Value {
    serde_json::json!({
        "id": row.get::<i32, _>("id"),
        "tenant_id": row.get::<Uuid, _>("tenant_id").to_string(),
        "amount": row.get::<Decimal, _>("amount").to_string(),
        "payment_date": row.get::<NaiveDate, _>("payment_date").to_string(),
        "payment_method": row.get::<String, _>("payment_method"),
        "period_start": row.get::<NaiveDate, _>("period_start").to_string(),
        "period_end": row.get::<NaiveDate, _>("period_end").to_string(),
        "notes": row.get::<String, _>("notes"),
        "recorded_by_id": row.get::<Option<i32>, _>("recorded_by_id").unwrap_or(0),
        "created_at": row.get::<chrono::DateTime<chrono::Utc>, _>("created_at").timestamp_millis(),
    })
}

#[async_trait]
impl PlansStore for PgPlansStore {
    #[tracing::instrument(skip_all)]
    async fn listar_planos(&self) -> Result<Vec<serde_json::Value>, DbError> {
        let rows = sqlx::query(
            "SELECT id, name, description, price, max_instances, max_departments, active, created_at FROM tenants_plan ORDER BY id",
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows.iter().map(plan_row_to_json).collect())
    }

    #[tracing::instrument(skip_all)]
    async fn criar_plano(
        &self,
        name: &str,
        description: &str,
        price: Option<Decimal>,
        max_instances: i32,
        max_departments: i32,
    ) -> Result<serde_json::Value, DbError> {
        let row = sqlx::query(
            r#"INSERT INTO tenants_plan (name, description, price, max_instances, max_departments)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, name, description, price, max_instances, max_departments, active, created_at"#,
        )
        .bind(name)
        .bind(description)
        .bind(price)
        .bind(max_instances)
        .bind(max_departments)
        .fetch_one(&self.pool)
        .await?;
        Ok(plan_row_to_json(&row))
    }

    #[tracing::instrument(skip_all, fields(plan_id = id))]
    async fn atualizar_plano(
        &self,
        id: i32,
        name: &str,
        description: &str,
        price: Option<Decimal>,
        max_instances: i32,
        max_departments: i32,
        active: bool,
    ) -> Result<bool, DbError> {
        let res = sqlx::query(
            r#"UPDATE tenants_plan
               SET name = $1, description = $2, price = $3, max_instances = $4, max_departments = $5, active = $6
               WHERE id = $7"#,
        )
        .bind(name)
        .bind(description)
        .bind(price)
        .bind(max_instances)
        .bind(max_departments)
        .bind(active)
        .bind(id)
        .execute(&self.pool)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_subscriptions(&self) -> Result<Vec<serde_json::Value>, DbError> {
        let rows = sqlx::query(
            r#"SELECT id, tenant_id, plan_id, status, current_period_start, current_period_end, payment_gateway, external_customer_id, external_subscription_id, updated_at
               FROM tenants_subscription ORDER BY id"#,
        )
        .fetch_all(self.cross_tenant_pool())
        .await?;
        Ok(rows
            .iter()
            .map(|row| {
                serde_json::json!({
                    "id": row.get::<i32, _>("id"),
                    "tenant_id": row.get::<Uuid, _>("tenant_id").to_string(),
                    "plan_id": row.get::<Option<i32>, _>("plan_id").unwrap_or(0),
                    "status": row.get::<String, _>("status"),
                    "current_period_start": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("current_period_start").map(|d| d.timestamp_millis()).unwrap_or(0),
                    "current_period_end": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("current_period_end").map(|d| d.timestamp_millis()).unwrap_or(0),
                    "payment_gateway": row.get::<String, _>("payment_gateway"),
                    "external_customer_id": row.get::<String, _>("external_customer_id"),
                    "external_subscription_id": row.get::<String, _>("external_subscription_id"),
                    "updated_at": row.get::<chrono::DateTime<chrono::Utc>, _>("updated_at").timestamp_millis(),
                })
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn registrar_pagamento(
        &self,
        tenant_id: Uuid,
        amount: Decimal,
        payment_date: NaiveDate,
        payment_method: &str,
        period_start: NaiveDate,
        period_end: NaiveDate,
        notes: &str,
        recorded_by: Option<i32>,
    ) -> Result<serde_json::Value, DbError> {
        let row = sqlx::query(
            r#"INSERT INTO tenants_paymentrecord (tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
               RETURNING id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at"#,
        )
        .bind(tenant_id)
        .bind(amount)
        .bind(payment_date)
        .bind(payment_method)
        .bind(period_start)
        .bind(period_end)
        .bind(notes)
        .bind(recorded_by)
        .fetch_one(self.cross_tenant_pool())
        .await?;
        Ok(payment_row_to_json(&row))
    }

    #[tracing::instrument(skip_all)]
    async fn listar_pagamentos(
        &self,
        tenant_id: Option<Uuid>,
    ) -> Result<Vec<serde_json::Value>, DbError> {
        let rows = if let Some(t) = tenant_id {
            sqlx::query(
                r#"SELECT id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at
                   FROM tenants_paymentrecord WHERE tenant_id = $1 ORDER BY payment_date DESC"#,
            )
            .bind(t)
            .fetch_all(self.cross_tenant_pool())
            .await?
        } else {
            sqlx::query(
                r#"SELECT id, tenant_id, amount, payment_date, payment_method, period_start, period_end, notes, recorded_by_id, created_at
                   FROM tenants_paymentrecord ORDER BY payment_date DESC"#,
            )
            .fetch_all(self.cross_tenant_pool())
            .await?
        };
        Ok(rows.iter().map(payment_row_to_json).collect())
    }
}
