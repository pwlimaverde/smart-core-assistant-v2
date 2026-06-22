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
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::AtendimentoStore;

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
}
