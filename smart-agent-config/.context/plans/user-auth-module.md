---
status: in_progress
generated: 2026-06-02
slug: user-auth-module
scale: LARGE
artifacts:
  plano_completo: "./user-auth-module/plano_completo_user-auth-module.md"
  info_aux: "./user-auth-module/info_aux_user-auth-module.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo, transporte/sessão e contrato"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — contrato proto, modelo de token/JWT e pools"
    prevc: "R"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-e"
    name: "Execution — deps, JWT, refresh, application e runtime_api"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-v"
    name: "Validation — testes de integração dos 4 fluxos (PG + Redis)"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento dotcontext"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Módulo de Autenticação de Usuário — JWT + `runtime_api` gRPC

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/03-comunicacao-e-autenticacao.md`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./user-auth-module/plano_completo_user-auth-module.md`](./user-auth-module/plano_completo_user-auth-module.md)
- **Documentação auxiliar (libs + decisões):**
  [`./user-auth-module/info_aux_user-auth-module.md`](./user-auth-module/info_aux_user-auth-module.md)

## Objetivo

Implementar o **módulo de autenticação de usuário** da v2: emissão e validação de JWT (HS256),
ciclo de vida de sessão (access 15 min + refresh opaco 7 dias com rotação por família) e o
**primeiro ponto de entrada gRPC real** (`apps/runtime_api`) com `AuthInterceptor` que constrói o
`RequestContext`. Fecha a defesa-em-3-camadas (Interceptor JWT → escopos em Rust → RLS no
PostgreSQL) descrita no doc 03.

O módulo **consome** as fundações já entregues:
- `infrastructure_postgres` — `AuthUser`, `Tenant`, `TenantUser`, Argon2, RLS, `RequestContext`.
- `infrastructure_redis` — `RefreshTokenStore` (rotação + reuse-detection), `TokenBlocklist`,
  `CachePermissoes`.

**Escopo:** deps de workspace (`jsonwebtoken`, `sha2`, `base16ct`, `rand_core`, `tonic`, `prost`),
crate `contracts` (`auth.proto`), módulo JWT, geração/hash de refresh tokens, política de senha,
extensões em `infrastructure_postgres` (`criar_owner`, `criar_admin_pool`), rate limiting de login,
crate `application` (`AuthService`: Register/Login/RefreshToken/Logout/InviteUser/AcceptInvite),
app `runtime_api` (Tonic + interceptor) e scaffold de handshake WebSocket autenticado.

**Fora do escopo:** fan-out realtime completo (WebSocket pub/sub), seleção multi-tenant
(hoje 1-para-1), recuperação de senha, MFA, OAuth, envio real de e-mail de convite.

**Sinal de sucesso:** `cargo build` do workspace compila com os novos crates; os testes de
integração provam os fluxos Register/Login/Refresh(+reuse)/Logout/AcceptInvite contra PostgreSQL
(RLS) e Redis reais; interceptor rejeita JWT ausente/blocklisted (`unauthenticated`) e escopo
insuficiente (`permission_denied`); `cargo clippy -D warnings` e `cargo fmt --check` limpos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo, transporte/sessão e contrato | Backend Specialist | ✅ completed |
| **R** | Review — contrato proto, modelo de token/JWT e pools | Backend Specialist (+ Security Auditor) | ⬜ pending |
| **E** | Execution — deps, JWT, refresh, application e `runtime_api` | Backend Specialist | ⬜ pending |
| **V** | Validation — testes de integração dos 4 fluxos (PG + Redis) | Test Writer (+ Backend Specialist) | ⬜ pending |
| **C** | Confirmation — final-review e arquivamento dotcontext | Backend Specialist | ⬜ pending |

## Decisões-chave (resumo — detalhes no plano completo)

1. **Transporte gRPC (tonic 0.14) + WebSocket (axum)** — gRPC para comandos/consultas; WS para
   realtime. Auth no handshake via `Authorization: Bearer` ou `?token=` (token curto, logs
   anonimizados).
2. **JWT HS256** com claims incluindo `iat`, `jti` (blocklist) e `family_id` (revogação de família
   no logout). Chaves via `std::sync::OnceLock`.
3. **Refresh token opaco** — `rand_core::OsRng` 32 bytes → base64url; só o **hash SHA-256** toca o
   Redis. Rotação por família com reuse-detection (já em `infrastructure_redis`).
4. **Multi-tenant 1-para-1** resolvido automaticamente no login (`UNIQUE(user_id)`); superuser →
   `tenant_id = null`.
5. **Pool admin (BYPASSRLS)** isolado (`DATABASE_ADMIN_URL`) só para lookups pré-tenant; novo
   helper `criar_admin_pool`.
6. **Bootstrap de cadastro** — `TenantUserRepository::criar_owner` sem `RequestContext` (o `criar`
   existente exige `tenant:admin`).
7. **Erros → `tonic::Status`** na borda; `AuthError` (thiserror) interno, sem vazar detalhe ao
   cliente.

## Correções aplicadas vs. plano base (doc 03)

`rand::OsRng`→`rand_core 0.6`; `tonic`/`prost` fixados em 0.14; adicionado `criar_admin_pool`
(GAP real — só existia `criar_pool`); hash via `sha2`+`base16ct`; `OnceLock` em vez de
`once_cell`/`lazy_static`; `criar_owner` separado de `criar`; `iat`+`family_id` nas claims;
`AcceptInvite` como rota pública. Detalhe completo na seção "Correções aplicadas" do plano completo.

## Verificação

`docker compose -f docker/compose/data.yml up -d` → exportar `JWT_SECRET`, `DATABASE_URL`,
`DATABASE_ADMIN_URL`, `REDIS_URL` → `cargo build` → `RUST_TEST_THREADS=1 cargo test -p application
-p infrastructure_postgres -p infrastructure_redis` → `cargo clippy --all-targets -D warnings` +
`cargo fmt --check`. Branch `claude/user-auth-module-plan-dykMV` a partir de `dev`; commits sem
auto-referência ao modelo; comentários em pt-br.
