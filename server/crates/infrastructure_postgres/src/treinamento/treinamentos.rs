use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Treinamento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub tag: String,
    pub grupo: String,
    pub conteudo: Option<String>,
    pub treinamento_finalizado: bool,
    pub treinamento_vetorizado: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

#[async_trait]
pub trait TreinamentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: Option<&str>,
    ) -> Result<Treinamento, DbError>;

    async fn buscar_por_tag_grupo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
    ) -> Result<Option<Treinamento>, DbError>;

    async fn marcar_finalizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError>;

    async fn marcar_vetorizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError>;

    async fn listar_pendentes_vetorizacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError>;
}

pub struct PostgresTreinamentoRepository;

#[async_trait]
impl TreinamentoRepository for PostgresTreinamentoRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: Option<&str>,
    ) -> Result<Treinamento, DbError> {
        if !ctx.has_permission("treinamento:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            Treinamento,
            r#"INSERT INTO oraculo_treinamento (tenant_id, tag, grupo, conteudo)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, tag, grupo, conteudo,
                         treinamento_finalizado, treinamento_vetorizado,
                         data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            tag,
            grupo,
            conteudo
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn buscar_por_tag_grupo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
    ) -> Result<Option<Treinamento>, DbError> {
        let row = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1 AND tag = $2 AND grupo = $3"#,
            ctx.tenant_id,
            tag,
            grupo
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn marcar_finalizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError> {
        if !ctx.has_permission("treinamento:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        sqlx::query!(
            r#"UPDATE oraculo_treinamento
               SET treinamento_finalizado = true, data_atualizacao = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            treinamento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn marcar_vetorizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_treinamento
               SET treinamento_vetorizado = true, data_atualizacao = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            treinamento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn listar_pendentes_vetorizacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError> {
        if !ctx.has_permission("treinamento:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1
                 AND treinamento_finalizado = true AND treinamento_vetorizado = false
               ORDER BY data_criacao"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
