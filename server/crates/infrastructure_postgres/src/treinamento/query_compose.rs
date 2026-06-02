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
}

pub struct PostgresQueryComposeRepository;

#[async_trait]
impl QueryComposeRepository for PostgresQueryComposeRepository {
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
        if !ctx.has_permission("treinamento:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
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

    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<QueryCompose>, DbError> {
        if !ctx.has_permission("treinamento:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
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
}
