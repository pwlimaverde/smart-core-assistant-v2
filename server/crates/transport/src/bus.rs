// transport/src/bus.rs  (comentários em pt-br)
#![allow(deprecated)]

use crate::error::TransportError;
use chrono::{DateTime, Utc};
use contracts::TenantEnvelope;
use redis::aio::ConnectionManager;
use redis::streams::{StreamMaxlen, StreamReadOptions, StreamReadReply, StreamPendingCountReply, StreamClaimOptions};
use redis::AsyncCommands;
use redis::{Client, aio::Connection};
use serde::de::DeserializeOwned;
use serde::Serialize;
use uuid::Uuid;

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
    /// Traceparent W3C propagado pelo barramento (vazio em eventos antigos/sem trace).
    pub traceparent: String,
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
            traceparent: self.traceparent.clone(),
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
                ("traceparent", evento.traceparent.clone()),
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
pub async fn garantir_consumer_group_stream<C>(
    con: &mut C,
    stream: &str,
    grupo: &str,
) -> Result<(), TransportError>
where
    C: redis::aio::ConnectionLike + Send,
{
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
            tracing::debug!(
                "consumer group já existia (BUSYGROUP) no stream '{}'",
                stream
            );
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
pub async fn consumir_stream<C>(
    con: &mut C,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
    block_ms: usize,
) -> Result<Vec<EventoBruto>, TransportError>
where
    C: redis::aio::ConnectionLike + Send,
{
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
pub async fn reprocessar_pendentes_stream<C>(
    con: &mut C,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
) -> Result<Vec<EventoBruto>, TransportError>
where
    C: redis::aio::ConnectionLike + Send,
{
    let opts = StreamReadOptions::default()
        .group(grupo, consumidor)
        .count(quantidade);
    let reply: StreamReadReply = con
        .xread_options(&[stream], &["0"], &opts)
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
    let eventos = extrair_eventos(reply);
    if !eventos.is_empty() {
        tracing::info!(
            pendentes = eventos.len(),
            "reprocessando eventos pendentes (PEL)"
        );
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
pub async fn confirmar_stream<C>(
    con: &mut C,
    stream: &str,
    grupo: &str,
    stream_id: &str,
) -> Result<(), TransportError>
where
    C: redis::aio::ConnectionLike + Send,
{
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
                traceparent: campo("traceparent"),
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
    client: Client,
}

impl Consumer {
    /// Cria uma nova instância do Consumer para um stream específico.
    pub fn new(
        stream: impl Into<String>,
        grupo: impl Into<String>,
        consumidor: impl Into<String>,
        client: Client,
    ) -> Self {
        Self {
            stream: stream.into(),
            grupo: grupo.into(),
            consumidor: consumidor.into(),
            client,
        }
    }

    /// Executa o loop de consumo de eventos indefinidamente.
    /// Para cada evento recebido, executa o `handler` fornecido e confirma o processamento.
    pub async fn run<F, Fut>(&self, handler: F) -> anyhow::Result<()>
    where
        F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        let mut con: Connection = self.client.get_async_connection().await
            .map_err(|e| TransportError::Bus(e.to_string()))?;
        garantir_consumer_group_stream(&mut con, &self.stream, &self.grupo).await?;

        tracing::info!(
            grupo = %self.grupo, stream = %self.stream, consumidor = %self.consumidor,
            "Consumidor iniciado em conexão dedicada."
        );

        // 1. Processar pendências da lista PEL (Pending Entries List) na inicialização
        match reprocessar_pendentes_stream(
            &mut con,
            &self.stream,
            &self.grupo,
            &self.consumidor,
            10,
        )
        .await
        {
            Ok(pendentes) => {
                for evento in pendentes {
                    match handler(evento.clone()).await {
                        Ok(()) => {
                            let _ = confirmar_stream(&mut con, &self.stream, &self.grupo, &evento.stream_id).await;
                        }
                        Err(e) => {
                            tracing::error!(
                                stream_id = %evento.stream_id, erro = ?e,
                                "reprocessador inicial: handler falhou; mantido na PEL"
                            );
                        }
                    }
                }
            }
            Err(e) => {
                tracing::warn!("Erro ao reprocessar pendentes na inicialização: {:?}", e);
            }
        }

        // 2. Loop de consumo ativo
        loop {
            match consumir_stream(
                &mut con,
                &self.stream,
                &self.grupo,
                &self.consumidor,
                10,
                1000,
            )
            .await
            {
                Ok(eventos) => {
                    for evento in eventos {
                        match handler(evento.clone()).await {
                            Ok(()) => {
                                let _ = confirmar_stream(
                                    &mut con,
                                    &self.stream,
                                    &self.grupo,
                                    &evento.stream_id,
                                )
                                .await;
                            }
                            Err(e) => {
                                tracing::error!(
                                    stream_id = %evento.stream_id, erro = ?e,
                                    "handler falhou; evento mantido na PEL para reprocessamento"
                                );
                            }
                        }
                    }
                }
                Err(e) => {
                    tracing::error!(
                        "Erro consumindo do Redis Streams: {:?}. Aguardando re-tentativa...",
                        e
                    );
                    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                }
            }
        }
    }

    /// Executa o loop de consumo de eventos em lote.
    /// O handler recebe um vetor de eventos e retorna um vetor contendo os IDs de stream processados com sucesso.
    pub async fn run_batch<F, Fut>(&self, handler: F) -> anyhow::Result<()>
    where
        F: Fn(Vec<EventoBruto>) -> Fut + Send + Sync + 'static,
        Fut: std::future::Future<Output = anyhow::Result<Vec<String>>> + Send + 'static,
    {
        let mut con: Connection = self.client.get_async_connection().await
            .map_err(|e| TransportError::Bus(e.to_string()))?;
        garantir_consumer_group_stream(&mut con, &self.stream, &self.grupo).await?;

        tracing::info!(
            grupo = %self.grupo, stream = %self.stream, consumidor = %self.consumidor,
            "Consumidor em lote iniciado em conexão dedicada."
        );

        // 1. Processar pendências da lista PEL (Pending Entries List) na inicialização
        match reprocessar_pendentes_stream(
            &mut con,
            &self.stream,
            &self.grupo,
            &self.consumidor,
            10,
        )
        .await
        {
            Ok(pendentes) => {
                if !pendentes.is_empty() {
                    match handler(pendentes).await {
                        Ok(sucessos) => {
                            for id in sucessos {
                                let _ = confirmar_stream(&mut con, &self.stream, &self.grupo, &id).await;
                            }
                        }
                        Err(e) => {
                            tracing::error!("reprocessador inicial em lote: handler falhou; mantido na PEL: {:?}", e);
                        }
                    }
                }
            }
            Err(e) => {
                tracing::warn!("Erro ao reprocessar pendentes na inicialização: {:?}", e);
            }
        }

        // 2. Loop de consumo ativo
        loop {
            match consumir_stream(
                &mut con,
                &self.stream,
                &self.grupo,
                &self.consumidor,
                10,
                1000,
            )
            .await
            {
                Ok(eventos) => {
                    if !eventos.is_empty() {
                        match handler(eventos).await {
                            Ok(sucessos) => {
                                for id in sucessos {
                                    let _ = confirmar_stream(
                                        &mut con,
                                        &self.stream,
                                        &self.grupo,
                                        &id,
                                    )
                                    .await;
                                }
                            }
                            Err(e) => {
                                tracing::error!(
                                    "handler em lote falhou; eventos mantidos na PEL para reprocessamento: {:?}",
                                    e
                                );
                            }
                        }
                    }
                }
                Err(e) => {
                    tracing::error!(
                        "Erro consumindo em lote do Redis Streams: {:?}. Aguardando re-tentativa...",
                        e
                    );
                    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                }
            }
        }
    }
}

const MAX_ENTREGAS: usize = 5;
pub const DLQ_STREAM: &str = "security:dlq";

/// Move para a DLQ os eventos da PEL entregues mais de `MAX_ENTREGAS` vezes e os confirma.
pub async fn varrer_dlq_pendentes(
    con: &mut Connection,
    stream: &str,
    grupo: &str,
    consumidor: &str,
) -> anyhow::Result<()> {
    let pend: StreamPendingCountReply = con
        .xpending_count(stream, grupo, "-", "+", 100)
        .await?;
        
    for id in pend.ids {
        if id.times_delivered > MAX_ENTREGAS {
            let opts = StreamClaimOptions::default();
            let _: redis::streams::StreamClaimReply = con
                .xclaim_options(stream, grupo, consumidor, 0, std::slice::from_ref(&id.id), opts)
                .await?;
                
            let _: String = con
                .xadd(
                    DLQ_STREAM,
                    "*",
                    &[
                        ("original_id", id.id.as_str()),
                        ("times_delivered", &id.times_delivered.to_string()),
                    ],
                )
                .await?;
                
            let _: i64 = con.xack(stream, grupo, std::slice::from_ref(&id.id)).await?;
            tracing::warn!(stream_id = %id.id, entregas = id.times_delivered, "evento movido para DLQ");
        }
    }
    Ok(())
}

/// Executa uma passada de reprocessamento da PEL no stream especificado.
pub async fn reprocessar_pendentes_uma_vez<F, Fut>(
    client: &redis::Client,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    handler: F,
) -> anyhow::Result<()>
where
    F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
{
    let mut con: Connection = client.get_async_connection().await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
        
    if let Err(e) = varrer_dlq_pendentes(&mut con, stream, grupo, consumidor).await {
        tracing::warn!("Falha ao varrer DLQ de pendentes: {:?}", e);
    }

    let pendentes = reprocessar_pendentes_stream(&mut con, stream, grupo, consumidor, 10).await?;
    for evento in pendentes {
        match handler(evento.clone()).await {
            Ok(()) => {
                let _ = confirmar_stream(&mut con, stream, grupo, &evento.stream_id).await;
            }
            Err(e) => {
                tracing::error!(
                    stream_id = %evento.stream_id, erro = ?e,
                    "reprocessador: handler falhou novamente; mantido na PEL"
                );
            }
        }
    }

    Ok(())
}

/// Executa uma passada de reprocessamento da PEL no stream especificado em lote.
pub async fn reprocessar_pendentes_uma_vez_batch<F, Fut>(
    client: &redis::Client,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    handler: F,
) -> anyhow::Result<()>
where
    F: Fn(Vec<EventoBruto>) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = anyhow::Result<Vec<String>>> + Send + 'static,
{
    let mut con: Connection = client.get_async_connection().await
        .map_err(|e| TransportError::Bus(e.to_string()))?;
        
    if let Err(e) = varrer_dlq_pendentes(&mut con, stream, grupo, consumidor).await {
        tracing::warn!("Falha ao varrer DLQ de pendentes: {:?}", e);
    }

    let pendentes = reprocessar_pendentes_stream(&mut con, stream, grupo, consumidor, 10).await?;
    if !pendentes.is_empty() {
        match handler(pendentes).await {
            Ok(sucessos) => {
                for id in sucessos {
                    let _ = confirmar_stream(&mut con, stream, grupo, &id).await;
                }
            }
            Err(e) => {
                tracing::error!("reprocessador em lote: handler falhou novamente; mantido na PEL: {:?}", e);
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evento_bruto_desserializar_success() {
        let tenant_id = Uuid::new_v4().to_string();
        let event_id = Uuid::now_v7().to_string();
        let timestamp = Utc::now().to_rfc3339();

        let raw = EventoBruto {
            stream_id: "1-0".to_string(),
            tenant_id: tenant_id.clone(),
            event_id: event_id.clone(),
            event_type: "test.event".to_string(),
            timestamp,
            traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01".to_string(),
            payload: "{\"valor\": 123}".to_string(),
        };

        let res = raw.desserializar::<serde_json::Value>();
        assert!(res.is_ok());

        let envelope = res.unwrap();
        assert_eq!(envelope.tenant_id.to_string(), tenant_id);
        assert_eq!(envelope.event_id.to_string(), event_id);
        assert_eq!(envelope.event_type, "test.event");
        assert_eq!(
            envelope.traceparent,
            "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        );
        assert_eq!(
            envelope.payload.get("valor").and_then(|v| v.as_i64()),
            Some(123)
        );
    }

    #[test]
    fn test_evento_bruto_desserializar_invalid_tenant() {
        let raw = EventoBruto {
            stream_id: "1-0".to_string(),
            tenant_id: "invalido".to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "test".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: "{}".to_string(),
        };
        assert!(raw.desserializar::<serde_json::Value>().is_err());
    }

    #[test]
    fn test_evento_bruto_desserializar_invalid_event_id() {
        let raw = EventoBruto {
            stream_id: "1-0".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            event_id: "invalido".to_string(),
            event_type: "test".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: "{}".to_string(),
        };
        assert!(raw.desserializar::<serde_json::Value>().is_err());
    }

    #[test]
    fn test_evento_bruto_desserializar_invalid_timestamp() {
        let raw = EventoBruto {
            stream_id: "1-0".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "test".to_string(),
            timestamp: "data-invalida".to_string(),
            traceparent: "".to_string(),
            payload: "{}".to_string(),
        };
        assert!(raw.desserializar::<serde_json::Value>().is_err());
    }

    #[test]
    fn test_evento_bruto_desserializar_invalid_payload() {
        let raw = EventoBruto {
            stream_id: "1-0".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "test".to_string(),
            timestamp: Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: "{invalid-json}".to_string(),
        };
        assert!(raw.desserializar::<serde_json::Value>().is_err());
    }
}
