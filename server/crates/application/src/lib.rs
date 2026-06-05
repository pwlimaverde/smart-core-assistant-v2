//! Crate que contém os casos de uso de domínio (negócio) do Smart Core Assistant v2.
//! 
//! Não se comunica diretamente com infraestrutura de persistência (PostgreSQL/Redis),
//! mas sim através do transportador por contratos RPC síncronos e pub/sub de eventos.

use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct RequestContext {
    /// Identificador único do tenant associado à requisição.
    pub tenant_id: Uuid,
    /// Identificador do usuário logado.
    pub user_id: i32,
    /// Permissões/Escopos concedidos ao usuário.
    pub user_scopes: Vec<String>,
    /// Identificador de rastreamento distribuído (W3C trace context).
    pub traceparent: String,
}

pub mod auth;
