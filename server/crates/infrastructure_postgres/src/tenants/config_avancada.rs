//! Configuração avançada do tenant: o que existia no banco sem nenhuma tela
//! nem RPC para escrever — prompts por tenant, tipos de entidade, marca, fuso,
//! idioma, pesquisa de satisfação, inatividade, análise prévia e transcrição.
//!
//! Atualização PARCIAL de verdade: campo ausente não é tocado. É o contrário do
//! `UpdateTenantConfig`, que grava todos os campos a cada chamada (o painel
//! sempre manda a configuração inteira). Um agente que só quer trocar um prompt
//! não pode, por tabela, apagar as mensagens padrão do negócio.

use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

/// Pedido de atualização. `None` = não mexer.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct ConfigAvancada {
    pub entity_types: Option<serde_json::Value>,
    /// `(chave, texto)`. Texto vazio remove o override (volta ao global).
    pub prompts: Vec<(String, String)>,
    pub brand_name: Option<String>,
    pub primary_color: Option<String>,
    pub secondary_color: Option<String>,
    pub timezone: Option<String>,
    pub language_code: Option<String>,
    pub analise_previa_habilitada: Option<bool>,
    pub pesquisa_satisfacao_ativa: Option<bool>,
    pub msg_pesquisa_satisfacao: Option<String>,
    /// `Some(0)` ou negativo = volta a herdar o global (grava NULL).
    pub minutos_inatividade_encerra: Option<i32>,
    pub transcription_enabled: Option<bool>,
}

/// Normaliza os tipos de entidade para o formato que a análise consome.
///
/// Aceita lista de nomes ou objeto `{tipo: descrição}`. O backup da v1 vem
/// embrulhado em `{"entity_types": {...}}`; sem desembrulhar, o único "tipo"
/// seria a própria palavra `entity_types`.
pub fn normalizar_tipos_de_entidade(valor: serde_json::Value) -> Result<serde_json::Value, String> {
    // JSON codificado duas vezes: o cliente mandou a string de um JSON dentro
    // de outra string. Desembrulha em vez de recusar.
    let valor = match valor {
        serde_json::Value::String(texto) => serde_json::from_str(&texto)
            .map_err(|e| format!("tipos de entidade: JSON inválido ({e})"))?,
        outro => outro,
    };
    let valor = match valor {
        serde_json::Value::Object(mut mapa)
            if mapa.len() == 1 && mapa.contains_key("entity_types") =>
        {
            mapa.remove("entity_types").unwrap_or_default()
        }
        outro => outro,
    };
    // Categorias da v1 (`{"categoria": {"tipo": "descrição"}}`): a análise lê
    // os TIPOS, e sem achatar veria só os nomes das categorias.
    let valor = match valor {
        serde_json::Value::Object(mapa)
            if !mapa.is_empty() && mapa.values().all(|v| v.is_object()) =>
        {
            let mut plano = serde_json::Map::new();
            for (categoria, itens) in mapa {
                if let serde_json::Value::Object(itens) = itens {
                    for (tipo, desc) in itens {
                        let desc = desc.as_str().unwrap_or_default();
                        plano.insert(
                            tipo,
                            serde_json::Value::String(format!("{desc} [{categoria}]")),
                        );
                    }
                }
            }
            serde_json::Value::Object(plano)
        }
        outro => outro,
    };
    match valor {
        serde_json::Value::Array(_) | serde_json::Value::Object(_) => Ok(valor),
        _ => Err("tipos de entidade: use uma lista de nomes ou um objeto {tipo: descrição}".into()),
    }
}

/// Aplica os pedidos de prompt sobre os overrides atuais do tenant.
///
/// Chave vira maiúscula (a v1 usava minúscula, e o `resolver_prompts` já as
/// trata como iguais) e precisa ser `PROMPT_*`: qualquer outra coisa não tem
/// consumidor, e aceitar seria fingir que o texto vai valer.
pub fn mesclar_prompts(
    atuais: &serde_json::Value,
    pedidos: &[(String, String)],
) -> Result<serde_json::Value, String> {
    let mut mapa: serde_json::Map<String, serde_json::Value> = atuais
        .as_object()
        .map(|o| {
            o.iter()
                .map(|(k, v)| (k.to_uppercase(), v.clone()))
                .collect()
        })
        .unwrap_or_default();
    for (chave, texto) in pedidos {
        let chave = chave.trim().to_uppercase();
        let valida = chave.len() > 7
            && chave.starts_with("PROMPT_")
            && chave.chars().all(|c| c.is_ascii_uppercase() || c == '_');
        if !valida {
            return Err(format!(
                "chave de prompt inválida: '{chave}' (use PROMPT_*)"
            ));
        }
        if texto.trim().is_empty() {
            mapa.remove(&chave);
        } else {
            mapa.insert(chave, serde_json::Value::String(texto.clone()));
        }
    }
    Ok(serde_json::Value::Object(mapa))
}

/// `#RRGGBB`. A coluna é `VARCHAR(7)` e a tela usa a cor como está.
pub fn cor_valida(cor: &str) -> bool {
    cor.len() == 7 && cor.starts_with('#') && cor[1..].chars().all(|c| c.is_ascii_hexdigit())
}

/// Valida o pedido inteiro antes de abrir transação. Devolve os nomes dos
/// campos que serão alterados — é o que vai para a auditoria (nunca o valor:
/// prompt e dados da empresa são texto livre).
pub fn validar(pedido: &ConfigAvancada) -> Result<Vec<&'static str>, String> {
    let mut campos = Vec::new();
    let texto =
        |v: &Option<String>, nome: &'static str, max: usize, campos: &mut Vec<&'static str>| {
            if let Some(t) = v {
                if t.chars().count() > max {
                    return Err(format!("{nome}: no máximo {max} caracteres"));
                }
                campos.push(nome);
            }
            Ok(())
        };
    if pedido.entity_types.is_some() {
        campos.push("entity_types");
    }
    if !pedido.prompts.is_empty() {
        campos.push("prompts");
    }
    texto(&pedido.brand_name, "brand_name", 100, &mut campos)?;
    for (v, nome) in [
        (&pedido.primary_color, "primary_color"),
        (&pedido.secondary_color, "secondary_color"),
    ] {
        if let Some(c) = v {
            if !cor_valida(c) {
                return Err(format!("{nome}: use o formato #RRGGBB"));
            }
            campos.push(nome);
        }
    }
    texto(&pedido.timezone, "timezone", 50, &mut campos)?;
    texto(&pedido.language_code, "language_code", 10, &mut campos)?;
    texto(
        &pedido.msg_pesquisa_satisfacao,
        "msg_pesquisa_satisfacao",
        500,
        &mut campos,
    )?;
    for (v, nome) in [
        (
            pedido.analise_previa_habilitada,
            "analise_previa_habilitada",
        ),
        (
            pedido.pesquisa_satisfacao_ativa,
            "pesquisa_satisfacao_ativa",
        ),
        (pedido.transcription_enabled, "transcription_enabled"),
    ] {
        if v.is_some() {
            campos.push(nome);
        }
    }
    if pedido.minutos_inatividade_encerra.is_some() {
        campos.push("minutos_inatividade_encerra");
    }
    Ok(campos)
}

/// Grava os campos pedidos. A linha do tenant é criada se não existir.
#[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
pub async fn atualizar(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    pedido: &ConfigAvancada,
) -> Result<(), DbError> {
    sqlx::query("INSERT INTO tenants_tenantconfig (tenant_id) VALUES ($1) ON CONFLICT (tenant_id) DO NOTHING")
        .bind(tenant_id)
        .execute(&mut **tx)
        .await?;

    let prompts = if pedido.prompts.is_empty() {
        None
    } else {
        let atuais: serde_json::Value =
            sqlx::query_scalar("SELECT prompts FROM tenants_tenantconfig WHERE tenant_id = $1")
                .bind(tenant_id)
                .fetch_one(&mut **tx)
                .await?;
        Some(mesclar_prompts(&atuais, &pedido.prompts).map_err(DbError::ConfigError)?)
    };
    // Inatividade: presente e <= 0 volta a herdar o global (NULL).
    let (mexer_minutos, minutos) = match pedido.minutos_inatividade_encerra {
        None => (false, None),
        Some(m) if m <= 0 => (true, None),
        Some(m) => (true, Some(m)),
    };

    sqlx::query(
        r#"UPDATE tenants_tenantconfig SET
              entity_types = COALESCE($2, entity_types),
              prompts = COALESCE($3, prompts),
              brand_name = COALESCE($4, brand_name),
              primary_color = COALESCE($5, primary_color),
              secondary_color = COALESCE($6, secondary_color),
              timezone = COALESCE($7, timezone),
              language_code = COALESCE($8, language_code),
              analise_previa_habilitada = COALESCE($9, analise_previa_habilitada),
              pesquisa_satisfacao_ativa = COALESCE($10, pesquisa_satisfacao_ativa),
              msg_pesquisa_satisfacao = COALESCE($11, msg_pesquisa_satisfacao),
              minutos_inatividade_encerra = CASE WHEN $12 THEN $13 ELSE minutos_inatividade_encerra END,
              transcription_enabled = COALESCE($14, transcription_enabled),
              updated_at = NOW()
            WHERE tenant_id = $1"#,
    )
    .bind(tenant_id)
    .bind(&pedido.entity_types)
    .bind(prompts)
    .bind(&pedido.brand_name)
    .bind(&pedido.primary_color)
    .bind(&pedido.secondary_color)
    .bind(&pedido.timezone)
    .bind(&pedido.language_code)
    .bind(pedido.analise_previa_habilitada)
    .bind(pedido.pesquisa_satisfacao_ativa)
    .bind(&pedido.msg_pesquisa_satisfacao)
    .bind(mexer_minutos)
    .bind(minutos)
    .bind(pedido.transcription_enabled)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

#[cfg(test)]
mod testes {
    use super::*;

    #[test]
    fn tipos_da_v1_sao_desembrulhados() {
        let v1 = serde_json::json!({ "entity_types": { "produto_grafico": { "dimensoes": "tamanho" } } });
        let v = normalizar_tipos_de_entidade(v1).unwrap();
        // Categorias achatadas: o tipo fica, a categoria vai para a descrição.
        assert_eq!(v["dimensoes"], "tamanho [produto_grafico]");
        assert!(v.get("produto_grafico").is_none());
        assert!(normalizar_tipos_de_entidade(serde_json::json!(["cpf"])).is_ok());
        assert!(normalizar_tipos_de_entidade(serde_json::json!("cpf")).is_err());
        // Codificado duas vezes: a string de um objeto JSON.
        let duplo = serde_json::json!("{\"cidade\": \"onde mora\"}");
        assert!(normalizar_tipos_de_entidade(duplo)
            .unwrap()
            .get("cidade")
            .is_some());
    }

    #[test]
    fn prompts_mesclam_removem_e_normalizam_a_chave() {
        let atuais = serde_json::json!({ "prompt_regras_resposta": "antigo", "PROMPT_INTENT_FOOTER": "fica" });
        let r = mesclar_prompts(
            &atuais,
            &[
                ("prompt_regras_resposta".into(), "novo".into()),
                ("PROMPT_INTENT_FOOTER".into(), "  ".into()),
                ("PROMPT_TEMPLATE_USER_RAG".into(), "rag".into()),
            ],
        )
        .unwrap();
        assert_eq!(r["PROMPT_REGRAS_RESPOSTA"], "novo");
        assert!(r.get("PROMPT_INTENT_FOOTER").is_none());
        assert_eq!(r["PROMPT_TEMPLATE_USER_RAG"], "rag");
    }

    #[test]
    fn chave_de_prompt_fora_do_padrao_e_recusada() {
        let atuais = serde_json::json!({});
        assert!(mesclar_prompts(&atuais, &[("OPENAI_API_KEY".into(), "x".into())]).is_err());
        assert!(mesclar_prompts(&atuais, &[("PROMPT_".into(), "x".into())]).is_err());
        assert!(mesclar_prompts(&atuais, &[("PROMPT_X-1".into(), "x".into())]).is_err());
    }

    #[test]
    fn validar_lista_os_campos_e_barra_cor_e_tamanho() {
        let ok = ConfigAvancada {
            primary_color: Some("#315c28".into()),
            timezone: Some("America/Fortaleza".into()),
            analise_previa_habilitada: Some(true),
            ..Default::default()
        };
        assert_eq!(
            validar(&ok).unwrap(),
            vec!["primary_color", "timezone", "analise_previa_habilitada"]
        );
        let cor_ruim = ConfigAvancada {
            secondary_color: Some("verde".into()),
            ..Default::default()
        };
        assert!(validar(&cor_ruim).is_err());
        let longo = ConfigAvancada {
            brand_name: Some("x".repeat(101)),
            ..Default::default()
        };
        assert!(validar(&longo).is_err());
    }
}
