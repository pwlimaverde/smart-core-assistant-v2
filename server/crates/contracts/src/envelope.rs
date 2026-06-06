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
    /// Traceparent W3C que propaga a cadeia de trace distribuído pelo barramento
    /// (Redis Streams). Vazio quando o evento nasce sem contexto de trace ativo.
    /// `#[serde(default)]` mantém a compatibilidade com eventos antigos sem o campo.
    #[serde(default)]
    pub traceparent: String,
    pub payload: T,
}

impl<T> TenantEnvelope<T> {
    /// Cria um envelope novo com `event_id` (UUID v7) e `timestamp` (agora, UTC).
    /// O `traceparent` começa vazio; use [`TenantEnvelope::com_traceparent`] para anexá-lo.
    pub fn novo(tenant_id: Uuid, event_type: impl Into<String>, payload: T) -> Self {
        Self {
            tenant_id,
            event_id: Uuid::now_v7(),
            event_type: event_type.into(),
            timestamp: Utc::now(),
            traceparent: String::new(),
            payload,
        }
    }

    /// Anexa o `traceparent` W3C ao envelope para propagar o trace distribuído pelo barramento.
    pub fn com_traceparent(mut self, traceparent: impl Into<String>) -> Self {
        self.traceparent = traceparent.into();
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tenant_envelope_new() {
        let tenant_id = Uuid::new_v4();
        let payload = "teste_payload".to_string();

        let env = TenantEnvelope::novo(tenant_id, "meu.evento", payload.clone());

        assert_eq!(env.tenant_id, tenant_id);
        assert_eq!(env.event_type, "meu.evento");
        assert_eq!(env.payload, payload);
        assert_eq!(env.traceparent, "");

        // Valida que event_id é UUID v7
        assert_eq!(env.event_id.get_version_num(), 7);

        // Valida se o timestamp está perto de agora (margem de 5 segundos)
        let agora = Utc::now();
        let diff = agora.signed_duration_since(env.timestamp);
        assert!(diff.num_seconds() >= 0);
        assert!(diff.num_seconds() < 5);
    }

    #[test]
    fn test_tenant_envelope_com_traceparent() {
        let tenant_id = Uuid::new_v4();
        let env = TenantEnvelope::novo(tenant_id, "test", ())
            .com_traceparent("00-trace-id-span-id-01");

        assert_eq!(env.traceparent, "00-trace-id-span-id-01");
    }
}

