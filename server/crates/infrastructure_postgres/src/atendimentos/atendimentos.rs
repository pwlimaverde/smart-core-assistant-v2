use async_trait::async_trait;
use chrono::{DateTime, Utc};
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::{errors::DbError, security::RequestContext};

#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct Atendimento {
    pub id: i32,
    pub tenant_id: Uuid,
    pub contato_id: i32,
    pub departamento_id: Option<i32>,
    pub fluxo_atendimento_id: Option<i32>,
    pub status: String,
    pub etapa_atual_id: Option<i32>,
    pub data_inicio: DateTime<Utc>,
    pub data_fim: Option<DateTime<Utc>>,
    pub data_ultima_mensagem: Option<DateTime<Utc>>,
    pub assunto: Option<String>,
    pub prioridade: String,
    pub atendente_humano_id: Option<i32>,
    pub contexto_conversa: serde_json::Value,
    pub historico_status: serde_json::Value,
    pub tags: serde_json::Value,
    pub avaliacao: Option<i32>,
    pub feedback: Option<String>,
    pub data_primeira_resposta: Option<DateTime<Utc>>,
    pub bot_pode_atender: bool,
    /// Última leitura de sentimento da IA (N6.5); `None` enquanto não avaliado.
    /// Não confundir com `avaliacao`/`feedback` (satisfação informada pelo cliente).
    pub sentimento_nota: Option<i32>,
    pub sentimento_label: Option<String>,
}

/// A tradução entre a coluna do quadro e o estado do atendimento.
///
/// O quadro e o status são duas leituras da mesma coisa: um cartão parado na
/// coluna de finalização com status `fila` é uma contradição que quem opera vê
/// como sistema quebrado. Estas duas funções são o único lugar onde a
/// correspondência mora — cada movimento, em qualquer direção, passa por aqui.
///
/// O vocabulário dos dois lados vem da v1: `TipoEtapa` (fila/trabalho/espera/
/// finalizacao) e `StatusAtendimento` (fila/em_atendimento/pendencia/resolvido/
/// cancelado/arquivado).
pub fn status_do_tipo_etapa(tipo_etapa: &str, nome_etapa: &str) -> Option<&'static str> {
    match tipo_etapa {
        "fila" => Some("fila"),
        "trabalho" => Some("em_atendimento"),
        "espera" => Some("pendencia"),
        // Um fluxo tem mais de uma coluna de finalização — "Resolvido" e
        // "Cancelado" nascem juntas. O tipo diz que a conversa terminou; é o
        // NOME que diz como, e o relatório depende dessa diferença.
        //
        // Regra herdada da v1 (`board_service._aplicar_regras_tipo_etapa`):
        // casa por prefixo para aceitar as variações que o tenant escreve
        // ("Cancelado", "Cancelamento", "Cancelada").
        "finalizacao" => {
            let nome = nome_etapa.to_lowercase();
            if nome.contains("cancel") {
                Some("cancelado")
            } else if nome.contains("arquiv") || nome.contains("archiv") {
                Some("arquivado")
            } else {
                Some("resolvido")
            }
        }
        _ => None,
    }
}

/// O caminho inverso. `cancelado` e `arquivado` também caem na finalização: são
/// fins de linha, e deixá-los sem coluna esconderia o cartão do quadro.
pub fn tipo_etapa_do_status(status: &str) -> Option<&'static str> {
    match status {
        "fila" => Some("fila"),
        "em_atendimento" => Some("trabalho"),
        "pendencia" => Some("espera"),
        "resolvido" | "cancelado" | "arquivado" => Some("finalizacao"),
        _ => None,
    }
}

/// `true` para os status que encerram o atendimento.
///
/// Serve para não reescrever um `cancelado` como `resolvido` só porque o cartão
/// foi arrastado dentro da mesma coluna de finalização — os dois terminam a
/// conversa, mas por motivos diferentes, e o relatório distingue.
pub fn status_e_fim_de_linha(status: &str) -> bool {
    matches!(status, "resolvido" | "cancelado" | "arquivado")
}

#[async_trait]
pub trait AtendimentoRepository: Send + Sync {
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
        etapa_inicial_id: Option<i32>,
    ) -> Result<Atendimento, DbError>;

    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendimento>, DbError>;

    async fn listar_por_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: &str,
    ) -> Result<(), DbError>;

    async fn atualizar_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_id: i32,
        atendente_id: Option<i32>,
    ) -> Result<(), DbError>;

    async fn assumir_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<(), DbError>;

    /// Solta a conversa de quem a estava atendendo, devolvendo-a ao rodízio.
    ///
    /// **Não mexe em `bot_pode_atender`** — regra herdada da v1
    /// (`board_service`, ramo `TipoEtapa.FILA`). Quem desligou o bot foi uma
    /// pessoa, ao assumir a conversa; religá-lo por conta própria ao devolver o
    /// cartão faria o robô voltar a responder um cliente que pediu para falar
    /// com gente.
    async fn desatribuir(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    /// Acrescenta uma linha à trilha de status do atendimento.
    ///
    /// Mesmo formato da v1 (`adicionar_historico_status`): lista de
    /// `{status, timestamp, observacao}` em `historico_status`. É o que
    /// responde "quem mudou isso, e quando" quando o cliente reclama — o
    /// `status` sozinho só conta o presente.
    async fn registrar_historico_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        status: &str,
        observacao: &str,
    ) -> Result<(), DbError>;

    async fn touch_last_message(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    async fn buscar_ativo_por_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<Option<Atendimento>, DbError>;

    /// Posiciona o atendimento na etapa inicial do Kanban, atribuindo fluxo e
    /// departamento padrão quando ainda ausentes e marcando o status como 'fila'.
    /// Usado pela política de ticket/Kanban (WS-2.4).
    async fn atribuir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: Option<i32>,
        etapa_id: i32,
    ) -> Result<(), DbError>;

    /// Transfere o atendimento para outro fluxo (N6.3): SOBRESCREVE fluxo/departamento/
    /// etapa (diferente de `atribuir_fluxo_etapa`, que preserva o fluxo já definido via
    /// COALESCE). Usado pela transferência automática decidida pela IA.
    async fn transferir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: i32,
        etapa_id: i32,
    ) -> Result<(), DbError>;

    /// Atualiza a última leitura de sentimento do atendimento (N6.5, best-effort —
    /// não é `avaliacao`/`feedback` de satisfação do cliente, é a análise da IA
    /// sobre o tom da conversa). Sobrescreve sempre com a leitura mais recente.
    async fn atualizar_sentimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError>;

    /// Varredura CROSS-TENANT (scheduler do worker, F4.3b): atendimentos resolvidos,
    /// sem feedback registrado e ainda não marcados como expirados, cuja `data_fim`
    /// ultrapassou o TTL. `ctx` é usado apenas para a checagem de escopo — a consulta
    /// não filtra por tenant (exige pool com BYPASSRLS).
    async fn listar_feedback_vencido(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    /// Marca o atendimento como tendo o feedback expirado (idempotente: chamada
    /// futura para o mesmo id é no-op pois `feedback_expirado_em` já estará setado
    /// e o `listar_feedback_vencido` não o retornará de novo).
    async fn marcar_feedback_expirado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    /// N8.5/E3 — registra que a pesquisa de satisfação foi ENVIADA ao contato.
    ///
    /// Sem esta marca não existe diferença observável entre "o cliente não
    /// respondeu" e "nunca foi perguntado" — e era essa ambiguidade que fazia o
    /// expirador marcar como vencido todo atendimento resolvido.
    ///
    /// Idempotente: só grava quando ainda está nulo, para uma reentrega não
    /// reabrir a janela de resposta do contato.
    async fn marcar_feedback_solicitado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<bool, DbError>;

    /// N8.5/E3 — grava a nota (1..5) e o comentário do contato.
    ///
    /// Só age em atendimento com pesquisa solicitada e ainda sem avaliação: a
    /// mensagem seguinte do contato num atendimento que nunca foi perguntado é
    /// conversa nova, não resposta de pesquisa.
    ///
    /// Devolve `true` quando gravou de fato.
    async fn registrar_avaliacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        comentario: &str,
    ) -> Result<bool, DbError>;

    /// N8.5/E3 — o atendimento está aguardando resposta da pesquisa?
    ///
    /// `ttl_horas` limita a janela: passado o prazo do expirador, a fala do
    /// contato volta a ser conversa comum.
    async fn aguardando_avaliacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        ttl_horas: i64,
    ) -> Result<bool, DbError>;
}

pub struct PostgresAtendimentoRepository;

#[async_trait]
impl AtendimentoRepository for PostgresAtendimentoRepository {
    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn criar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        departamento_id: Option<i32>,
        fluxo_id: Option<i32>,
        etapa_inicial_id: Option<i32>,
    ) -> Result<Atendimento, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Atendimento,
            r#"INSERT INTO oraculo_atendimento
                   (tenant_id, contato_id, departamento_id, fluxo_atendimento_id, etapa_atual_id)
               VALUES ($1, $2, $3, $4, $5)
               RETURNING id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                         status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                         assunto, prioridade, atendente_humano_id, contexto_conversa,
                         historico_status, tags, avaliacao, feedback,
                         data_primeira_resposta, bot_pode_atender,
                         sentimento_nota, sentimento_label"#,
            ctx.tenant_id,
            contato_id,
            departamento_id,
            fluxo_id,
            etapa_inicial_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(id = id))]
    async fn buscar_por_id(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<Atendimento>, DbError> {
        let row = sqlx::query_as!(
            Atendimento,
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender,
                      sentimento_nota, sentimento_label
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            id
        )
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(status = %status, limit = limit))]
    async fn listar_por_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
        let rows = sqlx::query_as!(
            Atendimento,
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender,
                      sentimento_nota, sentimento_label
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND status = $2
                 AND ($3::int IS NULL OR departamento_id = $3)
               ORDER BY data_inicio DESC
               LIMIT $4"#,
            ctx.tenant_id,
            status,
            departamento_id,
            limit
        )
        .fetch_all(&mut **tx)
        .await?;

        // RBAC fino por fluxo (WS-5a): atendimentos já roteados a um fluxo Kanban só
        // aparecem para quem tem flow_permission (ou bypass kanban:admin/tenant:admin).
        // Sem fluxo atribuído ainda (pré-roteamento) permanece visível a todos com escopo.
        let visiveis = rows
            .into_iter()
            .filter(|a| match a.fluxo_atendimento_id {
                Some(fluxo_id) => ctx.has_flow_permission(fluxo_id),
                None => true,
            })
            .collect();
        Ok(visiveis)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, novo_status = %novo_status))]
    async fn atualizar_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: &str,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET status = $1::text,
                   data_fim = CASE WHEN $1::text IN ('resolvido','cancelado','arquivado')
                                   THEN NOW() ELSE data_fim END
               WHERE tenant_id = $2 AND id = $3"#,
            novo_status,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, etapa_id = etapa_id))]
    async fn atualizar_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_id: i32,
        atendente_id: Option<i32>,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET etapa_atual_id = $1,
                   atendente_humano_id = COALESCE($2, atendente_humano_id)
               WHERE tenant_id = $3 AND id = $4"#,
            etapa_id,
            atendente_id,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, atendente_id = atendente_id))]
    async fn assumir_atendimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Desliga o bot e atribui o atendente humano
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET atendente_humano_id = $1,
                   bot_pode_atender = false,
                   status = 'em_atendimento'
               WHERE tenant_id = $2 AND id = $3"#,
            atendente_id,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn desatribuir(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // `bot_pode_atender` fica como está, de propósito: ver a doc do trait.
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET atendente_humano_id = NULL
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    // `observacao` pode citar o nome de quem agiu: `skip_all`.
    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, status = %status))]
    async fn registrar_historico_status(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        status: &str,
        observacao: &str,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let entrada = serde_json::json!({
            "status": status,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "observacao": observacao,
        });
        // `||` no próprio UPDATE em vez de ler-modificar-gravar: duas
        // transições simultâneas sobre o mesmo atendimento perderiam uma
        // linha da trilha se a lista fosse remontada em Rust.
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
                  SET historico_status = COALESCE(historico_status, '[]'::jsonb) || $3::jsonb
                WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            atendimento_id,
            serde_json::Value::Array(vec![entrada])
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn touch_last_message(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET data_ultima_mensagem = NOW()
               WHERE tenant_id = $1 AND id = $2"#,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(contato_id = contato_id))]
    async fn buscar_ativo_por_contato(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
    ) -> Result<Option<Atendimento>, DbError> {
        let row = sqlx::query_as::<_, Atendimento>(
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender,
                      sentimento_nota, sentimento_label
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND contato_id = $2 
                 AND status NOT IN ('resolvido', 'cancelado', 'arquivado')
               LIMIT 1"#,
        )
        .bind(ctx.tenant_id)
        .bind(contato_id)
        .fetch_optional(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, fluxo_id = fluxo_id, etapa_id = etapa_id))]
    async fn atribuir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: Option<i32>,
        etapa_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        // COALESCE preserva fluxo/departamento já definidos; só preenche quando nulos.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET fluxo_atendimento_id = COALESCE(fluxo_atendimento_id, $1),
                   departamento_id = COALESCE(departamento_id, $2),
                   etapa_atual_id = $3,
                   status = 'fila'
               WHERE tenant_id = $4 AND id = $5"#,
        )
        .bind(fluxo_id)
        .bind(departamento_id)
        .bind(etapa_id)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, fluxo_id = fluxo_id, etapa_id = etapa_id))]
    async fn transferir_fluxo_etapa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
        departamento_id: i32,
        etapa_id: i32,
    ) -> Result<(), DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        // SOBRESCREVE (sem COALESCE): a transferência muda o fluxo de fato.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET fluxo_atendimento_id = $1,
                   departamento_id = $2,
                   etapa_atual_id = $3,
                   status = 'fila'
               WHERE tenant_id = $4 AND id = $5"#,
        )
        .bind(fluxo_id)
        .bind(departamento_id)
        .bind(etapa_id)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, nota = nota))]
    async fn atualizar_sentimento(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError> {
        // Query em runtime (sem macro) para não exigir cache .sqlx no build offline.
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET sentimento_nota = $1, sentimento_label = $2
               WHERE tenant_id = $3 AND id = $4"#,
        )
        .bind(nota)
        .bind(label)
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(limite = limite, ttl_horas = ttl_horas))]
    async fn listar_feedback_vencido(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS (admin_pool).
        let rows = sqlx::query_as::<_, Atendimento>(
            r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                      status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                      assunto, prioridade, atendente_humano_id, contexto_conversa,
                      historico_status, tags, avaliacao, feedback,
                      data_primeira_resposta, bot_pode_atender,
                      sentimento_nota, sentimento_label
               FROM oraculo_atendimento
               WHERE status = 'resolvido'
                 AND feedback IS NULL
                 AND avaliacao IS NULL
                 AND feedback_expirado_em IS NULL
                 -- N8.5/E3: só expira o que foi de fato PERGUNTADO. Sem esta
                 -- linha, o job marcava como "feedback expirado" todo
                 -- atendimento resolvido — inclusive os que nunca receberam a
                 -- pesquisa, que até a N8.5 eram todos.
                 AND feedback_solicitado_em IS NOT NULL
                 AND data_fim IS NOT NULL
                 AND data_fim < NOW() - ($1 || ' hours')::interval
               ORDER BY data_fim ASC
               LIMIT $2"#,
        )
        .bind(ttl_horas.to_string())
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn marcar_feedback_expirado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError> {
        sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET feedback_expirado_em = NOW()
               WHERE tenant_id = $1 AND id = $2 AND feedback_expirado_em IS NULL"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(())
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn marcar_feedback_solicitado(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<bool, DbError> {
        let r = sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET feedback_solicitado_em = NOW()
               WHERE tenant_id = $1 AND id = $2 AND feedback_solicitado_em IS NULL"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(r.rows_affected() > 0)
    }

    #[tracing::instrument(
        skip_all,
        fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id, nota = nota)
    )]
    async fn registrar_avaliacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        comentario: &str,
    ) -> Result<bool, DbError> {
        // O comentário é texto livre do cliente — PII. Fica só na coluna: não
        // entra em span (`skip_all` acima), log, métrica nem descrição de
        // auditoria. O que circula é a nota.
        let r = sqlx::query(
            r#"UPDATE oraculo_atendimento
               SET avaliacao = $3, feedback = NULLIF($4, '')
               WHERE tenant_id = $1 AND id = $2
                 AND feedback_solicitado_em IS NOT NULL
                 AND avaliacao IS NULL"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .bind(nota)
        .bind(comentario)
        .execute(&mut **tx)
        .await?;
        Ok(r.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn aguardando_avaliacao(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        ttl_horas: i64,
    ) -> Result<bool, DbError> {
        let existe: Option<i32> = sqlx::query_scalar(
            r#"SELECT 1
               FROM oraculo_atendimento
               WHERE tenant_id = $1 AND id = $2
                 AND feedback_solicitado_em IS NOT NULL
                 AND avaliacao IS NULL
                 AND feedback_solicitado_em > NOW() - ($3 || ' hours')::interval"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .bind(ttl_horas.to_string())
        .fetch_optional(&mut **tx)
        .await?;
        Ok(existe.is_some())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A regra que decide o desfecho de um atendimento encerrado.
    ///
    /// Vale a pena travar: um fluxo nasce com duas colunas de finalização
    /// ("Resolvido" e "Cancelado"), e tratá-las igual apagaria a diferença
    /// entre um atendimento concluído e um desistido — que é exatamente o que
    /// o relatório de operação precisa distinguir.
    #[test]
    fn nome_da_coluna_decide_o_desfecho_da_finalizacao() {
        assert_eq!(
            status_do_tipo_etapa("finalizacao", "Resolvido"),
            Some("resolvido")
        );
        assert_eq!(
            status_do_tipo_etapa("finalizacao", "Cancelado"),
            Some("cancelado")
        );
        assert_eq!(
            status_do_tipo_etapa("finalizacao", "Arquivado"),
            Some("arquivado")
        );
    }

    #[test]
    fn a_regra_do_nome_aceita_as_variacoes_que_o_tenant_escreve() {
        // Casa por trecho, não por igualdade: quem renomeia a coluna escreve
        // "Cancelamento", "Cancelados", "CANCELADO".
        for nome in [
            "Cancelamento",
            "cancelados",
            "CANCELADO",
            "Pedido cancelado",
        ] {
            assert_eq!(
                status_do_tipo_etapa("finalizacao", nome),
                Some("cancelado"),
                "nome: {nome}"
            );
        }
    }

    #[test]
    fn finalizacao_com_nome_qualquer_resolve() {
        // O padrão é resolver: encerrar sem dizer o contrário é conclusão.
        assert_eq!(
            status_do_tipo_etapa("finalizacao", "Entregue"),
            Some("resolvido")
        );
        assert_eq!(status_do_tipo_etapa("finalizacao", ""), Some("resolvido"));
    }

    #[test]
    fn os_demais_tipos_ignoram_o_nome() {
        // Só a finalização tem mais de um desfecho; renomear a fila não muda
        // o que ela significa.
        assert_eq!(status_do_tipo_etapa("fila", "Cancelado"), Some("fila"));
        assert_eq!(
            status_do_tipo_etapa("trabalho", "Cancelado"),
            Some("em_atendimento")
        );
        assert_eq!(
            status_do_tipo_etapa("espera", "Arquivado"),
            Some("pendencia")
        );
    }

    #[test]
    fn tipo_desconhecido_nao_muda_status() {
        // A coluna é VARCHAR(20): uma linha antiga com valor fora do
        // vocabulário não deve mexer no estado do atendimento.
        assert_eq!(status_do_tipo_etapa("inventado", "x"), None);
    }

    #[test]
    fn o_caminho_de_volta_leva_todo_fim_de_linha_a_finalizacao() {
        // Cancelado e arquivado precisam de coluna: sem ela o cartão sumiria
        // do quadro.
        for status in ["resolvido", "cancelado", "arquivado"] {
            assert_eq!(tipo_etapa_do_status(status), Some("finalizacao"));
        }
        assert_eq!(tipo_etapa_do_status("fila"), Some("fila"));
        assert_eq!(tipo_etapa_do_status("em_atendimento"), Some("trabalho"));
        assert_eq!(tipo_etapa_do_status("pendencia"), Some("espera"));
    }

    #[test]
    fn fim_de_linha_cobre_os_tres_desfechos() {
        assert!(status_e_fim_de_linha("resolvido"));
        assert!(status_e_fim_de_linha("cancelado"));
        assert!(status_e_fim_de_linha("arquivado"));
        assert!(!status_e_fim_de_linha("em_atendimento"));
        assert!(!status_e_fim_de_linha("pendencia"));
        assert!(!status_e_fim_de_linha("fila"));
    }
}
