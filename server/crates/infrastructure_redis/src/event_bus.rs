use chrono::{DateTime, Utc};
use redis::aio::ConnectionManager;
use redis::streams::{StreamMaxlen, StreamReadOptions, StreamReadReply};
use redis::AsyncCommands;
use serde::de::DeserializeOwned;
use serde::Serialize;
use uuid::Uuid;

use crate::envelope::TenantEnvelope;
use crate::errors::RedisError;

/// Stream único de eventos do domínio. O `messaging_gateway` publica; o `worker` consome
/// via consumer groups.
pub const STREAM_EVENTOS: &str = "events:stream";

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
    pub fn desserializar<T: DeserializeOwned>(&self) -> Result<TenantEnvelope<T>, RedisError> {
        let tenant_id = Uuid::parse_str(&self.tenant_id)
            .map_err(|e| RedisError::ConfigError(format!("tenant_id inválido: {e}")))?;
        let event_id = Uuid::parse_str(&self.event_id)
            .map_err(|e| RedisError::ConfigError(format!("event_id inválido: {e}")))?;
        let timestamp = DateTime::parse_from_rfc3339(&self.timestamp)
            .map_err(|e| RedisError::ConfigError(format!("timestamp inválido: {e}")))?
            .with_timezone(&Utc);
        let payload: T = serde_json::from_str(&self.payload)?;
        Ok(TenantEnvelope {
            tenant_id,
            event_id,
            event_type: self.event_type.clone(),
            timestamp,
            payload,
        })
    }
}

/// Publica um evento no barramento (`XADD` com MAXLEN aproximado). O ID do stream é
/// atribuído pelo Redis (`*`); o `event_id` (UUID v7) viaja como campo para idempotência.
pub async fn publicar_evento<T: Serialize>(
    con: &mut ConnectionManager,
    evento: &TenantEnvelope<T>,
) -> Result<String, RedisError> {
    let payload = serde_json::to_string(&evento.payload)?;
    let id: String = con
        .xadd_maxlen(
            STREAM_EVENTOS,
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
        .await?;
    Ok(id)
}

/// Garante a existência do consumer group (idempotente). Cria o stream se necessário
/// (`MKSTREAM`) e ignora o erro `BUSYGROUP` quando o grupo já existe.
pub async fn garantir_consumer_group(
    con: &mut ConnectionManager,
    grupo: &str,
) -> Result<(), RedisError> {
    let resultado: redis::RedisResult<()> = redis::cmd("XGROUP")
        .arg("CREATE")
        .arg(STREAM_EVENTOS)
        .arg(grupo)
        .arg("$")
        .arg("MKSTREAM")
        .query_async(con)
        .await;
    match resultado {
        Ok(()) => Ok(()),
        Err(e) if e.code() == Some("BUSYGROUP") => Ok(()),
        Err(e) => Err(e.into()),
    }
}

/// Consome novos eventos para o `consumidor` dentro do `grupo` (`XREADGROUP ... >`).
///
/// `block_ms > 0` ativa o modo bloqueante (use uma conexão dedicada nesse caso, pois
/// comandos bloqueantes travam conexões multiplexadas). `block_ms == 0` retorna de imediato
/// com o que houver disponível.
pub async fn consumir(
    con: &mut ConnectionManager,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
    block_ms: usize,
) -> Result<Vec<EventoBruto>, RedisError> {
    let mut opts = StreamReadOptions::default()
        .group(grupo, consumidor)
        .count(quantidade);
    if block_ms > 0 {
        opts = opts.block(block_ms);
    }
    let reply: StreamReadReply = con.xread_options(&[STREAM_EVENTOS], &[">"], &opts).await?;
    Ok(extrair_eventos(reply))
}

/// Relê as mensagens já entregues a este `consumidor` mas ainda não confirmadas (PEL),
/// usando `XREADGROUP ... 0`. Permite reprocessar após uma falha/reinício do consumidor.
pub async fn reprocessar_pendentes(
    con: &mut ConnectionManager,
    grupo: &str,
    consumidor: &str,
    quantidade: usize,
) -> Result<Vec<EventoBruto>, RedisError> {
    let opts = StreamReadOptions::default()
        .group(grupo, consumidor)
        .count(quantidade);
    let reply: StreamReadReply = con.xread_options(&[STREAM_EVENTOS], &["0"], &opts).await?;
    Ok(extrair_eventos(reply))
}

/// Confirma o processamento de um evento (`XACK`), removendo-o da lista de pendentes.
pub async fn confirmar(
    con: &mut ConnectionManager,
    grupo: &str,
    stream_id: &str,
) -> Result<(), RedisError> {
    let _: i64 = con.xack(STREAM_EVENTOS, grupo, &[stream_id]).await?;
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
