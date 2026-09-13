//! Adapter Postgres dos consentimentos OAuth 2.1 dos clientes MCP (N13.2).
//!
//! `mcp_oauth_grant` é tabela COM RLS, então toda operação corre dentro de
//! [`run_in_tenant_transaction`] — a política `app.current_tenant` é a segunda
//! barreira, abaixo do filtro por `user_id` que o repositório aplica.

use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::mcp::grants;
use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::{run_in_tenant_transaction, DbError, McpGrant, McpGrantComSegredo};

use crate::ports::McpGrantStore;

#[derive(Clone)]
pub struct PgMcpGrantStore {
    pub pool: PgPool,
}

impl PgMcpGrantStore {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl McpGrantStore for PgMcpGrantStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id))]
    async fn registrar(
        &self,
        ctx: &RequestContext,
        client_id: &str,
        client_name: &str,
        redirect_uri: &str,
        escopos: &[String],
        created_ip: Option<String>,
    ) -> Result<McpGrant, DbError> {
        let ctx = ctx.clone();
        let client_id = client_id.to_string();
        let client_name = client_name.to_string();
        let redirect_uri = redirect_uri.to_string();
        let escopos = escopos.to_vec();

        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let grant = grants::registrar_consentimento(
                &mut tx,
                &ctx,
                &client_id,
                &client_name,
                &redirect_uri,
                &escopos,
                created_ip.as_deref(),
            )
            .await?;
            Ok((grant, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id))]
    async fn listar_atividade(
        &self,
        ctx: &RequestContext,
        filtro: infrastructure_postgres::auditoria::audit_log::FiltroAtividade,
    ) -> Result<Vec<serde_json::Value>, DbError> {
        let tenant_id = ctx.tenant_id;
        // `audit_log` e `mcp_oauth_grant` têm RLS: a transação do tenant é a
        // segunda barreira, abaixo do `tenant_id` que a consulta já filtra.
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let itens = infrastructure_postgres::auditoria::audit_log::buscar_atividade_do_tenant(
                &mut tx, tenant_id, &filtro,
            )
            .await?;
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, user_id = ctx.user_id))]
    async fn listar(&self, ctx: &RequestContext) -> Result<Vec<McpGrant>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let lista = grants::listar_do_usuario(&mut tx, &ctx).await?;
            Ok((lista, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, grant_id = %grant_id))]
    async fn revogar(&self, ctx: &RequestContext, grant_id: Uuid) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let revogado = grants::revogar(&mut tx, &ctx, grant_id).await?;
            Ok((revogado, tx))
        })
        .await
    }

    // `hash` fica fora do span: é derivado de segredo, e hash não muda isso.
    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, grant_id = %grant_id))]
    async fn definir_refresh_hash(
        &self,
        tenant_id: Uuid,
        grant_id: Uuid,
        hash: &str,
    ) -> Result<(), DbError> {
        let hash = hash.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            grants::definir_refresh_hash(&mut tx, tenant_id, grant_id, &hash).await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, grant_id = %grant_id))]
    async fn buscar_com_segredo(
        &self,
        tenant_id: Uuid,
        grant_id: Uuid,
    ) -> Result<Option<McpGrantComSegredo>, DbError> {
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let achado = grants::buscar_ativo_com_segredo(&mut tx, tenant_id, grant_id).await?;
            Ok((achado, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id, grant_id = %grant_id))]
    async fn revogar_por_reuso(&self, tenant_id: Uuid, grant_id: Uuid) -> Result<(), DbError> {
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            grants::revogar_por_reuso(&mut tx, tenant_id, grant_id).await?;
            Ok(((), tx))
        })
        .await
    }
}
