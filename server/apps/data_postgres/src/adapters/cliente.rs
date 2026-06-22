//! Adapter concreto do domínio Cliente: reusa PostgresContatoRepository de
//! infrastructure_postgres e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::clientes::contatos::{
    Contato, ContatoRepository, PostgresContatoRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::ClienteStore;

/// Implementação Postgres da port Cliente.
#[derive(Clone)]
pub struct PgClienteStore {
    pub pool: PgPool,
}

impl PgClienteStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl ClienteStore for PgClienteStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn salvar_contato(
        &self,
        ctx: &RequestContext,
        telefone: &str,
        nome: Option<String>,
    ) -> Result<Contato, DbError> {
        let repo = PostgresContatoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let telefone = telefone.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let contato = repo
                .salvar(&mut tx, &ctx, &telefone, nome.as_deref())
                .await?;
            Ok((contato, tx))
        })
        .await
    }
}
