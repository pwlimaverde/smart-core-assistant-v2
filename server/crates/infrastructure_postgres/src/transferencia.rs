//! Plano ia-engine-jev — cadastro das regras de transferência, sinais
//! automáticos, motor por tenant e o registro das decisões da IA.
//!
//! Tudo em tabela de tenant corre dentro de `run_in_tenant_transaction` (RLS);
//! as funções aqui recebem a transação já aberta. Consultas de tempo de
//! execução (`sqlx::query`), sem macros: não exigem regenerar o cache offline.

use serde::{Deserialize, Serialize};
use sqlx::{Postgres, Row, Transaction};
use uuid::Uuid;

use crate::errors::DbError;

pub const GATILHOS: [&str; 2] = ["condicao", "intencao"];
pub const MOMENTOS: [&str; 2] = ["imediato", "apos_coleta"];
pub const DESTINOS: [&str; 3] = ["fluxo", "setor_jev", "padrao"];
pub const SENSIBILIDADES: [&str; 3] = ["baixa", "media", "alta"];
pub const MOTORES: [&str; 3] = ["llm", "sombra", "jev"];
/// Sinais automáticos que o tenant liga, desliga e ajusta.
pub const SINAIS: [&str; 5] = [
    "pede_humano",
    "irritacao",
    "duvida_transfere",
    "base_sem_resposta",
    "resposta_sem_apoio",
];

/// Uma regra de transferência como a tela, o MCP e a IA a enxergam.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct RegraTransferencia {
    pub id: i64,
    pub nome: String,
    pub gatilho_tipo: String,
    pub condicao: String,
    pub intencao_tag: String,
    pub exemplos_sim: Vec<String>,
    pub exemplos_nao: Vec<String>,
    pub momento: String,
    pub campos_coleta: Vec<String>,
    pub destino_tipo: String,
    pub destino_fluxo_id: Option<i32>,
    pub mensagem: String,
    pub sensibilidade: String,
    pub ativa: bool,
    pub sugestao: bool,
    pub criado_em: i64,
    pub atualizado_em: i64,
}

/// Campos editáveis de uma regra.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DadosRegra {
    pub nome: String,
    pub gatilho_tipo: String,
    pub condicao: String,
    pub intencao_tag: String,
    pub exemplos_sim: Vec<String>,
    pub exemplos_nao: Vec<String>,
    pub momento: String,
    pub campos_coleta: Vec<String>,
    pub destino_tipo: String,
    pub destino_fluxo_id: Option<i32>,
    pub mensagem: String,
    pub sensibilidade: String,
}

fn lista(valor: Option<&serde_json::Value>) -> Vec<String> {
    valor
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default()
}

impl DadosRegra {
    /// Lê do payload JSON, com os padrões da tela onde faltar.
    pub fn do_json(p: &serde_json::Value) -> Self {
        let texto = |c: &str, padrao: &str| {
            p.get(c)
                .and_then(|v| v.as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .unwrap_or(padrao)
                .to_string()
        };
        Self {
            nome: texto("nome", ""),
            gatilho_tipo: texto("gatilho_tipo", "condicao"),
            condicao: texto("condicao", ""),
            intencao_tag: texto("intencao_tag", ""),
            exemplos_sim: lista(p.get("exemplos_sim")),
            exemplos_nao: lista(p.get("exemplos_nao")),
            momento: texto("momento", "imediato"),
            campos_coleta: lista(p.get("campos_coleta")),
            destino_tipo: texto("destino_tipo", "padrao"),
            destino_fluxo_id: p
                .get("destino_fluxo_id")
                .and_then(|v| v.as_i64())
                .filter(|v| *v > 0)
                .map(|v| v as i32),
            mensagem: texto("mensagem", ""),
            sensibilidade: texto("sensibilidade", "media"),
        }
    }

    /// Mescla sobre uma regra existente só os campos presentes no payload.
    pub fn mesclar(base: &RegraTransferencia, p: &serde_json::Value) -> Self {
        let texto = |c: &str, atual: &str| {
            p.get(c)
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_string())
                .unwrap_or_else(|| atual.to_string())
        };
        let lista_ou = |c: &str, atual: &Vec<String>| {
            if p.get(c).is_some() {
                lista(p.get(c))
            } else {
                atual.clone()
            }
        };
        Self {
            nome: texto("nome", &base.nome),
            gatilho_tipo: texto("gatilho_tipo", &base.gatilho_tipo),
            condicao: texto("condicao", &base.condicao),
            intencao_tag: texto("intencao_tag", &base.intencao_tag),
            exemplos_sim: lista_ou("exemplos_sim", &base.exemplos_sim),
            exemplos_nao: lista_ou("exemplos_nao", &base.exemplos_nao),
            momento: texto("momento", &base.momento),
            campos_coleta: lista_ou("campos_coleta", &base.campos_coleta),
            destino_tipo: texto("destino_tipo", &base.destino_tipo),
            destino_fluxo_id: match p.get("destino_fluxo_id") {
                Some(v) => v.as_i64().filter(|v| *v > 0).map(|v| v as i32),
                None => base.destino_fluxo_id,
            },
            mensagem: texto("mensagem", &base.mensagem),
            sensibilidade: texto("sensibilidade", &base.sensibilidade),
        }
    }

    /// O que falta ou está errado, em português, para a tela mostrar.
    ///
    /// O Jev lê a condição ao pé da letra: uma condição genérica ("assuntos
    /// comerciais") dispara em tudo ou em nada. Por isso o mínimo de tamanho.
    pub fn validar(&self) -> Result<(), String> {
        if self.nome.is_empty() {
            return Err("informe o nome da regra".into());
        }
        if self.nome.chars().count() > 120 {
            return Err("o nome da regra passa de 120 caracteres".into());
        }
        if !GATILHOS.contains(&self.gatilho_tipo.as_str()) {
            return Err("gatilho inválido: use condicao ou intencao".into());
        }
        if self.gatilho_tipo == "condicao" && self.condicao.chars().count() < 10 {
            return Err(
                "descreva a condição numa frase exata (ex.: \"o cliente quer fechar o pedido\")"
                    .into(),
            );
        }
        if self.gatilho_tipo == "intencao" && self.intencao_tag.is_empty() {
            return Err("escolha a intenção que dispara a regra".into());
        }
        if !MOMENTOS.contains(&self.momento.as_str()) {
            return Err("momento inválido: use imediato ou apos_coleta".into());
        }
        if self.momento == "apos_coleta" && self.campos_coleta.is_empty() {
            return Err("diga quais campos coletar antes de transferir".into());
        }
        if !DESTINOS.contains(&self.destino_tipo.as_str()) {
            return Err("destino inválido: use fluxo, setor_jev ou padrao".into());
        }
        if self.destino_tipo == "fluxo" && self.destino_fluxo_id.is_none() {
            return Err("escolha o fluxo de destino".into());
        }
        if !SENSIBILIDADES.contains(&self.sensibilidade.as_str()) {
            return Err("sensibilidade inválida: use baixa, media ou alta".into());
        }
        if self.exemplos_sim.len() > 20 || self.exemplos_nao.len() > 20 {
            return Err("no máximo 20 exemplos de cada lado".into());
        }
        Ok(())
    }
}

/// As colunas de uma regra. Macro, e não `const`: o `sqlx` só aceita SQL
/// estático (`&'static str`), e `concat!` monta a consulta em tempo de
/// compilação — um `format!` aqui abriria a porta para SQL dinâmico.
macro_rules! colunas {
    () => {
        "id, nome, gatilho_tipo, condicao, intencao_tag, exemplos_sim, exemplos_nao, \
         momento, campos_coleta, destino_tipo, destino_fluxo_id, mensagem, \
         sensibilidade, ativa, sugestao, criado_em, atualizado_em"
    };
}

fn da_linha(r: &sqlx::postgres::PgRow) -> Result<RegraTransferencia, DbError> {
    let lista_json = |c: &str| -> Result<Vec<String>, DbError> {
        let v: serde_json::Value = r.try_get(c)?;
        Ok(lista(Some(&v)))
    };
    let criado: chrono::DateTime<chrono::Utc> = r.try_get("criado_em")?;
    let atualizado: chrono::DateTime<chrono::Utc> = r.try_get("atualizado_em")?;
    Ok(RegraTransferencia {
        id: r.try_get("id")?,
        nome: r.try_get("nome")?,
        gatilho_tipo: r.try_get("gatilho_tipo")?,
        condicao: r.try_get("condicao")?,
        intencao_tag: r.try_get("intencao_tag")?,
        exemplos_sim: lista_json("exemplos_sim")?,
        exemplos_nao: lista_json("exemplos_nao")?,
        momento: r.try_get("momento")?,
        campos_coleta: lista_json("campos_coleta")?,
        destino_tipo: r.try_get("destino_tipo")?,
        destino_fluxo_id: r.try_get("destino_fluxo_id")?,
        mensagem: r.try_get("mensagem")?,
        sensibilidade: r.try_get("sensibilidade")?,
        ativa: r.try_get("ativa")?,
        sugestao: r.try_get("sugestao")?,
        criado_em: criado.timestamp_millis(),
        atualizado_em: atualizado.timestamp_millis(),
    })
}

pub async fn listar(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
) -> Result<Vec<RegraTransferencia>, DbError> {
    let linhas = sqlx::query(concat!(
        "SELECT ",
        colunas!(),
        " FROM oraculo_regra_transferencia \
         WHERE tenant_id = $1 ORDER BY ativa DESC, sugestao, nome"
    ))
    .bind(tenant_id)
    .fetch_all(&mut **tx)
    .await?;
    linhas.iter().map(da_linha).collect()
}

pub async fn obter(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    id: i64,
) -> Result<Option<RegraTransferencia>, DbError> {
    let linha = sqlx::query(concat!(
        "SELECT ",
        colunas!(),
        " FROM oraculo_regra_transferencia WHERE tenant_id = $1 AND id = $2"
    ))
    .bind(tenant_id)
    .bind(id)
    .fetch_optional(&mut **tx)
    .await?;
    linha.as_ref().map(da_linha).transpose()
}

/// Mesmo nome (sem diferenciar caixa) já cadastrado, fora a própria regra.
pub async fn existe_nome(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    nome: &str,
    exceto_id: Option<i64>,
) -> Result<bool, DbError> {
    let achou: Option<i64> = sqlx::query_scalar(
        "SELECT id FROM oraculo_regra_transferencia \
         WHERE tenant_id = $1 AND lower(nome) = lower($2) AND ($3::bigint IS NULL OR id <> $3) \
         LIMIT 1",
    )
    .bind(tenant_id)
    .bind(nome)
    .bind(exceto_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(achou.is_some())
}

pub async fn criar(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    d: &DadosRegra,
    ativa: bool,
    sugestao: bool,
) -> Result<RegraTransferencia, DbError> {
    let linha = sqlx::query(concat!(
        "INSERT INTO oraculo_regra_transferencia \
            (tenant_id, nome, gatilho_tipo, condicao, intencao_tag, exemplos_sim, exemplos_nao, \
             momento, campos_coleta, destino_tipo, destino_fluxo_id, mensagem, sensibilidade, \
             ativa, sugestao) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) \
         RETURNING ",
        colunas!()
    ))
    .bind(tenant_id)
    .bind(&d.nome)
    .bind(&d.gatilho_tipo)
    .bind(&d.condicao)
    .bind(&d.intencao_tag)
    .bind(serde_json::json!(d.exemplos_sim))
    .bind(serde_json::json!(d.exemplos_nao))
    .bind(&d.momento)
    .bind(serde_json::json!(d.campos_coleta))
    .bind(&d.destino_tipo)
    .bind(d.destino_fluxo_id)
    .bind(&d.mensagem)
    .bind(&d.sensibilidade)
    .bind(ativa)
    .bind(sugestao)
    .fetch_one(&mut **tx)
    .await?;
    da_linha(&linha)
}

pub async fn atualizar(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    id: i64,
    d: &DadosRegra,
) -> Result<Option<RegraTransferencia>, DbError> {
    let linha = sqlx::query(concat!(
        "UPDATE oraculo_regra_transferencia SET \
            nome = $3, gatilho_tipo = $4, condicao = $5, intencao_tag = $6, exemplos_sim = $7, \
            exemplos_nao = $8, momento = $9, campos_coleta = $10, destino_tipo = $11, \
            destino_fluxo_id = $12, mensagem = $13, sensibilidade = $14, \
            sugestao = FALSE, atualizado_em = NOW() \
         WHERE tenant_id = $1 AND id = $2 \
         RETURNING ",
        colunas!()
    ))
    .bind(tenant_id)
    .bind(id)
    .bind(&d.nome)
    .bind(&d.gatilho_tipo)
    .bind(&d.condicao)
    .bind(&d.intencao_tag)
    .bind(serde_json::json!(d.exemplos_sim))
    .bind(serde_json::json!(d.exemplos_nao))
    .bind(&d.momento)
    .bind(serde_json::json!(d.campos_coleta))
    .bind(&d.destino_tipo)
    .bind(d.destino_fluxo_id)
    .bind(&d.mensagem)
    .bind(&d.sensibilidade)
    .fetch_optional(&mut **tx)
    .await?;
    linha.as_ref().map(da_linha).transpose()
}

pub async fn definir_ativa(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    id: i64,
    ativa: bool,
) -> Result<Option<RegraTransferencia>, DbError> {
    let linha = sqlx::query(concat!(
        "UPDATE oraculo_regra_transferencia \
            SET ativa = $3, sugestao = CASE WHEN $3 THEN FALSE ELSE sugestao END, \
                atualizado_em = NOW() \
         WHERE tenant_id = $1 AND id = $2 RETURNING ",
        colunas!()
    ))
    .bind(tenant_id)
    .bind(id)
    .bind(ativa)
    .fetch_optional(&mut **tx)
    .await?;
    linha.as_ref().map(da_linha).transpose()
}

/// O fluxo pertence ao tenant e está ativo? (destino de regra ou padrão)
pub async fn fluxo_do_tenant(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    fluxo_id: i32,
) -> Result<bool, DbError> {
    let achou: Option<i32> = sqlx::query_scalar(
        "SELECT id FROM oraculo_fluxo_atendimento WHERE tenant_id = $1 AND id = $2",
    )
    .bind(tenant_id)
    .bind(fluxo_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(achou.is_some())
}

// ------------------------------------------------------------------ sinais
/// Config de transferência do tenant: sinais, fluxo padrão e motor.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ConfigTransferencia {
    pub sinais: serde_json::Value,
    pub fluxo_padrao_id: Option<i32>,
    pub motor_analise: Option<String>,
    pub msg_transferencia: String,
}

pub async fn obter_config(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
) -> Result<ConfigTransferencia, DbError> {
    let linha = sqlx::query(
        "SELECT transferencia_sinais, transferencia_fluxo_padrao_id, motor_analise, \
                COALESCE(msg_transferencia, '') AS msg_transferencia \
         FROM tenants_tenantconfig WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(match linha {
        Some(r) => ConfigTransferencia {
            sinais: r.try_get("transferencia_sinais")?,
            fluxo_padrao_id: r.try_get("transferencia_fluxo_padrao_id")?,
            motor_analise: r.try_get("motor_analise")?,
            msg_transferencia: r.try_get("msg_transferencia")?,
        },
        None => ConfigTransferencia {
            sinais: serde_json::json!({}),
            ..Default::default()
        },
    })
}

/// Normaliza o pedido de sinais: só nomes conhecidos, `ativo` booleano e
/// sensibilidade válida. O resto é descartado, não gravado em silêncio.
pub fn normalizar_sinais(
    atuais: &serde_json::Value,
    pedido: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    let mut mapa = atuais.as_object().cloned().unwrap_or_default();
    let Some(itens) = pedido.as_object() else {
        return Err("sinais: envie um objeto {sinal: {ativo, sensibilidade}}".into());
    };
    for (nome, valor) in itens {
        if !SINAIS.contains(&nome.as_str()) {
            return Err(format!("sinal desconhecido: {nome}"));
        }
        let mut atual = mapa
            .get(nome)
            .and_then(|v| v.as_object().cloned())
            .unwrap_or_default();
        match valor {
            serde_json::Value::Bool(b) => {
                atual.insert("ativo".into(), serde_json::Value::Bool(*b));
            }
            serde_json::Value::Object(o) => {
                if let Some(ativo) = o.get("ativo") {
                    let Some(b) = ativo.as_bool() else {
                        return Err(format!("{nome}.ativo precisa ser true ou false"));
                    };
                    atual.insert("ativo".into(), serde_json::Value::Bool(b));
                }
                if let Some(s) = o.get("sensibilidade") {
                    let s = s.as_str().unwrap_or_default();
                    if !SENSIBILIDADES.contains(&s) {
                        return Err(format!("{nome}.sensibilidade: use baixa, media ou alta"));
                    }
                    atual.insert("sensibilidade".into(), serde_json::Value::String(s.into()));
                }
            }
            _ => {
                return Err(format!(
                    "{nome}: use true/false ou {{ativo, sensibilidade}}"
                ))
            }
        }
        mapa.insert(nome.clone(), serde_json::Value::Object(atual));
    }
    Ok(serde_json::Value::Object(mapa))
}

/// Grava sinais e/ou fluxo padrão (cria a linha de config se faltar).
/// `fluxo_padrao`: `None` = não mexer; `Some(None)` = limpar.
pub async fn definir_config(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    sinais: Option<&serde_json::Value>,
    fluxo_padrao: Option<Option<i32>>,
) -> Result<(), DbError> {
    sqlx::query(
        "INSERT INTO tenants_tenantconfig (tenant_id) VALUES ($1) ON CONFLICT (tenant_id) DO NOTHING",
    )
    .bind(tenant_id)
    .execute(&mut **tx)
    .await?;
    if let Some(s) = sinais {
        sqlx::query(
            "UPDATE tenants_tenantconfig SET transferencia_sinais = $2, updated_at = NOW() \
             WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .bind(s)
        .execute(&mut **tx)
        .await?;
    }
    if let Some(f) = fluxo_padrao {
        sqlx::query(
            "UPDATE tenants_tenantconfig SET transferencia_fluxo_padrao_id = $2, updated_at = NOW() \
             WHERE tenant_id = $1",
        )
        .bind(tenant_id)
        .bind(f)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

/// Motor do tenant (`None` = herda o global `MOTOR_ANALISE`). Devolve o anterior.
pub async fn definir_motor(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    motor: Option<&str>,
) -> Result<Option<String>, DbError> {
    sqlx::query(
        "INSERT INTO tenants_tenantconfig (tenant_id) VALUES ($1) ON CONFLICT (tenant_id) DO NOTHING",
    )
    .bind(tenant_id)
    .execute(&mut **tx)
    .await?;
    let anterior: Option<String> =
        sqlx::query_scalar("SELECT motor_analise FROM tenants_tenantconfig WHERE tenant_id = $1")
            .bind(tenant_id)
            .fetch_one(&mut **tx)
            .await?;
    sqlx::query(
        "UPDATE tenants_tenantconfig SET motor_analise = $2, updated_at = NOW() WHERE tenant_id = $1",
    )
    .bind(tenant_id)
    .bind(motor)
    .execute(&mut **tx)
    .await?;
    Ok(anterior)
}

// ------------------------------------------------------ decisões da IA
/// Uma decisão da IA para `oraculo_decisao_ia` — sem texto da conversa.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DecisaoIa {
    pub atendimento_id: Option<i32>,
    pub etapa: String,
    pub motor: String,
    pub vale: bool,
    pub modelo: String,
    pub intencao: String,
    pub confianca_intencao: Option<f64>,
    pub decisao: String,
    pub transferiu: bool,
    pub motivo: String,
    pub regra_id: Option<i64>,
    pub fluxo_id: Option<i32>,
    pub sinais: serde_json::Value,
    pub trechos_aprovados: serde_json::Value,
    pub trechos_descartados: serde_json::Value,
    pub confiabilidade: Option<f64>,
    pub tokens_entrada: i64,
    pub requisicoes: i32,
    pub duracao_ms: i64,
}

fn corte(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

impl DecisaoIa {
    /// Lê o payload do worker, cortando os textos ao tamanho das colunas e
    /// descartando o que não for número/lista onde se espera número/lista.
    pub fn do_json(p: &serde_json::Value) -> Result<Self, String> {
        let texto = |c: &str| {
            p.get(c)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let etapa = texto("etapa");
        if etapa != "analise" && etapa != "resposta" {
            return Err("etapa inválida: analise ou resposta".into());
        }
        let motor = texto("motor");
        if motor != "llm" && motor != "jev" {
            return Err("motor inválido: llm ou jev".into());
        }
        let lista = |c: &str| match p.get(c) {
            Some(v @ serde_json::Value::Array(_)) => v.clone(),
            _ => serde_json::json!([]),
        };
        Ok(Self {
            atendimento_id: p
                .get("atendimento_id")
                .and_then(|v| v.as_i64())
                .map(|v| v as i32),
            etapa,
            motor,
            vale: p.get("vale").and_then(|v| v.as_bool()).unwrap_or(true),
            modelo: corte(&texto("modelo"), 40),
            intencao: corte(&texto("intencao"), 120),
            confianca_intencao: p.get("confianca_intencao").and_then(|v| v.as_f64()),
            decisao: corte(&texto("decisao"), 20),
            transferiu: p
                .get("transferiu")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            motivo: corte(&texto("motivo"), 200),
            regra_id: p.get("regra_id").and_then(|v| v.as_i64()),
            fluxo_id: p.get("fluxo_id").and_then(|v| v.as_i64()).map(|v| v as i32),
            sinais: lista("sinais"),
            trechos_aprovados: lista("trechos_aprovados"),
            trechos_descartados: lista("trechos_descartados"),
            confiabilidade: p.get("confiabilidade").and_then(|v| v.as_f64()),
            tokens_entrada: p
                .get("tokens_entrada")
                .and_then(|v| v.as_i64())
                .unwrap_or(0),
            requisicoes: p.get("requisicoes").and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            duracao_ms: p.get("duracao_ms").and_then(|v| v.as_i64()).unwrap_or(0),
        })
    }
}

pub async fn registrar_decisao(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    d: &DecisaoIa,
) -> Result<i64, DbError> {
    let id: i64 = sqlx::query_scalar(
        "INSERT INTO oraculo_decisao_ia \
            (tenant_id, atendimento_id, etapa, motor, vale, modelo, intencao, confianca_intencao, \
             decisao, transferiu, motivo, regra_id, fluxo_id, sinais, trechos_aprovados, \
             trechos_descartados, confiabilidade, tokens_entrada, requisicoes, duracao_ms) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) \
         RETURNING id",
    )
    .bind(tenant_id)
    .bind(d.atendimento_id)
    .bind(&d.etapa)
    .bind(&d.motor)
    .bind(d.vale)
    .bind(&d.modelo)
    .bind(&d.intencao)
    .bind(d.confianca_intencao)
    .bind(&d.decisao)
    .bind(d.transferiu)
    .bind(&d.motivo)
    .bind(d.regra_id)
    .bind(d.fluxo_id)
    .bind(&d.sinais)
    .bind(&d.trechos_aprovados)
    .bind(&d.trechos_descartados)
    .bind(d.confiabilidade)
    .bind(d.tokens_entrada)
    .bind(d.requisicoes)
    .bind(d.duracao_ms)
    .fetch_one(&mut **tx)
    .await?;
    Ok(id)
}

/// Últimas transferências decididas pela IA (as que valeram), com o motivo e
/// os sinais. Sem texto da conversa: o motivo é o nome da regra ou do sinal.
pub async fn listar_transferencias(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    limite: i64,
) -> Result<Vec<serde_json::Value>, DbError> {
    let linhas = sqlx::query(
        "SELECT d.id, d.atendimento_id, d.motor, d.modelo, d.motivo, d.regra_id, d.fluxo_id, \
                f.nome AS fluxo_nome, d.sinais, d.criado_em \
         FROM oraculo_decisao_ia d \
         LEFT JOIN oraculo_fluxo_atendimento f ON f.id = d.fluxo_id \
         WHERE d.tenant_id = $1 AND d.transferiu AND d.vale AND d.etapa = 'resposta' \
         ORDER BY d.criado_em DESC LIMIT $2",
    )
    .bind(tenant_id)
    .bind(limite.clamp(1, 200))
    .fetch_all(&mut **tx)
    .await?;
    linhas
        .iter()
        .map(|r| -> Result<serde_json::Value, DbError> {
            let criado: chrono::DateTime<chrono::Utc> = r.try_get("criado_em")?;
            Ok(serde_json::json!({
                "id": r.try_get::<i64, _>("id")?,
                "atendimento_id": r.try_get::<Option<i32>, _>("atendimento_id")?,
                "motor": r.try_get::<String, _>("motor")?,
                "modelo": r.try_get::<String, _>("modelo")?,
                "motivo": r.try_get::<String, _>("motivo")?,
                "regra_id": r.try_get::<Option<i64>, _>("regra_id")?,
                "fluxo_id": r.try_get::<Option<i32>, _>("fluxo_id")?,
                "fluxo_nome": r.try_get::<Option<String>, _>("fluxo_nome")?,
                "sinais": r.try_get::<serde_json::Value, _>("sinais")?,
                "criado_em": criado.timestamp_millis(),
            }))
        })
        .collect()
}

/// Marca o motor e o modelo na mensagem do bot (a escala da confiança muda
/// com o motor).
pub async fn marcar_motor_da_mensagem(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    mensagem_id: i32,
    motor: &str,
    modelo: &str,
) -> Result<(), DbError> {
    sqlx::query(
        "UPDATE oraculo_mensagem SET motor = $3, modelo = $4 WHERE tenant_id = $1 AND id = $2",
    )
    .bind(tenant_id)
    .bind(mensagem_id)
    .bind(corte(motor, 10))
    .bind(corte(modelo, 40))
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// Retenção de 90 dias: apaga decisões antigas de todos os tenants. Exige o
/// pool administrativo (consulta cross-tenant; no de runtime o RLS zeraria).
pub async fn purgar_decisoes_antigas(pool: &sqlx::PgPool, dias: i64) -> Result<u64, DbError> {
    let r = sqlx::query(
        "DELETE FROM oraculo_decisao_ia WHERE criado_em < NOW() - make_interval(days => $1::int)",
    )
    .bind(dias.clamp(1, 3650) as i32)
    .execute(pool)
    .await?;
    Ok(r.rows_affected())
}

// ------------------------------------------------------------ sugestões
/// Sugestões de regra a partir do texto de transferência de hoje — uma por
/// intenção cujo comportamento fala em transferir/encaminhar, e uma por linha
/// do prompt de regras de transferência. Nascem INATIVAS: o tenant revisa,
/// ajusta a condição e ativa. Determinístico (sem LLM): o que a migração faz
/// é tornar visível o que estava escondido em prosa, não decidir por ele.
pub fn sugestoes_do_texto(
    intents: &[(String, String)],
    prompt_transferencia: &str,
) -> Vec<DadosRegra> {
    const PALAVRAS: [&str; 5] = [
        "transfer",
        "encaminh",
        "atendente",
        "passe para",
        "passar para",
    ];
    let fala_de_transferir = |t: &str| {
        let t = t.to_lowercase();
        PALAVRAS.iter().any(|p| t.contains(p))
    };
    let mut sugestoes: Vec<DadosRegra> = intents
        .iter()
        .filter(|(tag, comportamento)| !tag.trim().is_empty() && fala_de_transferir(comportamento))
        .map(|(tag, _)| DadosRegra {
            nome: corte(&format!("Intenção {tag}"), 120),
            gatilho_tipo: "intencao".into(),
            intencao_tag: tag.trim().to_string(),
            momento: "imediato".into(),
            destino_tipo: "setor_jev".into(),
            sensibilidade: "media".into(),
            ..Default::default()
        })
        .collect();
    for (n, linha) in prompt_transferencia
        .lines()
        .map(|l| l.trim().trim_start_matches(['-', '*', '•', ' ']).trim())
        .filter(|l| l.chars().count() >= 10)
        .enumerate()
    {
        sugestoes.push(DadosRegra {
            nome: corte(&format!("Regra do prompt {}", n + 1), 120),
            gatilho_tipo: "condicao".into(),
            condicao: corte(linha, 1000),
            momento: "imediato".into(),
            destino_tipo: "setor_jev".into(),
            sensibilidade: "media".into(),
            ..Default::default()
        });
    }
    sugestoes
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valida() -> DadosRegra {
        DadosRegra {
            nome: "Fechar pedido".into(),
            gatilho_tipo: "condicao".into(),
            condicao: "o cliente quer fechar o pedido".into(),
            momento: "imediato".into(),
            destino_tipo: "padrao".into(),
            sensibilidade: "media".into(),
            ..Default::default()
        }
    }

    #[test]
    fn validacao_explica_o_que_falta() {
        assert!(valida().validar().is_ok());
        let mut d = valida();
        d.condicao = "vendas".into();
        assert!(d.validar().unwrap_err().contains("frase exata"));
        let mut d = valida();
        d.momento = "apos_coleta".into();
        assert!(d.validar().unwrap_err().contains("campos"));
        let mut d = valida();
        d.destino_tipo = "fluxo".into();
        assert!(d.validar().unwrap_err().contains("fluxo"));
        let mut d = valida();
        d.gatilho_tipo = "intencao".into();
        assert!(d.validar().unwrap_err().contains("intenção"));
        let mut d = valida();
        d.sensibilidade = "máxima".into();
        assert!(d.validar().is_err());
    }

    #[test]
    fn json_com_padroes_e_mescla_parcial() {
        let d = DadosRegra::do_json(&serde_json::json!({
            "nome": " Fechar ", "condicao": "o cliente quer fechar", "exemplos_sim": ["pode fechar", " "],
            "destino_fluxo_id": 0,
        }));
        assert_eq!(d.nome, "Fechar");
        assert_eq!(d.gatilho_tipo, "condicao");
        assert_eq!(d.exemplos_sim, vec!["pode fechar"]);
        assert_eq!(d.destino_fluxo_id, None);
        let base = RegraTransferencia {
            nome: "A".into(),
            exemplos_nao: vec!["x".into()],
            destino_fluxo_id: Some(3),
            ..Default::default()
        };
        let m = DadosRegra::mesclar(
            &base,
            &serde_json::json!({ "nome": "B", "destino_fluxo_id": null }),
        );
        assert_eq!(m.nome, "B");
        assert_eq!(m.exemplos_nao, vec!["x"]);
        assert_eq!(m.destino_fluxo_id, None);
    }

    #[test]
    fn sinais_so_conhecidos_e_validos() {
        let atuais = serde_json::json!({ "irritacao": { "ativo": true } });
        let novo = normalizar_sinais(
            &atuais,
            &serde_json::json!({ "irritacao": false, "pede_humano": { "sensibilidade": "alta" } }),
        )
        .unwrap();
        assert_eq!(novo["irritacao"]["ativo"], false);
        assert_eq!(novo["pede_humano"]["sensibilidade"], "alta");
        assert!(normalizar_sinais(&atuais, &serde_json::json!({ "outro": true })).is_err());
        assert!(normalizar_sinais(
            &atuais,
            &serde_json::json!({ "irritacao": { "sensibilidade": "x" } })
        )
        .is_err());
        assert!(normalizar_sinais(&atuais, &serde_json::json!([])).is_err());
    }

    #[test]
    fn decisao_sem_texto_e_com_limites() {
        let d = DecisaoIa::do_json(&serde_json::json!({
            "etapa": "resposta", "motor": "jev", "motivo": "x".repeat(500), "sinais": "não é lista",
            "trechos_aprovados": ["1"], "tokens_entrada": 90,
        }))
        .unwrap();
        assert_eq!(d.motivo.chars().count(), 200);
        assert_eq!(d.sinais, serde_json::json!([]));
        assert!(d.vale);
        assert!(DecisaoIa::do_json(&serde_json::json!({ "etapa": "x", "motor": "jev" })).is_err());
        assert!(
            DecisaoIa::do_json(&serde_json::json!({ "etapa": "analise", "motor": "gpt" })).is_err()
        );
    }

    #[test]
    fn sugestoes_saem_do_texto_escondido() {
        let intents = vec![
            (
                "campanha".to_string(),
                "Transfira para o Paulo imediatamente".to_string(),
            ),
            ("preco".to_string(), "Informe a tabela".to_string()),
        ];
        let s = sugestoes_do_texto(
            &intents,
            "- Se o cliente quiser fechar pedido, encaminhe\ncurto",
        );
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].gatilho_tipo, "intencao");
        assert_eq!(s[0].intencao_tag, "campanha");
        assert_eq!(
            s[1].condicao,
            "Se o cliente quiser fechar pedido, encaminhe"
        );
        assert!(s.iter().all(|r| r.validar().is_ok()));
    }
}
