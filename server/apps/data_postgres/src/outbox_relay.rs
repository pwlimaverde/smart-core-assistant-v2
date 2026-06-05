//! Relay de Outbox: escuta notificações do banco via LISTEN/NOTIFY e publica
//! os eventos pendentes no Redis Streams para replicação assíncrona.

use sqlx::{PgPool, postgres::PgListener};
use redis::aio::ConnectionManager;
use uuid::Uuid;
use chrono::Utc;
use std::time::Duration;

/// Estrutura para mapeamento de linhas do outbox
#[derive(sqlx::FromRow)]
struct OutboxRow {
    id: Uuid,
    tenant_id: Uuid,
    event_type: String,
    payload: Vec<u8>,
    occurred_at: chrono::DateTime<Utc>,
}

/// Relay que consome a tabela `outbox` do Postgres e envia para o Redis Streams.
pub struct OutboxRelay {
    pool: PgPool,
    redis_conn: ConnectionManager,
}

impl OutboxRelay {
    /// Cria uma nova instância do OutboxRelay.
    pub fn new(pool: PgPool, redis_conn: ConnectionManager) -> Self {
        Self { pool, redis_conn }
    }

    /// Loop principal de execução do relay.
    pub async fn run(&self) -> anyhow::Result<()> {
        let mut listener = PgListener::connect_with(&self.pool).await?;
        listener.listen("outbox_new").await?;
        
        tracing::info!("Outbox Relay iniciado e escutando canal 'outbox_new' no Postgres.");

        // Drenagem inicial ao subir para processar pendências anteriores
        if let Err(e) = self.drenar_outbox().await {
            tracing::error!("Erro na drenagem inicial do outbox: {:?}", e);
        }

        loop {
            match listener.recv().await {
                Ok(_) => {
                    if let Err(e) = self.drenar_outbox().await {
                        tracing::error!("Erro ao drenar outbox após notificação: {:?}", e);
                    }
                }
                Err(e) => {
                    tracing::error!("Erro na conexão do PgListener: {:?}. Tentando reconectar...", e);
                    tokio::time::sleep(Duration::from_secs(2)).await;
                    if let Ok(mut new_listener) = PgListener::connect_with(&self.pool).await {
                        if new_listener.listen("outbox_new").await.is_ok() {
                            listener = new_listener;
                            tracing::info!("PgListener reconectado com sucesso.");
                        }
                    }
                }
            }
        }
    }

    /// Busca eventos não publicados e publica no barramento do Redis.
    async fn drenar_outbox(&self) -> anyhow::Result<()> {
        let mut conn = self.redis_conn.clone();
        
        let rows = sqlx::query_as::<_, OutboxRow>(
            r#"SELECT id, tenant_id, event_type, payload, occurred_at
               FROM outbox
               WHERE published_at IS NULL
               ORDER BY occurred_at ASC
               LIMIT 100"#
        )
        .fetch_all(&self.pool)
        .await?;

        if rows.is_empty() {
            return Ok(());
        }

        tracing::debug!("Drenando {} eventos do outbox.", rows.len());

        for row in rows {
            let payload_str = match String::from_utf8(row.payload) {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!("Payload do outbox id {} não é UTF-8 válido: {:?}", row.id, e);
                    continue;
                }
            };

            let payload_json: serde_json::Value = match serde_json::from_str(&payload_str) {
                Ok(v) => v,
                Err(e) => {
                    tracing::error!("Payload do outbox id {} não é JSON válido: {:?}", row.id, e);
                    continue;
                }
            };

            let envelope = contracts::TenantEnvelope {
                tenant_id: row.tenant_id,
                event_id: row.id, // ID da linha garante idempotência no barramento
                event_type: row.event_type.clone(),
                timestamp: row.occurred_at.with_timezone(&Utc),
                payload: payload_json,
            };

            match transport::bus::publicar_evento(&mut conn, &envelope).await {
                Ok(_) => {
                    sqlx::query(
                        "UPDATE outbox SET published_at = NOW() WHERE id = $1"
                    )
                    .bind(row.id)
                    .execute(&self.pool)
                    .await?;
                }
                Err(e) => {
                    tracing::error!("Falha ao publicar evento do outbox {} no Redis: {:?}", row.id, e);
                    break;
                }
            }
        }

        Ok(())
    }
}
