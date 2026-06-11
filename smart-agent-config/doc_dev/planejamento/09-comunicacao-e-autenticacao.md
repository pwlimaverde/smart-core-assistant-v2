# 09 — Comunicação Front↔Back, IPC e Encaixe da Autenticação

> **Status:** 🚧 Parcial. **Transporte** (IPC UDS/FlatBuffers + gRPC fallback, barramento,
> envelope) ✅ concluído. **Autenticação** 🚧: a infraestrutura de tokens está pronta e
> testada (Argon2id, rotação de refresh por família, blocklist por `jti`), mas o caso de
> uso de login emite **tokens mockados** (UUIDs) — a emissão de JWT real, `Refresh`/`Logout`
> e o middleware de contexto são o escopo da etapa F6.1–6.3 (detalhamento na §6).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular; revisado em jun/2026 após análise da base.

---

## 1. Topologia de Transporte de Dados

Na arquitetura modular reestruturada, a comunicação de dados ocorre em dois níveis distintos:

### 1.1 Comunicação Interna (IPC/RPC Local) — UDS & FlatBuffers
* **Protocolo**: Unix Domain Sockets (UDS) como transporte de baixíssima latência na máquina Hostinger.
* **Codec**: FlatBuffers como formato de serialização padrão para chamadas RPC aos microsserviços `data_*`.
* **Fallback**: gRPC sobre TCP configurável em tempo de execução para ambientes distribuídos ou depuração.
* **Mecanismo**: A crate `crates/transport` gerencia os clientes e servidores tipados que se comunicam através da serialização automatizada provida por `contracts`.

### 1.2 Comunicação Externa (Front↔Back) — gRPC & Streaming Realtime
* **Request-Response**: O cliente (Flutter) consome a `runtime_api` via HTTP/2 (gRPC padrão/Tonic). O gRPC-Web é suportado com proxy reverso (Nginx/Caddy) traduzindo chamadas para suporte do Flutter Web.
* **Realtime**: Padronizado em **gRPC Server Streaming**, onde o cliente abre canais persistentes (ex: `StreamAtendimentos`) e o servidor envia eventos em tempo real propagados internamente via Redis Streams (`transport::bus`).

---

## 2. JWT & Gerenciamento de Sessão

O sistema de autenticação opera de forma distribuída, desacoplando o servidor de APIs (`runtime_api`) e os serviços de armazenamento de dados síncronos (`data_redis`).

### 2.1 Estrutura de Metadados e o `Envelope`
Em vez de trafegar claims de segurança abertamente entre as APIs locais, o contexto de segurança validado no middleware da `runtime_api` é injetado no **`Envelope`** de transporte unificado:

O `Envelope` é definido em `contracts/schemas/envelope.proto` (gRPC + FlatBuffers). Campos
relevantes para o transporte do contexto de segurança:

```text
Envelope {
  tenant_id:      string   // UUID do tenant validado no interceptor
  schema_version: uint32   // versão do schema (evolução aditiva)
  message_id:     string   // UUIDv7 — ordenável e idempotente
  causation_id:   string   // id da mensagem que causou esta
  traceparent:    string   // W3C TraceContext (trace distribuído)
  occurred_at:    int64    // epoch em milissegundos
  kind:           MessageKind  // REQUEST | REPLY | EVENT | STREAM_ITEM | ERROR
  method:         string   // nome lógico do RPC (ex.: "GetThread")
  payload:        bytes    // corpo FlatBuffers (opaco ao transporte)
  error:          ErrorEnvelope  // só quando kind = ERROR
}
```

O `tenant_id` e as permissões de escopo (`scopes`) e fluxo (`flow_permissions`) são cacheados no Redis local via RPC ao `data_redis` com TTL curto (60 segundos).

### 2.2 Rotação de Refresh Tokens e Blocklist (via `data_redis`)
1. **Access Token (JWT)**: Vida útil de 15 minutos, stateless, verificado localmente.
2. **Refresh Token (Opaque)**: Token randômico de 32 bytes validado exclusivamente via RPC contra o microserviço `data_redis`. O `data_redis` gerencia de forma atômica a rotação de família de tokens e a detecção de reuso fraudulento.
3. **Logout & Invalidação**: O JWT correspondente tem seu identificador (`jti`) inserido na blocklist do Redis pelo tempo de expiração restante, e a família de refresh tokens é expurgada do `data_redis`.

---

## 3. Defesa em 3 Camadas e RLS

A segurança e o isolamento de dados são reforçados a cada chamada de banco:

```
[Cliente] --> |JWT gRPC Metadata| 1. Middleware Runtime API (Valida JWT e extrai Tenant)
                                   v
[Contratos UDS] ----------------> 2. Injeta RequestContext no Envelope (UDS / RPC)
                                   v
[PostgreSQL] -------------------> 3. SET LOCAL app.current_tenant = tenant_id (RLS PostgreSQL)
```

1. **Camada 1 (Interceptor gRPC)**: Valida a assinatura do token, checa a blocklist no `data_redis`, carrega escopos e monta o `RequestContext`.
2. **Camada 2 (Contratos IPC)**: Ao invocar os serviços de persistência (`data_postgres`), a `runtime_api` ou o `worker` envelopa a requisição com o `tenant_id` validado e o `traceparent`.
3. **Camada 3 (Postgres RLS)**: O microsserviço `data_postgres`, ao receber a chamada e abrir uma transação no pool de conexões SQLx, define obrigatoriamente a variável de sessão `app.current_tenant`, forçando o PostgreSQL a filtrar todas as queries via Row-Level Security.

---

## 4. Variáveis de Ambiente de Segurança

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `JWT_SECRET` | ✅ | — | Chave de assinatura criptográfica HMAC-SHA256. |
| `S3_ACCESS_KEY_ID` | ✅ | — | Credenciais S3 (Cloudflare R2) consumidas pelo `data_storage`. |
| `DATABASE_ADMIN_URL` | ✅ | — | Conexão com privilégios de bypass RLS para autenticação inicial. |
| `REDIS_URL` | ✅ | — | String de conexão com o Redis de cache e barramento. |

---

## 5. Estado real da autenticação (análise jun/2026)

Snapshot do que **já existe e está testado** versus o que é **placeholder** a substituir
na etapa de login. Serve de inventário de partida para a §6.

### 5.1 Pronto e testado (reaproveitar, não reescrever)

| Peça | Onde | Observação |
|---|---|---|
| Hash/verify Argon2id (sync + async via `spawn_blocking`) | `infrastructure_postgres/src/auth/password.rs` | usado pelo `VerifyCredentials` |
| Repositório `auth_user` (criar, buscar, desativar, último login) | `infrastructure_postgres/src/auth/users.rs` | tabela global sem RLS |
| `RefreshTokenStore` — rotação por família + detecção de reuso (`KEEPTTL`) | `infrastructure_redis/src/auth_tokens.rs` | reuso revoga a família inteira |
| `TokenBlocklist` por `jti` com TTL | `infrastructure_redis/src/auth_tokens.rs` | pronto para o logout |
| Rotas RPC no `data_redis` | `StoreRefreshToken`, `ValidateAndRotate`, `RevokeFamily`, `BlockToken`, `IsTokenBlocked` | todas implementadas |
| Rota RPC `VerifyCredentials` no `data_postgres` | valida senha, checa `is_active`, mitiga timing-oracle com hash dummy, audita `login_failed` | corrigida em jun/2026 |
| Cache de `flow_permissions` (TTL 60s) | `infrastructure_redis/src/cache.rs` + rotas `GetCache`/`SetCache` | para o interceptor |
| Bootstrap de superusuário | `control_plane create-superuser`/`delete-superuser` via RPC | com auditoria |

### 5.2 Placeholders a substituir na etapa de login

1. **Tokens mockados** — `application/src/auth/login.rs` gera `access_token` e
   `refresh_token` como UUIDs e um "hash" `format!("hash_{token}")` (derivável,
   sem proteção real). Substituir por JWT assinado + refresh opaco com SHA-256.
2. **`RequestContext` forjado** — todos os handlers do `data_postgres` montam
   contexto fixo (`user_id: 1`, escopos hardcoded). O contexto real virá do
   interceptor (Camada 1) propagado pelo `Envelope`.
3. **`RequestContext` duplicado** — existem dois tipos distintos:
   `application::RequestContext` (com `traceparent`) e
   `infrastructure_postgres::security::RequestContext` (com `flow_permissions`).
   Unificar (ou definir conversão única) antes do middleware.
4. **Sem `Refresh`/`Logout` na `runtime_api`** — hoje só existe a rota `Login`;
   o `data_redis` já suporta as operações, falta expor.
5. **Cliente RPC por requisição** — `login.rs` e o `worker` chamam
   `transport::conectar_cliente(...)` a cada chamada. O `MuxClient` é multiplexado
   e reconecta sozinho: criar **uma vez no boot** e compartilhar no estado do app.
6. **TTL fixo** — o TTL do refresh (86400s) está hardcoded; mover para env
   (`AUTH_REFRESH_TTL_S`, padrão 7 dias) junto do TTL do access token.

---

## 6. Especificação do Login real (etapas F6.1–6.3)

### 6.1 Formato dos tokens

**Access Token — JWT HS256** (`JWT_SECRET`), vida útil **15 minutos**, verificado
localmente no interceptor (sem RPC no caminho quente, exceto blocklist):

```json
{
  "sub": "42",                       // auth_user.id
  "tenant_id": "uuid-ou-vazio",      // vazio para superusuário (contexto global)
  "scopes": ["atendimentos:read"],   // catálogo canônico de escopos
  "is_superuser": false,
  "jti": "uuidv7",                   // id único p/ blocklist no logout
  "iat": 1750000000,
  "exp": 1750000900
}
```

**Refresh Token — opaco**: 32 bytes aleatórios (CSPRNG), codificado base64url,
**nunca armazenado em claro**: o `data_redis` guarda apenas o **SHA-256** do token,
associado a `user_id`, `tenant_id`, `family_id` e flag `rotacionado` (estrutura
`RegistroRefresh` já existente). TTL padrão **7 dias** (`AUTH_REFRESH_TTL_S`).

### 6.2 Fluxos RPC

**Login** (`runtime_api::Login` → orquestrado em `application::auth::login`):
1. `VerifyCredentials` no `data_postgres` (Argon2id + `is_active` + timing-safe).
2. Gera JWT (claims acima) + refresh opaco; calcula SHA-256 do refresh.
3. `StoreRefreshToken` no `data_redis` (`family_id` novo = UUID v7).
4. Devolve `{access_token, refresh_token, expires_in}`; `atualizar_ultimo_login`
   em background.

**Refresh** (`runtime_api::Refresh` — **novo**):
1. SHA-256 do refresh recebido → `ValidateAndRotate` no `data_redis`.
2. `NotFound` → 401; `TokenReuse` → família já revogada pelo store → 401 + evento
   de auditoria `token_reuse_detected` no `security:stream`.
3. Sucesso → emite novo par (JWT + refresh) **mantendo o `family_id`**;
   `StoreRefreshToken` do novo hash.

**Logout** (`runtime_api::Logout` — **novo**):
1. `BlockToken` do `jti` do access atual com TTL = tempo restante de expiração.
2. `RevokeFamily` da família do refresh (logout global do dispositivo/sessão).

### 6.3 Interceptor de autenticação (Camada 1)

Middleware na `runtime_api` aplicado a **todas** as rotas exceto `Login`/`Refresh`:
1. Extrai o JWT do metadata gRPC; valida assinatura e `exp` localmente.
2. Checa `jti` na blocklist (`IsTokenBlocked` via `data_redis`).
3. Monta o `RequestContext` **unificado** (tenant, user, scopes, flow_permissions
   com cache TTL 60s) e injeta `tenant_id` validado no `Envelope` — o cliente
   **nunca** define `tenant_id` (princípio: claims > body).
4. O `data_postgres` passa a montar o `RequestContext` dos handlers a partir do
   `Envelope` recebido (eliminando o contexto forjado da §5.2-2).

### 6.4 Critérios de aceite (DoD da etapa de login)

- [ ] JWT real emitido/validado; access expira em 15 min e refresh rotaciona.
- [ ] Reuso de refresh rotacionado revoga a família e audita o evento.
- [ ] Logout bloqueia o `jti` e revoga a família (verificável por `IsTokenBlocked`).
- [ ] Nenhum handler do `data_postgres` com `user_id`/escopos hardcoded.
- [ ] `RequestContext` único no workspace (ou conversão única documentada).
- [ ] Clientes RPC compartilhados no estado dos apps (sem `conectar_cliente` por request).
- [ ] Rate limiting de tentativas de login (por IP/email, via Redis).
- [ ] Testes: fluxo feliz, senha errada, usuário inativo, refresh expirado,
      reuso de refresh, logout + tentativa de uso do token bloqueado.

### 6.5 Variáveis de ambiente novas

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `JWT_SECRET` | ✅ | — | Chave HMAC-SHA256 do access token (≥ 32 bytes). |
| `AUTH_ACCESS_TTL_S` | ⬜ | `900` | Vida útil do access token (15 min). |
| `AUTH_REFRESH_TTL_S` | ⬜ | `604800` | Vida útil do refresh token (7 dias). |
| `AUTH_LOGIN_RATE_LIMIT` | ⬜ | `5/60s` | Tentativas de login por janela (por email+IP). |

---

## 7. Próximos Passos

A infraestrutura de transporte local (IPC UDS FlatBuffers), serialização e a segurança
por RLS com contexto integrado no `Envelope` estão concluídas e validadas. A ordem de
execução do restante é a da §6 (login real na `runtime_api`), seguida do interceptor
(§6.3) — pré-requisitos do painel admin (plano 11). A implementação do frontend Flutter
deve configurar interceptores gRPC compatíveis com o formato do `Envelope` para
autenticação (F6.5).


