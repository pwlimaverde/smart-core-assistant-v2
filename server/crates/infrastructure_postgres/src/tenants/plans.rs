use async_trait::async_trait;
use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Plan {
    pub id: i32,
    pub name: String,
    pub description: String,
    pub price: Option<Decimal>,
    pub max_instances: i32,
    pub max_departments: i32,
    pub active: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Subscription {
    pub id: i32,
    pub tenant_id: Uuid,
    pub plan_id: Option<i32>,
    pub status: String,
    pub current_period_start: Option<DateTime<Utc>>,
    pub current_period_end: Option<DateTime<Utc>>,
    pub payment_gateway: String,
    pub external_customer_id: String,
    pub external_subscription_id: String,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct PaymentRecord {
    pub id: i32,
    pub tenant_id: Uuid,
    pub amount: Decimal,
    pub payment_date: NaiveDate,
    pub payment_method: String,
    pub period_start: NaiveDate,
    pub period_end: NaiveDate,
    pub notes: String,
    pub recorded_by_id: Option<i32>,
    pub created_at: DateTime<Utc>,
}

#[async_trait]
pub trait SubscriptionRepository: Send + Sync {
    async fn buscar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Option<Subscription>, DbError>;

    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
    ) -> Result<(), DbError>;
}

#[async_trait]
pub trait PaymentRecordRepository: Send + Sync {
    async fn registrar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        amount: Decimal,
        payment_method: &str,
        payment_date: NaiveDate,
        period_start: NaiveDate,
        period_end: NaiveDate,
        notes: &str,
    ) -> Result<PaymentRecord, DbError>;

    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<PaymentRecord>, DbError>;
}

pub struct PostgresSubscriptionRepository;
pub struct PostgresPaymentRecordRepository;

#[async_trait]
impl SubscriptionRepository for PostgresSubscriptionRepository {
    async fn buscar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Option<Subscription>, DbError> {
        if !ctx.has_permission("financeiro:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            Subscription,
            r#"SELECT id, tenant_id, plan_id, status,
                      current_period_start, current_period_end,
                      payment_gateway, external_customer_id, external_subscription_id,
                      updated_at
               FROM tenants_subscription WHERE tenant_id = $1"#,
            ctx.tenant_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
    ) -> Result<(), DbError> {
        if !ctx.has_permission("financeiro:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        sqlx::query!(
            r#"UPDATE tenants_subscription
               SET status = $1, updated_at = NOW()
               WHERE tenant_id = $2"#,
            status, ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

#[async_trait]
impl PaymentRecordRepository for PostgresPaymentRecordRepository {
    async fn registrar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        amount: Decimal,
        payment_method: &str,
        payment_date: NaiveDate,
        period_start: NaiveDate,
        period_end: NaiveDate,
        notes: &str,
    ) -> Result<PaymentRecord, DbError> {
        if !ctx.has_permission("financeiro:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            PaymentRecord,
            r#"INSERT INTO tenants_paymentrecord
                   (tenant_id, amount, payment_date, payment_method,
                    period_start, period_end, notes, recorded_by_id)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
               RETURNING id, tenant_id, amount, payment_date, payment_method,
                         period_start, period_end, notes, recorded_by_id, created_at"#,
            ctx.tenant_id, amount, payment_date, payment_method,
            period_start, period_end, notes, ctx.user_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<PaymentRecord>, DbError> {
        if !ctx.has_permission("financeiro:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            PaymentRecord,
            r#"SELECT id, tenant_id, amount, payment_date, payment_method,
                      period_start, period_end, notes, recorded_by_id, created_at
               FROM tenants_paymentrecord
               WHERE tenant_id = $1
               ORDER BY payment_date DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

// buscar_planos_ativos não precisa de contexto de tenant (global)
pub async fn listar_planos_ativos(pool: &PgPool) -> Result<Vec<Plan>, DbError> {
    let rows = sqlx::query_as!(
        Plan,
        "SELECT id, name, description, price, max_instances, max_departments, active, created_at
         FROM tenants_plan WHERE active = true ORDER BY name"
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}
