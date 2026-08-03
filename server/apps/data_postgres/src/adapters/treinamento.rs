//! Adapter concreto do domínio Treinamento/RAG: reusa os repositórios de busca
//! vetorial de `infrastructure_postgres` e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::treinamento::documentos::{
    DocumentoRepository, PostgresDocumentoRepository,
};
use infrastructure_postgres::treinamento::query_compose::{
    PostgresQueryComposeRepository, QueryComposeRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use infrastructure_postgres::treinamento::treinamentos::{
    PostgresTreinamentoRepository, Treinamento, TreinamentoRepository,
};

use crate::ports::{DocumentoTrecho, QueryComposeResultado, TreinamentoResumo, TreinamentoStore};

/// Converte a linha do repositório na forma que atravessa o RPC.
///
/// `conteudo` vira string vazia quando nulo: do lado do cliente "sem conteúdo"
/// e "conteúdo vazio" são a mesma coisa, e um opcional a mais no contrato só
/// daria trabalho a quem consome.
fn resumo(t: Treinamento) -> TreinamentoResumo {
    TreinamentoResumo {
        id: t.id,
        tag: t.tag,
        grupo: t.grupo,
        conteudo: t.conteudo.unwrap_or_default(),
        finalizado: t.treinamento_finalizado,
        vetorizado: t.treinamento_vetorizado,
        criado_em: t.data_criacao.timestamp_millis(),
        atualizado_em: t.data_atualizacao.timestamp_millis(),
    }
}

/// Implementação Postgres da port Treinamento/RAG. Tenant-scoped (RLS ativa via
/// `run_in_tenant_transaction`) — ao contrário das varreduras cross-tenant do
/// scheduler, aqui o `tenant_id` do chamador (worker, em nome do tenant da
/// conversa) já basta, sem precisar de `admin_pool`.
#[derive(Clone)]
pub struct PgTreinamentoStore {
    pub pool: PgPool,
}

impl PgTreinamentoStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl TreinamentoStore for PgTreinamentoStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, chunk_top_k = chunk_top_k))]
    async fn query_compose(
        &self,
        ctx: &RequestContext,
        query_embedding: Vec<f32>,
        distance_threshold: f64,
        chunk_top_k: i64,
    ) -> Result<QueryComposeResultado, DbError> {
        let query_compose_repo = PostgresQueryComposeRepository;
        let documento_repo = PostgresDocumentoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let comportamento = query_compose_repo
                .buscar_comportamento_similar(
                    &mut tx,
                    tenant_id,
                    query_embedding.clone(),
                    distance_threshold,
                )
                .await?;
            let documentos = documento_repo
                .buscar_documentos_similares(
                    &mut tx,
                    tenant_id,
                    query_embedding,
                    chunk_top_k,
                    distance_threshold,
                )
                .await?
                .into_iter()
                .map(|(doc, distancia)| DocumentoTrecho {
                    conteudo: doc.conteudo,
                    distancia,
                })
                .collect();
            let resultado = QueryComposeResultado {
                comportamento,
                documentos,
            };
            Ok((resultado, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, tag = %tag))]
    async fn criar_treinamento(
        &self,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: &str,
    ) -> Result<TreinamentoResumo, DbError> {
        let repo = PostgresTreinamentoRepository;
        let ctx = ctx.clone();
        let (tag, grupo, conteudo) = (tag.to_string(), grupo.to_string(), conteudo.to_string());

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let t = repo
                .criar(&mut tx, &ctx, &tag, &grupo, Some(&conteudo))
                .await?;
            Ok((resumo(t), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_treinamentos(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<TreinamentoResumo>, DbError> {
        let repo = PostgresTreinamentoRepository;
        let ctx = ctx.clone();

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let linhas = repo.listar_por_tenant(&mut tx, &ctx).await?;
            Ok((linhas.into_iter().map(resumo).collect(), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn obter_treinamento(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<TreinamentoResumo>, DbError> {
        let repo = PostgresTreinamentoRepository;
        let ctx = ctx.clone();

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let achado = repo.buscar_por_id(&mut tx, &ctx, id).await?;
            Ok((achado.map(resumo), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn finalizar_treinamento(
        &self,
        ctx: &RequestContext,
        id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError> {
        let repo = PostgresTreinamentoRepository;
        let ctx = ctx.clone();
        let conteudo = conteudo.to_string();

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            // Gravar o texto revisado e finalizar são um ato só: finalizar é o
            // que põe o treinamento na fila de vetorização, e vetorizar o texto
            // antigo seria pior do que não vetorizar.
            let atualizou = repo
                .atualizar_conteudo(&mut tx, &ctx, id, &conteudo)
                .await?;
            if atualizou {
                repo.marcar_finalizado(&mut tx, &ctx, id).await?;
            }
            Ok((atualizou, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn remover_treinamento(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError> {
        let repo = PostgresTreinamentoRepository;
        let ctx = ctx.clone();

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let removeu = repo.remover(&mut tx, &ctx, id).await?;
            Ok((removeu, tx))
        })
        .await
    }
}
