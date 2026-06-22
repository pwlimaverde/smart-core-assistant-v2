//! Port (abstração) do domínio Plans/Billing do data_postgres (planos, assinaturas
//! e pagamentos). O handler depende SOMENTE desta trait; o SQL vive no adapter (DIP).
//! O parse/validação de entrada (preço, datas) permanece no handler.

use async_trait::async_trait;
use chrono::NaiveDate;
use infrastructure_postgres::DbError;
use rust_decimal::Decimal;
use uuid::Uuid;

/// Operações de faturamento expostas aos handlers RPC. As consultas retornam JSON
/// já no formato estável esperado pelos clientes admin (construído no adapter).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait PlansStore: Send + Sync {
    /// Lista os planos de faturamento.
    async fn listar_planos(&self) -> Result<Vec<serde_json::Value>, DbError>;

    /// Cria um plano e retorna o JSON do plano criado.
    async fn criar_plano(
        &self,
        name: &str,
        description: &str,
        price: Option<Decimal>,
        max_instances: i32,
        max_departments: i32,
    ) -> Result<serde_json::Value, DbError>;

    /// Atualiza um plano; `true` se algum registro foi afetado.
    #[allow(clippy::too_many_arguments)]
    async fn atualizar_plano(
        &self,
        id: i32,
        name: &str,
        description: &str,
        price: Option<Decimal>,
        max_instances: i32,
        max_departments: i32,
        active: bool,
    ) -> Result<bool, DbError>;

    /// Lista as assinaturas.
    async fn listar_subscriptions(&self) -> Result<Vec<serde_json::Value>, DbError>;

    /// Registra um pagamento e retorna o JSON do registro criado.
    #[allow(clippy::too_many_arguments)]
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
    ) -> Result<serde_json::Value, DbError>;

    /// Lista pagamentos, opcionalmente filtrando por tenant.
    async fn listar_pagamentos(
        &self,
        tenant_id: Option<Uuid>,
    ) -> Result<Vec<serde_json::Value>, DbError>;
}
