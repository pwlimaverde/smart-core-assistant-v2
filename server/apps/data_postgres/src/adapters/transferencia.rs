//! Adapter do plano ia-engine-jev: cada operação numa transação do tenant
//! (RLS). Mudança que altera o que a IA lê (regras ativas, sinais, fluxo
//! padrão, motor) invalida o cache e republica a config no Redis — é de lá que
//! o `ia_engine_jev` e o worker leem.

use std::sync::Arc;

use async_trait::async_trait;
use redis::aio::ConnectionManager;
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::transferencia::{
    self as tr, ConfigTransferencia, DadosRegra, DecisaoIa, RegraTransferencia,
};
use infrastructure_postgres::{
    run_in_tenant_transaction, DbError, RequestContext, TenantConfigCache,
};

use crate::ports::transferencia::{Recusavel, TransferenciaStore};

#[derive(Clone)]
pub struct PgTransferenciaStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
    pub config_cache: Arc<TenantConfigCache>,
    /// Barramento: aviso às outras réplicas do data_postgres.
    pub bus_conn: ConnectionManager,
    /// Cache: onde vive `tenant:config:<uuid>`.
    pub cache_conn: ConnectionManager,
}

impl PgTransferenciaStore {
    pub fn new(
        pool: PgPool,
        admin_pool: Option<PgPool>,
        config_cache: Arc<TenantConfigCache>,
        bus_conn: ConnectionManager,
        cache_conn: ConnectionManager,
    ) -> Self {
        Self {
            pool,
            admin_pool,
            config_cache,
            bus_conn,
            cache_conn,
        }
    }

    /// Mesmo par do `UpdateTenantConfig`: descarta a cópia em RAM, avisa as
    /// réplicas e reescreve a config no Redis para a IA. Best-effort.
    async fn republicar(&self, tenant_id: Uuid) {
        self.config_cache.invalidate(&tenant_id);
        let mut conn = self.bus_conn.clone();
        let aviso = serde_json::json!({ "tenant_id": tenant_id.to_string() }).to_string();
        let _: Result<(), redis::RedisError> =
            redis::AsyncCommands::publish(&mut conn, "core:settings:invalidate", aviso).await;
        match self.config_cache.get_config(tenant_id).await {
            Ok(cfg) => {
                data_postgres::config_publisher::publicar_config_tenant(&self.cache_conn, &cfg)
                    .await
            }
            Err(e) => tracing::warn!(
                tenant_id = %tenant_id,
                "regras salvas mas não republicadas à IA: {e}"
            ),
        }
    }
}

/// Destino de regra precisa ser fluxo do próprio tenant.
async fn conferir_destino(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    tenant_id: Uuid,
    dados: &DadosRegra,
) -> Result<Option<String>, DbError> {
    if let Some(f) = dados.destino_fluxo_id {
        if !tr::fluxo_do_tenant(tx, tenant_id, f).await? {
            return Ok(Some("o fluxo de destino não existe neste negócio".into()));
        }
    }
    Ok(None)
}

#[async_trait]
impl TransferenciaStore for PgTransferenciaStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_regras(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<RegraTransferencia>, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let r = tr::listar(&mut tx, tenant).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn obter_regra(
        &self,
        ctx: &RequestContext,
        id: i64,
    ) -> Result<Option<RegraTransferencia>, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let r = tr::obter(&mut tx, tenant, id).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn criar_regra(
        &self,
        ctx: &RequestContext,
        dados: DadosRegra,
        ativa: bool,
    ) -> Result<Recusavel<RegraTransferencia>, DbError> {
        if let Err(motivo) = dados.validar() {
            return Ok(Err(motivo));
        }
        let tenant = ctx.tenant_id;
        let resultado = run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            if tr::existe_nome(&mut tx, tenant, &dados.nome, None).await? {
                return Ok((
                    Err(format!("já existe uma regra chamada \"{}\"", dados.nome)),
                    tx,
                ));
            }
            if let Some(motivo) = conferir_destino(&mut tx, tenant, &dados).await? {
                return Ok((Err(motivo), tx));
            }
            let regra = tr::criar(&mut tx, tenant, &dados, ativa, false).await?;
            Ok((Ok(regra), tx))
        })
        .await?;
        if matches!(&resultado, Ok(r) if r.ativa) {
            self.republicar(tenant).await;
        }
        Ok(resultado)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_regra(
        &self,
        ctx: &RequestContext,
        id: i64,
        payload: serde_json::Value,
    ) -> Result<Recusavel<Option<(RegraTransferencia, RegraTransferencia)>>, DbError> {
        let tenant = ctx.tenant_id;
        let resultado = run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let Some(antes) = tr::obter(&mut tx, tenant, id).await? else {
                return Ok((Ok(None), tx));
            };
            let dados = DadosRegra::mesclar(&antes, &payload);
            if let Err(motivo) = dados.validar() {
                return Ok((Err(motivo), tx));
            }
            if tr::existe_nome(&mut tx, tenant, &dados.nome, Some(id)).await? {
                return Ok((
                    Err(format!("já existe uma regra chamada \"{}\"", dados.nome)),
                    tx,
                ));
            }
            if let Some(motivo) = conferir_destino(&mut tx, tenant, &dados).await? {
                return Ok((Err(motivo), tx));
            }
            let depois = tr::atualizar(&mut tx, tenant, id, &dados).await?;
            Ok((Ok(depois.map(|d| (antes, d))), tx))
        })
        .await?;
        if matches!(&resultado, Ok(Some((a, d))) if a.ativa || d.ativa) {
            self.republicar(tenant).await;
        }
        Ok(resultado)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id, ativa = ativa))]
    async fn definir_regra_ativa(
        &self,
        ctx: &RequestContext,
        id: i64,
        ativa: bool,
    ) -> Result<Option<RegraTransferencia>, DbError> {
        let tenant = ctx.tenant_id;
        let r = run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let r = tr::definir_ativa(&mut tx, tenant, id, ativa).await?;
            Ok((r, tx))
        })
        .await?;
        if r.is_some() {
            self.republicar(tenant).await;
        }
        Ok(r)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn obter_config(&self, ctx: &RequestContext) -> Result<ConfigTransferencia, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let c = tr::obter_config(&mut tx, tenant).await?;
            Ok((c, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn definir_config(
        &self,
        ctx: &RequestContext,
        sinais: Option<serde_json::Value>,
        fluxo_padrao: Option<Option<i32>>,
    ) -> Result<Recusavel<(ConfigTransferencia, ConfigTransferencia)>, DbError> {
        let tenant = ctx.tenant_id;
        let resultado = run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let antes = tr::obter_config(&mut tx, tenant).await?;
            let novos = match &sinais {
                Some(pedido) => match tr::normalizar_sinais(&antes.sinais, pedido) {
                    Ok(v) => Some(v),
                    Err(motivo) => return Ok((Err(motivo), tx)),
                },
                None => None,
            };
            if let Some(Some(f)) = fluxo_padrao {
                if !tr::fluxo_do_tenant(&mut tx, tenant, f).await? {
                    return Ok((Err("o fluxo padrão não existe neste negócio".into()), tx));
                }
            }
            tr::definir_config(&mut tx, tenant, novos.as_ref(), fluxo_padrao).await?;
            let depois = tr::obter_config(&mut tx, tenant).await?;
            Ok((Ok((antes, depois)), tx))
        })
        .await?;
        if resultado.is_ok() {
            self.republicar(tenant).await;
        }
        Ok(resultado)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_transferencias(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<serde_json::Value>, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let r = tr::listar_transferencias(&mut tx, tenant, limite).await?;
            Ok((r, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn registrar_decisao(
        &self,
        ctx: &RequestContext,
        decisao: DecisaoIa,
    ) -> Result<i64, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let id = tr::registrar_decisao(&mut tx, tenant, &decisao).await?;
            Ok((id, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn rodadas_coleta(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<i32, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let n = tr::rodadas_coleta(&mut tx, tenant, atendimento_id).await?;
            Ok((n, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, atendimento_id = atendimento_id))]
    async fn registrar_rodada_coleta(
        &self,
        ctx: &RequestContext,
        atendimento_id: i32,
    ) -> Result<Option<i32>, DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let n = tr::registrar_rodada_coleta(&mut tx, tenant, atendimento_id).await?;
            Ok((n, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, mensagem_id = mensagem_id))]
    async fn marcar_motor_da_mensagem(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        motor: String,
        modelo: String,
    ) -> Result<(), DbError> {
        let tenant = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            tr::marcar_motor_da_mensagem(&mut tx, tenant, mensagem_id, &motor, &modelo).await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn gerar_sugestoes(&self, ctx: &RequestContext) -> Result<usize, DbError> {
        let tenant = ctx.tenant_id;
        // O prompt de regras de transferência resolvido (tenant > global).
        let prompt = self
            .config_cache
            .get_config(tenant)
            .await
            .ok()
            .and_then(|c| c.prompts.get("PROMPT_REGRAS_TRANSFERENCIA").cloned())
            .unwrap_or_default();
        run_in_tenant_transaction(&self.pool, tenant, move |mut tx| async move {
            let intents: Vec<(String, String)> = sqlx::query_as(
                "SELECT tag, COALESCE(comportamento, '') FROM treinamento_querycompose \
                 WHERE tenant_id = $1 ORDER BY tag",
            )
            .bind(tenant)
            .fetch_all(&mut *tx)
            .await?;
            let mut criadas = 0usize;
            for dados in tr::sugestoes_do_texto(&intents, &prompt) {
                if tr::existe_nome(&mut tx, tenant, &dados.nome, None).await? {
                    continue;
                }
                tr::criar(&mut tx, tenant, &dados, false, true).await?;
                criadas += 1;
            }
            Ok((criadas, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %tenant_id))]
    async fn definir_motor(
        &self,
        tenant_id: Uuid,
        motor: Option<String>,
    ) -> Result<Option<String>, DbError> {
        let anterior = run_in_tenant_transaction(&self.pool, tenant_id, move |mut tx| async move {
            let a = tr::definir_motor(&mut tx, tenant_id, motor.as_deref()).await?;
            Ok((a, tx))
        })
        .await?;
        self.republicar(tenant_id).await;
        Ok(anterior)
    }

    #[tracing::instrument(skip_all, fields(dias = dias))]
    async fn purgar_decisoes(&self, dias: i64) -> Result<u64, DbError> {
        let Some(pool) = self.admin_pool.as_ref() else {
            tracing::warn!("retenção das decisões da IA sem DATABASE_ADMIN_URL: nada apagado");
            return Ok(0);
        };
        tr::purgar_decisoes_antigas(pool, dias).await
    }
}
