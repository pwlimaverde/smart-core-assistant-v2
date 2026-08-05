use async_trait::async_trait;
use chrono::{DateTime, Utc};
use pgvector::Vector;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct QueryCompose {
    pub id: i32,
    pub tenant_id: Uuid,
    pub tag: String,
    pub grupo: String,
    pub descricao: String,
    pub exemplo: String,
    pub comportamento: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Gera o texto padronizado para envio à API de embeddings.
/// Concatena tag, descrição e exemplo de forma estruturada.
pub fn to_embedding_text(tag: &str, descricao: &str, exemplo: &str) -> String {
    format!("Categoria: {tag}\n{descricao}\nExemplo: {exemplo}")
}

#[async_trait]
pub trait QueryComposeRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        descricao: &str,
        exemplo: &str,
        comportamento: &str,
        embedding: Option<Vec<f32>>,
    ) -> Result<QueryCompose, DbError>;

    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<QueryCompose>, DbError>;

    /// Busca a intenção mais próxima e retorna o prompt de comportamento.
    /// Distância de cosseno (<=>), filtro por tenant_id e distance_threshold.
    async fn buscar_comportamento_similar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        tenant_id: Uuid,
        query_embedding: Vec<f32>,
        distance_threshold: f64,
    ) -> Result<Option<String>, DbError>;

    /// Atualiza a intenção. **Zera o embedding**: tag, descrição e exemplo são
    /// o texto que gerou o vetor, e manter o antigo faria a busca semântica
    /// casar pelo que a intenção era, não pelo que é.
    #[allow(clippy::too_many_arguments)]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        tag: &str,
        grupo: &str,
        descricao: &str,
        exemplo: &str,
        comportamento: &str,
    ) -> Result<bool, DbError>;

    /// Remove — aqui apagar é correto: uma intenção não tem histórico apontando
    /// para ela, e mantê-la inativa só sujaria a busca vetorial.
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

    /// Varredura CROSS-TENANT do scheduler: intenções sem vetor.
    ///
    /// Uma intenção sem embedding não é encontrada por
    /// `buscar_comportamento_similar` — existe no cadastro e não existe para a
    /// IA. Exige pool com BYPASSRLS.
    async fn listar_sem_embedding_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<QueryCompose>, DbError>;

    async fn definir_embedding(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        embedding: Vec<f32>,
    ) -> Result<bool, DbError>;
}

pub struct PostgresQueryComposeRepository;

#[async_trait]
impl QueryComposeRepository for PostgresQueryComposeRepository {
    #[tracing::instrument(skip_all, fields(tag = %tag, grupo = %grupo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        descricao: &str,
        exemplo: &str,
        comportamento: &str,
        embedding: Option<Vec<f32>>,
    ) -> Result<QueryCompose, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let vec = embedding.map(Vector::from);
        let row = sqlx::query!(
            r#"INSERT INTO treinamento_querycompose
                   (tenant_id, tag, grupo, descricao, exemplo, comportamento, embedding)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               RETURNING id, tenant_id, tag, grupo, descricao, exemplo, comportamento,
                         created_at, updated_at"#,
            ctx.tenant_id,
            tag,
            grupo,
            descricao,
            exemplo,
            comportamento,
            vec as _
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(QueryCompose {
            id: row.id,
            tenant_id: row.tenant_id,
            tag: row.tag,
            grupo: row.grupo,
            descricao: row.descricao,
            exemplo: row.exemplo,
            comportamento: row.comportamento,
            created_at: row.created_at,
            updated_at: row.updated_at,
        })
    }

    #[tracing::instrument(skip_all)]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<QueryCompose>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let rows = sqlx::query!(
            r#"SELECT id, tenant_id, tag, grupo, descricao, exemplo, comportamento,
                      created_at, updated_at
               FROM treinamento_querycompose
               WHERE tenant_id = $1
               ORDER BY created_at DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| QueryCompose {
                id: r.id,
                tenant_id: r.tenant_id,
                tag: r.tag,
                grupo: r.grupo,
                descricao: r.descricao,
                exemplo: r.exemplo,
                comportamento: r.comportamento,
                created_at: r.created_at,
                updated_at: r.updated_at,
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn buscar_comportamento_similar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        tenant_id: Uuid,
        query_embedding: Vec<f32>,
        distance_threshold: f64,
    ) -> Result<Option<String>, DbError> {
        let query_vector = Vector::from(query_embedding);

        let row = sqlx::query!(
            r#"
            SELECT comportamento
            FROM treinamento_querycompose
            WHERE tenant_id = $1
              AND embedding IS NOT NULL
              AND (embedding <=> $2) <= $3
            ORDER BY embedding <=> $2
            LIMIT 1
            "#,
            tenant_id,
            query_vector as _,
            distance_threshold
        )
        .fetch_optional(&mut **tx)
        .await?;

        Ok(row.map(|r| r.comportamento))
    }

    #[tracing::instrument(skip_all, fields(id = id, tag = %tag))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        tag: &str,
        grupo: &str,
        descricao: &str,
        exemplo: &str,
        comportamento: &str,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        // `embedding = NULL` devolve a intenção à fila de vetorização: o vetor
        // foi gerado do texto antigo, e mantê-lo faria a busca semântica casar
        // pelo que a intenção era, não pelo que é.
        let res = sqlx::query!(
            r#"UPDATE treinamento_querycompose
                  SET tag = $3, grupo = $4, descricao = $5, exemplo = $6,
                      comportamento = $7, embedding = NULL, updated_at = NOW()
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id,
            tag,
            grupo,
            descricao,
            exemplo,
            comportamento
        )
        .execute(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let res = sqlx::query!(
            "DELETE FROM treinamento_querycompose WHERE tenant_id = $1 AND id = $2",
            ctx.tenant_id,
            id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(limite = limite))]
    async fn listar_sem_embedding_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<QueryCompose>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        // Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS.
        let rows = sqlx::query_as::<
            _,
            (
                i32,
                Uuid,
                String,
                String,
                String,
                String,
                String,
                DateTime<Utc>,
                DateTime<Utc>,
            ),
        >(
            r#"SELECT id, tenant_id, tag, grupo, descricao, exemplo, comportamento,
                      created_at, updated_at
               FROM treinamento_querycompose
               WHERE embedding IS NULL
               ORDER BY created_at ASC
               LIMIT $1"#,
        )
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| QueryCompose {
                id: r.0,
                tenant_id: r.1,
                tag: r.2,
                grupo: r.3,
                descricao: r.4,
                exemplo: r.5,
                comportamento: r.6,
                created_at: r.7,
                updated_at: r.8,
            })
            .collect())
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn definir_embedding(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        embedding: Vec<f32>,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let vec = Vector::from(embedding);
        // `updated_at` fica como está: vetorizar não é edição do conteúdo, e
        // mexer nele faria a lista parecer alterada sem ninguém ter alterado.
        let res = sqlx::query!(
            "UPDATE treinamento_querycompose SET embedding = $3 WHERE tenant_id = $1 AND id = $2",
            ctx.tenant_id,
            id,
            vec as _
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }
}
