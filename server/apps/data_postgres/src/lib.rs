//! Biblioteca interna do `data_postgres`: expõe peças testáveis em **integração**
//! (banco real) reusadas pelo binário (`main.rs`). Hoje contém o consumidor de
//! auditoria, que persiste no Postgres e por isso é coberto por um teste de
//! integração em `tests/`, fora do caminho rápido `--bins`.

use infrastructure_postgres::{inserir_audit_log, NewAuditLogEntry};
use uuid::Uuid;

/// Consolida múltiplos eventos de auditoria vindos do barramento de segurança no banco
/// de dados em lote. Agrupa os eventos por inquilino e os insere sob uma transação por
/// inquilino (ou transação global). Retorna a lista de IDs de stream gravados com sucesso.
pub async fn processar_eventos_auditoria_lote(
    pool: sqlx::PgPool,
    eventos: Vec<transport::bus::EventoBruto>,
) -> anyhow::Result<Vec<String>> {
    use sqlx::Row;
    use std::collections::HashMap;

    let mut agrupamento_tenant: HashMap<Uuid, Vec<(String, NewAuditLogEntry)>> = HashMap::new();
    let mut globais: Vec<(String, NewAuditLogEntry)> = Vec::new();
    let mut sucessos = Vec::with_capacity(eventos.len());

    for evt in eventos {
        // Tentamos desserializar. Se der erro, descartamos o evento e marcamos como sucesso para receber XACK e não travar a fila.
        let envelope = match evt.desserializar::<observability::AuditLogPayload>() {
            Ok(env) => env,
            Err(e) => {
                tracing::error!(
                    "Falha ao desserializar evento de auditoria no lote (id={}): {:?}",
                    evt.stream_id,
                    e
                );
                sucessos.push(evt.stream_id);
                continue;
            }
        };

        let entry = NewAuditLogEntry {
            tenant_id: envelope.payload.tenant_id,
            level: envelope.payload.level,
            service: envelope.payload.service,
            trace_id: envelope.payload.trace_id,
            event: envelope.payload.event,
            message: envelope.payload.message,
            context: envelope.payload.context,
            user_id: envelope.payload.user_id,
            ip_address: envelope.payload.ip_address,
            user_agent: envelope.payload.user_agent,
        };

        if let Some(tenant_id) = envelope.payload.tenant_id {
            agrupamento_tenant
                .entry(tenant_id)
                .or_default()
                .push((evt.stream_id, entry));
        } else {
            globais.push((evt.stream_id, entry));
        }
    }

    // 1. Processa inquilinos (1 transação por inquilino)
    for (tenant_id, entries) in agrupamento_tenant {
        let result = infrastructure_postgres::run_in_tenant_transaction(
            &pool,
            tenant_id,
            |mut tx| async move {
                let mut ids = Vec::new();
                for (stream_id, entry) in &entries {
                    match inserir_audit_log(&mut tx, entry).await {
                        Ok(_) => ids.push(stream_id.clone()),
                        Err(e) => {
                            // Se falhar a inserção de um log específico de auditoria, interrompe a transação
                            return Err(e);
                        }
                    }
                }
                Ok((ids, tx))
            },
        )
        .await;

        match result {
            Ok(ids) => {
                sucessos.extend(ids);
            }
            Err(e) => {
                tracing::error!(
                    "Falha na transação de auditoria para o tenant {}: {:?}",
                    tenant_id,
                    e
                );
            }
        }
    }

    // 2. Processa globais (1 transação global para bypass de RLS)
    if !globais.is_empty() {
        let tx_result: Result<Vec<String>, sqlx::Error> = async {
            let mut tx = pool.begin().await?;
            let mut ids = Vec::new();
            for (stream_id, entry) in &globais {
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
                .fetch_one(&mut *tx)
                .await?;

                let _id: Uuid = row.get("id");
                ids.push(stream_id.clone());
            }
            tx.commit().await?;
            Ok(ids)
        }.await;

        match tx_result {
            Ok(ids) => {
                sucessos.extend(ids);
            }
            Err(e) => {
                tracing::error!(
                    "Falha ao consolidar logs de auditoria globais no Postgres: {:?}",
                    e
                );
            }
        }
    }

    Ok(sucessos)
}
