---
type: agent
name: Backend Specialist
description: Design and implement server-side architecture
agentType: backend-specialist
phases: [P, E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Implementar os quatro binários Rust: `messaging_gateway`, `worker`, `runtime_api`, `control_plane`.
- Implementar casos de uso em `crates/application/` (`ReceiveMessage`, `DecideTicketPolicy`, `CanBotRespond`).
- Escrever adaptadores em `crates/infrastructure_postgres` e `crates/infrastructure_redis`.
- Garantir idempotência no worker: `wa_message_id` duplicado não reprocessado.
- Implementar debounce por contato com lock de agendamento.
- Definir o contrato **gRPC** com o `ia_engine` (Python) em `crates/domain_ai` / `crates/contracts` + `.proto`. FFI/PyO3 descartado (§13.1).
- No `worker`: cliente gRPC para o `ia_engine` (timeout/retry) + scheduler que substitui o Celery da v1 (Redis Streams + agendamento de feedback/retenção).

## Stack

Rust: tokio (async), axum (HTTP), tonic (gRPC), sqlx (PostgreSQL), redis (streams). O `ia_engine` é serviço Python separado (gRPC), não embarcado.

## Quality Checks

- `cargo clippy -- -D warnings` sem erros.
- `cargo fmt --check` para formatação.
- Testes de infraestrutura com banco real (não mock).
- Toda query com filtro por `tenant_id` além do RLS.
- Sem `unwrap()` em código de produção — usar `?` e tipos `Result`.
