//! Port (abstração) do domínio Atendimento do data_postgres.
//! O handler depende SOMENTE desta trait; a transação (incl. o padrão outbox da
//! persistência de mensagem) vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::atendimentos::atendimentos::Atendimento;
use infrastructure_postgres::atendimentos::mensagens::{DestinoEnvioOutbound, Mensagem};
use infrastructure_postgres::operacional::fluxos::FluxoDisponivel;
use infrastructure_postgres::{DbError, RequestContext};
use uuid::Uuid;

/// Campo já coletado de um atendimento (N6.3, input-only para o Responder).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CampoColetadoDto {
    pub slug: String,
    pub nome: String,
    pub valor: String,
}

/// Campo obrigatório ainda não coletado de um atendimento (N6.3, input-only).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CampoPendenteDto {
    pub slug: String,
    pub nome: String,
    pub descricao: String,
    pub hint: String,
}

/// Campos personalizados resolvidos de um atendimento: já coletados (com valor)
/// e obrigatórios ainda pendentes (N6.3, input-only para o Responder).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct CamposAtendimentoDto {
    pub coletados: Vec<CampoColetadoDto>,
    pub pendentes: Vec<CampoPendenteDto>,
}

/// Resultado de uma transferência de atendimento para outro fluxo decidida pela IA (N6.3).
#[derive(Debug, Clone, Default)]
pub struct TransferenciaFluxoOutcome {
    /// `true` quando a transferência efetivamente ocorreu.
    pub transferido: bool,
    pub fluxo_id: Option<i32>,
    pub fluxo_nome: Option<String>,
    pub etapa_id: Option<i32>,
    pub etapa_nome: Option<String>,
    /// Motivo quando `transferido == false` (ex.: "fluxo_inexistente", "sem_etapa_inicial").
    pub reason: Option<String>,
}

/// Resultado da aplicação da política de ticket/Kanban sobre um atendimento (WS-2.4).
#[derive(Debug, Clone, Default)]
pub struct TicketKanbanOutcome {
    /// `true` quando o atendimento foi efetivamente posicionado/movido no Kanban.
    pub moved: bool,
    /// Status do ticket após a política (ex.: "fila").
    pub status: String,
    /// Etapa de destino, quando houve movimento.
    pub etapa_id: Option<i32>,
    /// Nome da etapa de destino (para auditoria/realtime).
    pub etapa_nome: Option<String>,
    /// Fluxo resolvido para o atendimento.
    pub fluxo_id: Option<i32>,
    /// Motivo quando `moved == false` (ex.: "ja_posicionado", "sem_fluxo", "sem_etapa_inicial").
    pub reason: Option<String>,
}

/// Metadados de origem de uma mensagem que chega para ser persistida — o que o
/// provedor de WhatsApp informou sobre ela. Todos opcionais: o caminho do bot e o
/// do painel não têm nenhum deles.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct OrigemMensagem {
    /// stanzaId da própria mensagem. Presente, é a chave natural de idempotência:
    /// reentrega do mesmo evento pelo bus devolve a mensagem já persistida em vez
    /// de duplicá-la no chat.
    pub message_id_whatsapp: Option<String>,
    /// stanzaId da mensagem citada (reply do WhatsApp), a resolver para o id interno.
    pub citando_message_id_whatsapp: Option<String>,
    /// `true` quando a mensagem já trafegou pelo WhatsApp antes de chegar aqui
    /// (mensagem `fromMe`, digitada pelo atendente no próprio celular): nasce
    /// `status_envio='sent'` para o worker não reenviá-la ao contato.
    pub ja_entregue: bool,
}

/// Operações de persistência do domínio Atendimento expostas aos handlers RPC.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait AtendimentoStore: Send + Sync {
    /// Lista as mensagens (thread) de um atendimento (tenant-scoped via RLS).
    async fn listar_mensagens(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Mensagem>, DbError>;

    /// Lista atendimentos por status (snapshot), opcionalmente filtrando departamento.
    async fn listar_atendimentos(
        &self,
        ctx: &RequestContext,
        status: &str,
        departamento_id: Option<i32>,
        limit: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    /// Persiste uma mensagem e o evento de domínio na MESMA transação ACID
    /// (padrão Outbox): grava em `atendimentos_mensagem` e em `outbox`.
    ///
    /// `action_id` (N7.2, opcional): quando presente (envio outbound do
    /// atendente via sync offline), dedupe atômico na MESMA transação —
    /// reenviar a mesma ação devolve a mensagem já persistida, sem duplicar.
    /// `None` (caminho de ingestão inbound/bot) preserva o comportamento atual.
    ///
    /// `origem`: metadados do provedor (stanzaId, citação, já entregue). Com
    /// `message_id_whatsapp` presente, a idempotência vale também para a
    /// reentrega do evento pelo bus, sem depender de `action_id`.
    #[allow(clippy::too_many_arguments)]
    async fn persistir_mensagem(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        traceparent: &str,
        action_id: Option<Uuid>,
        origem: OrigemMensagem,
    ) -> Result<Mensagem, DbError>;

    /// Busca ou cria um contato pelo telefone, e busca ou cria um atendimento ativo para esse contato.
    async fn resolver_atendimento_para_contato(
        &self,
        ctx: &RequestContext,
        telefone: &str,
        push_name: Option<String>,
    ) -> Result<(i32, Atendimento, bool), DbError>;

    /// Atualiza o status de leitura/entrega de uma mensagem pelo ID do WhatsApp.
    async fn atualizar_status_mensagem(
        &self,
        ctx: &RequestContext,
        message_id_whatsapp: &str,
        status: &str,
    ) -> Result<(), DbError>;

    /// Aplica a política de ticket/Kanban: para um atendimento ainda não posicionado,
    /// resolve o fluxo padrão, coloca-o na etapa inicial ('fila'), registra o
    /// `MovimentoFluxo` automático e devolve o resultado para auditoria/realtime (WS-2.4).
    async fn aplicar_politica_ticket_kanban(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<TicketKanbanOutcome, DbError>;

    /// Move manualmente um atendimento para outra etapa do Kanban (drag-and-drop na
    /// tela operacional — WS-6.2). Registra o `MovimentoFluxo` (não automático) na
    /// MESMA transação da atualização de etapa, para auditoria/histórico. Além do
    /// escopo (`ctx.exigir_qualquer`, checado em `atualizar_etapa`/`criar`), o
    /// implementador DEVE aplicar o RBAC fino por fluxo (`flow_permissions`, WS-5a)
    /// via `ctx.exigir_fluxo(fluxo_id)` sobre o fluxo atual do atendimento — o escopo
    /// sozinho não barra um atendente sem permissão para aquele fluxo específico.
    ///
    /// `motivo` vazio (`""`) equivale a ausente (convenção do trait, evita o lifetime
    /// explícito que `Option<&str>` exigiria sob `mockall::automock`).
    ///
    /// `action_id` (N7.2, opcional): dedupe atômico na MESMA transação — reenviar
    /// a mesma ação (após retry/reconexão do sync offline) não reaplica o
    /// movimento. `None` (clientes antigos) preserva o comportamento atual.
    async fn mover_etapa_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        etapa_destino_id: i32,
        motivo: &str,
        action_id: Option<Uuid>,
    ) -> Result<(), DbError>;

    /// Define o status do atendimento e **move o cartão junto**.
    ///
    /// O par simétrico de `mover_etapa_atendimento`: lá a coluna manda no
    /// status, aqui o status manda na coluna. Sem isto, encerrar uma conversa
    /// pelo chat deixaria o cartão parado na coluna de trabalho, e o quadro
    /// passaria a mentir sobre o que está aberto.
    ///
    /// O movimento resultante é registrado como **automático**, para o
    /// histórico distinguir o que uma pessoa arrastou do que o sistema mexeu.
    async fn definir_status_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        novo_status: String,
        motivo: String,
    ) -> Result<serde_json::Value, DbError>;

    /// Varredura CROSS-TENANT do scheduler do worker (F4.3b): atendimentos
    /// resolvidos aguardando feedback além do TTL. Exige `admin_pool` (BYPASSRLS).
    async fn listar_feedback_vencido(
        &self,
        ctx: &RequestContext,
        limite: i64,
        ttl_horas: i64,
    ) -> Result<Vec<Atendimento>, DbError>;

    /// Marca o atendimento (tenant-scoped) como tendo o feedback expirado.
    async fn marcar_feedback_expirado(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<(), DbError>;

    /// Varredura CROSS-TENANT do scheduler do worker (F4.3b): mensagens com mídia
    /// vencida (idade além do limite). Exige `admin_pool` (BYPASSRLS).
    async fn listar_midias_expiradas(
        &self,
        ctx: &RequestContext,
        limite: i64,
        idade_max_dias: i64,
    ) -> Result<Vec<Mensagem>, DbError>;

    /// Marca a mídia da mensagem (tenant-scoped) como purga solicitada.
    async fn marcar_midia_purgada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError>;

    /// Resolve instância/telefone de destino para o envio outbound de uma
    /// mensagem do atendente (elo outbox->outbound, N1.3).
    async fn resolver_destino_envio_outbound(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<Option<DestinoEnvioOutbound>, DbError>;

    /// Reprocessamento manual de um dead-letter de outbound (N7.2): RPC
    /// administrativo simples — sem harness automatizado, sob demanda do
    /// operador. Retorna `"reprocessada"` | `"ainda_sem_destino"` | `"nao_encontrada"`.
    async fn reprocessar_dead_letter(
        &self,
        ctx: &RequestContext,
        dead_letter_id: i32,
        traceparent: &str,
    ) -> Result<String, DbError>;

    /// Marca a mensagem outbound como enviada com sucesso, gravando o stanzaId.
    async fn marcar_mensagem_enviada(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        message_id_whatsapp: &str,
    ) -> Result<(), DbError>;

    /// Marca falha definitiva no envio outbound (após esgotar retries).
    async fn marcar_mensagem_falha_envio(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
    ) -> Result<(), DbError>;

    /// Anexa análise/resumo de mídia + ponteiro do arquivo a uma mensagem já
    /// persistida (pipeline de mídia do worker, N6.1). Campos vazios (`""`) são
    /// tratados como ausentes e não sobrescrevem o valor atual.
    async fn anexar_analise_midia(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        arquivo_midia: &str,
        analise_midia: &str,
        resumo_midia: &str,
    ) -> Result<(), DbError>;

    /// Lista os fluxos ativos do tenant (setor/nome/descrição) para o Responder (N6.3).
    async fn listar_fluxos_do_tenant(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<FluxoDisponivel>, DbError>;

    /// Transfere o atendimento para `fluxo_id`: resolve a etapa inicial do fluxo
    /// destino, sobrescreve fluxo/departamento/etapa e registra o `MovimentoFluxo`
    /// na mesma transação. Transferência automática decidida pela IA (N6.3).
    async fn transferir_atendimento_para_fluxo(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        fluxo_id: i32,
    ) -> Result<TransferenciaFluxoOutcome, DbError>;

    /// Resolve os campos personalizados (globais + do fluxo atual) do atendimento:
    /// já coletados (com valor) e obrigatórios pendentes (sem valor). Input-only
    /// para o Responder (N6.3) — o contrato do Responder não devolve campos
    /// extraídos, então não há write-back aqui.
    async fn resolver_campos_atendimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<CamposAtendimentoDto, DbError>;

    /// Atualiza a última leitura de sentimento do atendimento, calculada pela IA
    /// a partir de mensagens inbound de texto/transcrição de áudio (N6.5, best-effort).
    async fn atualizar_sentimento(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        nota: i32,
        label: &str,
    ) -> Result<(), DbError>;
}
