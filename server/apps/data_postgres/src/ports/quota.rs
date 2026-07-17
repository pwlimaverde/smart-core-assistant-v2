//! Port (abstração) de verificação de quota/inadimplência por tenant (N4.2).
//! Usado pelo `QuotaGuard` (decorator) nos caminhos quentes de ingestão/envio
//! (webhook_ingress, data_whatsapp) via RPC — ver `handler_check_quota`.
//! Roda sempre sobre a role de runtime (RLS respeitado), nunca sobre admin_pool:
//! é uma verificação por-tenant, não uma consulta administrativa cross-tenant.

use async_trait::async_trait;
use infrastructure_postgres::DbError;
use uuid::Uuid;

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait QuotaStore: Send + Sync {
    /// Verifica o uso atual do recurso (`"instancias"` | `"departamentos"`) contra
    /// o limite do plano vigente, e a situação de inadimplência da assinatura, em
    /// uma única transação de tenant. Retorna o JSON estável de `CheckQuotaReply`.
    async fn verificar_quota(
        &self,
        tenant_id: Uuid,
        recurso: &str,
    ) -> Result<serde_json::Value, DbError>;
}
