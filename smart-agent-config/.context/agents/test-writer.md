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

- Escrever testes unitários para regras de domínio em `crates/domain_*` (sem I/O, sem mocks).
- Escrever testes de integração com banco real para `crates/infrastructure_postgres`.
- Cobrir os casos críticos: política de ticket, bot bloqueado, janela de reabertura, idempotência, RLS.
- Escrever testes para o `ai_orchestrator` com pytest.

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
| [test-generation](./../skills/test-generation/SKILL.md) | Gerar casos de teste abrangentes |
