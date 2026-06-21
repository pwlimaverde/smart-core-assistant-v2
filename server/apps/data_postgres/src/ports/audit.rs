//! Port de auditoria: abstrai a publicação de eventos no bus de segurança.
//! O handler não conhece o ConnectionManager do Redis (DIP).

use async_trait::async_trait;
use contracts::Envelope;

/// Publica um evento de auditoria a partir do envelope da requisição.
/// `event` é o event_type estável (ex.: "whatsapp_instance.created").
/// `message`/`context` JÁ devem estar sanitizados pelo caller (sem segredos).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait AuditPort: Send + Sync {
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    );
}
