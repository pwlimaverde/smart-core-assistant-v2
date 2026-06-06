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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_report_creation() {
        let err = AppError::Auth("token expirado".to_string());
        let ctx = ErrorContext {
            trace_id: "trace-id-123".to_string(),
            tenant_id: "tenant-id-456".to_string(),
        };

        // Testa construção do ErrorReport
        let report = ErrorReport::from_error(&err, &ctx);
        assert_eq!(report.error_code, ErrorCode::AuthExpiredToken);
        assert_eq!(report.severity, Severity::Warn);
        assert_eq!(report.trace_id, "trace-id-123");
        assert_eq!(report.tenant_id, "tenant-id-456");
        assert_eq!(report.public_message, "Credencial inválida ou ausente.");
        assert!(report.context.is_none());

        // Testa builder com contexto
        let report_with_ctx = report.with_context("contexto interno de teste");
        assert_eq!(report_with_ctx.context.unwrap(), "contexto interno de teste");
    }

    #[test]
    fn test_registrar_flows() {
        // Garante que a função registrar executa sem erros/pânico para ambas severidades
        let ctx = ErrorContext {
            trace_id: "trace-id-123".to_string(),
            tenant_id: "tenant-id-456".to_string(),
        };

        let err_warn = AppError::Auth("token expirado".to_string());
        let err_error = AppError::Database("conexão falhou".to_string());

        // Deve registrar logs estruturados no tracing sem causar pânico
        registrar(&err_warn, &ctx);
        registrar(&err_error, &ctx);
    }
}

