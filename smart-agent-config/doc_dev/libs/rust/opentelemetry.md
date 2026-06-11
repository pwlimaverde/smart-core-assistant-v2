# OpenTelemetry Rust (opentelemetry + opentelemetry_sdk + opentelemetry-otlp + tracing-opentelemetry)

- **Versão no Projeto (ATUAL):** opentelemetry 0.24 / opentelemetry_sdk 0.24 / opentelemetry-otlp 0.17 / tracing-opentelemetry 0.25
- **Versão Recomendada (docs obsoletas):** opentelemetry 0.31.x / opentelemetry_sdk 0.31.x / opentelemetry-otlp 0.32.x / tracing-opentelemetry 0.32.x
- **Status de Atualização:** ✅ ATUALIZADA (alinhada com Cargo.toml + API de Métricas adicionada)
- **Última Verificação:** 2026-06-10
- **⚠️ Nota Importante:** Este documento foi atualizado para cobrir a versão **0.24** real do projeto (conforme `server/crates/observability/Cargo.toml`). A documentação de traces foi criada em 2026-06-04 citando versão 0.31, que NÃO corresponde ao projeto. Se houver versão 0.31/0.32+ em outro contexto, consulte context7 novamente para aquela stack específica. A API de métricas em 0.24 difere significativamente de versões posteriores (0.27+/0.31+).
- **Propósito no Projeto:** Bridge entre o ecossistema `tracing` (Rust) e o protocolo OpenTelemetry (OTLP) para exportar spans/traces ao OTel Collector, que roteia para Grafana Tempo (traces), Loki (logs) e Prometheus (métricas). Instrumentação de métricas para observabilidade de pools, latência e erros.
- **Documentação Oficial:**
  - [opentelemetry-rust (GitHub)](https://github.com/open-telemetry/opentelemetry-rust)
  - [tracing-opentelemetry (docs.rs)](https://docs.rs/tracing-opentelemetry)
  - [opentelemetry-otlp (docs.rs)](https://docs.rs/opentelemetry-otlp)
  - [Library ID Context7 usado nesta pesquisa](/open-telemetry/opentelemetry-rust)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 usa o `tracing` como framework de instrumentação. O OpenTelemetry entra como **camada de exportação**: o `tracing-opentelemetry` converte spans do `tracing` em spans OTel, e o `opentelemetry-otlp` os envia via gRPC (porta 4317) ao OpenTelemetry Collector configurado no Docker Compose de observabilidade.

### Features de Cargo necessárias (versão 0.24)

```toml
[dependencies]
# OpenTelemetry core — versão ATUAL do projeto
opentelemetry       = "0.24"
opentelemetry_sdk   = { version = "0.24", features = ["rt-tokio"] }
opentelemetry-otlp  = { version = "0.17", features = ["grpc-tonic", "trace"] }

# Bridge tracing ↔ OTel
tracing-opentelemetry = "0.25"
```

**Para adicionar suporte a MÉTRICAS** (além de traces):
- Feature `trace` já está ativa em `opentelemetry-otlp 0.17`
- Para exportar métricas, adicione feature `metrics` se necessário (verifique docs.rs do `opentelemetry-otlp 0.17`)
- Em 0.17, o exporter OTLP suporta métricas via gRPC; não há feature separada necessária se usar `PeriodicReader` com o exporter OTLP

> **Nota:** as versões do ecossistema OTel Rust mudam frequentemente. A versão 0.24→0.27+/0.31+ trouxe alterações significativas na API de métricas. Este documento cobre **0.24** especificamente.

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

## 3. API de Métricas (Meter / Gauge / Histogram / Counter) — versão 0.24

A API de métricas em OpenTelemetry Rust 0.24 fornece instrumentos síncronos (Counter, Histogram, Gauge) e assíncronos (ObservableCounter, ObservableGauge, ObservableUpDownCounter) para observabilidade de pools, latência por método, e taxas de erro.

### 3.1 Obter um Meter

```rust
use opentelemetry::global;

// Opção 1: Via global::meter (recomendado após set_meter_provider)
let meter = global::meter("my-service-name");

// Opção 2: De um MeterProvider explícito
let provider = /* ... SdkMeterProvider ... */;
let meter = provider.meter("my-service-name");
```

### 3.2 ObservableGauge com Callback (para valores instantâneos)

Ideal para amostrar tamanho/idle/em-uso de pools no momento da exportação:

```rust
use opentelemetry::metrics::MeterProvider;
use opentelemetry::KeyValue;
use std::sync::atomic::{AtomicU64, Ordering};

// Variável compartilhada que rastreia o estado do pool
static POOL_SIZE_IN_USE: AtomicU64 = AtomicU64::new(0);
static POOL_SIZE_IDLE: AtomicU64 = AtomicU64::new(0);

fn setup_pool_metrics(meter: &opentelemetry::metrics::Meter) {
    // ObservableGauge para conexões em uso
    let _gauge_in_use = meter
        .u64_observable_gauge("db.pool.connections.in_use")
        .with_description("Número de conexões em uso no pool")
        .with_unit("{connections}")
        .with_callback(|observer| {
            let value = POOL_SIZE_IN_USE.load(Ordering::SeqCst);
            observer.observe(value, &[KeyValue::new("pool", "postgres")])
        })
        .build();

    // ObservableGauge para conexões idle
    let _gauge_idle = meter
        .u64_observable_gauge("db.pool.connections.idle")
        .with_description("Número de conexões idle no pool")
        .with_unit("{connections}")
        .with_callback(|observer| {
            let value = POOL_SIZE_IDLE.load(Ordering::SeqCst);
            observer.observe(value, &[KeyValue::new("pool", "postgres")])
        })
        .build();
}

// Na aplicação: atualizar os contadores
fn acquire_connection() {
    // ...
    POOL_SIZE_IN_USE.fetch_add(1, Ordering::SeqCst);
    POOL_SIZE_IDLE.fetch_sub(1, Ordering::SeqCst);
}

fn release_connection() {
    // ...
    POOL_SIZE_IDLE.fetch_add(1, Ordering::SeqCst);
    POOL_SIZE_IN_USE.fetch_sub(1, Ordering::SeqCst);
}
```

**Assinatura em 0.24:**
```
meter.u64_observable_gauge(name: &str)
    .with_description(desc: &str)
    .with_unit(unit: &str)
    .with_callback(|observer| { observer.observe(value, &[KeyValue...]) })
    .build()
```

### 3.3 Histogram para Latência (síncronos)

Para registrar distribuição de latência por método/endpoint:

```rust
use std::time::Instant;
use opentelemetry::KeyValue;

fn setup_latency_metrics(meter: &opentelemetry::metrics::Meter) {
    let histogram = meter
        .f64_histogram("http.request.duration")
        .with_description("Duração das requisições HTTP em ms")
        .with_unit("ms")
        .build();

    // Armazenar em Arc/thread-local para usar em handlers
    return histogram;
}

// No handler HTTP:
fn handle_request(histogram: &opentelemetry::metrics::Histogram<f64>, method: &str) {
    let start = Instant::now();
    
    // ... processar request ...
    
    let elapsed_ms = start.elapsed().as_secs_f64() * 1000.0;
    histogram.record(
        elapsed_ms,
        &[
            KeyValue::new("method", method.to_string()),
            KeyValue::new("status", "200")
        ]
    );
}
```

**Assinatura em 0.24:**
```
meter.f64_histogram(name: &str)      // ou u64_histogram para valores inteiros
    .with_description(desc: &str)
    .with_unit(unit: &str)
    .build()
    
histogram.record(value: f64, attributes: &[KeyValue])
```

### 3.4 Counter para Taxa/Erros (síncronos)

Para contar eventos discretos (requisições, erros):

```rust
use opentelemetry::KeyValue;

fn setup_error_metrics(meter: &opentelemetry::metrics::Meter) {
    let error_counter = meter
        .u64_counter("errors.total")
        .with_description("Total de erros por tipo")
        .with_unit("1")
        .build();

    return error_counter;
}

// Na lógica de erro:
fn log_error(counter: &opentelemetry::metrics::Counter<u64>, error_type: &str) {
    counter.add(
        1,
        &[
            KeyValue::new("error_type", error_type.to_string()),
            KeyValue::new("service", "my-service")
        ]
    );
}
```

**Assinatura em 0.24:**
```
meter.u64_counter(name: &str)
    .with_description(desc: &str)
    .with_unit(unit: &str)
    .build()
    
counter.add(value: u64, attributes: &[KeyValue])
```

**Dica:** Use slices `&[KeyValue::new(...)]` diretamente, não `Vec`; evita alocações.

### 3.5 MeterProvider com Exportador OTLP (gRPC)

Para exportar métricas ao OTel Collector via gRPC porta 4317:

```rust
use opentelemetry_sdk::metrics::MeterProvider;
use opentelemetry_sdk::metrics::PeriodicReader;
use opentelemetry_otlp::MetricExporter;  // Feature: opentelemetry-otlp 0.17 com "grpc-tonic"
use opentelemetry::global;

pub fn init_metrics(service_name: &str) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Configurar o exporter OTLP (gRPC para o Collector)
    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://otel-collector:4317".into());

    let exporter = MetricExporter::builder()
        .with_tonic()
        .with_endpoint(&otlp_endpoint)
        .build()?;

    // 2. Criar PeriodicReader (exporta a cada 60s por padrão)
    let reader = PeriodicReader::builder(exporter).build();

    // 3. Criar MeterProvider com o reader
    let provider = MeterProvider::builder()
        .with_reader(reader)
        .build();

    // 4. Registrar globalmente
    global::set_meter_provider(provider.clone());

    // 5. Usar
    let meter = global::meter(service_name);
    // ... setup_pool_metrics(&meter), setup_latency_metrics(&meter), etc ...

    Ok(())
}

pub fn shutdown_metrics() {
    // Flush pendente e shutdown
    global::shutdown_meter_provider();
}
```

**Notas importantes:**
- `PeriodicReader` exporta em intervalos (padrão 60s; personalizável via env `OTEL_METRIC_EXPORT_INTERVAL` em ms)
- Em 0.17, `MetricExporter` é importado de `opentelemetry_otlp`; feature `grpc-tonic` já está ativa
- O exporter OTLP 0.17 suporta métricas nativamente para gRPC; não há feature `metrics` separada necessária
- Chamar `shutdown_meter_provider()` no graceful shutdown (antes de encerrar o processo)

### 3.6 Diferenças entre 0.24 e Versões Posteriores (0.27+/0.31+)

**Em 0.24:**
- `ObservableGauge` (assíncrono) / `Gauge` — NÃO há `Gauge` síncrono em 0.24; gauges são sempre observáveis
- API de métricas é mais simples, menos flexível
- `PeriodicReader` com builder direto

**Em 0.27+/0.31+:**
- Há `Gauge` síncrono (diferente do 0.24)
- API expandida com suporte a views/aggregation temporality
- Pequenas mudanças em nomes de métodos

**Ao atualizar:** consulte context7 para a nova versão.

---

## 4. Histórico de Atualizações

- **2026-06-10:** API de Métricas adicionada (Meter / ObservableGauge / Histogram / Counter / MeterProvider+OTLP). Alinhamento de versão: projeto usa 0.24/0.17/0.25, não 0.31. Documentação anterior (2026-06-04) estava desatualizada. Registro de divergências e diferenças entre versões.
- **2026-06-04:** Documentação inicial do ecossistema OpenTelemetry para Rust (traces). Criada durante a reestruturação do plano de observabilidade. ⚠️ Versão citada (0.31) não corresponde ao projeto; consulte esta versão 2026-06-10 para o stack real.
