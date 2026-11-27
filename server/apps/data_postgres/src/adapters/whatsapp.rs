//! Adapter concreto do domínio WhatsApp: reusa os repositórios de
//! infrastructure_postgres e encapsula a transação (antes vivia no handler).

use std::sync::Arc;

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::crypto::CipherManager;
use infrastructure_postgres::integracoes::conexoes;
use infrastructure_postgres::integracoes::conexoes::DetalheDaConexao;
use infrastructure_postgres::integracoes::whatsapp::{
    PostgresWhatsappContactRepository, PostgresWhatsappInstanceRepository,
    WhatsappContactRepository, WhatsappInstance, WhatsappInstanceRepository,
};
use infrastructure_postgres::integracoes::whitelist::{
    PostgresWhiteListRepository, WhiteList, WhiteListRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::WhatsappStore;

/// Implementação Postgres da port WhatsApp.
/// `admin_pool` (BYPASSRLS) é usado apenas nas consultas cross-tenant; quando
/// ausente, recai no pool de aplicação (RLS ativa) com aviso observável.
/// `cipher` decifra/encripta `api_key` (AES-256-GCM, jsonb em repouso — N8).
#[derive(Clone)]
pub struct PgWhatsappStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
    pub cipher: Arc<CipherManager>,
}

impl PgWhatsappStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>, cipher: Arc<CipherManager>) -> Self {
        Self {
            pool,
            admin_pool,
            cipher,
        }
    }
}

#[async_trait]
impl WhatsappStore for PgWhatsappStore {
    // Consultas do contrato de canal em SQL de tempo de execução (sem macro):
    // as colunas da 0054 não precisam entrar no cache offline do sqlx.
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn gravar_config_do_canal(
        &self,
        ctx: &RequestContext,
        id: i32,
        channel_kind: &str,
        provider_config: serde_json::Value,
    ) -> Result<bool, DbError> {
        let tenant_id = ctx.tenant_id;
        let channel_kind = channel_kind.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let res = sqlx::query(
                "UPDATE whatsapp_instance SET channel_kind = $1, provider_config = $2 \
                 WHERE id = $3 AND tenant_id = $4",
            )
            .bind(&channel_kind)
            .bind(&provider_config)
            .bind(id)
            .bind(tenant_id)
            .execute(&mut *tx)
            .await?;
            Ok((res.rows_affected() > 0, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(provider = provider))]
    async fn admin_resolver_por_id_externo(
        &self,
        _ctx: &RequestContext,
        provider: &str,
        id_externo: &str,
    ) -> Result<Option<(i32, uuid::Uuid)>, DbError> {
        // Cross-tenant: exige BYPASSRLS (admin_pool). Sem ele a RLS esconde
        // tudo e o webhook da Meta é descartado — o aviso denuncia a causa.
        if self.admin_pool.is_none() {
            tracing::warn!(
                "admin_resolver_por_id_externo sem DATABASE_ADMIN_URL: a RLS bloqueará \
                 a consulta e o webhook não achará a conexão"
            );
        }
        let pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let linha: Option<(i32, uuid::Uuid)> = sqlx::query_as(
            "SELECT id, tenant_id FROM whatsapp_instance \
             WHERE provider = $1 AND instance_id = $2 AND active",
        )
        .bind(provider)
        .bind(id_externo)
        .fetch_optional(pool)
        .await?;
        Ok(linha)
    }

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
        let cipher = self.cipher.clone();
        let tenant_id = ctx.tenant_id;
        let name = name.to_string();
        let api_key = api_key.to_string();
        let provider = provider.to_string();

        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo
                .criar(&mut tx, &ctx, &cipher, &name, &api_key, &provider)
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
        let cipher = self.cipher.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo.buscar_por_id(&mut tx, &ctx, &cipher, id).await?;
            Ok((inst, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id, habilitado = habilitado))]
    async fn definir_resposta_bot(
        &self,
        ctx: &RequestContext,
        id: i32,
        habilitado: bool,
    ) -> Result<bool, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let afetou = repo
                .definir_resposta_bot(&mut tx, &ctx, id, habilitado)
                .await?;
            Ok((afetou, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_ativas(&self, ctx: &RequestContext) -> Result<Vec<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let cipher = self.cipher.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let list = repo.listar_ativas(&mut tx, &ctx, &cipher).await?;
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
        let list = repo
            .admin_listar_todas_conectadas(&mut tx, ctx, &self.cipher)
            .await?;
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
        let cipher = self.cipher.clone();
        let tenant_id = ctx.tenant_id;
        let token = token.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst_opt = repo.buscar_por_id(&mut tx, &ctx, &cipher, id).await?;
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

    // ------------------------------------------------------------ P7
    //
    // Números ignorados e o vínculo conexão → departamento. Cada método abre a
    // própria transação pelo `run_in_tenant_transaction`, como o resto do
    // adapter: a RLS depende do `SET LOCAL app.current_tenant` que ele aplica.

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_numeros_ignorados(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhiteList>, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let repo = PostgresWhiteListRepository;
            let itens = repo.listar_todas(&mut tx, &ctx).await?;
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn criar_numero_ignorado(
        &self,
        ctx: &RequestContext,
        nome: &str,
        telefone: &str,
    ) -> Result<WhiteList, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let nome = nome.to_string();
        let telefone = telefone.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let repo = PostgresWhiteListRepository;
            let item = repo.criar(&mut tx, &ctx, &nome, &telefone, None).await?;
            Ok((item, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_numero_ignorado(
        &self,
        ctx: &RequestContext,
        id: i32,
        nome: &str,
        telefone: &str,
        ativo: bool,
    ) -> Result<Option<WhiteList>, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let nome = nome.to_string();
        let telefone = telefone.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let repo = PostgresWhiteListRepository;
            let item = repo
                .atualizar(&mut tx, &ctx, id, &nome, &telefone, ativo)
                .await?;
            Ok((item, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn remover_numero_ignorado(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let repo = PostgresWhiteListRepository;
            let apagou = repo.remover(&mut tx, &ctx, id).await?;
            Ok((apagou, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn definir_departamento_da_conexao(
        &self,
        ctx: &RequestContext,
        id: i32,
        departamento_id: Option<i32>,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let ok = conexoes::definir_departamento(&mut tx, &ctx, id, departamento_id).await?;
            Ok((ok, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn detalhe_da_conexao(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<DetalheDaConexao>, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let d = conexoes::detalhe(&mut tx, &ctx, id).await?;
            Ok((d, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn departamentos_das_conexoes(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<(i32, Option<i32>, String)>, DbError> {
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let linhas = conexoes::departamentos_das_conexoes(&mut tx, &ctx).await?;
            let saida = linhas
                .into_iter()
                .map(|l| {
                    (
                        l.id,
                        l.departamento_id,
                        l.departamento_nome.unwrap_or_default(),
                    )
                })
                .collect();
            Ok((saida, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = instance_id, contato_id = contato_id))]
    async fn vincular_contato(
        &self,
        ctx: &RequestContext,
        instance_id: i32,
        jid: &str,
        contato_id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappContactRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let jid = jid.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.criar_ou_atualizar(&mut tx, &ctx, instance_id, &jid, Some(contato_id))
                .await?;
            Ok(((), tx))
        })
        .await
    }
}
