//! Adapter concreto do domínio WhatsApp: reusa os repositórios de
//! infrastructure_postgres e encapsula a transação (antes vivia no handler).

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::integracoes::whatsapp::{
    PostgresWhatsappInstanceRepository, WhatsappInstance, WhatsappInstanceRepository,
};
use infrastructure_postgres::integracoes::whitelist::{
    PostgresWhiteListRepository, WhiteListRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::WhatsappStore;

/// Implementação Postgres da port WhatsApp.
/// `admin_pool` (BYPASSRLS) é usado apenas nas consultas cross-tenant; quando
/// ausente, recai no pool de aplicação (RLS ativa) com aviso observável.
#[derive(Clone)]
pub struct PgWhatsappStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgWhatsappStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }
}

#[async_trait]
impl WhatsappStore for PgWhatsappStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_name = name))]
    async fn criar_instancia(
        &self,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let name = name.to_string();
        let api_key = api_key.to_string();
        let provider = provider.to_string();

        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo
                .criar(&mut tx, &ctx, &name, &api_key, &provider)
                .await?;
            Ok((inst, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn buscar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo.buscar_por_id(&mut tx, &ctx, id).await?;
            Ok((inst, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_ativas(&self, ctx: &RequestContext) -> Result<Vec<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let list = repo.listar_ativas(&mut tx, &ctx).await?;
            Ok((list, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn admin_listar_conectadas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        // Consulta cross-tenant exige BYPASSRLS: usa admin_pool quando disponível.
        if self.admin_pool.is_none() {
            tracing::warn!(
                "admin_listar_conectadas sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 consulta cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresWhatsappInstanceRepository;
        let mut tx = effective_pool.begin().await?;
        let list = repo.admin_listar_todas_conectadas(&mut tx, ctx).await?;
        tx.commit().await?;
        Ok(list)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn admin_deletar_instancia(&self, ctx: &RequestContext, id: i32) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.admin_deletar_instancia(&mut tx, &ctx, id).await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn atualizar_estado(
        &self,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let connection_state = connection_state.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_estado(&mut tx, &ctx, id, &connection_state)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn atualizar_provider_id(
        &self,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<String>,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let instance_id = instance_id.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_instancia_provider_id(
                &mut tx,
                &ctx,
                id,
                &instance_id,
                phone_number.as_deref(),
            )
            .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn verificar_token(
        &self,
        ctx: &RequestContext,
        id: i32,
        token: &str,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let token = token.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst_opt = repo.buscar_por_id(&mut tx, &ctx, id).await?;
            if let Some(ref inst) = inst_opt {
                // Comparação em tempo constante para evitar timing attack na validação do token.
                use subtle::ConstantTimeEq;
                let armazenado = inst.api_key.as_bytes();
                let recebido = token.as_bytes();
                // `ct_eq` só é constante para o mesmo comprimento; igualar tamanho antes mantém
                // a comparação resistente a ataque de tempo independentemente do token enviado.
                let iguais =
                    armazenado.len() == recebido.len() && armazenado.ct_eq(recebido).into();
                if iguais {
                    return Ok((Some(inst.clone()), tx));
                }
            }
            Ok((None, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, phone_number = phone_number))]
    async fn verificar_telefone_whitelist(
        &self,
        ctx: &RequestContext,
        phone_number: &str,
    ) -> Result<bool, DbError> {
        let repo = PostgresWhiteListRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let phone_number = phone_number.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let res = repo.esta_na_lista(&mut tx, &ctx, &phone_number).await?;
            Ok((res, tx))
        })
        .await
    }
}
