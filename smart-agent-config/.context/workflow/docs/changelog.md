# Changelog - Smart Core Assistant v2

Histórico de alterações do projeto com base no ciclo PREVC.

## [2026-06-07] - DevOps Completo: CI/CD, Ambientes e Provisionamento do Servidor

> Ciclo PREVC `cicd-devops` concluído. Final-review (Opus):
> `final-review-cicd-devops.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Workflows GitHub Actions (`.github/workflows/`):** `ci.yml` (lint, testes, `cargo sqlx prepare --check` offline, detecção Flutter), `deploy-dev.yml` (build + deploy automático em push `dev` no self-hosted runner), `deploy-prod.yml` (build + deploy com approval manual, rollback via symlink/`PREV_RELEASE`, backup de banco, GitHub Release, job Flutter Windows) e `pr-to-main.yml` (PR automático `dev→main` após tag).
- **Provisionamento do servidor (`infra/server-setup.sh`):** setup completo do Hostinger KVM2 (Ubuntu 22.04) — usuários `smartcore`/`gh-runner`, Caddy com TLS automático e h2c para gRPC, journald, ufw (só 22/80/443), sudoers restrito, `protoc`/`flatc`, postgresql-client.
- **Systemd (`infra/systemd/`):** 14 service units (7 por ambiente dev/prod) + 2 targets, com `User=smartcore`, `NoNewPrivileges`, `PrivateTmp`, `EnvironmentFile` por ambiente e ordem de dependências (`runtime_api` depende dos demais).
- **Observabilidade (`docker/`):** stack LGTM (Grafana, Loki, Tempo, Prometheus, OTEL Collector, Promtail) com `mem_limit` por container, rede externa `smartcore_v2_network` e datasources do Grafana pré-provisionados (correlação log↔trace e service map por UID).
- **Backup cifrado dos `.env` (`infra/backup-envs.ps1`):** AES-256-CBC / PBKDF2 / 100k iterações, com manuseio de senha via `SecureString` e variável de ambiente (sem expor segredo na lista de processos).
- **Documentação de deploy:** `README.md` (raiz) com instruções de CI/CD e `.env.example` com todas as variáveis de deploy (incluindo Grafana).

### Corrigido (follow-up do final-review)
- **Datasources do Grafana (`docker/observability/provisioning/datasources/ds.yml`):** `datasourceUid` referenciava o nome em vez do UID — adicionados `uid:` explícitos e corrigidas as correlações derivedField/serviceMap.
- **Smoke tests (`deploy-dev.yml`/`deploy-prod.yml`):** ampliados de 4 para os 7 serviços, alinhando com o critério V.1 ("todos os serviços active").
- **`backup-envs.ps1`:** removido código morto (`$PasswordBytes`) e endurecido o manuseio de senha.

### Pendências remanescentes (trabalho futuro)
- Separar `REDIS_BUS_URL` antes de F3 (registrado no plano).
- `docker/compose/observability.yml`: trocar o default fraco `GRAFANA_ADMIN_PASSWORD:-admin_secret_pass` por variável obrigatória em produção.
- `infra/.env.deploy.example` está coberto pelo `.gitignore` (`.env.*`) — versionar o template na feature de deploy-data/tunnel.

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

### Corrigido (follow-up das pendências do final-review)
- **Runtime de transporte resiliente (`transport/src/runtime.rs`):** `MuxClient` reescrito com keepalive (PING→PONG nas flags do `framing`), detecção de conexão morta e reconexão automática com **backoff exponencial + jitter** (teto de tentativas). O `Server` responde PING com PONG sem passar pelos handlers.
- **Ciclo `observability→infrastructure_postgres` removido em produção:** feature `postgres-audit` saiu do `default` (`default = []`); o build padrão publica auditoria só via Redis Streams. Dev-dependency auto-referente reativa a feature nos testes (retrocompatibilidade com banco).
- **`traceparent` W3C ponta-a-ponta no barramento:** `TenantEnvelope`/`EventoBruto` ganham o campo `traceparent` (serde `default`, retrocompatível); publicado e lido no Redis Streams. Propagado em `messaging_gateway` (RPC→bus), `worker` (bus→RPC) e auditoria (`audit.rs`, `data_postgres`).
- **`traceparent` no relay do outbox:** `0011_outbox` ganha a coluna `traceparent`; o `handler_persist_message` persiste o trace da requisição na mesma transação ACID e o `OutboxRelay` o repropaga no barramento (persistência → relay → bus).
- **Stubs eliminados (handlers reais por contrato):**
  - `data_postgres`: `GetThread` carrega a thread de mensagens (RLS); novos RPCs `ListAtendimentos` (snapshot por status, RLS) e `CreateTenant` (escrita admin).
  - `runtime_api`: `StreamAtendimentos` deixa de ser mock e delega ao `data_postgres` (`ListAtendimentos`) via RPC.
  - `control_plane`: `RegisterTenant` deixa de gerar UUID fake e delega ao `data_postgres` (`CreateTenant`) via RPC.

### Pendências remanescentes (trabalho futuro)
- **Streaming multi-frame de verdade** (`runtime_api::StreamAtendimentos`): hoje é snapshot req/reply. Server-streaming real exige um primitivo de Handler com múltiplos frames no `transport` (as flags `STREAM_ITEM`/`STREAM_END` já existem no framing).
- **Validação em banco real:** os handlers novos (`GetThread`/`ListAtendimentos`/`CreateTenant`) passam `fmt`/`clippy`/build offline; a semântica RLS/admin precisa ser exercitada com o túnel SSH + DB (`cargo test`).

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
