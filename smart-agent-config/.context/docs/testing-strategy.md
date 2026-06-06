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
> referência canônica e completa é a skill `test-rust` (`.agents/skills/test-rust/SKILL.md`).

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

## Related Resources

- [Architecture](architecture.md)
- [Development Workflow](development-workflow.md)
