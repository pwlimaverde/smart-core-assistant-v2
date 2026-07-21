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

#[cfg(test)]
mod tests {
    use super::*;

    /// Helper de arranjo: monta um evento de atendimento simples para asserções.
    fn evento(tipo: &str) -> AtendimentoEvent {
        AtendimentoEvent {
            event_type: tipo.to_string(),
            tenant_id: "t".to_string(),
            payload: "{}".to_string(),
        }
    }

    #[test]
    fn new_with_valid_redis_url_succeeds() {
        // O construtor só faz `Client::open` (não conecta), então uma URL válida basta.
        assert!(RealtimeManager::new("redis://127.0.0.1:6379").is_ok());
    }

    #[test]
    fn new_with_invalid_url_returns_error() {
        // Esquema não-redis é rejeitado já no parsing do ConnectionInfo.
        assert!(RealtimeManager::new("http://invalid-scheme").is_err());
    }

    #[tokio::test]
    async fn obter_stream_reuses_broadcast_channel_for_same_tenant() {
        // Arrange
        let manager = RealtimeManager::new("redis://127.0.0.1:6379").expect("client");
        let tenant = Uuid::now_v7();

        // Act — duas assinaturas do mesmo tenant
        let mut rx1 = manager.obter_stream(tenant).await.expect("stream 1");
        let mut rx2 = manager.obter_stream(tenant).await.expect("stream 2");

        // Assert — há um único sender no mapa e ambos os receivers o compartilham
        let evt = evento("atendimento_criado");
        {
            let map = manager.tenants.lock().await;
            assert_eq!(map.len(), 1, "mesmo tenant não deve duplicar o canal");
            let sender = map.get(&tenant).expect("sender do tenant");
            let entregues = sender.send(evt.clone()).expect("send");
            // rx1, rx2 (o subscriber em background não é receiver do broadcast).
            assert_eq!(entregues, 2);
        }

        assert_eq!(rx1.recv().await.expect("rx1"), evt);
        assert_eq!(rx2.recv().await.expect("rx2"), evt);
    }

    #[tokio::test]
    async fn obter_stream_isolates_channels_between_tenants() {
        // Arrange
        let manager = RealtimeManager::new("redis://127.0.0.1:6379").expect("client");
        let tenant_a = Uuid::now_v7();
        let tenant_b = Uuid::now_v7();

        // Act
        let mut rx_a = manager.obter_stream(tenant_a).await.expect("stream a");
        let mut rx_b = manager.obter_stream(tenant_b).await.expect("stream b");

        let evt = evento("apenas_para_a");
        {
            let map = manager.tenants.lock().await;
            assert_eq!(map.len(), 2, "tenants distintos têm canais isolados");
            map.get(&tenant_a)
                .expect("sender a")
                .send(evt.clone())
                .expect("send a");
        }

        // Assert — o evento chega em A, mas B não enxerga nada
        assert_eq!(rx_a.recv().await.expect("rx_a"), evt);
        assert!(matches!(
            rx_b.try_recv(),
            Err(broadcast::error::TryRecvError::Empty)
        ));
    }

    #[tokio::test]
    async fn obter_stream_lagged_receiver_reports_lag() {
        // Arrange — canal de broadcast tem capacidade 100; estourá-la produz Lagged.
        let manager = RealtimeManager::new("redis://127.0.0.1:6379").expect("client");
        let tenant = Uuid::now_v7();
        let mut rx = manager.obter_stream(tenant).await.expect("stream");

        // Act — envia mais eventos do que a capacidade sem consumir
        {
            let map = manager.tenants.lock().await;
            let sender = map.get(&tenant).expect("sender");
            for i in 0..150 {
                let _ = sender.send(evento(&format!("e{i}")));
            }
        }

        // Assert — o primeiro recv sinaliza perda (Lagged), não silencia mensagens.
        assert!(matches!(
            rx.try_recv(),
            Err(broadcast::error::TryRecvError::Lagged(_))
        ));
    }
}
