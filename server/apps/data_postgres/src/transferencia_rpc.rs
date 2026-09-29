//! Plano ia-engine-jev — RPCs da "Transferência para atendente", do motor por
//! tenant e do registro das decisões da IA.
//!
//! Público:
//!
//! * a **borda** (`runtime_api`), para a tela e o MCP: listar, salvar, ativar e
//!   desativar regras, ler e mudar os sinais, as últimas transferências e as
//!   sugestões a partir do texto antigo;
//! * o **worker**: `RegistrarDecisaoIa` (uma linha por motor, sem texto da
//!   conversa), `PurgarDecisoesIa` (retenção de 90 dias) e as rodadas de
//!   coleta do motor Jev (`ObterRodadasColeta`, `RegistrarRodadaColeta`);
//! * o **superusuário**: `DefinirMotorTenant`.
//!
//! Toda escrita do tenant é auditada (evento, nome e campos alterados — nunca
//! o texto de conversa). O `dry_run` valida e diz o efeito sem gravar.

use contracts::Envelope;
use infrastructure_postgres::transferencia::{
    ConfigTransferencia, DadosRegra, DecisaoIa, RegraTransferencia, SINAIS,
};
use transport::Server;
use uuid::Uuid;

use crate::ports;
use crate::{contexto_do_envelope, erro, ok_reply, AppState};

fn payload_de(env: &Envelope) -> serde_json::Value {
    serde_json::from_slice(&env.payload).unwrap_or_else(|_| serde_json::json!({}))
}

fn validacao(msg: impl Into<String>, env: &Envelope) -> Envelope {
    erro(error_core::AppError::Validation(msg.into()), env)
}

fn id_do_payload(p: &serde_json::Value) -> Option<i64> {
    p.get("id").and_then(|v| v.as_i64()).filter(|id| *id > 0)
}

fn dry_run(p: &serde_json::Value) -> bool {
    p.get("dry_run").and_then(|v| v.as_bool()).unwrap_or(false)
}

/// Nomes dos campos que mudaram entre duas versões (para a auditoria).
fn campos_alterados(antes: &RegraTransferencia, depois: &DadosRegra) -> Vec<&'static str> {
    let mut c = Vec::new();
    let mut se = |nome: &'static str, mudou: bool| {
        if mudou {
            c.push(nome);
        }
    };
    se("nome", antes.nome != depois.nome);
    se("gatilho_tipo", antes.gatilho_tipo != depois.gatilho_tipo);
    se("condicao", antes.condicao != depois.condicao);
    se("intencao_tag", antes.intencao_tag != depois.intencao_tag);
    se("exemplos_sim", antes.exemplos_sim != depois.exemplos_sim);
    se("exemplos_nao", antes.exemplos_nao != depois.exemplos_nao);
    se("momento", antes.momento != depois.momento);
    se("campos_coleta", antes.campos_coleta != depois.campos_coleta);
    se("destino_tipo", antes.destino_tipo != depois.destino_tipo);
    se(
        "destino_fluxo_id",
        antes.destino_fluxo_id != depois.destino_fluxo_id,
    );
    se("mensagem", antes.mensagem != depois.mensagem);
    se("sensibilidade", antes.sensibilidade != depois.sensibilidade);
    c
}

/// Sinais com os padrões da decisão de 2026-09-28 onde o tenant não mexeu:
/// pedido de humano, irritação e dúvida ligados; base sem resposta e
/// resposta sem apoio desligados. A tela mostra sempre os cinco.
pub fn sinais_com_padroes(gravados: &serde_json::Value) -> Vec<serde_json::Value> {
    SINAIS
        .iter()
        .map(|nome| {
            let padrao_ativo = matches!(*nome, "pede_humano" | "irritacao" | "duvida_transfere");
            let g = gravados.get(*nome);
            let ativo = match g {
                Some(serde_json::Value::Bool(b)) => *b,
                Some(v) => v
                    .get("ativo")
                    .and_then(|a| a.as_bool())
                    .unwrap_or(padrao_ativo),
                None => padrao_ativo,
            };
            let sensibilidade = g
                .and_then(|v| v.get("sensibilidade"))
                .and_then(|s| s.as_str())
                .unwrap_or("media");
            serde_json::json!({ "nome": nome, "ativo": ativo, "sensibilidade": sensibilidade })
        })
        .collect()
}

fn config_json(c: &ConfigTransferencia, motor_efetivo: &str) -> serde_json::Value {
    serde_json::json!({
        "sinais": sinais_com_padroes(&c.sinais),
        "fluxo_padrao_id": c.fluxo_padrao_id,
        "msg_transferencia": c.msg_transferencia,
        "motor_analise": motor_efetivo,
    })
}

// ------------------------------------------------------------------ regras
#[tracing::instrument(skip_all, fields(rpc = "ListRegrasTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_listar_regras(
    store: &dyn ports::TransferenciaStore,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_regras(&ctx).await {
        Ok(regras) => ok_reply(
            &env,
            "ListRegrasTransferenciaReply",
            serde_json::json!({ "regras": regras }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "GetRegraTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_obter_regra(store: &dyn ports::TransferenciaStore, env: Envelope) -> Envelope {
    let p = payload_de(&env);
    let Some(id) = id_do_payload(&p) else {
        return validacao("regra não informada", &env);
    };
    let ctx = contexto_do_envelope(&env);
    match store.obter_regra(&ctx, id).await {
        Ok(Some(r)) => ok_reply(
            &env,
            "GetRegraTransferenciaReply",
            serde_json::json!({ "regra": r }),
        ),
        Ok(None) => validacao("regra não encontrada", &env),
        Err(e) => erro(e.into(), &env),
    }
}

/// Cria (`id` ausente) ou atualiza (`id`) uma regra. Na criação, a regra
/// nasce inativa: o tenant a testa antes de valer.
#[tracing::instrument(skip_all, fields(rpc = "SalvarRegraTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_salvar_regra(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let ctx = contexto_do_envelope(&env);
    let simular = dry_run(&p);

    match id_do_payload(&p) {
        None => {
            let dados = DadosRegra::do_json(&p);
            if let Err(motivo) = dados.validar() {
                return validacao(motivo, &env);
            }
            if simular {
                // Nome repetido também é recusado na simulação.
                return match store.listar_regras(&ctx).await {
                    Ok(regras)
                        if regras
                            .iter()
                            .any(|r| r.nome.to_lowercase() == dados.nome.to_lowercase()) =>
                    {
                        validacao(
                            format!("já existe uma regra chamada \"{}\"", dados.nome),
                            &env,
                        )
                    }
                    Ok(_) => ok_reply(
                        &env,
                        "SalvarRegraTransferenciaReply",
                        serde_json::json!({ "simulacao": true, "regra": dados, "efeito": "criar regra inativa" }),
                    ),
                    Err(e) => erro(e.into(), &env),
                };
            }
            match store.criar_regra(&ctx, dados, false).await {
                Ok(Ok(regra)) => {
                    audit
                        .publish(
                            &env,
                            "transferencia_regra.criada",
                            format!("Regra de transferência \"{}\" criada", regra.nome),
                            serde_json::json!({ "id": regra.id, "nome": regra.nome, "gatilho_tipo": regra.gatilho_tipo }),
                        )
                        .await;
                    ok_reply(
                        &env,
                        "SalvarRegraTransferenciaReply",
                        serde_json::json!({ "regra": regra }),
                    )
                }
                Ok(Err(motivo)) => validacao(motivo, &env),
                Err(e) => erro(e.into(), &env),
            }
        }
        Some(id) => {
            if simular {
                return match store.obter_regra(&ctx, id).await {
                    Ok(Some(antes)) => {
                        let dados = DadosRegra::mesclar(&antes, &p);
                        if let Err(motivo) = dados.validar() {
                            return validacao(motivo, &env);
                        }
                        let campos = campos_alterados(&antes, &dados);
                        ok_reply(
                            &env,
                            "SalvarRegraTransferenciaReply",
                            serde_json::json!({ "simulacao": true, "regra": antes, "campos_alterados": campos }),
                        )
                    }
                    Ok(None) => validacao("regra não encontrada", &env),
                    Err(e) => erro(e.into(), &env),
                };
            }
            match store.atualizar_regra(&ctx, id, p).await {
                Ok(Ok(Some((antes, depois)))) => {
                    let dados =
                        DadosRegra::do_json(&serde_json::to_value(&depois).unwrap_or_default());
                    let campos = campos_alterados(&antes, &dados);
                    audit
                        .publish(
                            &env,
                            "transferencia_regra.atualizada",
                            format!("Regra de transferência \"{}\" alterada", depois.nome),
                            serde_json::json!({ "id": depois.id, "nome": depois.nome, "campos": campos }),
                        )
                        .await;
                    ok_reply(
                        &env,
                        "SalvarRegraTransferenciaReply",
                        serde_json::json!({ "regra": depois, "campos_alterados": campos }),
                    )
                }
                Ok(Ok(None)) => validacao("regra não encontrada", &env),
                Ok(Err(motivo)) => validacao(motivo, &env),
                Err(e) => erro(e.into(), &env),
            }
        }
    }
}

/// Ativar ou desativar. Desativar exige `confirmar` com o nome da regra: um id
/// errado ou alucinado não pode desligar outra regra.
#[tracing::instrument(skip_all, fields(rpc = "SetRegraTransferenciaAtiva", tenant_id = %env.tenant_id))]
pub async fn handler_regra_ativa(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let Some(id) = id_do_payload(&p) else {
        return validacao("regra não informada", &env);
    };
    let Some(ativa) = p.get("ativa").and_then(|v| v.as_bool()) else {
        return validacao("informe ativa: true ou false", &env);
    };
    let ctx = contexto_do_envelope(&env);
    let atual = match store.obter_regra(&ctx, id).await {
        Ok(Some(r)) => r,
        Ok(None) => return validacao("regra não encontrada", &env),
        Err(e) => return erro(e.into(), &env),
    };
    if !ativa {
        let confirmar = p
            .get("confirmar")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim();
        if !dry_run(&p) && confirmar.to_lowercase() != atual.nome.to_lowercase() {
            return validacao(
                format!(
                    "para desativar, confirme digitando o nome da regra: \"{}\"",
                    atual.nome
                ),
                &env,
            );
        }
    }
    if dry_run(&p) {
        let efeito = if atual.ativa == ativa {
            "nada — a regra já está assim"
        } else if ativa {
            "a regra passa a valer na próxima mensagem"
        } else {
            "a regra deixa de valer; nada é apagado"
        };
        return ok_reply(
            &env,
            "SetRegraTransferenciaAtivaReply",
            serde_json::json!({ "simulacao": true, "regra": atual, "efeito": efeito }),
        );
    }
    match store.definir_regra_ativa(&ctx, id, ativa).await {
        Ok(Some(regra)) => {
            let evento = if ativa {
                "transferencia_regra.ativada"
            } else {
                "transferencia_regra.desativada"
            };
            audit
                .publish(
                    &env,
                    evento,
                    format!(
                        "Regra de transferência \"{}\" {}",
                        regra.nome,
                        if ativa { "ativada" } else { "desativada" }
                    ),
                    serde_json::json!({ "id": regra.id, "nome": regra.nome }),
                )
                .await;
            ok_reply(
                &env,
                "SetRegraTransferenciaAtivaReply",
                serde_json::json!({ "regra": regra }),
            )
        }
        Ok(None) => validacao("regra não encontrada", &env),
        Err(e) => erro(e.into(), &env),
    }
}

// ------------------------------------------------------------------ sinais
#[tracing::instrument(skip_all, fields(rpc = "GetConfigTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_obter_config(
    store: &dyn ports::TransferenciaStore,
    config_cache: &infrastructure_postgres::TenantConfigCache,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    let motor = config_cache
        .get_config(ctx.tenant_id)
        .await
        .map(|c| c.motor_analise.clone())
        .unwrap_or_else(|_| "llm".into());
    match store.obter_config(&ctx).await {
        Ok(c) => ok_reply(&env, "GetConfigTransferenciaReply", config_json(&c, &motor)),
        Err(e) => erro(e.into(), &env),
    }
}

/// Sinais (`sinais`: {nome: {ativo, sensibilidade}} ou lista de
/// {nome, ativo, sensibilidade}) e/ou fluxo padrão (`fluxo_padrao_id`: número,
/// ou null para limpar).
#[tracing::instrument(skip_all, fields(rpc = "SetSinaisTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_definir_sinais(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    config_cache: &infrastructure_postgres::TenantConfigCache,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let ctx = contexto_do_envelope(&env);
    // Aceita a lista da tela ({nome, ativo, sensibilidade}) além do objeto.
    let sinais = match p.get("sinais") {
        Some(serde_json::Value::Array(itens)) => {
            let mut mapa = serde_json::Map::new();
            for item in itens {
                let Some(nome) = item.get("nome").and_then(|v| v.as_str()) else {
                    return validacao("sinal sem nome", &env);
                };
                let mut v = serde_json::Map::new();
                if let Some(a) = item.get("ativo") {
                    v.insert("ativo".into(), a.clone());
                }
                if let Some(s) = item
                    .get("sensibilidade")
                    .filter(|s| s.as_str().is_some_and(|s| !s.is_empty()))
                {
                    v.insert("sensibilidade".into(), s.clone());
                }
                mapa.insert(nome.to_string(), serde_json::Value::Object(v));
            }
            Some(serde_json::Value::Object(mapa))
        }
        Some(v @ serde_json::Value::Object(_)) => Some(v.clone()),
        Some(serde_json::Value::Null) | None => None,
        Some(_) => return validacao("sinais: envie um objeto ou uma lista", &env),
    };
    let fluxo_padrao = match p.get("fluxo_padrao_id") {
        None => None,
        Some(serde_json::Value::Null) => Some(None),
        Some(v) => match v.as_i64() {
            Some(0) => Some(None),
            Some(id) if id > 0 => Some(Some(id as i32)),
            _ => return validacao("fluxo_padrao_id inválido", &env),
        },
    };
    if sinais.is_none() && fluxo_padrao.is_none() {
        return validacao("nada a alterar: envie sinais ou fluxo_padrao_id", &env);
    }
    let motor = config_cache
        .get_config(ctx.tenant_id)
        .await
        .map(|c| c.motor_analise.clone())
        .unwrap_or_else(|_| "llm".into());

    if dry_run(&p) {
        return match store.obter_config(&ctx).await {
            Ok(atual) => {
                let novos = match &sinais {
                    Some(pedido) => {
                        match infrastructure_postgres::transferencia::normalizar_sinais(
                            &atual.sinais,
                            pedido,
                        ) {
                            Ok(v) => v,
                            Err(motivo) => return validacao(motivo, &env),
                        }
                    }
                    None => atual.sinais.clone(),
                };
                let depois = ConfigTransferencia {
                    sinais: novos,
                    fluxo_padrao_id: fluxo_padrao.unwrap_or(atual.fluxo_padrao_id),
                    ..atual.clone()
                };
                let mut resp = config_json(&depois, &motor);
                resp["simulacao"] = serde_json::json!(true);
                resp["antes"] = config_json(&atual, &motor);
                ok_reply(&env, "SetSinaisTransferenciaReply", resp)
            }
            Err(e) => erro(e.into(), &env),
        };
    }

    match store.definir_config(&ctx, sinais, fluxo_padrao).await {
        Ok(Ok((antes, depois))) => {
            audit
                .publish(
                    &env,
                    "transferencia_sinais.alterados",
                    "Sinais automáticos de transferência alterados".to_string(),
                    serde_json::json!({
                        "antes": { "sinais": sinais_com_padroes(&antes.sinais), "fluxo_padrao_id": antes.fluxo_padrao_id },
                        "depois": { "sinais": sinais_com_padroes(&depois.sinais), "fluxo_padrao_id": depois.fluxo_padrao_id },
                    }),
                )
                .await;
            ok_reply(
                &env,
                "SetSinaisTransferenciaReply",
                config_json(&depois, &motor),
            )
        }
        Ok(Err(motivo)) => validacao(motivo, &env),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "ListTransferencias", tenant_id = %env.tenant_id))]
pub async fn handler_listar_transferencias(
    store: &dyn ports::TransferenciaStore,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let limite = p
        .get("limite")
        .and_then(|v| v.as_i64())
        .filter(|l| *l > 0)
        .unwrap_or(30);
    let ctx = contexto_do_envelope(&env);
    match store.listar_transferencias(&ctx, limite).await {
        Ok(itens) => ok_reply(
            &env,
            "ListTransferenciasReply",
            serde_json::json!({ "transferencias": itens }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "GerarSugestoesTransferencia", tenant_id = %env.tenant_id))]
pub async fn handler_gerar_sugestoes(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.gerar_sugestoes(&ctx).await {
        Ok(criadas) => {
            audit
                .publish(
                    &env,
                    "transferencia_regra.sugestoes_geradas",
                    format!(
                        "{criadas} sugestão(ões) de regra de transferência criada(s), inativas"
                    ),
                    serde_json::json!({ "quantidade": criadas }),
                )
                .await;
            ok_reply(
                &env,
                "GerarSugestoesTransferenciaReply",
                serde_json::json!({ "criadas": criadas }),
            )
        }
        Err(e) => erro(e.into(), &env),
    }
}

// --------------------------------------------------------------- worker
/// Uma decisão da IA (worker). Sem auditoria: é registro técnico para
/// calibração e comparação da sombra, não ação de alguém.
#[tracing::instrument(skip_all, fields(rpc = "RegistrarDecisaoIa", tenant_id = %env.tenant_id))]
pub async fn handler_registrar_decisao(
    store: &dyn ports::TransferenciaStore,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let decisao = match DecisaoIa::do_json(&p) {
        Ok(d) => d,
        Err(motivo) => return validacao(motivo, &env),
    };
    let ctx = contexto_do_envelope(&env);
    match store.registrar_decisao(&ctx, decisao).await {
        Ok(id) => ok_reply(
            &env,
            "RegistrarDecisaoIaReply",
            serde_json::json!({ "id": id }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

fn atendimento_do_payload(p: &serde_json::Value) -> Option<i32> {
    p.get("atendimento_id")
        .and_then(|v| v.as_i64())
        .filter(|id| *id > 0)
        .map(|id| id as i32)
}

#[tracing::instrument(skip_all, fields(rpc = "ObterRodadasColeta", tenant_id = %env.tenant_id))]
pub async fn handler_obter_rodadas(
    store: &dyn ports::TransferenciaStore,
    env: Envelope,
) -> Envelope {
    let Some(atendimento_id) = atendimento_do_payload(&payload_de(&env)) else {
        return validacao("informe o atendimento_id", &env);
    };
    let ctx = contexto_do_envelope(&env);
    match store.rodadas_coleta(&ctx, atendimento_id).await {
        Ok(n) => ok_reply(
            &env,
            "ObterRodadasColetaReply",
            serde_json::json!({ "rodadas": n }),
        ),
        Err(e) => erro(e.into(), &env),
    }
}

/// O bot pediu dados ao cliente (ato `coletar`, ou `responder` com perguntas):
/// soma uma rodada e audita quais campos — só os slugs, nunca a conversa.
#[tracing::instrument(skip_all, fields(rpc = "RegistrarRodadaColeta", tenant_id = %env.tenant_id))]
pub async fn handler_registrar_rodada(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let Some(atendimento_id) = atendimento_do_payload(&p) else {
        return validacao("informe o atendimento_id", &env);
    };
    let campos: Vec<String> = p
        .get("campos")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|c| c.as_str())
                .map(|c| c.chars().take(60).collect())
                .take(10)
                .collect()
        })
        .unwrap_or_default();
    let ctx = contexto_do_envelope(&env);
    match store.registrar_rodada_coleta(&ctx, atendimento_id).await {
        Ok(Some(n)) => {
            audit
                .publish(
                    &env,
                    "atendimento.coleta_rodada",
                    format!("O bot pediu {} dado(s) ao cliente", campos.len()),
                    serde_json::json!({
                        "atendimento_id": atendimento_id,
                        "rodada": n,
                        "campos": campos,
                    }),
                )
                .await;
            ok_reply(
                &env,
                "RegistrarRodadaColetaReply",
                serde_json::json!({ "rodadas": n }),
            )
        }
        Ok(None) => validacao("atendimento não encontrado", &env),
        Err(e) => erro(e.into(), &env),
    }
}

#[tracing::instrument(skip_all, fields(rpc = "PurgarDecisoesIa"))]
pub async fn handler_purgar_decisoes(
    store: &dyn ports::TransferenciaStore,
    env: Envelope,
) -> Envelope {
    let p = payload_de(&env);
    let dias = p
        .get("dias")
        .and_then(|v| v.as_i64())
        .filter(|d| *d > 0)
        .unwrap_or(90);
    match store.purgar_decisoes(dias).await {
        Ok(n) => {
            tracing::info!(apagadas = n, dias, "retenção das decisões da IA aplicada");
            ok_reply(
                &env,
                "PurgarDecisoesIaReply",
                serde_json::json!({ "apagadas": n }),
            )
        }
        Err(e) => erro(e.into(), &env),
    }
}

// --------------------------------------------------------- superusuário
/// Troca o motor das decisões da IA de um tenant. Só o superusuário: é decisão
/// de plataforma (custo, fornecedor, contrato), fora do MCP do tenant.
#[tracing::instrument(skip_all, fields(rpc = "DefinirMotorTenant"))]
pub async fn handler_definir_motor(
    store: &dyn ports::TransferenciaStore,
    audit: &dyn ports::AuditPort,
    env: Envelope,
) -> Envelope {
    if !env.auth_is_superuser {
        return erro(
            error_core::AppError::Auth("só o superusuário troca o motor da IA".into()),
            &env,
        );
    }
    let p = payload_de(&env);
    let Some(tenant_id) = p
        .get("tenant_id")
        .and_then(|v| v.as_str())
        .and_then(|s| Uuid::parse_str(s).ok())
    else {
        return validacao("tenant_id inválido", &env);
    };
    let motor = p
        .get("motor")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    let motor = match motor.as_str() {
        "" => None,
        m if infrastructure_postgres::transferencia::MOTORES.contains(&m) => Some(m.to_string()),
        _ => {
            return validacao(
                "motor inválido: llm, sombra, jev ou vazio (herda o global)",
                &env,
            )
        }
    };
    match store.definir_motor(tenant_id, motor.clone()).await {
        Ok(anterior) => {
            // Pelo `publish` (e não `publish_security`) com o envelope apontado
            // para o tenant alvo: assim a trilha leva também o `user_agent` de
            // quem trocou (08 §4.2), além do `user_id` do superusuário.
            let mut env_auditoria = env.clone();
            env_auditoria.tenant_id = tenant_id.to_string();
            audit
                .publish(
                    &env_auditoria,
                    "tenant_config.motor_alterado",
                    "Motor das decisões da IA alterado pelo superusuário".to_string(),
                    serde_json::json!({
                        "antes": anterior.as_deref().unwrap_or("global"),
                        "depois": motor.as_deref().unwrap_or("global"),
                    }),
                )
                .await;
            ok_reply(
                &env,
                "DefinirMotorTenantReply",
                serde_json::json!({
                    "anterior": anterior.unwrap_or_default(),
                    "atual": motor.unwrap_or_default(),
                }),
            )
        }
        Err(e) => erro(e.into(), &env),
    }
}

/// `PersistMessage` com o motor da resposta: grava a mensagem pelo handler de
/// sempre e marca motor e modelo na linha (a escala da confiança muda com o
/// motor). Best-effort na marcação: a mensagem já foi gravada.
async fn persistir_com_motor(state: &AppState, env: Envelope) -> Envelope {
    let p = payload_de(&env);
    let motor = p.get("motor").and_then(|v| v.as_str()).map(str::to_string);
    let modelo = p
        .get("modelo")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let ctx = contexto_do_envelope(&env);
    let resp = crate::handler_persist_message(state.atendimento.as_ref(), env).await;
    if let Some(motor) = motor.filter(|m| !m.is_empty()) {
        let id = serde_json::from_slice::<serde_json::Value>(&resp.payload)
            .ok()
            .and_then(|v| v.get("message_id").and_then(|m| m.as_i64()));
        if let Some(id) = id {
            if let Err(e) = state
                .transferencia
                .marcar_motor_da_mensagem(&ctx, id as i32, motor, modelo)
                .await
            {
                tracing::warn!("falha ao marcar o motor na mensagem do bot: {e}");
            }
        }
    }
    resp
}

/// Rotas do plano ia-engine-jev, à parte da cadeia principal pelo mesmo motivo
/// de `registrar_rotas_mcp`. Re-registra `PersistMessage` (o mapa de rotas
/// guarda a última) para marcar o motor na resposta do bot.
pub fn registrar_rotas(server: Server, state: AppState) -> Server {
    let s = |st: &AppState| st.clone();
    let (s13, s14) = (s(&state), s(&state));
    let (s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12) = (
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
        s(&state),
    );
    server
        .route("ListRegrasTransferencia", move |env| {
            let st = s1.clone();
            Box::pin(async move { handler_listar_regras(st.transferencia.as_ref(), env).await })
        })
        .route("GetRegraTransferencia", move |env| {
            let st = s2.clone();
            Box::pin(async move { handler_obter_regra(st.transferencia.as_ref(), env).await })
        })
        .route("SalvarRegraTransferencia", move |env| {
            let st = s3.clone();
            Box::pin(async move {
                handler_salvar_regra(st.transferencia.as_ref(), st.audit.as_ref(), env).await
            })
        })
        .route("SetRegraTransferenciaAtiva", move |env| {
            let st = s4.clone();
            Box::pin(async move {
                handler_regra_ativa(st.transferencia.as_ref(), st.audit.as_ref(), env).await
            })
        })
        .route("GetConfigTransferencia", move |env| {
            let st = s5.clone();
            Box::pin(async move {
                handler_obter_config(st.transferencia.as_ref(), st.config_cache.as_ref(), env).await
            })
        })
        .route("SetSinaisTransferencia", move |env| {
            let st = s6.clone();
            Box::pin(async move {
                handler_definir_sinais(
                    st.transferencia.as_ref(),
                    st.audit.as_ref(),
                    st.config_cache.as_ref(),
                    env,
                )
                .await
            })
        })
        .route("ListTransferencias", move |env| {
            let st = s7.clone();
            Box::pin(
                async move { handler_listar_transferencias(st.transferencia.as_ref(), env).await },
            )
        })
        .route("GerarSugestoesTransferencia", move |env| {
            let st = s8.clone();
            Box::pin(async move {
                handler_gerar_sugestoes(st.transferencia.as_ref(), st.audit.as_ref(), env).await
            })
        })
        .route("RegistrarDecisaoIa", move |env| {
            let st = s9.clone();
            Box::pin(async move { handler_registrar_decisao(st.transferencia.as_ref(), env).await })
        })
        .route("PurgarDecisoesIa", move |env| {
            let st = s10.clone();
            Box::pin(async move { handler_purgar_decisoes(st.transferencia.as_ref(), env).await })
        })
        .route("DefinirMotorTenant", move |env| {
            let st = s11.clone();
            Box::pin(async move {
                handler_definir_motor(st.transferencia.as_ref(), st.audit.as_ref(), env).await
            })
        })
        .route("PersistMessage", move |env| {
            let st = s12.clone();
            Box::pin(async move { persistir_com_motor(&st, env).await })
        })
        .route("ObterRodadasColeta", move |env| {
            let st = s13.clone();
            Box::pin(async move { handler_obter_rodadas(st.transferencia.as_ref(), env).await })
        })
        .route("RegistrarRodadaColeta", move |env| {
            let st = s14.clone();
            Box::pin(async move {
                handler_registrar_rodada(st.transferencia.as_ref(), st.audit.as_ref(), env).await
            })
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ports::{MockAuditPort, MockTransferenciaStore};
    use contracts::MessageKind;

    fn envelope(metodo: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: metodo.to_string(),
            tenant_id: Uuid::now_v7().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            auth_user_id: 7,
            auth_scopes: vec!["configuracoes:write".into()],
            ..Default::default()
        }
    }

    fn corpo(env: &Envelope) -> serde_json::Value {
        serde_json::from_slice(&env.payload).unwrap_or_default()
    }

    #[test]
    fn sinais_mostram_os_cinco_com_padroes() {
        let s = sinais_com_padroes(&serde_json::json!({ "irritacao": { "ativo": false } }));
        assert_eq!(s.len(), 5);
        assert_eq!(s[0]["nome"], "pede_humano");
        assert_eq!(s[0]["ativo"], true);
        assert_eq!(s[1]["ativo"], false);
        assert_eq!(s[3]["ativo"], false);
    }

    #[tokio::test]
    async fn criar_regra_invalida_nao_chega_ao_banco() {
        let store = MockTransferenciaStore::new();
        let audit = MockAuditPort::new();
        let env = envelope(
            "SalvarRegraTransferencia",
            serde_json::json!({ "nome": "x", "condicao": "curta" }),
        );
        let resp = handler_salvar_regra(&store, &audit, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn criar_regra_audita_sem_texto_da_conversa() {
        let mut store = MockTransferenciaStore::new();
        store.expect_criar_regra().returning(|_, d, _| {
            Ok(Ok(RegraTransferencia {
                id: 9,
                nome: d.nome,
                gatilho_tipo: d.gatilho_tipo,
                ..Default::default()
            }))
        });
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, evento, _, ctx| evento == "transferencia_regra.criada" && ctx["id"] == 9)
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope(
            "SalvarRegraTransferencia",
            serde_json::json!({ "nome": "Fechar pedido", "condicao": "o cliente quer fechar o pedido" }),
        );
        let resp = handler_salvar_regra(&store, &audit, env).await;
        assert_eq!(corpo(&resp)["regra"]["id"], 9);
    }

    #[tokio::test]
    async fn desativar_exige_o_nome() {
        let mut store = MockTransferenciaStore::new();
        store.expect_obter_regra().returning(|_, _| {
            Ok(Some(RegraTransferencia {
                id: 3,
                nome: "Fechar pedido".into(),
                ativa: true,
                ..Default::default()
            }))
        });
        let audit = MockAuditPort::new();
        let env = envelope(
            "SetRegraTransferenciaAtiva",
            serde_json::json!({ "id": 3, "ativa": false, "confirmar": "outra" }),
        );
        let resp = handler_regra_ativa(&store, &audit, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn motor_so_pelo_superusuario() {
        let store = MockTransferenciaStore::new();
        let audit = MockAuditPort::new();
        let env = envelope(
            "DefinirMotorTenant",
            serde_json::json!({ "tenant_id": Uuid::now_v7().to_string(), "motor": "jev" }),
        );
        let resp = handler_definir_motor(&store, &audit, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn motor_trocado_e_auditado() {
        let mut store = MockTransferenciaStore::new();
        store
            .expect_definir_motor()
            .returning(|_, _| Ok(Some("llm".into())));
        let alvo = Uuid::now_v7().to_string();
        let alvo_auditoria = alvo.clone();
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(move |env, evento, _, ctx| {
                evento == "tenant_config.motor_alterado"
                    && ctx["depois"] == "jev"
                    && env.tenant_id == alvo_auditoria
                    && env.auth_user_id == 7
            })
            .times(1)
            .returning(|_, _, _, _| ());
        let mut env = envelope(
            "DefinirMotorTenant",
            serde_json::json!({ "tenant_id": alvo, "motor": "jev" }),
        );
        env.auth_is_superuser = true;
        let resp = handler_definir_motor(&store, &audit, env).await;
        assert_eq!(corpo(&resp)["anterior"], "llm");
        assert_eq!(corpo(&resp)["atual"], "jev");
    }

    #[tokio::test]
    async fn decisao_invalida_e_recusada() {
        let store = MockTransferenciaStore::new();
        let env = envelope(
            "RegistrarDecisaoIa",
            serde_json::json!({ "etapa": "x", "motor": "jev" }),
        );
        let resp = handler_registrar_decisao(&store, env).await;
        assert_eq!(resp.kind, MessageKind::Error as i32);
    }

    #[tokio::test]
    async fn rodada_de_coleta_soma_e_audita_so_os_slugs() {
        let mut store = MockTransferenciaStore::new();
        store
            .expect_registrar_rodada_coleta()
            .withf(|_, atendimento| *atendimento == 42)
            .times(1)
            .returning(|_, _| Ok(Some(1)));
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, evento, _, ctx| {
                evento == "atendimento.coleta_rodada"
                    && ctx["rodada"] == 1
                    && ctx["campos"] == serde_json::json!(["quantidade", "arte"])
            })
            .times(1)
            .returning(|_, _, _, _| ());
        let env = envelope(
            "RegistrarRodadaColeta",
            serde_json::json!({ "atendimento_id": 42, "campos": ["quantidade", "arte"] }),
        );
        let resp = handler_registrar_rodada(&store, &audit, env).await;
        assert_eq!(corpo(&resp)["rodadas"], 1);
    }

    #[tokio::test]
    async fn rodadas_exigem_atendimento_e_leem_do_store() {
        let mut store = MockTransferenciaStore::new();
        store
            .expect_rodadas_coleta()
            .times(1)
            .returning(|_, _| Ok(2));
        let sem = handler_obter_rodadas(
            &store,
            envelope("ObterRodadasColeta", serde_json::json!({})),
        )
        .await;
        assert_eq!(sem.kind, MessageKind::Error as i32);
        let resp = handler_obter_rodadas(
            &store,
            envelope(
                "ObterRodadasColeta",
                serde_json::json!({ "atendimento_id": 5 }),
            ),
        )
        .await;
        assert_eq!(corpo(&resp)["rodadas"], 2);
        let mut vazio = MockTransferenciaStore::new();
        vazio
            .expect_registrar_rodada_coleta()
            .returning(|_, _| Ok(None));
        let audit = MockAuditPort::new();
        let nao_achou = handler_registrar_rodada(
            &vazio,
            &audit,
            envelope(
                "RegistrarRodadaColeta",
                serde_json::json!({ "atendimento_id": 5 }),
            ),
        )
        .await;
        assert_eq!(nao_achou.kind, MessageKind::Error as i32);
    }
}
