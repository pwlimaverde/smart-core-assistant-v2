//! # error_core
//!
//! Crate transversal de tratamento de erros do workspace `smart-core-assistant-v2`.

pub mod code;
pub mod envelope_bridge;
pub mod error;
pub mod report;

#[cfg(feature = "grpc")]
pub mod transport;

pub use code::{ErrorCategory, ErrorCode};
pub use error::{AppError, Severity};
pub use report::{detalhe_sem_dados, registrar, registrar_no_rpc, ErrorContext, ErrorReport};

#[cfg(feature = "grpc")]
pub use transport::to_status;
