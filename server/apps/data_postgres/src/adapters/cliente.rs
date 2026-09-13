//! Adapter concreto do domínio Cliente: reusa PostgresContatoRepository de
//! infrastructure_postgres e encapsula a transação. O SQL não muda.

use async_trait::async_trait;
use sqlx::PgPool;

use infrastructure_postgres::clientes::contatos::{
    Contato, ContatoRepository, EdicaoContato, PostgresContatoRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::{ClienteStore, DesfechoEdicaoContato};

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
    async fn listar_clientes(
        &self,
        ctx: &RequestContext,
        busca: String,
        incluir_inativos: bool,
        limite: i64,
    ) -> Result<Vec<infrastructure_postgres::clientes::clientes::ClienteResumo>, DbError> {
        let ctx = ctx.clone();
        let limite = limite.clamp(1, 200);
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let itens = infrastructure_postgres::clientes::clientes::listar_clientes(
                &mut tx,
                &ctx,
                busca.trim(),
                incluir_inativos,
                limite,
            )
            .await?;
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn criar_cliente(
        &self,
        ctx: &RequestContext,
        dados: infrastructure_postgres::clientes::clientes::DadosCliente,
    ) -> Result<infrastructure_postgres::clientes::clientes::ClienteResumo, DbError> {
        use infrastructure_postgres::clientes::clientes as repo;
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let id = repo::criar_cliente(&mut tx, &ctx, &dados).await?;
            let criado = repo::buscar_cliente(&mut tx, &ctx, id)
                .await?
                .ok_or(DbError::NotFound)?;
            Ok((criado, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_cliente(
        &self,
        ctx: &RequestContext,
        id: i32,
        dados: infrastructure_postgres::clientes::clientes::DadosCliente,
    ) -> Result<Option<Vec<String>>, DbError> {
        use infrastructure_postgres::clientes::clientes as repo;
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let Some(antes) = repo::buscar_cliente(&mut tx, &ctx, id).await? else {
                return Ok((None, tx));
            };
            let campos: Vec<String> = repo::campos_alterados(&antes, &dados)
                .into_iter()
                .map(str::to_string)
                .collect();
            if !campos.is_empty() {
                repo::atualizar_cliente(&mut tx, &ctx, id, &dados).await?;
            }
            Ok((Some(campos), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn definir_cliente_ativo(
        &self,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let feito = infrastructure_postgres::clientes::clientes::definir_cliente_ativo(
                &mut tx, &ctx, id, ativo,
            )
            .await?;
            Ok((feito, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, cliente_id = cliente_id))]
    async fn contatos_do_cliente(
        &self,
        ctx: &RequestContext,
        cliente_id: i32,
    ) -> Result<Vec<infrastructure_postgres::clientes::clientes::ContatoVinculado>, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let itens = infrastructure_postgres::clientes::clientes::contatos_do_cliente(
                &mut tx, &ctx, cliente_id,
            )
            .await?;
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, cliente_id = cliente_id, contato_id = contato_id))]
    async fn vincular_contato_cliente(
        &self,
        ctx: &RequestContext,
        cliente_id: i32,
        contato_id: i32,
        vincular: bool,
    ) -> Result<bool, DbError> {
        let ctx = ctx.clone();
        run_in_tenant_transaction(&self.pool, ctx.tenant_id, |mut tx| async move {
            let feito = infrastructure_postgres::clientes::clientes::vincular_contato(
                &mut tx, &ctx, cliente_id, contato_id, vincular,
            )
            .await?;
            Ok((feito, tx))
        })
        .await
    }

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

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_contatos(
        &self,
        ctx: &RequestContext,
        busca: Option<String>,
        limite: i64,
    ) -> Result<Vec<Contato>, DbError> {
        let repo = PostgresContatoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        // Teto defensivo: a lista cresce sem limite com o uso, e um cliente que
        // peça 100 mil linhas derrubaria a tela dele e pesaria no banco.
        let limite = limite.clamp(1, 200);

        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let itens = repo
                .listar_por_tenant(&mut tx, &ctx, busca.as_deref(), limite)
                .await?;
            Ok((itens, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn criar_contato(
        &self,
        ctx: &RequestContext,
        telefone: String,
        nome: Option<String>,
        email: Option<String>,
    ) -> Result<Contato, DbError> {
        let repo = PostgresContatoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let contato = repo
                .criar_manual(&mut tx, &ctx, &telefone, nome.as_deref(), email.as_deref())
                .await?;
            Ok((contato, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id))]
    async fn atualizar_contato(
        &self,
        ctx: &RequestContext,
        id: i32,
        edicao: EdicaoContato,
    ) -> Result<DesfechoEdicaoContato, DbError> {
        let repo = PostgresContatoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            // A contagem e o UPDATE na mesma transação de propósito: é ela que
            // impede duas edições simultâneas de concluírem, as duas, que o
            // contato "ainda não tinha conversa".
            if edicao.telefone.is_some() {
                let atendimentos = repo.contar_atendimentos(&mut tx, &ctx, id).await?;
                if atendimentos > 0 {
                    return Ok((DesfechoEdicaoContato::TelefoneTravado { atendimentos }, tx));
                }
            }

            let achou = repo.atualizar(&mut tx, &ctx, id, edicao).await?;
            let desfecho = if achou {
                DesfechoEdicaoContato::Atualizado
            } else {
                DesfechoEdicaoContato::NaoEncontrado
            };
            Ok((desfecho, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, id = id, ativo = ativo))]
    async fn definir_contato_ativo(
        &self,
        ctx: &RequestContext,
        id: i32,
        ativo: bool,
    ) -> Result<bool, DbError> {
        let repo = PostgresContatoRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let achou = repo.desativar(&mut tx, &ctx, id, ativo).await?;
            Ok((achou, tx))
        })
        .await
    }
}
