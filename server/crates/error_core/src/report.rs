//! Registro rastreável de erros — vincula `AppError` a `trace_id` e `tenant_id`
//! e emite log estruturado via `tracing` sem vazar PII ou detalhes internos.

use tracing::{error, warn};

use crate::{
    code::ErrorCode,
    error::{AppError, Severity},
};

/// Contexto de correlação obrigatório para registrar um erro rastreável.
pub struct ErrorContext {
    /// ID de rastreamento distribuído (gerado pela `observability`).
    pub trace_id: String,
    /// Identificador do tenant (multi-tenancy).
    pub tenant_id: String,
}

/// Estrutura completa do registro de erro — aparece no JSON de log.
#[derive(Debug)]
pub struct ErrorReport {
    pub error_code: ErrorCode,
    pub severity: Severity,
    pub trace_id: String,
    pub tenant_id: String,
    /// Mensagem segura para o cliente (nunca detalhe interno).
    pub public_message: String,
    /// Contexto adicional para diagnóstico interno (opcional).
    pub context: Option<String>,
}

impl ErrorReport {
    /// Constrói um `ErrorReport` a partir do `AppError` e do contexto de correlação.
    pub fn from_error(err: &AppError, ctx: &ErrorContext) -> Self {
        Self {
            error_code: err.code(),
            severity: err.severity(),
            trace_id: ctx.trace_id.clone(),
            tenant_id: ctx.tenant_id.clone(),
            public_message: err.public_message().to_owned(),
            context: None,
        }
    }

    /// Adiciona contexto interno de diagnóstico (não exposto ao cliente).
    pub fn with_context(mut self, ctx: impl Into<String>) -> Self {
        self.context = Some(ctx.into());
        self
    }
}

/// Registra um `AppError` via `tracing` com campos de correlação.
///
/// - Usa `error!()` para `Severity::Error` e `warn!()` para `Severity::Warn`.
/// - Nunca inclui PII, stack trace ou mensagem interna no campo `message`.
pub fn registrar(err: &AppError, ctx: &ErrorContext) {
    let report = ErrorReport::from_error(err, ctx);

    match report.severity {
        Severity::Error => {
            error!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                "Erro de aplicação registrado"
            );
        }
        Severity::Warn => {
            warn!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                "Aviso de aplicação registrado"
            );
        }
    }
}
