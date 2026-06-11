# Final Review — otimizacao-pools-observabilidade
Data: 2026-06-11 · Modelo: Opus · Diff: 87ac532...HEAD (commits 328aa81, 3e5e457) — escopo `server/` + `.env.example`

## Veredito: CORRIGIDO (auditoria) · INCOMPLETO (ciclo — fase V pendente, não arquivar)

> A auditoria do código implementado passou após correções (build/clippy/fmt limpos,
> invariante de arquitetura restaurada). O **ciclo PREVC não terminou**: a fase V
> (testes de carga/DoD) não foi executada e M5 (dashboard/alertas) está pendente —
> portanto o plano **não** foi arquivado.
>
> **Contradição de tracking registrada:** o harness (`prevc.json`) estava em E, mas o
> frontmatter do plano tinha R/E `pending`. A implementação real corresponde a R+E
> concluídas; o tracking foi atualizado para refletir a realidade (R/E `completed`,
> V `pending`).

## 1. Plano vs. Implementado

| Item | Status | Observação |
|---|---|---|
| **C1** Argon2 `spawn_blocking` | ✅ | `hash_password_async`/`verify_password_async` em `auth/password.rs`; usados em `handler_create_superuser` e `handler_verify_credentials`; exportados no `lib.rs`. |
| **C2** Consumer conexão dedicada | ✅ | `Consumer` guarda `redis::Client`; `run()`/`run_batch()` abrem `get_async_connection()`. `main.rs` passa `bus_client`. |
| **C3** `REDIS_BUS_URL` separada | ✅ | `redis_url` (6379 cache) vs `redis_bus_url` (6380 bus) com fallback; handlers/outbox publicam no `bus_conn`. `.env.example` corrigido (cache→6379, bus→6380). |
| **C4** ACK condicional + DLQ | ✅ | Handler devolve `Result`; XACK só em `Ok`; `reprocessar_pendentes_uma_vez(_batch)` periódico (60s); `varrer_dlq_pendentes` via `xpending_count.times_delivered > MAX_ENTREGAS(5)` + `xclaim` + XADD `security:dlq` + XACK. |
| **P1** `PoolConfig`+`criar_pool_config` | ✅ | Struct com 5 campos, `from_env("SMARTCORE_PG")`, `criar_pool` legada delega, log da config efetiva. |
| **P2** Envs de sizing | ✅ | `SMARTCORE_PG_POOL_MAX/MIN`, `ACQUIRE_TIMEOUT_MS`, `IDLE_TIMEOUT_S`, `MAX_LIFETIME_S` no `.env.example` (defaults dev 5/1). |
| **P3** Semáforo `MAX_INFLIGHT` | ✅ | `Server.semaforo`, `from_env` lê `SMARTCORE_<SVC>_MAX_INFLIGHT` (default 64), `acquire_owned()` antes do spawn por frame. |
| **P4** Timeouts Redis | ✅ | `criar_conexao_com_timeouts` via `new_with_backoff_and_timeouts` (6 args), env `SMARTCORE_REDIS_RESPONSE_TIMEOUT_MS` (2000). Só `data_postgres` migrou; `worker`/`data_storage` fora do escopo do plano. |
| **M1** Métricas de pool | ⚠️→✅ | `pool_metrics::monitorar_pool` com 3 `ObservableGauge` + `.init()` e log `target:"metrics::pool"`. **Estava gated por `postgres-audit`** (violava invariante de arquitetura) — **corrigido** para feature `pool-metrics` (só `sqlx`). |
| **M2** RED + slowlog | ✅ | Histograma `smartcore_rpc_duration_ms{method,error}` + counter `smartcore_rpc_total`; slowlog `target:"slowlog"` com `dur_ms`/`tenant_id`/`traceparent`, env `SMARTCORE_SLOW_REQUEST_MS`(500). Instrumentos criados por conexão (ver §3). |
| **M3** Acquire em `run_in_tenant_transaction` | ⚠️ | `warn`(>100ms)+`trace` em `target:"metrics::pg_acquire"`. Sem histograma `smartcore_pg_acquire_ms` — mínimo previsto pelo próprio plano para não acoplar `infrastructure_postgres → observability`. |
| **M4** Lag de filas | ✅ | Gauges `smartcore_bus_pending` (XPENDING→`StreamPendingReply.count`) e `smartcore_outbox_backlog` (`SELECT count(*) ... published_at IS NULL`) via amostra→`AtomicU64`→`observe`, task 30s. |
| **M5** Dashboard/alertas Grafana | ❌ pendente | Provisioning de infra (PromQL/Grafana), sem código Rust. Não corrigido aqui. |
| **MeterProvider** | ✅ | `init_metrics` via `new_pipeline().metrics(runtime::Tokio)...build()`, `.with_period(10s)`, feature `metrics` nas 3 crates OTel. |
| **E1** `revogar_familia` DEL variádico | ✅ | `del(&chaves)` num round-trip. |
| **E2** Outbox lote | ✅ | Acumula `publicados` + `UPDATE ... WHERE id = ANY($1)`. |
| **E3** Auditoria em lote | ✅ | `processar_eventos_auditoria_lote` agrupa por tenant (1 tx/tenant) + 1 tx global. |
| **Envs** | ✅ | 10 variáveis novas presentes; `REDIS_URL` corrigida p/ 6379; `server/.env.example` com `REDIS_BUS_URL`. |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| `observability/Cargo.toml:37` | **Violação de arquitetura**: M1 gated por `postgres-audit`, que ativa `dep:infrastructure_postgres`. Como `data_postgres` ligava `features=["postgres-audit"]`, a aresta de produção `observability → infrastructure_postgres` voltava (ciclo registrado em memória do projeto). | Feature nova `pool-metrics = ["dep:sqlx"]` (só `sqlx`, sem `infrastructure_postgres`). |
| `observability/src/lib.rs:13,18` | `pool_metrics`/`monitorar_pool` gated por `postgres-audit`. | Gate trocado para `feature = "pool-metrics"`. |
| `apps/data_postgres/Cargo.toml:20` | App ativava `observability` com `postgres-audit`. | Trocado para `features = ["pool-metrics"]`. Verificado via `cargo tree -e no-dev -i infrastructure_postgres`: aresta de produção eliminada. |
| `apps/data_postgres/src/main.rs:387` | Trailing whitespace que travava `rustfmt`. | Removido. |
| Workspace (12 arquivos) | Ciclo não rodou `cargo fmt` (`fmt --check` falhava). | `cargo fmt` aplicado; agora limpo. |

## 3. Decisões Autônomas (revisar depois)

- **Feature `pool-metrics` separada de `postgres-audit`** — era a forma exigida pelo plano (M1 recebe `&PgPool` por parâmetro, sem importar `infrastructure_postgres`); a implementação tinha unido as duas na mesma feature. `postgres-audit` permanece como dev-dependency auto-referente para testes de `audit.rs`. Única aresta remanescente `observability → infrastructure_postgres` é via dev-dependencies.
- **M2/instrumentos por conexão** (`runtime.rs:466`): `meter`/`h_dur`/`c_total` criados dentro de `handle_connection`, não em lazy estático. Funcional (OTel deduplica por nome) e clippy-limpo; mantido para evitar regressão. Recomendação futura: `OnceLock`/`LazyLock`.
- **M3 sem histograma**: mantido o mínimo (log com `target` dedicado) definido pelo próprio plano para não criar a aresta/ciclo `infrastructure_postgres → observability`.

## 4. Revalidação

| Gate | Resultado |
|---|---|
| `cargo fmt --check` | ✅ limpo (após `cargo fmt`) |
| `cargo clippy --workspace --all-targets -- -D warnings` | ✅ limpo (SQLX_OFFLINE) |
| `cargo build --workspace` | ✅ ok |
| `cargo tree -e no-dev -i infrastructure_postgres` (data_postgres) | ✅ invariante confirmada — `observability(default,pool-metrics)` não traz `infrastructure_postgres` em produção |
| `cargo test --workspace --no-run` | ✅ todos os testes compilam |
| `cargo test -p transport --lib` | ✅ 18/18 passaram |
| Testes de integração (data_postgres, infrastructure_*) | N/A — exigem túnel SSH + DB remoto (reset de schema); não executados nesta auditoria |

## 5. Pendências (escopo extra ou fora do plano)

- **M5 (dashboard "Saúde de Dados" + 5 alertas Grafana)**: pendente — provisioning de infra, sem código Rust. Necessário para fechar F3.
- **Fase V do plano**: DoDs de carga não executados — 20 logins concorrentes (C1), latência de publicação sob consumo (C2), rajada de 200 req (F2), saturação simulada pool max=2 (F3). Necessários para fechar o ciclo.
- **Topologia de portas no `infra/.env.deploy`** (não versionado): define `REDIS_PORT=6380` e não define `REDIS_BUS_PORT` — no remoto, cache e bus colidem na mesma porta host. Recomendação Devops: `REDIS_PORT=6379` + `REDIS_BUS_PORT=6380` e provisionar os dois serviços.
- **P4 parcial**: `worker` e `data_storage` ainda usam `ConnectionManager::new` sem timeouts (plano restringia P4 ao `data_postgres`). Estender quando entrarem no escopo.
- **`_cache_conn` em `main.rs`**: placeholder transitório (será usado quando o `data_postgres` ler tokens/cache).

---
*Nenhum commit foi feito pela auditoria; correções estão no working tree. Nenhum teste novo criado. Plano não arquivado (fase V pendente).*
</content>
