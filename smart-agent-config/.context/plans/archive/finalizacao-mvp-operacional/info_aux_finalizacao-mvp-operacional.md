# Documentação Auxiliar — Finalização MVP Operacional

> Gerado em: 2026-06-27
> Plano canônico: `.context/plans/finalizacao-mvp-operacional.md`
> Plano completo: `.context/plans/finalizacao-mvp-operacional/plano_completo_finalizacao-mvp-operacional.md`
> Origem: `doc_dev/planejamento/15-plano-finalizacao-em-andamento.md` (+ conversa)
>
> **Fontes:** libs marcadas **USAR LOCAL** vêm da central `doc_dev/libs/` (com data
> de verificação). Serviços externos e a API de Pub/Sub do redis 0.25 vieram de
> coleta WebSearch/WebFetch (subagentes haiku, 2026-06-27).

---

## Libs Rust (central local — USAR LOCAL)

### tonic (0.14.6) — `doc_dev/libs/rust/tonic.md` (✅ 2026-06-04)
Cobre tudo que WS-4 (realtime) e WS-5 (RBAC) precisam:

- **Server streaming (decisão D7):** RPC `rpc X(Req) returns (stream Msg)`; o
  `tonic-build` gera o associated type `type XStream: Stream<Item=Result<Msg,Status>>`.
- **Padrão recomendado:** canal `tokio::sync::mpsc` + `tokio_stream::wrappers::ReceiverStream`
  (precisa `tokio-stream`); alternativa `async_stream::stream!` + `Pin<Box<dyn Stream>>`.
- **Fan-out:** `tokio::sync::broadcast` + `BroadcastStream` para distribuir 1 evento
  a N clientes; tratar `Err(BroadcastStreamRecvError::Lagged)` → `Status::resource_exhausted`.
- **Interceptor JWT na abertura do stream:** o mesmo `Interceptor` das unárias roda
  **uma vez** antes de abrir o stream; injeta contexto via `request.extensions_mut()`.
  Status codes: `Status::unauthenticated` (401), `Status::permission_denied` (403).
- **gRPC-Web (port Web futuro):** `Server::builder().accept_http1(true).layer(GrpcWebLayer::new())`
  + `CorsLayer` (expor headers `grpc-status`/`grpc-message`). Server streaming É suportado
  em gRPC-Web; client/bidi não.

> **Correção de versão:** o doc local cita `tonic-web = "0.12"`; o workspace usa
> **`tonic-web = "0.14.1"`** (Cargo.toml). Usar 0.14.1.

### opentelemetry (0.24 / sdk 0.24 / otlp 0.17 / tracing-opentelemetry 0.25) — `doc_dev/libs/rust/opentelemetry.md` (✅ 2026-06-10)
Base do WS-0 (lado Rust — já implementado na crate `observability`, aqui é referência):

- `init_telemetry`: `SpanExporter::builder().with_tonic().with_endpoint(OTEL_EXPORTER_OTLP_ENDPOINT)`
  → `SdkTracerProvider` com `with_batch_exporter(..., runtime::Tokio)` → `OpenTelemetryLayer`
  + `fmt::layer().json()` + `EnvFilter`.
- **Endpoint padrão:** `http://otel-collector:4317` (gRPC). Nunca exportar direto a Tempo —
  sempre via Collector.
- **Propagação W3C:** `global::set_text_map_propagator(TraceContextPropagator::new())`;
  injetar/extrair `traceparent` (já há `observability::{injetar_contexto_atual, extrair_contexto}`).
- **Métricas 0.24:** gauges são sempre `*_observable_gauge(...).with_callback(...)`; há
  `f64_histogram`/`u64_counter`; export via `MetricExporter` + `PeriodicReader` (60s).
  Feature `pool-metrics` já existe no projeto.

> ⚠️ **Atenção:** o subagente de pesquisa LGTM sugeriu `opentelemetry 0.22` e a API
> antiga `new_pipeline()` — **ignorar**. A verdade é a 0.24 do doc local acima.

### redis (0.25.0) — `doc_dev/libs/rust/redis.md` (✅ 2026-06-10)
USAR LOCAL para Streams/lock/DLQ (WS-1 idempotência, WS-2 debounce):

- **Streams + Consumer Groups:** `xread_options(...).block(...).group(g,c)` em **conexão
  dedicada** (`get_async_connection`, não multiplexada — BLOCK não multiplexa) + `xack`.
- **Debounce lock (WS-2.3):** `SET tenant:<uuid>:lock:debounce:<contato> 1 NX EX <ttl>`.
- **DLQ / retry:** `xpending`/`xpending_count` (`times_delivered`) + `xclaim_options`
  (não há `xautoclaim` em 0.25).
- **Timeouts do ConnectionManager:** `new_with_backoff_and_timeouts(...)` (não existe
  `ConnectionManagerConfig` em 0.25).
- **Namespacing por tenant obrigatório:** `tenant:<uuid>:<recurso>:<chave>`.

> **Lacuna coberta abaixo (§ Serviços/API externa):** o doc local **não** traz a API
> de **Pub/Sub** do redis 0.25, necessária ao fan-out multi-réplica do WS-4.

### Demais libs USAR LOCAL (sem recorte novo)
- **axum** — `doc_dev/libs/rust/axum.md` — `webhook_ingress` já usa axum 0.8 (rotas `{param}`).
- **secrecy (0.10.3)** — `doc_dev/libs/rust/secrecy.md` — `SecretString` para tokens/keys (WS-1, WS-7).
- **sqlx (0.9)** / **jsonwebtoken (9.3)** / **argon2** — auth/persistência já implementados.
- **tracing (0.1.40)** / **tracing-subscriber (0.3.18)** — `tenant_span!` + logs JSON.

---

## Libs Flutter (central local — USAR LOCAL)
Para WS-6 (telas operacionais) e WS-7 (telas admin):

- **grpc (dart)** — `doc_dev/libs/flutter/grpc.md` — `GrpcWebClientChannel` no Web;
  `ResponseStream` para consumir server streaming (chat realtime).
- **flutter_bloc** — `doc_dev/libs/flutter/flutter_bloc.md` — stores reativos do stream.
- **get_it** — `doc_dev/libs/flutter/get_it.md` — DI (já há `get_it_module`).
- **go_router** — `doc_dev/libs/flutter/go_router.md` — navegação/guarda de sessão.
- **flutter_secure_storage** — refresh token (já usado no `login_module`).
- **Kanban (drag-and-drop):** **sem doc local** — `appflowy_board` (ou equivalente) será
  avaliado no WS-6; criar doc local se adotado.

---

## Serviços Externos

### Grafana LGTM (OTel Collector + Loki + Tempo + Prometheus + Grafana)
> Coleta 2026-06-27 (subagente). **As tags de imagem abaixo são referência — confirmar
> a tag estável vigente no momento do deploy** (o subagente pode ter sugerido versões
> não verificadas). A topologia e as configs são o material confiável.

**Topologia:** serviços Rust → OTLP gRPC `:4317` → **OTel Collector** → exporters →
Tempo (traces) / Loki (logs) / Prometheus (métricas) → **Grafana** (datasources +
correlação trace↔logs por `trace_id`). Acesso externo via **Caddy** num subdomínio.

**Decisão de fase (DEV vs PROD):** começar com a imagem all-in-one
`grafana/otel-lgtm` (valida o pipeline em minutos); migrar para **stack separada**
(5 serviços) para produção, com retenção e volumes próprios.

#### `otel-collector-config.yaml` (mínimo funcional)
```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }
processors:
  memory_limiter: { check_interval: 1s, limit_mib: 512 }
  batch: { send_batch_size: 512, timeout: 5s }
exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls: { insecure: true }
  otlphttp/loki:
    endpoint: http://loki:3100/otlp     # Loki recebe OTLP nativo (3.x)
    tls: { insecure: true }
  prometheusremotewrite:
    endpoint: http://prometheus:9090/api/v1/write
service:
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlp/tempo] }
    logs:    { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp/loki] }
    metrics: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [prometheusremotewrite] }
```

#### Grafana — provisionamento de datasources + correlação trace↔logs
```yaml
# provisioning/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    uid: prometheus-uid
  - name: Loki
    type: loki
    url: http://loki:3100
    uid: loki-uid
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: 'trace_id[\s]*[:=][\s]*([\w\-]+)'
          url: '$${__value.raw}'
          datasourceUid: tempo-uid     # log → trace
  - name: Tempo
    type: tempo
    url: http://tempo:3200
    uid: tempo-uid
    jsonData:
      tracesToLogs: { datasourceUid: loki-uid, filterByTraceID: true }  # trace → log
```

#### Gotchas / breaking changes
- **Loki 3.x:** `allow_structured_metadata: true` é **obrigatório**; Loki recebe OTLP
  nativo em `/otlp` (dispensa Promtail).
- **Promtail/Grafana Agent depreciados** → usar Grafana Alloy se precisar de coletor de
  host (no nosso caso o Collector OTLP já basta).
- **Prometheus:** flags `--storage.tsdb.retention.time=30d` e `--web.enable-lifecycle`.
- **Tempo:** `storage.trace.backend: local` para dev; `block_retention` controla retenção.
- **memory_limiter** no Collector é crítico para não dar OOM.
- Configurar prod com `GF_SECURITY_ADMIN_PASSWORD` (não deixar admin/admin) e Caddy na frente.

#### Caddy (subdomínio Grafana)
```caddy
grafana.smartcoreassistant.com.br {
    reverse_proxy localhost:3000 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
```

### Evolution Go API (WhatsApp)
- **Já implementado** em `server/crates/infrastructure_evolution` (cliente HTTP + provider)
  e exposto por `server/apps/data_whatsapp` (12 rotas RPC: send text/media, instâncias, etc.).
- **Fonte da verdade = código existente.** WS-1 (validar token de instância no webhook) e
  WS-3 (outbound) reusam esse cliente; não há endpoint novo a documentar.

---

## API externa coberta: Redis Pub/Sub assíncrono 0.25.0 (para o WS-4)
> Assinaturas confirmadas em docs.rs/redis/0.25.0 (subagente, 2026-06-27).
> **Não usar a API da redis-rs ≥1.0** (`get_async_pubsub()`/`split()`), que é diferente.

**Assinaturas válidas em 0.25:**
```rust
// Subscriber (conexão DEDICADA, bloqueante — não multiplexável)
let con = client.get_async_connection().await?;     // dedicada
let mut pubsub = con.into_pubsub();                  // redis::aio::PubSub
pubsub.subscribe("tenant:<uuid>:events").await?;     // ou psubscribe(pattern)
let mut stream = pubsub.on_message();                // impl Stream<Item = redis::Msg>
while let Some(msg) = stream.next().await {           // futures::StreamExt
    let payload: String = msg.get_payload()?;
    let canal = msg.get_channel_name();
}

// Publisher (MultiplexedConnection/ConnectionManager — clonável)
let mut con = client.get_multiplexed_async_connection().await?;
let n: u32 = con.publish("tenant:<uuid>:events", payload).await?; // nº de subscribers
```

**Padrão recomendado p/ WS-4 (multi-réplica):** cada réplica do `runtime_api` mantém
**um subscriber** por canal de tenant numa task `tokio::spawn` dedicada; o subscriber
faz fan-out **interno** via `tokio::sync::broadcast` para os N streams gRPC abertos
daquele tenant naquela réplica. O publisher (worker/runtime) usa `publish` numa
`MultiplexedConnection`. Tratar `broadcast` lagged → encerrar stream com
`Status::resource_exhausted`. **Nunca** usar a mesma conexão para subscribe e publish.

> Em redis-rs ≥1.0 migrar para `get_async_pubsub()` + `split()` (sink/stream). Registrar
> no doc local `redis.md` quando o WS-4 for implementado (seção "Pub/Sub 0.25").

---

## Notas Gerais
- **SOLID (pedido explícito do usuário, transversal a todos os WS):** manter o padrão
  **Ports & Adapters** já adotado nos `data_*` (plano 14). Casos de uso na `application`
  dependem de **traits (ports)**, não de implementações concretas (DIP); um adapter por
  fronteira externa (Evolution, Redis, Postgres) — SRP/ISP; novos provedores entram pelo
  `ProviderRegistry`/novas impls sem alterar os casos de uso (OCP); `domain_*` sem I/O.
- **Observabilidade/auditoria é DoD de cada etapa** (ver §1 do plano completo): span com
  `tenant_id`/`trace_id`, `traceparent` propagado, evento `AuditLogger` por ação, sem
  segredos (`secrecy`).
- **Versões de imagem do LGTM** são as únicas informações a re-confirmar no deploy; todo
  o resto (libs Rust/Flutter) está fixado nos manifests e coberto pela central local.
