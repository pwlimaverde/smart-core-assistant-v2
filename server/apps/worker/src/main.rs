//! Serviço worker: Consumidor em background que consome do barramento e orquestra processos de domínio.

use std::time::Duration;
use redis::aio::ConnectionManager;
use uuid::Uuid;
use contracts::{Envelope, MessageKind};

#[derive(Clone)]
struct AppState {}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("worker", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    tracing::info!("Iniciando serviço worker...");

    // 2. Conecta ao Redis para escutar eventos
    let redis_url = std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client).await?;
    tracing::info!("Conexão com Redis estabelecida.");

    let _state = AppState {};

    // 3. Inicia o consumidor do barramento (events:stream)
    let consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "worker_group",
        "worker_consumer_1",
        redis_conn,
    );

    tracing::info!("Consumidor do worker ativado e escutando eventos.");

    // Loop de consumo
    if let Err(e) = consumer.run(move |evt| {
        async move {
            if evt.event_type == "message.received" {
                if let Err(err) = processar_mensagem_recebida(evt).await {
                    tracing::error!("Erro ao processar mensagem recebida no worker: {:?}", err);
                }
            }
        }
    }).await {
        tracing::error!("Consumidor do worker parou com erro crítico: {:?}", e);
    }

    Ok(())
}

/// Consome o evento "message.received", orquestra e delega persistência ao data_postgres via RPC síncrono.
async fn processar_mensagem_recebida(evt: transport::bus::EventoBruto) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;
    let content = envelope.payload.get("content").and_then(|v| v.as_str()).unwrap_or("");
    let sender_id = envelope.payload.get("sender_id").and_then(|v| v.as_str()).unwrap_or("externo");
    
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
        traceparent: format!("00-00000000000000000000000000000000-0000000000000000-00"),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "PersistMessage".to_string(),
        payload: serde_json::to_vec(&persist_payload).unwrap_or_default(),
        error: None,
    };

    let resp = pg_client.call(req_envelope, Duration::from_secs(5)).await?;

    if resp.kind == MessageKind::Error as i32 {
        if let Some(err) = resp.error {
            anyhow::bail!("Falha na persistência da mensagem via data_postgres RPC: {}", err.message);
        }
        anyhow::bail!("Erro desconhecido na persistência RPC do data_postgres.");
    }

    tracing::info!(
        event_id = %envelope.event_id,
        "Mensagem persistida com sucesso via RPC síncrono do data_postgres."
    );

    Ok(())
}
