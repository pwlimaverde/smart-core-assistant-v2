//! N4.2 — verificação de quota por recurso (instâncias/departamentos) contra o
//! plano vigente do tenant. Segue o padrão de subquery de limite já usado em
//! `operacional::atendentes::buscar_disponivel_round_robin` (contagem correlacionada
//! comparada a um campo de limite), aqui em duas consultas (limite + uso) para manter
//! a lógica de "sem assinatura => sem limite aplicado" legível em Rust.
//!
//! Consultas com `sqlx::query_scalar` (runtime-checked, sem macro `!`) — evita a
//! dependência de `cargo sqlx prepare` contra um banco ao vivo para este módulo novo.

use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Recursos com quota aplicável. Volume de mensagens e armazenamento de mídia são
/// medidos (métricas) mas não bloqueados nesta iteração — ver N4.2 no plano.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecursoQuota {
    Instancias,
    Departamentos,
}

impl RecursoQuota {
    pub fn as_str(&self) -> &'static str {
        match self {
            RecursoQuota::Instancias => "instancias",
            RecursoQuota::Departamentos => "departamentos",
        }
    }

    pub fn parse(valor: &str) -> Option<Self> {
        match valor {
            "instancias" => Some(RecursoQuota::Instancias),
            "departamentos" => Some(RecursoQuota::Departamentos),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QuotaStatus {
    pub recurso: String,
    pub uso_atual: i64,
    /// `None` = sem assinatura/plano vinculado — comportamento conservador de não
    /// bloquear tenants em trial/legado até terem um plano configurado.
    pub limite: Option<i64>,
    pub excedido: bool,
}

/// Verifica a quota de um recurso do tenant contra o limite do plano vigente
/// (join `tenants_subscription` × `tenants_plan`). Deve rodar dentro da transação
/// de tenant (RLS já filtra `tenants_subscription` por `app.current_tenant`).
#[tracing::instrument(skip(tx), fields(tenant_id = %tenant_id, recurso = recurso.as_str()))]
pub async fn verificar_quota(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    recurso: RecursoQuota,
) -> Result<QuotaStatus, DbError> {
    let (limite, uso_atual): (Option<i32>, i64) = match recurso {
        RecursoQuota::Instancias => {
            let limite = sqlx::query_scalar::<_, i32>(
                "SELECT p.max_instances \
                 FROM tenants_subscription s \
                 JOIN tenants_plan p ON p.id = s.plan_id \
                 WHERE s.tenant_id = $1",
            )
            .bind(tenant_id)
            .fetch_optional(&mut **tx)
            .await?;

            let uso = sqlx::query_scalar::<_, i64>(
                "SELECT COUNT(*) FROM oraculo_app_instance WHERE tenant_id = $1 AND active = true",
            )
            .bind(tenant_id)
            .fetch_one(&mut **tx)
            .await?;

            (limite, uso)
        }
        RecursoQuota::Departamentos => {
            let limite = sqlx::query_scalar::<_, i32>(
                "SELECT p.max_departments \
                 FROM tenants_subscription s \
                 JOIN tenants_plan p ON p.id = s.plan_id \
                 WHERE s.tenant_id = $1",
            )
            .bind(tenant_id)
            .fetch_optional(&mut **tx)
            .await?;

            let uso = sqlx::query_scalar::<_, i64>(
                "SELECT COUNT(*) FROM oraculo_departamento WHERE tenant_id = $1 AND ativo = true",
            )
            .bind(tenant_id)
            .fetch_one(&mut **tx)
            .await?;

            (limite, uso)
        }
    };

    let limite = limite.map(i64::from);
    let excedido = limite.map(|l| uso_atual >= l).unwrap_or(false);
    Ok(QuotaStatus {
        recurso: recurso.as_str().to_string(),
        uso_atual,
        limite,
        excedido,
    })
}

/// Verifica se a assinatura do tenant está em situação de inadimplência
/// (`status` fora de `ACTIVE`/`TRIALING`). `None` = sem assinatura cadastrada
/// (mesma postura conservadora de `verificar_quota`: não bloqueia por omissão).
#[tracing::instrument(skip(tx), fields(tenant_id = %tenant_id))]
pub async fn verificar_inadimplencia(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
) -> Result<Option<String>, DbError> {
    let status = sqlx::query_scalar::<_, String>(
        "SELECT status FROM tenants_subscription WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?;

    Ok(match status {
        Some(s) if s != "ACTIVE" && s != "TRIALING" => Some(s),
        _ => None,
    })
}
