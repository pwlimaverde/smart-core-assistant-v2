//! Crate que contém os casos de uso de domínio (negócio) do Smart Core Assistant v2.
//!
//! Não se comunica diretamente com infraestrutura de persistência (PostgreSQL/Redis),
//! mas sim através do transportador por contratos RPC síncronos e pub/sub de eventos.

pub mod auth;
pub mod jwt;
pub mod pagamento;
pub mod tokens;
