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

use crate::{chamar_rpc, ia_engine, AppState};

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

        // TTL maior que o das outras duas: vetorizar um lote significa uma
        // chamada ao provedor de embeddings por treinamento, e 30s não bastam.
        let mut conn = redis_conn.clone();
        if tentar_lock(&mut conn, "scheduler:lock:vetorizacao", 120_000).await {
            match processar_vetorizacao_pendente(state).await {
                Ok(n) if n > 0 => {
                    tracing::info!(vetorizados = n, "scheduler: material treinado vetorizado")
                }
                Ok(_) => {}
                Err(e) => tracing::error!("scheduler: falha ao vetorizar treinamentos: {:?}", e),
            }

            match processar_intents_sem_embedding(state).await {
                Ok(n) if n > 0 => {
                    tracing::info!(vetorizadas = n, "scheduler: intenções vetorizadas")
                }
                Ok(_) => {}
                Err(e) => tracing::error!("scheduler: falha ao vetorizar intenções: {:?}", e),
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
/// `data_storage` consome esse evento (`processar_purga_midia`) e faz a deleção
/// física do objeto. A auditoria `midia.purgada` (um evento por arquivo) é emitida
/// aqui, no ponto de disparo da purga.
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
        let marcado = chamar_rpc(
            &state.pg_client,
            &tenant_id,
            "MarcarMidiaPurgada",
            acao_payload,
            "scheduler.tick",
            "",
        )
        .await;

        if let Err(e) = &marcado {
            // Publicação já ocorreu (delete é idempotente do lado do data_storage);
            // não marcar aqui só adia a purga para o próximo tick, não duplica risco.
            tracing::error!(
                mensagem_id = mensagem_id,
                "scheduler: falha ao marcar mídia purgada: {:?}",
                e
            );
        } else {
            let tenant_uuid = uuid::Uuid::parse_str(&tenant_id).unwrap_or(uuid::Uuid::nil());
            state.audit_logger.info(
                tenant_uuid,
                "midia.purgada",
                "Mídia expirada pela política de retenção; purga disparada",
                serde_json::json!({ "mensagem_id": mensagem_id }),
                None,
                None,
                None,
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
/// Divide o conteúdo em trechos para vetorizar.
///
/// Corta em parágrafos, não em número de caracteres: um vetor é a média
/// semântica do que está dentro dele, e um corte no meio de uma frase produz um
/// trecho que não responde a pergunta nenhuma. Parágrafos vizinhos são juntados
/// enquanto couberem no teto — trechos de uma linha só diluem a busca.
///
/// Um parágrafo maior que o teto sozinho **não** é partido: preferir um trecho
/// grande e íntegro a dois pedaços que perderam o sentido.
fn dividir_em_trechos(conteudo: &str, teto: usize) -> Vec<String> {
    let mut trechos: Vec<String> = Vec::new();
    let mut atual = String::new();

    for paragrafo in conteudo.split("\n\n") {
        let paragrafo = paragrafo.trim();
        if paragrafo.is_empty() {
            continue;
        }
        if !atual.is_empty() && atual.chars().count() + paragrafo.chars().count() > teto {
            trechos.push(std::mem::take(&mut atual));
        }
        if !atual.is_empty() {
            atual.push_str("\n\n");
        }
        atual.push_str(paragrafo);
    }
    if !atual.is_empty() {
        trechos.push(atual);
    }
    trechos
}

/// Vetoriza o material treinado que está esperando na fila.
///
/// Sem isto o RAG consulta uma tabela vazia: o tenant treina a IA, o texto fica
/// gravado, e a IA nunca o lê.
///
/// Cada treinamento é um lote independente — uma falha do provedor de
/// embeddings num deles não derruba os outros, e o que falhou continua na fila
/// para o próximo tick.
async fn processar_vetorizacao_pendente(state: &AppState) -> anyhow::Result<usize> {
    let limite = env_u64("SMARTCORE_VETORIZACAO_LOTE", 20);
    let teto_trecho = env_u64("SMARTCORE_VETORIZACAO_TAMANHO_TRECHO", 1500) as usize;

    let resp = chamar_rpc(
        &state.pg_client,
        SISTEMA_TENANT_PLACEHOLDER,
        "ListarTreinamentosPendentes",
        serde_json::json!({ "limite": limite }),
        "scheduler.tick",
        "",
    )
    .await?;

    let pendentes = resp
        .get("pendentes")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut processados = 0usize;
    for item in pendentes {
        let (Some(id), Some(tenant_id), Some(conteudo)) = (
            item.get("id").and_then(|v| v.as_i64()),
            item.get("tenant_id").and_then(|v| v.as_str()),
            item.get("conteudo").and_then(|v| v.as_str()),
        ) else {
            continue;
        };

        let trechos = dividir_em_trechos(conteudo, teto_trecho);
        if trechos.is_empty() {
            continue;
        }

        let embed_out = match state
            .ia_client
            .embed(
                ia_engine::EmbedInput {
                    tenant_id: tenant_id.to_string(),
                    textos: trechos.clone(),
                },
                "",
            )
            .await
        {
            Ok(out) => out,
            Err(e) => {
                // Fica na fila: o próximo tick tenta de novo. Marcar como
                // vetorizado aqui perderia o material para sempre.
                tracing::warn!(
                    treinamento_id = id,
                    "ia_engine.Embed falhou; treinamento segue na fila: {e}"
                );
                continue;
            }
        };

        // O provedor pode devolver menos vetores que textos; parear pelo índice
        // e descartar o excedente evita gravar trecho com o vetor do vizinho.
        let chunks: Vec<serde_json::Value> = trechos
            .into_iter()
            .zip(embed_out.embeddings)
            .enumerate()
            .filter(|(_, (_, emb))| !emb.is_empty())
            .map(|(ordem, (conteudo, embedding))| {
                serde_json::json!({
                    "conteudo": conteudo,
                    "embedding": embedding,
                    "ordem": ordem as i32,
                })
            })
            .collect();

        if chunks.is_empty() {
            tracing::warn!(treinamento_id = id, "embeddings vazios; segue na fila");
            continue;
        }

        match chamar_rpc(
            &state.pg_client,
            tenant_id,
            "SalvarChunksVetorizados",
            serde_json::json!({ "treinamento_id": id, "chunks": chunks }),
            "scheduler.tick",
            "",
        )
        .await
        {
            Ok(_) => processados += 1,
            Err(e) => tracing::error!(treinamento_id = id, "falha ao gravar trechos: {e}"),
        }
    }

    Ok(processados)
}

/// Gera o vetor das intenções cadastradas à mão na tela de curadoria.
///
/// Uma intenção sem embedding existe no cadastro e não existe para a IA:
/// `buscar_comportamento_similar` filtra por `embedding IS NOT NULL`.
async fn processar_intents_sem_embedding(state: &AppState) -> anyhow::Result<usize> {
    let limite = env_u64("SMARTCORE_VETORIZACAO_LOTE", 20);

    let resp = chamar_rpc(
        &state.pg_client,
        SISTEMA_TENANT_PLACEHOLDER,
        "ListarIntentsSemEmbedding",
        serde_json::json!({ "limite": limite }),
        "scheduler.tick",
        "",
    )
    .await?;

    let pendentes = resp
        .get("pendentes")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut processadas = 0usize;
    for item in pendentes {
        let (Some(id), Some(tenant_id), Some(texto)) = (
            item.get("id").and_then(|v| v.as_i64()),
            item.get("tenant_id").and_then(|v| v.as_str()),
            item.get("texto").and_then(|v| v.as_str()),
        ) else {
            continue;
        };

        let embed_out = match state
            .ia_client
            .embed(
                ia_engine::EmbedInput {
                    tenant_id: tenant_id.to_string(),
                    textos: vec![texto.to_string()],
                },
                "",
            )
            .await
        {
            Ok(out) => out,
            Err(e) => {
                tracing::warn!(intent_id = id, "ia_engine.Embed falhou; segue na fila: {e}");
                continue;
            }
        };

        let Some(embedding) = embed_out
            .embeddings
            .into_iter()
            .next()
            .filter(|e| !e.is_empty())
        else {
            tracing::warn!(intent_id = id, "embedding vazio; segue na fila");
            continue;
        };

        match chamar_rpc(
            &state.pg_client,
            tenant_id,
            "DefinirEmbeddingIntent",
            serde_json::json!({ "id": id, "embedding": embedding }),
            "scheduler.tick",
            "",
        )
        .await
        {
            Ok(_) => processadas += 1,
            Err(e) => tracing::error!(intent_id = id, "falha ao gravar embedding: {e}"),
        }
    }

    Ok(processadas)
}

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

    #[test]
    fn dividir_corta_em_paragrafos_e_junta_ate_o_teto() {
        // Cortar por numero de caracteres partiria frases no meio, e um vetor
        // de meia frase nao responde pergunta nenhuma.
        let conteudo = "Primeiro paragrafo.

Segundo paragrafo.

Terceiro.";

        let trechos = dividir_em_trechos(conteudo, 1000);

        assert_eq!(trechos.len(), 1, "cabem juntos no teto");
        assert!(trechos[0].contains("Primeiro"));
        assert!(trechos[0].contains("Terceiro"));
    }

    #[test]
    fn dividir_abre_trecho_novo_ao_estourar_o_teto() {
        let conteudo = "aaaaaaaaaa

bbbbbbbbbb

cccccccccc";

        let trechos = dividir_em_trechos(conteudo, 15);

        assert_eq!(trechos.len(), 3);
    }

    #[test]
    fn paragrafo_maior_que_o_teto_nao_e_partido() {
        // Preferir um trecho grande e integro a dois pedacos que perderam o
        // sentido.
        let gigante = "x".repeat(5000);

        let trechos = dividir_em_trechos(&gigante, 100);

        assert_eq!(trechos.len(), 1);
        assert_eq!(trechos[0].chars().count(), 5000);
    }

    #[test]
    fn conteudo_vazio_nao_gera_trecho() {
        // Um embedding de string vazia casaria com qualquer pergunta.
        assert!(dividir_em_trechos("", 100).is_empty());
        assert!(dividir_em_trechos(
            "   

  

 ",
            100
        )
        .is_empty());
    }

    #[test]
    fn linhas_em_branco_extras_nao_viram_trechos_vazios() {
        // Tres quebras seguidas produzem um pedaco vazio no split; vetorizar
        // esse pedaco criaria um trecho que casa com qualquer pergunta.
        let trechos = dividir_em_trechos(
            "Um.



Dois.",
            1000,
        );

        assert_eq!(trechos.len(), 1);
        assert_eq!(
            trechos[0],
            "Um.

Dois."
        );
    }

    async fn estado_sem_redis(pg_addr: &str) -> AppState {
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        let pg_client = StdArc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            storage_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(crate::ia_engine::MockIaEngineClient::new()),
            fluxos_cache: crate::FluxosCache::novo(),
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
