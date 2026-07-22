use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Atendimento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub contato_id: i32,
    pub departamento_id: Option<i32>,
    pub fluxo_atendimento_id: Option<i32>,
    pub status: String,
    pub etapa_atual_id: Option<i32>,
    pub data_inicio: DateTime<Utc>,
    pub data_fim: Option<DateTime<Utc>>,
    pub data_ultima_mensagem: Option<DateTime<Utc>>,
    pub assunto: Option<String>,
    pub prioridade: String,
    pub atendente_humano_id: Option<i32>,
    pub contexto_conversa: serde_json::Value,
    pub historico_status: serde_json::Value,
    pub tags: serde_json::Value,
    pub avaliacao: Option<i32>,
    pub feedback: Option<String>,
    pub data_primeira_resposta: Option<DateTime<Utc>>,
    pub bot_pode_atender: bool,
}

#[async_trait]
pub trait AtendimentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
        etapa_inicial_id: Option<i32>,
    ) -> Result<Atendimento, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendimento>, DbError>;

    async fn listar_por_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: &str,
    ) -> Result<(), DbError>;

    async fn atualizar_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_id: i32,
        atendente_id: Option<i32>,
    ) -> Result<(), DbError>;

    async fn assumir_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<(), DbError>;

    async fn touch_last_message(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    async fn buscar_ativo_por_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<Option<Atendimento>, DbError>;

    /// Posiciona o atendimento na etapa inicial do Kanban, atribuindo fluxo e
    /// departamento padrão quando ainda ausentes e marcando o status como 'fila'.
    /// Usado pela política de ticket/Kanban (WS-2.4).
    async fn atribuir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: Option<i32>,
        etapa_id: i32,
    ) -> Result<(), DbError>;

    /// Transfere o atendimento para outro fluxo (N6.3): SOBRESCREVE fluxo/departamento/
    /// etapa (diferente de `atribuir_fluxo_etapa`, que preserva o fluxo já definido via
    /// COALESCE). Usado pela transferência automática decidida pela IA.
    async fn transferir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: i32,
        etapa_id: i32,
    ) -> Result<(), DbError>;

    /// Atualiza a última leitura de sentimento do atendimento (N6.5, best-effort —
    /// não é `avaliacao`/`feedback` de satisfação do cliente, é a análise da IA
    /// sobre o tom da conversa). Sobrescreve sempre com a leitura mais recente.
    async fn atualizar_sentimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError>;

    /// Varredura CROSS-TENANT (scheduler do worker, F4.3b): atendimentos resolvidos,
    /// sem feedback registrado e ainda não marcados como expirados, cuja `data_fim`
    /// ultrapassou o TTL. `ctx` é usado apenas para a checagem de escopo — a consulta
    /// não filtra por tenant (exige pool com BYPASSRLS).
    async fn listar_feedback_vencido(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    /// Marca o atendimento como tendo o feedback expirado (idempotente: chamada
    /// futura para o mesmo id é no-op pois `feedback_expirado_em` já estará setado
    /// e o `listar_feedback_vencido` não o retornará de novo).
    async fn marcar_feedback_expirado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;
}

pub struct PostgresAtendimentoRepository;

#[async_trait]
impl AtendimentoRepository for PostgresAtendimentoRepository {
    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
        etapa_inicial_id: Option<i32>,
    ) -> Result<Atendimento, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Atendimento,
            r#"INSERT INTO oraculo_atendimento
                   (tenant_id, contato_id, departamento_id, fluxo_atendimento_id, etapa_atual_id)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                         status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                         assunto, prioridade, atendente_humano_id, contexto_conversa,
                         historico_status, tags, avaliacao, feedback,
                         data_primeira_resposta, bot_pode_atender"#,
            ctx.tenant_id,
            contato_id,
            departamento_id,
            fluxo_id,
            etapa_inicial_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendimento>, DbError> {
        let row = sqlx::query_as!(
            Atendimento,
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(status = %status, limit = limit))]
    async fn listar_por_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Atendimento,
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND status = $2
                 AND ($3::int IS NULL OR departamento_id = $3)
               ORDER BY data_inicio DESC
               LIMIT $4"#,
            ctx.tenant_id,
            status,
            departamento_id,
            limit
        )
        .fetch_all(&mut **tx)
        .await?;

        // RBAC fino por fluxo (WS-5a): atendimentos já roteados a um fluxo Kanban só
        // aparecem para quem tem flow_permission (ou bypass kanban:admin/tenant:admin).
        // Sem fluxo atribuído ainda (pré-roteamento) permanece visível a todos com escopo.
        let visiveis = rows
            .into_iter()
            .filter(|a| match a.fluxo_atendimento_id {
                Some(fluxo_id) => ctx.has_flow_permission(fluxo_id),
                None => true,
            })
            .collect();
        Ok(visiveis)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, novo_status = %novo_status))]
    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: &str,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET status = $1::text,
                   data_fim = CASE WHEN $1::text IN ('resolvido','cancelado','arquivado')
                                   THEN NOW() ELSE data_fim END
               WHERE tenant_id = $2 AND id = $3"#,
            novo_status,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etapa_id = etapa_id))]
    async fn atualizar_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_id: i32,
        atendente_id: Option<i32>,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET etapa_atual_id = $1,
                   atendente_humano_id = COALESCE($2, atendente_humano_id)
               WHERE tenant_id = $3 AND id = $4"#,
            etapa_id,
            atendente_id,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, atendente_id = atendente_id))]
    async fn assumir_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Desliga o bot e atribui o atendente humano
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET atendente_humano_id = $1,
                   bot_pode_atender = false,
                   status = 'em_atendimento'
               WHERE tenant_id = $2 AND id = $3"#,
            atendente_id,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn touch_last_message(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET data_ultima_mensagem = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn buscar_ativo_por_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<Option<Atendimento>, DbError> {
        let row = sqlx::query_as::<_, Atendimento>(
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND contato_id = $2 
                 AND status NOT IN ('resolvido', 'cancelado', 'arquivado')
               LIMIT 1"#,
        )
        .bind(ctx.tenant_id)
        .bind(contato_id)
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, fluxo_id = fluxo_id, etapa_id = etapa_id))]
    async fn atribuir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: Option<i32>,
        etapa_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        // COALESCE preserva fluxo/departamento já definidos; só preenche quando nulos.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET fluxo_atendimento_id = COALESCE(fluxo_atendimento_id, $1),
                   departamento_id = COALESCE(departamento_id, $2),
                   etapa_atual_id = $3,
                   status = 'fila'
               WHERE tenant_id = $4 AND id = $5"#,
        )
        .bind(fluxo_id)
        .bind(departamento_id)
        .bind(etapa_id)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, fluxo_id = fluxo_id, etapa_id = etapa_id))]
    async fn transferir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: i32,
        etapa_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        // SOBRESCREVE (sem COALESCE): a transferência muda o fluxo de fato.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET fluxo_atendimento_id = $1,
                   departamento_id = $2,
                   etapa_atual_id = $3,
                   status = 'fila'
               WHERE tenant_id = $4 AND id = $5"#,
        )
        .bind(fluxo_id)
        .bind(departamento_id)
        .bind(etapa_id)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, nota = nota))]
    async fn atualizar_sentimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError> {
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET sentimento_nota = $1, sentimento_label = $2
               WHERE tenant_id = $3 AND id = $4"#,
        )
        .bind(nota)
        .bind(label)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(limite = limite, ttl_horas = ttl_horas))]
    async fn listar_feedback_vencido(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS (admin_pool).
        let rows = sqlx::query_as::<_, Atendimento>(
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender
               FROM oraculo_atendimento
               WHERE status = 'resolvido'
                 AND feedback IS NULL
                 AND avaliacao IS NULL
                 AND feedback_expirado_em IS NULL
                 AND data_fim IS NOT NULL
                 AND data_fim < NOW() - ($1 || ' hours')::interval
               ORDER BY data_fim ASC
               LIMIT $2"#,
        )
        .bind(ttl_horas.to_string())
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn marcar_feedback_expirado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET feedback_expirado_em = NOW()
               WHERE tenant_id = $1 AND id = $2 AND feedback_expirado_em IS NULL"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}
