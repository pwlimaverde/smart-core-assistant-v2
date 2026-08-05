//! Adapter concreto do domínio Treinamento/RAG: reusa os repositórios de busca
//! vetorial de `infrastructure_postgres` e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::treinamento::documentos::{
    DocumentoRepository, PostgresDocumentoRepository,
};
use infrastructure_postgres::treinamento::query_compose::{
    to_embedding_text, PostgresQueryComposeRepository, QueryComposeRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use infrastructure_postgres::treinamento::treinamentos::{
    PostgresTreinamentoRepository, Treinamento, TreinamentoRepository,
};

use crate::ports::treinamento::{
    ChunkVetorizado, DadosIntent, Intent, IntentPendente, TreinamentoPendente,
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
    /// Único pool com BYPASSRLS. Necessário para a varredura cross-tenant
    /// da fila de vetorização: no pool de runtime a RLS devolve zero linhas
    /// em silêncio, e a fila pareceria sempre vazia.
    pub admin_pool: Option<PgPool>,
}

impl PgTreinamentoStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
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

    #[tracing::instrument(skip_all, fields(limite = limite))]
    async fn listar_pendentes_vetorizacao(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<TreinamentoPendente>, DbError> {
        if self.admin_pool.is_none() {
            tracing::warn!(
                "listar_pendentes_vetorizacao sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 varredura cross-tenant e a fila virá sempre vazia"
            );
        }
        let pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let mut tx = pool.begin().await?;
        let rows = PostgresTreinamentoRepository
            .listar_pendentes_global(&mut tx, ctx, limite)
            .await?;
        tx.commit().await?;
        Ok(rows
            .into_iter()
            // Sem conteúdo não há o que vetorizar; deixar passar geraria um
            // embedding de string vazia, que casaria com qualquer pergunta.
            .filter(|t| t.conteudo.as_deref().is_some_and(|c| !c.trim().is_empty()))
            .map(|t| TreinamentoPendente {
                id: t.id,
                tenant_id: t.tenant_id.to_string(),
                tag: t.tag,
                conteudo: t.conteudo.unwrap_or_default(),
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, treinamento_id = treinamento_id, chunks = chunks.len()))]
    async fn salvar_chunks_vetorizados(
        &self,
        ctx: &RequestContext,
        treinamento_id: i32,
        chunks: Vec<ChunkVetorizado>,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let repo_doc = PostgresDocumentoRepository;
            for chunk in &chunks {
                repo_doc
                    .criar(
                        &mut tx,
                        &ctx,
                        treinamento_id,
                        Some(&chunk.conteudo),
                        Some(chunk.embedding.clone()),
                        chunk.ordem,
                        serde_json::json!({ "origem": "scheduler" }),
                    )
                    .await?;
            }
            // Marcar e gravar são um ato só: marcar sem gravar perderia o
            // material para sempre (não volta à fila), e gravar sem marcar o
            // reprocessaria a cada tick, duplicando os trechos.
            PostgresTreinamentoRepository
                .marcar_vetorizado(&mut tx, &ctx, treinamento_id)
                .await?;
            Ok((true, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(limite = limite))]
    async fn listar_intents_sem_embedding(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<IntentPendente>, DbError> {
        let pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let mut tx = pool.begin().await?;
        let rows = PostgresQueryComposeRepository
            .listar_sem_embedding_global(&mut tx, ctx, limite)
            .await?;
        tx.commit().await?;
        Ok(rows
            .into_iter()
            .map(|i| IntentPendente {
                id: i.id,
                tenant_id: i.tenant_id.to_string(),
                // O formato do texto sai daqui, não do worker: se cada ponto
                // montasse o seu, o vetor da criação e o da revetorização
                // divergiriam e a busca ficaria instável.
                texto: to_embedding_text(&i.tag, &i.descricao, &i.exemplo),
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn definir_embedding_intent(
        &self,
        ctx: &RequestContext,
        id: i32,
        embedding: Vec<f32>,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let ok = PostgresQueryComposeRepository
                .definir_embedding(&mut tx, &ctx, id, embedding)
                .await?;
            Ok((ok, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_intents(&self, ctx: &RequestContext) -> Result<Vec<Intent>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let rows = PostgresQueryComposeRepository
                .listar_por_tenant(&mut tx, &ctx)
                .await?;
            // `vetorizada` é resolvido por uma consulta só, não por linha: a
            // lista abre inteira e um SELECT por intenção seria N+1.
            let com_vetor: Vec<i32> = sqlx::query_scalar!(
                "SELECT id FROM treinamento_querycompose \
                 WHERE tenant_id = $1 AND embedding IS NOT NULL",
                ctx.tenant_id
            )
            .fetch_all(&mut *tx)
            .await?;
            let vetorizadas: std::collections::HashSet<i32> = com_vetor.into_iter().collect();

            let itens = rows
                .into_iter()
                .map(|i| Intent {
                    vetorizada: vetorizadas.contains(&i.id),
                    id: i.id,
                    tag: i.tag,
                    grupo: i.grupo,
                    descricao: i.descricao,
                    exemplo: i.exemplo,
                    comportamento: i.comportamento,
                    criado_em: i.created_at.timestamp_millis(),
                    atualizado_em: i.updated_at.timestamp_millis(),
                })
                .collect();
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, tag = %dados.tag))]
    async fn criar_intent(
        &self,
        ctx: &RequestContext,
        dados: DadosIntent,
    ) -> Result<Intent, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            // Nasce SEM embedding: gerá-lo aqui exigiria que o data_postgres
            // falasse com o ia_engine, e a porta do banco não fala com IA. O
            // scheduler pega na próxima passada.
            let criada = PostgresQueryComposeRepository
                .criar(
                    &mut tx,
                    &ctx,
                    &dados.tag,
                    &dados.grupo,
                    &dados.descricao,
                    &dados.exemplo,
                    &dados.comportamento,
                    None,
                )
                .await?;
            let intent = Intent {
                id: criada.id,
                tag: criada.tag,
                grupo: criada.grupo,
                descricao: criada.descricao,
                exemplo: criada.exemplo,
                comportamento: criada.comportamento,
                vetorizada: false,
                criado_em: criada.created_at.timestamp_millis(),
                atualizado_em: criada.updated_at.timestamp_millis(),
            };
            Ok((intent, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_intent(
        &self,
        ctx: &RequestContext,
        id: i32,
        dados: DadosIntent,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let ok = PostgresQueryComposeRepository
                .atualizar(
                    &mut tx,
                    &ctx,
                    id,
                    &dados.tag,
                    &dados.grupo,
                    &dados.descricao,
                    &dados.exemplo,
                    &dados.comportamento,
                )
                .await?;
            Ok((ok, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn remover_intent(&self, ctx: &RequestContext, id: i32) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let ok = PostgresQueryComposeRepository
                .remover(&mut tx, &ctx, id)
                .await?;
            Ok((ok, tx))
        })
        .await
    }
}
