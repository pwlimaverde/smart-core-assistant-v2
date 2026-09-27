//! Port (abstração) do domínio Cliente do data_postgres.
//! O handler depende SOMENTE desta trait; a transação vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::clientes::contatos::{Contato, EdicaoContato};
use infrastructure_postgres::{DbError, RequestContext};

/// Como terminou uma edição de contato.
///
/// Três desfechos e não um `bool` porque "não encontrei" e "não deixo trocar o
/// telefone" pedem respostas diferentes na tela, e `DbError` não tem onde
/// carregar uma regra de negócio — ele fala de banco.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DesfechoEdicaoContato {
    Atualizado,
    NaoEncontrado,
    /// O contato já conversou: o número está amarrado a esse histórico.
    TelefoneTravado {
        atendimentos: i64,
    },
}

/// Operações de persistência do domínio Cliente expostas aos handlers RPC.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait ClienteStore: Send + Sync {
    /// Cria/atualiza (upsert) um contato pelo telefone. `nome` é owned para
    /// satisfazer o `automock` (lifetime aninhado em `Option<&str>`).
    async fn salvar_contato(
        &self,
        ctx: &RequestContext,
        telefone: &str,
        nome: Option<String>,
    ) -> Result<Contato, DbError>;

    /// Lista os contatos do tenant, mais recentes primeiro. `busca` é owned
    /// pelo mesmo motivo de `nome` acima.
    async fn listar_contatos(
        &self,
        ctx: &RequestContext,
        busca: Option<String>,
        limite: i64,
    ) -> Result<Vec<Contato>, DbError>;

    /// Cadastra um contato antes de qualquer mensagem (C4).
    ///
    /// Telefone repetido volta como `DbError::UniqueViolation`: cadastrar por
    /// engano o número de outra pessoa e receber a ficha dela em silêncio é
    /// pior que a recusa.
    async fn criar_contato(
        &self,
        ctx: &RequestContext,
        telefone: String,
        nome: Option<String>,
        email: Option<String>,
    ) -> Result<Contato, DbError>;

    /// Edita o cadastro.
    ///
    /// A troca de telefone é conferida aqui dentro, na mesma transação em que
    /// se conta o histórico: fora dela, duas requisições simultâneas veriam
    /// "nenhum atendimento" e uma delas mudaria o número de um contato que já
    /// tinha conversa.
    async fn atualizar_contato(
        &self,
        ctx: &RequestContext,
        id: i32,
        edicao: EdicaoContato,
    ) -> Result<DesfechoEdicaoContato, DbError>;

    /// B10 (N11 E5) — clientes do tenant, ativos primeiro.
    async fn listar_clientes(
        &self,
        ctx: &RequestContext,
        busca: String,
        incluir_inativos: bool,
        limite: i64,
    ) -> Result<Vec<infrastructure_postgres::clientes::clientes::ClienteResumo>, DbError>;

    /// B10 — cadastra um cliente.
    async fn criar_cliente(
        &self,
        ctx: &RequestContext,
        dados: infrastructure_postgres::clientes::clientes::DadosCliente,
    ) -> Result<infrastructure_postgres::clientes::clientes::ClienteResumo, DbError>;

    /// B10 — edita; devolve os **campos** alterados (`None` = não encontrado).
    async fn atualizar_cliente(
        &self,
        ctx: &RequestContext,
        id: i32,
        dados: infrastructure_postgres::clientes::clientes::DadosCliente,
    ) -> Result<Option<Vec<String>>, DbError>;

    /// B10 — tira (ou devolve) o cliente da lista.
    async fn definir_cliente_ativo(
        &self,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError>;

    /// B10 — os contatos ligados a um cliente.
    async fn contatos_do_cliente(
        &self,
        ctx: &RequestContext,
        cliente_id: i32,
    ) -> Result<Vec<infrastructure_postgres::clientes::clientes::ContatoVinculado>, DbError>;

    /// B10 — liga (ou desliga) um contato de um cliente. `false` = um dos dois
    /// não é deste tenant.
    async fn vincular_contato_cliente(
        &self,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
        vincular: bool,
    ) -> Result<bool, DbError>;

    /// Tira (ou devolve) o contato da lista sem apagar o histórico.
    async fn definir_contato_ativo(
        &self,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError>;
}
