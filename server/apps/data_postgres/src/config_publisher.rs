//! Publicação do `RuntimeConfig` consolidado no Redis, para consumo do `ia_engine`.
//!
//! Contrato definido em `doc_dev/modelagem_dados/gerenciamento_configuracoes_ia.md`
//! (seção 3.1): o Rust é o único que lê o Postgres e resolve a cascata
//! `TenantConfig > CoreSettings`; o resultado vai para `tenant:config:<uuid>` em
//! JSON, e uma notificação em `tenant:config:invalidate` manda o Python descartar
//! a cópia em RAM. Assim o payload gRPC por mensagem de WhatsApp carrega só o
//! `tenant_id` — nem chave de API nem prompt trafegam a cada interação.

use std::collections::HashMap;

use infrastructure_postgres::RuntimeConfig;
use redis::aio::ConnectionManager;
use secrecy::ExposeSecret;
use serde::Serialize;
use uuid::Uuid;

/// Validade da config no Redis. O valor é reescrito a cada mudança pelo gancho de
/// invalidação, então o TTL é só uma rede de segurança contra entrada órfã (tenant
/// removido) — não é o mecanismo de atualização.
const TTL_CONFIG_SEGUNDOS: u64 = 24 * 60 * 60;

/// Espelho serializável do `RuntimeConfig`.
///
/// Existe separado de propósito: o `RuntimeConfig` guarda as chaves em
/// `SecretString` justamente para NÃO ser serializado por acidente (`Debug` sai
/// como `[REDACTED]`). Aqui a exposição é explícita, num tipo cujo único uso é
/// esta publicação — quem ler o código vê onde o segredo sai do cofre.
///
/// Os nomes dos campos são contrato com o `RuntimeConfig` pydantic do
/// `ia_engine`; renomear qualquer um quebra o cliente Python.
#[derive(Serialize)]
pub struct RuntimeConfigDto {
    pub tenant_id: String,
    // Prompts de IA
    pub dados_empresa: String,
    pub persona_bot: String,
    pub bot_agent_name: String,
    // Mensagens automáticas
    pub msg_fallback: String,
    pub msg_sem_info: String,
    pub msg_transferencia: String,
    // LLM
    pub llm_class: String,
    pub model: String,
    pub llm_temperature: f64,
    // Transcrição de áudio
    pub transcription_provider: String,
    pub transcription_model: String,
    pub transcription_enabled: bool,
    // Visão computacional
    pub vision_provider: String,
    pub vision_model: String,
    // Embeddings e RAG
    pub embeddings_class: String,
    pub embeddings_model: String,
    pub chunk_size: i32,
    pub chunk_overlap: i32,
    // Thresholds
    pub similarity_threshold: f64,
    pub vector_distance_threshold: f64,
    // Chaves de API já decifradas (ver nota de segurança no módulo)
    pub openai_api_key: String,
    pub groq_api_key: String,
    pub google_api_key: String,
    /// Prompts de sistema resolvidos pela mesma cascata (tenant > global).
    /// Chave ausente => o `ia_engine` usa o default versionado no código dele.
    pub prompts: HashMap<String, String>,
}

impl From<&RuntimeConfig> for RuntimeConfigDto {
    fn from(cfg: &RuntimeConfig) -> Self {
        Self {
            tenant_id: cfg.tenant_id.to_string(),
            dados_empresa: cfg.dados_empresa.clone(),
            persona_bot: cfg.persona_bot.clone(),
            bot_agent_name: cfg.bot_agent_name.clone(),
            msg_fallback: cfg.msg_fallback.clone(),
            msg_sem_info: cfg.msg_sem_info.clone(),
            msg_transferencia: cfg.msg_transferencia.clone(),
            llm_class: cfg.llm_class.clone(),
            model: cfg.model.clone(),
            llm_temperature: cfg.llm_temperature,
            transcription_provider: cfg.transcription_provider.clone(),
            transcription_model: cfg.transcription_model.clone(),
            transcription_enabled: cfg.transcription_enabled,
            vision_provider: cfg.vision_provider.clone(),
            vision_model: cfg.vision_model.clone(),
            embeddings_class: cfg.embeddings_class.clone(),
            embeddings_model: cfg.embeddings_model.clone(),
            chunk_size: cfg.chunk_size,
            chunk_overlap: cfg.chunk_overlap,
            similarity_threshold: cfg.similarity_threshold,
            vector_distance_threshold: cfg.vector_distance_threshold,
            openai_api_key: cfg.openai_api_key.expose_secret().to_string(),
            groq_api_key: cfg.groq_api_key.expose_secret().to_string(),
            google_api_key: cfg.google_api_key.expose_secret().to_string(),
            prompts: cfg.prompts.clone(),
        }
    }
}

/// Grava a config do tenant no Redis e avisa o `ia_engine`.
///
/// Melhor-esforço, igual ao `publicar_invalidacao_cache`: uma falha do Redis não
/// pode derrubar a escrita de config que já foi commitada no Postgres. O
/// `ia_engine` degrada com erro explícito quando não encontra a chave, e o
/// pre-warm do próximo boot reconcilia.
pub async fn publicar_config_tenant(conn: &ConnectionManager, cfg: &RuntimeConfig) {
    let dto = RuntimeConfigDto::from(cfg);
    let json = match serde_json::to_string(&dto) {
        Ok(j) => j,
        Err(e) => {
            // Sem `{:?}` do dto: ele carrega as chaves de API decifradas.
            tracing::error!(
                tenant_id = %cfg.tenant_id,
                "Falha ao serializar RuntimeConfig para o Redis: {e}"
            );
            return;
        }
    };

    let mut conn = conn.clone();
    let chave = infrastructure_redis::chave_config_tenant(cfg.tenant_id);
    let set: Result<(), redis::RedisError> =
        redis::AsyncCommands::set_ex(&mut conn, &chave, json, TTL_CONFIG_SEGUNDOS).await;
    if let Err(e) = set {
        tracing::warn!(tenant_id = %cfg.tenant_id, "Falha ao gravar config no Redis: {e}");
        return;
    }

    // Só notifica depois de gravar: o Python descarta a cópia em RAM e relê a
    // chave — na ordem inversa ele releria o valor velho e voltaria ao estado
    // anterior até a próxima invalidação.
    let publish: Result<(), redis::RedisError> = redis::AsyncCommands::publish(
        &mut conn,
        infrastructure_redis::CANAL_CONFIG_INVALIDATE,
        cfg.tenant_id.to_string(),
    )
    .await;
    if let Err(e) = publish {
        tracing::warn!(tenant_id = %cfg.tenant_id, "Falha ao notificar invalidação de config: {e}");
    }
}

/// Resolve e publica a config de todos os tenants ativos (pre-warm do boot,
/// seção 3.4 do documento): sem isto, a primeira mensagem de cada tenant depois
/// de um deploy encontra o Redis vazio e falha até alguém salvar config no painel.
///
/// **Exige o `admin_pool`.** Listar todos os tenants é uma consulta
/// *cross-tenant*, e `tenants_tenant` tem RLS com `FORCE`: no pool de runtime
/// (`NOBYPASSRLS`, sem `app.current_tenant` definido) a política fail-closed
/// devolve ZERO linhas — sem erro. O pre-warm pareceria funcionar e nunca
/// publicaria nada. Sem `DATABASE_ADMIN_URL` configurada, avisa alto em vez de
/// reportar sucesso vazio.
pub async fn prewarm_configs(
    admin_pool: Option<&sqlx::PgPool>,
    cache: &infrastructure_postgres::TenantConfigCache,
    conn: &ConnectionManager,
) -> anyhow::Result<usize> {
    let Some(pool) = admin_pool else {
        tracing::error!(
            "Pre-warm de config ignorado: sem DATABASE_ADMIN_URL (o pool de runtime \
             não enxerga a lista de tenants por causa do RLS). A config de cada tenant \
             só será publicada quando alguém salvar algo no painel."
        );
        return Ok(0);
    };

    let ids: Vec<Uuid> = sqlx::query_scalar!("SELECT id FROM tenants_tenant WHERE active = TRUE")
        .fetch_all(pool)
        .await?;

    let mut publicados = 0usize;
    for tenant_id in ids {
        match cache.get_config(tenant_id).await {
            Ok(cfg) => {
                publicar_config_tenant(conn, &cfg).await;
                publicados += 1;
            }
            // Um tenant com config irrecuperável (ex.: chave que não decifra) não
            // pode impedir o pre-warm dos demais.
            Err(e) => tracing::warn!(
                tenant_id = %tenant_id,
                "Pre-warm ignorou tenant com config irresolvível: {e}"
            ),
        }
    }
    Ok(publicados)
}
