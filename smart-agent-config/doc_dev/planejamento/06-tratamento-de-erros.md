# 06 — Tratamento de Erros (`error_core`)

> **Status:** Planejamento (a implementar). **Fundação transversal** — par da
> observabilidade ([05-observabilidade.md](./05-observabilidade.md)).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Necessidade de **organizar os erros de forma rastreável** em todos
> os módulos (logs e registros de erro padronizados). Fundação, antes dos módulos
> de feature.

---

## 1. Objetivo

Centralizar a **organização dos erros** numa crate dedicada
(`server/crates/error_core`): uma taxonomia comum, mapeamento para o transporte
(gRPC/HTTP) e integração com a observabilidade, de modo que **todo erro seja
rastreável e consistente** entre os módulos.

> **Não substitui** os erros por crate (idiomático em Rust): `DbError`
> (`infrastructure_postgres`), `RedisError` (`infrastructure_redis`),
> `StorageError` (`infrastructure_storage`), `AuthError` (auth) **continuam**.
> O `error_core` os **unifica na borda** (aplicação/transporte) e padroniza o
> **registro rastreável** (log com `error_code` + `trace_id` + `tenant_id`).

## 2. Por que uma crate dedicada

- **Rastreabilidade:** todo erro carrega um `error_code` estável + correlação
  (`trace_id`/`tenant_id`), aparecendo nos logs/métricas (doc 05) e permitindo
  alertas por código.
- **Consistência:** um único lugar define severidade, se é *retryable* e qual a
  **mensagem pública** (sem vazar detalhe interno ao cliente).
- **Fronteira limpa:** converte qualquer erro interno em `tonic::Status` (e HTTP
  no futuro) de forma uniforme, em vez de cada handler reinventar o mapeamento.

## 3. Decisões travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| E1 | Erros por crate | **Mantidos** (`thiserror`) | Idiomático; cada crate dona do seu erro |
| E2 | Agregação | **`AppError`** (enum) com `From<DbError/RedisError/StorageError/AuthError>` | Um tipo único na camada `application`/apps |
| E3 | Código estável | **`ErrorCode`** (enum string-serializável, ex.: `AUTH_INVALID_TOKEN`, `STORAGE_NOT_FOUND`) | Estável para cliente, métricas e alertas |
| E4 | Classificação | cada erro expõe `severity` (warn/error) + `retryable` (bool) + `public_message` | Decide log, retry e o que o cliente vê |
| E5 | Transporte | `to_status() -> tonic::Status` (e `to_http()` futuro) | Mapeamento único na borda (espelha doc 09: `unauthenticated`/`permission_denied`/…) |
| E6 | Registro rastreável | helper que loga via `tracing` com `error_code`+`trace_id`+`tenant_id` | Integra ao doc 05; nunca vaza segredo/PII |
| E7 | Sem `unwrap()/expect()` em produção | uso de `?`/`Result<_, AppError>` | Padrão do workspace |

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade |
|---|---|
| `code.rs` | `ErrorCode` (taxonomia estável) + categoria |
| `error.rs` | `AppError` (agregador) + `From<…>` dos erros por crate + `severity`/`retryable`/`public_message` |
| `report.rs` | `ErrorReport` (estrutura logada: `error_code`, `severity`, `tenant_id`, `trace_id`, `context`) + helper `registrar(&AppError, ctx)` |
| `transport.rs` | `to_status()` (tonic) — mapa `ErrorCode → Code` |
| `lib.rs` | reexports + doc |

## 5. Relações

- **← `observability` (doc 05):** `error_core` usa o `tracing` configurado para
  registrar erros com correlação; as métricas de erro são contadas **por
  `error_code`**.
- **← erros por crate:** `From<DbError>`, `From<RedisError>`,
  `From<StorageError>`, `From<AuthError>` → `AppError`.
- **→ `application`/`apps`:** os casos de uso retornam `Result<_, AppError>`; os
  handlers gRPC chamam `to_status()` na borda (alinha à defesa-em-3-camadas do
  doc 09).
- **→ `contracts` (doc 07):** se algum `error_code`/DTO de erro cruzar a fronteira
  cliente↔servidor, o tipo vive em `contracts`.

## 6. Dependência e ambiente

- **Workspace:** adicionar `crates/error_core` aos `members`;
  `error_core = { path = "crates/error_core" }`.
- **Deps:** `thiserror`, `serde` (serializar `ErrorCode`), `tracing`; `tonic`
  (feature/opcional) para `to_status()`. Sem `sqlx`/`redis`.

## 7. Testes

- `From<…>` de cada erro de crate → `AppError` com `ErrorCode` correto.
- `to_status()` mapeia códigos esperados (ex.: `AUTH_INVALID_TOKEN` →
  `unauthenticated`).
- `public_message` nunca expõe detalhe interno; `ErrorReport` inclui correlação.
- Comandos: `cargo test -p error_core`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check`.

## 8. Mapeamento para fases

| Entrega | Fase | Escopo |
|---|---|---|
| `error_core` (taxonomia + `AppError` + `to_status` + registro) | **0.5** | base para todos os módulos |
| Cobertura de `error_code` por domínio | **conforme cada módulo** | crescente |

## 9. Próximo passo

Implementar junto com a observabilidade (doc 05), **antes** do storage e dos
módulos de feature, para que tudo já nasça com erros rastreáveis e padronizados.

---

*Plano do tratamento de erros. Sujeito a canonização via `plan-restructuring`.*
