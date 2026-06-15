//! Publicação de eventos de auditoria de segurança da borda (`security:stream`).
//!
//! Compartilhado entre o `transport::Server` (handlers do `main.rs`) e a fachada
//! gRPC-Web (`grpc_web.rs`), garantindo que ambas as bordas emitam **os mesmos**
//! eventos sem duplicar a lógica de montagem do envelope de auditoria.

use uuid::Uuid;

/// Publica um evento de auditoria de segurança no `security:stream` (consumido pelo
/// `data_postgres`, que consolida em `audit_log`). Nunca inclui tokens/senhas — apenas
/// identificadores (user_id, jti), o traceparent para correlação e, quando disponível,
/// o IP do cliente repassado pelo proxy.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn publicar_auditoria_borda(
    bus: &mut redis::aio::ConnectionManager,
    tenant_id: Option<Uuid>,
    level: &str,
    event: &str,
    message: String,
    context: serde_json::Value,
    user_id: Option<i32>,
    traceparent: &str,
    ip_address: Option<String>,
) {
    let audit_payload = observability::AuditLogPayload {
        tenant_id,
        level: level.to_string(),
        service: "runtime_api".to_string(),
        trace_id: Some(traceparent.to_string()),
        event: event.to_string(),
        message,
        context,
        user_id,
        ip_address,
    };
    let envelope_auditoria = contracts::TenantEnvelope::novo(
        tenant_id.unwrap_or_else(Uuid::nil),
        "security.audit",
        audit_payload,
    )
    .com_traceparent(traceparent.to_string());

    if let Err(e) = transport::bus::publicar_evento_seguranca(bus, &envelope_auditoria).await {
        tracing::error!("Falha ao publicar evento de auditoria '{}': {:?}", event, e);
    }
}

/// Publica o evento de auditoria `token_reuse_detected` no stream de segurança.
/// Nunca registra o token em si — apenas o traceparent para correlação.
pub(crate) async fn publicar_reuso_detectado(
    bus: &mut redis::aio::ConnectionManager,
    traceparent: &str,
    ip_address: Option<String>,
) {
    publicar_auditoria_borda(
        bus,
        None,
        "WARN",
        "token_reuse_detected",
        "Reuso de refresh token rotacionado detectado; família revogada.".to_string(),
        serde_json::json!({}),
        None,
        traceparent,
        ip_address,
    )
    .await;
}
