//! Port (abstração) do domínio Atendimento do data_postgres.
//! O handler depende SOMENTE desta trait; a transação (incl. o padrão outbox da
//! persistência de mensagem) vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::atendimentos::atendimentos::Atendimento;
use infrastructure_postgres::atendimentos::mensagens::Mensagem;
use infrastructure_postgres::{DbError, RequestContext};

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
    async fn persistir_mensagem(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
        tipo: &str,
        conteudo: &str,
        remetente: &str,
        traceparent: &str,
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
}
