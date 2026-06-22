//! Port (abstração) do domínio Cliente do data_postgres.
//! O handler depende SOMENTE desta trait; a transação vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::clientes::contatos::Contato;
use infrastructure_postgres::{DbError, RequestContext};

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
}
