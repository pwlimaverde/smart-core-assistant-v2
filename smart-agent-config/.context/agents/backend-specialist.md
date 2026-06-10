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

- Implementar os apps Rust de negócio (`messaging_gateway`, `worker`, `runtime_api`, `control_plane`) como **clientes finos**: dados só via RPC aos serviços `data_*` (`transport::conectar_cliente`), nunca importando `infrastructure_*`.
- Evoluir os serviços de dados (`data_postgres`, `data_redis`, `data_storage`): novo acesso a banco = **novo handler no `data_postgres`** (rota no `Server::from_env`, repositórios de `infrastructure_postgres`, auditoria via `transport::bus`).
- Implementar casos de uso em `crates/application/` (auth hoje; depois `ReceiveMessage`, `DecideTicketPolicy`, `CanBotRespond`).
- Escrever adaptadores nas libs `infrastructure_*` — consumidos exclusivamente pelos respectivos `data_*`.
- Garantir idempotência no worker: `wa_message_id` duplicado não reprocessado.
- Implementar debounce por contato com lock de agendamento.
- Definir o contrato **gRPC** com o `ia_engine` (Python) em `crates/contracts` + `.proto`. FFI/PyO3 descartado (§13.1).
- No `worker`: cliente gRPC para o `ia_engine` (timeout/retry) + scheduler que substitui o Celery da v1 (Redis Streams + agendamento de feedback/retenção).

## Stack

Rust: tokio (async), axum (HTTP do webhook), tonic (gRPC fallback), FlatBuffers (`flatc`, codec padrão do RPC interno), sqlx (PostgreSQL), redis (streams). O `ia_engine` é serviço Python separado (gRPC), não embarcado.

## Quality Checks

- `cargo clippy --all-targets -- -D warnings` sem erros.
- `cargo fmt --check` para formatação.
- Testes de infraestrutura com banco real (não mock); padrão da skill `test-rust`.
- Toda query com filtro por `tenant_id` além do RLS.
- Sem `unwrap()` em código de produção — usar `?` e tipos `Result` (`error_core::AppError`).
- Em Windows (dev), endpoints via `SMARTCORE_<SVC>_ENDPOINT=tcp://` (UDS não funciona).
