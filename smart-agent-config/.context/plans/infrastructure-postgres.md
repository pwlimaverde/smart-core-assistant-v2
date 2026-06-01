---
status: in_progress
generated: 2026-06-01
slug: infrastructure-postgres
scale: LARGE
artifacts:
  plano_completo: "./infrastructure-postgres/plano_completo_infrastructure-postgres.md"
  info_aux: "./infrastructure-postgres/info_aux_infrastructure-postgres.md"
phases:
  - id: "phase-p"
    name: "Planning — consolidação de schema e decisões"
    prevc: "P"
    agent: "database-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — validação de RLS, modelagem e cripto"
    prevc: "R"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-e"
    name: "Execution — workspace + crate infrastructure_postgres"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-v"
    name: "Validation — migrations, build offline e testes de integração"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review, commit gitflow e arquivamento"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Fundação Rust de Persistência — crate `infrastructure_postgres`

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./infrastructure-postgres/plano_completo_infrastructure-postgres.md`](./infrastructure-postgres/plano_completo_infrastructure-postgres.md)
- **Documentação auxiliar (libs + decisões):**
  [`./infrastructure-postgres/info_aux_infrastructure-postgres.md`](./infrastructure-postgres/info_aux_infrastructure-postgres.md)

## Objetivo

Criar o Cargo workspace em `server/` (raiz do repo `smart-core-assistant-v2`) e implementar
de ponta a ponta a crate **`infrastructure_postgres`** — base de toda a persistência do
Smart Core Assistant v2 sob arquitetura de **banco PostgreSQL único + pgvector com
Row-Level Security (RLS)**. Fonte do schema: `doc_dev/modelagem_dados/` (01..09 +
arquitetura/estratégia).

**Escopo (fundação):** migrations `0001..0009` com RLS, modelos/structs, traits e
repositórios SQLx, `run_in_tenant_transaction` (via `set_config`), `TenantConfigCache`
(DashMap), `CipherManager` (AES-256-GCM), `DbError`, `RequestContext` e busca vetorial
pgvector. **Fora do escopo:** `infrastructure_redis`, `application`, binários `apps/`,
middleware HTTP/JWT e gRPC `ia_engine` (fases posteriores).

**Sinal de sucesso:** `SQLX_OFFLINE=true cargo build -p infrastructure_postgres` compila;
migrations aplicam no Postgres real (via `infra/tunnel.ps1`); testes de integração provam
isolamento RLS cross-tenant, round-trip do `CipherManager`, fallback do `TenantConfigCache`
e busca vetorial por cosseno; `cargo clippy` e `cargo fmt --check` limpos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — consolidação de schema e decisões | Database Specialist | ✅ completed |
| **R** | Review — validação de RLS, modelagem e cripto | Backend Specialist (+ Security Auditor) | pending |
| **E** | Execution — workspace + crate `infrastructure_postgres` | Backend Specialist (+ Database Specialist) | pending |
| **V** | Validation — migrations, build offline e testes | Test Writer (+ Backend Specialist) | pending |
| **C** | Confirmation — final-review, commit e arquivamento | Backend Specialist | pending |

## Decisões-chave (resumo — detalhes no plano completo)

1. **RLS via `SELECT set_config('app.current_tenant', $1, true)`** — `SET LOCAL = $1` não
   aceita bind.
2. **`auth_user` mínima** (global, sem RLS) na migration `0001` para as FKs do legado.
3. **`SecretString` (secrecy)** nas chaves de API; feature `serde` só na ponte Redis futura.
4. **base64 0.22** usa `Engine` (`encode/decode` globais removidas).
5. **DashMap = cache de `RuntimeConfig`**, não pools por tenant; nunca segurar `Ref` em `.await`.
6. **Índice HNSW `vector_cosine_ops`** + filtro `tenant_id` explícito na busca vetorial.
7. **Tabelas globais sem RLS:** `auth_user`, `tenants_plan`, `settings_manager_coresettings`.

## Verificação

Túnel SSH → `sqlx migrate run` → validar RLS (`pg_class.relrowsecurity`) →
`cargo sqlx prepare` (commitar `.sqlx/`) → `SQLX_OFFLINE=true cargo build` →
testes de integração → `cargo clippy --all-targets -D warnings` + `cargo fmt --check`.
Branch gitflow `feature/infrastructure-postgres` a partir de `dev`; commits sem
auto-referência ao Claude; comentários em pt-br.
