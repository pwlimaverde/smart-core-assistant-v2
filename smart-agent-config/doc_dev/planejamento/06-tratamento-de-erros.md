# 06 — Tratamento de Erros (`error_core`)

> **Status:** ✅ Concluída (Fase 0 e Fase 1). Crate `server/crates/error_core` integrada com `contracts` (FlatBuffers/IPC) e `transport`.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular. Integração com o fluxo de serialização IPC/RPC.

---

## 1. Objetivo

Centralizar a **organização dos erros** numa crate dedicada (`server/crates/error_core`): uma taxonomia comum, mapeamento para o transporte IPC/FlatBuffers (via `ErrorEnvelope`) e gRPC/HTTP, e integração com a observabilidade, de modo que **todo erro seja rastreável e consistente** entre os microsserviços.

> **Não substitui** os erros por crate (idiomático em Rust): `DbError` (`infrastructure_postgres`), `RedisError` (`infrastructure_redis`), `StorageError` (`infrastructure_storage`), `AuthError` (auth) **continuam**. O `error_core` os **unifica na borda** de cada microsserviço e padroniza o **registro rastreável** (log com `error_code` + `trace_id` + `tenant_id`).

## 2. Por que uma crate dedicada em arquitetura modular

- **Rastreabilidade Distribuída:** todo erro carrega um `error_code` estável + correlação (`trace_id`/`tenant_id`), propagando-se por chamadas RPC no socket UDS ou via Redis Streams.
- **Preservação de Contexto:** a serialização via FlatBuffers (`ErrorEnvelope`) garante que um erro originado em um microsserviço de persistência (como `data_postgres`) possa ser interpretado de forma estruturada no chamador (`runtime_api` ou `worker`).
- **Consistência:** centralização de severidade, lógica de retry, e a **mensagem pública** (sem vazar detalhes sensíveis do banco/sistema).
- **Fronteira Única:** mapeamento único para `tonic::Status` (gRPC fallback) e estruturas FlatBuffers (IPC).

## 3. Decisões travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| E1 | Erros por crate | **Mantidos** (`thiserror`) | Idiomático; cada crate dona do seu erro |
| E2 | Agregação | **`AppError`** (enum) com `From<DbError/RedisError/StorageError/AuthError>` | Um tipo único na camada `application`/apps |
| E3 | Código estável | **`ErrorCode`** (enum string-serializável, ex.: `AUTH_INVALID_TOKEN`, `DB_QUERY_FAILURE`) | Estável para cliente, métricas e alertas |
| E4 | Classificação | cada erro expõe `severity` (warn/error) + `retryable` (bool) + `public_message` | Decide log, retry e o que o cliente vê |
| E5 | Transporte gRPC | `to_status() -> tonic::Status` | Mapeamento padrão para gRPC fallback (unauthenticated, permission_denied, etc.) |
| E6 | Registro rastreável | helper que loga via `tracing` com `error_code`+`trace_id`+`tenant_id` | Integra ao doc 05; nunca vaza segredo/PII |
| E7 | Sem `unwrap()/expect()` em produção | uso de `?`/`Result<_, AppError>` | Padrão do workspace |
| E8 | Serialização IPC | **`ErrorEnvelope`** via FlatBuffers na crate `contracts` | Permite que erros estruturados cruzem os sockets UDS sem perda de semântica |

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade |
|---|---|
| `code.rs` | `ErrorCode` (taxonomia estável) + categoria |
| `error.rs` | `AppError` (agregador) + `From<…>` dos erros por crate + `severity`/`retryable`/`public_message` |
| `report.rs` | `ErrorReport` (estrutura logada: `error_code`, `severity`, `tenant_id`, `trace_id`, `context`) + helper `registrar(&AppError, ctx)` |
| `transport.rs` | `to_status()` (tonic) e serialização/desserialização para `ErrorEnvelope` (FlatBuffers) |
| `envelope_bridge.rs` | ponte entre `AppError` e o `ErrorEnvelope` de `contracts` (`to_error_envelope`) usada pelos handlers RPC |
| `lib.rs` | reexports + doc |

## 5. Relações

- **← `observability` (doc 05):** `error_core` usa o `tracing` para registrar erros com correlação; métricas de erro contadas por `error_code`.
- **← erros por crate:** `From<DbError>`, `From<RedisError>`, `From<StorageError>` → `AppError`.
- **→ `application`/`apps`:** os casos de uso retornam `Result<_, AppError>`; os handlers de rede e IPC serializam o erro na borda.
- **→ `contracts` (doc 07):** os schemas protobuf/FlatBuffers definem o `ErrorEnvelope` contendo o código, a mensagem legível e metadados de trace para tráfego IPC.

## 6. Dependência e ambiente

- **Workspace:** `crates/error_core` como membro do Cargo workspace; disponível como dependency interna.
- **Deps:** `thiserror`, `serde`, `tracing`; `tonic` (feature `grpc`) para gRPC status, e `contracts` para conversão de FlatBuffers.

## 7. Testes e Validação

- `From<…>` de cada erro de crate mapeia para o `ErrorCode` correto.
- `ErrorEnvelope` FlatBuffers preserva código e mensagem após roundtrip de serialização.
- Clippy e formatadores obrigatórios: `cargo clippy --all-targets` sem warnings.

## 8. Mapeamento para fases

| Entrega | Fase | Status | Escopo |
|---|---|---|---|
| Crate `error_core` (taxonomia, `AppError`, helpers) | **Fase 0** | **Concluído (✅)** | Crate base para padronização de erros |
| Mapeamento RPC/IPC (`ErrorEnvelope` FlatBuffers) | **Fase 1** | **Concluído (✅)** | Integração com transporte distribuído |
| Evolução da taxonomia de erros por novos domínios | **Contínuo** | Em andamento | Conforme novos apps são codificados |

## 9. Próximo passo

O tratamento de erros unificado está implementado e integrado ao sistema de contratos ([07-crate-contracts.md](./07-crate-contracts.md)) e comunicação ([09-comunicacao-e-autenticacao.md](./09-comunicacao-e-autenticacao.md)). As próximas implementações de lógica de negócio em `worker` e `runtime_api` devem consumir `AppError` e propagar erros via cliente IPC tipado de `transport`.


