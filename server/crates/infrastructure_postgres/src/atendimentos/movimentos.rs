use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct MovimentoFluxo {
    pub id: i32,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub etapa_origem_id: Option<i32>,
    pub etapa_destino_id: i32,
    pub atendente_origem_id: Option<i32>,
    pub atendente_destino_id: Option<i32>,
    pub motivo: Option<String>,
    pub dados_complementares: serde_json::Value,
    pub automatico: bool,
    pub data_movimento: DateTime<Utc>,
    pub duracao_segundos: Option<i32>,
}

#[async_trait]
pub trait MovimentoFluxoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_origem_id: Option<i32>,
        etapa_destino_id: i32,
        atendente_destino_id: Option<i32>,
        motivo: Option<&str>,
        automatico: bool,
    ) -> Result<MovimentoFluxo, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Vec<MovimentoFluxo>, DbError>;
}

pub struct PostgresMovimentoFluxoRepository;

#[async_trait]
impl MovimentoFluxoRepository for PostgresMovimentoFluxoRepository {
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etapa_destino_id = etapa_destino_id, automatico = automatico))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_origem_id: Option<i32>,
        etapa_destino_id: i32,
        atendente_destino_id: Option<i32>,
        motivo: Option<&str>,
        automatico: bool,
    ) -> Result<MovimentoFluxo, DbError> {
        // Calcula duração em segundos desde o último movimento nesta etapa (se houver origem)
        let row = sqlx::query_as!(
            MovimentoFluxo,
            r#"INSERT INTO oraculo_movimento_fluxo
                   (tenant_id, atendimento_id, etapa_origem_id, etapa_destino_id,
                    atendente_destino_id, motivo, automatico,
                    duracao_segundos)
               VALUES ($1, $2, $3, $4, $5, $6, $7,
                   CASE WHEN $3::int4 IS NOT NULL THEN
                       EXTRACT(EPOCH FROM (NOW() - (
                           SELECT data_movimento FROM oraculo_movimento_fluxo
                           WHERE tenant_id = $1 AND atendimento_id = $2
                           ORDER BY data_movimento DESC LIMIT 1
                       )))::int
                   ELSE NULL END
               )
               RETURNING id, tenant_id, atendimento_id, etapa_origem_id, etapa_destino_id,
                         atendente_origem_id, atendente_destino_id, motivo, dados_complementares,
                         automatico, data_movimento, duracao_segundos"#,
            ctx.tenant_id,
            atendimento_id,
            etapa_origem_id,
            etapa_destino_id,
            atendente_destino_id,
            motivo,
            automatico
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
    ) -> Result<Vec<MovimentoFluxo>, DbError> {
        let rows = sqlx::query_as!(
            MovimentoFluxo,
            r#"SELECT id, tenant_id, atendimento_id, etapa_origem_id, etapa_destino_id,
                      atendente_origem_id, atendente_destino_id, motivo, dados_complementares,
                      automatico, data_movimento, duracao_segundos
               FROM oraculo_movimento_fluxo
               WHERE tenant_id = $1 AND atendimento_id = $2
               ORDER BY data_movimento DESC"#,
            ctx.tenant_id,
            atendimento_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }
}
