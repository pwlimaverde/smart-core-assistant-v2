use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Departamento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub nome: String,
    pub slug: String,
    pub descricao: Option<String>,
    pub ativo: bool,
    pub telefone_instancia: Option<String>,
    pub api_key: Option<String>,
    pub configuracoes: serde_json::Value,
    pub metadados: serde_json::Value,
    pub data_criacao: DateTime<Utc>,
}

#[async_trait]
pub trait DepartamentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<Departamento, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Departamento>, DbError>;

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Departamento>, DbError>;

    /// Valida as credenciais recebidas do webhook da Evolution API.
    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<Departamento>, DbError>;
}

pub struct PostgresDepartamentoRepository;

#[async_trait]
impl DepartamentoRepository for PostgresDepartamentoRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<Departamento, DbError> {
        if !ctx.has_permission("operacional:admin") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            Departamento,
            r#"INSERT INTO oraculo_departamento (tenant_id, nome, descricao)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, nome, slug, descricao, ativo,
                         telefone_instancia, api_key, configuracoes, metadados, data_criacao"#,
            ctx.tenant_id, nome, descricao
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Departamento>, DbError> {
        let row = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id, id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Departamento>, DbError> {
        if !ctx.has_permission("operacional:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    async fn buscar_por_api_key(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        api_key: &str,
    ) -> Result<Option<Departamento>, DbError> {
        let row = sqlx::query_as!(
            Departamento,
            r#"SELECT id, tenant_id, nome, slug, descricao, ativo,
                      telefone_instancia, api_key, configuracoes, metadados, data_criacao
               FROM oraculo_departamento
               WHERE tenant_id = $1 AND api_key = $2"#,
            ctx.tenant_id, api_key
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}
