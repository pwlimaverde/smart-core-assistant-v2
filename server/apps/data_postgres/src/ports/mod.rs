pub mod atendimento;
pub mod audit;
pub mod auth;
pub mod cliente;
pub mod operacional;
pub mod plans;
pub mod quota;
pub mod signup;
pub mod tenant;
pub mod treinamento;
pub mod vouchers;
pub mod whatsapp;

pub use atendimento::{
    AtendimentoStore, CampoColetadoDto, CampoPendenteDto, CamposAtendimentoDto, OrigemMensagem,
    TicketKanbanOutcome, TransferenciaFluxoOutcome,
};
pub use audit::AuditPort;
pub use auth::AuthStore;
pub use cliente::ClienteStore;
pub use operacional::OperacionalStore;
pub use plans::PlansStore;
pub use quota::QuotaStore;
pub use signup::{SignupIniciado, SignupStore, SlugIndisponivel, StatusSignup};
pub use tenant::TenantStore;
pub use treinamento::{DocumentoTrecho, QueryComposeResultado, TreinamentoStore};
pub use vouchers::{DesfechoResgate, VoucherStore};
pub use whatsapp::WhatsappStore;

#[cfg(test)]
#[allow(unused_imports)]
pub use atendimento::MockAtendimentoStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use audit::MockAuditPort;
#[cfg(test)]
#[allow(unused_imports)]
pub use auth::MockAuthStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use cliente::MockClienteStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use operacional::MockOperacionalStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use plans::MockPlansStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use quota::MockQuotaStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use signup::MockSignupStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use tenant::MockTenantStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use treinamento::MockTreinamentoStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use vouchers::MockVoucherStore;
#[cfg(test)]
#[allow(unused_imports)]
pub use whatsapp::MockWhatsappStore;
