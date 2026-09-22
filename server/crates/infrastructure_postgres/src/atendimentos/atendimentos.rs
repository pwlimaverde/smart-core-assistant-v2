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

/// Uma conversa parada, do ponto de vista da varredura do scheduler (D5).
///
/// Só id e tenant: o job não precisa da linha inteira, e trazer o atendimento
/// completo levaria junto `assunto` e `contexto_conversa` — conteúdo do cliente
/// — para dentro de um caminho que só quer saber o que arquivar.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct AtendimentoInativo {
    pub id: i32,
    pub tenant_id: Uuid,
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

    /// Cria um atendimento que **uma pessoa** começou, não uma mensagem que
    /// chegou.
    ///
    /// Difere de [`AtendimentoRepository::criar`] em três pontos, e cada um
    /// tem razão:
    ///
    /// - **`etapa_inicial_id` é obrigatório.** A ingestão cria sem etapa e o
    ///   fluxo é preenchido depois por `COALESCE`; um atendimento sem etapa
    ///   não aparece em coluna nenhuma do quadro — nasceria invisível, o que
    ///   para uma conversa que alguém acabou de abrir é o pior desfecho.
    /// - **`bot_pode_atender = false`.** Alguém decidiu falar com esse
    ///   cliente; o robô não entra no meio de uma conversa que uma pessoa
    ///   começou. O caminho de volta existe e é um clique
    ///   (`definir_bot_da_conversa`).
    /// - **`atendente_humano_id` = quem criou, quando quem criou atende.** A
    ///   coluna aponta para `oraculo_atendente`, não para `auth_user`, e nem
    ///   todo usuário do tenant é atendente: um admin que abre a conversa não
    ///   vira dono dela por isso. Quem resolve o vínculo é o chamador, que tem
    ///   a transação na mão; `None` deixa a conversa na fila, para a
    ///   distribuição normal cuidar.
    async fn criar_manual(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        fluxo_id: i32,
        etapa_inicial_id: i32,
        departamento_id: Option<i32>,
        atendente_id: Option<i32>,
        assunto: Option<&str>,
    ) -> Result<Atendimento, DbError>;

    /// Quantas conversas foram abertas hoje sem nenhuma mensagem trocada.
    ///
    /// É o retrato do disparo em massa, e só dele: uma conversa que veio de
    /// mensagem recebida já nasce com `data_ultima_mensagem`, e uma que
    /// alguém assumiu também. O que sobra são fichas abertas de propósito e
    /// ainda mudas — exatamente o que o teto do C3 limita.
    async fn contar_abertas_hoje_sem_mensagem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<i64, DbError>;

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

    /// Atribui o atendimento a um atendente **sem roubar** conversa que já tem
    /// dono (D2).
    ///
    /// `false` no retorno = já havia alguém atendendo, ou o atendimento não
    /// existe. O rodízio nunca tira uma conversa de quem já a pegou: quem está
    /// no meio de um atendimento não pode vê-lo desaparecer da própria fila.
    ///
    /// Não mexe em `status` nem em `bot_pode_atender`: atribuir é dizer de quem
    /// é a conversa, não dizer que ela já começou a ser atendida. Marcar
    /// `em_atendimento` aqui faria o painel mentir sobre quem está trabalhando.
    async fn atribuir_se_livre(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<bool, DbError>;

    /// Liga/desliga a resposta automática da IA **nesta conversa** (D3).
    ///
    /// O caminho de volta que faltava. `assumir_atendimento` desliga o bot, e
    /// nada no servidor devolvia o valor para `true` — uma conversa que passou
    /// por um humano ficava sem bot para sempre, sem tela para reverter.
    ///
    /// Isto **não** enfraquece a regra documentada em [`Self::desatribuir`]:
    /// devolver o cartão continua sem religar sozinho. A diferença é que agora
    /// existe uma ação deliberada para religar, em vez de nenhuma.
    async fn definir_bot_da_conversa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        habilitado: bool,
    ) -> Result<bool, DbError>;

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

    /// D5 — conversas paradas tempo demais, prontas para arquivar.
    ///
    /// Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS. O prazo é
    /// resolvido por linha — cada tenant pode ter o seu, com o padrão global
    /// como piso.
    async fn listar_inativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        minutos_padrao: i64,
    ) -> Result<Vec<AtendimentoInativo>, DbError>;

    /// D5 — arquiva a conversa abandonada.
    ///
    /// **`arquivado`, nunca `resolvido`.** Não é preciosismo de vocabulário: a
    /// pesquisa de satisfação é disparada por
    /// `solicitar_pesquisa_satisfacao`, que só age quando o status novo é
    /// `resolvido`. Encerrar por inatividade como resolvido perguntaria "como
    /// foi seu atendimento?" a quem justamente parou de responder — e ainda
    /// contaminaria a métrica de satisfação com conversas que nunca terminaram.
    /// A regra fica garantida pela estrutura, não por um `if` que alguém pode
    /// remover depois.
    async fn encerrar_por_inatividade(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<bool, DbError>;

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

    #[tracing::instrument(skip_all, fields(contato_id = contato_id, fluxo_id = fluxo_id))]
    async fn criar_manual(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato_id: i32,
        fluxo_id: i32,
        etapa_inicial_id: i32,
        departamento_id: Option<i32>,
        atendente_id: Option<i32>,
        assunto: Option<&str>,
    ) -> Result<Atendimento, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let row = sqlx::query_as!(
            Atendimento,
            r#"INSERT INTO oraculo_atendimento
                   (tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                    etapa_atual_id, atendente_humano_id, bot_pode_atender, assunto)
               VALUES ($1, $2, $3, $4, $5, $6, FALSE, $7)
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
            etapa_inicial_id,
            atendente_id,
            assunto
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(row)
    }

    #[tracing::instrument(skip_all)]
    async fn contar_abertas_hoje_sem_mensagem(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
    ) -> Result<i64, DbError> {
        // `date_trunc` no fuso do banco: o teto é diário no relógio do
        // servidor, e não uma janela deslizante de 24 h. Quem esbarrou nele
        // hoje volta a poder amanhã, que é o que se explica na tela.
        let total = sqlx::query_scalar!(
            r#"SELECT COUNT(*) FROM oraculo_atendimento
                WHERE tenant_id = $1
                  AND data_inicio >= date_trunc('day', NOW())
                  AND data_ultima_mensagem IS NULL"#,
            ctx.tenant_id
        )
        .fetch_one(&mut **tx)
        .await?;
        Ok(total.unwrap_or(0))
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

    #[tracing::instrument(skip_all, fields(limite = limite, minutos_padrao = minutos_padrao))]
    async fn listar_inativos(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        limite: i64,
        minutos_padrao: i64,
    ) -> Result<Vec<AtendimentoInativo>, DbError> {
        ctx.exigir_qualquer(&["operacional:admin"])?;
        // Cross-tenant por desenho (scheduler): exige pool com BYPASSRLS.
        //
        // Só `fila` e `pendencia`. `em_atendimento` fica de fora de propósito:
        // uma pessoa no meio de um caso pode passar meia hora sem escrever
        // (consultando um sistema, falando com outro setor), e ver o cartão
        // sumir da própria tela seria pior que qualquer fila inflada.
        //
        // O prazo é resolvido por linha, com cascata tenant > global > 30. O
        // filtro `value ~ '^[0-9]+$'` é o "cast que não explode": CoreSettings é
        // texto livre, e um valor inválido cai no padrão em vez de derrubar a
        // varredura inteira do sistema.
        //
        // `COALESCE(data_ultima_mensagem, data_inicio)`: conversa criada e nunca
        // respondida tem `data_ultima_mensagem` nula e também precisa vencer —
        // era justamente a que ficava para sempre.
        let rows = sqlx::query_as::<_, AtendimentoInativo>(
            r#"WITH padrao AS (
                   SELECT COALESCE(
                       (SELECT value::int
                          FROM settings_manager_coresettings
                         WHERE key = 'MINUTOS_INATIVIDADE_ENCERRA'
                           AND value ~ '^[0-9]+$'),
                       $1
                   ) AS minutos
               )
               SELECT a.id, a.tenant_id
                 FROM oraculo_atendimento a
                 LEFT JOIN tenants_tenantconfig tc ON tc.tenant_id = a.tenant_id
                 CROSS JOIN padrao p
                WHERE a.status IN ('fila', 'pendencia')
                  AND COALESCE(tc.minutos_inatividade_encerra, p.minutos) > 0
                  AND COALESCE(a.data_ultima_mensagem, a.data_inicio)
                      < NOW() - (COALESCE(tc.minutos_inatividade_encerra, p.minutos)
                                 || ' minutes')::interval
                ORDER BY COALESCE(a.data_ultima_mensagem, a.data_inicio) ASC
                LIMIT $2"#,
        )
        .bind(minutos_padrao as i32)
        .bind(limite)
        .fetch_all(&mut **tx)
        .await?;
        Ok(rows)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
    async fn encerrar_por_inatividade(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["operacional:admin", "tenant:admin"])?;
        // Recheca o status no UPDATE, e não só na varredura: entre a leitura
        // cross-tenant e esta escrita o cliente pode ter voltado a escrever. Sem
        // a recheca, o scheduler arquivaria uma conversa que acabou de reviver.
        let res = sqlx::query(
            r#"UPDATE oraculo_atendimento
                  SET status = 'arquivado', data_fim = NOW()
                WHERE tenant_id = $1 AND id = $2
                  AND status IN ('fila', 'pendencia')"#,
        )
        .bind(ctx.tenant_id)
        .bind(atendimento_id)
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, atendente_id = atendente_id))]
    async fn atribuir_se_livre(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        atendente_id: i32,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_atendimento
                  SET atendente_humano_id = $1
                WHERE tenant_id = $2 AND id = $3
                  AND atendente_humano_id IS NULL"#,
            atendente_id,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
    }

    #[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, habilitado = habilitado))]
    async fn definir_bot_da_conversa(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        atendimento_id: i32,
        habilitado: bool,
    ) -> Result<bool, DbError> {
        ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
        let res = sqlx::query!(
            r#"UPDATE oraculo_atendimento
               SET bot_pode_atender = $1
               WHERE tenant_id = $2 AND id = $3"#,
            habilitado,
            ctx.tenant_id,
            atendimento_id
        )
        .execute(&mut **tx)
        .await?;
        Ok(res.rows_affected() > 0)
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

/// B9 (N10 E2) — preenche o assunto do atendimento **só quando está vazio**.
///
/// Nunca sobrescreve o que um humano escreveu. `true` quando gravou.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
pub async fn definir_assunto_se_vazio(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    assunto: &str,
) -> Result<bool, DbError> {
    let res = sqlx::query(
        r#"UPDATE oraculo_atendimento
           SET assunto = $3
           WHERE tenant_id = $1 AND id = $2
             AND (assunto IS NULL OR btrim(assunto) = '')"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .bind(assunto)
    .execute(&mut **tx)
    .await?;
    Ok(res.rows_affected() > 0)
}

/// P1 — o recorte da lista do quadro, igual ao da v1 (`list_conversations`).
///
/// Campo vazio/zero = sem filtro. `atendente_id = Some(-1)` é "sem dono": a
/// fila que ninguém assumiu, que na v1 era o filtro mais usado do supervisor.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct FiltroDoQuadro {
    pub busca: String,
    pub atendente_id: Option<i32>,
    pub somente_nao_lidos: bool,
    pub prioridade: String,
    pub etiqueta_id: Option<i64>,
    /// "minhas conversas": resolvido aqui pelo `user_id` do contexto.
    pub somente_meus: bool,
}

/// Todos os atendimentos **ativos** do tenant (tudo menos `arquivado`).
///
/// É o que o quadro pede quando não filtra por status: as colunas vão de "fila"
/// a "finalização", e listar só `fila` deixava o quadro vazio assim que a
/// conversa andava — que é o estado normal de quem está atendendo. Arquivado
/// fica de fora porque o quadro é o trabalho de agora, não o histórico.
///
/// Ordena pela **última mensagem**, como a v1: o quadro é a fila de quem está
/// esperando resposta, e ordenar pela abertura empurra para baixo justamente a
/// conversa que acabou de receber mensagem.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, limit = limit))]
pub async fn listar_ativos_do_tenant(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    departamento_id: Option<i32>,
    filtro: &FiltroDoQuadro,
    limit: i64,
) -> Result<Vec<Atendimento>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let busca = filtro.busca.trim();
    let rows = sqlx::query_as::<_, Atendimento>(
        r#"SELECT a.id, a.tenant_id, a.contato_id, a.departamento_id, a.fluxo_atendimento_id,
                  a.status, a.etapa_atual_id, a.data_inicio, a.data_fim, a.data_ultima_mensagem,
                  a.assunto, a.prioridade, a.atendente_humano_id, a.contexto_conversa,
                  a.historico_status, a.tags, a.avaliacao, a.feedback,
                  a.data_primeira_resposta, a.bot_pode_atender,
                  a.sentimento_nota, a.sentimento_label
           FROM oraculo_atendimento a
           LEFT JOIN oraculo_contato c
             ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
           WHERE a.tenant_id = $1 AND a.status <> 'arquivado'
             AND ($2::int IS NULL OR a.departamento_id = $2)
             AND ($3 = '' OR COALESCE(c.nome_contato, '') ILIKE '%' || $3 || '%'
                  OR COALESCE(c.nome_perfil_whatsapp, '') ILIKE '%' || $3 || '%'
                  OR COALESCE(c.telefone, '') LIKE '%' || $3 || '%'
                  OR COALESCE(a.assunto, '') ILIKE '%' || $3 || '%')
             AND ($4::int IS NULL
                  OR ($4 = -1 AND a.atendente_humano_id IS NULL)
                  OR a.atendente_humano_id = $4)
             AND ($5 = '' OR a.prioridade = $5)
             AND (NOT $9 OR a.atendente_humano_id IN (
                   SELECT at.id FROM oraculo_atendente at
                    WHERE at.tenant_id = a.tenant_id AND at.usuario_id = $10))
             AND ($6::int IS NULL OR EXISTS (
                   SELECT 1 FROM atu_etiqueta_atendimento ea
                    WHERE ea.tenant_id = a.tenant_id AND ea.atendimento_id = a.id
                      AND ea.etiqueta_id = $6))
             AND (NOT $7 OR EXISTS (
                   SELECT 1 FROM oraculo_mensagem m
                    WHERE m.tenant_id = a.tenant_id AND m.atendimento_id = a.id
                      AND m.lido = false AND m.remetente = 'contato'))
           ORDER BY COALESCE(a.data_ultima_mensagem, a.data_inicio) DESC
           LIMIT $8"#,
    )
    .bind(ctx.tenant_id)
    .bind(departamento_id)
    .bind(busca)
    .bind(filtro.atendente_id)
    .bind(filtro.prioridade.trim())
    .bind(filtro.etiqueta_id)
    .bind(filtro.somente_nao_lidos)
    .bind(limit)
    .bind(filtro.somente_meus)
    .bind(ctx.user_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P3 — o atendimento ativo de um telefone, sem criar nada.
///
/// Serve à presença ("digitando..."), que chega da Evolution identificada só
/// pelo número. Diferente do `ResolveAtendimentoParaContato` da ingestão, aqui
/// **não** se cria contato nem atendimento: ninguém abre uma conversa porque o
/// outro lado encostou no teclado.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn buscar_ativo_por_telefone(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    telefone: &str,
) -> Result<Option<i32>, DbError> {
    let row = sqlx::query_as::<_, (i32,)>(
        r#"SELECT a.id
             FROM oraculo_atendimento a
             JOIN oraculo_contato c
               ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
            WHERE a.tenant_id = $1
              AND c.telefone = $2
              AND a.status NOT IN ('resolvido', 'cancelado', 'arquivado')
            ORDER BY a.data_inicio DESC
            LIMIT 1"#,
    )
    .bind(ctx.tenant_id)
    .bind(telefone)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.map(|(id,)| id))
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

/// P4 — a urgência do cartão.
///
/// O conjunto é fechado de propósito: a coluna é texto livre no banco, e um
/// valor fora da lista viraria um cartão que nenhum filtro encontra.
pub const PRIORIDADES: [&str; 4] = ["baixa", "normal", "alta", "urgente"];

#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id, prioridade = prioridade))]
pub async fn definir_prioridade(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
    prioridade: &str,
) -> Result<bool, DbError> {
    ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])?;
    // A validação do conjunto fechado é do handler, que sabe devolver
    // `Validation` ao cliente; aqui um valor estranho não deve chegar.
    debug_assert!(PRIORIDADES.contains(&prioridade));
    let r = sqlx::query(
        "UPDATE oraculo_atendimento SET prioridade = $1 WHERE tenant_id = $2 AND id = $3",
    )
    .bind(prioridade)
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// P4 — o atendente ligado ao usuário logado, quando existe.
///
/// É o que traduz "atribuir a mim" para um id de atendente: a tela conhece o
/// usuário da sessão, nunca o cadastro de atendentes.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn atendente_do_usuario(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
) -> Result<Option<i32>, DbError> {
    let row = sqlx::query_as::<_, (i32,)>(
        "SELECT id FROM oraculo_atendente \
         WHERE tenant_id = $1 AND usuario_id = $2 AND ativo = true LIMIT 1",
    )
    .bind(ctx.tenant_id)
    .bind(ctx.user_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.map(|(id,)| id))
}

/// P4 — uma linha do quadro exportado.
///
/// Traz o nome e o telefone do contato porque um CSV de ids não serve para
/// nada a quem vai abrir a planilha — e é justamente por trazer isso que a
/// exportação é auditada na camada de cima.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct LinhaDoQuadro {
    pub id: i32,
    pub contato: Option<String>,
    pub telefone: Option<String>,
    pub assunto: Option<String>,
    pub status: String,
    pub prioridade: String,
    pub atendente: Option<String>,
    pub fluxo: Option<String>,
    pub etapa: Option<String>,
    pub data_inicio: chrono::DateTime<chrono::Utc>,
    pub data_ultima_mensagem: Option<chrono::DateTime<chrono::Utc>>,
    pub nao_lidas: i64,
}

/// P4 — o quadro inteiro (no recorte pedido) para exportação.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn exportar_quadro(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    departamento_id: Option<i32>,
    filtro: &FiltroDoQuadro,
    limit: i64,
) -> Result<Vec<LinhaDoQuadro>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let busca = filtro.busca.trim();
    let rows = sqlx::query_as::<_, LinhaDoQuadro>(
        r#"SELECT a.id,
                  c.nome_contato AS contato,
                  c.telefone,
                  a.assunto,
                  a.status,
                  a.prioridade,
                  at.nome AS atendente,
                  f.nome AS fluxo,
                  e.nome AS etapa,
                  a.data_inicio,
                  a.data_ultima_mensagem,
                  (SELECT COUNT(*) FROM oraculo_mensagem m
                    WHERE m.tenant_id = a.tenant_id AND m.atendimento_id = a.id
                      AND m.lido = false AND m.remetente = 'contato') AS nao_lidas
           FROM oraculo_atendimento a
           LEFT JOIN oraculo_contato c
             ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
           LEFT JOIN oraculo_atendente at
             ON at.id = a.atendente_humano_id AND at.tenant_id = a.tenant_id
           LEFT JOIN oraculo_fluxo_atendimento f
             ON f.id = a.fluxo_atendimento_id AND f.tenant_id = a.tenant_id
           LEFT JOIN oraculo_etapa_fluxo e
             ON e.id = a.etapa_atual_id AND e.tenant_id = a.tenant_id
           WHERE a.tenant_id = $1 AND a.status <> 'arquivado'
             AND ($2::int IS NULL OR a.departamento_id = $2)
             AND ($3 = '' OR COALESCE(c.nome_contato, '') ILIKE '%' || $3 || '%'
                  OR COALESCE(c.nome_perfil_whatsapp, '') ILIKE '%' || $3 || '%'
                  OR COALESCE(c.telefone, '') LIKE '%' || $3 || '%'
                  OR COALESCE(a.assunto, '') ILIKE '%' || $3 || '%')
             AND (NOT $4 OR a.atendente_humano_id IN (
                   SELECT x.id FROM oraculo_atendente x
                    WHERE x.tenant_id = a.tenant_id AND x.usuario_id = $5))
             AND (NOT $6 OR EXISTS (
                   SELECT 1 FROM oraculo_mensagem m
                    WHERE m.tenant_id = a.tenant_id AND m.atendimento_id = a.id
                      AND m.lido = false AND m.remetente = 'contato'))
           ORDER BY COALESCE(a.data_ultima_mensagem, a.data_inicio) DESC
           LIMIT $7"#,
    )
    .bind(ctx.tenant_id)
    .bind(departamento_id)
    .bind(busca)
    .bind(filtro.somente_meus)
    .bind(ctx.user_id)
    .bind(filtro.somente_nao_lidos)
    .bind(limit)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P5 — um acontecimento da vida do atendimento, já pronto para a tela.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct EventoDaTimeline {
    pub tipo: String,
    pub quando: chrono::DateTime<chrono::Utc>,
    pub descricao: String,
    pub autor: Option<String>,
    pub automatico: bool,
}

/// P5 — a linha do tempo do atendimento.
///
/// Junta numa consulta só o que estava espalhado por quatro tabelas. É um
/// `UNION ALL` e não quatro chamadas porque a tela desenha uma lista ordenada:
/// fundir no cliente daria a mesma coisa com quatro idas ao banco e a chance
/// de mostrar metade da história enquanto a outra metade não chegou.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn listar_timeline(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<Vec<EventoDaTimeline>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, EventoDaTimeline>(
        r#"
        SELECT 'aberto' AS tipo,
               a.data_inicio AS quando,
               COALESCE(NULLIF(a.assunto, ''), 'Conversa iniciada') AS descricao,
               NULL::varchar AS autor,
               true AS automatico
          FROM oraculo_atendimento a
         WHERE a.tenant_id = $1 AND a.id = $2

        UNION ALL

        SELECT 'movido',
               m.data_movimento,
               COALESCE(eo.nome, 'início') || ' → ' || COALESCE(ed.nome, '?')
                 || COALESCE(' (' || NULLIF(m.motivo, '') || ')', ''),
               ad.nome,
               m.automatico
          FROM oraculo_movimento_fluxo m
          LEFT JOIN oraculo_etapa_fluxo eo
            ON eo.id = m.etapa_origem_id AND eo.tenant_id = m.tenant_id
          LEFT JOIN oraculo_etapa_fluxo ed
            ON ed.id = m.etapa_destino_id AND ed.tenant_id = m.tenant_id
          LEFT JOIN oraculo_atendente ad
            ON ad.id = m.atendente_destino_id AND ad.tenant_id = m.tenant_id
         WHERE m.tenant_id = $1 AND m.atendimento_id = $2

        UNION ALL

        SELECT 'nota', n.criado_em, n.texto, at.nome, false
          FROM atu_nota n
          LEFT JOIN oraculo_atendente at
            ON at.id = n.criado_por_id AND at.tenant_id = n.tenant_id
         WHERE n.tenant_id = $1 AND n.atendimento_id = $2

        UNION ALL

        SELECT 'etiqueta', ea.aplicada_em, e.nome, ap.nome, false
          FROM atu_etiqueta_atendimento ea
          JOIN atu_etiqueta e
            ON e.id = ea.etiqueta_id AND e.tenant_id = ea.tenant_id
          LEFT JOIN oraculo_atendente ap
            ON ap.id = ea.aplicada_por_id AND ap.tenant_id = ea.tenant_id
         WHERE ea.tenant_id = $1 AND ea.atendimento_id = $2

        UNION ALL

        SELECT 'encerrado', a.data_fim, 'Atendimento ' || a.status, NULL::varchar, false
          FROM oraculo_atendimento a
         WHERE a.tenant_id = $1 AND a.id = $2 AND a.data_fim IS NOT NULL

        ORDER BY quando ASC
        "#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P5 — as outras conversas do mesmo contato, da mais recente para a antiga.
#[tracing::instrument(skip_all, fields(contato_id = contato_id))]
pub async fn listar_do_contato(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    contato_id: i32,
    limit: i64,
) -> Result<Vec<Atendimento>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, Atendimento>(
        r#"SELECT id, tenant_id, contato_id, departamento_id, fluxo_atendimento_id,
                  status, etapa_atual_id, data_inicio, data_fim, data_ultima_mensagem,
                  assunto, prioridade, atendente_humano_id, contexto_conversa,
                  historico_status, tags, avaliacao, feedback,
                  data_primeira_resposta, bot_pode_atender,
                  sentimento_nota, sentimento_label
             FROM oraculo_atendimento
            WHERE tenant_id = $1 AND contato_id = $2
            ORDER BY data_inicio DESC
            LIMIT $3"#,
    )
    .bind(ctx.tenant_id)
    .bind(contato_id)
    .bind(limit)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P6 — carimba a primeira resposta do atendimento, uma vez só.
///
/// A coluna `data_primeira_resposta` existe desde a 0006, é lida em cinco
/// consultas e nunca foi escrita: o SLA do painel media o vazio. O `WHERE ...
/// IS NULL` é o que garante "uma vez": a segunda resposta do mesmo atendimento
/// não move o carimbo, e a conta do tempo continua sendo do primeiro retorno.
///
/// Vale para atendente **e** bot, como na v1: para quem está esperando, quem
/// respondeu primeiro importa menos do que ter sido respondido.
#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn marcar_primeira_resposta(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<bool, DbError> {
    let r = sqlx::query(
        r#"UPDATE oraculo_atendimento
              SET data_primeira_resposta = NOW()
            WHERE tenant_id = $1 AND id = $2 AND data_primeira_resposta IS NULL"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .execute(&mut **tx)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// P6 — a mediana do tempo de primeira resposta, em segundos, nas últimas
/// 24 horas.
///
/// Mediana e não média: uma conversa esquecida no fim de semana levaria a
/// média para as alturas e esconderia o atendimento normal do dia.
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn mediana_primeira_resposta_24h(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
) -> Result<Option<i32>, DbError> {
    let row = sqlx::query_as::<_, (Option<f64>,)>(
        r#"SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (
                    ORDER BY EXTRACT(EPOCH FROM (data_primeira_resposta - data_inicio))
                  )
             FROM oraculo_atendimento
            WHERE tenant_id = $1
              AND data_primeira_resposta IS NOT NULL
              AND data_inicio > NOW() - INTERVAL '24 hours'"#,
    )
    .bind(ctx.tenant_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row.and_then(|(v,)| v).map(|v| v.round() as i32))
}

/// P13 — o contato de cada cartão do quadro.
///
/// O resumo do atendimento nunca levou nome nem telefone: o cartão mostrava
/// `Contato #id`. `nome` cai para o nome de perfil do WhatsApp quando ninguém
/// cadastrou um, e fica vazio quando nem isso existe — a tela então mostra o
/// telefone.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct ContatoDoQuadro {
    pub atendimento_id: i32,
    pub nome: String,
    pub telefone: String,
    pub foto_url: String,
}

#[tracing::instrument(skip_all, fields(quantidade = ids.len()))]
pub async fn contatos_do_quadro(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    ids: &[i32],
) -> Result<Vec<ContatoDoQuadro>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let rows = sqlx::query_as::<_, ContatoDoQuadro>(
        r#"SELECT a.id AS atendimento_id,
                  COALESCE(NULLIF(TRIM(c.nome_contato), ''),
                           NULLIF(TRIM(c.nome_perfil_whatsapp), ''), '') AS nome,
                  COALESCE(c.telefone, '') AS telefone,
                  COALESCE(c.foto_perfil_url_origem, '') AS foto_url
             FROM oraculo_atendimento a
             JOIN oraculo_contato c
               ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
            WHERE a.tenant_id = $1 AND a.id = ANY($2)"#,
    )
    .bind(ctx.tenant_id)
    .bind(ids)
    .fetch_all(&mut **tx)
    .await?;
    Ok(rows)
}

/// P13 — o contato de um atendimento, com a data da última consulta da foto.
#[derive(Debug, Clone, sqlx::FromRow, serde::Serialize, serde::Deserialize)]
pub struct ContatoComFoto {
    pub contato_id: i32,
    pub nome: String,
    pub telefone: String,
    pub foto_url: String,
    pub foto_verificada_em: Option<DateTime<Utc>>,
}

#[tracing::instrument(skip_all, fields(atendimento_id = atendimento_id))]
pub async fn contato_do_atendimento(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    atendimento_id: i32,
) -> Result<Option<ContatoComFoto>, DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    let row = sqlx::query_as::<_, ContatoComFoto>(
        r#"SELECT c.id AS contato_id,
                  COALESCE(NULLIF(TRIM(c.nome_contato), ''),
                           NULLIF(TRIM(c.nome_perfil_whatsapp), ''), '') AS nome,
                  COALESCE(c.telefone, '') AS telefone,
                  COALESCE(c.foto_perfil_url_origem, '') AS foto_url,
                  c.foto_verificada_em
             FROM oraculo_atendimento a
             JOIN oraculo_contato c
               ON c.id = a.contato_id AND c.tenant_id = a.tenant_id
            WHERE a.tenant_id = $1 AND a.id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(atendimento_id)
    .fetch_optional(&mut **tx)
    .await?;
    Ok(row)
}

/// P13 — grava o resultado da consulta da foto.
///
/// `None` NÃO apaga a foto guardada: o cliente do provedor devolve `None`
/// também quando a chamada falha, e apagar por causa de uma queda de rede
/// tiraria a foto de quem tem. Só a data da consulta anda.
#[tracing::instrument(skip_all, fields(contato_id = contato_id))]
pub async fn registrar_foto_do_contato(
    tx: &mut Transaction<'_, Postgres>,
    ctx: &RequestContext,
    contato_id: i32,
    foto_url: Option<&str>,
) -> Result<(), DbError> {
    ctx.exigir_qualquer(&["atendimentos:read", "tenant:admin"])?;
    sqlx::query(
        r#"UPDATE oraculo_contato
              SET foto_perfil_url_origem = COALESCE(NULLIF($3, ''), foto_perfil_url_origem),
                  foto_verificada_em = NOW()
            WHERE tenant_id = $1 AND id = $2"#,
    )
    .bind(ctx.tenant_id)
    .bind(contato_id)
    .bind(foto_url.unwrap_or_default())
    .execute(&mut **tx)
    .await?;
    Ok(())
}
