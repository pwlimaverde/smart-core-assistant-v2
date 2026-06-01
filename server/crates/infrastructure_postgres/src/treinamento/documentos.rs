use async_trait::async_trait;
use chrono::{DateTime, Utc};
use pgvector::Vector;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Documento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub treinamento_id: i32,
    pub conteudo: Option<String>,
    pub metadata: serde_json::Value,
    pub ordem: i32,
    pub data_criacao: DateTime<Utc>,
}

#[async_trait]
pub trait DocumentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: Option<&str>,
        embedding: Option<Vec<f32>>,
        ordem: i32,
        metadata: serde_json::Value,
    ) -> Result<Documento, DbError>;

    /// Busca documentos similares usando distância de cosseno (pgvector <=>).
    /// Filtro duplo: tenant_id explícito + RLS ativo. Índice HNSW vector_cosine_ops.
    async fn buscar_documentos_similares(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        tenant_id: Uuid,
        query_embedding: Vec<f32>,
        top_k: i64,
        distance_threshold: f64,
    ) -> Result<Vec<(Documento, f64)>, DbError>;
}

pub struct PostgresDocumentoRepository;

#[async_trait]
impl DocumentoRepository for PostgresDocumentoRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: Option<&str>,
        embedding: Option<Vec<f32>>,
        ordem: i32,
        metadata: serde_json::Value,
    ) -> Result<Documento, DbError> {
        if !ctx.has_permission("treinamento:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let vec = embedding.map(Vector::from);
        let row = sqlx::query!(
            r#"INSERT INTO oraculo_documento
                   (tenant_id, treinamento_id, conteudo, embedding, ordem, metadata)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, treinamento_id, conteudo, metadata, ordem, data_criacao"#,
            ctx.tenant_id,
            treinamento_id,
            conteudo,
            vec as _,
            ordem,
            metadata
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(Documento {
            id: row.id,
            tenant_id: row.tenant_id,
            treinamento_id: row.treinamento_id,
            conteudo: row.conteudo,
            metadata: row.metadata,
            ordem: row.ordem,
            data_criacao: row.data_criacao,
        })
    }

    async fn buscar_documentos_similares(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        tenant_id: Uuid,
        query_embedding: Vec<f32>,
        top_k: i64,
        distance_threshold: f64,
    ) -> Result<Vec<(Documento, f64)>, DbError> {
        let query_vector = Vector::from(query_embedding);

        let rows = sqlx::query!(
            r#"
            SELECT d.id, d.tenant_id, d.treinamento_id, d.conteudo,
                   d.metadata, d.ordem, d.data_criacao,
                   (d.embedding <=> $1) AS "distancia!"
            FROM oraculo_documento d
            INNER JOIN oraculo_treinamento t ON d.treinamento_id = t.id
            WHERE d.tenant_id = $2
              AND t.treinamento_finalizado = true
              AND d.embedding IS NOT NULL
              AND (d.embedding <=> $1) <= $3
            ORDER BY d.embedding <=> $1
            LIMIT $4
            "#,
            query_vector as _,
            tenant_id,
            distance_threshold,
            top_k
        )
        .fetch_all(&mut **tx)
        .await?;

        let result = rows
            .into_iter()
            .map(|r| {
                (
                    Documento {
                        id: r.id,
                        tenant_id: r.tenant_id,
                        treinamento_id: r.treinamento_id,
                        conteudo: r.conteudo,
                        metadata: r.metadata,
                        ordem: r.ordem,
                        data_criacao: r.data_criacao,
                    },
                    r.distancia,
                )
            })
            .collect();
        Ok(result)
    }
}
