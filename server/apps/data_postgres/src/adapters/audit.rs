//! Adapter de auditoria: publica no bus de segurança via ConnectionManager.

use async_trait::async_trait;
use contracts::Envelope;
use redis::aio::ConnectionManager;
use uuid::Uuid;

use crate::ports::AuditPort;

/// Publica eventos de auditoria no bus de segurança (REDIS_BUS_URL).
#[derive(Clone)]
pub struct RedisAuditPort {
    conn: ConnectionManager,
}

impl RedisAuditPort {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl AuditPort for RedisAuditPort {
    #[tracing::instrument(skip_all, fields(event = event))]
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    ) {
        // ConnectionManager é clonável (compartilha a conexão multiplexada subjacente).
        let mut conn = self.conn.clone();
        // Reusa a função existente: NÃO há auditoria própria aqui (evita recursão);
        // a falha de publicação é registrada como ERROR dentro de publicar_auditoria.
        crate::publicar_auditoria(&mut conn, env, event, message, context).await;
    }

    #[tracing::instrument(skip_all, fields(event = event, level = level))]
    async fn publish_security(
        &self,
        traceparent: &str,
        tenant_id: Option<Uuid>,
        level: &str,
        event: &str,
        message: String,
        context: serde_json::Value,
        user_id: Option<i32>,
    ) {
        let mut conn = self.conn.clone();
        // Eventos globais (sem tenant) usam Uuid::nil como roteamento no envelope,
        // preservando `tenant_id = None` no payload de auditoria.
        let audit_payload = observability::AuditLogPayload {
            tenant_id,
            level: level.to_string(),
            service: "data_postgres".to_string(),
            trace_id: Some(traceparent.to_string()),
            event: event.to_string(),
            message,
            context,
            user_id,
            ip_address: None,
            user_agent: None,
        };
        let envelope_auditoria = contracts::TenantEnvelope::novo(
            tenant_id.unwrap_or_else(Uuid::nil),
            "security.audit",
            audit_payload,
        )
        .com_traceparent(traceparent.to_string());
        if let Err(e) =
            transport::bus::publicar_evento_seguranca(&mut conn, &envelope_auditoria).await
        {
            tracing::error!("Falha ao publicar evento de segurança '{}': {:?}", event, e);
        }
    }
}
