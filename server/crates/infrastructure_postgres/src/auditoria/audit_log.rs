use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Registro de um evento de auditoria retornado do banco de dados.
/// `tenant_id` é `Option` — NULL indica ação de superusuário/sistema.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AuditLogEntry {
    pub id: Uuid,
    pub tenant_id: Option<Uuid>, // NULL = superusuário/sistema
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
    pub user_agent: Option<String>,
}

/// Dados para inserir um novo registro de auditoria.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewAuditLogEntry {
    pub tenant_id: Option<Uuid>, // None = ação global (superusuário)
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    /// Quando o evento ACONTECEU, não quando foi gravado.
    ///
    /// A trilha chega por `transport::bus` de forma assíncrona; entre o fato e a
    /// linha no banco pode haver segundos — ou dias, se o consumidor estiver
    /// parado. Em 09/2026 ele ficou três dias sem consumir, e sem este campo a
    /// consolidação carimbaria todos os eventos com a hora em que a fila foi
    /// drenada: uma trilha de auditoria que mente sobre a cronologia dos fatos.
    ///
    /// `None` para quem grava direto no banco, sem passar pela fila — aí o
    /// `now()` do Postgres é a hora do evento, e é o COALESCE que resolve.
    pub timestamp: Option<DateTime<Utc>>,
}

// ============================================================
// Métodos de Inserção (Escrita) — Dinâmicos para build offline
// ============================================================

/// Insere um registro de auditoria associado a um inquilino (tenant).
/// Esta função executa dentro da transação do inquilino que configura o RLS.
// Sem `err`: o `AuditLogger` (crate observability) já registra falhas de persistência;
// evita-se log duplicado mantendo apenas o span de correlação.
#[tracing::instrument(
    level = "debug",
    skip(tx, entry),
    fields(event = %entry.event, level = %entry.level, tenant_id = ?entry.tenant_id)
)]
pub async fn inserir_audit_log(
    tx: &mut Transaction<'_, Postgres>,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address, user_agent, timestamp)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, now()))
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
    .bind(&entry.user_agent)
    .bind(entry.timestamp)
    .fetch_one(&mut **tx)
    .await?;

    let id: Uuid = row.get("id");
    Ok(id)
}

/// Insere um registro de auditoria global (sem tenant, ex: superusuário/sistema)
/// usando o pool administrativo que ignora ou bypassa o RLS.
#[tracing::instrument(
    level = "debug",
    skip(admin_pool, entry),
    fields(event = %entry.event, level = %entry.level)
)]
pub async fn inserir_audit_log_global(
    admin_pool: &PgPool,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address, user_agent, timestamp)
        VALUES (NULL, $1, $2, $3, $4, $5, $6, $7, $8, $9, COALESCE($10, now()))
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
    .bind(&entry.user_agent)
    .bind(entry.timestamp)
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
#[tracing::instrument(level = "debug", skip(tx), fields(tenant_id = %tenant_id, limit, offset), err)]
pub async fn buscar_audit_logs(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at, user_agent
        FROM audit_log
        WHERE tenant_id = $1
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(tenant_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(rows)
}

/// Busca registros de auditoria do inquilino filtrados por evento.
#[tracing::instrument(
    level = "debug",
    skip(tx),
    fields(tenant_id = %tenant_id, event = %event, limit, offset),
    err
)]
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
               event, message, context, user_id, ip_address, created_at, user_agent
        FROM audit_log
        WHERE tenant_id = $1 AND event = $2
        ORDER BY timestamp DESC
        LIMIT $3 OFFSET $4
        "#,
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
#[tracing::instrument(
    level = "debug",
    skip(admin_pool),
    fields(event_filter = ?event_filter, limit, offset),
    err
)]
pub async fn buscar_audit_logs_admin(
    admin_pool: &PgPool,
    event_filter: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at, user_agent
        FROM audit_log
        WHERE ($1::text IS NULL OR event = $1)
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#,
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
#[tracing::instrument(level = "debug", skip(admin_pool), fields(limit, offset), err)]
pub async fn buscar_audit_logs_globais(
    admin_pool: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at, user_agent
        FROM audit_log
        WHERE tenant_id IS NULL
        ORDER BY timestamp DESC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(admin_pool)
    .await?;

    Ok(rows)
}

// ============================================================
// B3 — atividade do próprio tenant ("o que o agente fez")
// ============================================================

/// Recorte da trilha que a aba "Atividade" pede.
#[derive(Debug, Clone, Default)]
pub struct FiltroAtividade {
    /// `""` = tudo, `"mcp"` = só agentes, `"painel"` = só pessoas.
    pub origem: String,
    /// `Some` restringe ao que foi feito em nome de um usuário.
    pub user_id: Option<i32>,
    /// `Some` restringe a um aplicativo conectado.
    pub grant_id: Option<Uuid>,
    pub desde: Option<chrono::DateTime<chrono::Utc>>,
    pub limit: i64,
    pub offset: i64,
}

/// Prefixo que o `mcp_server` põe no `user-agent` de toda chamada de agente.
pub const PREFIXO_USER_AGENT_MCP: &str = "SmartCoreAssistant-MCP/";

/// Origem e operação a partir do `user_agent` gravado.
///
/// O formato é `SmartCoreAssistant-MCP/<tool> (grant <uuid>)`. Derivar daqui, e
/// não de uma coluna nova, é o que a N13.7 decidiu: o `user_agent` já é gravado
/// desde então exatamente para isso, e duas colunas dizendo a mesma coisa
/// acabariam discordando.
pub fn origem_e_tool(user_agent: Option<&str>) -> (&'static str, String) {
    match user_agent.and_then(|ua| ua.strip_prefix(PREFIXO_USER_AGENT_MCP)) {
        Some(resto) => (
            "mcp",
            resto
                .split_whitespace()
                .next()
                .unwrap_or_default()
                .to_string(),
        ),
        None => ("painel", String::new()),
    }
}

/// A trilha do tenant, do mais recente para o mais antigo, já traduzida para o
/// que a tela mostra.
///
/// **Sem `message` nem `context`.** Alguns eventos guardam nome ou e-mail na
/// mensagem (o de convite, por exemplo), e a aba de atividade não mostra dado
/// pessoal — não é a tela que deve decidir o que esconder, é o que chega a ela.
///
/// A consulta de leitura da própria trilha (`audit_log_consultado`) fica de
/// fora: abrir a aba geraria uma linha nova a cada vez, e a lista viraria o
/// registro de quem olhou a lista.
#[tracing::instrument(level = "debug", skip(tx, filtro), fields(tenant_id = %tenant_id), err)]
pub async fn buscar_atividade_do_tenant(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    filtro: &FiltroAtividade,
) -> Result<Vec<serde_json::Value>, DbError> {
    use sqlx::Row;

    let linhas = sqlx::query(
        r#"
        SELECT a.timestamp, a.event, a.user_agent, a.user_id,
               COALESCE(NULLIF(u.first_name, ''), u.username) AS user_nome,
               g.client_name,
               g.id AS grant_id
        FROM audit_log a
        LEFT JOIN auth_user u ON u.id = a.user_id
        LEFT JOIN mcp_oauth_grant g
               ON g.id::text = substring(a.user_agent from '\(grant ([0-9a-fA-F-]{36})\)')
        WHERE a.tenant_id = $1
          AND a.event <> 'audit_log_consultado'
          AND ($2::text = ''
               OR ($2::text = 'mcp' AND a.user_agent LIKE 'SmartCoreAssistant-MCP/%')
               OR ($2::text = 'painel'
                   AND COALESCE(a.user_agent, '') NOT LIKE 'SmartCoreAssistant-MCP/%'))
          AND ($3::int IS NULL OR a.user_id = $3)
          AND ($4::uuid IS NULL OR g.id = $4)
          AND ($5::timestamptz IS NULL OR a.timestamp >= $5)
        ORDER BY a.timestamp DESC
        LIMIT $6 OFFSET $7
        "#,
    )
    .bind(tenant_id)
    .bind(&filtro.origem)
    .bind(filtro.user_id)
    .bind(filtro.grant_id)
    .bind(filtro.desde)
    .bind(filtro.limit)
    .bind(filtro.offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(linhas
        .iter()
        .map(|r| {
            let user_agent: Option<String> = r.try_get("user_agent").ok().flatten();
            let (origem, tool) = origem_e_tool(user_agent.as_deref());
            serde_json::json!({
                "timestamp": r
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("timestamp")
                    .map(|t| t.timestamp_millis())
                    .unwrap_or(0),
                "event_type": r.try_get::<String, _>("event").unwrap_or_default(),
                "origem": origem,
                "tool": tool,
                "user_id": r.try_get::<Option<i32>, _>("user_id").ok().flatten().unwrap_or(0),
                "user_nome": r
                    .try_get::<Option<String>, _>("user_nome")
                    .ok()
                    .flatten()
                    .unwrap_or_default(),
                "client_name": r
                    .try_get::<Option<String>, _>("client_name")
                    .ok()
                    .flatten()
                    .unwrap_or_default(),
                "grant_id": r
                    .try_get::<Option<Uuid>, _>("grant_id")
                    .ok()
                    .flatten()
                    .map(|g| g.to_string())
                    .unwrap_or_default(),
            })
        })
        .collect())
}

#[cfg(test)]
mod tests_atividade {
    use super::*;

    #[test]
    fn chamada_de_agente_da_a_origem_e_a_tool() {
        let ua = "SmartCoreAssistant-MCP/SendOutboundMessage (grant 3f2504e0-4f89-11d3-9a0c-0305e82c3301)";
        assert_eq!(
            origem_e_tool(Some(ua)),
            ("mcp", "SendOutboundMessage".to_string())
        );
    }

    #[test]
    fn user_agent_antigo_sem_grant_ainda_e_agente() {
        // Linhas gravadas antes de o grant entrar no user-agent continuam
        // sendo de agente — só não dizem de qual aplicativo.
        assert_eq!(
            origem_e_tool(Some("SmartCoreAssistant-MCP/GetMyPainel")),
            ("mcp", "GetMyPainel".to_string())
        );
    }

    #[test]
    fn navegador_ou_sem_user_agent_e_painel() {
        assert_eq!(origem_e_tool(Some("Mozilla/5.0")).0, "painel");
        assert_eq!(origem_e_tool(None).0, "painel");
    }
}
