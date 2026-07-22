//! Adapter concreto do domínio Atendimento: reusa os repositórios de mensagens e
//! atendimentos de infrastructure_postgres e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::atendimentos::atendimentos::{
    Atendimento, AtendimentoRepository, PostgresAtendimentoRepository,
};
use infrastructure_postgres::atendimentos::campos::{
    CampoPersonalizadoRepository, PostgresCampoPersonalizadoRepository,
    PostgresValorCampoRepository, ValorCampoRepository,
};
use infrastructure_postgres::atendimentos::mensagens::{
    DestinoEnvioOutbound, Mensagem, MensagemRepository, PostgresMensagemRepository,
};
use infrastructure_postgres::atendimentos::movimentos::{
    MovimentoFluxoRepository, PostgresMovimentoFluxoRepository,
};
use infrastructure_postgres::clientes::contatos::{ContatoRepository, PostgresContatoRepository};
use infrastructure_postgres::operacional::fluxos::{
    EtapaFluxoRepository, FluxoAtendimentoRepository, FluxoDisponivel,
    PostgresEtapaFluxoRepository, PostgresFluxoAtendimentoRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::{
    AtendimentoStore, CampoColetadoDto, CampoPendenteDto, CamposAtendimentoDto,
    TicketKanbanOutcome, TransferenciaFluxoOutcome,
};

/// Implementação Postgres da port Atendimento.
/// `admin_pool` (BYPASSRLS) é usado apenas nas varreduras cross-tenant do
/// scheduler do worker (F4.3b); quando ausente, recai no pool de aplicação
/// (RLS ativa, resultado vazio) com aviso observável — mesmo padrão de
/// `PgWhatsappStore::admin_listar_conectadas`.
#[derive(Clone)]
pub struct PgAtendimentoStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgAtendimentoStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }
}

#[async_trait]
impl AtendimentoStore for PgAtendimentoStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn listar_mensagens(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let mensagens = repo
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id, limit, offset)
                .await?;
            Ok((mensagens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, status = status))]
    async fn listar_atendimentos(
        &self,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let status = status.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let atendimentos = repo
                .listar_por_status(&mut tx, &ctx, &status, departamento_id, limit)
                .await?;
            Ok((atendimentos, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn persistir_mensagem(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        traceparent: &str,
    ) -> Result<Mensagem, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let tipo = tipo.to_string();
        let conteudo = conteudo.to_string();
        let remetente = remetente.to_string();
        let traceparent = traceparent.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let msg = repo
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    &tipo,
                    &conteudo,
                    &remetente,
                    None,
                    None,
                )
                .await?;

            let repo_atendimento = PostgresAtendimentoRepository;
            repo_atendimento.touch_last_message(&mut tx, &ctx, atendimento_id).await?;

            // Padrão OUTBOX: insere o evento de domínio na MESMA transação ACID.
            let event_payload = serde_json::json!({
                "message_id": msg.id.to_string(),
                "sender_id": msg.remetente,
                "content": msg.conteudo,
                "timestamp": msg.timestamp.timestamp_millis(),
            });
            let event_payload_bytes = serde_json::to_vec(&event_payload)
                .map_err(|e| DbError::ConfigError(e.to_string()))?;

            sqlx::query(
                "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4)",
            )
            .bind(tenant_id)
            .bind("message.persisted")
            .bind(event_payload_bytes)
            .bind(&traceparent)
            .execute(&mut *tx)
            .await?;

            Ok((msg, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, telefone = %telefone))]
    async fn resolver_atendimento_para_contato(
        &self,
        ctx: &RequestContext,
        telefone: &str,
        push_name: Option<String>,
    ) -> Result<(i32, Atendimento, bool), DbError> {
        let repo_contato = PostgresContatoRepository;
        let repo_atendimento = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let telefone = telefone.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // 1. Busca ou cria o contato
            let contato = match repo_contato
                .buscar_por_telefone(&mut tx, &ctx, &telefone)
                .await?
            {
                Some(c) => c,
                None => {
                    repo_contato
                        .salvar(&mut tx, &ctx, &telefone, push_name.as_deref())
                        .await?
                }
            };

            let mut is_new = false;
            // 2. Busca se já existe um atendimento ativo para o contato
            let atendimento = match repo_atendimento
                .buscar_ativo_por_contato(&mut tx, &ctx, contato.id)
                .await?
            {
                Some(a) => a,
                None => {
                    is_new = true;
                    // Cria um novo atendimento
                    repo_atendimento
                        .criar(&mut tx, &ctx, contato.id, None, None, None)
                        .await?
                }
            };

            Ok(((contato.id, atendimento, is_new), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, message_id_whatsapp = %message_id_whatsapp, status = %status))]
    async fn atualizar_status_mensagem(
        &self,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
        status: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let message_id_whatsapp = message_id_whatsapp.to_string();
        let status = status.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_status_por_whatsapp_id(&mut tx, &ctx, &message_id_whatsapp, &status)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn aplicar_politica_ticket_kanban(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<TicketKanbanOutcome, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_fluxo = PostgresFluxoAtendimentoRepository;
        let repo_etapa = PostgresEtapaFluxoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let atendimento = match repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
            {
                Some(a) => a,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: "desconhecido".to_string(),
                        reason: Some("atendimento_inexistente".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Idempotência: se já está numa etapa, não move de novo.
            if atendimento.etapa_atual_id.is_some() {
                let outcome = TicketKanbanOutcome {
                    status: atendimento.status.clone(),
                    fluxo_id: atendimento.fluxo_atendimento_id,
                    etapa_id: atendimento.etapa_atual_id,
                    reason: Some("ja_posicionado".to_string()),
                    ..Default::default()
                };
                return Ok((outcome, tx));
            }

            // Resolve o fluxo: o do atendimento (se houver) ou o primeiro ativo do tenant.
            let fluxo = match atendimento.fluxo_atendimento_id {
                Some(fid) => repo_fluxo.buscar_por_id(&mut tx, &ctx, fid).await?,
                None => repo_fluxo.buscar_primeiro_ativo(&mut tx, &ctx).await?,
            };
            let fluxo = match fluxo {
                Some(f) => f,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: atendimento.status.clone(),
                        reason: Some("sem_fluxo".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Etapa de entrada (tipo 'fila') do fluxo.
            let etapa = match repo_etapa
                .get_etapa_inicial(&mut tx, &ctx, fluxo.id)
                .await?
            {
                Some(e) => e,
                None => {
                    let outcome = TicketKanbanOutcome {
                        status: atendimento.status.clone(),
                        fluxo_id: Some(fluxo.id),
                        reason: Some("sem_etapa_inicial".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Posiciona o atendimento e registra o movimento automático de entrada.
            repo_atendimento
                .atribuir_fluxo_etapa(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    fluxo.id,
                    Some(fluxo.departamento_id),
                    etapa.id,
                )
                .await?;
            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    None,
                    etapa.id,
                    None,
                    Some("entrada automática no fluxo"),
                    true,
                )
                .await?;

            let outcome = TicketKanbanOutcome {
                moved: true,
                status: "fila".to_string(),
                etapa_id: Some(etapa.id),
                etapa_nome: Some(etapa.nome),
                fluxo_id: Some(fluxo.id),
                reason: None,
            };
            Ok((outcome, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, etapa_destino_id = etapa_destino_id))]
    async fn mover_etapa_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_destino_id: i32,
        motivo: &str,
    ) -> Result<(), DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let motivo = (!motivo.is_empty()).then(|| motivo.to_string());
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let atendimento = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .ok_or(DbError::NotFound)?;

            // RBAC fino por fluxo (WS-5a): só quem tem flow_permission do fluxo atual
            // do atendimento (ou bypass kanban:admin/tenant:admin) pode movê-lo.
            if let Some(fluxo_id) = atendimento.fluxo_atendimento_id {
                ctx.exigir_fluxo(fluxo_id)?;
            }

            let etapa_origem_id = atendimento.etapa_atual_id;

            repo_atendimento
                .atualizar_etapa(&mut tx, &ctx, atendimento_id, etapa_destino_id, None)
                .await?;

            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    etapa_origem_id,
                    etapa_destino_id,
                    None,
                    motivo.as_deref(),
                    false,
                )
                .await?;

            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(limite = limite, ttl_horas = ttl_horas))]
    async fn listar_feedback_vencido(
        &self,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_feedback_vencido sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 varredura cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresAtendimentoRepository;
        let mut tx = effective_pool.begin().await?;
        let rows = repo
            .listar_feedback_vencido(&mut tx, ctx, limite, ttl_horas)
            .await?;
        tx.commit().await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn marcar_feedback_expirado(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_feedback_expirado(&mut tx, &ctx, atendimento_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(limite = limite, idade_max_dias = idade_max_dias))]
    async fn listar_midias_expiradas(
        &self,
        ctx: &RequestContext,
        limite: i64,
        idade_max_dias: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_midias_expiradas sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 varredura cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresMensagemRepository;
        let mut tx = effective_pool.begin().await?;
        let rows = repo
            .listar_midias_expiradas(&mut tx, ctx, limite, idade_max_dias)
            .await?;
        tx.commit().await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_midia_purgada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_midia_purgada(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn resolver_destino_envio_outbound(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<Option<DestinoEnvioOutbound>, DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let destino = repo
                .resolver_destino_envio_outbound(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok((destino, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_enviada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        message_id_whatsapp: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let message_id_whatsapp = message_id_whatsapp.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_mensagem_enviada(&mut tx, &ctx, mensagem_id, &message_id_whatsapp)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_falha_envio(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.marcar_mensagem_falha_envio(&mut tx, &ctx, mensagem_id)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn anexar_analise_midia(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        arquivo_midia: &str,
        analise_midia: &str,
        resumo_midia: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresMensagemRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        // String vazia = campo ausente; converte para `None` (não sobrescreve).
        let arquivo = (!arquivo_midia.is_empty()).then(|| arquivo_midia.to_string());
        let analise = (!analise_midia.is_empty()).then(|| analise_midia.to_string());
        let resumo = (!resumo_midia.is_empty()).then(|| resumo_midia.to_string());
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.anexar_analise_midia(
                &mut tx,
                &ctx,
                mensagem_id,
                arquivo.as_deref(),
                analise.as_deref(),
                resumo.as_deref(),
            )
            .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_fluxos_do_tenant(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoDisponivel>, DbError> {
        let repo = PostgresFluxoAtendimentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let fluxos = repo.listar_ativos_do_tenant(&mut tx, &ctx).await?;
            Ok((fluxos, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, fluxo_id = fluxo_id))]
    async fn transferir_atendimento_para_fluxo(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
    ) -> Result<TransferenciaFluxoOutcome, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_fluxo = PostgresFluxoAtendimentoRepository;
        let repo_etapa = PostgresEtapaFluxoRepository;
        let repo_movimento = PostgresMovimentoFluxoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // Fluxo destino precisa existir e estar ativo.
            let fluxo = match repo_fluxo.buscar_por_id(&mut tx, &ctx, fluxo_id).await? {
                Some(f) if f.ativo => f,
                _ => {
                    let outcome = TransferenciaFluxoOutcome {
                        reason: Some("fluxo_inexistente".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            // Etapa de entrada (tipo 'fila') do fluxo destino.
            let etapa = match repo_etapa
                .get_etapa_inicial(&mut tx, &ctx, fluxo.id)
                .await?
            {
                Some(e) => e,
                None => {
                    let outcome = TransferenciaFluxoOutcome {
                        fluxo_id: Some(fluxo.id),
                        fluxo_nome: Some(fluxo.nome),
                        reason: Some("sem_etapa_inicial".to_string()),
                        ..Default::default()
                    };
                    return Ok((outcome, tx));
                }
            };

            let etapa_origem = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .and_then(|a| a.etapa_atual_id);

            repo_atendimento
                .transferir_fluxo_etapa(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    fluxo.id,
                    fluxo.departamento_id,
                    etapa.id,
                )
                .await?;
            repo_movimento
                .criar(
                    &mut tx,
                    &ctx,
                    atendimento_id,
                    etapa_origem,
                    etapa.id,
                    None,
                    Some("transferência automática pela IA"),
                    true,
                )
                .await?;

            let outcome = TransferenciaFluxoOutcome {
                transferido: true,
                fluxo_id: Some(fluxo.id),
                fluxo_nome: Some(fluxo.nome),
                etapa_id: Some(etapa.id),
                etapa_nome: Some(etapa.nome),
                reason: None,
            };
            Ok((outcome, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn resolver_campos_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<CamposAtendimentoDto, DbError> {
        let repo_atendimento = PostgresAtendimentoRepository;
        let repo_campo = PostgresCampoPersonalizadoRepository;
        let repo_valor = PostgresValorCampoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let fluxo_id = repo_atendimento
                .buscar_por_id(&mut tx, &ctx, atendimento_id)
                .await?
                .and_then(|a| a.fluxo_atendimento_id);

            // Catálogo aplicável: globais (sem filtro de fluxo) + os do fluxo atual
            // do atendimento, quando houver.
            let mut definicoes = repo_campo
                .listar_por_escopo(&mut tx, &ctx, "GLOBAL", None)
                .await?;
            if let Some(fluxo_id) = fluxo_id {
                definicoes.extend(
                    repo_campo
                        .listar_por_escopo(&mut tx, &ctx, "FLUXO", Some(fluxo_id))
                        .await?,
                );
            }

            let valores = repo_valor
                .listar_por_atendimento(&mut tx, &ctx, atendimento_id)
                .await?;

            let mut coletados = Vec::new();
            let mut pendentes = Vec::new();
            for def in definicoes {
                let valor_existente = valores.iter().find(|v| v.campo_id == def.id);
                match valor_existente {
                    Some(v) => coletados.push(CampoColetadoDto {
                        slug: def.slug,
                        nome: def.nome,
                        // O valor é JSONB livre; string "crua" evita aspas duplas
                        // indevidas quando já é uma string JSON.
                        valor: v
                            .valor
                            .as_str()
                            .map(str::to_string)
                            .unwrap_or_else(|| v.valor.to_string()),
                    }),
                    None if def.obrigatorio => pendentes.push(CampoPendenteDto {
                        slug: def.slug,
                        nome: def.nome,
                        descricao: def.descricao,
                        hint: def.extrair_hint,
                    }),
                    None => {}
                }
            }

            Ok((
                CamposAtendimentoDto {
                    coletados,
                    pendentes,
                },
                tx,
            ))
        })
        .await
    }
}
