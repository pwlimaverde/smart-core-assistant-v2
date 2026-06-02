use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Cliente {
    pub id: i32,
    pub tenant_id: Uuid,
    pub nome_fantasia: String,
    pub slug: String,
    pub razao_social: Option<String>,
    pub tipo: Option<String>,
    pub cnpj: Option<String>,
    pub cpf: Option<String>,
    pub telefone: Option<String>,
    pub site: Option<String>,
    pub ramo_atividade: Option<String>,
    pub observacoes: Option<String>,
    pub cep: Option<String>,
    pub logradouro: Option<String>,
    pub numero: Option<String>,
    pub complemento: Option<String>,
    pub bairro: Option<String>,
    pub cidade: Option<String>,
    pub uf: Option<String>,
    pub pais: Option<String>,
    pub data_cadastro: DateTime<Utc>,
    pub ultima_atualizacao: DateTime<Utc>,
    pub ativo: bool,
    pub metadados: serde_json::Value,
}

#[async_trait]
pub trait ClienteRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome_fantasia: &str,
        tipo: Option<&str>,
        cnpj: Option<&str>,
        cpf: Option<&str>,
    ) -> Result<Cliente, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Cliente>, DbError>;

    async fn adicionar_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError>;

    async fn remover_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError>;

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Cliente>, DbError>;
}

pub struct PostgresClienteRepository;

#[async_trait]
impl ClienteRepository for PostgresClienteRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nome_fantasia: &str,
        tipo: Option<&str>,
        cnpj: Option<&str>,
        cpf: Option<&str>,
    ) -> Result<Cliente, DbError> {
        if !ctx.has_permission("clientes:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            Cliente,
            r#"INSERT INTO oraculo_cliente (tenant_id, nome_fantasia, tipo, cnpj, cpf)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                         cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                         cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                         data_cadastro, ultima_atualizacao, ativo, metadados"#,
            ctx.tenant_id,
            nome_fantasia,
            tipo,
            cnpj,
            cpf
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
    ) -> Result<Option<Cliente>, DbError> {
        let row = sqlx::query_as!(
            Cliente,
            r#"SELECT id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                      cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                      cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                      data_cadastro, ultima_atualizacao, ativo, metadados
               FROM oraculo_cliente
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn adicionar_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError> {
        if !ctx.has_permission("clientes:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        sqlx::query!(
            r#"INSERT INTO oraculo_cliente_contatos (tenant_id, cliente_id, contato_id)
               VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
            ctx.tenant_id,
            cliente_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn remover_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
    ) -> Result<(), DbError> {
        if !ctx.has_permission("clientes:write") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        sqlx::query!(
            "DELETE FROM oraculo_cliente_contatos
             WHERE tenant_id = $1 AND cliente_id = $2 AND contato_id = $3",
            ctx.tenant_id,
            cliente_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn listar_ativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Cliente>, DbError> {
        if !ctx.has_permission("clientes:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            Cliente,
            r#"SELECT id, tenant_id, nome_fantasia, slug, razao_social, tipo,
                      cnpj, cpf, telefone, site, ramo_atividade, observacoes,
                      cep, logradouro, numero, complemento, bairro, cidade, uf, pais,
                      data_cadastro, ultima_atualizacao, ativo, metadados
               FROM oraculo_cliente
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY nome_fantasia
               LIMIT $2 OFFSET $3"#,
            ctx.tenant_id,
            limit,
            offset
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
