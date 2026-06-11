# Documentação Auxiliar — Otimização de Pools, Concorrência e Observabilidade

> Gerado em: 2026-06-10
> Plano canônico: `.context/plans/otimizacao-pools-observabilidade.md`
> Plano completo: `.context/plans/otimizacao-pools-observabilidade/plano_completo_otimizacao-pools-observabilidade.md`
> Origem do plano-base: `smart-agent-config/doc_dev/planejamento/12-plano-otimizacao-pools-observabilidade.md`

## ⚠️ Nota sobre versões (leia primeiro)

As versões deste documento são as **fixadas no `server/Cargo.lock`** — não as
"recomendadas" genéricas. O Context7 só indexa as versões **novas** dessas libs
(redis 1.0+, opentelemetry 0.27+), então parte do que ele devolveu **não vale**
para as versões do projeto. As assinaturas abaixo foram **reconciliadas com o
código real** do repositório (`telemetry.rs`, `connection.rs`).

| Lib | Cargo.lock | Doc local | Fonte da verdade aqui |
|---|---|---|---|
| sqlx | **0.9.0** | ✅ atualizado | Context7 (bate com a versão) |
| redis | **0.25.5** | ✅ atualizado c/ ressalva | Código real + docs.rs 0.25 |
| opentelemetry | **0.24.0** | ✅ corrigido (era 0.31) | Código real (`telemetry.rs`) |
| opentelemetry_sdk | **0.24.1** | — | Código real |
| opentelemetry-otlp | **0.17.0** | — | Código real |
| tracing-opentelemetry | **0.25.0** | — | Código real |
| argon2 | **0.5.3** | ✅ (USAR LOCAL) | doc local |
| tokio | **1.38** | ✅ (USAR LOCAL) | doc local |
| tracing | **0.1.40** | ✅ (USAR LOCAL) | doc local |

---

## Libs Rust

### sqlx (0.9.0) — Pool de conexões
Fonte: Context7 `/websites/rs_sqlx` (versão bate com o projeto). Doc local atualizado:
`doc_dev/libs/rust/sqlx.md` (Última Verificação 2026-06-10).

**`PgPoolOptions` (builder) — assinaturas:**

| Método | Assinatura | Recebe |
|---|---|---|
| `max_connections` | `fn(self, u32) -> Self` | `u32` |
| `min_connections` | `fn(self, u32) -> Self` | `u32` (pool quente) |
| `acquire_timeout` | `fn(self, Duration) -> Self` | `Duration` |
| `idle_timeout` | `fn(self, impl Into<Option<Duration>>) -> Self` | `Duration`/`Option` |
| `max_lifetime` | `fn(self, impl Into<Option<Duration>>) -> Self` | `Duration`/`Option` |
| `connect` | `async fn(self, &str) -> Result<PgPool, Error>` | url |

**Introspecção em runtime (peça central de M1):**
- `PgPool::size(&self) -> u32` — total de conexões abertas (idle + em uso).
- `PgPool::num_idle(&self) -> usize` — conexões ociosas **agora**.
- `em_uso = size() - num_idle() as u32`.

**Exemplo (pool configurado):**
```rust
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

let pool = PgPoolOptions::new()
    .max_connections(cfg.max_connections)
    .min_connections(cfg.min_connections)   // pool quente
    .acquire_timeout(cfg.acquire_timeout)   // fail-fast (ex.: 3s)
    .idle_timeout(cfg.idle_timeout)         // ex.: 300s
    .max_lifetime(cfg.max_lifetime)         // ex.: 1800s
    .connect(&url).await?;
```

- A espera por `acquire` acontece dentro de `pool.begin()` (e de `acquire()`); se
  exceder `acquire_timeout`, retorna erro (sem mais a espera silenciosa de 30s do default).
- **Breaking changes 0.8→0.9 que afetem pool/options:** nenhuma relevante.

---

### redis (0.25.5)
Fonte: código real (`infrastructure_redis/src/connection.rs`) + Context7 (que só
indexa redis-rs ≥1.0, portanto **validar contra docs.rs/redis/0.25.5** os pontos
marcados ⚠️). Doc local: `doc_dev/libs/rust/redis.md` (Última Verificação 2026-06-10).

**Estado atual no código (base de partida):**
```rust
// connection.rs já existente
pub async fn criar_conexao_com_url(url: &str) -> Result<ConnectionManager, RedisError> {
    let client = Client::open(url.to_string())?;
    let manager = ConnectionManager::new(client).await?;   // multiplexado
    Ok(manager)
}
pub fn criar_cliente(url: &str) -> Result<Client, RedisError> {
    Ok(Client::open(url.to_string())?)                      // p/ conexões dedicadas
}
```
> O doc-comment do próprio `connection.rs` já diz: *"Para loops de consumo
> bloqueante (XREADGROUP com BLOCK) ou pub/sub, prefira uma conexão dedicada via
> `get_async_connection`/`get_async_pubsub`."* — ou seja, a correção C2 já tem o
> caminho aberto no código.

**C2 — conexão exclusiva para o loop do consumer (BLOCK):**
- O correto em 0.25.5 é o `Consumer::run` abrir **uma conexão dedicada single**:
  `let mut con = client.get_async_connection().await?;` (não-multiplexada → o
  `XREADGROUP ... BLOCK` não afeta mais ninguém).
- ⚠️ **Atenção:** o exemplo do plano-base usa `ConnectionManager::new(self.client.clone())`
  no `run()`. Isso é **subótimo** — `ConnectionManager` é multiplexado; o BLOCK
  ainda competiria. Preferir `client.get_async_connection()` (conexão crua dedicada).
- `Consumer` passa a guardar um `redis::Client` (não o `ConnectionManager` compartilhado).

**P4 — timeouts (corrigido após validação no fonte vendorizado):**
- ✅ **`ConnectionManagerConfig` NÃO existe em redis 0.25.5** (é redis ≥1.0). Nem
  `AsyncConnectionConfig` (Context7) nem `ConnectionManagerConfig` valem aqui.
- O único caminho em 0.25.5 é o construtor com timeouts embutidos
  `ConnectionManager::new_with_backoff_and_timeouts(client, exponent_base, factor,
  number_of_retries, response_timeout, connection_timeout)` (confirmado em
  `redis-0.25.5/.../aio/connection_manager.rs:147`).
```rust
// redis 0.25.5 — timeouts via construtor (não há struct de config)
let manager = ConnectionManager::new_with_backoff_and_timeouts(
    client,
    2,                         // exponent_base do backoff
    100,                       // factor (ms)
    6,                         // number_of_retries
    Duration::from_secs(2),    // response_timeout
    Duration::from_secs(2),    // connection_timeout
).await?;
```

**Streams — monitoramento e retry (M4 / C4):**
- `XPENDING <stream> <grupo>` (resumo): em 0.25.5 há o helper tipado
  `con.xpending(stream, grupo).await? -> StreamPendingReply`, cujo `.count()` é o
  total da PEL → gauge `smartcore_bus_pending` (não é tupla crua).
- **Retry/DLQ do C4 (corrigido):** `xautoclaim`/`xautoclaim_options` **NÃO existem
  em redis 0.25.5** (só `xclaim`/`xclaim_options` + `xpending*`). O caminho certo:
  `xpending_count(stream, grupo, start, end, count)` → `Vec<StreamPendingId>`, cujo
  campo **`times_delivered`** dá o contador de tentativas. Acima de N entregas →
  `xclaim` para mover ao consumidor de DLQ e `XADD` em `security:dlq` + `XACK` no original.
- `XACK`: `con.xack(stream, grupo, &[stream_id]).await?` — **só após sucesso** do handler (C4).

**E1 — DEL variádico:** `con.del(&chaves).await?` onde `chaves: &[String]` → uma
única chamada (`DEL k1 k2 k3...`), retorno `i64`/`usize` (nº removidas).

---

### opentelemetry — API de **Métricas** (0.24.0 / sdk 0.24.1 / otlp 0.17.0)
Fonte: **código real** (`observability/src/telemetry.rs`) — o Context7 devolveu a
API de métricas da 0.27+/1.x, que **não compila** em 0.24/0.17. Doc local corrigido:
`doc_dev/libs/rust/opentelemetry.md` (versão realinhada 0.24, Última Verificação 2026-06-10).

**Setup de traces HOJE (referência da API 0.17 — padrão a espelhar para métricas):**
```rust
let provider = opentelemetry_otlp::new_pipeline()
    .tracing()
    .with_exporter(opentelemetry_otlp::new_exporter().tonic().with_endpoint(otlp_endpoint))
    .with_trace_config(Config::default().with_resource(resource))
    .install_batch(opentelemetry_sdk::runtime::Tokio)?;
```

**Setup de MÉTRICAS na API 0.17 (o que o plano deve usar — NÃO `MetricExporter::builder`):**
```rust
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::runtime;

// retorna um SdkMeterProvider (API de pipeline da 0.17)
let meter_provider = opentelemetry_otlp::new_pipeline()
    .metrics(runtime::Tokio)
    .with_exporter(
        opentelemetry_otlp::new_exporter().tonic().with_endpoint(otlp_endpoint),
    )
    .with_resource(resource.clone())
    .with_period(std::time::Duration::from_secs(10))  // intervalo de export
    .build()?;

opentelemetry::global::set_meter_provider(meter_provider);
```
> ⚠️ **Cargo:** hoje `opentelemetry-otlp = { version = "0.17", features = ["grpc-tonic", "trace"] }`.
> Para métricas é preciso **adicionar a feature `metrics`** (e provavelmente
> `metrics` em `opentelemetry_sdk`). Confirmar nomes exatos das features em
> docs.rs/opentelemetry-otlp/0.17.0.

**Instrumentos (API 0.24 — confirmada como a do projeto):**
```rust
let meter = opentelemetry::global::meter("data_postgres");

// Gauge amostrado (pool size/idle/em-uso) — em 0.24 só há ObservableGauge (callback);
// NÃO existe Gauge síncrono (isso é 0.27+).
let g = meter
    .u64_observable_gauge("smartcore_pg_pool_size")
    .with_description("Conexões abertas no pool PG")
    .with_callback(|obs| {
        obs.observe(pool.size() as u64, &[KeyValue::new("pool", "postgres")]);
    })
    .init();   // ⚠️ em 0.24 é .init(); .build() é 0.27+

// Histograma de latência por método (M2/M3)
let h = meter.f64_histogram("smartcore_rpc_duration_ms").with_unit("ms").init();
h.record(dur_ms, &[KeyValue::new("method", metodo), KeyValue::new("error", erro)]);

// Counter de requisições/erros
let c = meter.u64_counter("smartcore_rpc_total").init();
c.add(1, &[KeyValue::new("method", metodo)]);
```
> **Diferenças 0.24 → 0.27+/0.31 (registrar p/ futuro upgrade):** em 0.24 o builder
> de instrumento finaliza com `.init()` e gauges instantâneos só via `ObservableGauge`
> (callback). Da 0.27+ surge `Gauge` síncrono, builders terminam em `.build()`, e o
> setup vira `MetricExporter::builder().with_tonic()` + `PeriodicReader::builder()`.
> O doc local recomendava 0.31 — **ignorar enquanto o Cargo.lock fixar 0.24**.

---

### Libs USAR LOCAL (reaproveitadas da central, sem Context7)

- **tokio 1.38** (`doc_dev/libs/rust/tokio.md`, 2026-05-31) — `spawn_blocking` (C1:
  Argon2 fora do runtime async), `tokio::sync::Semaphore::acquire_owned` (P3:
  admission control), `tokio::time::interval` (M1/M4: tasks de amostragem).
- **tracing 0.1.40** (`doc_dev/libs/rust/tracing.md`, 2026-05-31) — `tracing::info!/warn!`
  com `target:` dedicado (`metrics::pool`, `metrics::rpc`, `slowlog`) e campos
  estruturados (`traceparent`, `dur_ms`) para o link log→trace no Grafana.
- **argon2 0.5.3** (`doc_dev/libs/rust/argon2.md`, 2026-05-31) — `hash_password`/
  `verify_password` (CPU-bound, vão para `spawn_blocking` no C1).

---

## Serviços Externos

**Nenhum serviço de terceiros (API REST/SDK) no escopo.** A exportação de
telemetria é feita via **OTLP/gRPC (porta 4317)** para o OpenTelemetry Collector já
provisionado no compose, que roteia para a stack LGTM (Prometheus/Grafana/Loki/Tempo).
Prometheus e Grafana **consomem** as métricas/dashboards — o código Rust não fala HTTP
com eles diretamente. Logo, não há Grupo B a documentar via WebSearch/WebFetch.

> Dashboards (M5) e alertas são configuração de infra (PromQL/Grafana provisioning),
> tratados na fase de monitoramento; não dependem de doc de API externa.

---

## Notas Gerais / Gotchas

1. **Versão manda:** o Context7 puxa a API mais nova; aqui a verdade é o `Cargo.lock`.
   Qualquer snippet de redis ≥1.0 (`AsyncConnectionConfig`, `get_multiplexed_async_connection_with_config`)
   ou otel ≥0.27 (`MetricExporter::builder`, `.build()` em instrumentos) está **fora**.
2. **`opentelemetry-otlp` precisa da feature `metrics`** — sem ela o pipeline de
   métricas nem compila. É a primeira mudança de `Cargo.toml` da fase de monitoramento.
3. **C2 usa conexão dedicada (`get_async_connection`)**, não um novo `ConnectionManager`.
4. **Os 3 pontos ⚠️ já foram resolvidos no fonte vendorizado** (durante a etapa 4):
   redis 0.25.5 **não tem** `ConnectionManagerConfig` (usar `new_with_backoff_and_timeouts`)
   **nem** `xautoclaim` (usar `xpending_count.times_delivered` + `xclaim`); a feature
   `metrics` **existe** no `opentelemetry-otlp 0.17.0`. Detalhe na seção "Correções
   aplicadas" do plano completo.
5. **Sem novas libs**: todo o plano se resolve com o que já está no workspace
   (sqlx, tokio, redis, opentelemetry*, tracing, argon2) — apenas ativando features.
</content>
</invoke>
