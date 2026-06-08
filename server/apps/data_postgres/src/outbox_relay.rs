//! Relay de Outbox: escuta notificações do banco via LISTEN/NOTIFY e publica
//! os eventos pendentes no Redis Streams para replicação assíncrona.

use chrono::Utc;
use redis::aio::ConnectionManager;
use sqlx::{postgres::PgListener, PgPool};
use std::time::Duration;
use uuid::Uuid;

/// Estrutura para mapeamento de linhas do outbox
#[derive(sqlx::FromRow)]
struct OutboxRow {
    id: Uuid,
    tenant_id: Uuid,
    event_type: String,
    payload: Vec<u8>,
    traceparent: String,
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

    /// Busca eventos não publicados e publica no barramento do Redis.
    async fn drenar_outbox(&self) -> anyhow::Result<()> {
        let mut conn = self.redis_conn.clone();

        let rows = sqlx::query_as::<_, OutboxRow>(
            r#"SELECT id, tenant_id, event_type, payload, traceparent, occurred_at
               FROM outbox
               WHERE published_at IS NULL
               ORDER BY occurred_at ASC
               LIMIT 100"#,
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

            match transport::bus::publicar_evento(&mut conn, &envelope).await {
                Ok(_) => {
                    sqlx::query("UPDATE outbox SET published_at = NOW() WHERE id = $1")
                        .bind(row.id)
                        .execute(&self.pool)
                        .await?;
                }
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

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn carregar_env_teste() {
        test_support::ensure_tunnel();
        let caminhos = vec![
            ".env",
            "../.env",
            "../../.env",
            "apps/data_postgres/.env",
            "../data_postgres/.env",
        ];
        for caminho in caminhos {
            if let Ok(conteudo) = std::fs::read_to_string(caminho) {
                for linha in conteudo.lines() {
                    let linha_limpa = linha.trim();
                    if linha_limpa.is_empty() || linha_limpa.starts_with('#') {
                        continue;
                    }
                    if let Some((chave, valor)) = linha_limpa.split_once('=') {
                        let chave = chave.trim();
                        let valor = valor.trim().trim_matches('"').trim_matches('\'');
                        if std::env::var(chave).is_err() {
                            std::env::set_var(chave, valor);
                        }
                    }
                }
                break;
            }
        }
    }

    #[tokio::test]
    async fn test_outbox_relay_drenar() {
        carregar_env_teste();

        let admin_url = std::env::var("DATABASE_ADMIN_URL").expect("DATABASE_ADMIN_URL ausente");
        let pool = PgPool::connect(&admin_url)
            .await
            .expect("Falha ao conectar Postgres");

        infrastructure_postgres::inicializar_banco_dados(&pool)
            .await
            .unwrap();

        // Garante o auth_user id=1 (owner do tenant inserido abaixo). Idempotente:
        // existe no banco compartilhado, é criado no banco limpo do CI. A sequence é
        // avançada para não colidir com inserts de id automático em outros testes.
        sqlx::query(
            "INSERT INTO auth_user (id, username, email, password_hash, is_superuser, is_staff) \
             VALUES (1, 'ci_seed_admin', 'ci-seed@local', '', TRUE, TRUE) \
             ON CONFLICT (id) DO NOTHING",
        )
        .execute(&pool)
        .await
        .expect("falha ao semear auth_user padrão");
        sqlx::query(
            "SELECT setval(pg_get_serial_sequence('auth_user','id'), \
             GREATEST((SELECT COALESCE(MAX(id), 1) FROM auth_user), 1))",
        )
        .execute(&pool)
        .await
        .expect("falha ao ajustar a sequence de auth_user");

        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6380".to_string());
        let redis_client = redis::Client::open(redis_url).unwrap();
        let redis_conn = ConnectionManager::new(redis_client).await.unwrap();

        let relay = OutboxRelay::new(pool.clone(), redis_conn.clone());

        // Cria registros no outbox
        let tenant_id = Uuid::new_v4();
        let slug = format!("tenant-{}", Uuid::new_v4());
        sqlx::query(
            "INSERT INTO tenants_tenant (id, name, slug, api_key, owner_id) VALUES ($1, $2, $3, $4, 1)"
        )
        .bind(tenant_id)
        .bind("Tenant Outbox Test")
        .bind(&slug)
        .bind(Uuid::new_v4().to_string())
        .execute(&pool)
        .await
        .unwrap();

        let event_id = Uuid::now_v7();
        let payload = serde_json::json!({"teste": "outbox"});
        let payload_bytes = serde_json::to_vec(&payload).unwrap();
        let traceparent = "00-trace-1-span-1-01".to_string();

        sqlx::query(
            "INSERT INTO outbox (id, tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4, $5)"
        )
        .bind(event_id)
        .bind(tenant_id)
        .bind("outbox.test")
        .bind(payload_bytes)
        .bind(traceparent)
        .execute(&pool)
        .await
        .unwrap();

        // Executa drenar_outbox
        let drenou = relay.drenar_outbox().await;
        assert!(drenou.is_ok(), "Falha ao drenar outbox: {:?}", drenou.err());

        // Verifica se o registro foi marcado como publicado
        let row: (Option<chrono::DateTime<Utc>>,) =
            sqlx::query_as("SELECT published_at FROM outbox WHERE id = $1")
                .bind(event_id)
                .fetch_one(&pool)
                .await
                .unwrap();
        assert!(row.0.is_some(), "Deveria ter marcado como publicado");

        // Limpeza
        sqlx::query("DELETE FROM outbox WHERE id = $1")
            .bind(event_id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("DELETE FROM tenants_tenant WHERE id = $1")
            .bind(tenant_id)
            .execute(&pool)
            .await
            .unwrap();
    }
}
