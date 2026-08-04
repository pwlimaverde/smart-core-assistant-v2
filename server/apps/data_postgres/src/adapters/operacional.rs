//! Adapter concreto do domínio Operacional: encapsula SQL, cifragem
//! (CipherManager), invalidação de cache (TenantConfigCache + Redis) e PING de
//! Redis. O SQL não muda em relação aos handlers originais.

use async_trait::async_trait;
use redis::aio::ConnectionManager;
use secrecy::ExposeSecret;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use uuid::Uuid;

use infrastructure_postgres::crypto::CipherManager;
use infrastructure_postgres::operacional::atendentes::{
    AtendenteRepository, PostgresAtendenteRepository,
};
use infrastructure_postgres::operacional::departamentos::{
    DepartamentoRepository, PostgresDepartamentoRepository,
};
use infrastructure_postgres::{
    connection::run_in_tenant_transaction, DbError, RequestContext, TenantConfigCache,
};

use crate::ports::operacional::{ConfigIa, CoreSetting};
use crate::ports::OperacionalStore;

/// Heurística de nome de provedor a partir do nome da classe LangChain configurada
/// pelo tenant (convenção herdada da v1). Serve tanto para o LLM
/// ("ChatOpenAI"/"ChatGroq"/"ChatGoogleGenerativeAI") quanto para embeddings
/// ("OpenAIEmbeddings"/"GoogleGenerativeAIEmbeddings"): mapeia o nome da classe para
/// o SLUG de provedor que o `ia_engine` passa a `init_chat_model`/`init_embeddings`
/// ("openai"/"groq"/"google_genai") e decide qual api_key resolvida usar. Sem
/// correspondência, cai em "openai" (provedor mais comum).
fn provider_e_api_key_de(
    class_name: &str,
    cfg: &infrastructure_postgres::RuntimeConfig,
) -> (String, String) {
    let lower = class_name.to_lowercase();
    if lower.contains("groq") {
        (
            "groq".to_string(),
            cfg.groq_api_key.expose_secret().to_string(),
        )
    } else if lower.contains("google") || lower.contains("gemini") {
        (
            "google_genai".to_string(),
            cfg.google_api_key.expose_secret().to_string(),
        )
    } else {
        (
            "openai".to_string(),
            cfg.openai_api_key.expose_secret().to_string(),
        )
    }
}

/// Implementação Postgres+Redis da port Operacional.
#[derive(Clone)]
pub struct PgOperacionalStore {
    pub pool: PgPool,
    pub cipher: Arc<CipherManager>,
    pub config_cache: Arc<TenantConfigCache>,
    /// Conexão de bus usada para publicar invalidações de cache e PING de health.
    pub conn: ConnectionManager,
    /// Conexão do Redis de CACHE (`REDIS_URL`) — instância distinta do bus.
    /// É onde o `ia_engine` procura `tenant:config:<uuid>`; publicar no bus
    /// deixaria a config íntegra e invisível para quem a consome.
    pub cache_conn: ConnectionManager,
    /// Único pool com BYPASSRLS. Necessário para LISTAR tenants ao republicar a
    /// config de todos após uma mudança global: `tenants_tenant` tem RLS com
    /// `FORCE` e, no pool de runtime, a consulta cross-tenant devolve zero
    /// linhas em silêncio.
    pub admin_pool: Option<PgPool>,
}

impl PgOperacionalStore {
    pub fn new(
        pool: PgPool,
        cipher: Arc<CipherManager>,
        config_cache: Arc<TenantConfigCache>,
        conn: ConnectionManager,
        cache_conn: ConnectionManager,
        admin_pool: Option<PgPool>,
    ) -> Self {
        Self {
            pool,
            cipher,
            config_cache,
            conn,
            cache_conn,
            admin_pool,
        }
    }

    /// Publica a invalidação do `TenantConfigCache` no canal `core:settings:invalidate`
    /// (WS-7.2), para que outras réplicas do `data_postgres` também descartem a
    /// entrada local. `tenant_id = None` sinaliza invalidação global (CoreSettings
    /// afeta todos os tenants). Melhor-esforço: publish nunca falha a operação.
    async fn publicar_invalidacao_cache(&self, tenant_id: Option<Uuid>) {
        let mut conn = self.conn.clone();
        let payload = serde_json::json!({ "tenant_id": tenant_id.map(|t| t.to_string()) });
        let payload_str = payload.to_string();
        let _: Result<(), redis::RedisError> =
            redis::AsyncCommands::publish(&mut conn, "core:settings:invalidate", payload_str).await;
    }

    /// Reresolve e republica a config no Redis para o `ia_engine`.
    ///
    /// Complementa `publicar_invalidacao_cache`, que só avisa as réplicas do
    /// próprio `data_postgres` a esvaziar o cache em memória. O `ia_engine` não
    /// fala com o Postgres (ver `gerenciamento_configuracoes_ia.md`): ele lê
    /// `tenant:config:<uuid>`, então a config precisa ser **reescrita** aqui,
    /// não só invalidada — senão a IA seguiria com o valor antigo até o TTL.
    ///
    /// `None` = mudança em CoreSettings, que alimenta TODOS os tenants; nesse
    /// caso a republicação da base inteira vai para background (ver abaixo).
    /// Chamar SEMPRE depois de `config_cache.invalidate*`, para o `get_config`
    /// reresolver do banco em vez de devolver a cópia velha que acabou de mudar.
    async fn republicar_config_ia(&self, tenant_id: Option<Uuid>) {
        match tenant_id {
            Some(id) => match self.config_cache.get_config(id).await {
                Ok(cfg) => {
                    data_postgres::config_publisher::publicar_config_tenant(&self.cache_conn, &cfg)
                        .await;
                }
                Err(e) => tracing::warn!(
                    tenant_id = %id,
                    "Config salva mas não republicada ao ia_engine: {e}"
                ),
            },
            // Uma linha de CoreSetting alterada obriga a reresolver a cascata de
            // cada tenant (uma consulta ao banco por tenant). Fazer isso dentro
            // do handler faria o `UpsertCoreSetting` do painel esperar por toda
            // a base — segurando a resposta e arriscando timeout no cliente por
            // um trabalho que já é best-effort. Vai para background.
            None => {
                let store = self.clone();
                tokio::spawn(async move {
                    match data_postgres::config_publisher::prewarm_configs(
                        store.admin_pool.as_ref(),
                        &store.config_cache,
                        &store.cache_conn,
                    )
                    .await
                    {
                        Ok(n) => tracing::info!(
                            "CoreSetting alterada: {n} config(s) republicada(s) ao ia_engine"
                        ),
                        Err(e) => {
                            tracing::warn!("Falha ao republicar configs após mudança global: {e}")
                        }
                    }
                });
            }
        }
    }
}

#[async_trait]
impl OperacionalStore for PgOperacionalStore {
    #[tracing::instrument(skip_all)]
    async fn listar_core_settings(&self) -> Result<Vec<CoreSetting>, DbError> {
        let rows = sqlx::query!(
            "SELECT key, value, encrypted, description FROM settings_manager_coresettings ORDER BY key"
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|row| {
                // Valor cifrado nunca sai do adapter em claro: já mascarado.
                let value = if row.encrypted {
                    "••••••••".to_string()
                } else {
                    row.value
                };
                CoreSetting {
                    key: row.key,
                    value,
                    encrypted: row.encrypted,
                    description: row.description,
                }
            })
            .collect())
    }

    #[tracing::instrument(skip_all)]
    async fn upsert_core_setting(
        &self,
        key: &str,
        raw_value: &str,
        encrypted: bool,
        description: &str,
    ) -> Result<(), DbError> {
        let final_value = if encrypted {
            let (ct, nonce, tag) = self
                .cipher
                .encrypt(raw_value.as_bytes())
                .map_err(|e| DbError::ConfigError(format!("erro de criptografia: {e}")))?;
            format!("{ct}:{nonce}:{tag}")
        } else {
            raw_value.to_string()
        };
        infrastructure_postgres::tenants::settings::upsert_setting(
            &self.pool,
            key,
            &final_value,
            encrypted,
            description,
        )
        .await?;

        // CoreSettings alimentam o RuntimeConfig de todos os tenants: invalida tudo.
        self.config_cache.invalidate_all();
        self.publicar_invalidacao_cache(None).await;
        self.republicar_config_ia(None).await;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn deletar_core_setting(&self, key: &str) -> Result<bool, DbError> {
        let res = sqlx::query!(
            "DELETE FROM settings_manager_coresettings WHERE key = $1",
            key
        )
        .execute(&self.pool)
        .await?;
        let deletado = res.rows_affected() > 0;
        if deletado {
            self.config_cache.invalidate_all();
            self.publicar_invalidacao_cache(None).await;
            self.republicar_config_ia(None).await;
        }
        Ok(deletado)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn obter_tenant_config(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<serde_json::Value>, DbError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        // Query runtime (sem macro): independe do cache .sqlx, mantendo o caminho
        // rápido sem banco. A cobertura real fica nos testes de integração.
        let tc_row = sqlx::query(
            "SELECT dados_empresa, persona_bot, bot_agent_name, msg_fallback, msg_sem_info, \
             msg_transferencia, llm_class, model, llm_temperature, transcription_provider, \
             transcription_model, vision_provider, vision_model, embeddings_class, \
             embeddings_model, chunk_size, chunk_overlap, similarity_threshold, \
             vector_distance_threshold, api_keys \
             FROM tenants_tenantconfig WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .fetch_optional(&mut *tx)
        .await?;
        let _ = tx.commit().await;

        let Some(row) = tc_row else {
            return Ok(None);
        };

        let api_keys: serde_json::Value = row.get("api_keys");
        let mut api_keys_masked = serde_json::Map::new();
        for key_name in &["openai_api_key", "groq_api_key", "google_api_key"] {
            let val = self
                .cipher
                .decrypt_from_jsonb(&api_keys, key_name)
                .unwrap_or_default();
            let masked = if val.is_empty() {
                ""
            } else {
                "••••••••"
            };
            api_keys_masked.insert(
                key_name.to_string(),
                serde_json::Value::String(masked.to_string()),
            );
        }

        let s = |col: &str| row.get::<Option<String>, _>(col).unwrap_or_default();
        let dec = |col: &str| {
            row.get::<Option<rust_decimal::Decimal>, _>(col)
                .unwrap_or_default()
        };
        Ok(Some(serde_json::json!({
            "dados_empresa": s("dados_empresa"),
            "persona_bot": s("persona_bot"),
            "bot_agent_name": s("bot_agent_name"),
            "msg_fallback": s("msg_fallback"),
            "msg_sem_info": s("msg_sem_info"),
            "msg_transferencia": s("msg_transferencia"),
            "llm_class": s("llm_class"),
            "model": s("model"),
            "llm_temperature": dec("llm_temperature"),
            "transcription_provider": s("transcription_provider"),
            "transcription_model": s("transcription_model"),
            "vision_provider": s("vision_provider"),
            "vision_model": s("vision_model"),
            "embeddings_class": s("embeddings_class"),
            "embeddings_model": s("embeddings_model"),
            "chunk_size": row.get::<Option<i32>, _>("chunk_size").unwrap_or(0),
            "chunk_overlap": row.get::<Option<i32>, _>("chunk_overlap").unwrap_or(0),
            "similarity_threshold": dec("similarity_threshold"),
            "vector_distance_threshold": dec("vector_distance_threshold"),
            "api_keys": serde_json::Value::Object(api_keys_masked),
        })))
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn atualizar_tenant_config(
        &self,
        tenant_id: Uuid,
        payload_json: serde_json::Value,
    ) -> Result<Vec<String>, DbError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
            .bind(tenant_id.to_string())
            .execute(&mut *tx)
            .await?;

        let keys_existente = sqlx::query!(
            "SELECT api_keys FROM tenants_tenantconfig WHERE tenant_id = $1",
            tenant_id
        )
        .fetch_optional(&mut *tx)
        .await?;
        let api_keys_atual = match keys_existente {
            Some(row) => row.api_keys,
            None => serde_json::Value::Object(Default::default()),
        };

        let mut novas_keys = serde_json::Map::new();
        // Coleta apenas os NOMES das chaves de API alteradas (nunca valores).
        let mut chaves_alteradas: Vec<String> = Vec::new();
        if let Some(req_keys) = payload_json.get("api_keys").and_then(|v| v.as_object()) {
            for key_name in &["openai_api_key", "groq_api_key", "google_api_key"] {
                if let Some(val_str) = req_keys.get(*key_name).and_then(|v| v.as_str()) {
                    if val_str == "••••••••" {
                        // Máscara preserva o valor existente (sem alteração).
                        if let Some(existente) = api_keys_atual.get(*key_name) {
                            novas_keys.insert(key_name.to_string(), existente.clone());
                        }
                    } else if val_str.is_empty() {
                        // Remoção da chave conta como alteração.
                        if api_keys_atual.get(*key_name).is_some_and(|v| !v.is_null()) {
                            chaves_alteradas.push(key_name.to_string());
                        }
                        novas_keys.insert(key_name.to_string(), serde_json::Value::Null);
                    } else {
                        let (ct, nonce, tag) =
                            self.cipher.encrypt(val_str.as_bytes()).map_err(|e| {
                                DbError::ConfigError(format!("erro ao cifrar chaves: {e}"))
                            })?;
                        novas_keys.insert(
                            key_name.to_string(),
                            serde_json::json!({ "ciphertext": ct, "nonce": nonce, "tag": tag }),
                        );
                        chaves_alteradas.push(key_name.to_string());
                    }
                }
            }
        }

        let dados_empresa = payload_json.get("dados_empresa").and_then(|v| v.as_str());
        let persona_bot = payload_json.get("persona_bot").and_then(|v| v.as_str());
        let bot_agent_name = payload_json.get("bot_agent_name").and_then(|v| v.as_str());
        let msg_fallback = payload_json.get("msg_fallback").and_then(|v| v.as_str());
        let msg_sem_info = payload_json.get("msg_sem_info").and_then(|v| v.as_str());
        let msg_transferencia = payload_json
            .get("msg_transferencia")
            .and_then(|v| v.as_str());
        let llm_class = payload_json.get("llm_class").and_then(|v| v.as_str());
        let model = payload_json.get("model").and_then(|v| v.as_str());
        let llm_temperature = payload_json
            .get("llm_temperature")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());
        let transcription_provider = payload_json
            .get("transcription_provider")
            .and_then(|v| v.as_str());
        let transcription_model = payload_json
            .get("transcription_model")
            .and_then(|v| v.as_str());
        let vision_provider = payload_json.get("vision_provider").and_then(|v| v.as_str());
        let vision_model = payload_json.get("vision_model").and_then(|v| v.as_str());
        let embeddings_class = payload_json
            .get("embeddings_class")
            .and_then(|v| v.as_str());
        let embeddings_model = payload_json
            .get("embeddings_model")
            .and_then(|v| v.as_str());
        let chunk_size = payload_json
            .get("chunk_size")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let chunk_overlap = payload_json
            .get("chunk_overlap")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let similarity_threshold = payload_json
            .get("similarity_threshold")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());
        let vector_distance_threshold = payload_json
            .get("vector_distance_threshold")
            .and_then(|v| v.as_str())
            .and_then(|s| s.parse::<rust_decimal::Decimal>().ok());

        let api_keys_json = serde_json::Value::Object(novas_keys);

        // Query runtime (sem macro): independe do cache .sqlx. Mesmo SQL/UPSERT de antes.
        let query_res = sqlx::query(
            "INSERT INTO tenants_tenantconfig ( \
                tenant_id, dados_empresa, persona_bot, bot_agent_name, \
                msg_fallback, msg_sem_info, msg_transferencia, \
                llm_class, model, llm_temperature, \
                transcription_provider, transcription_model, \
                vision_provider, vision_model, \
                embeddings_class, embeddings_model, \
                chunk_size, chunk_overlap, \
                similarity_threshold, vector_distance_threshold, \
                api_keys, updated_at \
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, NOW()) \
            ON CONFLICT (tenant_id) DO UPDATE SET \
                dados_empresa = COALESCE(EXCLUDED.dados_empresa, tenants_tenantconfig.dados_empresa), \
                persona_bot = COALESCE(EXCLUDED.persona_bot, tenants_tenantconfig.persona_bot), \
                bot_agent_name = COALESCE(EXCLUDED.bot_agent_name, tenants_tenantconfig.bot_agent_name), \
                msg_fallback = COALESCE(EXCLUDED.msg_fallback, tenants_tenantconfig.msg_fallback), \
                msg_sem_info = COALESCE(EXCLUDED.msg_sem_info, tenants_tenantconfig.msg_sem_info), \
                msg_transferencia = COALESCE(EXCLUDED.msg_transferencia, tenants_tenantconfig.msg_transferencia), \
                llm_class = COALESCE(EXCLUDED.llm_class, tenants_tenantconfig.llm_class), \
                model = COALESCE(EXCLUDED.model, tenants_tenantconfig.model), \
                llm_temperature = COALESCE(EXCLUDED.llm_temperature, tenants_tenantconfig.llm_temperature), \
                transcription_provider = COALESCE(EXCLUDED.transcription_provider, tenants_tenantconfig.transcription_provider), \
                transcription_model = COALESCE(EXCLUDED.transcription_model, tenants_tenantconfig.transcription_model), \
                vision_provider = COALESCE(EXCLUDED.vision_provider, tenants_tenantconfig.vision_provider), \
                vision_model = COALESCE(EXCLUDED.vision_model, tenants_tenantconfig.vision_model), \
                embeddings_class = COALESCE(EXCLUDED.embeddings_class, tenants_tenantconfig.embeddings_class), \
                embeddings_model = COALESCE(EXCLUDED.embeddings_model, tenants_tenantconfig.embeddings_model), \
                chunk_size = COALESCE(EXCLUDED.chunk_size, tenants_tenantconfig.chunk_size), \
                chunk_overlap = COALESCE(EXCLUDED.chunk_overlap, tenants_tenantconfig.chunk_overlap), \
                similarity_threshold = COALESCE(EXCLUDED.similarity_threshold, tenants_tenantconfig.similarity_threshold), \
                vector_distance_threshold = COALESCE(EXCLUDED.vector_distance_threshold, tenants_tenantconfig.vector_distance_threshold), \
                api_keys = EXCLUDED.api_keys, \
                updated_at = NOW()",
        )
        .bind(tenant_id)
        .bind(dados_empresa)
        .bind(persona_bot)
        .bind(bot_agent_name)
        .bind(msg_fallback)
        .bind(msg_sem_info)
        .bind(msg_transferencia)
        .bind(llm_class)
        .bind(model)
        .bind(llm_temperature)
        .bind(transcription_provider)
        .bind(transcription_model)
        .bind(vision_provider)
        .bind(vision_model)
        .bind(embeddings_class)
        .bind(embeddings_model)
        .bind(chunk_size)
        .bind(chunk_overlap)
        .bind(similarity_threshold)
        .bind(vector_distance_threshold)
        .bind(api_keys_json)
        .execute(&mut *tx)
        .await;

        if let Err(err) = query_res {
            let _ = tx.rollback().await;
            return Err(err.into());
        }
        tx.commit().await?;

        self.config_cache.invalidate(&tenant_id);
        self.publicar_invalidacao_cache(Some(tenant_id)).await;
        self.republicar_config_ia(Some(tenant_id)).await;
        Ok(chaves_alteradas)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn obter_evolution_instance(
        &self,
        tenant_id: Uuid,
    ) -> Result<Option<(String, String)>, DbError> {
        let row = sqlx::query(
            "SELECT name, api_key FROM whatsapp_instance WHERE tenant_id = $1 AND active = true LIMIT 1",
        )
        .bind(tenant_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|row| {
            let name: String = row.get("name");
            let api_key: String = row.get("api_key");
            (name, api_key)
        }))
    }

    #[tracing::instrument(skip_all)]
    async fn listar_feature_flags(&self) -> Result<Vec<serde_json::Value>, DbError> {
        let flags_rows = sqlx::query(
            "SELECT key, description, enabled_globally FROM feature_flags ORDER BY key",
        )
        .fetch_all(&self.pool)
        .await?;
        let overrides_rows =
            sqlx::query("SELECT feature_key, tenant_id, enabled FROM feature_flag_overrides")
                .fetch_all(&self.pool)
                .await?;

        use std::collections::HashMap;
        let mut overrides_map: HashMap<String, Vec<serde_json::Value>> = HashMap::new();
        for row in overrides_rows {
            let f_key: String = row.get("feature_key");
            let tenant_id: Uuid = row.get("tenant_id");
            let enabled: bool = row.get("enabled");
            overrides_map
                .entry(f_key)
                .or_default()
                .push(serde_json::json!({
                    "tenant_id": tenant_id.to_string(),
                    "enabled": enabled,
                }));
        }

        Ok(flags_rows
            .into_iter()
            .map(|row| {
                let key: String = row.get("key");
                let description: String = row.get("description");
                let enabled_globally: bool = row.get("enabled_globally");
                let ovs = overrides_map.get(&key).cloned().unwrap_or_default();
                serde_json::json!({
                    "key": key,
                    "description": description,
                    "enabled_globally": enabled_globally,
                    "overrides": ovs,
                })
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(flag_key = key))]
    async fn set_feature_flag(&self, key: &str, enabled_globally: bool) -> Result<(), DbError> {
        sqlx::query("UPDATE feature_flags SET enabled_globally = $1 WHERE key = $2")
            .bind(enabled_globally)
            .bind(key)
            .execute(&self.pool)
            .await?;

        // Publica invalidação no Redis (melhor-esforço).
        let mut conn = self.conn.clone();
        let channel = format!("feature_flag:invalidate:{key}");
        let _: Result<(), redis::RedisError> =
            redis::AsyncCommands::publish(&mut conn, channel, enabled_globally.to_string()).await;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(flag_key = key, tenant_id = %tenant_id))]
    async fn set_feature_flag_override(
        &self,
        key: &str,
        tenant_id: Uuid,
        enabled: bool,
        remove: bool,
    ) -> Result<(), DbError> {
        if remove {
            sqlx::query(
                "DELETE FROM feature_flag_overrides WHERE feature_key = $1 AND tenant_id = $2",
            )
            .bind(key)
            .bind(tenant_id)
            .execute(&self.pool)
            .await?;
        } else {
            sqlx::query(
                "INSERT INTO feature_flag_overrides (feature_key, tenant_id, enabled) \
                 VALUES ($1, $2, $3) \
                 ON CONFLICT (feature_key, tenant_id) DO UPDATE SET enabled = EXCLUDED.enabled",
            )
            .bind(key)
            .bind(tenant_id)
            .bind(enabled)
            .execute(&self.pool)
            .await?;
        }

        let mut conn = self.conn.clone();
        let channel = format!("feature_flag_override:invalidate:{key}:{tenant_id}");
        let val_str = if remove {
            "deleted".to_string()
        } else {
            enabled.to_string()
        };
        let _: Result<(), redis::RedisError> =
            redis::AsyncCommands::publish(&mut conn, channel, val_str).await;
        Ok(())
    }

    #[tracing::instrument(skip_all)]
    async fn query_audit_log(
        &self,
        tenant_id: Option<Uuid>,
        event_type: Option<String>,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<serde_json::Value>, i64), DbError> {
        let mut query_str = "SELECT id, tenant_id, timestamp, level, service, trace_id, event, message, context, user_id, ip_address FROM audit_log WHERE 1=1".to_string();
        let mut count_str = "SELECT COUNT(*) FROM audit_log WHERE 1=1".to_string();

        let bind_tenant = tenant_id.is_some();
        let event_type = event_type.filter(|s| !s.is_empty());
        let bind_event = event_type.is_some();

        if bind_tenant {
            query_str.push_str(" AND tenant_id = $1");
            count_str.push_str(" AND tenant_id = $1");
        }
        let event_index = if bind_tenant { 2 } else { 1 };
        if bind_event {
            query_str.push_str(&format!(" AND event = ${event_index}"));
            count_str.push_str(&format!(" AND event = ${event_index}"));
        }

        let limit_index = if bind_tenant && bind_event {
            3
        } else if bind_tenant || bind_event {
            2
        } else {
            1
        };
        let offset_index = limit_index + 1;
        query_str.push_str(&format!(
            " ORDER BY timestamp DESC LIMIT ${limit_index} OFFSET ${offset_index}"
        ));

        let mut q = sqlx::query(sqlx::AssertSqlSafe(query_str));
        let mut c = sqlx::query(sqlx::AssertSqlSafe(count_str));
        if let Some(t) = tenant_id {
            q = q.bind(t);
            c = c.bind(t);
        }
        if let Some(ref e) = event_type {
            q = q.bind(e.clone());
            c = c.bind(e.clone());
        }
        q = q.bind(limit).bind(offset);

        let rows = q.fetch_all(&self.pool).await?;
        let count_row = c.fetch_one(&self.pool).await?;
        let total_count: i64 = count_row.get(0);

        let list = rows
            .into_iter()
            .map(|row| {
                let id: Uuid = row.get("id");
                let tenant_id: Option<Uuid> = row.get("tenant_id");
                let timestamp: chrono::DateTime<chrono::Utc> = row.get("timestamp");
                let level: String = row.get("level");
                let service: String = row.get("service");
                let trace_id: Option<String> = row.get("trace_id");
                let event: String = row.get("event");
                let message: String = row.get("message");
                let context: serde_json::Value = row.get("context");
                let user_id: Option<i32> = row.get("user_id");
                let ip_address: Option<String> = row.get("ip_address");
                serde_json::json!({
                    "id": id.to_string(),
                    "tenant_id": tenant_id.map(|u| u.to_string()).unwrap_or_default(),
                    "created_at": timestamp.timestamp_millis(),
                    "level": level,
                    "service": service,
                    "trace_id": trace_id.unwrap_or_default(),
                    "event_type": event,
                    "description": message,
                    "context": context,
                    "user_id": user_id.unwrap_or(0),
                    "ip_address": ip_address.unwrap_or_default(),
                })
            })
            .collect();
        Ok((list, total_count))
    }

    #[tracing::instrument(skip_all)]
    async fn service_health(&self) -> Vec<serde_json::Value> {
        let mut services = Vec::new();

        let start_pg = std::time::Instant::now();
        let pg_res = sqlx::query("SELECT 1").execute(&self.pool).await;
        let duration_pg = start_pg.elapsed().as_millis() as i64;
        services.push(if pg_res.is_ok() {
            serde_json::json!({ "service_name": "PostgreSQL", "status": "healthy", "message": "Conectado com sucesso", "response_time_ms": duration_pg })
        } else {
            serde_json::json!({ "service_name": "PostgreSQL", "status": "unhealthy", "message": pg_res.err().unwrap().to_string(), "response_time_ms": duration_pg })
        });

        let mut conn = self.conn.clone();
        let start_redis = std::time::Instant::now();
        let redis_res: Result<String, redis::RedisError> =
            redis::cmd("PING").query_async(&mut conn).await;
        let duration_redis = start_redis.elapsed().as_millis() as i64;
        services.push(if redis_res.is_ok() {
            serde_json::json!({ "service_name": "Redis", "status": "healthy", "message": "Conectado com sucesso", "response_time_ms": duration_redis })
        } else {
            serde_json::json!({ "service_name": "Redis", "status": "unhealthy", "message": redis_res.err().unwrap().to_string(), "response_time_ms": duration_redis })
        });

        // Os demais serviços da stack, sondados pelo PING do transport.
        //
        // Antes, esta tela reportava só Postgres e Redis — vistos de dentro do
        // data_postgres. Um painel que diz "tudo saudável" com o worker morto e o
        // data_whatsapp travado é pior do que não ter painel: ele encerra a
        // investigação no lugar errado.
        //
        // O `worker` não aparece aqui de propósito: ele não atende ninguém (só
        // consome do barramento), então não há o que sondar. Quem cuida dele é o
        // healthcheck de batimento do container, e o estado chega ao alerting
        // pelo `smartcore_service_up` do watchdog.
        for (rotulo, servico) in [
            ("data_redis", "DATA_REDIS"),
            ("data_storage", "DATA_STORAGE"),
            ("data_whatsapp", "DATA_WHATSAPP"),
            ("control_plane", "CONTROL_PLANE"),
            ("runtime_api", "RUNTIME_API"),
        ] {
            let inicio = std::time::Instant::now();
            let resultado =
                transport::sondar_servico(servico, std::time::Duration::from_secs(2)).await;
            let duracao = inicio.elapsed().as_millis() as i64;

            services.push(match resultado {
                Ok(()) => serde_json::json!({
                    "service_name": rotulo,
                    "status": "healthy",
                    "message": "Respondeu ao ping",
                    "response_time_ms": duracao,
                }),
                Err(e) => serde_json::json!({
                    "service_name": rotulo,
                    "status": "unhealthy",
                    "message": e.to_string(),
                    "response_time_ms": duracao,
                }),
            });
        }

        services
    }

    #[tracing::instrument(skip_all)]
    async fn dashboard_summary(&self) -> Result<serde_json::Value, DbError> {
        let total_tenants: i64 = sqlx::query("SELECT COUNT(*) FROM tenants_tenant")
            .fetch_one(&self.pool)
            .await?
            .get(0);
        let active_tenants: i64 =
            sqlx::query("SELECT COUNT(*) FROM tenants_tenant WHERE active = true")
                .fetch_one(&self.pool)
                .await?
                .get(0);
        let total_subscriptions: i64 =
            sqlx::query("SELECT COUNT(*) FROM tenants_subscription WHERE status = 'active'")
                .fetch_one(&self.pool)
                .await?
                .get(0);
        let mrr: rust_decimal::Decimal = sqlx::query(
            "SELECT COALESCE(SUM(p.price), 0) FROM tenants_subscription s JOIN tenants_plan p ON s.plan_id = p.id WHERE s.status = 'active'",
        )
        .fetch_one(&self.pool)
        .await?
        .get(0);

        let services = self.service_health().await;

        Ok(serde_json::json!({
            "total_tenants": total_tenants as i32,
            "active_tenants": active_tenants as i32,
            "total_subscriptions": total_subscriptions as i32,
            "monthly_recurring_revenue": mrr.to_string(),
            "health": services,
        }))
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn resolver_config_ia(&self, tenant_id: Uuid) -> Result<ConfigIa, DbError> {
        let cfg = self.config_cache.get_config(tenant_id).await?;
        let (llm_provider, api_key) = provider_e_api_key_de(&cfg.llm_class, &cfg);
        // Embeddings passa pela MESMA normalização de classe->slug do LLM: o
        // `embeddings_class` é um nome de classe LangChain (ex.: "OpenAIEmbeddings"),
        // não um slug — enviá-lo cru quebraria o `init_embeddings` do ia_engine.
        let (embeddings_provider, embeddings_api_key) =
            provider_e_api_key_de(&cfg.embeddings_class, &cfg);
        Ok(ConfigIa {
            dados_empresa: cfg.dados_empresa.clone(),
            persona_bot: cfg.persona_bot.clone(),
            llm_provider,
            llm_model: cfg.model.clone(),
            llm_temperature: cfg.llm_temperature,
            embeddings_provider,
            embeddings_model: cfg.embeddings_model.clone(),
            similarity_threshold: cfg.similarity_threshold,
            vector_distance_threshold: cfg.vector_distance_threshold,
            transcription_enabled: cfg.transcription_enabled,
            api_key,
            embeddings_api_key,
        })
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn criar_departamento(
        &self,
        ctx: &RequestContext,
        nome: String,
        descricao: Option<String>,
    ) -> Result<serde_json::Value, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let departamento = PostgresDepartamentoRepository
                .criar(&mut tx, &ctx, &nome, descricao.as_deref())
                .await?;
            let json = serde_json::to_value(&departamento).map_err(|e| {
                DbError::ConfigError(format!("falha ao serializar departamento: {e}"))
            })?;
            Ok((json, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_departamentos(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<serde_json::Value>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let itens = PostgresDepartamentoRepository
                .listar_ativos(&mut tx, &ctx)
                .await?;
            let json = itens
                .iter()
                .map(serde_json::to_value)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| {
                    DbError::ConfigError(format!("falha ao serializar departamentos: {e}"))
                })?;
            Ok((json, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_departamento(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: String,
        descricao: Option<String>,
        ativo: bool,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let ok = PostgresDepartamentoRepository
                .atualizar(&mut tx, &ctx, id, &nome, descricao.as_deref(), ativo)
                .await?;
            Ok((ok, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn desativar_departamento(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let ok = PostgresDepartamentoRepository
                .desativar(&mut tx, &ctx, id)
                .await?;
            Ok((ok, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_atendentes(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<serde_json::Value>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let itens = PostgresAtendenteRepository
                .listar_por_tenant(&mut tx, &ctx)
                .await?;
            let json = itens
                .iter()
                .map(serde_json::to_value)
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| {
                    DbError::ConfigError(format!("falha ao serializar atendentes: {e}"))
                })?;
            Ok((json, tx))
        })
        .await
    }
}
