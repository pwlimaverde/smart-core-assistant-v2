//! Serviço worker: Consumidor em background que consome do barramento e orquestra processos de domínio.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use std::time::Duration;
use uuid::Uuid;

#[derive(Clone)]
struct AppState {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("worker", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço worker...");

    // 2. Conecta ao Redis para escutar eventos
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let _redis_conn = ConnectionManager::new(redis_client.clone()).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    let _state = AppState {};

    // 3. Inicia o consumidor do barramento (events:stream)
    let consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "worker_group",
        "worker_consumer_1",
        redis_client.clone(),
    );

    tracing::info!("Consumidor do worker ativado e escutando eventos.");

    // Loop de consumo
    if let Err(e) = consumer
        .run(move |evt| async move {
            if evt.event_type == "message.received" {
                processar_mensagem_recebida(evt).await?;
            }
            Ok(())
        })
        .await
    {
        tracing::error!("Consumidor do worker parou com erro crítico: {:?}", e);
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::time::Duration;
    use transport::bus::EventoBruto;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    static WORKER_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    fn evento_message_received(tenant_id: &str) -> EventoBruto {
        let payload = serde_json::json!({
            "content": "Preciso de ajuda",
            "sender_id": "whatsapp:5511999999",
            "timestamp": chrono::Utc::now().timestamp_millis(),
        });
        EventoBruto {
            stream_id: "1234567890-0".to_string(),
            tenant_id: tenant_id.to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-01-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sucesso() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29220";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers").route("PersistMessage", |env| {
            Box::pin(async move {
                let reply = serde_json::json!({ "status": "success", "message_id": 42 });
                Envelope {
                    kind: MessageKind::Reply as i32,
                    method: "PersistMessageReply".to_string(),
                    payload: serde_json::to_vec(&reply).unwrap(),
                    ..env
                }
            })
        });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(evt).await;
        assert!(
            resultado.is_ok(),
            "Esperava sucesso, obteve: {:?}",
            resultado
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_erro_rpc() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29221";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers").route("PersistMessage", |env| {
            Box::pin(async move {
                let error_env = contracts::ErrorEnvelope {
                    code: "DB_ERROR".to_string(),
                    message: "Falha ao persistir".to_string(),
                    ..Default::default()
                };
                Envelope {
                    kind: MessageKind::Error as i32,
                    method: "PersistMessageReply".to_string(),
                    error: Some(error_env),
                    ..env
                }
            })
        });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(evt).await;
        assert!(resultado.is_err(), "Esperava erro na persistência RPC");

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sem_data_postgres() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29229");

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(evt).await;
        assert!(resultado.is_err(), "Esperava erro de conexão recusada");
    }

    #[tokio::test]
    async fn test_processar_mensagem_tenant_uuid_invalido_falha_desserializacao() {
        let evt = EventoBruto {
            stream_id: "1234-0".to_string(),
            tenant_id: "nao-e-um-uuid".to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: r#"{"content":"ok","sender_id":"s"}"#.to_string(),
        };
        let resultado = processar_mensagem_recebida(evt).await;
        assert!(resultado.is_err(), "Esperava erro de UUID inválido");
    }
}

/// Consome o evento "message.received", orquestra e delega persistência ao data_postgres via RPC síncrono.
async fn processar_mensagem_recebida(evt: transport::bus::EventoBruto) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;
    let content = envelope
        .payload
        .get("content")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let sender_id = envelope
        .payload
        .get("sender_id")
        .and_then(|v| v.as_str())
        .unwrap_or("externo");

    tracing::info!(
        event_id = %envelope.event_id,
        tenant_id = %envelope.tenant_id,
        "Worker processando evento message.received."
    );

    // 1. Conecta ao microserviço data_postgres
    let pg_client = transport::conectar_cliente("data_postgres").await?;

    // 2. Envia RPC PersistMessage para persistir no Postgres sujeito a RLS e disparar Outbox
    let persist_payload = serde_json::json!({
        "atendimento_id": 1,
        "content": content,
        "tipo": "texto",
        "sender_id": sender_id,
    });

    let req_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        // Propaga o traceparent W3C carregado no evento do bus para a chamada RPC
        // downstream, fechando a cadeia de trace distribuído gateway → bus → worker → data_postgres.
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "PersistMessage".to_string(),
        payload: serde_json::to_vec(&persist_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
    };

    let resp = pg_client.call(req_envelope, Duration::from_secs(5)).await?;

    if resp.kind == MessageKind::Error as i32 {
        if let Some(err) = resp.error {
            anyhow::bail!(
                "Falha na persistência da mensagem via data_postgres RPC: {}",
                err.message
            );
        }
        anyhow::bail!("Erro desconhecido na persistência RPC do data_postgres.");
    }

    tracing::info!(
        event_id = %envelope.event_id,
        "Mensagem persistida com sucesso via RPC síncrono do data_postgres."
    );

    Ok(())
}
