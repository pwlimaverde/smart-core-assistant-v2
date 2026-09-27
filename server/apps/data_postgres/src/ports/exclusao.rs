//! Port da exclusão definitiva (doc 39): excluir, desativar/reativar e listar
//! os excluídos, para qualquer entidade de [`TipoExcluivel`].

use async_trait::async_trait;
use infrastructure_postgres::exclusao::{ItemExcluido, ResultadoExclusao, TipoExcluivel};
use infrastructure_postgres::{DbError, RequestContext};

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait ExclusaoStore: Send + Sync {
    /// Exclui. Definitivo: não há restauração.
    async fn excluir(
        &self,
        ctx: &RequestContext,
        tipo: TipoExcluivel,
        id: i64,
    ) -> Result<ResultadoExclusao, DbError>;

    /// Desativa ou reativa. `None` = a entidade não tem estado inativo;
    /// `Some(false)` = inexistente ou excluída.
    async fn definir_ativo(
        &self,
        ctx: &RequestContext,
        tipo: TipoExcluivel,
        id: i64,
        ativo: bool,
    ) -> Result<Option<bool>, DbError>;

    /// Os excluídos do tenant, somente leitura.
    async fn listar_excluidos(
        &self,
        ctx: &RequestContext,
        tipo: Option<TipoExcluivel>,
        limite: i64,
    ) -> Result<Vec<ItemExcluido>, DbError>;
}
