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

use crate::ports::{DocumentoTrecho, QueryComposeResultado, TreinamentoStore};

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
}
