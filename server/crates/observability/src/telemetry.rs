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
    // Camada fmt para imprimir logs estruturados em JSON no stdout
    let json_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true);

    // Filtro de nível por RUST_LOG ou padrão info
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    // Verifica se a telemetria do SDK do OpenTelemetry foi desativada via variavel de ambiente
    let otel_disabled = std::env::var("OTEL_SDK_DISABLED")
        .map(|v| v.to_lowercase() == "true")
        .unwrap_or(false);

    if otel_disabled {
        // Registra apenas o formatador JSON local, sem o pipeline OTel/OTLP
        Registry::default().with(env_filter).with(json_layer).init();

        tracing::info!(
            service = service_name,
            environment = env,
            "Telemetria inicializada no modo local (apenas stdout JSON, OTel desativado)."
        );
        return Ok(());
    }

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
                .with_endpoint(&otlp_endpoint),
        )
        .with_trace_config(Config::default().with_resource(resource.clone()))
        .install_batch(opentelemetry_sdk::runtime::Tokio)?;

    let tracer = provider.tracer(service_name.to_string());

    // Camada do OpenTelemetry para propagar spans do Tracing
    let otel_layer = OpenTelemetryLayer::new(tracer);

    // Registra todas as camadas no Tracing Subscriber
    Registry::default()
        .with(env_filter)
        .with(json_layer)
        .with(otel_layer)
        .init();

    // Inicializa o pipeline de métricas OTLP
    if let Err(e) = init_metrics(&otlp_endpoint, resource) {
        tracing::warn!("Falha ao inicializar pipeline de métricas OTLP: {:?}", e);
    }

    tracing::info!(
        service = service_name,
        environment = env,
        "Telemetria inicializada com sucesso (stdout JSON + OTLP gRPC)."
    );

    Ok(())
}

/// Inicializa o pipeline de MÉTRICAS via OTLP/gRPC, reaproveitando o mesmo endpoint e
/// resource do tracing. API da otlp 0.17: `new_pipeline().metrics(rt)...build()`.
pub fn init_metrics(
    otlp_endpoint: &str,
    resource: Resource,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let meter_provider = opentelemetry_otlp::new_pipeline()
        .metrics(opentelemetry_sdk::runtime::Tokio)
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(otlp_endpoint),
        )
        .with_resource(resource)
        .with_period(std::time::Duration::from_secs(10)) // export de métricas a cada 10s
        .build()?;
    opentelemetry::global::set_meter_provider(meter_provider);
    tracing::info!("Pipeline de métricas OTLP inicializado.");
    Ok(())
}

/// Encerra o TracerProvider e o MeterProvider globais, enviando spans e métricas pendentes.
/// Chamar no graceful shutdown do servidor.
pub fn shutdown_telemetry() {
    tracing::info!("Encerrando telemetria — flushing spans e métricas pendentes...");
    global::shutdown_tracer_provider();
    // Em opentelemetry v0.24, não há global::shutdown_meter_provider()
}
