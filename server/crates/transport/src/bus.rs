// transport/src/bus.rs  (comentários em pt-br)
use chrono::{DateTime, Utc};
use redis::aio::ConnectionManager;
use redis::streams::{StreamMaxlen, StreamReadOptions, StreamReadReply};
use redis::AsyncCommands;
use serde::de::DeserializeOwned;
use serde::Serialize;
use uuid::Uuid;
use crate::error::TransportError;
use contracts::TenantEnvelope;

/// Stream único de eventos do domínio. O `messaging_gateway` publica; o `worker` consome
/// via consumer groups.
pub const STREAM_EVENTOS: &str = "events:stream";
pub const STREAM_SEGURANCA: &str = "security:stream";

/// Limite aproximado do tamanho do stream (evita crescimento ilimitado de memória).
const MAXLEN_APROX: usize = 10_000;

/// Evento lido do stream em forma bruta (campos como strings). Use
/// [`EventoBruto::desserializar`] para reconstruir o `TenantEnvelope<T>` tipado.
#[derive(Debug, Clone)]
pub struct EventoBruto {
    /// ID atribuído pelo Redis (`<ms>-<seq>`), usado para `XACK`/replay.
    pub stream_id: String,
    pub tenant_id: String,
    pub event_id: String,
    pub event_type: String,
    pub timestamp: String,
    pub payload: String,
}

impl EventoBruto {
    /// Reconstrói o envelope tipado a partir dos campos brutos.
    pub fn desserializar<T: DeserializeOwned>(&self) -> Result<TenantEnvelope<T>, TransportError> {
        let tenant_id = Uuid::parse_str(&self.tenant_id)
            .map_err(|e| TransportError::Codec(format!("tenant_id inválido: {e}")))?;
        let event_id = Uuid::parse_str(&self.event_id)
            .map_err(|e| TransportError::Codec(format!("event_id inválido: {e}")))?;
        let timestamp = DateTime::parse_from_rfc3339(&self.timestamp)
            .map_err(|e| TransportError::Codec(format!("timestamp inválido: {e}")))?
            .with_timezone(&Utc);
        let payload: T = serde_json::from_str(&self.payload)
            .map_err(|e| TransportError::Codec(format!("erro desserializacao payload: {e}")))?;
        Ok(TenantEnvelope {
            tenant_id,
            event_id,
            event_type: self.event_type.clone(),
            timestamp,
            payload,
        })
    }
}

/// Publica um evento no barramento padrão (`STREAM_EVENTOS`).
pub async fn publicar_evento<T: Serialize>(
    con: &mut ConnectionManager,
    evento: &TenantEnvelope<T>,
) -> Result<String, TransportError> {
    publicar_evento_no_stream(con, STREAM_EVENTOS, evento).await
}

/// Publica um evento de segurança (auditoria) no stream dedicado (`STREAM_SEGURANCA`).
pub async fn publicar_evento_seguranca<T: Serialize>(
    con: &mut ConnectionManager,
    evento: &TenantEnvelope<T>,
) -> Result<String, TransportError> {
    publicar_evento_no_stream(con, STREAM_SEGURANCA, evento).await
}

/// Publica um evento em um stream arbitrário do Redis.
#[tracing::instrument(
    skip(con, evento),
    fields(
        stream = %stream,
        tenant_id = %evento.tenant_id,
        event_id = %evento.event_id,
        event_type = %evento.event_type,
    ),
    err
)]
pub async fn publicar_evento_no_stream<T: Serialize>(
    con: &mut ConnectionManager,
    stream: &str,
    evento: &TenantEnvelope<T>,
) -> Result<String, TransportError> {
    let payload = serde_json::to_string(&evento.payload)
        .map_err(|e| TransportError::Codec(format!("erro serializacao payload: {e}")))?;
    let id: String = con
        .xadd_maxlen(
            stream,
            StreamMaxlen::Approx(MAXLEN_APROX),
            "*",
            &[
                ("tenant_id", evento.tenant_id.to_string()),
                ("event_id", evento.event_id.to_string()),
                ("event_type", evento.event_type.clone()),
                ("timestamp", evento.timestamp.to_rfc3339()),
                ("payload", payload),
            ],
        )
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
    tracing::debug!(stream_id = %id, "evento publicado no barramento");
    Ok(id)
}

/// Garante a existência do consumer group (idempotente) no stream padrão.
#[tracing::instrument(skip(con), fields(grupo = %grupo), err)]
pub async fn garantir_consumer_group(
    con: &mut ConnectionManager,
    grupo: &str,
) -> Result<(), TransportError> {
    garantir_consumer_group_stream(con, STREAM_EVENTOS, grupo).await
}

/// Consome novos eventos para o `consumidor` dentro do `grupo` no stream padrão.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(grupo = %grupo, consumidor = %consumidor, quantidade, block_ms),
    err
)]
pub async fn consumir(
    con: &mut ConnectionManager,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
    block_ms: usize,
) -> Result<Vec<EventoBruto>, TransportError> {
    consumir_stream(con, STREAM_EVENTOS, grupo, consumidor, quantidade, block_ms).await
}

/// Relê as mensagens já entregues a este `consumidor` mas ainda não confirmadas (PEL) no stream padrão.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(grupo = %grupo, consumidor = %consumidor, quantidade),
    err
)]
pub async fn reprocessar_pendentes(
    con: &mut ConnectionManager,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
) -> Result<Vec<EventoBruto>, TransportError> {
    reprocessar_pendentes_stream(con, STREAM_EVENTOS, grupo, consumidor, quantidade).await
}

/// Confirma o processamento de um evento (`XACK`) no stream padrão.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(grupo = %grupo, stream_id = %stream_id),
    err
)]
pub async fn confirmar(
    con: &mut ConnectionManager,
    grupo: &str,
    stream_id: &str,
) -> Result<(), TransportError> {
    confirmar_stream(con, STREAM_EVENTOS, grupo, stream_id).await
}

/// Garante a existência do consumer group (idempotente) em um stream específico.
#[tracing::instrument(skip(con), fields(stream = %stream, grupo = %grupo), err)]
pub async fn garantir_consumer_group_stream(
    con: &mut ConnectionManager,
    stream: &str,
    grupo: &str,
) -> Result<(), TransportError> {
    let resultado: redis::RedisResult<()> = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(stream)
        .arg(grupo)
        .arg("$")
        .arg("MKSTREAM")
        .query_async(con)
        .await;
    match resultado {
        Ok(()) => {
            tracing::info!("consumer group criado no stream '{}'", stream);
            Ok(())
        }
        Err(e) if e.code() == Some("BUSYGROUP") => {
            tracing::debug!("consumer group já existia (BUSYGROUP) no stream '{}'", stream);
            Ok(())
        }
        Err(e) => Err(TransportError::Bus(e.to_string())),
    }
}

/// Consome novos eventos de um stream específico para o `consumidor` dentro do `grupo`.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(stream = %stream, grupo = %grupo, consumidor = %consumidor, quantidade, block_ms),
    err
)]
pub async fn consumir_stream(
    con: &mut ConnectionManager,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
    block_ms: usize,
) -> Result<Vec<EventoBruto>, TransportError> {
    let mut opts = StreamReadOptions::default()
        .group(grupo, consumidor)
        .count(quantidade);
    if block_ms > 0 {
        opts = opts.block(block_ms);
    }
    let reply: StreamReadReply = con
        .xread_options(&[stream], &[">"], &opts)
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
    let eventos = extrair_eventos(reply);
    tracing::debug!(eventos = eventos.len(), "eventos consumidos do barramento");
    Ok(eventos)
}

/// Relê as mensagens já entregues a este `consumidor` mas ainda não confirmadas (PEL) no stream.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(stream = %stream, grupo = %grupo, consumidor = %consumidor, quantidade),
    err
)]
pub async fn reprocessar_pendentes_stream(
    con: &mut ConnectionManager,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
) -> Result<Vec<EventoBruto>, TransportError> {
    let opts = StreamReadOptions::default()
        .group(grupo, consumidor)
        .count(quantidade);
    let reply: StreamReadReply = con
        .xread_options(&[stream], &["0"], &opts)
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
    let eventos = extrair_eventos(reply);
    if !eventos.is_empty() {
        tracing::info!(pendentes = eventos.len(), "reprocessando eventos pendentes (PEL)");
    }
    Ok(eventos)
}

/// Confirma o processamento de um evento (`XACK`) no stream.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(stream = %stream, grupo = %grupo, stream_id = %stream_id),
    err
)]
pub async fn confirmar_stream(
    con: &mut ConnectionManager,
    stream: &str,
    grupo: &str,
    stream_id: &str,
) -> Result<(), TransportError> {
    let _: i64 = con
        .xack(stream, grupo, &[stream_id])
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
    Ok(())
}

/// Converte a resposta do `XREADGROUP` em uma lista de [`EventoBruto`].
fn extrair_eventos(reply: StreamReadReply) -> Vec<EventoBruto> {
    let mut eventos = Vec::new();
    for chave in reply.keys {
        for entrada in chave.ids {
            let campo = |nome: &str| -> String {
                entrada
                    .map
                    .get(nome)
                    .and_then(|v| redis::from_redis_value::<String>(v).ok())
                    .unwrap_or_default()
            };
            eventos.push(EventoBruto {
                stream_id: entrada.id.clone(),
                tenant_id: campo("tenant_id"),
                event_id: campo("event_id"),
                event_type: campo("event_type"),
                timestamp: campo("timestamp"),
                payload: campo("payload"),
            });
        }
    }
    eventos
}

/// Consumidor de alto nível para o barramento de eventos do Redis Streams.
/// Encapsula o ciclo de leitura de pendentes (PEL), loop de consumo ativo e confirmação (XACK).
pub struct Consumer {
    stream: String,
    grupo: String,
    consumidor: String,
    redis_conn: ConnectionManager,
}

impl Consumer {
    /// Cria uma nova instância do Consumer para um stream específico.
    pub fn new(
        stream: impl Into<String>,
        grupo: impl Into<String>,
        consumidor: impl Into<String>,
        redis_conn: ConnectionManager,
    ) -> Self {
        Self {
            stream: stream.into(),
            grupo: grupo.into(),
            consumidor: consumidor.into(),
            redis_conn,
        }
    }

    /// Executa o loop de consumo de eventos indefinidamente.
    /// Para cada evento recebido, executa o `handler` fornecido e confirma o processamento.
    pub async fn run<F, Fut>(&self, handler: F) -> anyhow::Result<()>
    where
        F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = ()> + Send + 'static,
    {
        let mut con = self.redis_conn.clone();
        garantir_consumer_group_stream(&mut con, &self.stream, &self.grupo).await?;

        tracing::info!(
            "Consumidor do grupo '{}' iniciado no stream '{}' para o consumidor '{}'.",
            self.grupo,
            self.stream,
            self.consumidor
        );

        // 1. Processar pendências da lista PEL (Pending Entries List)
        match reprocessar_pendentes_stream(&mut con, &self.stream, &self.grupo, &self.consumidor, 10).await {
            Ok(pendentes) => {
                for evento in pendentes {
                    handler(evento.clone()).await;
                    let _ = confirmar_stream(&mut con, &self.stream, &self.grupo, &evento.stream_id).await;
                }
            }
            Err(e) => {
                tracing::warn!("Erro ao reprocessar pendentes na inicialização: {:?}", e);
            }
        }

        // 2. Loop de consumo ativo
        loop {
            match consumir_stream(&mut con, &self.stream, &self.grupo, &self.consumidor, 10, 1000).await {
                Ok(eventos) => {
                    for evento in eventos {
                        handler(evento.clone()).await;
                        let _ = confirmar_stream(&mut con, &self.stream, &self.grupo, &evento.stream_id).await;
                    }
                }
                Err(e) => {
                    tracing::error!("Erro consumindo do Redis Streams: {:?}. Aguardando re-tentativa...", e);
                    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                }
            }
        }
    }
}
