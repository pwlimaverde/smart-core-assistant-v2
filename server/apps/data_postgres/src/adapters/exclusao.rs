//! Adapter da exclusão definitiva: cada operação numa transação do tenant (RLS).

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::exclusao::{
    self, DescricaoExclusao, ItemExcluido, ResultadoExclusao, TipoExcluivel,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::ExclusaoStore;

#[derive(Clone)]
pub struct PgExclusaoStore {
    pub pool: PgPool,
}

impl PgExclusaoStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl ExclusaoStore for PgExclusaoStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, tipo = tipo.nome(), id = id))]
    async fn descrever(
        &self,
        ctx: &RequestContext,
        tipo: TipoExcluivel,
        id: i64,
    ) -> Result<Option<DescricaoExclusao>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let r = exclusao::descrever(&mut tx, &ctx, tipo, id).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, tipo = tipo.nome(), id = id))]
    async fn excluir(
        &self,
        ctx: &RequestContext,
        tipo: TipoExcluivel,
        id: i64,
        confirmar: String,
    ) -> Result<ResultadoExclusao, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let r = exclusao::excluir(&mut tx, &ctx, tipo, id, Some(&confirmar)).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, tipo = tipo.nome(), id = id))]
    async fn definir_ativo(
        &self,
        ctx: &RequestContext,
        tipo: TipoExcluivel,
        id: i64,
        ativo: bool,
    ) -> Result<Option<bool>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let r = exclusao::definir_ativo(&mut tx, &ctx, tipo, id, ativo).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_excluidos(
        &self,
        ctx: &RequestContext,
        tipo: Option<TipoExcluivel>,
        limite: i64,
    ) -> Result<Vec<ItemExcluido>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, move |mut tx| async move {
            let r = exclusao::listar_excluidos(&mut tx, &ctx, tipo, limite).await?;
            Ok((r, tx))
        })
        .await
    }
}
