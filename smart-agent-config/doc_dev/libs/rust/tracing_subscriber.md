# Tracing Subscriber (tracing-subscriber)

- **Versão Recomendada:** 0.3.x
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-04
- **Propósito no Projeto:** Configura os layers de logging (JSON estruturado em produção, formato humano em dev), filtro de nível via `RUST_LOG`, e integração com OpenTelemetry para export de spans/traces.
- **Documentação Oficial:** [https://docs.rs/tracing-subscriber](https://docs.rs/tracing-subscriber)

---

## 1. Contexto e Uso no Projeto

O `tracing-subscriber` é o par indissociável do `tracing`. Enquanto o `tracing` define macros e spans, o `tracing-subscriber` controla **para onde** e **como** os eventos são formatados e exportados.

No Smart Core Assistant v2, o subscriber é configurado na crate `observability` com dois layers:
1. **Layer JSON** (stdout) → Docker captura e envia ao Loki via Promtail/Alloy.
2. **Layer OpenTelemetry** → exporta spans via OTLP para o Collector.

### Features de Cargo utilizadas

```toml
tracing-subscriber = { version = "0.3", features = ["json", "env-filter", "fmt", "registry"] }
```

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Inicialização com Registry (padrão composável)

Use `Registry` para compor layers de forma modular. Nunca use `fmt::init()` direto — ele não permite composição com OTel.

```rust
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

pub fn init_telemetry() {
    // Layer 1: JSON estruturado no stdout (Docker captura)
    let json_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true);

    // Filtro de nível via RUST_LOG (default: info)
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    Registry::default()
        .with(env_filter)
        .with(json_layer)
        // .with(otel_layer)  // Adicionado quando OTel está configurado
        .init();
}
```

### 2.2 Campos Estruturados Automáticos

O layer JSON serializa automaticamente todos os campos do span corrente. Ao usar `#[instrument]` com campos como `tenant_id` e `trace_id`, eles aparecem em **todo** evento dentro do span:

```json
{
  "timestamp": "2026-06-04T17:35:00Z",
  "level": "INFO",
  "target": "infrastructure_postgres::atendimentos",
  "fields": {
    "message": "Ticket criado",
    "tenant_id": "uuid-...",
    "trace_id": "abc-..."
  },
  "span": { "name": "create_ticket" }
}
```

### 2.3 Filtro Dinâmico por Módulo

Use `EnvFilter` para controlar verbosidade por crate/módulo sem recompilar:

```bash
# Apenas erros globais, mas debug para o worker
RUST_LOG="error,worker=debug" cargo run

# Info global, trace para a crate de postgres
RUST_LOG="info,infrastructure_postgres=trace" cargo run
```

### 2.4 Proibição

Nunca use `tracing_subscriber::fmt::init()` sozinho — ele não suporta composição com layers OpenTelemetry. Sempre use o padrão `Registry::default().with(...)`.

---

## 3. Histórico de Atualizações

- **2026-06-04:** Documentação inicial da biblioteca. Criada durante a reestruturação do plano de observabilidade (Plan Restructuring skill).
