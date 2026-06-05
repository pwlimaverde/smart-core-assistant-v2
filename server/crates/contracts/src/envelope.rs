use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Envelope obrigatório de todo evento publicado no barramento (Redis Streams).
///
/// O `tenant_id` reside na raiz para que consumidores assíncronos configurem o contexto
/// RLS de banco antes de rodar os Use Cases. O `event_id` é um UUID v7 (ordenável no tempo)
/// que garante idempotência.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TenantEnvelope<T> {
    pub tenant_id: Uuid,
    pub event_id: Uuid,
    pub event_type: String,
    pub timestamp: DateTime<Utc>,
    pub payload: T,
}

impl<T> TenantEnvelope<T> {
    /// Cria um envelope novo com `event_id` (UUID v7) e `timestamp` (agora, UTC).
    pub fn novo(tenant_id: Uuid, event_type: impl Into<String>, payload: T) -> Self {
        Self {
            tenant_id,
            event_id: Uuid::now_v7(),
            event_type: event_type.into(),
            timestamp: Utc::now(),
            payload,
        }
    }
}
