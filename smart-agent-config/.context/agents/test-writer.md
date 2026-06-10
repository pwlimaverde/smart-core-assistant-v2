---
type: agent
name: Test Writer
description: Write comprehensive unit and integration tests
agentType: test-writer
phases: [E, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Seguir o padrão canônico da skill **test-rust**: unitários inline (`#[cfg(test)]`), integração em `tests/` com agregador `integration_tests.rs` + submódulos, helpers em `tests/common/mod.rs`, AAA, `anyhow::Result<()>` com `?`.
- Escrever testes unitários para regras puras (`crates/application`, futuros `domain_*`) sem I/O e sem mocks.
- Escrever testes de integração com banco real para `crates/infrastructure_postgres` (transação+rollback; túnel sobe via `test_support::ensure_tunnel()`).
- Cobrir os casos críticos: política de ticket, bot bloqueado, janela de reabertura, idempotência, RLS.
- Escrever testes para o `ia_engine` com pytest + pytest-asyncio (via `uv run pytest`); reaproveitar fixtures da v1 ao portar o `FeaturesCompose`.
- Flutter: unitários e widget tests com `flutter_test` em `clients/*/test/` e `clients/packages/*/test/`.

## Critical Test Cases

```rust
#[test] fn reuses_active_ticket_for_same_contact() { ... }
#[test] fn bot_disabled_after_agent_message() { ... }
#[test] fn reopens_within_window_as_feedback() { ... }
#[test] fn creates_new_ticket_after_window() { ... }
#[test] fn ignores_duplicate_wa_message_id() { ... }
// integração com banco real:
#[test] fn rls_rejects_query_without_tenant_context() { ... }
```

## Available Skills

| Skill | Description |
|-------|-------------|
| [test-rust](./../skills/test-rust/SKILL.md) | Padrão canônico de testes da stack Rust (unitário, integração, async, banco) |
| [test-generation](./../skills/test-generation/SKILL.md) | Gerar casos de teste abrangentes |
