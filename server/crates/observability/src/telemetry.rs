use opentelemetry::global;
use opentelemetry::KeyValue;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{propagation::TraceContextPropagator, trace::Config, Resource};
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

/// Inicializa o subscriber com JSON no stdout + export OTel via OTLP/gRPC.
/// Deve ser chamado no início de cada binário (gateway, worker, runtime_api, control_plane).
pub fn init_telemetry(
    service_name: &str,
    env: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Propagação W3C TraceContext (inter-serviço)
    global::set_text_map_propagator(TraceContextPropagator::new());

    // Endpoint do Collector (configurável via env)
    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4317".into());

    // Resource com metadados do serviço
    let resource = Resource::new(vec![
        KeyValue::new("service.name", service_name.to_string()),
        KeyValue::new("deployment.environment", env.to_string()),
    ]);

    use opentelemetry::trace::TracerProvider as _;

    // Configurar o pipeline do OpenTelemetry Tracer usando OTLP/gRPC (porta 4317)
    let provider = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(otlp_endpoint),
        )
        .with_trace_config(Config::default().with_resource(resource))
        .install_batch(opentelemetry_sdk::runtime::Tokio)?;

    let tracer = provider.tracer(service_name.to_string());

    // Camada do OpenTelemetry para propagar spans do Tracing
    let otel_layer = OpenTelemetryLayer::new(tracer);

    // Camada fmt para imprimir logs estruturados em JSON no stdout
    let json_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true);

    // Filtro de nível por RUST_LOG ou padrão info
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    // Registra todas as camadas no Tracing Subscriber
    Registry::default()
        .with(env_filter)
        .with(json_layer)
        .with(otel_layer)
        .init();

    tracing::info!(
        service = service_name,
        environment = env,
        "Telemetria inicializada com sucesso (stdout JSON + OTLP gRPC)."
    );

    Ok(())
}

/// Encerra o TracerProvider global, enviando spans pendentes para o collector.
/// Chamar no graceful shutdown do servidor.
pub fn shutdown_telemetry() {
    tracing::info!("Encerrando telemetria — flushing spans pendentes...");
    global::shutdown_tracer_provider();
}
