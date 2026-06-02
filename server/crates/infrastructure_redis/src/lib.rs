//! Crate de infraestrutura de cache e barramento de eventos do Smart Core Assistant v2.
//!
//! Centraliza todo o acesso ao Redis: barramento de eventos (Redis Streams + consumer
//! groups com `TenantEnvelope`), cache de permissões (`flow_permissions`, TTL curto) e
//! gestão de tokens de autenticação (refresh tokens com rotação/detecção de reuso e
//! blocklist de access tokens).
//!
//! REGRA: esta é a ÚNICA crate do workspace que usa o cliente Redis diretamente.
//! Toda chave gravada DEVE respeitar o namespacing por tenant (ver `keys`).

#![allow(clippy::too_many_arguments)]

pub mod auth_tokens;
pub mod cache;
pub mod connection;
pub mod envelope;
pub mod errors;
pub mod event_bus;
pub mod keys;

// Re-exports de conveniência para os binários/consumidores.
pub use auth_tokens::{RefreshTokenStore, RegistroRefresh, TokenBlocklist};
pub use cache::{CachePermissoes, TTL_FLOW_PERMISSIONS_SEGUNDOS};
pub use connection::{criar_cliente, criar_conexao_com_url, criar_conexao_redis, ping};
pub use envelope::TenantEnvelope;
pub use errors::RedisError;
pub use event_bus::{
    confirmar, consumir, garantir_consumer_group, publicar_evento, reprocessar_pendentes,
    EventoBruto, STREAM_EVENTOS,
};
pub use keys::{
    chave_blocklist, chave_flow_permissions, chave_refresh, chave_refresh_familia, chave_tenant,
};
