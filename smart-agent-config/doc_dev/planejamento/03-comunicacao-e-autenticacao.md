# 03 — Comunicação Front↔Back e Encaixe da Autenticação

> Análise de referência para retomar o módulo de cadastro/login + JWT. Status: **parado/aguardando**
> a fundação Redis (`infrastructure_redis`) e as decisões em aberto ao final deste documento.

## 1. Transporte Front↔Back (NÃO é HTTP/REST)

- **Comandos/consultas:** **gRPC (tonic)**. A doc original lista "gRPC/HTTP" e registrava em
  *Decisões em aberto* "gRPC vs REST+WS"; ficou definido **gRPC** (não-HTTP).
- **Realtime (push):** **WebSocket**, com fan-out por tenant via Redis (nova mensagem, typing,
  presença, leitura, mudança de etapa, resposta da IA, atualização do Kanban).
- **Binário terminador:** `runtime_api` (ainda **não existe** na `dev`; é a Fase 6). É ele que
  fala gRPC (comandos) e WebSocket (realtime).
- **Desktop (Windows):** usa `local_engine` via **FFI (flutter_rust_bridge)** apenas como
  cache/performance — "o FFI é camada de desempenho, não a fonte da verdade". **Login e token
  nunca passam pelo FFI**; autenticação é sempre no servidor, pela rede. **Web = `RemoteOnly`.**

## 2. Onde a autenticação se encaixa

- Token vai em **metadata/headers** `Authorization: Bearer <JWT>`. Em gRPC isso é um
  **interceptor tonic** (equivalente ao middleware Axum dos exemplos da doc). O **WebSocket valida
  o JWT no handshake**.
- **Defesa em 3 camadas:**
  1. Interceptor/middleware: valida assinatura **HS256**, extrai claims, monta `RequestContext`,
     carrega `flow_permissions` do **Redis** (TTL ~60s, fora do JWT, para refletir revogação sem
     esperar expiração).
  2. Repositório (Rust): checa `has_permission`/`has_flow_permission` (fail-fast).
  3. Banco: RLS via `SELECT set_config('app.current_tenant', $1, true)` (`SET LOCAL`).
- **Regra dura:** `tenant_id` vem **exclusivamente das claims assinadas** — nunca do corpo/query.
- **`JWT_SECRET`** carregado **uma única vez no startup** (estado da app), nunca por requisição.
- **Claims:** `{ sub: user_id, tenant_id: uuid|null, scopes: [...], exp }`.
  Superuser → `tenant_id = null`, `scopes = ["system:admin"]`.

## 3. O que já existe na ponte (`infrastructure_postgres`)

- Argon2id (`auth/password.rs`: `hash_password`/`verify_password`).
- `auth_user` global sem RLS (`auth/users.rs`): `criar`, `buscar_por_username/email/id`,
  `atualizar_ultimo_login`, `atualizar_senha`, `desativar`.
- `TenantUser` (role + `module_permissions` + `flow_permissions`), `TenantInvite` (token),
  `Tenant` (owner) em `tenants/tenants.rs`. Lookups cross-tenant exigem **admin pool** (BYPASSRLS).
- `RequestContext` (`security.rs`): `tenant_id`, `user_id`, `user_scopes`, `flow_permissions`.

## 4. RBAC (de 09_diretrizes_permissoes_acesso.md)

- Catálogo de scopes (`system:admin`, `tenant:admin`, `clientes:read/write`, `atendimentos:read/write`,
  `treinamento:read/write`, `operacional:read/admin`, `financeiro:read/write`, `configuracoes:read/write`,
  `kanban:admin`).
- Mapa role→scopes na emissão do JWT: `admin`→`tenant:admin`; `manager`→reads+writes exceto
  `financeiro:write`/`configuracoes:write`; `staff`→`clientes:read`+`atendimentos:read/write`;
  `viewer`→apenas `*:read`.

## 5. Fluxos previstos

- **Cadastro (owner):** cria `auth_user` → cria `tenants_tenant` (owner_id) → cria `tenants_tenantuser`
  (role=admin) → emite JWT.
- **Login:** `buscar_por_username/email` (admin pool) → `verify_password` → `atualizar_ultimo_login`
  → resolve tenant → emite access (HS256, curto) + refresh (**no Redis**).
- **Aceite de convite:** valida `tenants_tenantinvite` (admin pool, não expirado, não usado) →
  cria `auth_user` + `tenants_tenantuser` → marca convite usado (transação) → emite JWT.
- **Logout:** blocklist do JWT no Redis.

## 6. Decisões em aberto (resolver ao retomar)

- **Escopo da entrega do auth:** (A) camada de serviço + JWT; ou (B) camada + `runtime_api` mínimo
  expondo só o `AuthService` (gRPC Login/Register/Refresh/Logout) + interceptor.
- **Resolução multi-tenant no login** (um `auth_user` pode pertencer a vários tenants): auto +
  seleção quando >1; dois passos sempre; ou um tenant por enquanto.
- **Senha:** confirmar parâmetros do Argon2 (default atual) e política de força.

## 7. Decisões já tomadas

- Transporte: gRPC + WebSocket (não-HTTP). Refresh tokens: **Redis**. Senhas: Argon2id.
  Namespacing Redis: `tenant:<uuid>:<recurso>:<chave>`.

## 8. Próximo passo

Implementar a fundação **`infrastructure_redis`** (refresh tokens, blocklist, cache de
`flow_permissions`, event bus), depois retomar este módulo de auth a partir das decisões da seção 6.
