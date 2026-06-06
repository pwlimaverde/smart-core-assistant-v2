use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct CampoPersonalizado {
    pub id: i64,
    pub tenant_id: Uuid,
    pub slug: String,
    pub nome: String,
    pub descricao: String,
    pub escopo: String,
    pub fluxo_id: Option<i32>,
    pub tipo: String,
    pub opcoes: serde_json::Value,
    pub obrigatorio: bool,
    pub extrair_automaticamente: bool,
    pub extrair_hint: String,
    pub mostrar_no_card: bool,
    pub ordem: i32,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct ValorCampoAtendimento {
    pub id: i64,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub campo_id: i64,
    pub valor: serde_json::Value,
    pub origem: String,
    pub confianca: Option<f64>,
    pub mensagem_origem_id: Option<i32>,
    pub editado_por_id: Option<i32>,
    pub data_atualizacao: DateTime<Utc>,
}

#[async_trait]
pub trait CampoPersonalizadoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        slug: &str,
        nome: &str,
        escopo: &str,
        tipo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<CampoPersonalizado, DbError>;

    async fn listar_por_escopo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        escopo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<Vec<CampoPersonalizado>, DbError>;
}

#[async_trait]
pub trait ValorCampoRepository: Send + Sync {
    async fn upsert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        origem: &str,
        confianca: Option<f64>,
    ) -> Result<ValorCampoAtendimento, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<ValorCampoAtendimento>, DbError>;
}

pub struct PostgresCampoPersonalizadoRepository;
pub struct PostgresValorCampoRepository;

#[async_trait]
impl CampoPersonalizadoRepository for PostgresCampoPersonalizadoRepository {
    #[tracing::instrument(skip_all, fields(slug = %slug, escopo = %escopo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        slug: &str,
        nome: &str,
        escopo: &str,
        tipo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<CampoPersonalizado, DbError> {
        ctx.exigir_qualquer(&["configuracoes:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            CampoPersonalizado,
            r#"INSERT INTO atu_campo_personalizado (tenant_id, slug, nome, escopo, tipo, fluxo_id)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, slug, nome, descricao, escopo, fluxo_id, tipo,
                         opcoes, obrigatorio, extrair_automaticamente, extrair_hint,
                         mostrar_no_card, ordem, ativo, data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            slug,
            nome,
            escopo,
            tipo,
            fluxo_id
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(escopo = %escopo))]
    async fn listar_por_escopo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        escopo: &str,
        fluxo_id: Option<i32>,
    ) -> Result<Vec<CampoPersonalizado>, DbError> {
        let rows = sqlx::query_as!(
            CampoPersonalizado,
            r#"SELECT id, tenant_id, slug, nome, descricao, escopo, fluxo_id, tipo,
                      opcoes, obrigatorio, extrair_automaticamente, extrair_hint,
                      mostrar_no_card, ordem, ativo, data_criacao, data_atualizacao
               FROM atu_campo_personalizado
               WHERE tenant_id = $1 AND escopo = $2
                 AND ($3::int IS NULL OR fluxo_id = $3) AND ativo = true
               ORDER BY ordem, nome"#,
            ctx.tenant_id,
            escopo,
            fluxo_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}

#[async_trait]
impl ValorCampoRepository for PostgresValorCampoRepository {
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, campo_id = campo_id))]
    async fn upsert(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        campo_id: i64,
        valor: serde_json::Value,
        origem: &str,
        confianca: Option<f64>,
    ) -> Result<ValorCampoAtendimento, DbError> {
        let row = sqlx::query_as!(
            ValorCampoAtendimento,
            r#"INSERT INTO atu_valor_campo
                   (tenant_id, atendimento_id, campo_id, valor, origem, confianca)
               VALUES ($1, $2, $3, $4, $5, $6)
               ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
                   SET valor = EXCLUDED.valor,
                       origem = EXCLUDED.origem,
                       confianca = EXCLUDED.confianca,
                       data_atualizacao = NOW()
               RETURNING id, tenant_id, atendimento_id, campo_id, valor, origem,
                         confianca, mensagem_origem_id, editado_por_id, data_atualizacao"#,
            ctx.tenant_id,
            atendimento_id,
            campo_id,
            valor,
            origem,
            confianca
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<ValorCampoAtendimento>, DbError> {
        let rows = sqlx::query_as!(
            ValorCampoAtendimento,
            r#"SELECT id, tenant_id, atendimento_id, campo_id, valor, origem,
                      confianca, mensagem_origem_id, editado_por_id, data_atualizacao
               FROM atu_valor_campo
               WHERE tenant_id = $1 AND atendimento_id = $2"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
