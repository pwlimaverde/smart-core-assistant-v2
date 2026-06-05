use error_core::{AppError, ErrorContext, ErrorReport, ErrorCode, Severity, registrar};

#[test]
fn test_error_report_from_error() {
    // Arrange
    let err = AppError::Auth("token expirado".to_owned());
    let ctx = ErrorContext {
        trace_id: "trace-123".to_owned(),
        tenant_id: "tenant-abc".to_owned(),
    };

    // Act
    let report = ErrorReport::from_error(&err, &ctx);

    // Assert
    assert_eq!(report.error_code, ErrorCode::AuthExpiredToken);
    assert_eq!(report.severity, Severity::Warn);
    assert_eq!(report.trace_id, "trace-123");
    assert_eq!(report.tenant_id, "tenant-abc");
    assert_eq!(report.public_message, err.public_message());
    assert!(report.context.is_none());
}

#[test]
fn test_error_report_with_context() {
    // Arrange
    let err = AppError::Database("conexão falhou".to_owned());
    let ctx = ErrorContext {
        trace_id: "trace-456".to_owned(),
        tenant_id: "tenant-xyz".to_owned(),
    };

    // Act
    let report = ErrorReport::from_error(&err, &ctx)
        .with_context("Erro adicional de teste interno");

    // Assert
    assert_eq!(report.error_code, ErrorCode::DbConnectionFailed);
    assert_eq!(report.severity, Severity::Error);
    assert_eq!(report.context, Some("Erro adicional de teste interno".to_owned()));
}

#[test]
fn test_registrar_does_not_panic() {
    let err = AppError::Internal("erro crítico de teste".to_owned());
    let ctx = ErrorContext {
        trace_id: "trace-789".to_owned(),
        tenant_id: "tenant-123".to_owned(),
    };

    // Deve registrar o log com Severity::Error sem pânico.
    registrar(&err, &ctx);

    let err_warn = AppError::Validation("dados inválidos".to_owned());
    // Deve registrar o log com Severity::Warn sem pânico.
    registrar(&err_warn, &ctx);
}
