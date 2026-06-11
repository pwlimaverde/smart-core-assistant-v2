---
status: in_progress
generated: 2026-06-10
slug: otimizacao-pools-observabilidade
scale: LARGE
artifacts:
  plano_completo: "./otimizacao-pools-observabilidade/plano_completo_otimizacao-pools-observabilidade.md"
  info_aux: "./otimizacao-pools-observabilidade/info_aux_otimizacao-pools-observabilidade.md"
phases:
  - id: "phase-p"
    name: "Planning — diagnóstico, alavancas de pool e desenho de telemetria"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — risco de concorrência e validação das APIs nas versões fixadas"
    prevc: "R"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-e"
    name: "Execution — F1 críticas, F2 pools, F3 monitoramento, F4 eficiência"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-v"
    name: "Validation — testes de carga/concorrência e DoD por sub-fase"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento dotcontext"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Otimização de Pools, Concorrência e Observabilidade de Gargalos

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/12-plano-otimizacao-pools-observabilidade.md`, com APIs
> validadas contra as **versões fixadas no `server/Cargo.lock`** (e no fonte vendorizado).

## Artefatos

- **Plano completo (verdade técnica):**
  [`./otimizacao-pools-observabilidade/plano_completo_otimizacao-pools-observabilidade.md`](./otimizacao-pools-observabilidade/plano_completo_otimizacao-pools-observabilidade.md)
- **Documentação auxiliar (libs nas versões fixadas):**
  [`./otimizacao-pools-observabilidade/info_aux_otimizacao-pools-observabilidade.md`](./otimizacao-pools-observabilidade/info_aux_otimizacao-pools-observabilidade.md)

## Objetivo

(a) Corrigir **gargalos e bugs de concorrência** já presentes no `data_postgres`/`transport`/
`infrastructure_redis`; (b) dar **controle fino dos pools** PostgreSQL dirigido por configuração
e por medição (nem conexões ociosas demais, nem fila por escassez); (c) instalar um **sistema de
monitoramento de gargalos por requisição** (latência por método, saturação de pool, lag de filas)
na stack LGTM já provisionada (OTel Collector → Prometheus/Grafana/Loki/Tempo).

**Escopo:** `apps/data_postgres`, `crates/transport`, `crates/infrastructure_postgres`,
`crates/infrastructure_redis`, `crates/observability` (e, por extensão, futuros `data_redis`/`worker`).

**Fora do escopo:** refator RF0–RF6 (este plano apenas instrumenta os pontos previstos por ele);
fan-out realtime; lógica de domínio do `worker`.

**Sinal de sucesso:** sob 20 logins concorrentes o `GetThread` paralelo mantém p95 < 100ms (C1);
publicação no bus < 10ms sob consumo ativo (C2); rajada de 200 requisições responde 100% (sucesso
ou erro `retryable` < 4s) sem espera silenciosa de 30s nem OOM no Postgres (F2); saturação simulada
(pool max=2 + carga) é apontada pelo dashboard **antes** do erro chegar ao cliente (F3);
`cargo clippy -D warnings` e `cargo fmt --check` limpos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — diagnóstico, alavancas de pool e desenho de telemetria | Backend Specialist | ✅ completed |
| **R** | Review — risco de concorrência e validação das APIs (versões fixadas) | Backend Specialist (+ Performance Optimizer) | ⬜ pending |
| **E** | Execution — F1 críticas, F2 pools, F3 monitoramento, F4 eficiência | Backend Specialist (+ Performance Optimizer, Devops) | ⬜ pending |
| **V** | Validation — testes de carga/concorrência e DoD por sub-fase | Test Writer | ⬜ pending |
| **C** | Confirmation — final-review e arquivamento dotcontext | Backend Specialist | ⬜ pending |

### Sub-fases de execução (fase E)

| Sub-fase | Itens | Foco |
|---|---|---|
| **F1 — Correções críticas** | C1 Argon2 em `spawn_blocking`; C2 conexão dedicada no consumer (BLOCK); C3 `REDIS_BUS_URL` separada; C4 ACK condicional + DLQ | Estancar travas de runtime e perda de evento |
| **F2 — Controle de pools** | P1 `PoolConfig::from_env`; P2 sizing (prod 12/4, dev 5/1); P3 admission control (semáforo); P4 timeouts Redis | Fail-fast + pool quente + fila mensurável |
| **F3 — Monitoramento** | M1 métricas de pool; M2 RED por método + slowlog; M3 espera de `acquire`; M4 lag de filas; M5 dashboard+alertas | Tornar o gargalo visível antes do incidente |
| **F4 — Eficiência** | E1 `DEL` variádico; E2 outbox em lote; E3 auditoria em lote | Reduzir round-trips no caminho quente |

## Decisões-chave (resumo — detalhes no plano completo)

1. **Argon2 → `spawn_blocking`** (C1): expor `hash_password_async`/`verify_password_async` na
   `infrastructure_postgres` para o caminho correto ser o fácil.
2. **Consumer com conexão dedicada** (C2): `Consumer` guarda um `redis::Client` e abre
   `client.get_async_connection()` no `run()` — o `XREADGROUP ... BLOCK` deixa de competir na
   conexão multiplexada compartilhada.
3. **Cache × Bus separados** (C3): `REDIS_BUS_URL` (6380, noeviction) distinta de `REDIS_URL`
   (6379, allkeys-lru); publicação/outbox no bus, tokens/cache no cache.
4. **ACK condicional + DLQ** (C4): `Consumer::run` só dá `XACK` em `Ok`; em `Err` o evento fica
   na PEL (reentrega periódica). DLQ por `xpending_count.times_delivered` + `xclaim` → `security:dlq`.
5. **Pool dirigido por config** (P1/P2): `PoolConfig` (max/min/acquire/idle/lifetime) via env;
   `acquire_timeout` curto (fail-fast) + `min_connections` (pool quente).
6. **Admission control** (P3): semáforo `MAX_INFLIGHT` na borda do `transport::Server` — a fila
   vira mensurável antes do pool.
7. **Métricas via OTel 0.24 / OTLP 0.17** (M1–M4): `ObservableGauge`+callback e `Histogram`/
   `Counter` com `.init()`; `MeterProvider` via `new_pipeline().metrics(runtime::Tokio)`; ativar a
   feature `metrics` no `opentelemetry-otlp`. **Sem** acoplar `observability → infrastructure_postgres`
   (o `&PgPool` entra por parâmetro).

## Correções aplicadas vs. plano base (doc 12)

Validação contra as versões **fixadas** corrigiu 3 pontos onde o Context7 (que só indexa redis ≥1.0
e otel ≥0.27) divergia da realidade do projeto:
- **redis 0.25.5 não tem `ConnectionManagerConfig`** → timeouts via `ConnectionManager::new_with_backoff_and_timeouts`.
- **redis 0.25.5 não tem `xautoclaim`** → DLQ via `xpending_count.times_delivered` + `xclaim`.
- **OTel métricas é 0.24** (`.init()`, `ObservableGauge`, `new_pipeline().metrics(...)`), **não** a
  API 0.27+ (`MetricExporter::builder`/`.build()`); a feature `metrics` do `opentelemetry-otlp 0.17` existe.

Além disso: C2 usa `get_async_connection()` (não `ConnectionManager` no loop); C3 corrige o
`.env.example` atual (que aponta `REDIS_URL` para 6380) direcionando cache→6379. Detalhe completo
na seção "Correções aplicadas" do plano completo.

## Verificação

`docker compose -f docker/compose/data.yml up -d` (Postgres + Redis 6379/6380 + OTel/LGTM) →
exportar envs novas (`SMARTCORE_PG_POOL_*`, `REDIS_BUS_URL`, `SMARTCORE_*_MAX_INFLIGHT`,
`SMARTCORE_SLOW_REQUEST_MS`, `SMARTCORE_POOL_METRICS_INTERVAL_S`) → `cargo build` do workspace →
testes de carga/concorrência (F1–F3 DoD) → `cargo clippy --all-targets -D warnings` +
`cargo fmt --check`. Branch a partir de `dev` (gitflow); commits sem auto-referência ao modelo;
comentários em pt-br.
</content>
