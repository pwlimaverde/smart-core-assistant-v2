//! Serviço worker: Consumidor em background que consome do barramento e orquestra processos de domínio.

use contracts::{Envelope, MessageKind};
use redis::aio::ConnectionManager;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use uuid::Uuid;

use std::sync::Arc;

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

#[allow(dead_code)]
mod ia_engine;
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
    #[allow(dead_code)]
    redis_conn: Option<ConnectionManager>,
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
    if let Some(ref redis_conn) = state.redis_conn {
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
        let mut conn = redis_conn.clone();
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
    let api_key = config_resp
        .get("api_key")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let llm = ia_engine::LlmProviderConfigInput {
        provider: config_resp
            .get("llm_provider")
            .and_then(|v| v.as_str())
            .unwrap_or("openai")
            .to_string(),
        model: config_resp
            .get("llm_model")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        api_key,
        temperature: config_resp
            .get("llm_temperature")
            .and_then(|v| v.as_f64())
            .unwrap_or(0.7),
    };
    // Embeddings tem provider/api_key próprios: LLM e embeddings podem usar
    // provedores distintos (ex.: LLM Groq + embeddings OpenAI), então a api_key do
    // embeddings vem separada do data_postgres (nunca reaproveita a do LLM).
    let embeddings_api_key = config_resp
        .get("embeddings_api_key")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let embeddings_provider = ia_engine::LlmProviderConfigInput {
        provider: config_resp
            .get("embeddings_provider")
            .and_then(|v| v.as_str())
            .unwrap_or("openai")
            .to_string(),
        model: config_resp
            .get("embeddings_model")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        api_key: embeddings_api_key,
        temperature: 0.0,
    };
    let dados_empresa = config_resp
        .get("dados_empresa")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let similarity_threshold = config_resp
        .get("similarity_threshold")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.75);
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
                embeddings_provider: embeddings_provider.clone(),
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
                let role = if remetente == "atendente" || remetente == "bot" {
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
                dados_empresa,
                dados_treinamento,
                campos_coletados,
                campos_pendentes,
                llm,
                embeddings_provider,
                similarity_threshold,
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
    tracing::info!("Iniciando serviço worker...");

    // 2. Conecta ao Redis para escutar eventos
    let redis_url =
        std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1:6379".to_string());
    let redis_client = redis::Client::open(redis_url)?;
    let redis_conn = ConnectionManager::new(redis_client.clone()).await?;
    tracing::info!("Conexão com Redis estabelecida.");

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

    let audit_logger = observability::AuditLogger::new_with_redis(redis_conn.clone(), "worker");
    let state = AppState {
        redis_conn: Some(redis_conn),
        audit_logger,
        pg_client,
        whatsapp_client,
        storage_client,
        ia_client,
        fluxos_cache: FluxosCache::novo(),
    };

    // 3. Inicia o consumidor do barramento (events:stream)
    let consumer = transport::bus::Consumer::new(
        transport::bus::STREAM_EVENTOS,
        "worker_group",
        "worker_consumer_1",
        redis_client.clone(),
    );

    tracing::info!("Consumidor do worker ativado e escutando eventos.");

    // 3b. Scheduler temporal (F4.3b): timeout de feedback + disparo de purga de mídia.
    // Roda em tokio::spawn paralelo ao loop de consumo do bus abaixo.
    scheduler::iniciar(state.clone());

    // Loop de consumo
    let state_clone = state.clone();
    if let Err(e) = consumer
        .run(move |evt| {
            let state = state_clone.clone();
            async move {
                if evt.event_type == "whatsapp.message.received"
                    || evt.event_type == "message.received"
                {
                    processar_mensagem_recebida(&state, evt).await?;
                } else if evt.event_type == "whatsapp.message.status" {
                    processar_status_mensagem(&state, evt).await?;
                } else if evt.event_type == "message.persisted" {
                    processar_mensagem_persistida(&state, evt).await?;
                }
                Ok(())
            }
        })
        .await
    {
        tracing::error!("Consumidor do worker parou com erro crítico: {:?}", e);
    }

    Ok(())
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

    // 2. Persiste a mensagem no atendimento resolvido
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
        "sender_id": msg_normalized.sender,
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

    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.recebida",
            "tenant_id": tenant_uuid.to_string(),
            "payload": {
                "atendimento_id": atendimento_id,
                "message": msg_normalized,
            }
        });

        let mut conn = redis_conn.clone();
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
    if let (Some(media_payload), Some(mensagem_id)) =
        (msg_normalized.media_payload.clone(), mensagem_id)
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

        if bot_pode_atender && atendente_humano_id.is_none() {
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
                &msg_normalized.content,
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
            // Barreira de bot impediu a resposta automática (humano ativo ou flag desligada).
            state.audit_logger.info(
                tenant_uuid,
                "bot.silenciado",
                "Assistente virtual silenciado para o atendimento",
                serde_json::json!({
                    "atendimento_id": atendimento_id,
                    "bot_pode_atender": bot_pode_atender,
                    "humano_ativo": atendente_humano_id.is_some(),
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

    // 3. URL pré-assinada para o ia_engine (Python) conseguir buscar o binário.
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

    // 4. Config de IA do tenant (mesmo provider/api_key do LLM é reusado para
    // transcrição/visão neste ciclo — simplificação conhecida; providers dedicados
    // de transcrição/visão ficam para uma continuação).
    let provider = match resolver_provider_ia(state, tenant_str, causation_id, traceparent).await {
        Ok(p) => p,
        Err(e) => {
            span.record("error_code", "config_falhou");
            tracing::warn!(erro = %e, "falha ao resolver config de IA; análise ausente");
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
                        transcription_provider: provider,
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
                        vision_provider: provider,
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
        span.record("error_code", "persist_falhou");
        tracing::warn!(erro = %e, "falha ao anexar análise de mídia à mensagem");
        return;
    }

    // Auditoria: mídia analisada (nível INFO). SEM conteúdo/transcrição — só
    // metadados operacionais. O download em si não gera evento (o span já o rastreia).
    let duracao_ms = inicio.elapsed().as_millis() as i64;
    state.audit_logger.info(
        tenant_uuid,
        "midia.analisada",
        "Mídia recebida analisada e anexada à mensagem",
        serde_json::json!({
            "mensagem_id": mensagem_id,
            "tipo": tipo_str,
            "duracao_ms": duracao_ms,
        }),
        None,
        None,
        Some(causation_id.to_string()),
    );
}

/// Resolve a config de provider de IA do tenant (via `ResolverConfigIa` no
/// data_postgres) e monta o `LlmProviderConfigInput` reusado para transcrição/visão.
async fn resolver_provider_ia(
    state: &AppState,
    tenant_str: &str,
    causation_id: &str,
    traceparent: &str,
) -> anyhow::Result<ia_engine::LlmProviderConfigInput> {
    let cfg = chamar_rpc(
        &state.pg_client,
        tenant_str,
        "ResolverConfigIa",
        serde_json::json!({}),
        causation_id,
        traceparent,
    )
    .await?;
    Ok(ia_engine::LlmProviderConfigInput {
        provider: cfg
            .get("llm_provider")
            .and_then(|v| v.as_str())
            .unwrap_or("openai")
            .to_string(),
        model: cfg
            .get("llm_model")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        api_key: cfg
            .get("api_key")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        temperature: 0.0,
    })
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
    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", tenant_uuid);
        let event_payload = serde_json::json!({
            "event_type": "kanban.movido",
            "tenant_id": tenant_uuid.to_string(),
            "payload": contexto,
        });
        let mut conn = redis_conn.clone();
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

    if let Some(ref redis_conn) = state.redis_conn {
        let channel = format!("tenant:{}:events", envelope.tenant_id);
        let event_payload = serde_json::json!({
            "event_type": "mensagem.status_atualizado",
            "tenant_id": envelope.tenant_id.to_string(),
            "payload": {
                "message_id_whatsapp": msg_id,
                "status": status_str,
            }
        });

        let mut conn = redis_conn.clone();
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
    if sender_id != "atendente" {
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
}
