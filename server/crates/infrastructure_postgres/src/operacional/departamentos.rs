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

    /// Renomeia e reescreve a descrição.
    ///
    /// O `slug` NÃO muda: ele é referência estável, e há registros que apontam
    /// para o departamento por ele.
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// Desativa em vez de apagar.
    ///
    /// Atendimentos e atendentes apontam para o departamento; remover a linha
    /// levaria histórico junto. Inativo some das listas de trabalho e continua
    /// respondendo pelo que já passou por ele.
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError>;

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
    #[tracing::instrument(skip_all, fields(nome = %nome))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome: &str,
        descricao: Option<&str>,
    ) -> Result<Departamento, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Departamento,
            r#"INSERT INTO oraculo_departamento (tenant_id, nome, descricao)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, nome, slug, descricao, ativo,
                         telefone_instancia, api_key, configuracoes, metadados, data_criacao"#,
            ctx.tenant_id,
            nome,
            descricao
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
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
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Departamento>, DbError> {
        ctx.exigir_qualquer(&["operacional:read", "tenant:admin"])?;
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

    // `api_key` é credencial: `skip_all`.
    #[tracing::instrument(skip_all)]
    #[tracing::instrument(skip_all, fields(id = id))]
    async fn atualizar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        descricao: Option<&str>,
        ativo: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_departamento
                  SET nome = $1, descricao = $2, ativo = $3
                WHERE id = $4 AND tenant_id = $5"#,
            nome,
            descricao,
            ativo,
            id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn desativar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let res = sqlx::query!(
            "UPDATE oraculo_departamento SET ativo = false WHERE id = $1 AND tenant_id = $2",
            id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
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
            ctx.tenant_id,
            api_key
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}
