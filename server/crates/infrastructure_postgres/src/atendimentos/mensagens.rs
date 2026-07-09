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

/// Destino resolvido para o envio outbound de uma mensagem do atendente (N1.3):
/// instância WhatsApp (id no banco) + telefone do contato + status_envio atual
/// (para o consumidor decidir se é reentrega idempotente do consumer group).
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct DestinoEnvioOutbound {
    pub atendimento_id: i32,
    pub instance_id: i32,
    pub to_number: String,
    pub status_envio: String,
    pub conteudo: String,
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

    /// Varredura CROSS-TENANT (scheduler do worker, F4.3b): mensagens com mídia
    /// ainda não purgada e mais antigas que `idade_max_dias`. `ctx` só para escopo.
    async fn listar_midias_expiradas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        idade_max_dias: i64,
    ) -> Result<Vec<Mensagem>, DbError>;

    /// Marca a mídia da mensagem como purga solicitada (idempotente).
    async fn marcar_midia_purgada(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError>;

    /// Resolve o destino de envio (instância + telefone) de uma mensagem outbound
    /// do atendente, a partir do contato do atendimento (WS-6.3 / N1.3).
    async fn resolver_destino_envio_outbound(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<Option<DestinoEnvioOutbound>, DbError>;

    /// Marca a mensagem como enviada com sucesso ao provedor, gravando o
    /// `message_id_whatsapp` (stanzaId) para correlação futura com webhooks de status.
    async fn marcar_mensagem_enviada(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        message_id_whatsapp: &str,
    ) -> Result<(), DbError>;

    /// Marca falha definitiva no envio (após esgotar as tentativas de retry).
    async fn marcar_mensagem_falha_envio(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
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

    #[tracing::instrument(skip_all, fields(limite = limite, idade_max_dias = idade_max_dias))]
    async fn listar_midias_expiradas(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        idade_max_dias: i64,
    ) -> Result<Vec<Mensagem>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS (admin_pool).
        let rows = sqlx::query_as::<_, Mensagem>(
            r#"SELECT id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                      timestamp, message_id_whatsapp, metadados, respondida, lido,
                      resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                      arquivo_midia, analise_midia, resumo_midia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida
               FROM oraculo_mensagem
               WHERE arquivo_midia IS NOT NULL
                 AND midia_purgada_em IS NULL
                 AND timestamp < NOW() - ($1 || ' days')::interval
               ORDER BY timestamp ASC
               LIMIT $2"#,
        )
        .bind(idade_max_dias.to_string())
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_midia_purgada(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_mensagem
               SET midia_purgada_em = NOW()
               WHERE tenant_id = $1 AND id = $2 AND midia_purgada_em IS NULL"#,
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn resolver_destino_envio_outbound(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<Option<DestinoEnvioOutbound>, DbError> {
        let row = sqlx::query_as::<_, DestinoEnvioOutbound>(
            r#"SELECT om.atendimento_id, wc.instance_id, oc.telefone AS to_number,
                      om.status_envio, om.conteudo
               FROM oraculo_mensagem om
               JOIN oraculo_atendimento oa
                 ON oa.id = om.atendimento_id AND oa.tenant_id = om.tenant_id
               JOIN oraculo_contato oc
                 ON oc.id = oa.contato_id AND oc.tenant_id = oa.tenant_id
               JOIN whatsapp_contact wc
                 ON wc.contact_id = oc.id AND wc.tenant_id = oc.tenant_id AND wc.active = true
               WHERE om.tenant_id = $1 AND om.id = $2 AND oc.telefone IS NOT NULL
               ORDER BY wc.updated_at DESC
               LIMIT 1"#,
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_enviada(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        message_id_whatsapp: &str,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_mensagem
               SET status_envio = 'sent', message_id_whatsapp = $3
               WHERE tenant_id = $1 AND id = $2 AND status_envio = 'pending'"#,
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .bind(message_id_whatsapp)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_mensagem_falha_envio(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_mensagem
               SET status_envio = 'failed'
               WHERE tenant_id = $1 AND id = $2 AND status_envio = 'pending'"#,
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}
