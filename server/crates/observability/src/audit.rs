// Os métodos de auditoria carregam o contexto completo do evento (tenant, ator, trace,
// rede) numa única chamada; a assinatura larga é intencional e espelha a tabela audit_log.
#![allow(clippy::too_many_arguments)]

use redis::aio::ConnectionManager;
use uuid::Uuid;

#[cfg(feature = "postgres-audit")]
use sqlx::PgPool;

/// Payload do evento de log de auditoria publicado no barramento.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AuditLogPayload {
    pub tenant_id: Option<Uuid>,
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
    /// User-Agent da requisição que originou o evento (doc 08 §4.2). Campo aditivo:
    /// `#[serde(default)]` mantém retrocompatibilidade com payloads antigos sem ele.
    #[serde(default)]
    pub user_agent: Option<String>,
}

/// Metadados de ator/rede/trace de um evento de auditoria, agrupados para evitar
/// que `info`/`warn`/`error` cresçam em mais parâmetros posicionais soltos (WS-5b).
/// `Default` cobre call-sites de sistema (sem ator HTTP por trás do evento).
#[derive(Debug, Clone, Default)]
pub struct AuditContext {
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
    pub trace_id: Option<String>,
}

/// Logger de auditoria que redireciona logs para o Redis Streams em produção.
/// Em ambiente de testes, pode salvar diretamente no banco de dados para retrocompatibilidade.
#[derive(Clone)]
pub struct AuditLogger {
    service_name: String,
    redis_conn: Option<ConnectionManager>,
    #[cfg(feature = "postgres-audit")]
    tenant_pool: Option<PgPool>,
    #[cfg(feature = "postgres-audit")]
    admin_pool: Option<PgPool>,
}

impl AuditLogger {
    /// Inicializa o logger para testes com os pools do Postgres.
    #[cfg(feature = "postgres-audit")]
    pub fn new(tenant_pool: PgPool, admin_pool: PgPool, service_name: &str) -> Self {
        Self {
            service_name: service_name.to_string(),
            redis_conn: None,
            tenant_pool: Some(tenant_pool),
            admin_pool: Some(admin_pool),
        }
    }

    /// Inicializa o logger para produção usando o barramento do Redis.
    pub fn new_with_redis(redis_conn: ConnectionManager, service_name: &str) -> Self {
        Self {
            service_name: service_name.to_string(),
            redis_conn: Some(redis_conn),
            #[cfg(feature = "postgres-audit")]
            tenant_pool: None,
            #[cfg(feature = "postgres-audit")]
            admin_pool: None,
        }
    }

    /// Inicializa um logger inativo (dummy) para testes isolados.
    pub fn new_dummy(service_name: &str) -> Self {
        Self {
            service_name: service_name.to_string(),
            redis_conn: None,
            #[cfg(feature = "postgres-audit")]
            tenant_pool: None,
            #[cfg(feature = "postgres-audit")]
            admin_pool: None,
        }
    }

    // ============================================================
    // Ações Vinculadas a Tenant (Inquilino)
    // ============================================================

    /// Registra um evento de auditoria para um inquilino.
    /// Em produção publica no Redis Streams, em testes salva direto no banco.
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
        self.log_tenant_event_com_user_agent(
            tenant_id, event, message, level, context, user_id, ip_address, None, trace_id,
        );
    }

    /// Variante de [`Self::log_tenant_event`] que recebe o `AuditContext` agregado
    /// (inclui `user_agent`) em vez de metadados soltos — eventos críticos (doc 08
    /// §4.2) devem migrar para esta forma.
    pub fn log_tenant_event_ctx(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        ctx: &AuditContext,
    ) {
        self.log_tenant_event_com_user_agent(
            tenant_id,
            event,
            message,
            level,
            context,
            ctx.user_id,
            ctx.ip_address.clone(),
            ctx.user_agent.clone(),
            ctx.trace_id.clone(),
        );
    }

    #[allow(clippy::too_many_arguments)]
    fn log_tenant_event_com_user_agent(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        user_agent: Option<String>,
        trace_id: Option<String>,
    ) {
        // user_id=0 é o sentinela documentado de "público/não autenticado"
        // (envelope.proto: auth_user_id). Nunca deve virar Some(0) no payload —
        // não existe auth_user id=0, violaria audit_log_user_id_fkey. Filtrado
        // aqui uma vez para blindar todos os chamadores (dezenas, entre
        // webhook_ingress, worker e runtime_api).
        let user_id = user_id.filter(|&id| id > 0);

        // tenant_id nil é o sentinela já usado em todo o codebase para "sem
        // tenant real" (webhook não autenticado, login antes de resolver o
        // tenant, job de sistema). Sem este guard, Some(Uuid::nil()) ia pro
        // payload e violava audit_log_tenant_id_fkey — o evento se perdia em
        // silêncio. Achado ao auditar o sistema de auditoria: reproduzível por
        // qualquer request HTTP externo sem autenticação em webhook_ingress
        // (tenant_id vem direto do path da URL, antes da checagem de api key).
        if tenant_id.is_nil() {
            self.log_global_event_com_user_agent(
                event, message, level, context, user_id, ip_address, user_agent, trace_id,
            );
            return;
        }

        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();
        let trace_id_clone = trace_id.clone();

        if let Some(mut con) = self.redis_conn.clone() {
            tokio::spawn(async move {
                let payload = AuditLogPayload {
                    tenant_id: Some(tenant_id),
                    level: level.clone(),
                    service: service.clone(),
                    trace_id: trace_id_clone,
                    event: event.clone(),
                    message,
                    context,
                    user_id,
                    ip_address,
                    user_agent,
                };
                let traceparent = payload.trace_id.clone().unwrap_or_default();
                let envelope = contracts::TenantEnvelope::novo(tenant_id, "audit_log", payload)
                    .com_traceparent(traceparent);
                if let Err(e) = transport::bus::publicar_evento_seguranca(&mut con, &envelope).await
                {
                    tracing::error!(
                        error = ?e,
                        audit_event = %event,
                        tenant_id = %tenant_id,
                        "Falha ao publicar log de auditoria no Redis Streams"
                    );
                }
            });
        } else {
            // Sem Redis (cenário de testes): grava direto no banco quando habilitado.
            #[cfg(feature = "postgres-audit")]
            {
                if let Some(pool) = self.tenant_pool.clone() {
                    tokio::spawn(async move {
                        let entry = infrastructure_postgres::NewAuditLogEntry {
                            tenant_id: Some(tenant_id),
                            level,
                            service,
                            trace_id,
                            event: event.clone(),
                            message,
                            context,
                            user_id,
                            ip_address,
                            user_agent,
                        };

                        let result = infrastructure_postgres::run_in_tenant_transaction(
                            &pool,
                            tenant_id,
                            |mut tx| async move {
                                let id =
                                    infrastructure_postgres::inserir_audit_log(&mut tx, &entry)
                                        .await?;
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
            }
        }
    }

    // ============================================================
    // Ações Globais (Superusuário / Sistema / Background)
    // ============================================================

    /// Registra um evento de auditoria global (sem tenant_id).
    /// Em produção publica no Redis Streams, em testes salva direto no banco.
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
        self.log_global_event_com_user_agent(
            event, message, level, context, user_id, ip_address, None, trace_id,
        );
    }

    /// Variante de [`Self::log_global_event`] que recebe o `AuditContext` agregado
    /// (inclui `user_agent`) em vez de metadados soltos.
    pub fn log_global_event_ctx(
        &self,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        ctx: &AuditContext,
    ) {
        self.log_global_event_com_user_agent(
            event,
            message,
            level,
            context,
            ctx.user_id,
            ctx.ip_address.clone(),
            ctx.user_agent.clone(),
            ctx.trace_id.clone(),
        );
    }

    #[allow(clippy::too_many_arguments)]
    fn log_global_event_com_user_agent(
        &self,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        user_agent: Option<String>,
        trace_id: Option<String>,
    ) {
        // Mesmo filtro de log_tenant_event_com_user_agent — repetido aqui porque
        // esta função também é chamada diretamente (log_global_event/_ctx), não só
        // por delegação do caminho de tenant.
        let user_id = user_id.filter(|&id| id > 0);

        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();
        let trace_id_clone = trace_id.clone();

        if let Some(mut con) = self.redis_conn.clone() {
            tokio::spawn(async move {
                let payload = AuditLogPayload {
                    tenant_id: None,
                    level: level.clone(),
                    service: service.clone(),
                    trace_id: trace_id_clone,
                    event: event.clone(),
                    message,
                    context,
                    user_id,
                    ip_address,
                    user_agent,
                };
                let traceparent = payload.trace_id.clone().unwrap_or_default();
                let envelope = contracts::TenantEnvelope::novo(Uuid::nil(), "audit_log", payload)
                    .com_traceparent(traceparent);
                if let Err(e) = transport::bus::publicar_evento_seguranca(&mut con, &envelope).await
                {
                    tracing::error!(
                        error = ?e,
                        audit_event = %event,
                        "Falha ao publicar log de auditoria global no Redis Streams"
                    );
                }
            });
        } else {
            // Sem Redis (cenário de testes): grava direto no banco quando habilitado.
            #[cfg(feature = "postgres-audit")]
            {
                if let Some(admin_pool) = self.admin_pool.clone() {
                    tokio::spawn(async move {
                        let entry = infrastructure_postgres::NewAuditLogEntry {
                            tenant_id: None,
                            level,
                            service,
                            trace_id,
                            event: event.clone(),
                            message,
                            context,
                            user_id,
                            ip_address,
                            user_agent,
                        };

                        let result =
                            infrastructure_postgres::inserir_audit_log_global(&admin_pool, &entry)
                                .await;

                        if let Err(e) = result {
                            tracing::error!(
                                error = ?e,
                                audit_event = %event,
                                "Falha ao persistir log de auditoria global no banco."
                            );
                        }
                    });
                }
            }
        }
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
        self.log_tenant_event(
            tenant_id, event, message, "INFO", context, user_id, ip_address, trace_id,
        );
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
        self.log_tenant_event(
            tenant_id, event, message, "WARN", context, user_id, ip_address, trace_id,
        );
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
        self.log_tenant_event(
            tenant_id, event, message, "ERROR", context, user_id, ip_address, trace_id,
        );
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
        self.log_global_event(
            event, message, "INFO", context, user_id, ip_address, trace_id,
        );
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
        self.log_global_event(
            event, message, "WARN", context, user_id, ip_address, trace_id,
        );
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
        self.log_global_event(
            event, message, "ERROR", context, user_id, ip_address, trace_id,
        );
    }
}
