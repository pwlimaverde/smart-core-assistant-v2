//! N7.2 — dedupe server-side de ações reenviadas pelo sync offline do desktop
//! (`MoveAtendimentoEtapa`/`SendOutboundMessage`, identificadas por `action_id`
//! uuid v7 gerado client-side). Reenviar a mesma ação (após retry/reconexão) não
//! deve reaplicar o efeito — só devolver o resultado já obtido da primeira vez.
//!
//! Uso: o chamador (adapter em `data_postgres`) primeiro consulta
//! [`buscar_acao_aplicada`] dentro da MESMA transação de tenant; se `Some`,
//! devolve o resultado armazenado sem tocar a mutação. Caso contrário, aplica a
//! mutação normalmente e registra o resultado com [`registrar_acao_aplicada`]
//! antes do commit.

use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Consulta se `action_id` já foi aplicado para este tenant. `Some(resultado)`
/// quando sim — o chamador deve devolver esse JSON sem reaplicar a mutação.
#[tracing::instrument(skip(tx), fields(tenant_id = %tenant_id, action_id = %action_id))]
pub async fn buscar_acao_aplicada(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    action_id: Uuid,
) -> Result<Option<serde_json::Value>, DbError> {
    let resultado = sqlx::query_scalar::<_, serde_json::Value>(
        "SELECT resultado FROM applied_actions WHERE tenant_id = $1 AND action_id = $2",
    )
    .bind(tenant_id)
    .bind(action_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(resultado)
}

/// Registra `action_id` como aplicado, com o `resultado` idempotente (o mesmo
/// JSON devolvido em reenvios futuros). `ON CONFLICT DO NOTHING`: sob corrida
/// entre duas requisições concorrentes com o mesmo `action_id`, a segunda apenas
/// não sobrescreve — o resultado já registrado pela primeira prevalece.
#[tracing::instrument(skip(tx, resultado), fields(tenant_id = %tenant_id, action_id = %action_id))]
pub async fn registrar_acao_aplicada(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    action_id: Uuid,
    resultado: &serde_json::Value,
) -> Result<(), DbError> {
    sqlx::query(
        "INSERT INTO applied_actions (action_id, tenant_id, resultado) \
         VALUES ($1, $2, $3) ON CONFLICT (action_id) DO NOTHING",
    )
    .bind(action_id)
    .bind(tenant_id)
    .bind(resultado)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
