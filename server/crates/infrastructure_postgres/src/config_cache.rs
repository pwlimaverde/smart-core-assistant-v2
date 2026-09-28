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
    /// N8.5/E3 — pedido de avaliação enviado ao encerrar o atendimento. A v1
    /// tinha esse texto fixo no código, com o nome de uma empresa dentro.
    pub msg_pesquisa_satisfacao: String,
    /// Liga a pesquisa de satisfação para o tenant (default global `true`).
    pub pesquisa_satisfacao_ativa: bool,
    // LLM
    pub llm_class: String,
    pub model: String,
    pub llm_temperature: f64,
    // Transcrição de áudio
    pub transcription_provider: String,
    pub transcription_model: String,
    /// Kill-switch de transcrição por tenant (N6.4): quando `false`, o pipeline de
    /// mídia grava o áudio no R2 e persiste o ponteiro, mas não pede transcrição à
    /// IA. Resolvido pela cascata `tenants_tenantconfig` > CoreSetting
    /// `TRANSCRIPTION_ENABLED` (default global `false` — custo/latência por áudio).
    pub transcription_enabled: bool,
    /// B9 (N10 E1) — kill-switch da análise prévia (intenções e entidades) por
    /// tenant. Default global `true`: a v1 sempre analisava.
    pub analise_previa_habilitada: bool,
    /// B9 — tipos de entidade que a análise procura
    /// (`tenants_tenantconfig.entity_types`). Vazio = sem restrição de tipo.
    pub entity_types: Vec<String>,
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
    /// B4 — abaixo disto a resposta da IA vira transferência, mesmo com o
    /// modelo dizendo que sabe responder. `None` ou 0 = veto desligado, que é
    /// o padrão: ligar sem histórico é calibrar no escuro.
    pub confianca_minima_transferencia: Option<f64>,
    /// B4 — a partir disto a IA responde sem revisão, e é também o piso para um
    /// valor extraído entrar na ficha (C1). Padrão 0.8.
    pub confianca_minima_automatica: f64,
    // Chaves de API descriptografadas (SecretString: Debug = [REDACTED], zeroize no Drop)
    pub openai_api_key: SecretString,
    pub groq_api_key: SecretString,
    pub google_api_key: SecretString,
    /// Overrides de prompt de sistema resolvidos pela mesma cascata
    /// (`tenants_tenantconfig.prompts` > CoreSetting `PROMPT_*`).
    ///
    /// Contém APENAS as chaves com override de verdade — valor vazio é omitido.
    /// Chave ausente significa "use o default", que vive versionado no código do
    /// `ia_engine`: assim uma chave não semeada nunca deixa a IA sem prompt.
    pub prompts: std::collections::HashMap<String, String>,

    // --- Motor Jev (plano ia-engine-jev) ---------------------------------
    /// Chave da PLATAFORMA na TypeSafe (CoreSetting `TYPESAFE_API_KEY`, na
    /// configuração geral). Sem override por tenant: uma conta para todos.
    pub typesafe_api_key: SecretString,
    /// Versão fixa do Jev (tenant > CoreSetting `JEV_MODELO`).
    pub jev_modelo: String,
    /// llm | sombra | jev (tenant > CoreSetting `MOTOR_ANALISE`). Lido pelo
    /// worker, que escolhe o motor de cada mensagem.
    pub motor_analise: String,
    /// Tipo de entidade → descrição (`entity_types` do tenant). O motor Jev
    /// usa a descrição na pergunta de presença; o atual só lia os nomes.
    pub entity_descricoes: std::collections::HashMap<String, String>,
    /// Pisos calibrados na avaliação e estratégia por tipo de entidade.
    pub jev_config: serde_json::Value,
    /// Sinais automáticos da transferência (liga/desliga e sensibilidade).
    pub transferencia_sinais: serde_json::Value,
    pub transferencia_fluxo_padrao_id: Option<i32>,
    /// Regras ATIVAS do cadastro "Transferência para atendente", já no
    /// formato que o `ia_engine_jev` lê.
    pub regras_transferencia: Vec<serde_json::Value>,
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Plano ia-engine-jev (J0.1, c): a chave da plataforma na TypeSafe nunca
    /// aparece no `Debug` da config — um `?cfg` num log não pode vazá-la.
    #[test]
    fn debug_da_config_nao_mostra_a_chave_typesafe() {
        let chave = "ts-chave-sentinela-da-plataforma";
        let cfg = RuntimeConfig {
            tenant_id: Uuid::nil(),
            dados_empresa: String::new(),
            persona_bot: String::new(),
            bot_agent_name: String::new(),
            msg_fallback: String::new(),
            msg_sem_info: String::new(),
            msg_transferencia: String::new(),
            msg_pesquisa_satisfacao: String::new(),
            pesquisa_satisfacao_ativa: false,
            llm_class: String::new(),
            model: String::new(),
            llm_temperature: 0.0,
            transcription_provider: String::new(),
            transcription_model: String::new(),
            transcription_enabled: false,
            analise_previa_habilitada: false,
            entity_types: Vec::new(),
            vision_provider: String::new(),
            vision_model: String::new(),
            embeddings_class: String::new(),
            embeddings_model: String::new(),
            chunk_size: 0,
            chunk_overlap: 0,
            similarity_threshold: 0.0,
            vector_distance_threshold: 0.0,
            confianca_minima_transferencia: None,
            confianca_minima_automatica: 0.8,
            openai_api_key: SecretString::from(String::new()),
            groq_api_key: SecretString::from(String::new()),
            google_api_key: SecretString::from(String::new()),
            prompts: std::collections::HashMap::new(),
            typesafe_api_key: SecretString::from(chave.to_string()),
            jev_modelo: "jev-1.13.0".to_string(),
            motor_analise: "llm".to_string(),
            entity_descricoes: std::collections::HashMap::new(),
            jev_config: serde_json::json!({}),
            transferencia_sinais: serde_json::json!({}),
            transferencia_fluxo_padrao_id: None,
            regras_transferencia: Vec::new(),
        };
        let depurado = format!("{cfg:?}");
        assert!(depurado.contains("typesafe_api_key"));
        assert!(!depurado.contains(chave));
    }
}
