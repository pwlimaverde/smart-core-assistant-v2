//! Port de auditoria: abstrai a publicação de eventos no bus de segurança.
//! O handler não conhece o ConnectionManager do Redis (DIP).

use async_trait::async_trait;
use contracts::Envelope;
use uuid::Uuid;

/// Publica eventos de auditoria a partir do envelope da requisição.
/// `message`/`context` JÁ devem estar sanitizados pelo caller (sem segredos).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait AuditPort: Send + Sync {
    /// Evento de auditoria tenant-scoped padrão (nível WARN, user_id do envelope).
    /// `event` é o event_type estável (ex.: "whatsapp_instance.created").
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    );

    /// Evento de segurança com controle explícito de tenant/level/user_id. Usado por
    /// eventos globais (sem tenant) ou de nível diferente de WARN, como
    /// `superuser_created` (INFO global), `superuser_deleted` (WARN global) e
    /// `login_failed`. `message`/`context` JÁ devem estar sanitizados.
    #[allow(clippy::too_many_arguments)]
    async fn publish_security(
        &self,
        traceparent: &str,
        tenant_id: Option<Uuid>,
        level: &str,
        event: &str,
        message: String,
        context: serde_json::Value,
        user_id: Option<i32>,
    );
}
