use infrastructure_postgres::{
    inserir_audit_log, inserir_audit_log_global, NewAuditLogEntry,
};
use sqlx::PgPool;
use uuid::Uuid;

/// Logger de auditoria que persiste eventos críticos no banco de dados de forma assíncrona.
/// Suporta tanto ações vinculadas a inquilinos (RLS) quanto ações globais de superusuário (admin pool).
#[derive(Clone)]
pub struct AuditLogger {
    tenant_pool: PgPool,   // pool convencional com RLS habilitado
    admin_pool: PgPool,    // pool administrativo (BYPASSRLS) para gravação global (tenant_id = NULL)
    service_name: String,
}

impl AuditLogger {
    /// Inicializa o logger com os pools necessários e o nome do serviço atual.
    pub fn new(tenant_pool: PgPool, admin_pool: PgPool, service_name: &str) -> Self {
        Self {
            tenant_pool,
            admin_pool,
            service_name: service_name.to_string(),
        }
    }

    // ============================================================
    // Ações Vinculadas a Tenant (Inquilino)
    // ============================================================

    /// Registra um evento de auditoria para um inquilino em background (fire-and-forget).
    /// Usa o pool com RLS executando dentro de `run_in_tenant_transaction`.
    pub fn log_tenant_event(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        let pool = self.tenant_pool.clone();
        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();

        tokio::spawn(async move {
            let entry = NewAuditLogEntry {
                tenant_id: Some(tenant_id),
                level,
                service,
                trace_id,
                event: event.clone(),
                message,
                context,
                user_id,
                ip_address,
            };

            let result = infrastructure_postgres::run_in_tenant_transaction(
                &pool,
                tenant_id,
                |mut tx| async move {
                    let id = inserir_audit_log(&mut tx, &entry).await?;
                    Ok((id, tx))
                },
            )
            .await;

            if let Err(e) = result {
                tracing::error!(
                    error = ?e,
                    audit_event = %event,
                    tenant_id = %tenant_id,
                    "Falha ao persistir log de auditoria do inquilino no banco."
                );
            }
        });
    }

    // ============================================================
    // Ações Globais (Superusuário / Sistema / Background)
    // ============================================================

    /// Registra um evento de auditoria global (sem tenant_id) em background (fire-and-forget).
    /// Usa o pool administrativo (BYPASSRLS) para gravação direta.
    pub fn log_global_event(
        &self,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        let admin_pool = self.admin_pool.clone();
        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();

        tokio::spawn(async move {
            let entry = NewAuditLogEntry {
                tenant_id: None,
                level,
                service,
                trace_id,
                event: event.clone(),
                message,
                context,
                user_id,
                ip_address,
            };

            let result = inserir_audit_log_global(&admin_pool, &entry).await;

            if let Err(e) = result {
                tracing::error!(
                    error = ?e,
                    audit_event = %event,
                    "Falha ao persistir log de auditoria global no banco."
                );
            }
        });
    }

    // ============================================================
    // Helpers de Nível — COM Tenant
    // ============================================================

    pub fn info(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "INFO", context, user_id, ip_address, trace_id);
    }

    pub fn warn(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "WARN", context, user_id, ip_address, trace_id);
    }

    pub fn error(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "ERROR", context, user_id, ip_address, trace_id);
    }

    // ============================================================
    // Helpers de Nível — SEM Tenant (Globais)
    // ============================================================

    pub fn info_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "INFO", context, user_id, ip_address, trace_id);
    }

    pub fn warn_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "WARN", context, user_id, ip_address, trace_id);
    }

    pub fn error_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "ERROR", context, user_id, ip_address, trace_id);
    }
}
