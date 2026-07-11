//! Scheduler temporal do worker (F4.3b): substitui o Celery beat da v1.
//!
//! Duas tarefas rodam a cada tick (`tokio::time::interval`, sem `sleep` encadeado
//! para não sofrer drift): timeout de feedback vencido e disparo de purga de mídia
//! expirada. Cada tarefa é protegida por um lock Redis (`SET NX PX`) cross-tenant —
//! o scheduler varre todos os tenants por chamada, então o lock não é por tenant
//! (diferente do debounce de `main.rs`), é por tarefa: só uma réplica do worker
//! executa a tarefa em cada tick; as demais, ao perder o lock, fazem no-op.

use chrono::{DateTime, Utc};
use redis::aio::ConnectionManager;
use std::time::Duration;

use crate::{chamar_rpc, AppState};

/// Fonte de tempo injetável (port `SchedulerClock`). Greenfield: não havia
/// abstração de tempo no backend antes da N1 — todo o código usa `Utc::now()`
/// diretamente. Permite testar a lógica do tick com um relógio congelado/avançável.
pub trait Clock: Send + Sync {
    fn now(&self) -> DateTime<Utc>;
}

/// Implementação real: delega para `chrono::Utc::now()`.
pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> DateTime<Utc> {
        Utc::now()
    }
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

/// Sobe o loop do scheduler em `tokio::spawn`, paralelo ao consumidor do bus.
/// Não retorna: roda até o processo encerrar.
pub fn iniciar(state: AppState) {
    tokio::spawn(async move {
        let tick_secs = env_u64("SMARTCORE_SCHEDULER_TICK_SECS", 60);
        let clock = SystemClock;
        let mut tick = tokio::time::interval(Duration::from_secs(tick_secs));
        // A primeira `tick.tick()` completa imediatamente; não é um problema aqui
        // (mesmo padrão do lag sampler do data_postgres), só adianta o primeiro ciclo.
        loop {
            tick.tick().await;
            executar_tick(&state, &clock).await;
        }
    });
}

/// Um ciclo do scheduler: tenta as duas tarefas (feedback vencido e mídia
/// expirada), cada uma sob seu próprio lock. Falhas de uma tarefa não impedem a
/// outra — cada uma loga o próprio erro e segue para o próximo tick.
#[tracing::instrument(skip_all, name = "scheduler.tick")]
async fn executar_tick(state: &AppState, clock: &dyn Clock) {
    let _ = clock.now(); // âncora do tick para futura extensão (ex.: TTL relativo a um instante congelado em teste)

    if let Some(ref redis_conn) = state.redis_conn {
        let mut conn = redis_conn.clone();
        if tentar_lock(&mut conn, "scheduler:lock:feedback_timeout", 30_000).await {
            match processar_feedback_vencido(state).await {
                Ok(n) if n > 0 => {
                    tracing::info!(vencidos = n, "scheduler: feedback vencido processado")
                }
                Ok(_) => {}
                Err(e) => {
                    tracing::error!("scheduler: falha ao processar feedback vencido: {:?}", e)
                }
            }
        }

        let mut conn = redis_conn.clone();
        if tentar_lock(&mut conn, "scheduler:lock:media_purge", 30_000).await {
            match processar_midia_expirada(state).await {
                Ok(n) if n > 0 => {
                    tracing::info!(purgados = n, "scheduler: purga de mídia disparada")
                }
                Ok(_) => {}
                Err(e) => tracing::error!("scheduler: falha ao processar mídia expirada: {:?}", e),
            }
        }
    } else {
        tracing::warn!("scheduler: sem conexão Redis, tick pulado (sem lock disponível)");
    }
}

/// Lock Redis `SET NX PX` — mesmo padrão do debounce de mensagens (`main.rs`),
/// trocando `EX` (segundos) por `PX` (milissegundos). TTL menor que o intervalo do
/// tick: se a réplica cair no meio do lote, o lock expira sozinho e a próxima tick
/// (desta ou de outra réplica) assume — não há unlock manual nem token de posse.
async fn tentar_lock(conn: &mut ConnectionManager, chave: &str, ttl_ms: usize) -> bool {
    let res: Result<bool, _> = redis::cmd("SET")
        .arg(chave)
        .arg("1")
        .arg("NX")
        .arg("PX")
        .arg(ttl_ms)
        .query_async(conn)
        .await;
    match res {
        Ok(ganhou) => ganhou,
        Err(e) => {
            tracing::error!(
                "scheduler: erro no Redis ao obter lock '{}': {:?}",
                chave,
                e
            );
            false
        }
    }
}

/// Varre atendimentos com feedback vencido (RPC cross-tenant) e, para cada um,
/// transiciona o estado (RPC tenant-scoped) + audita `atendimento.feedback_expirado`.
/// Varredura vazia não audita (não inundar a trilha, ver info_aux N1).
async fn processar_feedback_vencido(state: &AppState) -> anyhow::Result<usize> {
    let limite = env_u64("SMARTCORE_SCHEDULER_LOTE", 100);
    let ttl_horas = env_u64("SMARTCORE_SCHEDULER_FEEDBACK_TTL_HORAS", 48);

    let scan_payload = serde_json::json!({ "limite": limite, "ttl_horas": ttl_horas });
    let resp = chamar_rpc(
        &state.pg_client,
        SISTEMA_TENANT_PLACEHOLDER,
        "ListarAtendimentosFeedbackVencido",
        scan_payload,
        "scheduler.tick",
        "",
    )
    .await?;

    let atendimentos = resp
        .get("atendimentos")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut processados = 0usize;
    for item in atendimentos {
        let atendimento_id = match item.get("id").and_then(|v| v.as_i64()) {
            Some(id) => id,
            None => continue,
        };
        let tenant_id = match item.get("tenant_id").and_then(|v| v.as_str()) {
            Some(t) => t.to_string(),
            None => continue,
        };

        let acao_payload = serde_json::json!({ "atendimento_id": atendimento_id });
        if let Err(e) = chamar_rpc(
            &state.pg_client,
            &tenant_id,
            "MarcarFeedbackExpirado",
            acao_payload,
            "scheduler.tick",
            "",
        )
        .await
        {
            tracing::error!(
                atendimento_id = atendimento_id,
                "scheduler: falha ao marcar feedback expirado: {:?}",
                e
            );
            continue;
        }

        let tenant_uuid = uuid::Uuid::parse_str(&tenant_id).unwrap_or(uuid::Uuid::nil());
        state.audit_logger.info(
            tenant_uuid,
            "atendimento.feedback_expirado",
            "Feedback do atendimento expirou pelo TTL do scheduler",
            serde_json::json!({ "atendimento_id": atendimento_id }),
            None,
            None,
            None,
        );
        processados += 1;
    }

    Ok(processados)
}

/// Varre mensagens com mídia expirada (RPC cross-tenant); para cada uma, marca a
/// purga como solicitada (idempotência) e publica `media.purge` no bus — o
/// `data_storage` já consome esse evento (`processar_purga_midia`) e audita
/// `midia.purgada` no lado dele.
async fn processar_midia_expirada(state: &AppState) -> anyhow::Result<usize> {
    let limite = env_u64("SMARTCORE_SCHEDULER_LOTE", 100);
    let idade_max_dias = env_u64("SMARTCORE_SCHEDULER_MEDIA_IDADE_MAX_DIAS", 30);

    let scan_payload = serde_json::json!({ "limite": limite, "idade_max_dias": idade_max_dias });
    let resp = chamar_rpc(
        &state.pg_client,
        SISTEMA_TENANT_PLACEHOLDER,
        "ListarMidiasExpiradas",
        scan_payload,
        "scheduler.tick",
        "",
    )
    .await?;

    let mensagens = resp
        .get("mensagens")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut processados = 0usize;
    for item in mensagens {
        let mensagem_id = match item.get("id").and_then(|v| v.as_i64()) {
            Some(id) => id,
            None => continue,
        };
        let tenant_id = match item.get("tenant_id").and_then(|v| v.as_str()) {
            Some(t) => t.to_string(),
            None => continue,
        };
        let file_name = match item.get("arquivo_midia").and_then(|v| v.as_str()) {
            Some(f) if !f.is_empty() => f.to_string(),
            _ => continue,
        };

        if let Err(e) = publicar_media_purge(state, &tenant_id, &file_name).await {
            tracing::error!(
                mensagem_id = mensagem_id,
                "scheduler: falha ao publicar evento media.purge: {:?}",
                e
            );
            continue;
        }

        let acao_payload = serde_json::json!({ "mensagem_id": mensagem_id });
        if let Err(e) = chamar_rpc(
            &state.pg_client,
            &tenant_id,
            "MarcarMidiaPurgada",
            acao_payload,
            "scheduler.tick",
            "",
        )
        .await
        {
            // Publicação já ocorreu (delete é idempotente do lado do data_storage);
            // não marcar aqui só adia a purga para o próximo tick, não duplica risco.
            tracing::error!(
                mensagem_id = mensagem_id,
                "scheduler: falha ao marcar mídia purgada: {:?}",
                e
            );
        }
        processados += 1;
    }

    Ok(processados)
}

/// Publica o evento `media.purge` no bus (mesmo stream/formato consumido por
/// `data_storage::processar_purga_midia`: payload `{"file_name": "..."}`,
/// `tenant_id` no envelope do bus, não no payload).
async fn publicar_media_purge(
    state: &AppState,
    tenant_id: &str,
    file_name: &str,
) -> anyhow::Result<()> {
    let redis_conn = state
        .redis_conn
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("sem conexão Redis para publicar media.purge"))?;
    let mut conn = redis_conn.clone();
    let tenant_uuid = uuid::Uuid::parse_str(tenant_id)?;
    let envelope = contracts::TenantEnvelope::novo(
        tenant_uuid,
        "media.purge",
        serde_json::json!({ "file_name": file_name }),
    );
    transport::bus::publicar_evento(&mut conn, &envelope).await?;
    Ok(())
}

/// Placeholder de `tenant_id` para RPCs cross-tenant (varredura): o handler no
/// data_postgres usa o pool admin (BYPASSRLS) e ignora o tenant do envelope para a
/// consulta em si — só os escopos (`escopos_sistema()`, coringa `"*"`) importam
/// para a checagem de permissão. Mantido como UUID nulo por clareza (nunca usado
/// para filtrar dados).
const SISTEMA_TENANT_PLACEHOLDER: &str = "00000000-0000-0000-0000-000000000000";

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc as StdArc;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    static SCHEDULER_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    async fn estado_sem_redis(pg_addr: &str) -> AppState {
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        let pg_client = StdArc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        AppState {
            redis_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(crate::ia_engine::MockIaEngineClient::new()),
        }
    }

    #[tokio::test]
    async fn test_processar_feedback_vencido_marca_e_audita() {
        let _guard = SCHEDULER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29320";
        let endpoint = Endpoint::parse(pg_addr).unwrap();
        let server = Server::new(endpoint, "flatbuffers")
            .route("ListarAtendimentosFeedbackVencido", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "atendimentos": [
                            { "id": 7, "tenant_id": Uuid::new_v4().to_string() }
                        ]
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListarAtendimentosFeedbackVencidoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("MarcarFeedbackExpirado", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "ok" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "MarcarFeedbackExpiradoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let handle = tokio::spawn(async move { server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let state = estado_sem_redis(pg_addr).await;
        let processados = processar_feedback_vencido(&state).await.unwrap();
        assert_eq!(processados, 1);

        handle.abort();
    }

    /// DoD da N1.2: 2 ticks seguidos não duplicam efeito. Simula a idempotência do
    /// lado do data_postgres (marcação `feedback_expirado_em`): na 2ª varredura, o
    /// item já processado não aparece mais na lista — o worker não tenta marcá-lo
    /// de novo.
    #[tokio::test]
    async fn test_processar_feedback_vencido_dois_ciclos_idempotente() {
        let _guard = SCHEDULER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29321";
        let endpoint = Endpoint::parse(pg_addr).unwrap();
        let chamadas_scan = StdArc::new(AtomicUsize::new(0));
        let chamadas_marcar = StdArc::new(AtomicUsize::new(0));
        let chamadas_scan_h = chamadas_scan.clone();
        let chamadas_marcar_h = chamadas_marcar.clone();

        let server = Server::new(endpoint, "flatbuffers")
            .route("ListarAtendimentosFeedbackVencido", move |env| {
                let chamadas_scan = chamadas_scan_h.clone();
                Box::pin(async move {
                    let primeira_chamada = chamadas_scan.fetch_add(1, Ordering::SeqCst) == 0;
                    let atendimentos = if primeira_chamada {
                        serde_json::json!([{ "id": 7, "tenant_id": Uuid::new_v4().to_string() }])
                    } else {
                        serde_json::json!([])
                    };
                    let reply = serde_json::json!({ "atendimentos": atendimentos });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListarAtendimentosFeedbackVencidoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("MarcarFeedbackExpirado", move |env| {
                let chamadas_marcar = chamadas_marcar_h.clone();
                Box::pin(async move {
                    chamadas_marcar.fetch_add(1, Ordering::SeqCst);
                    let reply = serde_json::json!({ "status": "ok" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "MarcarFeedbackExpiradoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let handle = tokio::spawn(async move { server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let state = estado_sem_redis(pg_addr).await;

        let primeiro_tick = processar_feedback_vencido(&state).await.unwrap();
        let segundo_tick = processar_feedback_vencido(&state).await.unwrap();

        assert_eq!(
            primeiro_tick, 1,
            "primeiro tick deve processar o item vencido"
        );
        assert_eq!(
            segundo_tick, 0,
            "segundo tick não deve reprocessar (já marcado)"
        );
        assert_eq!(
            chamadas_marcar.load(Ordering::SeqCst),
            1,
            "MarcarFeedbackExpirado só deve ser chamado uma vez (idempotência)"
        );

        handle.abort();
    }

    #[tokio::test]
    async fn test_processar_midia_expirada_marca_e_publica() {
        let _guard = SCHEDULER_TEST_MUTEX.lock().await;
        let redis_url =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
        let redis_client = match redis::Client::open(redis_url) {
            Ok(c) => c,
            Err(_) => return,
        };
        let redis_conn = match ConnectionManager::new(redis_client).await {
            Ok(c) => c,
            Err(_) => return, // sem Redis disponível neste ambiente: pula (integração real via test-local.ps1)
        };

        let pg_addr = "tcp://127.0.0.1:29322";
        let endpoint = Endpoint::parse(pg_addr).unwrap();
        let server = Server::new(endpoint, "flatbuffers")
            .route("ListarMidiasExpiradas", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "mensagens": [
                            {
                                "id": 55,
                                "tenant_id": Uuid::new_v4().to_string(),
                                "arquivo_midia": "midia-teste-n1.jpg"
                            }
                        ]
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ListarMidiasExpiradasReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("MarcarMidiaPurgada", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "ok" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "MarcarMidiaPurgadaReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let handle = tokio::spawn(async move { server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let mut state = estado_sem_redis(pg_addr).await;
        state.redis_conn = Some(redis_conn);

        let processados = processar_midia_expirada(&state).await.unwrap();
        assert_eq!(processados, 1);

        handle.abort();
    }
}
