/// Macro utilitária para criar spans estruturados do Tracing incluindo metadados
/// obrigatórios como `tenant_id` e `trace_id` para facilitar a correlação de logs.
///
/// # Exemplos
/// ```rust
/// // Criando span apenas com tenant_id
/// let span = tenant_span!(tenant_id, "processar_mensagem");
/// let _guard = span.enter();
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
