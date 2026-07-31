//! Port do domínio Voucher: criação, listagem e revogação (superusuário) e o
//! resgate em si (chamado pelo provedor de pagamento durante o cadastro).
//!
//! O handler depende SOMENTE desta trait; a transação e o SQL vivem no adapter.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use infrastructure_postgres::DbError;
use uuid::Uuid;

/// Desfecho de um resgate, já resolvido contra o banco.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DesfechoResgate {
    Concedido {
        resgate_id: Uuid,
        plan_id: i32,
        periodo_inicio: DateTime<Utc>,
        periodo_fim: DateTime<Utc>,
    },
    /// Recusa é caso de negócio: `motivo` é o discriminante para log/auditoria,
    /// `mensagem` é o texto que vai ao usuário (e que não revela se o código
    /// existe).
    Recusado { motivo: String, mensagem: String },
}

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait VoucherStore: Send + Sync {
    /// Resgata `codigo` para `tenant_id`, registrando a concessão na mesma
    /// transação — o que torna o par (resgate, registro) tudo-ou-nada.
    async fn resgatar(
        &self,
        codigo: &str,
        tenant_id: Uuid,
        ip: &str,
    ) -> Result<DesfechoResgate, DbError>;

    #[allow(clippy::too_many_arguments)]
    async fn criar(
        &self,
        codigo: &str,
        descricao: &str,
        plan_id: i32,
        duracao_dias: i32,
        max_resgates: i32,
        valido_ate: Option<DateTime<Utc>>,
        created_by_id: Option<i32>,
    ) -> Result<serde_json::Value, DbError>;

    async fn listar(&self) -> Result<Vec<serde_json::Value>, DbError>;

    /// `true` se a revogação afetou o voucher (`false` = já estava revogado).
    async fn revogar(
        &self,
        voucher_id: Uuid,
        revogado_por_id: Option<i32>,
        motivo: &str,
    ) -> Result<bool, DbError>;

    async fn listar_resgates(&self, voucher_id: Uuid) -> Result<Vec<serde_json::Value>, DbError>;
}
