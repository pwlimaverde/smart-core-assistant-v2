use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Contato {
    pub id: i32,
    pub tenant_id: Uuid,
    pub telefone: Option<String>,
    pub nome_contato: Option<String>,
    pub slug: String,
    pub email: Option<String>,
    pub nome_perfil_whatsapp: Option<String>,
    pub data_cadastro: DateTime<Utc>,
    pub ultima_interacao: DateTime<Utc>,
    pub ativo: bool,
    pub metadados: serde_json::Value,
    pub foto_perfil: Option<String>,
    pub foto_perfil_url_origem: Option<String>,
}

#[async_trait]
pub trait ContatoRepository: Send + Sync {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
    ) -> Result<Contato, DbError>;

    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Contato>, DbError>;

    async fn listar_recentes(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
    ) -> Result<Vec<Contato>, DbError>;

    async fn atualizar_ultima_interacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<(), DbError>;
}

pub struct PostgresContatoRepository;

#[async_trait]
impl ContatoRepository for PostgresContatoRepository {
    // `telefone`/`nome_contato` são PII: `skip_all` mantém-nos fora do span.
    #[tracing::instrument(skip_all)]
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
        nome_contato: Option<&str>,
    ) -> Result<Contato, DbError> {
        ctx.exigir_qualquer(&["clientes:write", "tenant:admin"])?;
        // ON CONFLICT atualiza apenas nome_contato e ultima_interacao
        let row = sqlx::query_as!(
            Contato,
            r#"INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato)
               VALUES ($1, $2, $3)
               ON CONFLICT (tenant_id, telefone) DO UPDATE
                   SET nome_contato = COALESCE(EXCLUDED.nome_contato, oraculo_contato.nome_contato),
                       ultima_interacao = NOW()
               RETURNING id, tenant_id, telefone, nome_contato, slug, email,
                         nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                         ativo, metadados, foto_perfil, foto_perfil_url_origem"#,
            ctx.tenant_id,
            telefone,
            nome_contato
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError> {
        let row = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND telefone = $2"#,
            ctx.tenant_id,
            telefone
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Contato>, DbError> {
        let row = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(limit = limit))]
    async fn listar_recentes(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limit: i64,
    ) -> Result<Vec<Contato>, DbError> {
        ctx.exigir_qualquer(&["clientes:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Contato,
            r#"SELECT id, tenant_id, telefone, nome_contato, slug, email,
                      nome_perfil_whatsapp, data_cadastro, ultima_interacao,
                      ativo, metadados, foto_perfil, foto_perfil_url_origem
               FROM oraculo_contato
               WHERE tenant_id = $1 AND ativo = true
               ORDER BY ultima_interacao DESC
               LIMIT $2"#,
            ctx.tenant_id,
            limit
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn atualizar_ultima_interacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            "UPDATE oraculo_contato SET ultima_interacao = NOW()
             WHERE tenant_id = $1 AND id = $2",
            ctx.tenant_id,
            contato_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}
