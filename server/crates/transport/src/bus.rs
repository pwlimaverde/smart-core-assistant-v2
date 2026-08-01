// transport/src/bus.rs  (comentários em pt-br)
#![allow(deprecated)]

use crate::error::TransportError;
use chrono::{DateTime, Utc};
use contracts::TenantEnvelope;
use redis::aio::ConnectionManager;
use redis::streams::{
    StreamClaimOptions, StreamClaimReply, StreamId, StreamMaxlen, StreamPendingCountReply,
    StreamReadOptions, StreamReadReply,
};
use redis::AsyncCommands;
use redis::{aio::Connection, Client};
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

/// Nome deste processo como consumidor de um grupo, a partir de `prefixo`.
///
/// O default preserva o nome histórico (`{prefixo}_1`) para não trocar a PEL de um
/// deployment já em operação. `SMARTCORE_CONSUMER_NAME` existe para o dia em que
/// houver mais de uma réplica do mesmo serviço: duas réplicas com o MESMO nome
/// compartilham uma única PEL, e a releitura da PEL no boot de uma delas pegaria os
/// eventos que a outra está processando naquele instante — resposta duplicada ao
/// cliente. Com nome próprio por réplica, cada uma responde apenas pela sua
/// pendência, e a PEL de uma réplica que morreu é recuperada pelo piso de
/// inatividade de [`reclamar_pendentes_abandonados`], que varre o grupo inteiro.
pub fn nome_consumidor(prefixo: &str) -> String {
    std::env::var("SMARTCORE_CONSUMER_NAME")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|sufixo| format!("{prefixo}_{sufixo}"))
        .unwrap_or_else(|| format!("{prefixo}_1"))
}

/// Tempo mínimo (ms) que um evento precisa estar parado na PEL para o
/// reprocessador periódico considerá-lo ABANDONADO e reclamá-lo.
///
/// Existe porque a PEL não distingue "evento cujo handler morreu" de "evento que
/// o loop de consumo está processando neste instante": os dois estão pendentes até
/// o `XACK`. Sem um piso de inatividade, o tick de reprocessamento roda em paralelo
/// ao loop ativo e reprocessa o que está em voo — no `worker`, isso significa
/// responder duas vezes à mesma mensagem do cliente (a persistência é idempotente
/// pelo stanzaId, mas o envio ao WhatsApp não é).
///
/// O piso tem de ser MAIOR que a duração máxima de um handler. O pior caso do
/// `worker` é a resposta da IA (`SMARTCORE_IA_ENGINE_TIMEOUT_TEXT_MS` = 8s × 3
/// tentativas + backoff 0/1/2 ≈ 27s) somada às RPCs de persistência e envio;
/// 120s deixa margem confortável e ainda recupera um evento travado em ~2–3 min.
pub const MIN_IDLE_REPROCESSAMENTO_MS: usize = 120_000;

/// Reclama para `consumidor` os eventos da PEL do GRUPO que estão parados há pelo
/// menos `min_idle_ms`, devolvendo-os já prontos para reprocessar.
///
/// Duas diferenças em relação a [`reprocessar_pendentes_stream`]:
///
/// * **Piso de inatividade** (ver [`MIN_IDLE_REPROCESSAMENTO_MS`]): o `XCLAIM`
///   carrega o mesmo `min_idle_ms`, então o Redis descarta a entrada se ela tiver
///   sido entregue de novo entre o `XPENDING` e o `XCLAIM` — a proteção contra
///   reprocessar evento em voo é atômica, não uma janela de melhor esforço.
/// * **Escopo do grupo, não do consumidor**: varre a pendência de TODOS os
///   consumidores do grupo. É o que recupera a PEL órfã de uma réplica que morreu
///   (ou que foi removida numa redução de escala) — com nome de consumidor próprio
///   por réplica, ninguém mais releria aquela PEL.
#[tracing::instrument(
    level = "debug",
    skip(con),
    fields(stream = %stream, grupo = %grupo, consumidor = %consumidor, min_idle_ms, quantidade),
    err
)]
pub async fn reclamar_pendentes_abandonados<C>(
    con: &mut C,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    min_idle_ms: usize,
    quantidade: usize,
) -> Result<Vec<EventoBruto>, TransportError>
where
    C: redis::aio::ConnectionLike + Send,
{
    // `XPENDING <stream> <grupo> IDLE <ms> - + <count>` (Redis >= 6.2): a forma
    // estendida com IDLE não é exposta pelo helper `xpending_count` do crate, daí
    // o comando cru. A resposta tem o mesmo formato, então o parse é o mesmo.
    let pendentes: StreamPendingCountReply = redis::cmd("XPENDING")
        .arg(stream)
        .arg(grupo)
        .arg("IDLE")
        .arg(min_idle_ms)
        .arg("-")
        .arg("+")
        .arg(quantidade)
        .query_async(con)
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;

    let ids: Vec<String> = pendentes.ids.into_iter().map(|p| p.id).collect();
    if ids.is_empty() {
        return Ok(Vec::new());
    }

    let reclamados: StreamClaimReply = con
        .xclaim_options(
            stream,
            grupo,
            consumidor,
            min_idle_ms,
            &ids,
            StreamClaimOptions::default(),
        )
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;

    // O `XCLAIM` devolve só as entradas efetivamente reclamadas; as que voltaram a
    // ser entregues (idle abaixo do piso) e as já removidas do stream saem de fora.
    let eventos: Vec<EventoBruto> = reclamados.ids.iter().map(evento_de_entrada).collect();
    if !eventos.is_empty() {
        tracing::info!(
            reclamados = eventos.len(),
            min_idle_ms,
            "eventos abandonados reclamados da PEL para reprocessamento"
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

/// Converte uma entrada do stream em [`EventoBruto`]. Compartilhado pelo
/// `XREADGROUP` ([`extrair_eventos`]) e pelo `XCLAIM`
/// ([`reclamar_pendentes_abandonados`]), que devolvem a mesma `StreamId`.
fn evento_de_entrada(entrada: &StreamId) -> EventoBruto {
    let campo = |nome: &str| -> String {
        entrada
            .map
            .get(nome)
            .and_then(|v| redis::from_redis_value::<String>(v).ok())
            .unwrap_or_default()
    };
    EventoBruto {
        stream_id: entrada.id.clone(),
        tenant_id: campo("tenant_id"),
        event_id: campo("event_id"),
        event_type: campo("event_type"),
        timestamp: campo("timestamp"),
        traceparent: campo("traceparent"),
        payload: campo("payload"),
    }
}

/// Converte a resposta do `XREADGROUP` em uma lista de [`EventoBruto`].
fn extrair_eventos(reply: StreamReadReply) -> Vec<EventoBruto> {
    reply
        .keys
        .iter()
        .flat_map(|chave| chave.ids.iter().map(evento_de_entrada))
        .collect()
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
        let mut con: Connection = self
            .client
            .get_async_connection()
            .await
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
                    // Batimento no ponto exato em que o loop provou estar vivo: o
                    // read do Redis voltou. Registrar antes disso (ou num timer
                    // paralelo) manteria o arquivo fresco com o consumo travado.
                    crate::liveness::bater();
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
        let mut con: Connection = self
            .client
            .get_async_connection()
            .await
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
                                let _ = confirmar_stream(&mut con, &self.stream, &self.grupo, &id)
                                    .await;
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
                    // Ver a nota em `run`: o batimento vale a volta do loop, não o
                    // recebimento de evento — stream vazio também é sinal de vida.
                    crate::liveness::bater();
                    if !eventos.is_empty() {
                        match handler(eventos).await {
                            Ok(sucessos) => {
                                for id in sucessos {
                                    let _ =
                                        confirmar_stream(&mut con, &self.stream, &self.grupo, &id)
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
///
/// `min_idle_ms` protege o evento em voo pelo mesmo motivo de
/// [`reclamar_pendentes_abandonados`]: `times_delivered` alto não quer dizer
/// "abandonado" — o loop ativo pode estar processando a entrada agora, na enésima
/// tentativa. Reclamar com piso zero descartaria para a DLQ (e daria `XACK` em) um
/// evento que ainda tinha chance de terminar.
pub async fn varrer_dlq_pendentes(
    con: &mut Connection,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    min_idle_ms: usize,
) -> anyhow::Result<()> {
    let pend: StreamPendingCountReply = con.xpending_count(stream, grupo, "-", "+", 100).await?;

    for id in pend.ids {
        if id.times_delivered > MAX_ENTREGAS {
            let opts = StreamClaimOptions::default();
            let reclamado: StreamClaimReply = con
                .xclaim_options(
                    stream,
                    grupo,
                    consumidor,
                    min_idle_ms,
                    std::slice::from_ref(&id.id),
                    opts,
                )
                .await?;

            // Vazio = a entrada voltou a ser entregue (idle abaixo do piso) ou já
            // saiu do stream: não é para mandar à DLQ nem dar XACK nela agora.
            let Some(entrada) = reclamado.ids.first() else {
                continue;
            };

            // O conteúdo vai junto. Antes a DLQ guardava só o `original_id`, e como
            // o stream de origem é limitado por MAXLEN (~10k eventos), o evento
            // podia já ter sido descartado quando alguém fosse investigar — a DLQ
            // apontava para um id que não existia mais. Com o payload, a perícia
            // (e um eventual reenvio manual) não depende do stream original.
            let evento = evento_de_entrada(entrada);
            let _: String = con
                .xadd(
                    DLQ_STREAM,
                    "*",
                    &[
                        ("original_id", id.id.as_str()),
                        ("times_delivered", &id.times_delivered.to_string()),
                        ("stream_origem", stream),
                        ("grupo_origem", grupo),
                        ("tenant_id", evento.tenant_id.as_str()),
                        ("event_id", evento.event_id.as_str()),
                        ("event_type", evento.event_type.as_str()),
                        ("timestamp", evento.timestamp.as_str()),
                        ("traceparent", evento.traceparent.as_str()),
                        ("payload", evento.payload.as_str()),
                    ],
                )
                .await?;

            let _: i64 = con
                .xack(stream, grupo, std::slice::from_ref(&id.id))
                .await?;
            tracing::warn!(
                stream_id = %id.id,
                entregas = id.times_delivered,
                event_type = %evento.event_type,
                "evento movido para DLQ"
            );
        }
    }
    Ok(())
}

/// Executa uma passada de reprocessamento da PEL no stream especificado.
///
/// Só toca em eventos parados há pelo menos `min_idle_ms` (use
/// [`MIN_IDLE_REPROCESSAMENTO_MS`]), porque esta passada roda em paralelo ao loop
/// de consumo ativo — sem o piso, reprocessaria o que está em voo.
pub async fn reprocessar_pendentes_uma_vez<F, Fut>(
    client: &redis::Client,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    min_idle_ms: usize,
    handler: F,
) -> anyhow::Result<()>
where
    F: Fn(EventoBruto) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
{
    let mut con: Connection = client
        .get_async_connection()
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;

    if let Err(e) = varrer_dlq_pendentes(&mut con, stream, grupo, consumidor, min_idle_ms).await {
        tracing::warn!("Falha ao varrer DLQ de pendentes: {:?}", e);
    }

    let pendentes =
        reclamar_pendentes_abandonados(&mut con, stream, grupo, consumidor, min_idle_ms, 10)
            .await?;
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
/// Mesmo piso de inatividade da versão unitária ([`MIN_IDLE_REPROCESSAMENTO_MS`]).
pub async fn reprocessar_pendentes_uma_vez_batch<F, Fut>(
    client: &redis::Client,
    stream: &str,
    grupo: &str,
    consumidor: &str,
    min_idle_ms: usize,
    handler: F,
) -> anyhow::Result<()>
where
    F: Fn(Vec<EventoBruto>) -> Fut + Send + Sync + 'static,
    Fut: std::future::Future<Output = anyhow::Result<Vec<String>>> + Send + 'static,
{
    let mut con: Connection = client
        .get_async_connection()
        .await
        .map_err(|e| TransportError::Bus(e.to_string()))?;

    if let Err(e) = varrer_dlq_pendentes(&mut con, stream, grupo, consumidor, min_idle_ms).await {
        tracing::warn!("Falha ao varrer DLQ de pendentes: {:?}", e);
    }

    let pendentes =
        reclamar_pendentes_abandonados(&mut con, stream, grupo, consumidor, min_idle_ms, 10)
            .await?;
    if !pendentes.is_empty() {
        match handler(pendentes).await {
            Ok(sucessos) => {
                for id in sucessos {
                    let _ = confirmar_stream(&mut con, stream, grupo, &id).await;
                }
            }
            Err(e) => {
                tracing::error!(
                    "reprocessador em lote: handler falhou novamente; mantido na PEL: {:?}",
                    e
                );
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

    // --- extrair_eventos: conversão pura de StreamReadReply → Vec<EventoBruto> ---

    use redis::streams::{StreamId, StreamKey, StreamReadReply};
    use redis::Value;
    use std::collections::HashMap;

    /// Monta um `StreamId` com os campos informados (valores como bulk string).
    fn stream_id(id: &str, campos: &[(&str, &str)]) -> StreamId {
        let mut map = HashMap::new();
        for (k, v) in campos {
            map.insert(k.to_string(), Value::Data(v.as_bytes().to_vec()));
        }
        StreamId {
            id: id.to_string(),
            map,
        }
    }

    #[test]
    fn extrair_eventos_mapeia_todos_os_campos() {
        let reply = StreamReadReply {
            keys: vec![StreamKey {
                key: STREAM_EVENTOS.to_string(),
                ids: vec![stream_id(
                    "1526984818136-0",
                    &[
                        ("tenant_id", "t-1"),
                        ("event_id", "e-1"),
                        ("event_type", "message.received"),
                        ("timestamp", "2026-07-20T00:00:00Z"),
                        ("traceparent", "00-abc-def-01"),
                        ("payload", "{\"x\":1}"),
                    ],
                )],
            }],
        };

        let eventos = extrair_eventos(reply);
        assert_eq!(eventos.len(), 1);
        let e = &eventos[0];
        assert_eq!(e.stream_id, "1526984818136-0");
        assert_eq!(e.tenant_id, "t-1");
        assert_eq!(e.event_id, "e-1");
        assert_eq!(e.event_type, "message.received");
        assert_eq!(e.timestamp, "2026-07-20T00:00:00Z");
        assert_eq!(e.traceparent, "00-abc-def-01");
        assert_eq!(e.payload, "{\"x\":1}");
    }

    #[test]
    fn extrair_eventos_campos_ausentes_viram_string_vazia() {
        // Entrada só com o payload: os demais campos caem no unwrap_or_default (vazio).
        let reply = StreamReadReply {
            keys: vec![StreamKey {
                key: STREAM_EVENTOS.to_string(),
                ids: vec![stream_id("2-0", &[("payload", "{}")])],
            }],
        };

        let eventos = extrair_eventos(reply);
        assert_eq!(eventos.len(), 1);
        let e = &eventos[0];
        assert_eq!(e.stream_id, "2-0");
        assert_eq!(e.tenant_id, "");
        assert_eq!(e.event_id, "");
        assert_eq!(e.event_type, "");
        assert_eq!(e.traceparent, "");
        assert_eq!(e.payload, "{}");
    }

    #[test]
    fn extrair_eventos_multiplas_chaves_e_ids_preserva_ordem() {
        let reply = StreamReadReply {
            keys: vec![
                StreamKey {
                    key: STREAM_EVENTOS.to_string(),
                    ids: vec![
                        stream_id("1-0", &[("event_type", "a")]),
                        stream_id("2-0", &[("event_type", "b")]),
                    ],
                },
                StreamKey {
                    key: STREAM_SEGURANCA.to_string(),
                    ids: vec![stream_id("3-0", &[("event_type", "c")])],
                },
            ],
        };

        let eventos = extrair_eventos(reply);
        let tipos: Vec<&str> = eventos.iter().map(|e| e.event_type.as_str()).collect();
        assert_eq!(tipos, vec!["a", "b", "c"]);
    }

    #[test]
    fn extrair_eventos_reply_vazio_gera_lista_vazia() {
        let reply = StreamReadReply { keys: vec![] };
        assert!(extrair_eventos(reply).is_empty());
    }

    /// O default TEM de continuar sendo o nome histórico: trocá-lo num deployment
    /// em operação abandonaria a PEL do nome antigo (eventos pendentes ficariam
    /// esperando o piso de inatividade para serem reclamados).
    #[test]
    fn nome_consumidor_default_preserva_o_nome_historico() {
        std::env::remove_var("SMARTCORE_CONSUMER_NAME");
        assert_eq!(nome_consumidor("worker_consumer"), "worker_consumer_1");
        assert_eq!(
            nome_consumidor("data_storage_purge_consumer"),
            "data_storage_purge_consumer_1"
        );
    }

    /// Com a variável setada, cada réplica ganha nome próprio — condição para
    /// escalar horizontalmente sem duas réplicas dividindo a mesma PEL.
    #[test]
    fn nome_consumidor_usa_sufixo_do_ambiente() {
        std::env::set_var("SMARTCORE_CONSUMER_NAME", "b7");
        assert_eq!(nome_consumidor("worker_consumer"), "worker_consumer_b7");

        // Valor em branco não conta como nome: cai no default.
        std::env::set_var("SMARTCORE_CONSUMER_NAME", "   ");
        assert_eq!(nome_consumidor("worker_consumer"), "worker_consumer_1");
        std::env::remove_var("SMARTCORE_CONSUMER_NAME");
    }

    /// O piso de inatividade precisa ser maior que a duração máxima de um handler,
    /// senão o reprocessador periódico reclama evento em voo. O pior caso conhecido
    /// é a resposta da IA no worker: 8s de timeout × 3 tentativas + backoff 0/1/2.
    #[test]
    fn min_idle_cobre_o_pior_caso_de_handler() {
        let pior_caso_ia_ms = (8_000 * 3) + (1_000 + 2_000);
        assert!(
            MIN_IDLE_REPROCESSAMENTO_MS > pior_caso_ia_ms,
            "piso {}ms não cobre o pior caso de {}ms",
            MIN_IDLE_REPROCESSAMENTO_MS,
            pior_caso_ia_ms
        );
    }

    #[test]
    fn consumer_new_guarda_campos() {
        // Construtor puro: não abre conexão. `Client::open` valida a URL sem conectar.
        let client = redis::Client::open("redis://127.0.0.1:6379").unwrap();
        let consumer = Consumer::new("meu:stream", "grupo-x", "consumidor-y", client);
        assert_eq!(consumer.stream, "meu:stream");
        assert_eq!(consumer.grupo, "grupo-x");
        assert_eq!(consumer.consumidor, "consumidor-y");
    }
}
