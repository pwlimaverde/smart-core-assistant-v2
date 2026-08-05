//! Serviço worker: Consumidor em background que consome do barramento e orquestra processos de domínio.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use uuid::Uuid;

use std::sync::Arc;

/// Valor de `remetente`/`sender_id` das mensagens do assistente virtual. Espelha
/// `infrastructure_postgres::atendimentos::mensagens::REMETENTE_BOT` (o worker
/// fala com o banco só por RPC, então não importa a crate de infra): é o que faz
/// o `data_postgres` derivar `gerado_por_ia = true` ao persistir, e o que mantém
/// `processar_mensagem_persistida` ignorando a resposta do bot no fluxo outbound.
const REMETENTE_BOT: &str = "bot";
/// Valor de `remetente` das mensagens enviadas por um atendente humano — o único
/// que `processar_mensagem_persistida` trata como envio outbound pendente.
const REMETENTE_ATENDENTE: &str = "atendente";

/// Um fluxo do tenant já formatado para o Responder: `chave` = "Setor - descrição"
/// (convenção da v1, casada pelo ia_engine) e `fluxo_id` (para mapear a decisão de
/// transferência de volta ao fluxo real).
#[derive(Clone)]
struct FluxoItem {
    chave: String,
    fluxo_id: i32,
}

/// Entrada do cache de fluxos: instante de gravação + fluxos do tenant.
type EntradaCacheFluxos = (Instant, Arc<Vec<FluxoItem>>);

/// Cache in-memory por tenant dos fluxos disponíveis (N6.3). TTL curto (~30s) para
/// não bater no `data_postgres` a cada mensagem — a topologia de fluxos muda raramente.
/// Não havia cache equivalente no worker; este é novo e mínimo.
#[derive(Clone)]
struct FluxosCache {
    inner: Arc<tokio::sync::Mutex<HashMap<Uuid, EntradaCacheFluxos>>>,
    ttl: Duration,
}

impl FluxosCache {
    fn novo() -> Self {
        let ttl_secs = std::env::var("SMARTCORE_FLUXOS_CACHE_TTL_SEGUNDOS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(30);
        Self {
            inner: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
            ttl: Duration::from_secs(ttl_secs),
        }
    }

    /// Devolve os fluxos do tenant do cache (se fresco) ou `None` para o chamador carregar.
    async fn obter(&self, tenant: Uuid) -> Option<Arc<Vec<FluxoItem>>> {
        let guard = self.inner.lock().await;
        guard.get(&tenant).and_then(|(gravado_em, fluxos)| {
            (gravado_em.elapsed() < self.ttl).then(|| fluxos.clone())
        })
    }

    async fn gravar(&self, tenant: Uuid, fluxos: Arc<Vec<FluxoItem>>) {
        self.inner
            .lock()
            .await
            .insert(tenant, (Instant::now(), fluxos));
    }
}

// O cliente de IA virou crate quando ganhou um segundo consumidor (a tela
// de testar pergunta, no runtime_api). O apelido preserva os caminhos
// `ia_engine::...` que o pipeline inteiro já usa.
use ia_client as ia_engine;
mod scheduler;

/// Escopos de um ator de SISTEMA (worker). O worker é um serviço interno confiável
/// que reage a eventos do barramento (não a um usuário final); as operações de
/// persistência/orquestração que ele dispara exigem escopos de escrita no
/// `data_postgres`. Usa-se o coringa `"*"` (acesso pleno intra-tenant) para não
/// acoplar o worker ao catálogo de escopos — o RLS do Postgres continua isolando
/// por `tenant_id` em todas as queries.
fn escopos_sistema() -> Vec<String> {
    vec!["*".to_string()]
}

/// Mascara um telefone para auditoria/log, preservando apenas os 4 últimos dígitos.
/// Evita expor PII completa na trilha de auditoria.
fn mascarar_telefone(phone: &str) -> String {
    let digitos: Vec<char> = phone.chars().collect();
    if digitos.len() <= 4 {
        return "*".repeat(digitos.len());
    }
    let visiveis: String = digitos[digitos.len() - 4..].iter().collect();
    format!("{}{}", "*".repeat(digitos.len() - 4), visiveis)
}

/// Chama uma RPC síncrona (`method`) em `client`, propagando `traceparent`/`causation_id`
/// e os escopos de sistema do worker. Retorna o payload desserializado da resposta ou
/// um erro (inclui o corpo de erro do serviço remoto na mensagem).
pub(crate) async fn chamar_rpc(
    client: &transport::MuxClient,
    tenant_id: &str,
    method: &str,
    payload: serde_json::Value,
    causation_id: &str,
    traceparent: &str,
) -> anyhow::Result<serde_json::Value> {
    let envelope = Envelope {
        tenant_id: tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: causation_id.to_string(),
        traceparent: traceparent.to_string(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: method.to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = client.call(envelope, Duration::from_secs(5)).await?;
    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("RPC {} falhou: {}", method, err_msg);
    }
    Ok(serde_json::from_slice(&resp.payload)?)
}

#[derive(Clone)]
struct AppState {
    /// Redis de CACHE (`REDIS_URL`). Só para estado efêmero do próprio worker —
    /// hoje, o lock de debounce. **Não** serve para publicar nada: quem escuta
    /// as publicações do worker (runtime_api, data_postgres) está no barramento.
    #[allow(dead_code)]
    redis_conn: Option<ConnectionManager>,
    /// Redis de BARRAMENTO (`REDIS_BUS_URL`). É por onde saem os eventos de
    /// realtime (`tenant:<id>:events`), que o `RealtimeManager` do runtime_api
    /// assina — ele conecta em `REDIS_BUS_URL` (grpc_web.rs, `serve`). Publicar
    /// no Redis de cache entregava a mensagem a um canal sem nenhum ouvinte.
    #[allow(dead_code)]
    bus_conn: Option<ConnectionManager>,
    audit_logger: observability::AuditLogger,
    pg_client: Arc<transport::MuxClient>,
    whatsapp_client: Arc<transport::MuxClient>,
    storage_client: Arc<transport::MuxClient>,
    ia_client: Arc<dyn ia_engine::IaEngineClient>,
    fluxos_cache: FluxosCache,
}

/// Carrega os fluxos disponíveis do tenant (via `ListarFluxosDoTenant` no
/// data_postgres), com cache TTL curto por tenant. Best-effort: se a RPC falhar ou o
/// tenant não tiver fluxos, devolve lista vazia — o bot segue sem transferência (N6.3).
async fn carregar_fluxos_disponiveis(
    state: &AppState,
    tenant_uuid: Uuid,
    causation_id: &str,
    traceparent: &str,
) -> Arc<Vec<FluxoItem>> {
    if let Some(fluxos) = state.fluxos_cache.obter(tenant_uuid).await {
        return fluxos;
    }

    let resp = match chamar_rpc(
        &state.pg_client,
        &tenant_uuid.to_string(),
        "ListarFluxosDoTenant",
        serde_json::json!({}),
        causation_id,
        traceparent,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(erro = %e, "ListarFluxosDoTenant falhou; seguindo sem fluxos");
            return Arc::new(Vec::new());
        }
    };

    let mut itens = Vec::new();
    if let Some(arr) = resp.get("fluxos").and_then(|v| v.as_array()) {
        for f in arr {
            let Some(fluxo_id) = f.get("id").and_then(|v| v.as_i64()) else {
                continue;
            };
            let setor = f.get("setor").and_then(|v| v.as_str()).unwrap_or_default();
            // Descrição do fluxo compõe a chave "Setor - descrição"; na falta dela,
            // usa o nome do fluxo para o setor não ficar sem qualificador.
            let descricao = f
                .get("descricao")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .or_else(|| f.get("nome").and_then(|v| v.as_str()))
                .unwrap_or_default();
            itens.push(FluxoItem {
                chave: format!("{setor} - {descricao}"),
                fluxo_id: fluxo_id as i32,
            });
        }
    }

    let fluxos = Arc::new(itens);
    state.fluxos_cache.gravar(tenant_uuid, fluxos.clone()).await;
    fluxos
}

/// Aplica a transferência de fluxo decidida pela IA (N6.3): mapeia a chave devolvida em
/// `fluxo_transferencia` de volta ao `fluxo_id` e chama `TransferirAtendimentoParaFluxo`
/// no data_postgres. Best-effort: qualquer falha só significa "sem transferência", nunca
/// trava o atendimento. Audita `atendimento.transferido_por_ia` quando efetiva.
async fn aplicar_transferencia_ia(
    state: &AppState,
    tenant_uuid: Uuid,
    atendimento_id: i32,
    fluxos: &[FluxoItem],
    fluxo_transferencia: &str,
    causation_id: &str,
    traceparent: &str,
) {
    let Some(item) = fluxos.iter().find(|f| f.chave == fluxo_transferencia) else {
        tracing::warn!(
            "IA indicou transferência para fluxo desconhecido; ignorando (sem transferência)"
        );
        return;
    };

    let resp = match chamar_rpc(
        &state.pg_client,
        &tenant_uuid.to_string(),
        "TransferirAtendimentoParaFluxo",
        serde_json::json!({ "atendimento_id": atendimento_id, "fluxo_id": item.fluxo_id }),
        causation_id,
        traceparent,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::warn!(erro = %e, "TransferirAtendimentoParaFluxo falhou; atendimento segue no fluxo atual");
            return;
        }
    };

    if !resp
        .get("transferido")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
    {
        tracing::warn!(
            motivo = resp
                .get("reason")
                .and_then(|v| v.as_str())
                .unwrap_or("desconhecido"),
            "transferência por IA não efetivada"
        );
        return;
    }

    // Auditoria: SEM conteúdo da conversa — só ids/fluxo destino.
    state.audit_logger.info(
        tenant_uuid,
        "atendimento.transferido_por_ia",
        "Atendimento transferido automaticamente pela IA para outro fluxo",
        serde_json::json!({
            "atendimento_id": atendimento_id,
            "fluxo_id": item.fluxo_id,
            "etapa_id": resp.get("etapa_id"),
        }),
        None,
        None,
        Some(causation_id.to_string()),
    );

    // Realtime: notifica o tenant sobre a movimentação no Kanban (mesmo padrão da
    // política automática de ticket/Kanban).
    if let Some(ref bus_conn) = state.bus_conn {
        let channel = format!("tenant:{tenant_uuid}:events");
        let event_payload = serde_json::json!({
            "event_type": "kanban.movido",
            "tenant_id": tenant_uuid.to_string(),
            "payload": {
                "atendimento_id": atendimento_id,
                "fluxo_id": item.fluxo_id,
                "etapa_id": resp.get("etapa_id"),
                "etapa_nome": resp.get("etapa_nome"),
            }
        });
        let mut conn = bus_conn.clone();
        let payload_str = event_payload.to_string();
        let _: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;
    }
}

/// Orquestra a resposta via IA (fase N2.5): resolve a config do tenant, embeda a
/// mensagem, compõe o contexto de RAG (`data_postgres.QueryCompose`) e chama
/// `ia_engine.Responder`. Passos de RAG/histórico são best-effort — só falham a
/// chamada inteira se a config/embed/responder falharem; a barreira de bot
/// (`processar_mensagem_recebida`) decide o fallback textual em caso de erro.
///
/// `skip_all` + `fields` explícitos: a mensagem do usuário é PII e nunca entra no
/// span; só ids de correlação (`tenant_id`/`atendimento_id`).
#[tracing::instrument(
    skip_all,
    name = "ia.responder",
    fields(
        tenant_id = %tenant_uuid,
        atendimento_id = atendimento_id,
        fluxos_count = tracing::field::Empty,
        campos_pendentes_count = tracing::field::Empty,
    )
)]
async fn responder_via_ia(
    state: &AppState,
    tenant_uuid: Uuid,
    atendimento_id: i32,
    mensagem_texto: &str,
    causation_id: &str,
    traceparent: &str,
) -> anyhow::Result<String> {
    let tenant_id_str = tenant_uuid.to_string();

    // 1. Config de IA do tenant (LLM + embeddings provider/api_key), resolvida
    // pelo data_postgres (TenantConfigCache, api_key descriptografada).
    let config_resp = chamar_rpc(
        &state.pg_client,
        &tenant_id_str,
        "ResolverConfigIa",
        serde_json::json!({}),
        causation_id,
        traceparent,
    )
    .await?;
    // O que o ia_engine precisa (provedor, modelo, api_key, prompts, persona,
    // thresholds) ele lê direto do Redis, publicado pelo data_postgres — não
    // trafega mais no request (ver gerenciamento_configuracoes_ia.md). Aqui fica
    // só o que é decisão DO WORKER: o limiar de distância do RAG, usado no
    // QueryCompose logo abaixo.
    let vector_distance_threshold = config_resp
        .get("vector_distance_threshold")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.3);

    // 2. Embedding da mensagem (necessário para o RAG).
    let embed_out = state
        .ia_client
        .embed(
            ia_engine::EmbedInput {
                tenant_id: tenant_id_str.clone(),
                textos: vec![mensagem_texto.to_string()],
            },
            traceparent,
        )
        .await
        .map_err(|e| anyhow::anyhow!("ia_engine.Embed falhou: {e}"))?;
    let query_embedding = embed_out.embeddings.into_iter().next().unwrap_or_default();

    // 3. RAG via data_postgres.QueryCompose — best-effort: uma falha aqui não
    // aborta a resposta, só segue sem contexto de treinamento.
    let mut dados_treinamento = String::new();
    if !query_embedding.is_empty() {
        let qc_payload = serde_json::json!({
            "query_embedding": query_embedding,
            "distance_threshold": vector_distance_threshold,
            "chunk_top_k": 3,
        });
        match chamar_rpc(
            &state.pg_client,
            &tenant_id_str,
            "QueryCompose",
            qc_payload,
            causation_id,
            traceparent,
        )
        .await
        {
            Ok(resp) => {
                let mut partes: Vec<String> = Vec::new();
                if let Some(c) = resp.get("comportamento").and_then(|v| v.as_str()) {
                    partes.push(c.to_string());
                }
                if let Some(docs) = resp.get("documentos").and_then(|v| v.as_array()) {
                    for d in docs {
                        if let Some(c) = d.get("conteudo").and_then(|v| v.as_str()) {
                            partes.push(c.to_string());
                        }
                    }
                }
                dados_treinamento = partes.join("\n\n");
            }
            Err(e) => tracing::warn!("QueryCompose falhou (seguindo sem RAG): {:?}", e),
        }
    }

    // 4. Histórico recente — best-effort (uma falha só significa responder sem
    // histórico, não aborta a resposta).
    let mut historico = Vec::new();
    if let Ok(thread_resp) = chamar_rpc(
        &state.pg_client,
        &tenant_id_str,
        "GetThread",
        serde_json::json!({ "atendimento_id": atendimento_id, "limit": 10 }),
        causation_id,
        traceparent,
    )
    .await
    {
        if let Some(mensagens) = thread_resp.get("mensagens").and_then(|v| v.as_array()) {
            for m in mensagens {
                let remetente = m.get("remetente").and_then(|v| v.as_str()).unwrap_or("");
                let conteudo = m.get("conteudo").and_then(|v| v.as_str()).unwrap_or("");
                if conteudo.is_empty() {
                    continue;
                }
                let role = if remetente == REMETENTE_ATENDENTE || remetente == REMETENTE_BOT {
                    "ai"
                } else {
                    "human"
                };
                historico.push(ia_engine::ChatTurnInput {
                    role: role.to_string(),
                    conteudo: conteudo.to_string(),
                });
            }
        }
    }

    // 4b. Fluxos disponíveis do tenant (N6.3): dá ao Responder o catálogo para
    // decidir transferência. Best-effort/cacheado; lista vazia = sem transferência.
    let fluxos = carregar_fluxos_disponiveis(state, tenant_uuid, causation_id, traceparent).await;
    let fluxos_kv: Vec<(String, String)> = fluxos
        .iter()
        .map(|f| (f.chave.clone(), f.fluxo_id.to_string()))
        .collect();

    // 4c. Campos personalizados do atendimento (N6.3): input-only para o Responder —
    // o contrato do Responder não devolve campos extraídos, então não há write-back
    // aqui (ver decisão registrada no plano). Best-effort: falha = seguir sem campos.
    let (campos_coletados, campos_pendentes) = match chamar_rpc(
        &state.pg_client,
        &tenant_id_str,
        "ResolverCamposAtendimento",
        serde_json::json!({ "atendimento_id": atendimento_id }),
        causation_id,
        traceparent,
    )
    .await
    {
        Ok(resp) => {
            let coletados = resp
                .get("coletados")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|c| {
                            Some(ia_engine::client::CampoColetadoInput {
                                slug: c.get("slug")?.as_str()?.to_string(),
                                nome: c.get("nome")?.as_str()?.to_string(),
                                valor: c.get("valor")?.as_str()?.to_string(),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default();
            let pendentes = resp
                .get("pendentes")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|c| {
                            Some(ia_engine::client::CampoPendenteInput {
                                slug: c.get("slug")?.as_str()?.to_string(),
                                nome: c.get("nome")?.as_str()?.to_string(),
                                descricao: c.get("descricao")?.as_str()?.to_string(),
                                hint: c.get("hint")?.as_str()?.to_string(),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default();
            (coletados, pendentes)
        }
        Err(e) => {
            tracing::warn!(erro = %e, "ResolverCamposAtendimento falhou; seguindo sem campos");
            (Vec::new(), Vec::new())
        }
    };

    let span = tracing::Span::current();
    span.record("fluxos_count", fluxos.len());
    span.record("campos_pendentes_count", campos_pendentes.len());

    // 5. Gera a resposta (Structured Output + score triádico + safety-net de
    // transferência ficam dentro do ia_engine — ver features/responder.py).
    let resposta = state
        .ia_client
        .responder(
            ia_engine::ResponderInput {
                tenant_id: tenant_id_str.clone(),
                atendimento_id: atendimento_id.to_string(),
                mensagem: mensagem_texto.to_string(),
                historico,
                fluxos_disponiveis: fluxos_kv,
                dados_treinamento,
                campos_coletados,
                campos_pendentes,
            },
            traceparent,
        )
        .await
        .map_err(|e| anyhow::anyhow!("ia_engine.Responder falhou: {e}"))?;

    // N6.3: quando a IA decide transferir e devolve um fluxo válido, move o atendimento
    // para o fluxo/etapa certos. Best-effort — nunca falha a resposta ao usuário.
    if resposta.transferir_atendimento && !resposta.fluxo_transferencia.is_empty() {
        aplicar_transferencia_ia(
            state,
            tenant_uuid,
            atendimento_id,
            &fluxos,
            &resposta.fluxo_transferencia,
            causation_id,
            traceparent,
        )
        .await;
    }

    Ok(resposta.resposta_texto)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Inicializa observabilidade
    observability::init_telemetry("worker", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    // Panic em task de background mata so a task: o processo segue vivo e a
    // funcionalidade some sem deixar rastro. O hook garante o registro estruturado.
    observability::instalar_hook_de_panic("worker");
    tracing::info!("Iniciando serviço worker...");

    // 2. Conecta às DUAS instâncias de Redis, que têm papéis distintos.
    //
    // O worker era o único serviço da stack que fazia tudo por `REDIS_URL` —
    // control_plane, data_whatsapp, webhook_ingress, runtime_api e data_postgres
    // já usavam `REDIS_BUS_URL` para o barramento. Como dev e prod sobem duas
    // instâncias separadas (`redis` e `redis-bus`), o worker consumia
    // `events:stream` de um Redis onde ninguém publica, e publicava auditoria e
    // realtime num Redis que ninguém lê. O fallback para `REDIS_URL` mantém
    // funcionando quem só tem uma instância (ambientes de teste).
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let bus_url = std::env::var("REDIS_BUS_URL").unwrap_or_else(|_| redis_url.clone());

    // Cache: estado efêmero do próprio worker (lock de debounce).
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client.clone()).await?;

    // Barramento: consumo de `events:stream`, auditoria e realtime.
    let bus_client = redis::Client::open(bus_url)?;
    let bus_conn = ConnectionManager::new(bus_client.clone()).await?;
    tracing::info!("Conexões com Redis (cache e barramento) estabelecidas.");

    // Conecta ao microserviço data_postgres (cliente gRPC persistente)
    let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await?);
    tracing::info!("Cliente RPC data_postgres estabelecido.");

    // Conecta ao microserviço data_whatsapp (cliente gRPC persistente)
    let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await?);
    tracing::info!("Cliente RPC data_whatsapp estabelecido.");

    // Conecta ao microserviço data_storage (cliente gRPC persistente) — usado pelo
    // pipeline de mídia (N6.1) para gravar o binário baixado no R2.
    let storage_client = Arc::new(transport::conectar_cliente("data_storage").await?);
    tracing::info!("Cliente RPC data_storage estabelecido.");

    // Conecta ao ia_engine (gRPC real, HTTP/2 — não o protocolo interno transport::
    // MuxClient) com resiliência (timeout+retry). `connect_lazy` não bloqueia o
    // boot do worker: falhas de conectividade só aparecem na primeira chamada real
    // e degradam graciosamente para o texto fixo (ver `responder_via_ia`).
    let ia_engine_endpoint = std::env::var("SMARTCORE_IA_ENGINE_ENDPOINT")
        .unwrap_or_else(|_| "http://127.0.0.1:50060".to_string());
    let ia_client: Arc<dyn ia_engine::IaEngineClient> =
        Arc::new(ia_engine::ResilientIaEngine::new(
            ia_engine::TonicIaEngineClient::connect_lazy(&ia_engine_endpoint)?,
        ));
    tracing::info!(endpoint = %ia_engine_endpoint, "Cliente gRPC ia_engine estabelecido (lazy).");

    // A auditoria vai para o barramento: é de lá que o consumidor do
    // `data_postgres` lê o `security:stream` para consolidar em `audit_log`.
    let audit_logger = observability::AuditLogger::new_with_redis(bus_conn.clone(), "worker");
    let state = AppState {
        redis_conn: Some(redis_conn),
        bus_conn: Some(bus_conn),
        audit_logger,
        pg_client,
        whatsapp_client,
        storage_client,
        ia_client,
        fluxos_cache: FluxosCache::novo(),
    };

    // 3. Inicia o consumidor do barramento (events:stream)
    // Nome do consumidor: default histórico (`worker_consumer_1`), sobrescrevível
    // por réplica via `SMARTCORE_CONSUMER_NAME` — ver `bus::nome_consumidor`.
    let consumidor = transport::bus::nome_consumidor("worker_consumer");
    let consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "worker_group",
        consumidor.clone(),
        bus_client.clone(),
    );

    tracing::info!("Consumidor do worker ativado e escutando eventos.");

    // 3b. Scheduler temporal (F4.3b): timeout de feedback + disparo de purga de mídia.
    // Roda em tokio::spawn paralelo ao loop de consumo do bus abaixo.
    scheduler::iniciar(state.clone());

    // 3c. Reprocessamento periódico da PEL + varredura de DLQ.
    //
    // `Consumer::run` relê a PEL uma única vez, no boot: um evento cujo handler
    // falhou durante o loop ativo ficava pendente até o próximo restart do worker
    // — mensagem do cliente sem resposta por tempo indeterminado — e nunca era
    // movido para a dead-letter. Este tick fecha as duas pontas (o data_postgres
    // já fazia o mesmo com o stream de auditoria).
    //
    // O tick roda em paralelo ao loop de consumo, e a PEL não distingue "handler
    // morreu" de "handler está rodando agora": por isso o reprocessamento só toca
    // em eventos parados há mais de `MIN_IDLE_REPROCESSAMENTO_MS`. Sem esse piso, o
    // tick pegaria a mensagem que o loop está processando neste instante e o bot
    // responderia duas vezes ao cliente (a persistência é idempotente pelo
    // stanzaId, mas o envio ao WhatsApp não é).
    {
        let state_retry = state.clone();
        let bus_client_retry = bus_client.clone();
        let consumidor_retry = consumidor.clone();
        let intervalo = std::env::var("SMARTCORE_WORKER_PEL_RETRY_SECS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(60u64);
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(intervalo));
            loop {
                tick.tick().await;
                let state_tick = state_retry.clone();
                let handler = move |evt| {
                    let state = state_tick.clone();
                    async move { despachar_evento(&state, evt).await }
                };
                if let Err(e) = transport::bus::reprocessar_pendentes_uma_vez(
                    &bus_client_retry,
                    transport::bus::STREAM_EVENTOS,
                    "worker_group",
                    &consumidor_retry,
                    transport::bus::MIN_IDLE_REPROCESSAMENTO_MS,
                    handler,
                )
                .await
                {
                    tracing::warn!("Falha no reprocessamento periódico da PEL: {:?}", e);
                }
            }
        });
    }

    // Loop de consumo
    let state_clone = state.clone();
    tokio::select! {
        res = consumer.run(move |evt| {
            let state = state_clone.clone();
            async move { despachar_evento(&state, evt).await }
        }) => {
            if let Err(e) = res {
                tracing::error!("Consumidor do worker parou com erro crítico: {:?}", e);
            }
        }
        // Ver a nota em `data_redis`: sem tratar SIGTERM, o deploy interrompe o
        // processamento de uma mensagem no meio, e o evento volta para a PEL sem
        // que ninguém registre por quê.
        _ = observability::aguardar_sinal_de_parada() => {
            tracing::info!("Encerrando o consumidor do worker a pedido do supervisor.");
        }
    }

    observability::shutdown_telemetry();
    Ok(())
}

/// Roteia um evento do barramento para o handler do seu tipo. Compartilhado pelo
/// loop de consumo e pelo reprocessador periódico da PEL — os dois têm de tratar
/// exatamente o mesmo conjunto de eventos, senão um evento reentregue seria
/// silenciosamente descartado (ou reprocessado por um caminho diferente).
async fn despachar_evento(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    match evt.event_type.as_str() {
        "whatsapp.message.received" | "message.received" => {
            processar_mensagem_recebida(state, evt).await
        }
        "whatsapp.message.status" => processar_status_mensagem(state, evt).await,
        "message.persisted" => processar_mensagem_persistida(state, evt).await,
        // Eventos de outros consumidores (ex.: `media.purge`, do data_storage)
        // compartilham o stream: ignorar é o comportamento correto, e o XACK do
        // Consumer evita que fiquem pendurados na PEL deste grupo.
        _ => Ok(()),
    }
}

/// Consome o evento "message.received", orquestra e delega persistência ao data_postgres via RPC síncrono.
async fn processar_mensagem_recebida(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;

    let raw_payload = &envelope.payload;
    let raw_event = raw_payload
        .get("raw_event")
        .ok_or_else(|| anyhow::anyhow!("raw_event ausente"))?;
    let instance_id = raw_payload
        .get("instance_id")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;

    // Normalização via domain_whatsapp
    let msg_normalized =
        domain_whatsapp::NormalizedMessage::parse(raw_event, envelope.tenant_id, instance_id)
            .map_err(|e| anyhow::anyhow!("Erro ao normalizar mensagem: {}", e))?;

    tracing::info!(
        event_id = %envelope.event_id,
        tenant_id = %envelope.tenant_id,
        sender = %msg_normalized.sender,
        "Worker processando evento message.received."
    );

    let pg_client = &state.pg_client;

    // 1. Resolve atendimento para contato
    let resolve_payload = serde_json::json!({
        "phone": msg_normalized.sender,
        "push_name": msg_normalized.push_name,
    });

    let resolve_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "ResolveAtendimentoParaContato".to_string(),
        payload: serde_json::to_vec(&resolve_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resolve_resp = pg_client
        .call(resolve_envelope, Duration::from_secs(5))
        .await?;
    if resolve_resp.kind == MessageKind::Error as i32 {
        let err_msg = resolve_resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("Falha ao resolver atendimento: {}", err_msg);
    }

    let resolve_body: serde_json::Value = serde_json::from_slice(&resolve_resp.payload)?;
    let atendimento_id = resolve_body
        .get("atendimento_id")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| anyhow::anyhow!("atendimento_id ausente na resposta"))?
        as i32;

    // 2. Persiste a mensagem no atendimento resolvido.
    //
    // `fromMe` = a mensagem saiu do próprio WhatsApp da instância: o atendente
    // escreveu pelo celular/WhatsApp Web, ou é o eco da resposta que o bot acabou
    // de enviar. Registrar isso como se fosse fala do CONTATO faria o bot responder
    // à sua própria mensagem — e o eco dessa resposta voltaria pelo webhook, em
    // laço. Regra herdada da v1 (`protocolo_comunicacao.md` §4.2): grava como
    // ATENDENTE e não aciona o bot.
    //
    // O eco da resposta do bot não chega a ser gravado como atendente: ele traz o
    // MESMO stanzaId que o `SendWhatsappMessage` devolveu e que já foi persistido
    // junto da resposta, então a idempotência por stanzaId do `data_postgres`
    // reconhece a mensagem existente (remetente `bot`, autoria correta no chat) e
    // devolve ela. Sobra como "atendente" só o que o humano digitou de fato no
    // celular/WhatsApp Web — exatamente o caso que a regra da v1 descreve.
    let de_mim = msg_normalized.is_from_me;
    let remetente = if de_mim {
        REMETENTE_ATENDENTE
    } else {
        msg_normalized.sender.as_str()
    };
    let persist_payload = serde_json::json!({
        "atendimento_id": atendimento_id,
        "content": msg_normalized.content,
        "tipo": match msg_normalized.media_type {
            domain_whatsapp::MediaType::Text => "texto",
            domain_whatsapp::MediaType::Image => "imagem",
            domain_whatsapp::MediaType::Audio => "audio",
            domain_whatsapp::MediaType::Video => "video",
            domain_whatsapp::MediaType::Document => "documento",
            domain_whatsapp::MediaType::Location => "localizacao",
            domain_whatsapp::MediaType::Sticker => "sticker",
            domain_whatsapp::MediaType::Contact => "contato",
            domain_whatsapp::MediaType::Other(ref o) => o,
        },
        "sender_id": remetente,
        // Chave natural de idempotência: o bus é at-least-once, e sem o stanzaId
        // uma reentrega duplicaria a mensagem no chat.
        "message_id_whatsapp": msg_normalized.message_id,
        // Citação (reply) do WhatsApp: o data_postgres resolve o stanzaId citado
        // para o id interno da mensagem.
        "citando_message_id_whatsapp": msg_normalized.reply_to,
        // Mensagem `fromMe` já trafegou pelo WhatsApp; nasce `status_envio='sent'`
        // para o elo outbox->outbound NÃO reenviá-la ao contato.
        "ja_entregue": de_mim,
    });

    let persist_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "PersistMessage".to_string(),
        payload: serde_json::to_vec(&persist_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = pg_client
        .call(persist_envelope, Duration::from_secs(5))
        .await?;

    let tenant_uuid = envelope.tenant_id;

    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");

        state.audit_logger.error(
            tenant_uuid,
            "mensagem.falha_persistencia",
            &format!(
                "Falha na persistência da mensagem via data_postgres RPC: {}",
                err_msg
            ),
            serde_json::json!({
                "error": err_msg,
                "sender_id": mascarar_telefone(&msg_normalized.sender),
            }),
            None,
            None,
            Some(envelope.event_id.to_string()),
        );

        anyhow::bail!(
            "Falha na persistência da mensagem via data_postgres RPC: {}",
            err_msg
        );
    }

    // Id da mensagem recém-persistida (necessário para anexar a análise de mídia depois).
    let mensagem_id: Option<i32> = serde_json::from_slice::<serde_json::Value>(&resp.payload)
        .ok()
        .and_then(|v| v.get("message_id").and_then(|m| m.as_i64()))
        .map(|id| id as i32);

    state.audit_logger.info(
        tenant_uuid,
        "mensagem.persistida",
        "Mensagem persistida com sucesso via worker",
        serde_json::json!({
            "atendimento_id": atendimento_id,
            "sender_id": mascarar_telefone(&msg_normalized.sender),
        }),
        None,
        None,
        Some(envelope.event_id.to_string()),
    );

    tracing::info!(
        event_id = %envelope.event_id,
        atendimento_id = atendimento_id,
        "Mensagem persistida com sucesso via RPC síncrono do data_postgres."
    );

    if let Some(ref bus_conn) = state.bus_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.recebida",
            "tenant_id": tenant_uuid.to_string(),
            "payload": {
                "atendimento_id": atendimento_id,
                "message": msg_normalized,
            }
        });

        let mut conn = bus_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;

        if let Err(e) = publish_res {
            tracing::error!("Erro ao publicar mensagem no Redis Pub/Sub: {:?}", e);
        }
    }

    // 2c. Pipeline de mídia (N6.1): quando a mensagem carrega mídia, dispara o
    // download+análise em background (fire-and-forget controlado). A mensagem já
    // apareceu no chat na etapa de persistência acima — a análise é assíncrona e
    // NUNCA bloqueia nem falha o handler principal (degradação graciosa interna).
    // `de_mim` fica fora: é mídia que o próprio atendente enviou — não há o que
    // transcrever/interpretar para ele, e transcrever custa por minuto de áudio.
    if let (false, Some(media_payload), Some(mensagem_id)) =
        (de_mim, msg_normalized.media_payload.clone(), mensagem_id)
    {
        let state_midia = state.clone();
        let raw_event = raw_event.clone();
        let media_type = msg_normalized.media_type.clone();
        let media_mime = msg_normalized.media_mime.clone();
        let tenant_str = envelope.tenant_id.to_string();
        let causation = envelope.event_id.to_string();
        let traceparent = envelope.traceparent.clone();
        tokio::spawn(async move {
            processar_pipeline_midia(
                &state_midia,
                tenant_uuid,
                &tenant_str,
                instance_id,
                atendimento_id,
                mensagem_id,
                media_type,
                media_mime,
                media_payload,
                &raw_event,
                &causation,
                &traceparent,
            )
            .await;
        });
    }

    // 2d. Sentimento (N6.5): mensagens de texto avaliam o tom da conversa em
    // background, best-effort (mensagens de mídia sem legenda ficam para quando a
    // transcrição terminar — ver `processar_pipeline_midia`). Nunca bloqueia nem
    // falha o handler principal.
    //
    // `texto_para_ia` (não `content`): sentimento se mede sobre o que o CONTATO
    // escreveu. Mídia sem legenda tem `content` = URL da CDN, que não tem tom
    // nenhum a medir; e `de_mim` é fala do atendente, não do cliente.
    if let (false, Some(texto_contato)) = (de_mim, msg_normalized.texto_para_ia()) {
        let state_sentimento = state.clone();
        let texto = texto_contato.to_string();
        let tenant_str = envelope.tenant_id.to_string();
        let causation = envelope.event_id.to_string();
        let traceparent = envelope.traceparent.clone();
        tokio::spawn(async move {
            avaliar_sentimento_best_effort(
                &state_sentimento,
                tenant_uuid,
                &tenant_str,
                atendimento_id,
                &texto,
                &causation,
                &traceparent,
            )
            .await;
        });
    }

    // 3. Se o atendimento foi acabado de criar (is_new == true), audita a abertura
    let is_new = resolve_body
        .get("is_new")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if is_new {
        state.audit_logger.info(
            tenant_uuid,
            "atendimento.aberto",
            "Novo atendimento aberto para o contato",
            serde_json::json!({
                "atendimento_id": atendimento_id,
                "sender_id": mascarar_telefone(&msg_normalized.sender),
            }),
            None,
            None,
            Some(envelope.event_id.to_string()),
        );

        // Política de ticket/Kanban: posiciona o atendimento recém-aberto na etapa
        // inicial do fluxo. Falha aqui não interrompe o processamento da mensagem
        // (best-effort), mas é auditada/logada.
        if let Err(e) = aplicar_politica_ticket_kanban(
            state,
            tenant_uuid,
            &envelope.event_id.to_string(),
            &envelope.traceparent,
            atendimento_id,
        )
        .await
        {
            tracing::warn!(
                atendimento_id = atendimento_id,
                "Falha ao aplicar política de ticket/Kanban: {:?}",
                e
            );
        }
    }

    // Mensagem do próprio número (atendente pelo celular, ou eco da resposta do
    // bot): já está registrada no thread; daqui para baixo é só automação de
    // resposta, que não se aplica. Encerrar aqui é o que quebra o laço
    // bot → eco → bot descrito na etapa 2.
    if de_mim {
        state.audit_logger.info(
            tenant_uuid,
            "bot.silenciado",
            "Mensagem enviada pelo próprio número da instância; bot não responde",
            serde_json::json!({
                "atendimento_id": atendimento_id,
                "motivo": "from_me",
            }),
            None,
            None,
            Some(envelope.event_id.to_string()),
        );
        return Ok(());
    }

    // 4. Aplica o debounce de 2 segundos para regras do Bot/Kanban
    let mut is_debounce_winner = true;
    if let Some(ref redis_conn) = state.redis_conn {
        let lock_key = format!(
            "tenant:{}:lock:debounce:{}",
            tenant_uuid, msg_normalized.sender
        );
        let mut conn = redis_conn.clone();
        let set_res: Result<bool, _> = redis::cmd("SET")
            .arg(&lock_key)
            .arg("1")
            .arg("NX")
            .arg("EX")
            .arg(2) // 2 segundos
            .query_async(&mut conn)
            .await;

        match set_res {
            Ok(inserted) => {
                is_debounce_winner = inserted;
            }
            Err(e) => {
                tracing::error!("Erro no Redis ao obter lock de debounce: {:?}", e);
            }
        }
    }

    if is_debounce_winner {
        // 5. Verifica a barreira de bot
        let bot_pode_atender = resolve_body
            .get("bot_pode_atender")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let atendente_humano_id = resolve_body
            .get("atendente_humano_id")
            .and_then(|v| v.as_i64());

        // Sem texto do contato não há pergunta a responder: mídia sem legenda,
        // sticker, localização. Antes o bot era acionado de todo jeito com
        // `content`, que nesses casos é a URL da CDN — a IA recebia "https://..."
        // como se fosse a fala do cliente. O conteúdo da mídia entra na conversa
        // pelo pipeline de mídia (transcrição/análise), não por aqui.
        let texto_do_contato = msg_normalized.texto_para_ia();

        if bot_pode_atender && atendente_humano_id.is_none() && texto_do_contato.is_some() {
            tracing::info!(
                atendimento_id = atendimento_id,
                sender = %msg_normalized.sender,
                "Assistente virtual respondendo à mensagem..."
            );

            const BOT_TEXT_FALLBACK: &str = "Olá! Sou o assistente virtual. Recebi sua mensagem e ela já está na nossa fila de atendimento. Em breve um atendente falará com você.";

            // N2.5: tenta responder via ia_engine (RAG); degrada para o texto fixo
            // em qualquer falha (timeout/indisponibilidade/erro do provedor) — a
            // barreira de bot NUNCA trava o atendimento por causa da IA.
            let bot_text = match responder_via_ia(
                state,
                tenant_uuid,
                atendimento_id,
                texto_do_contato.unwrap_or_default(),
                &envelope.event_id.to_string(),
                &envelope.traceparent,
            )
            .await
            {
                Ok(texto) if !texto.trim().is_empty() => texto,
                Ok(_) => {
                    tracing::warn!(
                        atendimento_id = atendimento_id,
                        "ia_engine devolveu resposta vazia; usando fallback"
                    );
                    state.audit_logger.warn(
                        tenant_uuid,
                        "bot.degradado",
                        "Resposta da IA veio vazia — usando resposta padrão",
                        serde_json::json!({ "atendimento_id": atendimento_id }),
                        None,
                        None,
                        Some(envelope.event_id.to_string()),
                    );
                    BOT_TEXT_FALLBACK.to_string()
                }
                Err(e) => {
                    tracing::warn!(
                        atendimento_id = atendimento_id,
                        "ia_engine indisponível/erro, usando fallback: {:?}",
                        e
                    );
                    state.audit_logger.warn(
                        tenant_uuid,
                        "bot.degradado",
                        "Falha ao consultar a IA — usando resposta padrão",
                        serde_json::json!({
                            "atendimento_id": atendimento_id,
                            "motivo": e.to_string(),
                        }),
                        None,
                        None,
                        Some(envelope.event_id.to_string()),
                    );
                    BOT_TEXT_FALLBACK.to_string()
                }
            };
            let bot_text = bot_text.as_str();

            // Chaves exigidas pelo handler de data_whatsapp (main.rs de data_whatsapp,
            // handler_send_whatsapp_message): "id" (db id da instância) e "to_number"
            // (telefone) — não "instance_id"/"to" (bug pré-existente corrigido na N1.3).
            let outbound_payload = serde_json::json!({
                "id": instance_id,
                "to_number": msg_normalized.sender,
                "text": bot_text,
            });

            let outbound_envelope = Envelope {
                tenant_id: envelope.tenant_id.to_string(),
                schema_version: 1,
                message_id: Uuid::now_v7().to_string(),
                causation_id: envelope.event_id.to_string(),
                traceparent: envelope.traceparent.clone(),
                occurred_at: chrono::Utc::now().timestamp_millis(),
                kind: MessageKind::Request as i32,
                method: "SendWhatsappMessage".to_string(),
                payload: serde_json::to_vec(&outbound_payload).unwrap_or_default(),
                error: None,
                auth_user_id: 0,
                auth_scopes: escopos_sistema(),
                auth_is_superuser: false,
                flow_permissions: vec![],
                user_agent: String::new(),
            };

            let out_resp = state
                .whatsapp_client
                .call(outbound_envelope, Duration::from_secs(5))
                .await?;
            if out_resp.kind == MessageKind::Error as i32 {
                let err_msg = out_resp
                    .error
                    .as_ref()
                    .map(|e| e.message.as_str())
                    .unwrap_or("Erro desconhecido");
                tracing::error!("Falha ao enviar resposta do bot: {}", err_msg);

                // Auditoria de falha de envio outbound (sem corpo da mensagem).
                state.audit_logger.warn(
                    tenant_uuid,
                    "mensagem.falha_envio",
                    "Falha ao enviar resposta automática do assistente virtual",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                        "error": err_msg,
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
            } else {
                // Persiste a resposta do bot no thread (remetente "bot" ⇒
                // `gerado_por_ia=true` no INSERT do data_postgres). Sem isto: o
                // atendente não vê no chat o que o bot respondeu, e o próprio bot
                // perde a memória das suas respostas — o `historico` do
                // `Responder` é montado a partir do `GetThread`, então cada turno
                // veria só as falas do contato. Best-effort: a mensagem já foi
                // entregue ao contato, uma falha aqui não deve derrubar o
                // processamento (só deixa o thread incompleto).
                //
                // Não realimenta o loop de envio: `processar_mensagem_persistida`
                // só reage a `sender_id == "atendente"`.
                //
                // O stanzaId devolvido pelo provedor vai junto: é o que correlaciona
                // os webhooks de status (`sent`/`delivered`/`read`) desta resposta
                // com a linha no thread — sem ele, `UpdateMessageStatus` não acha a
                // mensagem e o atendente nunca vê o "entregue/lido" do que o bot
                // respondeu. Também torna a persistência idempotente se o evento
                // for reentregue pela PEL.
                let stanza_bot = serde_json::from_slice::<serde_json::Value>(&out_resp.payload)
                    .ok()
                    .and_then(|v| {
                        v.get("message_id")
                            .and_then(|m| m.as_str())
                            .map(|s| s.to_string())
                    })
                    .unwrap_or_default();
                if let Err(e) = chamar_rpc(
                    &state.pg_client,
                    &envelope.tenant_id.to_string(),
                    "PersistMessage",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "content": bot_text,
                        "sender_id": REMETENTE_BOT,
                        "tipo": "texto",
                        "message_id_whatsapp": stanza_bot,
                        // Já entregue ao contato pelo envio acima.
                        "ja_entregue": true,
                    }),
                    &envelope.event_id.to_string(),
                    &envelope.traceparent,
                )
                .await
                {
                    tracing::warn!(
                        atendimento_id = atendimento_id,
                        erro = %e,
                        "falha ao persistir a resposta do bot no thread (mensagem já entregue ao contato)"
                    );
                }

                // Auditoria de barreira de bot (respondeu) e do envio outbound.
                state.audit_logger.info(
                    tenant_uuid,
                    "bot.respondeu",
                    "Resposta automática do assistente virtual enviada com sucesso",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
                state.audit_logger.info(
                    tenant_uuid,
                    "mensagem.enviada",
                    "Mensagem outbound enviada com sucesso via data_whatsapp",
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "recipient": mascarar_telefone(&msg_normalized.sender),
                    }),
                    None,
                    None,
                    Some(envelope.event_id.to_string()),
                );
            }
        } else {
            // Barreira de bot impediu a resposta automática (humano ativo, flag
            // desligada ou mensagem sem texto a responder).
            state.audit_logger.info(
                tenant_uuid,
                "bot.silenciado",
                "Assistente virtual silenciado para o atendimento",
                serde_json::json!({
                    "atendimento_id": atendimento_id,
                    "bot_pode_atender": bot_pode_atender,
                    "humano_ativo": atendente_humano_id.is_some(),
                    "sem_texto": texto_do_contato.is_none(),
                }),
                None,
                None,
                Some(envelope.event_id.to_string()),
            );
        }
    }

    Ok(())
}

/// Rótulo curto e estável do tipo de mídia (usado no caminho da chave do R2 e no
/// atributo `media_type` do span/telemetria).
fn rotulo_media_type(t: &domain_whatsapp::MediaType) -> &'static str {
    match t {
        domain_whatsapp::MediaType::Image => "image",
        domain_whatsapp::MediaType::Audio => "audio",
        domain_whatsapp::MediaType::Video => "video",
        domain_whatsapp::MediaType::Document => "document",
        _ => "other",
    }
}

/// Extrai o `trace-id` do traceparent W3C (`00-<trace-id>-<span-id>-<flags>`) para
/// registrar como atributo de span; devolve o próprio valor quando o formato foge do padrão.
fn trace_id_de(traceparent: &str) -> &str {
    traceparent.split('-').nth(1).unwrap_or(traceparent)
}

/// Pipeline de mídia (N6.1): baixa o binário da mídia da Evolution (via
/// `data_whatsapp`), grava no R2 (via `data_storage`), pede transcrição/análise à
/// IA (via `ia_engine`) e anexa resumo/análise + ponteiro à mensagem (via
/// `data_postgres`). Roda em background (fire-and-forget): TODA falha aqui degrada
/// graciosamente — a mensagem já está no chat, só a análise fica ausente. Nunca
/// propaga erro nem faz pânico.
///
/// `skip_all`: `media_payload`/`raw_event` carregam metadados da mídia (potencial
/// PII); só ids de correlação entram no span. `error_code` é preenchido via
/// `Span::record` quando alguma etapa falha.
#[allow(clippy::too_many_arguments)]
#[tracing::instrument(
    skip_all,
    name = "midia.pipeline",
    fields(
        tenant_id = %tenant_uuid,
        trace_id = %trace_id_de(traceparent),
        message_id = mensagem_id,
        media_type = %rotulo_media_type(&media_type),
        error_code = tracing::field::Empty,
    )
)]
async fn processar_pipeline_midia(
    state: &AppState,
    tenant_uuid: Uuid,
    tenant_str: &str,
    instance_id: i32,
    atendimento_id: i32,
    mensagem_id: i32,
    media_type: domain_whatsapp::MediaType,
    media_mime: Option<String>,
    _media_payload: serde_json::Value,
    raw_event: &serde_json::Value,
    causation_id: &str,
    traceparent: &str,
) {
    let span = tracing::Span::current();
    let inicio = std::time::Instant::now();
    let tipo_str = rotulo_media_type(&media_type);

    // A Evolution espera a mensagem completa (nó `data` do webhook, com key+message)
    // no corpo do downloadmedia. A URL da CDN do WhatsApp expira em ~1h, por isso o
    // download é disparado imediatamente após a persistência (fila curta).
    let message = match raw_event.get("data") {
        Some(d) => d.clone(),
        None => {
            span.record("error_code", "sem_data");
            tracing::warn!("pipeline de mídia abortado: raw_event sem 'data'");
            return;
        }
    };

    // 1. Download da mídia (data_whatsapp). Erros 401/400/500 da Evolution são
    // transitório-terminais (token/mediaKey/URL expirados): não vale retry tardio —
    // o próprio erro já vem tratado do data_whatsapp; aqui só degradamos.
    let download = match chamar_rpc(
        &state.whatsapp_client,
        tenant_str,
        "DownloadWhatsappMedia",
        serde_json::json!({ "id": instance_id, "message": message }),
        causation_id,
        traceparent,
    )
    .await
    {
        Ok(v) => v,
        Err(e) => {
            span.record("error_code", "download_falhou");
            tracing::warn!(erro = %e, "download de mídia falhou; análise ausente");
            return;
        }
    };

    let base64 = download
        .get("base64")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    if base64.is_empty() {
        span.record("error_code", "midia_vazia");
        tracing::warn!("download de mídia retornou base64 vazio; análise ausente");
        return;
    }
    let mime = download
        .get("mime_type")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or(media_mime)
        .unwrap_or_default();

    // 2. Grava o binário no R2 (data_storage). Chave content-addressable:
    // media/{tenant}/{instance}/{type}/{hash}. O hash do base64 (determinístico a
    // partir do conteúdo) garante dedup e evita colisão entre mídias distintas.
    let hash = {
        let mut hasher = Sha256::new();
        hasher.update(base64.as_bytes());
        format!("{:x}", hasher.finalize())
    };
    let file_key = format!("media/{tenant_str}/{instance_id}/{tipo_str}/{hash}");

    if let Err(e) = chamar_rpc(
        &state.storage_client,
        tenant_str,
        "PutFile",
        serde_json::json!({ "file_name": file_key, "content_base64": base64 }),
        causation_id,
        traceparent,
    )
    .await
    {
        span.record("error_code", "storage_falhou");
        tracing::warn!(erro = %e, "falha ao gravar mídia no storage; análise ausente");
        return;
    }

    // 3. Config de IA do tenant (mesmo provider/api_key do LLM é reusado para
    // transcrição/visão neste ciclo — simplificação conhecida; providers dedicados
    // de transcrição/visão ficam para uma continuação). Resolvida ANTES do presign
    // porque o kill-switch de transcrição pode dispensar as duas etapas seguintes.
    let cfg_midia = match transcricao_habilitada(state, tenant_str, causation_id, traceparent).await
    {
        Ok(p) => p,
        Err(e) => {
            span.record("error_code", "config_falhou");
            tracing::warn!(erro = %e, "falha ao resolver config de IA; análise ausente");
            return;
        }
    };

    // N6.4 (passo 4): kill-switch de transcrição por tenant. Desligado, o áudio
    // ainda vai para o R2 e o ponteiro é persistido (o atendente continua podendo
    // ouvir) — só a chamada à IA, o presign que a alimenta e o custo por minuto
    // transcrito são dispensados.
    let audio_sem_transcricao =
        matches!(media_type, domain_whatsapp::MediaType::Audio) && !cfg_midia;
    if audio_sem_transcricao {
        tracing::debug!("transcrição desligada para o tenant; persistindo só o ponteiro do áudio");
        anexar_analise_midia(
            state,
            tenant_uuid,
            tenant_str,
            mensagem_id,
            &file_key,
            "",
            "",
            tipo_str,
            inicio,
            causation_id,
            traceparent,
        )
        .await;
        return;
    }

    // 4. URL pré-assinada para o ia_engine (Python) conseguir buscar o binário.
    let media_url = match chamar_rpc(
        &state.storage_client,
        tenant_str,
        "PresignFile",
        serde_json::json!({ "file_name": file_key, "expires_in": 3600 }),
        causation_id,
        traceparent,
    )
    .await
    {
        Ok(v) => v
            .get("url")
            .and_then(|u| u.as_str())
            .unwrap_or_default()
            .to_string(),
        Err(e) => {
            span.record("error_code", "presign_falhou");
            tracing::warn!(erro = %e, "falha ao pré-assinar URL da mídia; análise ausente");
            return;
        }
    };

    let media_ref = ia_engine::client::MediaRefInput {
        url: media_url,
        mimetype: mime,
        file_name: file_key.clone(),
    };

    // 5. Transcrição (áudio) ou interpretação (imagem/vídeo). Documento não passa por
    // IA neste ciclo — só o ponteiro é persistido. Falha na IA degrada: persistimos
    // ao menos o ponteiro do arquivo.
    let (analise, resumo) = match media_type {
        domain_whatsapp::MediaType::Audio => {
            match state
                .ia_client
                .transcribe(
                    ia_engine::client::TranscribeInput {
                        tenant_id: tenant_str.to_string(),
                        media: media_ref,
                        language: String::new(),
                    },
                    traceparent,
                )
                .await
            {
                Ok(out) => (out.transcricao, out.resumo),
                Err(e) => {
                    span.record("error_code", "ia_falhou");
                    tracing::warn!(erro = %e, "transcrição de áudio falhou; persistindo só o ponteiro");
                    (String::new(), String::new())
                }
            }
        }
        domain_whatsapp::MediaType::Image | domain_whatsapp::MediaType::Video => {
            match state
                .ia_client
                .interpret_media(
                    ia_engine::client::InterpretMediaInput {
                        tenant_id: tenant_str.to_string(),
                        media: media_ref,
                        media_type: tipo_str.to_string(),
                    },
                    traceparent,
                )
                .await
            {
                Ok(out) => (out.analise, out.resumo),
                Err(e) => {
                    span.record("error_code", "ia_falhou");
                    tracing::warn!(erro = %e, "interpretação de mídia falhou; persistindo só o ponteiro");
                    (String::new(), String::new())
                }
            }
        }
        _ => (String::new(), String::new()),
    };

    // 6. Anexa análise/resumo + ponteiro à mensagem (data_postgres). Sempre grava ao
    // menos o ponteiro do arquivo, mesmo quando a IA falhou.
    anexar_analise_midia(
        state,
        tenant_uuid,
        tenant_str,
        mensagem_id,
        &file_key,
        &analise,
        &resumo,
        tipo_str,
        inicio,
        causation_id,
        traceparent,
    )
    .await;

    // 6b. Sentimento (N6.5): áudio transcrito também avalia o tom da conversa,
    // best-effort, em background — não atrasa o retorno deste pipeline.
    if matches!(media_type, domain_whatsapp::MediaType::Audio) && !analise.is_empty() {
        let state_sentimento = state.clone();
        let tenant_str_owned = tenant_str.to_string();
        let texto = analise.clone();
        let causation = causation_id.to_string();
        let traceparent_owned = traceparent.to_string();
        tokio::spawn(async move {
            avaliar_sentimento_best_effort(
                &state_sentimento,
                tenant_uuid,
                &tenant_str_owned,
                atendimento_id,
                &texto,
                &causation,
                &traceparent_owned,
            )
            .await;
        });
    }
}

/// Anexa análise/resumo + ponteiro do arquivo à mensagem e audita `midia.analisada`.
/// Chamado nos dois desfechos do pipeline: com análise da IA, e com análise vazia
/// (IA falhou, tipo sem IA neste ciclo, ou transcrição desligada para o tenant) —
/// em todos, o ponteiro do arquivo no R2 é o que não pode faltar.
///
/// `skip_all`: `analise`/`resumo` derivam de conteúdo do contato (PII) e nunca
/// entram no span nem na auditoria — só ids, tipo e duração.
#[allow(clippy::too_many_arguments)]
#[tracing::instrument(skip_all, fields(mensagem_id = mensagem_id, tipo = tipo_str))]
async fn anexar_analise_midia(
    state: &AppState,
    tenant_uuid: Uuid,
    tenant_str: &str,
    mensagem_id: i32,
    file_key: &str,
    analise: &str,
    resumo: &str,
    tipo_str: &str,
    inicio: std::time::Instant,
    causation_id: &str,
    traceparent: &str,
) {
    if let Err(e) = chamar_rpc(
        &state.pg_client,
        tenant_str,
        "AnexarAnaliseMidia",
        serde_json::json!({
            "mensagem_id": mensagem_id,
            "arquivo_midia": file_key,
            "analise": analise,
            "resumo": resumo,
        }),
        causation_id,
        traceparent,
    )
    .await
    {
        tracing::Span::current().record("error_code", "persist_falhou");
        tracing::warn!(erro = %e, "falha ao anexar análise de mídia à mensagem");
        return;
    }

    // Auditoria: mídia analisada (nível INFO). SEM conteúdo/transcrição — só
    // metadados operacionais. O download em si não gera evento (o span já o rastreia).
    state.audit_logger.info(
        tenant_uuid,
        "midia.analisada",
        "Mídia recebida analisada e anexada à mensagem",
        serde_json::json!({
            "mensagem_id": mensagem_id,
            "tipo": tipo_str,
            "duracao_ms": inicio.elapsed().as_millis() as i64,
        }),
        None,
        None,
        Some(causation_id.to_string()),
    );
}

/// Resolve a config de provider de IA do tenant (via `ResolverConfigIa` no
/// Lê o kill-switch de transcrição do tenant (N6.4) via `ResolverConfigIa`.
///
/// Antes esta função também montava o provedor de LLM para transcrição/visão;
/// isso saiu daqui quando o `ia_engine` passou a ler a config direto do Redis
/// (ver `gerenciamento_configuracoes_ia.md`). O que resta é decisão do worker:
/// gastar ou não uma transcrição paga antes de chamar a IA.
async fn transcricao_habilitada(
    state: &AppState,
    tenant_str: &str,
    causation_id: &str,
    traceparent: &str,
) -> anyhow::Result<bool> {
    let cfg = chamar_rpc(
        &state.pg_client,
        tenant_str,
        "ResolverConfigIa",
        serde_json::json!({}),
        causation_id,
        traceparent,
    )
    .await?;
    // Ausente na resposta = desligado (conservador): a transcrição custa
    // dinheiro/latência por áudio recebido.
    Ok(cfg
        .get("transcription_enabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(false))
}

/// Avalia o sentimento de uma mensagem inbound (texto ou transcrição de áudio) e
/// persiste a leitura mais recente no atendimento (N6.5). Best-effort: qualquer
/// falha (config/RPC/parsing) só significa "sentimento não atualizado desta vez",
/// nunca afeta o atendimento. `skip_all`: o texto da mensagem é PII e nunca entra
/// no span — só a nota (número) é registrada.
#[tracing::instrument(
    skip_all,
    name = "ia.sentimento",
    fields(tenant_id = %tenant_uuid, atendimento_id = atendimento_id, nota = tracing::field::Empty)
)]
async fn avaliar_sentimento_best_effort(
    state: &AppState,
    tenant_uuid: Uuid,
    tenant_str: &str,
    atendimento_id: i32,
    texto: &str,
    causation_id: &str,
    traceparent: &str,
) {
    // Sem round-trip de config: o ia_engine resolve o provedor pelo tenant_id,
    // lendo do Redis. Antes era preciso um RPC `ResolverConfigIa` aqui só para
    // montar o `LlmProviderConfigInput` que ia no request.

    let saida = match state
        .ia_client
        .sentimento(
            ia_engine::client::SentimentoInput {
                tenant_id: tenant_str.to_string(),
                historico: vec![ia_engine::ChatTurnInput {
                    role: "human".to_string(),
                    conteudo: texto.to_string(),
                }],
            },
            traceparent,
        )
        .await
    {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(erro = %e, "ia_engine.Sentimento falhou; sentimento não atualizado");
            return;
        }
    };

    tracing::Span::current().record("nota", saida.nota);

    if let Err(e) = chamar_rpc(
        &state.pg_client,
        tenant_str,
        "AtualizarSentimentoAtendimento",
        serde_json::json!({
            "atendimento_id": atendimento_id,
            "nota": saida.nota,
            "label": saida.sentimento,
        }),
        causation_id,
        traceparent,
    )
    .await
    {
        tracing::warn!(erro = %e, "falha ao persistir sentimento do atendimento");
    }
}

/// Aplica a política de ticket/Kanban a um atendimento recém-aberto via RPC ao
/// `data_postgres` e, havendo movimento, audita `ticket.transicionado` + `kanban.movido`
/// e publica o evento de realtime para o tenant (WS-2.4).
async fn aplicar_politica_ticket_kanban(
    state: &AppState,
    tenant_uuid: Uuid,
    causation_id: &str,
    traceparent: &str,
    atendimento_id: i32,
) -> anyhow::Result<()> {
    let payload = serde_json::json!({ "atendimento_id": atendimento_id });

    let req_envelope = Envelope {
        tenant_id: tenant_uuid.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: causation_id.to_string(),
        traceparent: traceparent.to_string(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "AplicarPoliticaTicketKanban".to_string(),
        payload: serde_json::to_vec(&payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = state
        .pg_client
        .call(req_envelope, Duration::from_secs(5))
        .await?;
    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!("Falha ao aplicar política de ticket/Kanban: {}", err_msg);
    }

    let body: serde_json::Value = serde_json::from_slice(&resp.payload)?;
    let moved = body.get("moved").and_then(|v| v.as_bool()).unwrap_or(false);
    if !moved {
        // Sem fluxo configurado / já posicionado: nada a auditar como transição.
        return Ok(());
    }

    let etapa_id = body.get("etapa_id").and_then(|v| v.as_i64());
    let etapa_nome = body
        .get("etapa_nome")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let ticket_status = body
        .get("ticket_status")
        .and_then(|v| v.as_str())
        .unwrap_or("fila")
        .to_string();

    let contexto = serde_json::json!({
        "atendimento_id": atendimento_id,
        "etapa_id": etapa_id,
        "etapa_nome": etapa_nome,
        "status": ticket_status,
    });

    state.audit_logger.info(
        tenant_uuid,
        "ticket.transicionado",
        "Ticket posicionado pela política automática de atendimento",
        contexto.clone(),
        None,
        None,
        Some(causation_id.to_string()),
    );
    state.audit_logger.info(
        tenant_uuid,
        "kanban.movido",
        "Atendimento movido para a etapa inicial do Kanban",
        contexto.clone(),
        None,
        None,
        Some(causation_id.to_string()),
    );

    // Realtime: notifica o tenant sobre a movimentação no Kanban.
    if let Some(ref bus_conn) = state.bus_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "kanban.movido",
            "tenant_id": tenant_uuid.to_string(),
            "payload": contexto,
        });
        let mut conn = bus_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;
        if let Err(e) = publish_res {
            tracing::error!(
                "Erro ao publicar movimento de Kanban no Redis Pub/Sub: {:?}",
                e
            );
        }
    }

    Ok(())
}

async fn processar_status_mensagem(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;
    let raw_payload = &envelope.payload;
    let raw_event = raw_payload
        .get("raw_event")
        .ok_or_else(|| anyhow::anyhow!("raw_event ausente"))?;

    let data = raw_event
        .get("data")
        .ok_or_else(|| anyhow::anyhow!("data ausente no status"))?;
    let status_str = data
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("sent");
    let key = data
        .get("key")
        .ok_or_else(|| anyhow::anyhow!("key ausente no status"))?;
    let msg_id = key
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("id da mensagem ausente"))?;

    tracing::info!(
        event_id = %envelope.event_id,
        tenant_id = %envelope.tenant_id,
        message_id = %msg_id,
        status = %status_str,
        "Worker processando evento whatsapp.message.status"
    );

    let pg_client = &state.pg_client;

    let req_payload = serde_json::json!({
        "message_id_whatsapp": msg_id,
        "status": status_str,
    });

    let req_envelope = Envelope {
        tenant_id: envelope.tenant_id.to_string(),
        schema_version: 1,
        message_id: Uuid::now_v7().to_string(),
        causation_id: envelope.event_id.to_string(),
        traceparent: envelope.traceparent.clone(),
        occurred_at: chrono::Utc::now().timestamp_millis(),
        kind: MessageKind::Request as i32,
        method: "UpdateMessageStatus".to_string(),
        payload: serde_json::to_vec(&req_payload).unwrap_or_default(),
        error: None,
        auth_user_id: 0,
        auth_scopes: escopos_sistema(),
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let resp = pg_client.call(req_envelope, Duration::from_secs(5)).await?;

    if resp.kind == MessageKind::Error as i32 {
        let err_msg = resp
            .error
            .as_ref()
            .map(|e| e.message.as_str())
            .unwrap_or("Erro desconhecido");
        anyhow::bail!(
            "Falha ao atualizar status da mensagem no data_postgres: {}",
            err_msg
        );
    }

    // Convenção do glossário (§8): confirmação de status outbound usa `mensagem.confirmada`.
    state.audit_logger.info(
        envelope.tenant_id,
        "mensagem.confirmada",
        "Status de mensagem do WhatsApp atualizado",
        serde_json::json!({
            "message_id_whatsapp": msg_id,
            "status": status_str,
        }),
        None,
        None,
        Some(envelope.event_id.to_string()),
    );

    if let Some(ref bus_conn) = state.bus_conn {
        let channel = format!("tenant:{}:events", envelope.tenant_id);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.status_atualizado",
            "tenant_id": envelope.tenant_id.to_string(),
            "payload": {
                "message_id_whatsapp": msg_id,
                "status": status_str,
            }
        });

        let mut conn = bus_conn.clone();
        let payload_str = event_payload.to_string();
        let publish_res: Result<u32, _> = redis::cmd("PUBLISH")
            .arg(&channel)
            .arg(&payload_str)
            .query_async(&mut conn)
            .await;

        if let Err(e) = publish_res {
            tracing::error!("Erro ao publicar status no Redis Pub/Sub: {:?}", e);
        }
    }

    Ok(())
}

/// Consome "message.persisted" (drenado do outbox pelo `OutboxRelay` do data_postgres)
/// e fecha o elo outbox->outbound do atendente (WS-6.3 / N1.3): quando `sender_id`
/// é "atendente", resolve instância/telefone do contato e envia via
/// `data_whatsapp::SendWhatsappMessage`, com retry/backoff e atualização de
/// `status_envio`. Mensagens do contato/bot (`sender_id` != "atendente") também
/// passam pelo outbox mas já foram entregues antes de chegar aqui — no-op.
async fn processar_mensagem_persistida(
    state: &AppState,
    evt: transport::bus::EventoBruto,
) -> anyhow::Result<()> {
    let envelope = evt.desserializar::<serde_json::Value>()?;

    let sender_id = envelope
        .payload
        .get("sender_id")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    if sender_id != REMETENTE_ATENDENTE {
        return Ok(());
    }

    let mensagem_id: i32 = envelope
        .payload
        .get("message_id")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| {
            anyhow::anyhow!("message_id ausente/inválido no evento message.persisted")
        })?;

    let tenant_id = envelope.tenant_id.to_string();
    let causation_id = envelope.event_id.to_string();

    let destino = chamar_rpc(
        &state.pg_client,
        &tenant_id,
        "ResolverDestinoEnvioOutbound",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        &causation_id,
        &envelope.traceparent,
    )
    .await?;

    let status_envio = destino
        .get("status_envio")
        .and_then(|v| v.as_str())
        .unwrap_or_default();
    if status_envio != "pending" {
        // Reentrega do consumer group (at-least-once) de um evento já processado
        // (sent/failed): no-op idempotente — status_envio é a fonte de verdade.
        tracing::debug!(
            mensagem_id = mensagem_id,
            status_envio = status_envio,
            "mensagem outbound já processada, ignorando reentrega"
        );
        return Ok(());
    }

    let instance_id = destino
        .get("instance_id")
        .and_then(|v| v.as_i64())
        .ok_or_else(|| anyhow::anyhow!("instance_id ausente na resolução de destino"))?;
    let to_number = destino
        .get("to_number")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("to_number ausente na resolução de destino"))?
        .to_string();
    let conteudo = destino
        .get("conteudo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();

    let send_payload = serde_json::json!({
        "id": instance_id,
        "to_number": to_number,
        "text": conteudo,
    });

    // Retry com backoff (1s/2s/4s) para falhas transitórias do provedor.
    let backoffs_secs = [0u64, 1, 2, 4];
    let mut ultimo_erro: Option<anyhow::Error> = None;
    let mut stanza_id: Option<String> = None;
    for espera_secs in backoffs_secs {
        if espera_secs > 0 {
            tokio::time::sleep(Duration::from_secs(espera_secs)).await;
        }
        match chamar_rpc(
            &state.whatsapp_client,
            &tenant_id,
            "SendWhatsappMessage",
            send_payload.clone(),
            &causation_id,
            &envelope.traceparent,
        )
        .await
        {
            Ok(resp) => {
                stanza_id = resp
                    .get("message_id")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                ultimo_erro = None;
                break;
            }
            Err(e) => ultimo_erro = Some(e),
        }
    }

    if let Some(stanza_id) = stanza_id {
        chamar_rpc(
            &state.pg_client,
            &tenant_id,
            "MarcarMensagemEnviada",
            serde_json::json!({ "mensagem_id": mensagem_id, "message_id_whatsapp": stanza_id }),
            &causation_id,
            &envelope.traceparent,
        )
        .await?;
        return Ok(());
    }

    // Falha definitiva após esgotar as tentativas.
    if let Err(e) = chamar_rpc(
        &state.pg_client,
        &tenant_id,
        "MarcarMensagemFalhaEnvio",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        &causation_id,
        &envelope.traceparent,
    )
    .await
    {
        tracing::error!(
            mensagem_id = mensagem_id,
            "falha ao marcar status_envio='failed': {:?}",
            e
        );
    }

    state.audit_logger.warn(
        envelope.tenant_id,
        "mensagem.envio_falhou",
        "Falha definitiva ao enviar mensagem outbound do atendente ao WhatsApp",
        serde_json::json!({ "mensagem_id": mensagem_id }),
        None,
        None,
        Some(causation_id),
    );

    anyhow::bail!(
        "Falha definitiva ao enviar mensagem outbound (mensagem_id={}): {:?}",
        mensagem_id,
        ultimo_erro
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use contracts::{Envelope, MessageKind};
    use std::time::Duration;
    use transport::bus::EventoBruto;
    use transport::runtime::{Endpoint, Server};
    use uuid::Uuid;

    static WORKER_TEST_MUTEX: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    fn evento_message_received(tenant_id: &str) -> EventoBruto {
        let raw_event = serde_json::json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": false,
                    "id": "MSG1234"
                },
                "pushName": "João Silva",
                "messageTimestamp": chrono::Utc::now().timestamp(),
                "message": {
                    "conversation": "Preciso de ajuda"
                }
            }
        });

        let payload = serde_json::json!({
            "instance_id": 42,
            "provider": "evolution",
            "raw_event": raw_event
        });

        EventoBruto {
            stream_id: "1234567890-0".to_string(),
            tenant_id: tenant_id.to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "whatsapp.message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-01-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sucesso() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29220";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "status": "success",
                        "contato_id": 10,
                        "atendimento_id": 42,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("PersistMessage", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "success", "message_id": 100 });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "PersistMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "Esperava sucesso, obteve: {:?}",
            resultado
        );

        pg_handle.abort();
    }

    /// N6.2: a resposta do bot precisa ir para o thread, não só para o WhatsApp —
    /// senão o atendente não vê o que o bot respondeu e o próprio bot perde a
    /// memória das suas falas (o `historico` do Responder vem do `GetThread`).
    /// Aqui a IA é deixada falhar de propósito (sem rota `ResolverConfigIa`): o
    /// fallback textual é enviado e DEVE ser persistido com `sender_id = "bot"`.
    #[tokio::test]
    async fn test_resposta_do_bot_e_persistida_no_thread() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29228";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        // Coleta os payloads de PersistMessage vistos pelo data_postgres falso.
        let persistidas: Arc<std::sync::Mutex<Vec<serde_json::Value>>> =
            Arc::new(std::sync::Mutex::new(Vec::new()));
        let persistidas_rota = persistidas.clone();

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "status": "success",
                        "contato_id": 10,
                        "atendimento_id": 42,
                        // Barreira de bot liberada e nenhum humano no atendimento.
                        "bot_pode_atender": true,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("PersistMessage", move |env| {
                let coletor = persistidas_rota.clone();
                Box::pin(async move {
                    if let Ok(p) = serde_json::from_slice::<serde_json::Value>(&env.payload) {
                        coletor.lock().unwrap().push(p);
                    }
                    let reply = serde_json::json!({ "status": "success", "message_id": 100 });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "PersistMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            // O mesmo endpoint faz o papel do data_whatsapp neste teste (o state
            // aponta os dois clientes para ele): envio outbound bem-sucedido.
            .route("SendWhatsappMessage", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "success" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "SendWhatsappMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_ok(), "obteve: {:?}", resultado);

        let vistas = persistidas.lock().unwrap().clone();
        let do_bot: Vec<_> = vistas
            .iter()
            .filter(|p| p.get("sender_id").and_then(|v| v.as_str()) == Some(REMETENTE_BOT))
            .collect();
        assert_eq!(
            do_bot.len(),
            1,
            "esperava exatamente 1 PersistMessage do bot; vistas: {vistas:?}"
        );
        assert!(
            !do_bot[0]
                .get("content")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .is_empty(),
            "a resposta persistida do bot não pode ser vazia"
        );
        // Resposta do bot já saiu pelo WhatsApp: não pode nascer pendente de envio,
        // senão o elo outbox->outbound a enviaria de novo.
        assert_eq!(
            do_bot[0].get("ja_entregue").and_then(|v| v.as_bool()),
            Some(true)
        );
        // A mensagem inbound do contato segue persistida (não foi substituída) e
        // carrega o stanzaId, que é a chave de idempotência da reentrega.
        let do_contato: Vec<_> = vistas
            .iter()
            .filter(|p| p.get("sender_id").and_then(|v| v.as_str()) != Some(REMETENTE_BOT))
            .collect();
        assert_eq!(do_contato.len(), 1);
        assert_eq!(
            do_contato[0]
                .get("message_id_whatsapp")
                .and_then(|v| v.as_str()),
            Some("MSG1234")
        );

        pg_handle.abort();
    }

    /// Evento `messages.upsert` com `fromMe: true` — o que a Evolution devolve
    /// quando o atendente escreve pelo celular/WhatsApp Web e, principalmente,
    /// quando ela ecoa a mensagem que o próprio bot acabou de enviar.
    fn evento_message_received_from_me(tenant_id: &str) -> EventoBruto {
        let raw_event = serde_json::json!({
            "data": {
                "key": {
                    "remoteJid": "5511999998888@s.whatsapp.net",
                    "fromMe": true,
                    "id": "MSGFROMME"
                },
                "pushName": "Atendimento",
                "messageTimestamp": chrono::Utc::now().timestamp(),
                "message": { "conversation": "Bom dia, em que posso ajudar?" }
            }
        });
        let payload = serde_json::json!({
            "instance_id": 42,
            "provider": "evolution",
            "raw_event": raw_event
        });
        EventoBruto {
            stream_id: "1234567890-1".to_string(),
            tenant_id: tenant_id.to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "whatsapp.message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-02-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    /// Mensagem do próprio número: grava como ATENDENTE, já entregue, e NÃO aciona
    /// o bot (regra da v1, `protocolo_comunicacao.md` §4.2). Sem isso, o eco da
    /// resposta do bot voltava como se fosse fala do cliente e o bot respondia a si
    /// mesmo — laço que se realimenta a cada volta do webhook.
    #[tokio::test]
    async fn test_mensagem_from_me_vira_atendente_e_nao_aciona_o_bot() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29229";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let persistidas: Arc<std::sync::Mutex<Vec<serde_json::Value>>> =
            Arc::new(std::sync::Mutex::new(Vec::new()));
        let persistidas_rota = persistidas.clone();
        let envios = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let envios_rota = envios.clone();

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    // Barreira de bot LIBERADA de propósito: o que impede a resposta
                    // aqui tem de ser o `fromMe`, não a configuração do tenant.
                    let reply = serde_json::json!({
                        "status": "success",
                        "contato_id": 10,
                        "atendimento_id": 42,
                        "bot_pode_atender": true,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("PersistMessage", move |env| {
                let coletor = persistidas_rota.clone();
                Box::pin(async move {
                    if let Ok(p) = serde_json::from_slice::<serde_json::Value>(&env.payload) {
                        coletor.lock().unwrap().push(p);
                    }
                    let reply = serde_json::json!({ "status": "success", "message_id": 101 });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "PersistMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("SendWhatsappMessage", move |env| {
                let contador = envios_rota.clone();
                Box::pin(async move {
                    contador.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                    let reply = serde_json::json!({ "status": "success" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "SendWhatsappMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_received_from_me(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_ok(), "obteve: {:?}", resultado);

        let vistas = persistidas.lock().unwrap().clone();
        assert_eq!(
            vistas.len(),
            1,
            "fromMe deve gerar só a própria persistência; vistas: {vistas:?}"
        );
        assert_eq!(
            vistas[0].get("sender_id").and_then(|v| v.as_str()),
            Some(REMETENTE_ATENDENTE)
        );
        assert_eq!(
            vistas[0].get("ja_entregue").and_then(|v| v.as_bool()),
            Some(true),
            "mensagem já entregue pelo celular do atendente não pode entrar na fila de envio"
        );
        assert_eq!(
            vistas[0]
                .get("message_id_whatsapp")
                .and_then(|v| v.as_str()),
            Some("MSGFROMME")
        );
        assert_eq!(
            envios.load(std::sync::atomic::Ordering::SeqCst),
            0,
            "o bot não pode responder ao eco da própria mensagem"
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_erro_rpc() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29221";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server =
            Server::new(pg_endpoint, "flatbuffers").route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move {
                    let error_env = contracts::ErrorEnvelope {
                        code: "DB_ERROR".to_string(),
                        message: "Falha ao resolver".to_string(),
                        ..Default::default()
                    };
                    Envelope {
                        kind: MessageKind::Error as i32,
                        method: "ResolveAtendimentoParaContatoReply".to_string(),
                        error: Some(error_env),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro na persistência RPC");

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_recebida_sem_data_postgres() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", "tcp://127.0.0.1:29229");

        let pg_client_res = transport::conectar_cliente("data_postgres").await;
        if pg_client_res.is_err() {
            return;
        }

        let pg_client = Arc::new(pg_client_res.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_received(&Uuid::new_v4().to_string());
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro de conexão recusada");
    }

    #[tokio::test]
    async fn test_processar_mensagem_tenant_uuid_invalido_falha_desserializacao() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29223";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let pg_endpoint = Endpoint::parse(pg_addr).unwrap();
        let pg_server = Server::new(pg_endpoint, "flatbuffers")
            .route("ResolveAtendimentoParaContato", |env| {
                Box::pin(async move { env })
            });
        let pg_handle = tokio::spawn(async move {
            pg_server.run().await.unwrap();
        });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            whatsapp_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = EventoBruto {
            stream_id: "1234-0".to_string(),
            tenant_id: "nao-e-um-uuid".to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.received".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "".to_string(),
            payload: r#"{"content":"ok","sender_id":"s"}"#.to_string(),
        };
        let resultado = processar_mensagem_recebida(&state, evt).await;
        assert!(resultado.is_err(), "Esperava erro de UUID inválido");

        pg_handle.abort();
    }

    fn evento_message_persistida(sender_id: &str, mensagem_id: i64) -> EventoBruto {
        let payload = serde_json::json!({
            "message_id": mensagem_id.to_string(),
            "sender_id": sender_id,
            "content": "mensagem de teste do atendente",
            "timestamp": chrono::Utc::now().timestamp_millis(),
        });

        EventoBruto {
            stream_id: "9999-0".to_string(),
            tenant_id: Uuid::new_v4().to_string(),
            event_id: Uuid::now_v7().to_string(),
            event_type: "message.persisted".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            traceparent: "00-trace-worker-n13-01".to_string(),
            payload: serde_json::to_string(&payload).unwrap(),
        }
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_sender_contato_noop() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        // Servidor sem nenhuma rota registrada: se o código tentasse qualquer RPC
        // aqui, receberia um erro do servidor (método desconhecido) e o teste falharia.
        let pg_addr = "tcp://127.0.0.1:29390";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", pg_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers");
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            pg_client,
            whatsapp_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_persistida("contato", 1);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "mensagem de contato/bot deve ser no-op: {:?}",
            resultado
        );

        pg_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_sucesso_envia() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29392";
        let wa_addr = "tcp://127.0.0.1:29393";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers")
            .route("ResolverDestinoEnvioOutbound", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "atendimento_id": 42,
                        "instance_id": 7,
                        "to_number": "5511999998888",
                        "status_envio": "pending",
                        "conteudo": "mensagem de teste do atendente",
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolverDestinoEnvioOutboundReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("MarcarMensagemEnviada", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "status": "ok" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "MarcarMensagemEnviadaReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            });
        let wa_server = Server::new(Endpoint::parse(wa_addr).unwrap(), "flatbuffers").route(
            "SendWhatsappMessage",
            |env| {
                Box::pin(async move {
                    let reply =
                        serde_json::json!({ "status": "success", "message_id": "WA-STANZA-1" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "SendWhatsappMessageReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        let wa_handle = tokio::spawn(async move { wa_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            pg_client,
            whatsapp_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_persistida("atendente", 100);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "Esperava sucesso, obteve: {:?}",
            resultado
        );

        pg_handle.abort();
        wa_handle.abort();
    }

    #[tokio::test]
    async fn test_processar_mensagem_persistida_idempotente_ja_enviada() {
        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29394";
        // whatsapp aponta para o mesmo servidor mock (sem rota SendWhatsappMessage):
        // se o código tentasse enviar de novo, receberia erro de método desconhecido —
        // confirma que o caminho idempotente não chama SendWhatsappMessage.
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", pg_addr);

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers").route(
            "ResolverDestinoEnvioOutbound",
            |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "atendimento_id": 42,
                        "instance_id": 7,
                        "to_number": "5511999998888",
                        "status_envio": "sent",
                        "conteudo": "já enviada antes",
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        method: "ResolverDestinoEnvioOutboundReply".to_string(),
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            storage_client: pg_client.clone(),
            fluxos_cache: FluxosCache::novo(),
            pg_client,
            whatsapp_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
        };

        let evt = evento_message_persistida("atendente", 101);
        let resultado = processar_mensagem_persistida(&state, evt).await;
        assert!(
            resultado.is_ok(),
            "reentrega de mensagem já enviada deve ser idempotente (no-op): {:?}",
            resultado
        );

        pg_handle.abort();
    }

    #[test]
    fn rotulo_media_type_mapeia_variantes() {
        assert_eq!(
            rotulo_media_type(&domain_whatsapp::MediaType::Image),
            "image"
        );
        assert_eq!(
            rotulo_media_type(&domain_whatsapp::MediaType::Audio),
            "audio"
        );
        assert_eq!(
            rotulo_media_type(&domain_whatsapp::MediaType::Video),
            "video"
        );
        assert_eq!(
            rotulo_media_type(&domain_whatsapp::MediaType::Document),
            "document"
        );
        assert_eq!(
            rotulo_media_type(&domain_whatsapp::MediaType::Text),
            "other"
        );
    }

    #[test]
    fn trace_id_de_extrai_o_segundo_campo_do_traceparent() {
        assert_eq!(
            trace_id_de("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"),
            "4bf92f3577b34da6a3ce929d0e0e4736"
        );
        // Formato fora do padrão: devolve o próprio valor.
        assert_eq!(trace_id_de("semtracos"), "semtracos");
    }

    /// HAPPY PATH do pipeline de mídia (áudio): download -> storage -> transcrição
    /// -> anexa análise. Cobre a orquestração ponta-a-ponta com servidores mock dos
    /// três serviços de dados + `MockIaEngineClient` para o ia_engine.
    #[tokio::test]
    async fn test_pipeline_midia_audio_transcreve_e_anexa() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29420";
        let wa_addr = "tcp://127.0.0.1:29421";
        let st_addr = "tcp://127.0.0.1:29422";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);
        std::env::set_var("SMARTCORE_DATA_STORAGE_ENDPOINT", st_addr);

        let anexou = Arc::new(AtomicBool::new(false));
        let anexou_c = anexou.clone();

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers")
            .route("ResolverConfigIa", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "llm_provider": "openai",
                        "llm_model": "gpt-4o-mini",
                        "api_key": "chave-teste",
                        // Kill-switch de transcrição LIGADO para este tenant (N6.4).
                        "transcription_enabled": true,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("AnexarAnaliseMidia", move |env| {
                let anexou = anexou_c.clone();
                Box::pin(async move {
                    anexou.store(true, Ordering::SeqCst);
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "status": "ok" }))
                            .unwrap(),
                        ..env
                    }
                })
            });
        let wa_server = Server::new(Endpoint::parse(wa_addr).unwrap(), "flatbuffers").route(
            "DownloadWhatsappMedia",
            |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "base64": "QUJD",
                        "mime_type": "audio/ogg",
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let st_server = Server::new(Endpoint::parse(st_addr).unwrap(), "flatbuffers")
            .route("PutFile", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "uri": "r2://k" }))
                            .unwrap(),
                        ..env
                    }
                })
            })
            .route("PresignFile", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(
                            &serde_json::json!({ "url": "https://r2/presigned" }),
                        )
                        .unwrap(),
                        ..env
                    }
                })
            });

        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        let wa_handle = tokio::spawn(async move { wa_server.run().await.unwrap() });
        let st_handle = tokio::spawn(async move { st_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let mut mock_ia = ia_engine::MockIaEngineClient::new();
        mock_ia.expect_transcribe().times(1).returning(|_, _| {
            Ok(ia_engine::client::TranscribeOutput {
                transcricao: "olá mundo".to_string(),
                resumo: "saudação".to_string(),
            })
        });

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let storage_client = Arc::new(transport::conectar_cliente("data_storage").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            pg_client,
            whatsapp_client,
            storage_client,
            ia_client: Arc::new(mock_ia),
            fluxos_cache: FluxosCache::novo(),
        };

        let tenant = Uuid::new_v4();
        let raw_event = serde_json::json!({
            "data": {
                "key": { "remoteJid": "5511999998888@s.whatsapp.net", "id": "MSGA" },
                "message": { "audioMessage": { "url": "http://x/a.ogg", "mimetype": "audio/ogg" } }
            }
        });

        processar_pipeline_midia(
            &state,
            tenant,
            &tenant.to_string(),
            42,
            99,
            7,
            domain_whatsapp::MediaType::Audio,
            Some("audio/ogg".to_string()),
            serde_json::json!({ "url": "http://x/a.ogg" }),
            &raw_event,
            "causation-1",
            "00-trace-pipe-01-01",
        )
        .await;

        assert!(
            anexou.load(Ordering::SeqCst),
            "AnexarAnaliseMidia deveria ter sido chamado ao fim do pipeline"
        );

        pg_handle.abort();
        wa_handle.abort();
        st_handle.abort();
    }

    /// N6.4 (passo 4) — kill-switch de transcrição POR TENANT: com a flag desligada,
    /// o áudio ainda vai para o R2 e o ponteiro é persistido (o atendente continua
    /// podendo ouvir), mas nem a IA nem o presign que a alimenta são acionados —
    /// nada de custo por minuto transcrito num tenant que não pediu a feature.
    #[tokio::test]
    async fn test_pipeline_midia_audio_sem_transcricao_persiste_so_o_ponteiro() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29430";
        let wa_addr = "tcp://127.0.0.1:29431";
        let st_addr = "tcp://127.0.0.1:29432";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);
        std::env::set_var("SMARTCORE_DATA_WHATSAPP_ENDPOINT", wa_addr);
        std::env::set_var("SMARTCORE_DATA_STORAGE_ENDPOINT", st_addr);

        let anexou = Arc::new(AtomicBool::new(false));
        let anexou_c = anexou.clone();
        let presignou = Arc::new(AtomicBool::new(false));
        let presignou_c = presignou.clone();

        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers")
            .route("ResolverConfigIa", |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({
                        "llm_provider": "openai",
                        "llm_model": "gpt-4o-mini",
                        "api_key": "chave-teste",
                        // Kill-switch DESLIGADO para este tenant.
                        "transcription_enabled": false,
                    });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            })
            .route("AnexarAnaliseMidia", move |env| {
                let anexou = anexou_c.clone();
                Box::pin(async move {
                    let payload: serde_json::Value =
                        serde_json::from_slice(&env.payload).unwrap_or_default();
                    // O ponteiro do arquivo é o que não pode faltar; análise vazia.
                    assert!(!payload["arquivo_midia"].as_str().unwrap_or("").is_empty());
                    assert_eq!(payload["analise"].as_str(), Some(""));
                    anexou.store(true, Ordering::SeqCst);
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "status": "ok" }))
                            .unwrap(),
                        ..env
                    }
                })
            });
        let wa_server = Server::new(Endpoint::parse(wa_addr).unwrap(), "flatbuffers").route(
            "DownloadWhatsappMedia",
            |env| {
                Box::pin(async move {
                    let reply = serde_json::json!({ "base64": "QUJD", "mime_type": "audio/ogg" });
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&reply).unwrap(),
                        ..env
                    }
                })
            },
        );
        let st_server = Server::new(Endpoint::parse(st_addr).unwrap(), "flatbuffers")
            .route("PutFile", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({ "uri": "r2://k" }))
                            .unwrap(),
                        ..env
                    }
                })
            })
            .route("PresignFile", move |env| {
                let presignou = presignou_c.clone();
                Box::pin(async move {
                    presignou.store(true, Ordering::SeqCst);
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(
                            &serde_json::json!({ "url": "https://r2/presigned" }),
                        )
                        .unwrap(),
                        ..env
                    }
                })
            });

        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        let wa_handle = tokio::spawn(async move { wa_server.run().await.unwrap() });
        let st_handle = tokio::spawn(async move { st_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        // A IA NÃO pode ser chamada: `never()` falha o teste se o kill-switch vazar.
        let mut mock_ia = ia_engine::MockIaEngineClient::new();
        mock_ia.expect_transcribe().never();

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let whatsapp_client = Arc::new(transport::conectar_cliente("data_whatsapp").await.unwrap());
        let storage_client = Arc::new(transport::conectar_cliente("data_storage").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            pg_client,
            whatsapp_client,
            storage_client,
            ia_client: Arc::new(mock_ia),
            fluxos_cache: FluxosCache::novo(),
        };

        let tenant = Uuid::new_v4();
        let raw_event = serde_json::json!({
            "data": {
                "key": { "remoteJid": "5511999998888@s.whatsapp.net", "id": "MSGB" },
                "message": { "audioMessage": { "url": "http://x/b.ogg", "mimetype": "audio/ogg" } }
            }
        });

        processar_pipeline_midia(
            &state,
            tenant,
            &tenant.to_string(),
            42,
            99,
            8,
            domain_whatsapp::MediaType::Audio,
            Some("audio/ogg".to_string()),
            serde_json::json!({ "url": "http://x/b.ogg" }),
            &raw_event,
            "causation-2",
            "00-trace-pipe-02-01",
        )
        .await;

        assert!(
            anexou.load(Ordering::SeqCst),
            "o ponteiro do áudio deve ser persistido mesmo sem transcrição"
        );
        assert!(
            !presignou.load(Ordering::SeqCst),
            "sem transcrição não há por que pré-assinar URL para a IA"
        );

        pg_handle.abort();
        wa_handle.abort();
        st_handle.abort();
    }

    #[tokio::test]
    async fn fluxos_cache_respeita_ttl() {
        let cache = FluxosCache {
            inner: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
            ttl: Duration::from_millis(50),
        };
        let tenant = Uuid::new_v4();
        assert!(cache.obter(tenant).await.is_none(), "vazio no início");

        cache
            .gravar(
                tenant,
                Arc::new(vec![FluxoItem {
                    chave: "Vendas - funil".to_string(),
                    fluxo_id: 1,
                }]),
            )
            .await;
        assert!(cache.obter(tenant).await.is_some(), "fresco após gravar");

        tokio::time::sleep(Duration::from_millis(80)).await;
        assert!(cache.obter(tenant).await.is_none(), "expira após o TTL");
    }

    /// A transferência só dispara a RPC quando a chave devolvida pela IA casa um fluxo
    /// conhecido; chave desconhecida é ignorada (sem transferência).
    #[tokio::test]
    async fn aplicar_transferencia_ia_chama_rpc_quando_chave_casa() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29430";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let transferiu = Arc::new(AtomicBool::new(false));
        let transferiu_c = transferiu.clone();
        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers").route(
            "TransferirAtendimentoParaFluxo",
            move |env| {
                let flag = transferiu_c.clone();
                Box::pin(async move {
                    flag.store(true, Ordering::SeqCst);
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(
                            &serde_json::json!({ "transferido": true, "etapa_id": 11 }),
                        )
                        .unwrap(),
                        ..env
                    }
                })
            },
        );
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            storage_client: pg_client.clone(),
            pg_client,
            ia_client: std::sync::Arc::new(ia_engine::MockIaEngineClient::new()),
            fluxos_cache: FluxosCache::novo(),
        };

        let fluxos = vec![FluxoItem {
            chave: "Vendas - funil".to_string(),
            fluxo_id: 7,
        }];

        // Chave desconhecida: não transfere.
        aplicar_transferencia_ia(
            &state,
            Uuid::new_v4(),
            42,
            &fluxos,
            "Inexistente - x",
            "c",
            "tp",
        )
        .await;
        assert!(
            !transferiu.load(Ordering::SeqCst),
            "chave desconhecida não transfere"
        );

        // Chave conhecida: dispara a RPC de transferência.
        aplicar_transferencia_ia(
            &state,
            Uuid::new_v4(),
            42,
            &fluxos,
            "Vendas - funil",
            "c",
            "tp",
        )
        .await;
        assert!(
            transferiu.load(Ordering::SeqCst),
            "chave conhecida transfere"
        );

        pg_handle.abort();
    }

    /// Sentimento avaliado com sucesso persiste nota/label via
    /// `AtualizarSentimentoAtendimento`; best-effort, nunca propaga erro.
    #[tokio::test]
    async fn avaliar_sentimento_best_effort_persiste_nota_e_label() {
        use std::sync::atomic::{AtomicBool, Ordering};

        let _guard = WORKER_TEST_MUTEX.lock().await;
        let pg_addr = "tcp://127.0.0.1:29431";
        std::env::set_var("SMARTCORE_DATA_POSTGRES_ENDPOINT", pg_addr);

        let persistiu = Arc::new(AtomicBool::new(false));
        let persistiu_c = persistiu.clone();
        let pg_server = Server::new(Endpoint::parse(pg_addr).unwrap(), "flatbuffers")
            .route("ResolverConfigIa", |env| {
                Box::pin(async move {
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({
                            "llm_provider": "openai",
                            "llm_model": "gpt-4o-mini",
                            "api_key": "sk-teste",
                        }))
                        .unwrap(),
                        ..env
                    }
                })
            })
            .route("AtualizarSentimentoAtendimento", move |env| {
                let flag = persistiu_c.clone();
                Box::pin(async move {
                    let body: serde_json::Value = serde_json::from_slice(&env.payload).unwrap();
                    assert_eq!(body["nota"].as_i64(), Some(8));
                    assert_eq!(body["label"].as_str(), Some("positivo"));
                    flag.store(true, Ordering::SeqCst);
                    Envelope {
                        kind: MessageKind::Reply as i32,
                        payload: serde_json::to_vec(&serde_json::json!({})).unwrap(),
                        ..env
                    }
                })
            });
        let pg_handle = tokio::spawn(async move { pg_server.run().await.unwrap() });
        tokio::time::sleep(Duration::from_millis(150)).await;

        let mut mock_ia = ia_engine::MockIaEngineClient::new();
        mock_ia.expect_sentimento().times(1).returning(|_, _| {
            Ok(ia_engine::client::SentimentoOutput {
                nota: 8,
                sentimento: "positivo".to_string(),
                feedback: "cliente satisfeito".to_string(),
            })
        });

        let pg_client = Arc::new(transport::conectar_cliente("data_postgres").await.unwrap());
        let state = AppState {
            redis_conn: None,
            bus_conn: None,
            audit_logger: observability::AuditLogger::new_dummy("worker"),
            whatsapp_client: pg_client.clone(),
            storage_client: pg_client.clone(),
            pg_client,
            ia_client: Arc::new(mock_ia),
            fluxos_cache: FluxosCache::novo(),
        };

        avaliar_sentimento_best_effort(
            &state,
            Uuid::new_v4(),
            "tenant-x",
            42,
            "estou muito feliz com o atendimento",
            "c",
            "tp",
        )
        .await;

        assert!(
            persistiu.load(Ordering::SeqCst),
            "deveria ter persistido a nota/label do sentimento"
        );

        pg_handle.abort();
    }
}
