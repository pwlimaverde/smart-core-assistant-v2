/// Macro utilitária para criar spans estruturados do Tracing incluindo metadados
/// obrigatórios como `tenant_id` e `trace_id` para facilitar a correlação de logs.
///
/// # Exemplos
/// ```rust
/// use observability::tenant_span;
///
/// let tenant_id = uuid::Uuid::new_v4();
/// let trace_id = "trace-abc-123";
///
/// // Criando span apenas com tenant_id
/// let span = tenant_span!(tenant_id, "processar_mensagem");
/// let _guard = span.enter();
/// drop(_guard);
///
/// // Criando span com tenant_id e trace_id correlacionados
/// let span = tenant_span!(tenant_id, trace_id, "chamar_ia");
/// let _guard = span.enter();
/// ```
#[macro_export]
macro_rules! tenant_span {
    ($tenant_id:expr, $name:expr) => {
        tracing::info_span!($name, tenant_id = %$tenant_id)
    };
    ($tenant_id:expr, $trace_id:expr, $name:expr) => {
        tracing::info_span!($name, tenant_id = %$tenant_id, trace_id = %$trace_id)
    };
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    #[test]
    fn test_tenant_span_macro_expansion() {
        let tenant_id = Uuid::new_v4();
        let trace_id = "trace-123-test";

        // Testa expansão da macro com tenant_id
        let span_com_tenant = tenant_span!(tenant_id, "span_test_1");
        assert_eq!(span_com_tenant.metadata().unwrap().name(), "span_test_1");

        // Testa expansão da macro com tenant_id e trace_id
        let span_com_ambos = tenant_span!(tenant_id, trace_id, "span_test_2");
        assert_eq!(span_com_ambos.metadata().unwrap().name(), "span_test_2");
    }
}
