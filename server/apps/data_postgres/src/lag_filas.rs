//! Amostragem periódica do lag das filas (M4, ampliada após o incidente 2026-11-16).
//!
//! Antes só o `data_postgres_audit_group` era medido. A PEL do `worker_group` em
//! `events:stream` — onde a mensagem do cliente para quando o worker não consegue
//! processar — não tinha métrica nenhuma, e o alerta de PEL vigiava o grupo errado.
//!
//! Por grupo vigiado (labels `stream` e `grupo`):
//! - `smartcore_bus_pending`: entregues e ainda sem XACK (PEL).
//! - `smartcore_bus_lag`: entradas do stream ainda não entregues ao grupo (`XINFO GROUPS`, Redis 7+).
//! - `smartcore_bus_pendente_mais_antigo_segundos`: idade do evento mais antigo da PEL,
//!   contada do XADD. É o sinal sem ruído de "mensagem parada": com tráfego baixo ele
//!   fica em zero, ao contrário de "tempo desde a última mensagem processada".
//!
//! Globais: `smartcore_bus_dlq_tamanho` (XLEN da DLQ) e `smartcore_outbox_backlog`.

use observability::opentelemetry::{global, KeyValue};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

pub const GRUPOS_VIGIADOS: [(&str, &str); 2] = [
    (transport::bus::STREAM_EVENTOS, "worker_group"),
    (
        transport::bus::STREAM_SEGURANCA,
        "data_postgres_audit_group",
    ),
];

#[derive(Default)]
struct Amostra {
    pendentes: AtomicU64,
    lag: AtomicU64,
    idade_pendente_s: AtomicU64,
}

#[derive(Debug, Default, PartialEq, Eq)]
struct EstadoGrupo {
    pendentes: u64,
    lag: u64,
    idade_pendente_s: u64,
}

fn rotulos(stream: &'static str, grupo: &'static str) -> [KeyValue; 2] {
    [
        KeyValue::new("stream", stream),
        KeyValue::new("grupo", grupo),
    ]
}

/// Registra os gauges e sobe a task de amostragem. Em falha de leitura, o gauge
/// mantém o último valor e a falha vai para o log: zerar esconderia o problema.
pub fn iniciar(bus: ConnectionManager, pool: PgPool, intervalo: Duration) {
    let amostras: Arc<Vec<Amostra>> =
        Arc::new(GRUPOS_VIGIADOS.iter().map(|_| Amostra::default()).collect());
    let outbox = Arc::new(AtomicU64::new(0));
    let dlq = Arc::new(AtomicU64::new(0));
    let meter = global::meter("data_postgres");

    let a = amostras.clone();
    let g_pendentes = meter
        .u64_observable_gauge("smartcore_bus_pending")
        .with_description("Mensagens entregues e ainda sem XACK na PEL do grupo")
        .with_callback(move |obs| {
            for (i, &(stream, grupo)) in GRUPOS_VIGIADOS.iter().enumerate() {
                obs.observe(
                    a[i].pendentes.load(Ordering::Relaxed),
                    &rotulos(stream, grupo),
                );
            }
        })
        .init();

    let a = amostras.clone();
    let g_lag = meter
        .u64_observable_gauge("smartcore_bus_lag")
        .with_description("Entradas do stream ainda nao entregues ao grupo")
        .with_callback(move |obs| {
            for (i, &(stream, grupo)) in GRUPOS_VIGIADOS.iter().enumerate() {
                obs.observe(a[i].lag.load(Ordering::Relaxed), &rotulos(stream, grupo));
            }
        })
        .init();

    let a = amostras.clone();
    let g_idade = meter
        .u64_observable_gauge("smartcore_bus_pendente_mais_antigo_segundos")
        .with_description("Idade, desde o XADD, do evento mais antigo ainda na PEL do grupo")
        .with_callback(move |obs| {
            for (i, &(stream, grupo)) in GRUPOS_VIGIADOS.iter().enumerate() {
                obs.observe(
                    a[i].idade_pendente_s.load(Ordering::Relaxed),
                    &rotulos(stream, grupo),
                );
            }
        })
        .init();

    let o = outbox.clone();
    let g_outbox = meter
        .u64_observable_gauge("smartcore_outbox_backlog")
        .with_description("Mensagens acumuladas na tabela de outbox do PostgreSQL")
        .with_callback(move |obs| obs.observe(o.load(Ordering::Relaxed), &[]))
        .init();

    let d = dlq.clone();
    let g_dlq = meter
        .u64_observable_gauge("smartcore_bus_dlq_tamanho")
        .with_description("Eventos na dead-letter (entregues mais de 5 vezes sem sucesso)")
        .with_callback(move |obs| {
            obs.observe(
                d.load(Ordering::Relaxed),
                &[KeyValue::new("stream", transport::bus::DLQ_STREAM)],
            )
        })
        .init();

    tokio::spawn(async move {
        let _vivos = (g_pendentes, g_lag, g_idade, g_outbox, g_dlq);
        let mut con = bus;
        let mut tick = tokio::time::interval(intervalo);
        loop {
            tick.tick().await;
            let agora_ms = agora_epoch_ms();

            for (i, &(stream, grupo)) in GRUPOS_VIGIADOS.iter().enumerate() {
                match amostrar_grupo(&mut con, stream, grupo, agora_ms).await {
                    Ok(e) => {
                        amostras[i].pendentes.store(e.pendentes, Ordering::Relaxed);
                        amostras[i].lag.store(e.lag, Ordering::Relaxed);
                        amostras[i]
                            .idade_pendente_s
                            .store(e.idade_pendente_s, Ordering::Relaxed);
                        tracing::debug!(
                            target: "metrics::lag",
                            stream, grupo,
                            pendentes = e.pendentes, lag = e.lag, idade_pendente_s = e.idade_pendente_s,
                            "amostra do grupo do bus"
                        );
                    }
                    Err(e) => {
                        tracing::warn!(stream, grupo, erro = ?e, "falha ao amostrar o grupo do bus")
                    }
                }
            }

            match redis::cmd("XLEN")
                .arg(transport::bus::DLQ_STREAM)
                .query_async::<_, u64>(&mut con)
                .await
            {
                Ok(n) => dlq.store(n, Ordering::Relaxed),
                Err(e) => tracing::warn!(erro = ?e, "falha ao ler XLEN da DLQ"),
            }

            let backlog: Result<(i64,), sqlx::Error> =
                sqlx::query_as("SELECT count(*) FROM outbox WHERE published_at IS NULL")
                    .fetch_one(&pool)
                    .await;
            match backlog {
                Ok((n,)) => outbox.store(n.max(0) as u64, Ordering::Relaxed),
                Err(e) => tracing::warn!("Falha ao contar backlog da outbox no Postgres: {:?}", e),
            }
        }
    });
}

async fn amostrar_grupo(
    con: &mut ConnectionManager,
    stream: &str,
    grupo: &str,
    agora_ms: i64,
) -> redis::RedisResult<EstadoGrupo> {
    let grupos: Vec<HashMap<String, redis::Value>> = redis::cmd("XINFO")
        .arg("GROUPS")
        .arg(stream)
        .query_async(&mut *con)
        .await?;
    // Grupo ainda não criado (serviço consumidor nunca subiu): nada pendente.
    let Some((pendentes, lag)) = extrair_grupo(&grupos, grupo) else {
        return Ok(EstadoGrupo::default());
    };
    let idade_pendente_s = if pendentes > 0 {
        let resumo: redis::streams::StreamPendingReply = con.xpending(stream, grupo).await?;
        match resumo {
            redis::streams::StreamPendingReply::Data(d) => idade_do_id(&d.start_id, agora_ms),
            redis::streams::StreamPendingReply::Empty => 0,
        }
    } else {
        0
    };
    Ok(EstadoGrupo {
        pendentes,
        lag,
        idade_pendente_s,
    })
}

/// `(pending, lag)` do grupo na resposta de `XINFO GROUPS`. `lag` nulo (o Redis não
/// consegue calcular, ex.: após XDEL no meio do stream) vira 0.
fn extrair_grupo(grupos: &[HashMap<String, redis::Value>], grupo: &str) -> Option<(u64, u64)> {
    let info = grupos.iter().find(|g| {
        g.get("name")
            .and_then(|v| redis::from_redis_value::<String>(v).ok())
            .as_deref()
            == Some(grupo)
    })?;
    Some((inteiro(info.get("pending")), inteiro(info.get("lag"))))
}

fn inteiro(v: Option<&redis::Value>) -> u64 {
    match v {
        Some(redis::Value::Int(n)) if *n > 0 => *n as u64,
        _ => 0,
    }
}

/// Idade em segundos de um id de stream (`<ms>-<seq>`) em relação a `agora_ms`.
fn idade_do_id(id: &str, agora_ms: i64) -> u64 {
    id.split('-')
        .next()
        .and_then(|ms| ms.parse::<i64>().ok())
        .map(|ms| agora_ms.saturating_sub(ms).max(0) as u64 / 1000)
        .unwrap_or(0)
}

fn agora_epoch_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use redis::Value;

    fn grupo(nome: &str, pending: i64, lag: Value) -> HashMap<String, Value> {
        HashMap::from([
            ("name".to_string(), Value::Data(nome.as_bytes().to_vec())),
            ("pending".to_string(), Value::Int(pending)),
            ("lag".to_string(), lag),
        ])
    }

    #[test]
    fn extrai_pending_e_lag_do_grupo_certo() {
        let grupos = vec![
            grupo("data_postgres_audit_group", 3, Value::Int(0)),
            grupo("worker_group", 42, Value::Int(1000)),
        ];
        assert_eq!(extrair_grupo(&grupos, "worker_group"), Some((42, 1000)));
        assert_eq!(extrair_grupo(&grupos, "inexistente"), None);
    }

    #[test]
    fn lag_nulo_vira_zero() {
        let grupos = vec![grupo("worker_group", 5, Value::Nil)];
        assert_eq!(extrair_grupo(&grupos, "worker_group"), Some((5, 0)));
    }

    #[test]
    fn idade_do_id_usa_o_timestamp_do_xadd() {
        assert_eq!(idade_do_id("1794805237421-0", 1794805237421 + 125_000), 125);
        assert_eq!(idade_do_id("1794805237421-7", 1794805237000), 0);
        assert_eq!(idade_do_id("lixo", 1794805237421), 0);
    }

    #[test]
    fn grupos_vigiados_incluem_o_worker() {
        assert!(GRUPOS_VIGIADOS.contains(&(transport::bus::STREAM_EVENTOS, "worker_group")));
    }
}
