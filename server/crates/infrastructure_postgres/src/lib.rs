//! Crate de infraestrutura de persistência do Smart Core Assistant v2.
//!
//! Implementa banco PostgreSQL único com isolamento lógico via Row-Level Security (RLS),
//! busca vetorial pgvector (1536 dimensões, cosseno), cache DashMap de configurações
//! e criptografia AES-256-GCM de credenciais.
//!
//! REGRA: esta é a ÚNICA crate do workspace que usa SQLx diretamente.
//! Toda query em tabela de tenant DEVE correr dentro de run_in_tenant_transaction.

// Lints permitidos por design desta camada de persistência:
// - too_many_arguments: os repositórios recebem tx + ctx + os campos da entidade.
// - module_inception: a estrutura é um-arquivo-por-domínio (ex.: tenants/tenants.rs).
#![allow(clippy::too_many_arguments, clippy::module_inception)]

pub mod atendimentos;
pub mod clientes;
pub mod config_cache;
pub mod connection;
pub mod crypto;
pub mod errors;
pub mod integracoes;
pub mod operacional;
pub mod security;
pub mod tenants;
pub mod treinamento;

// Re-exports de conveniência para os binários consumidores
pub use config_cache::{RuntimeConfig, TenantConfigCache};
pub use connection::{criar_pool, inicializar_banco_dados, run_in_tenant_transaction};
pub use crypto::CipherManager;
pub use errors::DbError;
pub use security::RequestContext;
