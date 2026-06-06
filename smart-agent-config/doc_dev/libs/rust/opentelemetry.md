# OpenTelemetry Rust (opentelemetry + opentelemetry_sdk + opentelemetry-otlp + tracing-opentelemetry)

- **Versão Recomendada:** opentelemetry 0.31.x / opentelemetry_sdk 0.31.x / opentelemetry-otlp 0.32.x / tracing-opentelemetry 0.32.x
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-04
- **Propósito no Projeto:** Bridge entre o ecossistema `tracing` (Rust) e o protocolo OpenTelemetry (OTLP) para exportar spans/traces ao OTel Collector, que roteia para Grafana Tempo (traces), Loki (logs) e Prometheus (métricas).
- **Documentação Oficial:**
  - [opentelemetry-rust (GitHub)](https://github.com/open-telemetry/opentelemetry-rust)
  - [tracing-opentelemetry (docs.rs)](https://docs.rs/tracing-opentelemetry)
  - [opentelemetry-otlp (docs.rs)](https://docs.rs/opentelemetry-otlp)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 usa o `tracing` como framework de instrumentação. O OpenTelemetry entra como **camada de exportação**: o `tracing-opentelemetry` converte spans do `tracing` em spans OTel, e o `opentelemetry-otlp` os envia via gRPC (porta 4317) ao OpenTelemetry Collector configurado no Docker Compose de observabilidade.

### Features de Cargo necessárias

```toml
[workspace.dependencies]
# OpenTelemetry core
opentelemetry       = "0.31"
opentelemetry_sdk   = { version = "0.31", features = ["rt-tokio"] }
opentelemetry-otlp  = { version = "0.32", features = ["grpc-tonic", "trace"] }

# Bridge tracing ↔ OTel
tracing-opentelemetry = "0.32"
```

> **Nota:** as versões do ecossistema OTel Rust mudam frequentemente. Verifique compatibilidade entre `opentelemetry`, `opentelemetry_sdk`, `opentelemetry-otlp` e `tracing-opentelemetry` sempre que atualizar.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Inicialização do TracerProvider + Layer OTel

A configuração completa na crate `observability` combina JSON logging com export OTel:

```rust
use opentelemetry::global;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::trace::SdkTracerProvider;
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

/// Inicializa o subscriber com JSON no stdout + export OTel via OTLP/gRPC.
/// O endpoint padrão é `http://otel-collector:4317` (configurável via env).
pub fn init_telemetry(service_name: &str) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Configurar o exporter OTLP (gRPC para o Collector)
    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://otel-collector:4317".into());

    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .with_endpoint(&otlp_endpoint)
        .build()?;

    // 2. Criar o TracerProvider com batch export (não bloqueia o runtime)
    let provider = SdkTracerProvider::builder()
        .with_batch_exporter(exporter, opentelemetry_sdk::runtime::Tokio)
        .build();

    global::set_tracer_provider(provider.clone());

    // 3. Montar os layers
    let otel_layer = OpenTelemetryLayer::new(provider.tracer(service_name));

    let json_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_thread_ids(true);

    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    // 4. Compor e inicializar
    Registry::default()
        .with(env_filter)
        .with(json_layer)
        .with(otel_layer)
        .init();

    Ok(())
}

/// Encerra o TracerProvider, flushando spans pendentes.
/// Chamar no graceful shutdown do servidor.
pub fn shutdown_telemetry() {
    global::shutdown_tracer_provider();
}
```

### 2.2 Propagação de Contexto (W3C TraceContext)

Para traces distribuídos entre serviços (Rust ↔ Python via gRPC), propague o `traceparent` header:

```rust
use opentelemetry::global;
use opentelemetry::propagation::TextMapPropagator;
use opentelemetry_sdk::propagation::TraceContextPropagator;

// Na inicialização (dentro de init_telemetry):
global::set_text_map_propagator(TraceContextPropagator::new());

// No cliente gRPC (tonic): injetar headers
// No servidor gRPC (tonic): extrair headers e criar span-pai
```

### 2.3 Recurso (Resource) com Metadados do Serviço

Para identificar o serviço nos traces (ex: `messaging_gateway` vs `worker`):

```rust
use opentelemetry_sdk::Resource;
use opentelemetry::KeyValue;

let resource = Resource::builder()
    .with_attributes([
        KeyValue::new("service.name", service_name.to_string()),
        KeyValue::new("deployment.environment", env.to_string()),
    ])
    .build();

// Usar no provider:
// SdkTracerProvider::builder().with_resource(resource)...
```

### 2.4 Proibições

- **Nunca exportar direto para Tempo/Jaeger** — sempre usar o Collector como intermediário.
- **Nunca bloquear no shutdown** — o `shutdown_tracer_provider()` faz flush; registrar no graceful shutdown do Axum/Tonic.
- **Cuidado com versões** — mismatch entre crates OTel causa erros de compilação opacos.

---

## 3. Histórico de Atualizações

- **2026-06-04:** Documentação inicial do ecossistema OpenTelemetry para Rust. Criada durante a reestruturação do plano de observabilidade.
