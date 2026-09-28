//! Port do plano ia-engine-jev: regras de transferência, sinais automáticos,
//! motor por tenant e o registro das decisões da IA.

use async_trait::async_trait;
use infrastructure_postgres::transferencia::{
    ConfigTransferencia, DadosRegra, DecisaoIa, RegraTransferencia,
};
use infrastructure_postgres::{DbError, RequestContext};
use uuid::Uuid;

/// Uma escrita recusada por regra de negócio (nome repetido, fluxo de outro
/// tenant, pedido inválido): o motivo vai para a tela, não vira erro 500.
pub type Recusavel<T> = Result<T, String>;

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait TransferenciaStore: Send + Sync {
    async fn listar_regras(&self, ctx: &RequestContext)
        -> Result<Vec<RegraTransferencia>, DbError>;

    async fn obter_regra(
        &self,
        ctx: &RequestContext,
        id: i64,
    ) -> Result<Option<RegraTransferencia>, DbError>;

    /// Cria a regra (inativa, a menos que `ativa`). Recusa nome repetido.
    async fn criar_regra(
        &self,
        ctx: &RequestContext,
        dados: DadosRegra,
        ativa: bool,
    ) -> Result<Recusavel<RegraTransferencia>, DbError>;

    /// Atualiza só os campos presentes em `payload`. Devolve (antes, depois);
    /// `None` = não existe.
    async fn atualizar_regra(
        &self,
        ctx: &RequestContext,
        id: i64,
        payload: serde_json::Value,
    ) -> Result<Recusavel<Option<(RegraTransferencia, RegraTransferencia)>>, DbError>;

    async fn definir_regra_ativa(
        &self,
        ctx: &RequestContext,
        id: i64,
        ativa: bool,
    ) -> Result<Option<RegraTransferencia>, DbError>;

    async fn obter_config(&self, ctx: &RequestContext) -> Result<ConfigTransferencia, DbError>;

    /// Sinais e/ou fluxo padrão. Devolve (antes, depois).
    async fn definir_config(
        &self,
        ctx: &RequestContext,
        sinais: Option<serde_json::Value>,
        fluxo_padrao: Option<Option<i32>>,
    ) -> Result<Recusavel<(ConfigTransferencia, ConfigTransferencia)>, DbError>;

    async fn listar_transferencias(
        &self,
        ctx: &RequestContext,
        limite: i64,
    ) -> Result<Vec<serde_json::Value>, DbError>;

    async fn registrar_decisao(
        &self,
        ctx: &RequestContext,
        decisao: DecisaoIa,
    ) -> Result<i64, DbError>;

    async fn marcar_motor_da_mensagem(
        &self,
        ctx: &RequestContext,
        mensagem_id: i32,
        motor: String,
        modelo: String,
    ) -> Result<(), DbError>;

    /// Cria as sugestões inativas a partir do texto de transferência de hoje
    /// (comportamentos das intenções e prompt de regras). Devolve quantas.
    async fn gerar_sugestoes(&self, ctx: &RequestContext) -> Result<usize, DbError>;

    /// Superusuário: motor do tenant (`None` = herda o global). Devolve o anterior.
    async fn definir_motor(
        &self,
        tenant_id: Uuid,
        motor: Option<String>,
    ) -> Result<Option<String>, DbError>;

    /// Retenção: apaga decisões com mais de `dias` (pool administrativo).
    async fn purgar_decisoes(&self, dias: i64) -> Result<u64, DbError>;
}
