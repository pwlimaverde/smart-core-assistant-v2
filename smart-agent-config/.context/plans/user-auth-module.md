---
status: in_progress
generated: 2026-06-02
updated: 2026-06-12
slug: user-auth-module
scale: LARGE
artifacts:
  plano_completo: "./user-auth-module/plano_completo_user-auth-module.md"
  info_aux: "./user-auth-module/info_aux_user-auth-module.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo real, inventário e decisões fechadas"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — Envelope aditivo, RequestContext único, escopos e contratos"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — JWT/refresh, Login/Refresh/Logout, interceptor e rotas admin de config"
    prevc: "E"
    agent: "backend-specialist"
    status: "in_progress"
  - id: "phase-v"
    name: "Validation — testes de integração (auth + admin) com túnel automático"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — final-review e arquivamento dotcontext"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Login Real + Rotas Admin de Configuração — `user-auth-module`

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> **Reestruturado em 2026-06-12** pela skill `plan-restructuring` contra o estado real do
> código (pós-refatoração modular), a partir de `doc_dev/planejamento/09-comunicacao-e-autenticacao.md`
> §5–6 e do subconjunto "configurações" de `doc_dev/planejamento/11-painel-admin-superusuario.md`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./user-auth-module/plano_completo_user-auth-module.md`](./user-auth-module/plano_completo_user-auth-module.md)
- **Documentação auxiliar (inventário do código + libs):**
  [`./user-auth-module/info_aux_user-auth-module.md`](./user-auth-module/info_aux_user-auth-module.md)

## Objetivo

Substituir os **mocks de autenticação** por tokens reais e expor as **rotas admin de
configuração**, deixando o backend **pronto para plugar o app Windows (Flutter) de
configuração do superusuário** (cadastro de prompts e chaves usadas dinamicamente pelos
tenants — equivalente do `service_hub`/`settings_manager` da v1). O Flutter fica fora de
escopo (plano 11); o critério é "backend pronto para plugar" via `runtime_api`.

**Escopo (doc 09 §6 + subconjunto config do doc 11):**
1. **Login real** — JWT HS256 (claims §6.1), refresh opaco 32B + SHA-256, TTLs via env
   (`AUTH_ACCESS_TTL_S`/`AUTH_REFRESH_TTL_S`), rate limiting, `MuxClient` compartilhado no boot.
2. **Refresh/Logout** — novas rotas na `runtime_api` sobre `ValidateAndRotate`/`RevokeFamily`/
   `BlockToken`; auditoria de `token_reuse_detected`.
3. **Interceptor (Camada 1)** — wrapper de handler sobre o `transport` próprio (não tonic):
   valida JWT, checa blocklist, sobrescreve `tenant_id` do Envelope (claims > body); guard
   `is_superuser` nas rotas admin.
4. **RequestContext unificado** — extensão **aditiva** do `envelope.proto` (identidade);
   `data_postgres` monta contexto do Envelope e elimina os 4 contextos forjados.
5. **Rotas admin de config** — CRUD de `CoreSettings` + `Get/UpdateTenantConfig` (cifra
   AES-256-GCM, leitura mascarada, invalidação do `TenantConfigCache`, auditoria).

**Fora de escopo:** frontend Flutter; CRUD de tenants/planos/assinaturas/pagamentos
(plano 11); Register/Invite (cadastro via `control_plane create-superuser`); MFA/OAuth;
recuperação de senha; fan-out realtime.

**Sinal de sucesso (DoD, doc 09 §6.4):** JWT real emitido/validado; refresh rotaciona e
reuso revoga a família com auditoria; logout bloqueia `jti`; nenhum handler com contexto
forjado; `RequestContext` único; clientes RPC compartilhados; rate limiting ativo; rotas
admin de config funcionais com superuser e rejeitadas sem; testes de integração dos fluxos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo real, inventário e decisões fechadas | Backend Specialist | ✅ completed |
| **R** | Review — Envelope aditivo, RequestContext único, escopos e contratos | Architect Specialist (+ Security Auditor) | ✅ completed |
| **E** | Execution — JWT/refresh, Login/Refresh/Logout, interceptor e rotas admin | Backend Specialist | 🔄 in_progress (falta rate limiting) |
| **V** | Validation — testes de integração (auth + admin) | Test Writer (+ Backend Specialist) | ⬜ pending |
| **C** | Confirmation — final-review e arquivamento dotcontext | Backend Specialist | ⬜ pending |

## Decisões-chave (resumo — detalhes no plano completo)

1. **Borda = `transport` próprio** (UDS/FlatBuffers + fallback gRPC); interceptor é
   **wrapper de handler**, não `tonic::Interceptor` nem middleware global.
2. **Claims do doc 09 §6.1** (`sub`, `tenant_id`, `scopes`, `is_superuser`, `jti`, `iat`,
   `exp`); `family_id` vive só no `RefreshTokenStore`, não nas claims.
3. **Banco tem uma porta:** `data_postgres` via RPC — sem pool de Postgres na
   `runtime_api`/`application` (descartado `criar_admin_pool` na borda).
4. **Envelope estendido aditivamente** (`auth_user_id`, `auth_scopes`, `auth_is_superuser`)
   para propagar identidade validada da Camada 1 às camadas internas.
5. **`RequestContext` canônico = o de `infrastructure_postgres`** (tem `exigir_qualquer`
   e `flow_permissions`); o da `application` converge para ele.
6. **`rand_core 0.6` `OsRng`** (estável, transitivo via `argon2`) em vez de `rand 0.10`.
7. **Config dinâmica reusa a fundação pronta** (`settings.rs`, `config.rs`,
   `config_cache.rs`, `crypto.rs`) — só expõe via RPC com máscara e invalidação de cache.

## Correções aplicadas vs. plano anterior (resumo)

Descartados: servidor Tonic dedicado na borda, Register/Invite/AcceptInvite, pools diretos
na `application`, `criar_admin_pool`, WebSocket Axum, upgrade desnecessário de prost.
Alinhados ao código real: `MuxClient` no boot, claims §6.1, Envelope aditivo, contexto
forjado eliminado (linhas 427/491/889/994 do `data_postgres`), rotas admin de config sobre
infra existente. GAPs reais identificados: `VerifyCredentials` não devolve `tenant_id`
(estender reply), `DeleteCoreSetting` inexistente, catálogo de escopos a fechar na fase R.
Detalhe completo na seção "Correções aplicadas" do plano completo.

## Verificação

Túnel/test_support automático nos testes → exportar `JWT_SECRET`, `AUTH_ACCESS_TTL_S`,
`AUTH_REFRESH_TTL_S`, `ENCRYPTION_KEY`, `DATABASE_URL`, `REDIS_URL` → `cargo build` →
`cargo test -p application -p data_postgres -p data_redis -p runtime_api` (SQLX_OFFLINE) →
`cargo clippy --all-targets -D warnings` + `cargo fmt --check`. Branch `feature/*` a partir
de `dev` (gitflow); commits sem auto-referência ao modelo; comentários em pt-br.
