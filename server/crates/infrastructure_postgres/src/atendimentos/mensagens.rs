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
}

pub struct PostgresMensagemRepository;

#[async_trait]
impl MensagemRepository for PostgresMensagemRepository {
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
            ctx.tenant_id, atendimento_id, tipo, conteudo, remetente,
            message_id_whatsapp, mensagem_citada_id
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
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        if !ctx.has_permission("atendimentos:read") && !ctx.has_permission("tenant:admin") {
            return Err(DbError::PermissionDenied);
        }
        let rows = sqlx::query_as!(
            Mensagem,
            r#"SELECT id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                      timestamp, message_id_whatsapp, metadados, respondida, lido,
                      resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                      arquivo_midia, analise_midia, resumo_midia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida
               FROM oraculo_mensagem
               WHERE tenant_id = $1 AND atendimento_id = $2
               ORDER BY timestamp ASC
               LIMIT $3 OFFSET $4"#,
            ctx.tenant_id, atendimento_id, limit, offset
        )
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

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
            resposta, confianca, ctx.tenant_id, mensagem_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    async fn marcar_como_lida(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_mensagem SET lido = true
               WHERE tenant_id = $1 AND atendimento_id = $2 AND lido = false"#,
            ctx.tenant_id, atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}
