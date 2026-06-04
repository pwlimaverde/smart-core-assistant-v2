use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Transaction, Row};
use uuid::Uuid;

use crate::errors::DbError;

/// Registro de um evento de auditoria retornado do banco de dados.
/// `tenant_id` é `Option` — NULL indica ação de superusuário/sistema.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AuditLogEntry {
    pub id: Uuid,
    pub tenant_id: Option<Uuid>,  // NULL = superusuário/sistema
    pub timestamp: DateTime<Utc>,
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Dados para inserir um novo registro de auditoria.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewAuditLogEntry {
    pub tenant_id: Option<Uuid>,  // None = ação global (superusuário)
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
}

// ============================================================
// Métodos de Inserção (Escrita) — Dinâmicos para build offline
// ============================================================

/// Insere um registro de auditoria associado a um inquilino (tenant).
/// Esta função executa dentro da transação do inquilino que configura o RLS.
pub async fn inserir_audit_log(
    tx: &mut Transaction<'_, Postgres>,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id
        "#
    )
    .bind(entry.tenant_id)
    .bind(&entry.level)
    .bind(&entry.service)
    .bind(&entry.trace_id)
    .bind(&entry.event)
    .bind(&entry.message)
    .bind(&entry.context)
    .bind(entry.user_id)
    .bind(&entry.ip_address)
    .fetch_one(&mut **tx)
    .await?;

    let id: Uuid = row.get("id");
    Ok(id)
}

/// Insere um registro de auditoria global (sem tenant, ex: superusuário/sistema)
/// usando o pool administrativo que ignora ou bypassa o RLS.
pub async fn inserir_audit_log_global(
    admin_pool: &PgPool,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address)
        VALUES (NULL, $1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
        "#
    )
    .bind(&entry.level)
    .bind(&entry.service)
    .bind(&entry.trace_id)
    .bind(&entry.event)
    .bind(&entry.message)
    .bind(&entry.context)
    .bind(entry.user_id)
    .bind(&entry.ip_address)
    .fetch_one(admin_pool)
    .await?;

    let id: Uuid = row.get("id");
    Ok(id)
}

// ============================================================
// Métodos de Consulta (Leitura) — Dinâmicos para build offline
// ============================================================

/// Busca registros de auditoria do inquilino (tenant) com paginação.
/// Deve ser executado em transação configurada com o tenant_id para que o RLS filtre corretamente.
pub async fn buscar_audit_logs(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id = $1
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#
    )
    .bind(tenant_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(rows)
}

/// Busca registros de auditoria do inquilino filtrados por evento.
pub async fn buscar_audit_logs_por_evento(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    event: &str,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id = $1 AND event = $2
        ORDER BY timestamp DESC
        LIMIT $3 OFFSET $4
        "#
    )
    .bind(tenant_id)
    .bind(event)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(rows)
}

/// Busca todos os registros de auditoria do sistema (incluindo inquilinos e globais).
/// Uso restrito do pool administrativo para dashboards de administração global.
pub async fn buscar_audit_logs_admin(
    admin_pool: &PgPool,
    event_filter: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE ($1::text IS NULL OR event = $1)
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#
    )
    .bind(event_filter)
    .bind(limit)
    .bind(offset)
    .fetch_all(admin_pool)
    .await?;

    Ok(rows)
}

/// Busca apenas os registros de auditoria globais do sistema (onde tenant_id IS NULL).
/// Uso restrito do pool administrativo.
pub async fn buscar_audit_logs_globais(
    admin_pool: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id IS NULL
        ORDER BY timestamp DESC
        LIMIT $1 OFFSET $2
        "#
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(admin_pool)
    .await?;

    Ok(rows)
}
