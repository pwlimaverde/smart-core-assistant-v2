# Changelog - Smart Core Assistant v2

Histórico de alterações do projeto com base no ciclo PREVC.

## [2026-06-05] - Refator de Arquitetura Modular por Contrato (RF0–RF6)

> Ciclo PREVC `refator-arquitetura-modular` concluído. Final-review (Opus):
> `final-review-refator-arquitetura-modular.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Crate `contracts` (`server/crates/contracts`):** Fonte de schema canônica em **`.proto`** (`schemas/*.proto`) gerando gRPC/Protobuf via `tonic_prost_build` e FlatBuffers via `flatc --proto`→`.fbs`→`flatc --rust` (`build.rs`). `protoc`/`flatc` vendorizados em `server/bin/`. Decisão de manchete: o `flatc` **não** transpila `.fbs`→`.proto`, então o IDL autorado virou `.proto` — FlatBuffers permanece o codec de fio padrão (`payload:[ubyte]` preservado).
- **Crate `transport` (`server/crates/transport`):** Runtime de transporte sobre UDS — `framing.rs` (len/flags/corr_id), `runtime.rs` (`MuxClient` corr_id→oneshot, timeout, backpressure), `codec.rs` (codec FB/gRPC comutável por env) e `bus.rs` (Redis Streams `STREAM_EVENTOS`/`STREAM_SEGURANCA`, consumer group, XACK, reprocessamento PEL) absorvendo o antigo `event_bus.rs` do `infrastructure_redis`.
- **`ErrorEnvelope` no `error_core` (`envelope_bridge.rs`):** Ponte serializável entre `AppError` e o envelope de contrato; 6 categorias novas em `code.rs` (apêndice, disciplina de não-remover preservada).
- **Rewire de auditoria p/ Streams (`observability/src/audit.rs`):** Auditoria publica em `STREAM_SEGURANCA` via `transport::bus`; consumidor de consolidação no app `data_postgres`.
- **Apps por contrato (`server/apps/*`):** `data_postgres` (RPC 3 protocolos + consumer de auditoria + `OutboxRelay` via PgListener), `data_redis`, `data_storage`, `runtime_api`, `messaging_gateway`, `worker`, `control_plane` (topologia ponta-a-ponta; realtime/WS e `control_plane` como stubs declarados).
- **Crate `application` (`auth/login.rs`):** Caso de uso de login falando por RPC (`transport::conectar_cliente`), sem acesso direto a repositório.
- **Migration `0011_outbox.sql`:** Tabela `outbox` + trigger `pg_notify('outbox_new')` para o relay outbox→bus.
- **Docker:** serviço `redis-bus` com `--maxmemory-policy noeviction` (separado do `allkeys-lru` que evicta Streams).

### Pendências (trabalho futuro, fora do escopo do ciclo)
- Runtime de transporte sem keepalive/reconexão com backoff (read_loop encerra na queda).
- Feature `postgres-audit` ainda `default` em `observability` (o ciclo `observability→postgres` não foi removido à risca).
- `traceparent` não trafega no evento do bus (salto bus→RPC inicia novo trace).
- Stubs por completar: `control_plane`, realtime/WS de `runtime_api`, handlers mock de `data_postgres`.

## [2026-06-04] - Tratamento de Erros (`error_core`)

### Adicionado
- **Crate `error_core` (`server/crates/error_core`):** Fundação transversal de tratamento de erros rastreável do workspace. Reexporta `ErrorCode`, `ErrorCategory`, `AppError`, `Severity`, `ErrorReport`, `ErrorContext` e `registrar()`.
- **Taxonomia estável `ErrorCode` (`code.rs`):** 17 códigos cobrindo auth/storage/db/cache/validação/conflito/internal, serializáveis em `SCREAMING_SNAKE_CASE` (serde) com `Display` manual (sem `serde_json` no hot path de log) e `category()` para agrupamento em métricas.
- **Agregador `AppError` (`error.rs`):** Enum com payload `String` (erros de infra ainda não existem no workspace) expondo `code()`, `severity()` (composta por variante + conteúdo), `retryable()` e `public_message()` — esta nunca vaza PII, stack trace ou detalhe interno.
- **Registro rastreável (`report.rs`):** `ErrorReport` + `registrar()` emitindo log estruturado via `tracing` (`error!`/`warn!` por severidade) com correlação `trace_id`/`tenant_id`, integrado à crate `observability`.
- **Mapeamento gRPC (`transport.rs`, feature `grpc`):** `to_status()` converte `AppError` em `tonic::Status`; `AuthInsufficientScope → PermissionDenied`, demais auth → `Unauthenticated`, alinhado ao doc 09. `tonic` carregado apenas sob a feature opcional.
- **`tonic = "0.14.6"` no workspace:** Adicionada a `[workspace.dependencies]` e `error_core` registrada em `[workspace.members]` de `server/Cargo.toml`.
- **Testes de integração:** 13 testes (`tests/integration_tests.rs` + submódulos `code`/`error`/`report`/`transport`/`observability`) cobrindo mapeamento de códigos, severidade, retryable, mensagens públicas, transporte gRPC (feature-gated) e integração real com `tracing_subscriber` (correlação e não-vazamento de PII).

## [2026-06-04] - Observabilidade e Auditoria

### Adicionado
- **Migration `0010_audit_log.sql`:** Nova migração no PostgreSQL com tabela `audit_log`, índices focados em desempenho para buscas de tenant/globais, e suporte à isolamento de dados com Row-Level Security (RLS).
- **Módulo `auditoria` no `infrastructure_postgres`:** Repositório Rust (`audit_log.rs`) contendo inserção e busca estruturada de logs. Mapeamentos do SQLx implementados usando formato dinâmico (sem macros `!`) para compatibilidade com compilações locais/CI offline.
- **Crate `observability`:** Nova crate Rust transversal para inicializar o OpenTelemetry gRPC e o Tracing JSON no stdout.
- **`AuditLogger` assíncrono:** Logger fire-and-forget com dual pool (Conventional tenant pool + Admin pool com BYPASSRLS) para gravação concorrente de logs de inquilinos e de superusuários do sistema.
- **Helpers de Propagação:** Helpers utilitários no Rust para injetar e extrair o TraceContext W3C a partir de HashMaps genéricos, preparados para Redis Streams e payloads JSON.
- **Stack LGTM Docker Compose:** Configurações centralizadas em `docker/compose/observability.yml` e arquivos em `docker/observability/` (OTel Collector, Loki, Tempo, Prometheus, Grafana, Promtail) com limites rígidos de memória.
- **Provisionamento de Dashboards:** Configuração as-code para provisionamento automático de datasources no Grafana e criação do dashboard "Smart Core v2 - Auditoria e Segurança" (`audit_log.json`).
