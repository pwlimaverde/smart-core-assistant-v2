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

/// Recursos com quota aplicável. Volume de mensagens ainda é só medido (métrica)
/// sem bloqueio — ver N4.2 no plano. Armazenamento ganhou limite+guard na N7.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecursoQuota {
    Instancias,
    Departamentos,
    Storage,
}

impl RecursoQuota {
    pub fn as_str(&self) -> &'static str {
        match self {
            RecursoQuota::Instancias => "instancias",
            RecursoQuota::Departamentos => "departamentos",
            RecursoQuota::Storage => "storage",
        }
    }

    pub fn parse(valor: &str) -> Option<Self> {
        match valor {
            "instancias" => Some(RecursoQuota::Instancias),
            "departamentos" => Some(RecursoQuota::Departamentos),
            "storage" => Some(RecursoQuota::Storage),
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
    let (limite, uso_atual): (Option<i64>, i64) = match recurso {
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

            (limite.map(i64::from), uso)
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

            (limite.map(i64::from), uso)
        }
        RecursoQuota::Storage => {
            // `max_storage_bytes` é NULLABLE (NULL = ilimitado): query_scalar com
            // `Option<i64>` interno para distinguir "sem assinatura" (outer None) de
            // "assinatura sem limite configurado" (outer Some(None)) — ambos tratados
            // como sem limite (postura conservadora já usada pelos outros recursos).
            let limite = sqlx::query_scalar::<_, Option<i64>>(
                "SELECT p.max_storage_bytes \
                 FROM tenants_subscription s \
                 JOIN tenants_plan p ON p.id = s.plan_id \
                 WHERE s.tenant_id = $1",
            )
            .bind(tenant_id)
            .fetch_optional(&mut **tx)
            .await?
            .flatten();

            let uso = sqlx::query_scalar::<_, i64>(
                "SELECT COALESCE(total_bytes, 0) FROM tenants_storage_usage WHERE tenant_id = $1",
            )
            .bind(tenant_id)
            .fetch_optional(&mut **tx)
            .await?
            .unwrap_or(0);

            (limite, uso)
        }
    };

    let excedido = limite.map(|l| uso_atual >= l).unwrap_or(false);
    Ok(QuotaStatus {
        recurso: recurso.as_str().to_string(),
        uso_atual,
        limite,
        excedido,
    })
}

/// Incrementa o uso de armazenamento agregado do tenant em `delta_bytes` (N7.1),
/// chamado pelo `data_storage` após um `PutFile` bem-sucedido no R2. Upsert
/// atômico (`ON CONFLICT ... DO UPDATE SET total_bytes = total_bytes + EXCLUDED`)
/// — sem corrida entre uploads concorrentes do mesmo tenant. Retorna o total após
/// o incremento (não usado no caminho quente, mas útil para diagnóstico/teste).
#[tracing::instrument(skip(tx), fields(tenant_id = %tenant_id, delta_bytes))]
pub async fn registrar_uso_storage(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    delta_bytes: i64,
) -> Result<i64, DbError> {
    let total: i64 = sqlx::query_scalar(
        "INSERT INTO tenants_storage_usage (tenant_id, total_bytes, updated_at) \
         VALUES ($1, $2, NOW()) \
         ON CONFLICT (tenant_id) DO UPDATE \
         SET total_bytes = tenants_storage_usage.total_bytes + EXCLUDED.total_bytes, \
             updated_at = NOW() \
         RETURNING total_bytes",
    )
    .bind(tenant_id)
    .bind(delta_bytes)
    .fetch_one(&mut **tx)
    .await?;
    Ok(total)
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
