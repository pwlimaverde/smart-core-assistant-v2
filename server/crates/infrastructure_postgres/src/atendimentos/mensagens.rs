use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

/// Valor de `oraculo_mensagem.remetente` para as mensagens do assistente virtual.
/// É o discriminador de `gerado_por_ia` na escrita (ver [`MensagemRepository::criar`])
/// e o que impede o worker de reprocessar a própria resposta do bot como outbound
/// do atendente (`processar_mensagem_persistida` só reage a `"atendente"`).
pub const REMETENTE_BOT: &str = "bot";

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
    /// N9/E1 — metadados do anexo (migration 0029). Sem eles a tela não sabe se
    /// monta um player de áudio, um visualizador de imagem ou um cartão de
    /// documento; `arquivo_midia` sozinho é só uma chave opaca.
    ///
    /// O mimetype é o **conferido** por magic bytes, não o declarado no upload.
    pub mimetype_midia: Option<String>,
    /// Nome original do arquivo. Pode conter PII — nunca em log ou auditoria.
    pub nome_arquivo_midia: Option<String>,
    pub tamanho_midia: Option<i64>,
    pub gerado_por_ia: bool,
    pub mensagem_citada_id: Option<i32>,
    pub quoted_preview: Option<serde_json::Value>,
    pub status_envio: String,
    pub data_entregue: Option<DateTime<Utc>>,
    pub data_lida: Option<DateTime<Utc>>,
}

/// Dados de criação de uma mensagem no thread de um atendimento.
///
/// Existe como struct (e não como lista de parâmetros) porque a criação carrega
/// campos opcionais de origem — stanzaId, citação e "já entregue" — que só alguns
/// caminhos de ingestão preenchem; posicionalmente seriam 9 argumentos fáceis de
/// trocar de lugar.
#[derive(Debug, Clone)]
pub struct NovaMensagem<'a> {
    pub atendimento_id: i32,
    pub tipo: &'a str,
    pub conteudo: &'a str,
    pub remetente: &'a str,
    /// stanzaId do WhatsApp. No inbound é a chave natural de idempotência
    /// (reentrega do consumer group não pode duplicar a mensagem no chat) e o que
    /// permite correlacionar os webhooks de status (`messages.update`) depois.
    pub message_id_whatsapp: Option<&'a str>,
    /// Id interno da mensagem citada (reply), já resolvido pelo chamador.
    pub mensagem_citada_id: Option<i32>,
    /// `true` quando a mensagem já trafegou pelo WhatsApp antes de ser persistida
    /// (mensagem que o atendente digitou no próprio celular, `fromMe`): nasce com
    /// `status_envio='sent'` para o elo outbox->outbound do worker NÃO tentar
    /// enviá-la de novo — o que devolveria a mesma mensagem ao contato.
    pub ja_entregue: bool,
    /// Confiança (0..1) da IA na resposta. Só o remetente `bot` a preenche.
    ///
    /// Fica na linha da **resposta**, não na da pergunta como fazia a v1: a v2
    /// responde a uma rajada agregada, e não existe "a mensagem respondida".
    pub confianca_resposta: Option<f64>,
    /// P8 — o que não cabe em `conteudo`: opções da enquete, itens da lista,
    /// rótulos dos botões, vCard do contato.
    ///
    /// A coluna existe desde a 0006 e a ingestão nunca escreveu nela: enquete e
    /// lista chegavam ao chat só com o título, sem as alternativas.
    pub metadados: Option<serde_json::Value>,
}

impl<'a> NovaMensagem<'a> {
    /// Construtor mínimo: só os campos obrigatórios; os de origem ficam vazios.
    pub fn nova(atendimento_id: i32, tipo: &'a str, conteudo: &'a str, remetente: &'a str) -> Self {
        Self {
            atendimento_id,
            tipo,
            conteudo,
            remetente,
            message_id_whatsapp: None,
            mensagem_citada_id: None,
            ja_entregue: false,
            confianca_resposta: None,
            metadados: None,
        }
    }
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
        nova: NovaMensagem<'_>,
    ) -> Result<Mensagem, DbError>;

    /// Busca a mensagem do tenant pelo `message_id_whatsapp` (stanzaId), quando existir.
    /// Sustenta a idempotência da ingestão: o mesmo stanzaId reentregue pelo bus
    /// devolve a mensagem já persistida em vez de criar uma duplicata no chat.
    async fn buscar_por_whatsapp_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
    ) -> Result<Option<Mensagem>, DbError>;

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

    /// Anexa a análise de mídia (ponteiro do arquivo no storage + resumo/análise
    /// da IA) a uma mensagem já persistida (N6.1). Campos `None` não são sobrescritos.
    async fn anexar_analise_midia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        arquivo_midia: Option<&str>,
        analise_midia: Option<&str>,
        resumo_midia: Option<&str>,
    ) -> Result<(), DbError>;

    /// Reprocessamento manual de um dead-letter (N7.2): se agora existe
    /// `whatsapp_contact` ativo para o contato da mensagem, volta o
    /// `status_envio` a `"pending"` e reinsere o evento `message.persisted` no
    /// outbox (mesma transação ACID) para o worker tentar o envio de novo.
    /// Retorna `"reprocessada"` | `"ainda_sem_destino"` | `"nao_encontrada"`.
    async fn reprocessar_dead_letter(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        dead_letter_id: i32,
        traceparent: &str,
    ) -> Result<&'static str, DbError>;
}

pub struct PostgresMensagemRepository;

#[async_trait]
impl MensagemRepository for PostgresMensagemRepository {
    // `conteudo` é mensagem do usuário (PII): `skip_all` evita registrá-lo.
    #[tracing::instrument(skip_all, fields(atendimento_id = nova.atendimento_id, tipo = %nova.tipo))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        nova: NovaMensagem<'_>,
    ) -> Result<Mensagem, DbError> {
        // Escrever no thread é operação de escrita, como criar/atualizar atendimento
        // (mesmos escopos exigidos em `atendimentos.rs`). Faltava a checagem aqui: um
        // usuário do tenant com `module_permissions` só de leitura conseguia, via
        // `SendOutboundMessage`, inserir mensagem em qualquer atendimento — e ela
        // seria de fato entregue ao WhatsApp do cliente pelo worker.
        //
        // Os serviços internos (worker/scheduler) usam o coringa `"*"`, que satisfaz
        // qualquer escopo, então a ingestão inbound e a resposta do bot não mudam.
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;

        // `gerado_por_ia` é derivado do remetente: uma mensagem cujo remetente é o
        // assistente virtual É gerada por IA (N6.2 — a UI lê este campo para o selo
        // "gerado por IA"). Derivar aqui, no único ponto de escrita da tabela, evita
        // um parâmetro redundante no trait e garante que nenhum caminho de ingestão
        // esqueça de marcar a mensagem do bot.
        let gerado_por_ia = nova.remetente == REMETENTE_BOT;
        // `status_envio` explícito (em vez do DEFAULT do schema) porque a mensagem
        // que o atendente digitou no celular nasce já entregue — ver `ja_entregue`.
        let status_envio = if nova.ja_entregue { "sent" } else { "pending" };
        // API de runtime (e não `query_as!`) por escolha: o INSERT do thread muda
        // junto com os campos de origem da ingestão, e a macro obrigaria a
        // regravar o cache `.sqlx` com o banco no ar a cada ajuste. Mesmo padrão
        // já adotado em `listar_midias_expiradas`/`resolver_destino_envio_outbound`.
        let row = sqlx::query_as::<_, Mensagem>(
            r#"INSERT INTO oraculo_mensagem
                   (tenant_id, atendimento_id, tipo, conteudo, remetente,
                    message_id_whatsapp, mensagem_citada_id, gerado_por_ia, status_envio,
                    confianca_resposta, metadados)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                       COALESCE($11, '{}'::jsonb))
               RETURNING id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                         timestamp, message_id_whatsapp, metadados, respondida, lido,
                         resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                         arquivo_midia, analise_midia, resumo_midia, gerado_por_ia, mensagem_citada_id,
                         quoted_preview, status_envio, data_entregue, data_lida,
                         mimetype_midia, nome_arquivo_midia, tamanho_midia"#,
        )
        .bind(ctx.tenant_id)
        .bind(nova.atendimento_id)
        .bind(nova.tipo)
        .bind(nova.conteudo)
        .bind(nova.remetente)
        .bind(nova.message_id_whatsapp)
        .bind(nova.mensagem_citada_id)
        .bind(gerado_por_ia)
        .bind(status_envio)
        .bind(nova.confianca_resposta)
        .bind(nova.metadados)
        .fetch_one(&mut **tx)
        .await
        .map_err(DbError::from_sqlx_unique)?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(message_id_whatsapp = %message_id_whatsapp))]
    async fn buscar_por_whatsapp_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
    ) -> Result<Option<Mensagem>, DbError> {
        let row = sqlx::query_as::<_, Mensagem>(
            r#"SELECT id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                      timestamp, message_id_whatsapp, metadados, respondida, lido,
                      resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                      arquivo_midia, analise_midia, resumo_midia, gerado_por_ia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida,
                      mimetype_midia, nome_arquivo_midia, tamanho_midia
               FROM oraculo_mensagem
               WHERE tenant_id = $1 AND message_id_whatsapp = $2
               ORDER BY id DESC
               LIMIT 1"#,
        )
        .bind(ctx.tenant_id)
        .bind(message_id_whatsapp)
        .fetch_optional(&mut **tx)
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
                      arquivo_midia, analise_midia, resumo_midia, gerado_por_ia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida,
                      mimetype_midia, nome_arquivo_midia, tamanho_midia
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
        // N4.3: retenção por plano (tenants_plan.retention_days) tem prioridade sobre
        // o default global recebido em `idade_max_dias`; COALESCE cai no default
        // quando o tenant não tem assinatura/plano ou o plano não define override.
        let rows = sqlx::query_as::<_, Mensagem>(
            r#"SELECT m.id, m.tenant_id, m.atendimento_id, m.tipo, m.conteudo, m.remetente,
                      m.timestamp, m.message_id_whatsapp, m.metadados, m.respondida, m.lido,
                      m.resposta_bot, m.intent_detectado, m.entidades_extraidas, m.confianca_resposta,
                      m.arquivo_midia, m.analise_midia, m.resumo_midia, m.gerado_por_ia, m.mensagem_citada_id,
                      m.quoted_preview, m.status_envio, m.data_entregue, m.data_lida,
                      m.mimetype_midia, m.nome_arquivo_midia, m.tamanho_midia
               FROM oraculo_mensagem m
               LEFT JOIN tenants_subscription s ON s.tenant_id = m.tenant_id
               LEFT JOIN tenants_plan p ON p.id = s.plan_id
               WHERE m.arquivo_midia IS NOT NULL
                 AND m.midia_purgada_em IS NULL
                 AND m.timestamp < NOW() - (COALESCE(p.retention_days, $1)::text || ' days')::interval
               ORDER BY m.timestamp ASC
               LIMIT $2"#,
        )
        .bind(idade_max_dias as i32)
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
        if row.is_some() {
            return Ok(row);
        }

        // N7.2 — sem destino resolvível (nenhum whatsapp_contact ativo para o
        // contato): em vez de propagar erro/descartar, vira dead-letter auditável
        // e reprocessável, e a mensagem sai de "pending" (evita reentrega infinita
        // do consumer group). Qualquer `status_envio != "pending"` já é tratado
        // como no-op idempotente pelo worker — reaproveita o mesmo contrato.
        let existente = sqlx::query_as::<_, (i32, String)>(
            "SELECT atendimento_id, status_envio FROM oraculo_mensagem \
             WHERE tenant_id = $1 AND id = $2",
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .fetch_optional(&mut **tx)
        .await?;

        let Some((atendimento_id, status_envio)) = existente else {
            return Ok(None);
        };

        if status_envio != "pending" {
            // Já processada (sent/failed/dead_letter): no-op idempotente, mesmo
            // contrato de reentrega do consumer group.
            return Ok(Some(DestinoEnvioOutbound {
                atendimento_id,
                instance_id: 0,
                to_number: String::new(),
                status_envio,
                conteudo: String::new(),
            }));
        }

        sqlx::query(
            "INSERT INTO mensagem_dead_letter (tenant_id, mensagem_id, atendimento_id, motivo) \
             VALUES ($1, $2, $3, 'sem_whatsapp_contact_ativo')",
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;

        sqlx::query(
            "UPDATE oraculo_mensagem SET status_envio = 'dead_letter' \
             WHERE tenant_id = $1 AND id = $2 AND status_envio = 'pending'",
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .execute(&mut **tx)
        .await?;

        // Marcador distinto de "dead_letter" (valor persistido): sinaliza ao
        // chamador (data_postgres/handler) que ESTA chamada é que acabou de
        // registrar o dead-letter — só nesse instante a auditoria deve publicar
        // o evento `mensagem.dead_letter` (reentregas futuras caem no ramo acima,
        // com `status_envio == "dead_letter"` já persistido, e não reauditam).
        Ok(Some(DestinoEnvioOutbound {
            atendimento_id,
            instance_id: 0,
            to_number: String::new(),
            status_envio: "dead_letter_novo".to_string(),
            conteudo: String::new(),
        }))
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, dead_letter_id = dead_letter_id))]
    async fn reprocessar_dead_letter(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        dead_letter_id: i32,
        traceparent: &str,
    ) -> Result<&'static str, DbError> {
        // Reprocessar remuta estado (reenfileira o envio outbound no outbox): é
        // operação administrativa e exige escopo de admin, mesmo padrão de
        // `criar_departamento`. Defesa em profundidade sobre a RLS por tenant.
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        let registro = sqlx::query_as::<_, (i32, bool)>(
            "SELECT mensagem_id, reprocessado FROM mensagem_dead_letter \
             WHERE tenant_id = $1 AND id = $2",
        )
        .bind(ctx.tenant_id)
        .bind(dead_letter_id)
        .fetch_optional(&mut **tx)
        .await?;

        let Some((mensagem_id, ja_reprocessado)) = registro else {
            return Ok("nao_encontrada");
        };
        if ja_reprocessado {
            return Ok("reprocessada");
        }

        // Mesma checagem de destino de `resolver_destino_envio_outbound`: só
        // reprocessa se agora existe whatsapp_contact ativo para o contato.
        let destino = sqlx::query_as::<_, (i32, String, String)>(
            r#"SELECT om.atendimento_id, wc.instance_id::text, om.conteudo
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

        let Some((_atendimento_id, _instance_id, conteudo)) = destino else {
            return Ok("ainda_sem_destino");
        };

        sqlx::query(
            "UPDATE oraculo_mensagem SET status_envio = 'pending' \
             WHERE tenant_id = $1 AND id = $2 AND status_envio = 'dead_letter'",
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .execute(&mut **tx)
        .await?;

        sqlx::query(
            "UPDATE mensagem_dead_letter SET reprocessado = true WHERE tenant_id = $1 AND id = $2",
        )
        .bind(ctx.tenant_id)
        .bind(dead_letter_id)
        .execute(&mut **tx)
        .await?;

        // Reinsere no outbox (mesmo formato de `persistir_mensagem`) para o
        // worker retomar a tentativa de envio.
        let event_payload = serde_json::json!({
            "message_id": mensagem_id.to_string(),
            "sender_id": "atendente",
            "content": conteudo,
            "timestamp": chrono::Utc::now().timestamp_millis(),
        });
        let event_payload_bytes =
            serde_json::to_vec(&event_payload).map_err(|e| DbError::ConfigError(e.to_string()))?;
        sqlx::query(
            "INSERT INTO outbox (tenant_id, event_type, payload, traceparent) VALUES ($1, $2, $3, $4)",
        )
        .bind(ctx.tenant_id)
        .bind("message.persisted")
        .bind(event_payload_bytes)
        .bind(traceparent)
        .execute(&mut **tx)
        .await?;

        Ok("reprocessada")
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

    // `analise_midia`/`resumo_midia` podem conter transcrição/interpretação: PII,
    // por isso `skip_all` — nunca registrar o conteúdo no span.
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn anexar_analise_midia(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        mensagem_id: i32,
        arquivo_midia: Option<&str>,
        analise_midia: Option<&str>,
        resumo_midia: Option<&str>,
    ) -> Result<(), DbError> {
        // COALESCE preserva o valor atual quando o parâmetro chega `NULL`, para
        // atualização parcial (ex.: áudio grava resumo/transcrição, sem análise de visão).
        sqlx::query(
            r#"UPDATE oraculo_mensagem
               SET arquivo_midia = COALESCE($3, arquivo_midia),
                   analise_midia = COALESCE($4, analise_midia),
                   resumo_midia  = COALESCE($5, resumo_midia)
               WHERE tenant_id = $1 AND id = $2"#,
        )
        .bind(ctx.tenant_id)
        .bind(mensagem_id)
        .bind(arquivo_midia)
        .bind(analise_midia)
        .bind(resumo_midia)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }
}

/// B6 (N9 E4) — mensagens do contato ainda não lidas, por atendimento.
///
/// Só as do contato: o que o atendente ou o bot mandou não é "falta responder".
/// "Do contato" é tudo que não veio de `atendente` nem de `bot` — a mesma regra
/// com que a conversa decide de que lado desenhar o balão.
/// Consulta sem macro, para não depender do cache offline do sqlx.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimentos = ids.len()))]
pub async fn contar_nao_lidas_por_atendimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    ids: &[i32],
) -> Result<std::collections::HashMap<i32, i64>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    if ids.is_empty() {
        return Ok(std::collections::HashMap::new());
    }
    let linhas: Vec<(i32, i64)> = sqlx::query_as(
        r#"SELECT atendimento_id, COUNT(*)
           FROM oraculo_mensagem
           WHERE tenant_id = $1 AND atendimento_id = ANY($2)
             AND remetente NOT IN ('atendente', 'bot') AND lido = false
           GROUP BY atendimento_id"#,
    )
    .bind(ctx.tenant_id)
    .bind(ids)
    .fetch_all(&mut **tx)
    .await?;
    Ok(linhas.into_iter().collect())
}

/// B6 — o que a leitura mudou, e para onde espelhá-la no WhatsApp.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct LeituraMarcada {
    pub marcadas: i64,
    /// Ids do WhatsApp só das mensagens marcadas agora: as já lidas antes não
    /// voltam a ser avisadas ao contato.
    pub message_ids_whatsapp: Vec<String>,
    /// Instância (id no banco) e telefone do contato; `None` quando a conversa
    /// não tem WhatsApp ativo — aí a leitura fica só aqui.
    pub instance_id: Option<i32>,
    pub telefone: Option<String>,
}

/// B6 — marca como lidas as mensagens do contato numa conversa.
///
/// Mesmo RBAC fino do quadro: quem não enxerga o fluxo da conversa não a marca.
/// `data_lida` guarda o primeiro momento da leitura e não é sobrescrito.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
pub async fn marcar_lidas_do_contato(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<LeituraMarcada, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let fluxo: Option<(Option<i32>,)> = sqlx::query_as(
        "SELECT fluxo_atendimento_id FROM oraculo_atendimento WHERE tenant_id = $1 AND id = $2",
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    let Some((fluxo_id,)) = fluxo else {
        return Err(DbError::NotFound);
    };
    if let Some(fluxo_id) = fluxo_id {
        ctx.exigir_fluxo(fluxo_id)?;
    }

    let marcadas: Vec<(Option<String>,)> = sqlx::query_as(
        r#"UPDATE oraculo_mensagem
           SET lido = true, data_lida = COALESCE(data_lida, NOW())
           WHERE tenant_id = $1 AND atendimento_id = $2
             AND remetente NOT IN ('atendente', 'bot') AND lido = false
           RETURNING message_id_whatsapp"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_all(&mut **tx)
    .await?;
    let total = marcadas.len() as i64;
    let message_ids_whatsapp: Vec<String> = marcadas
        .into_iter()
        .filter_map(|(id,)| id)
        .filter(|id| !id.is_empty())
        .collect();
    if message_ids_whatsapp.is_empty() {
        return Ok(LeituraMarcada {
            marcadas: total,
            ..Default::default()
        });
    }

    let destino: Option<(i32, String)> = sqlx::query_as(
        r#"SELECT wc.instance_id, oc.telefone
           FROM oraculo_atendimento oa
           JOIN oraculo_contato oc
             ON oc.id = oa.contato_id AND oc.tenant_id = oa.tenant_id
           JOIN whatsapp_contact wc
             ON wc.contact_id = oc.id AND wc.tenant_id = oc.tenant_id AND wc.active = true
           WHERE oa.tenant_id = $1 AND oa.id = $2 AND oc.telefone IS NOT NULL
           ORDER BY wc.updated_at DESC
           LIMIT 1"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(LeituraMarcada {
        marcadas: total,
        message_ids_whatsapp,
        instance_id: destino.as_ref().map(|d| d.0),
        telefone: destino.map(|d| d.1),
    })
}

/// B9 (N10 E1) — grava as intenções e entidades detectadas numa mensagem.
///
/// O **valor** de uma entidade pode ser PII (nome, e-mail, CPF): fica só aqui,
/// na coluna, e nunca em log ou span.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
pub async fn anexar_analise_mensagem(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    mensagem_id: i32,
    intents: &serde_json::Value,
    entidades: &serde_json::Value,
) -> Result<(), DbError> {
    sqlx::query(
        r#"UPDATE oraculo_mensagem
           SET intent_detectado = $3, entidades_extraidas = $4
           WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(mensagem_id)
    .bind(intents.clone())
    .bind(entidades.clone())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// P2 — as `limit` mensagens imediatamente **anteriores** a `before_id`.
///
/// Devolve em ordem crescente, como a tela desenha. O cursor é o id (não o
/// offset) porque a conversa continua recebendo mensagem enquanto se rola o
/// histórico: com offset, cada chegada empurra a janela e a pessoa vê a mesma
/// bolha duas vezes — ou pula uma.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, before_id = before_id))]
pub async fn listar_anteriores_a(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    before_id: i32,
    limit: i64,
) -> Result<Vec<Mensagem>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, Mensagem>(
        r#"SELECT * FROM (
               SELECT id, tenant_id, atendimento_id, tipo, conteudo, remetente,
                      timestamp, message_id_whatsapp, metadados, respondida, lido,
                      resposta_bot, intent_detectado, entidades_extraidas, confianca_resposta,
                      arquivo_midia, analise_midia, resumo_midia, gerado_por_ia, mensagem_citada_id,
                      quoted_preview, status_envio, data_entregue, data_lida,
                      mimetype_midia, nome_arquivo_midia, tamanho_midia
                 FROM oraculo_mensagem
                WHERE tenant_id = $1 AND atendimento_id = $2 AND id < $3
                ORDER BY timestamp DESC, id DESC
                LIMIT $4
           ) AS anteriores
           ORDER BY timestamp ASC, id ASC"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(before_id)
    .bind(limit)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P3 — para onde mandar a presença de um atendimento: instância e telefone.
///
/// Espelha o destino do envio outbound, mas parte do **atendimento**: presença
/// não tem mensagem à qual se pendurar. Sem destino resolvível devolve `None`
/// — e quem chama simplesmente não manda nada, porque "digitando" que não
/// chega não é erro que valha interromper a conversa.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn resolver_destino_do_atendimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<Option<(i64, String)>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let row = sqlx::query_as::<_, (i64, String)>(
        r#"SELECT wc.instance_id, oc.telefone
             FROM oraculo_atendimento oa
             JOIN oraculo_contato oc
               ON oc.id = oa.contato_id AND oc.tenant_id = oa.tenant_id
             JOIN whatsapp_contact wc
               ON wc.contact_id = oc.id AND wc.tenant_id = oc.tenant_id AND wc.active = true
            WHERE oa.tenant_id = $1 AND oa.id = $2 AND oc.telefone IS NOT NULL
            ORDER BY wc.updated_at DESC
            LIMIT 1"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row)
}

/// P8 — grava (ou apaga) a reação de alguém numa mensagem.
///
/// Reação não é bolha nova: é atributo da mensagem reagida, como no WhatsApp
/// Web. Fica em `metadados.reacoes`, uma lista de `{emoji, de}`.
///
/// Uma pessoa tem **uma** reação por mensagem: reagir de novo troca a anterior,
/// que é o comportamento do WhatsApp. `emoji` vazio é remoção — o provedor manda
/// `text: ""` quando a pessoa desfaz, e guardar isso deixaria um rastro
/// invisível na bolha para sempre.
///
/// `false` no retorno = mensagem alvo desconhecida. Acontece de verdade: reagir
/// a uma conversa anterior à integração é comum, e não é erro.
#[tracing::instrument(skip_all, fields(alvo = %message_id_whatsapp))]
pub async fn aplicar_reacao(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    message_id_whatsapp: &str,
    emoji: &str,
    de: &str,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    // Tudo numa consulta só: ler, filtrar e regravar em três idas ao banco
    // abriria janela para duas reações simultâneas se perderem.
    let r = sqlx::query(
        r#"UPDATE oraculo_mensagem
              SET metadados = jsonb_set(
                    COALESCE(metadados, '{}'::jsonb),
                    '{reacoes}',
                    COALESCE(
                      (SELECT jsonb_agg(r)
                         FROM jsonb_array_elements(
                                COALESCE(metadados->'reacoes', '[]'::jsonb)
                              ) AS r
                        WHERE r->>'de' IS DISTINCT FROM $4),
                      '[]'::jsonb
                    ) || CASE WHEN $3 = '' THEN '[]'::jsonb
                              ELSE jsonb_build_array(
                                     jsonb_build_object('emoji', $3::text, 'de', $4::text)
                                   )
                         END
                  )
            WHERE tenant_id = $1 AND message_id_whatsapp = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(message_id_whatsapp)
    .bind(emoji)
    .bind(de)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// P9 — uma mensagem que ficou sem destino.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct MensagemNaoEntregue {
    pub id: i32,
    pub mensagem_id: i32,
    pub atendimento_id: i32,
    pub motivo: String,
    pub criado_em: DateTime<Utc>,
    /// Início do texto. PII — nunca em log.
    pub trecho: String,
    pub contato: String,
}

/// P9 — as mensagens pendentes de reenvio, as mais novas primeiro.
///
/// O reprocessamento existia desde a N7.2 e nenhuma tela listava o que havia a
/// reprocessar: a mensagem ficava parada sem ninguém saber que ela não chegou.
#[tracing::instrument(skip_all)]
pub async fn listar_nao_entregues(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
) -> Result<Vec<MensagemNaoEntregue>, DbError> {
    ctx.exigir_qualquer(&["operacional:read", "operacional:admin", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, MensagemNaoEntregue>(
        r#"SELECT d.id, d.mensagem_id, d.atendimento_id, d.motivo, d.criado_em,
                  LEFT(COALESCE(m.conteudo, ''), 120) AS trecho,
                  COALESCE(c.nome_contato, c.telefone, '') AS contato
             FROM mensagem_dead_letter d
             LEFT JOIN oraculo_mensagem m
                    ON m.id = d.mensagem_id AND m.tenant_id = d.tenant_id
             LEFT JOIN oraculo_atendimento a
                    ON a.id = d.atendimento_id AND a.tenant_id = d.tenant_id
             LEFT JOIN oraculo_contato c
                    ON c.id = a.contato_id AND c.tenant_id = d.tenant_id
            WHERE d.tenant_id = $1 AND d.reprocessado = false
            ORDER BY d.criado_em DESC
            LIMIT 200"#,
    )
    .bind(ctx.tenant_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}
