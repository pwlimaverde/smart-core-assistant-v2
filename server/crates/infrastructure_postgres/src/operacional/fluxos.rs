use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct FluxoAtendimento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub departamento_id: i32,
    pub nome: String,
    pub descricao: Option<String>,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct EtapaFluxo {
    pub id: i32,
    pub tenant_id: Uuid,
    pub fluxo_id: i32,
    pub nome: String,
    pub descricao: Option<String>,
    pub ordem: i32,
    pub cor: String,
    pub tipo_etapa: String,
    pub permite_atribuicao: bool,
    pub automatico: bool,
    pub regras_transicao: serde_json::Value,
    pub campos_obrigatorios: serde_json::Value,
    pub ativo: bool,
    pub data_criacao: DateTime<Utc>,
}

#[async_trait]
pub trait FluxoAtendimentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
        nome: &str,
    ) -> Result<FluxoAtendimento, DbError>;

    async fn buscar_por_departamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
    ) -> Result<Vec<FluxoAtendimento>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<FluxoAtendimento>, DbError>;
}

#[async_trait]
pub trait EtapaFluxoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        nome: &str,
        ordem: i32,
        tipo_etapa: &str,
        cor: Option<&str>,
    ) -> Result<EtapaFluxo, DbError>;

    async fn listar_por_fluxo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Vec<EtapaFluxo>, DbError>;

    /// Retorna a primeira etapa do tipo 'fila' do fluxo (etapa de entrada).
    async fn get_etapa_inicial(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError>;
}

pub struct PostgresFluxoAtendimentoRepository;
pub struct PostgresEtapaFluxoRepository;

#[async_trait]
impl FluxoAtendimentoRepository for PostgresFluxoAtendimentoRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
        nome: &str,
    ) -> Result<FluxoAtendimento, DbError> {
        if !ctx.has_permission("operacional:admin") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let row = sqlx::query_as!(
            FluxoAtendimento,
            r#"INSERT INTO oraculo_fluxo_atendimento (tenant_id, departamento_id, nome)
               VALUES ($1, $2, $3)
               RETURNING id, tenant_id, departamento_id, nome, descricao, ativo,
                         data_criacao, data_atualizacao"#,
            ctx.tenant_id,
            departamento_id,
            nome
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    async fn buscar_por_departamento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        departamento_id: i32,
    ) -> Result<Vec<FluxoAtendimento>, DbError> {
        let rows = sqlx::query_as!(
            FluxoAtendimento,
            r#"SELECT id, tenant_id, departamento_id, nome, descricao, ativo,
                      data_criacao, data_atualizacao
               FROM oraculo_fluxo_atendimento
               WHERE tenant_id = $1 AND departamento_id = $2 AND ativo = true
               ORDER BY nome"#,
            ctx.tenant_id,
            departamento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<FluxoAtendimento>, DbError> {
        let row = sqlx::query_as!(
            FluxoAtendimento,
            r#"SELECT id, tenant_id, departamento_id, nome, descricao, ativo,
                      data_criacao, data_atualizacao
               FROM oraculo_fluxo_atendimento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}

#[async_trait]
impl EtapaFluxoRepository for PostgresEtapaFluxoRepository {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
        nome: &str,
        ordem: i32,
        tipo_etapa: &str,
        cor: Option<&str>,
    ) -> Result<EtapaFluxo, DbError> {
        if !ctx.has_permission("operacional:admin") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let cor_val = cor.unwrap_or("#6B7280");
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"INSERT INTO oraculo_etapa_fluxo (tenant_id, fluxo_id, nome, ordem, tipo_etapa, cor)
               VALUES ($1, $2, $3, $4, $5, $6)
               RETURNING id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                         permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                         ativo, data_criacao"#,
            ctx.tenant_id,
            fluxo_id,
            nome,
            ordem,
            tipo_etapa,
            cor_val
        )
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    async fn listar_por_fluxo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Vec<EtapaFluxo>, DbError> {
        let rows = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND fluxo_id = $2 AND ativo = true
               ORDER BY ordem"#,
            ctx.tenant_id,
            fluxo_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    async fn get_etapa_inicial(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        fluxo_id: i32,
    ) -> Result<Option<EtapaFluxo>, DbError> {
        let row = sqlx::query_as!(
            EtapaFluxo,
            r#"SELECT id, tenant_id, fluxo_id, nome, descricao, ordem, cor, tipo_etapa,
                      permite_atribuicao, automatico, regras_transicao, campos_obrigatorios,
                      ativo, data_criacao
               FROM oraculo_etapa_fluxo
               WHERE tenant_id = $1 AND fluxo_id = $2
                 AND tipo_etapa = 'fila' AND ativo = true
               ORDER BY ordem ASC
               LIMIT 1"#,
            ctx.tenant_id,
            fluxo_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }
}
