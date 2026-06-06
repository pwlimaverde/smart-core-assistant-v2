---
status: completed
generated: 2026-06-04
slug: tratamento-de-erros
scale: MEDIUM
artifacts:
  plano_completo: "./tratamento-de-erros/plano_completo_tratamento-de-erros.md"
  info_aux: "./tratamento-de-erros/info_aux_tratamento-de-erros.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo, API pública e decisões de workspace"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — design de tipos, mapeamento gRPC e feature flags"
    prevc: "R"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — crate error_core (code, error, report, transport, testes)"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — cargo test + clippy + fmt + integração observability"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento dotcontext"
    prevc: "C"
    agent: "backend-specialist"
    status: "completed"
---

# Crate `error_core` — Tratamento de Erros Rastreável

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/06-tratamento-de-erros.md`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./tratamento-de-erros/plano_completo_tratamento-de-erros.md`](./tratamento-de-erros/plano_completo_tratamento-de-erros.md)
- **Documentação auxiliar (libs + decisões):**
  [`./tratamento-de-erros/info_aux_tratamento-de-erros.md`](./tratamento-de-erros/info_aux_tratamento-de-erros.md)

## Objetivo

Criar a crate `server/crates/error_core` com **taxonomia de erros estável** (`ErrorCode`),
**tipo agregador** (`AppError`), **registro rastreável** (`ErrorReport` + `registrar()`) e
**mapeamento gRPC** (`to_status()`, feature opcional `grpc`).

Fundação transversal da v2 — todo módulo posterior nasce com erros rastreáveis e padronizados,
integrados à `observability` (doc 05) via `tracing`. **Não substitui** os erros por crate
(`DbError`, `RedisError`, `StorageError`, `AuthError`): o `error_core` os unifica na borda
(camada `application`/handlers gRPC).

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo, API pública e decisões de workspace | Backend Specialist | ✅ completed |
| **R** | Review — design de tipos, mapeamento gRPC e feature flags | Backend Specialist | ✅ completed |
| **E** | Execution — crate `error_core` (code, error, report, transport, testes) | Backend Specialist | ✅ completed |
| **V** | Validation — `cargo test` + clippy + fmt + integração observability | Test Writer | ✅ completed |
| **C** | Confirmation — final-review e arquivamento dotcontext | Backend Specialist | ✅ completed |

## Decisões-chave (resumo — detalhes no plano completo)

1. **`AppError` com payload `String`** — erros de infra ainda não existem no workspace; `From<XError>` será adicionado incrementalmente quando as crates concretas existirem.
2. **`tonic = "0.14.6"` como dep de workspace** — ausente no `server/Cargo.toml` atual; primeira ação da fase E.
3. **Feature `grpc` opcional** — `tonic` só é carregado em crates/binários que precisam de gRPC.
4. **`Display` para `ErrorCode`** — serialização `SCREAMING_SNAKE_CASE` sem `serde_json` no hot path de log.
5. **`severity()` por variante + conteúdo** — `AppError::Storage(not_found)` é `Warn`; `Storage(upload_failed)` é `Error`.
6. **Mapeamento gRPC alinhado ao doc 09:** `AuthInsufficientScope` → `PermissionDenied`; demais auth → `Unauthenticated`.

## Correções aplicadas vs. plano base

`tonic` ausente no workspace → adicionada como dep explícita (E8); `#[from]` sobre crates inexistentes → payload `String` temporário; `AuthInsufficientScope` separado de `Unauthenticated`; `RateLimitExceeded`/`Conflict` adicionados ao `ErrorCode`; testes feature-gated por arquivo; `severity()` composta. Detalhes completos na seção "Correções Aplicadas" do plano completo.

## Verificação

`cargo build -p error_core` → `cargo build -p error_core --features grpc` → `cargo test -p error_core --features grpc` → `cargo clippy -p error_core --all-targets -- -D warnings` → `cargo fmt --check -p error_core`. Branch `feature/tratamento-de-erros`; commits sem auto-referência; comentários em pt-br.
