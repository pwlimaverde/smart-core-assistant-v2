---
type: doc
name: testing-strategy
description: Test frameworks, patterns, coverage requirements, and quality gates
category: testing
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Testing Strategy

> Em desenvolvimento — estratégia refinada incrementalmente. O padrão de testes da
> stack Rust foi **padronizado** (skill `test-rust`) e já há **testes de integração
> reais** contra Postgres (isolamento multi-tenant/RLS) e Redis (event bus/auth_tokens),
> além de cobertura em `error_core`, `observability`, `transport` e `application`. A
> referência canônica e completa é a [SKILL.md](../skills/test-rust/SKILL.md) da skill test-rust.

## Padrão de testes Rust (canônico — skill `test-rust`)

A stack Rust segue um padrão único, válido para toda crate (`crates/`) e app (`apps/`):

- **Unitários — inline no `src/`**: lógica pura, conversões e branches de erro vivem num
  `#[cfg(test)] mod tests` dentro do próprio arquivo (acesso a itens privados via
  `use super::*;`). Ex.: `contracts/src/envelope.rs`, handlers de `apps/data_storage`.
- **Integração — pasta `tests/` por crate** (vizinha ao `Cargo.toml`), com:
  - **Um único ponto de entrada agregador** `tests/integration_tests.rs` que declara os
    submódulos por domínio (`mod auth; mod cache; mod tenants; …`). Isso compila uma só
    crate de teste (mais rápido) em vez de um binário por arquivo.
  - **Submódulos espelhando o `src/`**: `tests/<dominio>/mod.rs` (ex.: `tests/atendimentos/mod.rs`,
    `tests/event_bus/mod.rs`).
  - **Helpers compartilhados** em `tests/common/mod.rs` (usar `common/mod.rs`, nunca
    `common.rs`, para o Cargo não tratá-lo como suíte separada).
- **Nomenclatura**: funções de teste em **inglês**, comportamentais
  (`rls_blocks_cross_tenant_read`, `save_contact_is_idempotent_on_conflict`); comentários
  explicativos em **pt-br**. Padrão **AAA** (Arrange/Act/Assert), um `Act` por teste.
- **Resultados/erros**: preferir `-> anyhow::Result<()>` com `?` no encanamento; validar a
  **variante** do erro (`matches!`), não só `is_err()`. `#[should_panic(expected = …)]`
  para panics genuínos.
- **Async**: `#[tokio::test]` (multi-thread só quando há concorrência real); sempre com
  `timeout` em I/O/rede; inicialização única via `OnceLock`/`Once`.

## Testes de banco (PostgreSQL / SQLx)

- **Banco real, nunca mock** — mock de banco testa o mock, não o SQL.
- **Transação por teste com rollback** (regra de ouro) ou `#[sqlx::test]` com fixtures.
- **Fail-closed/RLS**: testar explicitamente a **negação** — query sem tenant retorna zero
  linhas; tenant B não enxerga dados de tenant A (`run_in_tenant_transaction` + `RequestContext`).
- **Infra dos testes**: `test_support::ensure_tunnel()` sobe o túnel SSH sozinho;
  `SQLX_OFFLINE=true` com `.sqlx/` versionado; Redis usa o **banco lógico 15** com `FLUSHDB`
  e `RUST_TEST_THREADS=1`. Ver memória `testes-db-tunel-e-reset`.
- **Topologia do túnel** (local → Hostinger): `5434`→Postgres, `6379`→Redis **cache**
  (remoto 6380, allkeys-lru), `6380`→Redis **bus** (remoto 6381, noeviction). A porta
  host 6379 do servidor pertence a outro projeto — não usar.

## Ambientes de teste

O projeto possui **três ambientes distintos**:

| Ambiente | Onde roda | Suite executada | Gatilho |
|----------|-----------|-----------------|---------|
| **Local (Windows)** | máquina do dev | completa: unit + integração | manual, pré-push |
| **CI (GitHub Actions)** | ubuntu-latest | gate: `--lib --bins`; cobertura combinada (`--workspace`, unit+integração) informativa via `cargo llvm-cov` | push/PR automático |
| **Hostinger dev/prod** | VPS remota | deploy automático pós-CI verde | CI verde em `dev`/`main` |

## Workflow ao escrever um novo teste

A regra depende do **tipo** de teste:

**Teste unitário** (inline em `src/`, sem banco/cache/rede) → roda **isolado via `cargo`**:

```powershell
# a partir de server/
cargo test nome_parcial_do_teste
cargo test -p data_postgres login          # filtrar por crate
cargo test nome_parcial -- --nocapture     # ver saída
```

Unitários não tocam recursos externos — não precisam de túnel nem de `.env`.

**Teste de integração** (pasta `tests/`, depende de Postgres/Redis) → roda **a partir do
script** `infra/test-local.ps1`, **nunca** via `cargo test` direto. É o script que orquestra
as conexões (túnel SSH para os bancos da Hostinger, variáveis de ambiente, ordem dos gates):

```powershell
.\infra\test-local.ps1                # esteira completa: fmt → clippy → cargo test --workspace → sqlx prepare --check
.\infra\test-local.ps1 -ResetTunnel   # idem, derrubando túneis ssh antigos antes (após mudança de portas)
.\infra\test-local.ps1 -Fast          # modo rápido sem banco: fmt → clippy → --lib --bins (igual ao CI)
```

`-Fast` é o que o CI executa; **não substitui** a esteira completa. **Sempre rode sem flags
antes do push** para exercitar a integração.

## Esteira local pré-push (`infra/test-local.ps1`)

O gate do CI (`ci.yml`) roda `--lib --bins` com serviços efêmeros do runner. A **suíte
completa** (unit + integração contra o banco real da Hostinger) roda **localmente, antes
do push**, com a mesma sequência de gates do CI:

```
fmt → clippy → cargo test --workspace → cargo sqlx prepare --check
```

Desde a etapa **C1** do plano de cobertura (`.context/plans/cobertura-testes-100.md`), o
CI também roda `cargo llvm-cov --workspace` (unit+integração combinada, contra os mesmos
service containers efêmeros) como passo **informativo** (`continue-on-error`) — é a
primeira vez que a suíte de integração roda no CI (antes só localmente), então ainda não
bloqueia o pipeline. Vira gate (ratchet) na etapa C5, depois de provar estável. `ia_engine`
também ganhou job próprio no CI (`uv sync` + `uv run pytest --cov`) — antes os 44 testes
Python nunca rodavam no pipeline.

Pré-requisitos: `infra/.env.deploy` (credenciais SSH) e `server/.env`
(`DATABASE_URL`/`DATABASE_ADMIN_URL`/`REDIS_URL`/`REDIS_BUS_URL` apontando para
`5434`/`6379`/`6380` locais).

## Mocking — só nas fronteiras externas

- Mock **apenas** de rede/serviços externos (ex.: o futuro cliente do `ia_engine`), sobre
  **traits** (`mockall`/`wiremock`). Nunca mockar banco, cache ou lógica de domínio própria.

## Test Organization (por stack)

- **Rust**: unitários inline em `src/` (`#[cfg(test)]`); integração em `crates/*/tests/`
  e `apps/*/tests/` com o agregador `integration_tests.rs` + submódulos por domínio.
- **Python**: testes em `ia_engine/tests/` com pytest (gerenciado por `uv`).
- **Flutter**: unitários em `clients/flutter_windows/test/` e `clients/flutter_web/test/`
  + `clients/packages/*/test/`; widget e integration tests conforme necessário.

## Testing Priorities

1. **`crates/application`** (e `domain_*` quando extraídos) — casos de uso/regras puras;
   alta cobertura. Cobrir auth, `TicketPolicy`, `BotRulesEngine`, debounce.
2. **`crates/infrastructure_postgres`** — integração com banco real (não mock). Lição da
   v1: mocks escondem divergências de schema.
3. **`crates/transport` / `contracts`** — round-trip de codecs (FlatBuffers/gRPC) e o
   barramento (`transport::bus`): publicar→consumir→confirmar e replay de pendentes.
4. **`messaging_gateway`** — validação de webhook, resolução de tenant, idempotência.
5. **`ia_engine`** — cada feature (transcrição, RAG, geração de resposta); reaproveitar
   fixtures da v1 ao portar o `FeaturesCompose`.

## Domain Rules to Test Explicitly

- Um atendimento ativo por contato (política de ticket).
- Janela de reabertura de 10 min.
- Bot bloqueado permanentemente por mensagem de atendente.
- Idempotência: `wa_message_id` duplicado não reprocessado.
- RLS: query sem `tenant_id` no contexto deve ser rejeitada (zero linhas).
- Debounce: rajada resulta em lote único processado.

## Tooling

| Stack | Framework | Observação |
|-------|-----------|-----------|
| Rust | `cargo test` / `cargo test --workspace` | Unitários inline + integração por crate |
| Rust (recomendado) | `cargo nextest run` | Mais rápido; um processo por teste reforça isolamento |
| Rust (integração) | banco real sob transação+rollback | Não usar mocks de banco; `test_support::ensure_tunnel()` + `SQLX_OFFLINE` |
| Rust (cobertura) | `cargo llvm-cov` | Bússola, não meta cega |
| Rust (lint de testes) | `cargo clippy --all-targets -- -D warnings` | Cobre o código de teste |
| Python | `pytest` + `pytest-asyncio` | Para `ia_engine` async (via `uv run pytest`) |
| Flutter | `flutter test` | Unitário + widget |

## Cobertura de testes (plano `cobertura-testes-100`, C1–C5)

> Iniciativa concluída em 2026-07-20 — `.context/plans/cobertura-testes-100.md`.
> Política: **bússola, não meta cega** — 100% é o norte, com exclusões justificadas.

| Stack | Baseline | Final medido | Ratchet no CI |
|---|---|---|---|
| Python (`ia_engine`, não-bootstrap) | 73% | **99%** (878 stmts, 130 testes) | ✅ ativo — `--cov-fail-under=90` |
| Flutter (`clients`, agregado significativo) | 76,4% | **95,1%** (1143/1202, 337 testes) | ✅ ativo — piso 85% no job `flutter` |
| Rust (unitário, `--lib --bins`) | 48% (16.623 linhas) | **~56%** (workspace) | ⏸️ informativo — combinado real (unit+integração) no CI; threshold numérico quando a suíte provar mais rodadas estáveis |

Crates/módulos Rust de lógica cobertos com folga: `error_core` 97–100%, `application` (`jwt` 97%, `tokens` 100%, `login` 91%), `domain_whatsapp` 99%, `local_engine` 97–99%, `transport` (`codec`/`framing` 98–100%), `infrastructure_postgres` (repos 80–100%), `contracts/envelope` 100%.

### Cobertura residual (pós-C5, 2026-07-20 — lacunas fora do escopo original do plano)
Um levantamento pós-plano revelou áreas nunca visadas pelas etapas C1–C5; fechadas em seguida:
- **Flutter `admin_module`** (painel do superusuário): tinha **0 testes** (67 arquivos, nem diretório `test/`) → **100% do código significativo** (315 linhas, 136 testes: 25 métodos do `admin_service_impl`, `grpc_error_mapper`, 8 controllers via `bloc_test`, 22 usecases, 12 models).
- **Rust `runtime_api`**: `grpc_web.rs` 11%→34% e `realtime.rs` 0%→63% (24 testes; partes puras — extração de metadata, guardas de escopo, mapeamento de erro, gerência de canais broadcast do `RealtimeManager`).
- **Rust secundários**: `worker/ia_engine/tonic_client.rs` 0%→82%, `observability/usage_metrics.rs` 64%→100% e `pool_metrics.rs` 0%→70%, `data_storage/main.rs` 26%→55%, `transport/bus.rs` 27%→47%, `infrastructure_evolution/provider.rs` (unit + wiremock em `tests/`); 49 testes.

### Exclusões revisadas (justificadas, não meta cega)
- **Python**: `[tool.coverage.run] omit` em `ia_engine/pyproject.toml` — stubs gRPC gerados (`contracts/*`), `__main__.py`, e bootstrap (`server.py`, `settings.py`, `telemetry.py`). O único trecho residual (`features/transcribe/domain/services.py`, corpo `...` de um `Protocol`) é estruturalmente não-invocável.
- **Rust**: `--ignore-filename-regex '.*/target/.*/out/.*'` no CI, excluindo código FlatBuffers/protobuf gerado pelo `build.rs`. **Correção do Planning original**: a hipótese de excluir todo `main.rs` de `apps/*` como "entrypoint fino" é falsa aqui — a C4 elevou `apps/data_redis/src/main.rs` de 44% para 83% com testes de lógica real; `main.rs` **não** é excluído. Áreas genuinamente integração-only (handlers RPC de `grpc_web`/`data_postgres` adapters, chamadas tonic reais, callbacks de gauge OTLP, `control_plane/cli` interativo) são cobertas por `tests/` de integração, não por unit.
- **Flutter**: o `flutter test --coverage` não tem `omit` nativo, então a exclusão é aplicada **na agregação do lcov** (CI `ci.yml` e `infra/test-flutter.ps1`, mesma regra): não contam para o denominador `data/datasources/*` (fronteira externa gRPC/remoto/FFI — cobertos por integração/E2E) nem `presentation/pages|routes/*` (layout/navegação de UI pura). Widgets **contam** (o `design_system` os testa de verdade). Sem isso, um módulo UI-pesado como o `admin_module` (datasource gRPC de 331 linhas + páginas) afundaria o agregado sem refletir a cobertura significativa real.

### Achados registrados para follow-up (fora do escopo desta iniciativa de testes)
- `local_engine::offline_queue::OfflineQueue::next_version()` faz `SELECT MAX(version)+1` numa query separada do `INSERT` de `enqueue()`, sem transação/lock — corrida sob concorrência comprovada por teste dedicado (`achado_next_version_nao_e_atomico_sob_concorrencia`, em `server/crates/local_engine/src/offline_queue/mod.rs`). Fix arquitetural não foi feito aqui (fora de escopo de uma tarefa de testes).
- Falha pré-existente e ambiental em `apps/worker/src/scheduler.rs::test_processar_midia_expirada_marca_e_publica` quando `REDIS_URL` aponta para `localhost:6379` (porta de outro projeto local); passa no CI (container próprio). Ver memória `deploy-evolution-remove-orphans`.

## Related Resources

- [Architecture](architecture.md)
- [Development Workflow](development-workflow.md)
