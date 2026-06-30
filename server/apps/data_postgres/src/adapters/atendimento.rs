//! Adapter concreto do domínio Atendimento: reusa os repositórios de mensagens e
//! atendimentos de infrastructure_postgres e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::atendimentos::atendimentos::{
    Atendimento, AtendimentoRepository, PostgresAtendimentoRepository,
};
use infrastructure_postgres::atendimentos::mensagens::{
    Mensagem, MensagemRepository, PostgresMensagemRepository,
};
use infrastructure_postgres::atendimentos::movimentos::{
    MovimentoFluxoRepository, PostgresMovimentoFluxoRepository,
};
use infrastructure_postgres::clientes::contatos::{ContatoRepository, PostgresContatoRepository};
use infrastructure_postgres::operacional::fluxos::{
    EtapaFluxoRepository, FluxoAtendimentoRepository, PostgresEtapaFluxoRepository,
    PostgresFluxoAtendimentoRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::{AtendimentoStore, TicketKanbanOutcome};

/// Implementação Postgres da port Atendimento.
#[derive(Clone)]
pub struct PgAtendimentoStore {
    pub pool: PgPool,
}

impl PgAtendimentoStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
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
}
