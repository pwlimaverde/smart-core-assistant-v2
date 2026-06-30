use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Mensagem {
    pub id: i32,
    pub tenant_id: Uuid,
    pub atendimento_id: i32,
    pub tipo: String,
    pub conteudo: String,
    pub remetente: String,
    pub timestamp: DateTime<Utc>,
    pub message_id_whatsapp: Option<String>,
    pub metadados: serde_json::Value,
    pub respondida: bool,
    pub lido: bool,
    pub resposta_bot: Option<String>,
    pub intent_detectado: serde_json::Value,
    pub entidades_extraidas: serde_json::Value,
    pub confianca_resposta: Option<f64>,
    pub arquivo_midia: Option<String>,
    pub analise_midia: Option<String>,
    pub resumo_midia: Option<String>,
    pub mensagem_citada_id: Option<i32>,
    pub quoted_preview: Option<serde_json::Value>,
    pub status_envio: String,
    pub data_entregue: Option<DateTime<Utc>>,
    pub data_lida: Option<DateTime<Utc>>,
}

#[async_trait]
pub trait MensagemRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        message_id_whatsapp: Option<&str>,
        mensagem_citada_id: Option<i32>,
    ) -> Result<Mensagem, DbError>;

    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError>;

    async fn registrar_resposta_bot(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        resposta: &str,
        confianca: Option<f64>,
    ) -> Result<(), DbError>;

    async fn marcar_como_lida(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    async fn atualizar_status_por_whatsapp_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
        status: &str,
    ) -> Result<(), DbError>;
}

pub struct PostgresMensagemRepository;

#[async_trait]
impl MensagemRepository for PostgresMensagemRepository {
    // `conteudo` é mensagem do usuário (PII): `skip_all` evita registrá-lo.
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, tipo = %tipo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        message_id_whatsapp: Option<&str>,
        mensagem_citada_id: Option<i32>,
    ) -> Result<Mensagem, DbError> {
        let row = sqlx::query_as!(
            Mensagem,
            r#"INSERT INTO oraculo_mensagem
                   (tenant_id, atendimento_id, tipo, conteudo, remetente,
                    message_id_whatsapp, mensagem_citada_id)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               RETURNING id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                         timestamp, message_id_whatsapp, metadados, respondida, lido,
                         resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                         arquivo_midia, analise_midia, resumo_midia, mensagem_citada_id,
                         quoted_preview, status_envio, data_entregue, data_lida"#,
            ctx.tenant_id,
            atendimento_id,
            tipo,
            conteudo,
            remetente,
            message_id_whatsapp,
            mensagem_citada_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, limit = limit, offset = offset))]
    async fn listar_por_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Mensagem,
            r#"SELECT id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                      timestamp, message_id_whatsapp, metadados, respondida, lido,
                      resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                      arquivo_midia, analise_midia, resumo_midia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida
               FROM oraculo_mensagem
               WHERE tenant_id = $1 AND atendimento_id = $2
               ORDER BY timestamp ASC, id ASC
               LIMIT $3 OFFSET $4"#,
            ctx.tenant_id,
            atendimento_id,
            limit,
            offset
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(mensagem_id = mensagem_id))]
    async fn registrar_resposta_bot(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        resposta: &str,
        confianca: Option<f64>,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_mensagem
               SET resposta_bot = $1, confianca_resposta = $2, respondida = true
               WHERE tenant_id = $3 AND id = $4"#,
            resposta,
            confianca,
            ctx.tenant_id,
            mensagem_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn marcar_como_lida(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_mensagem SET lido = true
               WHERE tenant_id = $1 AND atendimento_id = $2 AND lido = false"#,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(message_id_whatsapp = %message_id_whatsapp, status = %status))]
    async fn atualizar_status_por_whatsapp_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
        status: &str,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_mensagem
               SET status_envio = $3,
                   data_entregue = CASE WHEN $3 = 'delivered' AND data_entregue IS NULL THEN NOW() ELSE data_entregue END,
                   data_lida = CASE WHEN $3 = 'read' AND data_lida IS NULL THEN NOW() ELSE data_lida END,
                   lido = CASE WHEN $3 = 'read' THEN true ELSE lido END
               WHERE tenant_id = $1 AND message_id_whatsapp = $2"#,
        )
        .bind(ctx.tenant_id)
        .bind(message_id_whatsapp)
        .bind(status)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}
