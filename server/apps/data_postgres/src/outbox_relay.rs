//! Relay de Outbox: escuta notificações do banco via LISTEN/NOTIFY e publica
//! os eventos pendentes no Redis Streams para replicação assíncrona.
//!
//! A lógica de drenagem depende da port [`OutboxStore`] (DIP): os acessos ao
//! datastore (busca de pendentes, marcação de publicados) e ao barramento ficam
//! no adapter [`PgOutboxStore`], tornando `drenar` testável com mock, sem banco.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use redis::aio::ConnectionManager;
use sqlx::{postgres::PgListener, PgPool};
use std::time::Duration;
use uuid::Uuid;

/// Evento pendente lido da tabela `outbox`.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct OutboxEvent {
    pub id: Uuid,
    pub tenant_id: Uuid,
    pub event_type: String,
    pub payload: Vec<u8>,
    pub traceparent: String,
    pub occurred_at: DateTime<Utc>,
}

/// Port de drenagem do outbox (abstração): isola o datastore e o barramento.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait OutboxStore: Send + Sync {
    /// Busca até `limit` eventos ainda não publicados, mais antigos primeiro.
    async fn fetch_pending(&self, limit: i64) -> anyhow::Result<Vec<OutboxEvent>>;

    /// Publica um envelope de evento no barramento (Redis Streams).
    async fn publish_event(
        &self,
        envelope: &contracts::TenantEnvelope<serde_json::Value>,
    ) -> anyhow::Result<()>;

    /// Marca como publicados os eventos cujos ids são informados.
    async fn mark_published(&self, ids: &[Uuid]) -> anyhow::Result<()>;
}

/// Adapter Postgres+Redis da port de drenagem do outbox.
#[derive(Clone)]
pub struct PgOutboxStore {
    pool: PgPool,
    redis_conn: ConnectionManager,
}

impl PgOutboxStore {
    pub fn new(pool: PgPool, redis_conn: ConnectionManager) -> Self {
        Self { pool, redis_conn }
    }
}

#[async_trait]
impl OutboxStore for PgOutboxStore {
    async fn fetch_pending(&self, limit: i64) -> anyhow::Result<Vec<OutboxEvent>> {
        let rows = sqlx::query_as::<_, OutboxEvent>(
            r#"SELECT id, tenant_id, event_type, payload, traceparent, occurred_at
               FROM outbox
               WHERE published_at IS NULL
               ORDER BY occurred_at ASC
               LIMIT $1"#,
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    async fn publish_event(
        &self,
        envelope: &contracts::TenantEnvelope<serde_json::Value>,
    ) -> anyhow::Result<()> {
        let mut conn = self.redis_conn.clone();
        transport::bus::publicar_evento(&mut conn, envelope)
            .await
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;
        Ok(())
    }

    async fn mark_published(&self, ids: &[Uuid]) -> anyhow::Result<()> {
        sqlx::query("UPDATE outbox SET published_at = NOW() WHERE id = ANY($1)")
            .bind(ids)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

/// Drena os eventos pendentes do outbox via port (testável com mock).
/// Publica cada evento no barramento e, ao final, marca os publicados. Em caso de
/// falha de publicação, interrompe o lote (os não publicados ficam para a próxima).
async fn drenar(store: &dyn OutboxStore) -> anyhow::Result<()> {
    let rows = store.fetch_pending(100).await?;
    if rows.is_empty() {
        return Ok(());
    }

    tracing::debug!("Drenando {} eventos do outbox.", rows.len());

    let mut publicados: Vec<Uuid> = Vec::with_capacity(rows.len());
    for row in rows {
        let payload_str = match String::from_utf8(row.payload) {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(
                    "Payload do outbox id {} não é UTF-8 válido: {:?}",
                    row.id,
                    e
                );
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
            // Propaga o traceparent persistido no outbox, mantendo o trace distribuído
            // vivo no salto assíncrono persistência → relay → barramento.
            traceparent: row.traceparent.clone(),
            payload: payload_json,
        };

        match store.publish_event(&envelope).await {
            Ok(_) => publicados.push(row.id),
            Err(e) => {
                tracing::error!(
                    "Falha ao publicar evento do outbox {} no Redis: {:?}",
                    row.id,
                    e
                );
                break;
            }
        }
    }

    if !publicados.is_empty() {
        store.mark_published(&publicados).await?;
    }

    Ok(())
}

/// Relay que consome a tabela `outbox` do Postgres e envia para o Redis Streams.
pub struct OutboxRelay {
    pool: PgPool,
    store: PgOutboxStore,
}

impl OutboxRelay {
    /// Cria uma nova instância do OutboxRelay.
    pub fn new(pool: PgPool, redis_conn: ConnectionManager) -> Self {
        let store = PgOutboxStore::new(pool.clone(), redis_conn);
        Self { pool, store }
    }

    /// Loop principal de execução do relay.
    pub async fn run(&self) -> anyhow::Result<()> {
        let mut listener = PgListener::connect_with(&self.pool).await?;
        listener.listen("outbox_new").await?;

        tracing::info!("Outbox Relay iniciado e escutando canal 'outbox_new' no Postgres.");

        // Drenagem inicial ao subir para processar pendências anteriores
        if let Err(e) = drenar(&self.store).await {
            tracing::error!("Erro na drenagem inicial do outbox: {:?}", e);
        }

        loop {
            match listener.recv().await {
                Ok(_) => {
                    if let Err(e) = drenar(&self.store).await {
                        tracing::error!("Erro ao drenar outbox após notificação: {:?}", e);
                    }
                }
                Err(e) => {
                    tracing::error!(
                        "Erro na conexão do PgListener: {:?}. Tentando reconectar...",
                        e
                    );
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    /// Teste UNITÁRIO da drenagem: sem banco/Redis, via `MockOutboxStore`.
    /// Verifica que os eventos pendentes são publicados e marcados como publicados.
    #[tokio::test]
    async fn drenar_publishes_and_marks_pending_events() {
        // Arrange: um evento pendente; publish OK; espera-se mark_published com o id.
        let event_id = Uuid::now_v7();
        let mut store = MockOutboxStore::new();
        store.expect_fetch_pending().times(1).returning(move |_| {
            Ok(vec![OutboxEvent {
                id: event_id,
                tenant_id: Uuid::nil(),
                event_type: "outbox.test".to_string(),
                payload: serde_json::to_vec(&serde_json::json!({ "teste": "outbox" })).unwrap(),
                traceparent: "00-trace-1-span-1-01".to_string(),
                occurred_at: Utc::now(),
            }])
        });
        store.expect_publish_event().times(1).returning(|_| Ok(()));
        store
            .expect_mark_published()
            .withf(move |ids| ids == [event_id])
            .times(1)
            .returning(|_| Ok(()));

        // Act
        let res = drenar(&store).await;

        // Assert
        assert!(res.is_ok(), "drenar falhou: {:?}", res.err());
    }

    /// FAIL-CLOSED: payload não-JSON é descartado (continue) e NÃO marca publicado.
    #[tokio::test]
    async fn drenar_skips_invalid_payload_without_marking() {
        // Arrange: payload inválido (não-JSON) → nenhum publish, nenhum mark.
        let mut store = MockOutboxStore::new();
        store.expect_fetch_pending().times(1).returning(|_| {
            Ok(vec![OutboxEvent {
                id: Uuid::now_v7(),
                tenant_id: Uuid::nil(),
                event_type: "outbox.test".to_string(),
                payload: b"\xff\xfe-nao-json".to_vec(),
                traceparent: "00-t-s-01".to_string(),
                occurred_at: Utc::now(),
            }])
        });
        store.expect_publish_event().never();
        store.expect_mark_published().never();

        // Act
        let res = drenar(&store).await;

        // Assert
        assert!(res.is_ok());
    }
}
