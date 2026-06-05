use std::sync::Arc;

use dashmap::DashMap;
use secrecy::SecretString;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{crypto::CipherManager, errors::DbError};

/// Configuração resolvida de um tenant com todos os fallbacks (Tenant > CoreSettings) aplicados.
/// Chaves de API são protegidas por SecretString — nunca aparecem em logs.
#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub tenant_id: Uuid,
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
    // Chaves de API descriptografadas (SecretString: Debug = [REDACTED], zeroize no Drop)
    pub openai_api_key: SecretString,
    pub groq_api_key: SecretString,
    pub google_api_key: SecretString,
}

/// Cache concorrente de RuntimeConfig por tenant (DashMap thread-safe).
/// Guarda configurações resolvidas — NÃO pools de conexão (pool global único via RLS).
pub struct TenantConfigCache {
    pool: PgPool,
    cipher: Arc<CipherManager>,
    cache: DashMap<Uuid, Arc<RuntimeConfig>>,
}

impl std::fmt::Debug for TenantConfigCache {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TenantConfigCache")
            .field("cached_tenants", &self.cache.len())
            .finish()
    }
}

impl TenantConfigCache {
    pub fn new(pool: PgPool, cipher: Arc<CipherManager>) -> Self {
        Self {
            pool,
            cipher,
            cache: DashMap::new(),
        }
    }

    /// Obtém a config resolvida para o tenant.
    /// Cache hit: clona o Arc e SOLTA o guard antes de qualquer await (evita deadlock).
    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id), err)]
    pub async fn get_config(&self, tenant_id: Uuid) -> Result<Arc<RuntimeConfig>, DbError> {
        // Extrai o Arc e descarta o Ref antes do await assíncrono
        if let Some(cfg) = self.cache.get(&tenant_id).map(|r| r.clone()) {
            tracing::debug!("cache hit de RuntimeConfig");
            return Ok(cfg);
        }
        tracing::debug!("cache miss de RuntimeConfig — resolvendo do banco");
        let config = Arc::new(self.resolve_from_db(tenant_id).await?);
        self.cache.insert(tenant_id, config.clone());
        Ok(config)
    }

    /// Remove a entrada do cache local. Chamado pela crate infrastructure_redis
    /// ao receber o evento de invalidação do canal Redis Pub/Sub.
    pub fn invalidate(&self, tenant_id: &Uuid) {
        self.cache.remove(tenant_id);
        tracing::debug!(tenant_id = %tenant_id, "cache de RuntimeConfig invalidado");
    }

    /// Invalida e re-resolve todos os tenants ativos. Usado no cold-start.
    pub fn invalidate_all(&self) {
        self.cache.clear();
    }

    #[tracing::instrument(skip(self), fields(tenant_id = %tenant_id), err)]
    async fn resolve_from_db(&self, tenant_id: Uuid) -> Result<RuntimeConfig, DbError> {
        crate::tenants::config::resolve_runtime_config(&self.pool, &self.cipher, tenant_id).await
    }
}
