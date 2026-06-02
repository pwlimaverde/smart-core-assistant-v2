use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Etiqueta {
    pub id: i64,
    pub tenant_id: Uuid,
    pub nome: String,
    pub cor: String,
    pub descricao: String,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Nota {
    pub id: i64,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub texto: String,
    pub criado_por_id: Option<i32>,
    pub criado_em: DateTime<Utc>,
}

#[async_trait]
pub trait EtiquetaRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        cor: Option<&str>,
    ) -> Result<Etiqueta, DbError>;

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Etiqueta>, DbError>;

    async fn aplicar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError>;

    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError>;
}

#[async_trait]
pub trait NotaRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        texto: &str,
        criado_por_id: Option<i32>,
    ) -> Result<Nota, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Nota>, DbError>;
}

pub struct PostgresEtiquetaRepository;
pub struct PostgresNotaRepository;

#[async_trait]
impl EtiquetaRepository for PostgresEtiquetaRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        cor: Option<&str>,
    ) -> Result<Etiqueta, DbError> {
        if !ctx.has_permission("atendimentos:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let cor_val = cor.unwrap_or("#a98f71");
        let row = sqlx::query_as!(
            Etiqueta,
            r#"INSERT INTO atu_etiqueta (tenant_id, nome, cor)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, nome, cor, descricao, ativo, data_criacao"#,
            ctx.tenant_id,
            nome,
            cor_val
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn listar_ativas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Etiqueta>, DbError> {
        let rows = sqlx::query_as!(
            Etiqueta,
            r#"SELECT id, tenant_id, nome, cor, descricao, ativo, data_criacao
               FROM atu_etiqueta
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    async fn aplicar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"INSERT INTO atu_etiqueta_atendimento (tenant_id, atendimento_id, etiqueta_id)
               VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
            ctx.tenant_id,
            atendimento_id,
            etiqueta_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etiqueta_id: i64,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"DELETE FROM atu_etiqueta_atendimento
               WHERE tenant_id = $1 AND atendimento_id = $2 AND etiqueta_id = $3"#,
            ctx.tenant_id,
            atendimento_id,
            etiqueta_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

#[async_trait]
impl NotaRepository for PostgresNotaRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        texto: &str,
        criado_por_id: Option<i32>,
    ) -> Result<Nota, DbError> {
        let row = sqlx::query_as!(
            Nota,
            r#"INSERT INTO atu_nota (tenant_id, atendimento_id, texto, criado_por_id)
               VALUES ($1, $2, $3, $4)
               RETURNING id, tenant_id, atendimento_id, texto, criado_por_id, criado_em"#,
            ctx.tenant_id,
            atendimento_id,
            texto,
            criado_por_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<Nota>, DbError> {
        let rows = sqlx::query_as!(
            Nota,
            r#"SELECT id, tenant_id, atendimento_id, texto, criado_por_id, criado_em
               FROM atu_nota
               WHERE tenant_id = $1 AND atendimento_id = $2
               ORDER BY criado_em DESC"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
