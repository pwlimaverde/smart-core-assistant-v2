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

    /// Varredura CROSS-TENANT do scheduler: o que foi finalizado e ainda não
    /// virou vetor, de toda a base.
    ///
    /// Exige pool com BYPASSRLS (`admin_pool`) — no pool de aplicação a RLS
    /// devolve zero linhas em silêncio, e a fila pareceria sempre vazia.
    async fn listar_pendentes_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<Treinamento>, DbError>;

    /// Lista tudo do tenant, do mais recente para o mais antigo.
    ///
    /// É o que a tela de acompanhamento mostra: os três estados (rascunho,
    /// aguardando vetorização e vetorizado) convivem na mesma lista, porque
    /// quem treinou precisa ver o que ficou pelo caminho.
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<Option<Treinamento>, DbError>;

    /// Substitui o conteúdo — o aceite da revisão, quando o texto foi editado.
    ///
    /// Zera `treinamento_vetorizado`: o conteúdo mudou, e os vetores antigos
    /// já não representam o texto. A revetorização é do worker.
    async fn atualizar_conteudo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError>;

    /// Remove o treinamento e, por cascata, seus documentos.
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<bool, DbError>;
}

pub struct PostgresTreinamentoRepository;

#[async_trait]
impl TreinamentoRepository for PostgresTreinamentoRepository {
    #[tracing::instrument(skip_all, fields(tag = %tag, grupo = %grupo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        tag: &str,
        grupo: &str,
        conteudo: Option<&str>,
    ) -> Result<Treinamento, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
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

    #[tracing::instrument(skip_all, fields(tag = %tag, grupo = %grupo))]
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

    #[tracing::instrument(skip_all, fields(treinamento_id = treinamento_id))]
    async fn marcar_finalizado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
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

    #[tracing::instrument(skip_all, fields(treinamento_id = treinamento_id))]
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

    #[tracing::instrument(skip_all)]
    async fn listar_pendentes_vetorizacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
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

    #[tracing::instrument(skip_all, fields(limite = limite))]
    async fn listar_pendentes_global(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        // Cross-tenant por desenho (scheduler): sem `WHERE tenant_id`, e por
        // isso exige o pool com BYPASSRLS.
        let rows = sqlx::query_as::<_, Treinamento>(
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE treinamento_finalizado = true AND treinamento_vetorizado = false
               ORDER BY data_criacao ASC
               LIMIT $1"#,
        )
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all)]
    async fn listar_por_tenant(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<Vec<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE tenant_id = $1
               ORDER BY data_criacao DESC"#,
            ctx.tenant_id
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<Option<Treinamento>, DbError> {
        ctx.exigir_qualquer(&["treinamento:read", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Treinamento,
            r#"SELECT id, tenant_id, tag, grupo, conteudo,
                      treinamento_finalizado, treinamento_vetorizado,
                      data_criacao, data_atualizacao
               FROM oraculo_treinamento
               WHERE id = $1 AND tenant_id = $2"#,
            treinamento_id,
            ctx.tenant_id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn atualizar_conteudo(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
        conteudo: &str,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_treinamento
                  SET conteudo = $1,
                      treinamento_vetorizado = false,
                      data_atualizacao = NOW()
                WHERE id = $2 AND tenant_id = $3"#,
            conteudo,
            treinamento_id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(treinamento_id))]
    async fn remover(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        treinamento_id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["treinamento:write", "tenant:admin"])?;
        let res = sqlx::query!(
            "DELETE FROM oraculo_treinamento WHERE id = $1 AND tenant_id = $2",
            treinamento_id,
            ctx.tenant_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }
}
