use rust_decimal::prelude::ToPrimitive;
use secrecy::SecretString;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    config_cache::RuntimeConfig, crypto::CipherManager, errors::DbError, tenants::settings,
};

/// Linha bruta do banco para tenants_tenantconfig (todos os campos nullable).
#[derive(Debug, sqlx::FromRow)]
struct TenantConfigRow {
    dados_empresa: Option<String>,
    persona_bot: Option<String>,
    bot_agent_name: Option<String>,
    msg_fallback: Option<String>,
    msg_sem_info: Option<String>,
    msg_transferencia: Option<String>,
    llm_class: Option<String>,
    model: Option<String>,
    llm_temperature: Option<rust_decimal::Decimal>,
    transcription_provider: Option<String>,
    transcription_model: Option<String>,
    transcription_enabled: Option<bool>,
    vision_provider: Option<String>,
    vision_model: Option<String>,
    embeddings_class: Option<String>,
    embeddings_model: Option<String>,
    chunk_size: Option<i32>,
    chunk_overlap: Option<i32>,
    similarity_threshold: Option<rust_decimal::Decimal>,
    vector_distance_threshold: Option<rust_decimal::Decimal>,
    api_keys: serde_json::Value,
    prompts: serde_json::Value,
}

/// Prefixo das CoreSettings que carregam prompt de sistema. Só estas entram no
/// `RuntimeConfig.prompts` — o resto das settings globais não tem por que
/// trafegar até o `ia_engine`.
const PREFIXO_PROMPT: &str = "PROMPT_";

/// Resolve os prompts pela cascata: global (`PROMPT_*` do CoreSettings) por
/// baixo, override do tenant (`tenants_tenantconfig.prompts`) por cima.
///
/// Valor vazio dos dois lados é OMITIDO em vez de virar string vazia: as linhas
/// são semeadas vazias pela migration 0026 (o texto canônico dos prompts é o do
/// código), e mandar `""` ao `ia_engine` apagaria o prompt em vez de deixá-lo
/// cair no default.
fn resolver_prompts(
    core: &std::collections::HashMap<String, String>,
    prompts_tenant: &serde_json::Value,
) -> std::collections::HashMap<String, String> {
    let mut resolvidos: std::collections::HashMap<String, String> = core
        .iter()
        .filter(|(k, v)| k.starts_with(PREFIXO_PROMPT) && !v.trim().is_empty())
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();

    if let Some(obj) = prompts_tenant.as_object() {
        for (chave, valor) in obj {
            // Só string: um JSON com número/objeto aqui é config malformada e
            // não deve sobrescrever silenciosamente o global com lixo.
            if let Some(texto) = valor.as_str() {
                if !texto.trim().is_empty() {
                    resolvidos.insert(chave.to_uppercase(), texto.to_string());
                }
            }
        }
    }
    resolvidos
}

/// Resolve o RuntimeConfig aplicando a cascata Tenant > CoreSettings.
/// Chamado por TenantConfigCache em cache miss.
#[tracing::instrument(skip(pool, cipher), fields(tenant_id = %tenant_id), err)]
pub async fn resolve_runtime_config(
    pool: &PgPool,
    cipher: &CipherManager,
    tenant_id: Uuid,
) -> Result<RuntimeConfig, DbError> {
    // 1. Carrega todas as CoreSettings globais (tabela sem RLS — leitura direta no pool)
    let core = settings::load_all_settings(pool, cipher).await?;

    // 2. Carrega o TenantConfig sob contexto RLS do tenant.
    // tenants_tenantconfig tem RLS: sem configurar app.current_tenant, a política
    // fail-closed bloqueia a leitura (a role de runtime é NOBYPASSRLS). Por isso a
    // consulta roda numa transação que define o tenant via set_config.
    let mut tx = pool.begin().await?;
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;

    let tc = sqlx::query_as!(
        TenantConfigRow,
        r#"SELECT dados_empresa, persona_bot, bot_agent_name,
                  msg_fallback, msg_sem_info, msg_transferencia,
                  llm_class, model, llm_temperature,
                  transcription_provider, transcription_model, transcription_enabled,
                  vision_provider, vision_model,
                  embeddings_class, embeddings_model,
                  chunk_size, chunk_overlap,
                  similarity_threshold, vector_distance_threshold,
                  api_keys, prompts
           FROM tenants_tenantconfig
           WHERE tenant_id = $1"#,
        tenant_id
    )
    .fetch_optional(&mut *tx)
    .await?;

    tx.commit().await?;

    // Helper: usa campo do tenant se não nulo/vazio; senão usa o global
    let fallback = |tenant_val: Option<String>, core_key: &str| -> String {
        tenant_val
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| core.get(core_key).cloned().unwrap_or_default())
    };

    let fallback_dec = |tenant_val: Option<rust_decimal::Decimal>, core_key: &str| -> f64 {
        tenant_val.and_then(|d| d.to_f64()).unwrap_or_else(|| {
            core.get(core_key)
                .and_then(|s| s.parse::<f64>().ok())
                .unwrap_or(0.0)
        })
    };

    let fallback_i32 = |tenant_val: Option<i32>, core_key: &str| -> i32 {
        tenant_val.unwrap_or_else(|| {
            core.get(core_key)
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0)
        })
    };

    // Kill-switch booleano: NULL no tenant cai no CoreSetting; CoreSetting ausente
    // ou com valor não reconhecido = desligado (postura conservadora — a feature
    // custa dinheiro/latência por áudio recebido).
    let fallback_bool = |tenant_val: Option<bool>, core_key: &str| -> bool {
        tenant_val.unwrap_or_else(|| {
            core.get(core_key)
                .map(|s| s.eq_ignore_ascii_case("true"))
                .unwrap_or(false)
        })
    };

    // 3. Resolve chaves de API (local do tenant tem prioridade; fallback para global)
    let api_keys = tc
        .as_ref()
        .map(|r| r.api_keys.clone())
        .unwrap_or_else(|| serde_json::Value::Object(Default::default()));

    let resolve_api_key = |key_name: &str, core_key: &str| -> Result<SecretString, DbError> {
        let local = cipher.decrypt_from_jsonb(&api_keys, key_name)?;
        if !local.is_empty() {
            return Ok(SecretString::from(local));
        }
        Ok(SecretString::from(
            core.get(core_key).cloned().unwrap_or_default(),
        ))
    };

    let prompts = resolver_prompts(
        &core,
        &tc.as_ref()
            .map(|r| r.prompts.clone())
            .unwrap_or(serde_json::Value::Null),
    );

    let tc = tc.unwrap_or_else(|| TenantConfigRow {
        dados_empresa: None,
        persona_bot: None,
        bot_agent_name: None,
        msg_fallback: None,
        msg_sem_info: None,
        msg_transferencia: None,
        llm_class: None,
        model: None,
        llm_temperature: None,
        transcription_provider: None,
        transcription_model: None,
        transcription_enabled: None,
        vision_provider: None,
        vision_model: None,
        embeddings_class: None,
        embeddings_model: None,
        chunk_size: None,
        chunk_overlap: None,
        similarity_threshold: None,
        vector_distance_threshold: None,
        api_keys: serde_json::Value::Object(Default::default()),
        prompts: serde_json::Value::Object(Default::default()),
    });

    Ok(RuntimeConfig {
        tenant_id,
        dados_empresa: tc.dados_empresa.unwrap_or_default(),
        persona_bot: tc.persona_bot.unwrap_or_default(),
        bot_agent_name: tc.bot_agent_name.unwrap_or_default(),
        msg_fallback: fallback(tc.msg_fallback, "MSG_FALLBACK"),
        msg_sem_info: fallback(tc.msg_sem_info, "MSG_SEM_INFO"),
        msg_transferencia: fallback(tc.msg_transferencia, "MSG_TRANSFERENCIA"),
        llm_class: fallback(tc.llm_class, "LLM_CLASS"),
        model: fallback(tc.model, "MODEL"),
        llm_temperature: fallback_dec(tc.llm_temperature, "LLM_TEMPERATURE"),
        transcription_provider: fallback(tc.transcription_provider, "TRANSCRIPTION_PROVIDER"),
        transcription_model: fallback(tc.transcription_model, "TRANSCRIPTION_MODEL"),
        transcription_enabled: fallback_bool(tc.transcription_enabled, "TRANSCRIPTION_ENABLED"),
        vision_provider: fallback(tc.vision_provider, "VISION_PROVIDER"),
        vision_model: fallback(tc.vision_model, "VISION_MODEL"),
        embeddings_class: fallback(tc.embeddings_class, "EMBEDDINGS_CLASS"),
        embeddings_model: fallback(tc.embeddings_model, "EMBEDDINGS_MODEL"),
        chunk_size: fallback_i32(tc.chunk_size, "CHUNK_SIZE"),
        chunk_overlap: fallback_i32(tc.chunk_overlap, "CHUNK_OVERLAP"),
        similarity_threshold: fallback_dec(tc.similarity_threshold, "SIMILARITY_THRESHOLD"),
        vector_distance_threshold: fallback_dec(
            tc.vector_distance_threshold,
            "VECTOR_DISTANCE_THRESHOLD",
        ),
        openai_api_key: resolve_api_key("openai_api_key", "OPENAI_API_KEY")?,
        groq_api_key: resolve_api_key("groq_api_key", "GROQ_API_KEY")?,
        google_api_key: resolve_api_key("google_api_key", "GOOGLE_API_KEY")?,
        prompts,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn core_com(pares: &[(&str, &str)]) -> HashMap<String, String> {
        pares
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn resolves_only_prompt_prefixed_settings_ignoring_other_globals() {
        let core = core_com(&[
            ("PROMPT_REGRAS_RESPOSTA", "regras globais"),
            ("MODEL", "gemini-2.5-flash-lite"),
            ("OPENAI_API_KEY", "nao-deve-vazar-para-prompts"),
        ]);

        let prompts = resolver_prompts(&core, &serde_json::Value::Null);

        assert_eq!(prompts.len(), 1);
        assert_eq!(prompts["PROMPT_REGRAS_RESPOSTA"], "regras globais");
    }

    #[test]
    fn tenant_override_wins_over_global() {
        let core = core_com(&[("PROMPT_REGRAS_RESPOSTA", "global")]);
        let tenant = serde_json::json!({ "PROMPT_REGRAS_RESPOSTA": "do tenant" });

        let prompts = resolver_prompts(&core, &tenant);

        assert_eq!(prompts["PROMPT_REGRAS_RESPOSTA"], "do tenant");
    }

    #[test]
    fn empty_values_are_omitted_so_the_engine_falls_back_to_its_default() {
        // A migration 0026 semeia as chaves VAZIAS de proposito (o texto canonico
        // e' o do codigo). Emitir "" apagaria o prompt no ia_engine em vez de
        // deixa-lo cair no default.
        let core = core_com(&[
            ("PROMPT_REGRAS_RESPOSTA", ""),
            ("PROMPT_INTENT_SYSTEM", "   "),
        ]);
        let tenant = serde_json::json!({ "PROMPT_SENTIMENTO_SYSTEM": "" });

        let prompts = resolver_prompts(&core, &tenant);

        assert!(
            prompts.is_empty(),
            "esperado nenhum override, veio {prompts:?}"
        );
    }

    #[test]
    fn tenant_key_is_normalized_to_uppercase() {
        // O JSONB e' escrito pelo painel; aceitar so' o case exato faria um
        // override valido ser ignorado sem aviso.
        let tenant = serde_json::json!({ "prompt_regras_resposta": "minusculo" });

        let prompts = resolver_prompts(&HashMap::new(), &tenant);

        assert_eq!(prompts["PROMPT_REGRAS_RESPOSTA"], "minusculo");
    }

    #[test]
    fn non_string_tenant_values_do_not_override_the_global() {
        let core = core_com(&[("PROMPT_REGRAS_RESPOSTA", "global valido")]);
        let tenant = serde_json::json!({ "PROMPT_REGRAS_RESPOSTA": { "texto": "objeto" } });

        let prompts = resolver_prompts(&core, &tenant);

        assert_eq!(prompts["PROMPT_REGRAS_RESPOSTA"], "global valido");
    }
}
