use contracts::grpc::queries::AtendimentoEvent;
use futures_util::StreamExt;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex};
use uuid::Uuid;

#[derive(Clone)]
pub struct RealtimeManager {
    redis_client: redis::Client,
    tenants: Arc<Mutex<HashMap<Uuid, broadcast::Sender<AtendimentoEvent>>>>,
}

impl RealtimeManager {
    pub fn new(redis_url: &str) -> anyhow::Result<Self> {
        let redis_client = redis::Client::open(redis_url)?;
        Ok(Self {
            redis_client,
            tenants: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    pub async fn obter_stream(
        &self,
        tenant_id: Uuid,
    ) -> Result<broadcast::Receiver<AtendimentoEvent>, tonic::Status> {
        let mut map = self.tenants.lock().await;

        if let Some(sender) = map.get(&tenant_id) {
            return Ok(sender.subscribe());
        }

        // Criar canal de broadcast
        let (tx, rx) = broadcast::channel(100);
        map.insert(tenant_id, tx.clone());

        // Iniciar subscriber em background
        let tenants_clone = self.tenants.clone();
        let client = self.redis_client.clone();
        tokio::spawn(async move {
            tracing::info!(tenant_id = %tenant_id, "Iniciando Redis Pub/Sub para tenant");
            if let Err(e) = rodar_subscriber(client, tenant_id, tx, tenants_clone).await {
                tracing::error!(tenant_id = %tenant_id, "Erro no Redis Pub/Sub subscriber: {:?}", e);
            }
        });

        Ok(rx)
    }
}

#[allow(deprecated)]
async fn rodar_subscriber(
    client: redis::Client,
    tenant_id: Uuid,
    tx: broadcast::Sender<AtendimentoEvent>,
    tenants: Arc<Mutex<HashMap<Uuid, broadcast::Sender<AtendimentoEvent>>>>,
) -> anyhow::Result<()> {
    let con = client.get_async_connection().await?;
    let mut pubsub = con.into_pubsub();
    let channel = format!("tenant:{}:events", tenant_id);
    pubsub.subscribe(&channel).await?;

    let mut stream = pubsub.on_message();
    while let Some(msg) = stream.next().await {
        // Se não houver mais receivers ativos no broadcast, podemos parar o loop
        if tx.receiver_count() == 0 {
            tracing::info!(tenant_id = %tenant_id, "Nenhum receiver gRPC ativo para tenant, encerrando subscriber");
            break;
        }

        let payload_str: String = match msg.get_payload() {
            Ok(p) => p,
            Err(e) => {
                tracing::error!("Falha ao ler payload do Pub/Sub: {:?}", e);
                continue;
            }
        };

        // Parse do JSON para extrair event_type, tenant_id e payload
        let val: serde_json::Value = match serde_json::from_str(&payload_str) {
            Ok(v) => v,
            Err(_) => continue,
        };

        let event_type = val
            .get("event_type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();
        let t_id = val
            .get("tenant_id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let payload = val
            .get("payload")
            .map(|v| v.to_string())
            .unwrap_or_default();

        let event = AtendimentoEvent {
            event_type,
            tenant_id: t_id,
            payload,
        };

        let _ = tx.send(event);
    }

    // Remover o tenant do mapa para que novas conexões recriem o subscriber
    let mut map = tenants.lock().await;
    map.remove(&tenant_id);
    Ok(())
}
