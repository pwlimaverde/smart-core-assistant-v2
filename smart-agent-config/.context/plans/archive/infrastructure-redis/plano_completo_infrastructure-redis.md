# Plano Completo — Fundação `infrastructure_redis`

> Verdade técnica detalhada da crate de cache/barramento. Reestruturado a partir de
> `doc_dev/planejamento/04-infraestrutura-redis.md` e validado contra a central de libs
> (`doc_dev/libs/rust/`) e contra o **código já implementado e testado**. Idioma: pt-br;
> identificadores em inglês, verbos de função em pt-br (`criar_*`, `publicar_*`, `consumir_*`),
> espelhando `infrastructure_postgres`.

## Escopo

**Dentro do escopo (implementado nesta entrega):**
- Conexão Redis via `ConnectionManager` (+ `ping`), lendo `REDIS_URL`; helper de cliente dedicado
  para fluxos bloqueantes/pubsub.
- Namespacing obrigatório por tenant (`tenant:<uuid>:<recurso>:<chave>`) e prefixo `auth:` para
  chaves globais de autenticação.
- **Auth (driver imediato):** refresh tokens com rotação e detecção de reuso por família;
  blocklist de access tokens por `jti`; cache de `flow_permissions` (TTL curto).
- **Event bus (Etapa 3.3):** Redis Streams + consumer groups com `TenantEnvelope`
  (publicar / consumir / confirmar / reprocessar pendentes).
- Erro único `RedisError` (thiserror); `TenantEnvelope<T>` com `event_id` UUID v7.
- Testes de integração contra Redis real (banco lógico 15).

**Fora do escopo (fases futuras — ver §FASES e tabela do canônico):** pub/sub de invalidação de
config e cache `tenant:config:{id}`; fan-out realtime por tenant (WebSocket); lock de debounce por
contato; delayed tasks (sorted-set por ETA); presença/typing. O **módulo de auth** (cadastro/login +
JWT) é plano separado e consome esta fundação.

## Arquitetura (invariantes obrigatórias)

1. **Crate única de Redis.** Nenhuma outra crate importa o cliente `redis` diretamente.
2. **`ConnectionManager`** (multiplexado, `Clone`, reconexão) para comandos; **conexão dedicada**
   (`criar_cliente` → `get_async_connection`/`get_async_pubsub`) para `XREADGROUP BLOCK`/pubsub.
3. **Namespacing por tenant** em toda chave de cache; chaves de auth com prefixo `auth:`
   (o `tenant_id` viaja dentro do registro, nunca como fonte de verdade de fora).
4. **Erro único por crate:** `RedisError` (thiserror), espelhando `DbError`.
5. **Sem `unwrap()/expect()` em produção;** uso de `?`/`Result`. Comentários em pt-br.
6. **Envelope obrigatório** para eventos: `TenantEnvelope<T>` com `tenant_id` na raiz e `event_id`
   UUID v7 (ordenável/idempotente).
7. **Segredos nunca em claro no Redis:** refresh tokens são gravados apenas como **hash**.

---

# FASES (mapeadas ao PREVC)

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo do cache/barramento e decisões | Backend Specialist | ✅ completed |
| **R** | Review — chaves, envelope e segurança de tokens | Backend Specialist (+ Security Reviewer) | ✅ completed |
| **E** | Execution — crate `infrastructure_redis` | Backend Specialist | ✅ completed |
| **V** | Validation — testes de integração contra Redis real | Test Writer (+ Backend Specialist) | ✅ completed |
| **C** | Confirmation — registro e arquivamento | Backend Specialist | ✅ completed |

## FASE P — Planning (Backend Specialist)

- Definir o papel da crate (cache + barramento + primitivas de auth) e o recorte de escopo
  ("Incluir event bus", excluir realtime/config-cache/debounce para fases futuras).
- Decidir o transporte que motiva a auth (gRPC + WebSocket; refresh em Redis) — registrado em
  `doc_dev/planejamento/03-comunicacao-e-autenticacao.md`.
- Saídas: `04-infraestrutura-redis.md` (registro) + este plano completo + `info_aux`.

## FASE R — Review (Backend Specialist + Security Reviewer)

- Validar modelo de chaves (namespacing por tenant; `auth:` global) contra
  `doc_dev/libs/rust/redis.md` §Envelopamento e diretrizes de segurança.
- Revisar a segurança dos refresh tokens: somente hash no Redis; rotação com reuse-detection por
  família; blocklist por `jti` com TTL = vida restante do access token.
- Confirmar idempotência do event bus (UUID v7, MAXLEN aproximado, `BUSYGROUP` tolerado).

## FASE E — Execution (Backend Specialist)

### (a) Workspace
- `server/Cargo.toml`: adicionar `crates/infrastructure_redis` aos `members`; `redis` em
  `[workspace.dependencies]` com features `aio, tokio-comp, connection-manager, streams`; somar a
  feature `v7` ao `uuid` (aditivo — `infrastructure_postgres` segue compilando).
- `server/crates/infrastructure_redis/Cargo.toml`: deps `redis, serde, serde_json, chrono, uuid,
  thiserror, tracing` (workspace) + dev-dep `tokio` (`macros`, `rt-multi-thread`).

### (b) Módulos (`src/`)

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Conexão e health | `criar_conexao_redis()`, `criar_conexao_com_url(url)`, `criar_cliente(url)`, `ping(con)` |
| `errors.rs` | Erro único | `RedisError { Redis, Serde, ConfigError, NotFound, TokenReuse }` |
| `keys.rs` | Namespacing | `chave_tenant`, `chave_flow_permissions`, `chave_refresh`, `chave_refresh_familia`, `chave_blocklist` |
| `envelope.rs` | Contrato de evento | `TenantEnvelope<T>` + `TenantEnvelope::novo(...)` (UUID v7) |
| `cache.rs` | Cache de permissões | `CachePermissoes::{definir,obter,invalidar}_flow_permissions`; `TTL_FLOW_PERMISSIONS_SEGUNDOS=60` |
| `auth_tokens.rs` | Tokens de auth | `RefreshTokenStore`, `TokenBlocklist`, `RegistroRefresh` |
| `event_bus.rs` | Streams | `publicar_evento`, `garantir_consumer_group`, `consumir`, `reprocessar_pendentes`, `confirmar`, `EventoBruto` |
| `lib.rs` | Re-exports | declara módulos e reexporta os tipos/funções públicos |

### (c) Modelo de chaves

| Recurso | Chave | TTL | Observação |
|---|---|---|---|
| flow_permissions | `tenant:{tenant_id}:flow_permissions:{user_id}` | 60s | JSON `[i32]`; curto p/ refletir revogação sem esperar o JWT |
| refresh token | `auth:refresh:{token_hash}` | vida do refresh | guarda `RegistroRefresh`; só o **hash** toca o Redis |
| família de refresh | `auth:refresh_family:{family_id}` | renovado a cada token | Set com os hashes da família (revogação em massa) |
| blocklist (logout) | `auth:blocklist:{jti}` | tempo restante do access | valor `"1"` |
| event bus | `events:stream` (Stream) | MAXLEN ~10.000 | stream único; segregação lógica por `tenant_id` no envelope |

### (d) Fluxos detalhados

**Refresh tokens (`auth_tokens.rs`):**
- `armazenar(token_hash, user_id, tenant_id, family_id, ttl)` grava `RegistroRefresh`
  (`rotacionado=false`) e indexa o hash na família.
- `validar_e_rotacionar(token_hash)`: inexistente/expirado/revogado → `NotFound`; já rotacionado
  (reuso) → revoga a família inteira e retorna `TokenReuse`; válido → marca `rotacionado=true`
  preservando TTL (`SET ... KEEPTTL`) e retorna o registro original para o caller emitir novo par
  na mesma família.
- `revogar(token_hash)` e `revogar_familia(family_id)` (logout global / resposta a reuso).
- Premissa: geração do token aleatório e hashing (ex.: SHA-256) ficam na camada de auth.

**Blocklist (`auth_tokens.rs`):** `bloquear(jti, ttl)` com `ttl` = vida restante do access token;
`esta_bloqueado(jti)` consultado pelo interceptor a cada requisição.

**Cache de `flow_permissions` (`cache.rs`):** `definir_flow_permissions(tenant, user, &[i32],
ttl=60)` na emissão; `obter_flow_permissions` no interceptor (miss → recarrega do Postgres);
`invalidar` ao mudar permissões.

**Event bus (`event_bus.rs`):** `publicar_evento` → `XADD events:stream MAXLEN ~ 10000 *`
(`event_id` UUID v7 como campo); `garantir_consumer_group` → `XGROUP CREATE ... $ MKSTREAM`
(idempotente, ignora `BUSYGROUP`); `consumir` → `XREADGROUP ... >` (`block_ms>0` ativa modo
bloqueante, conexão dedicada); `reprocessar_pendentes` → `XREADGROUP ... 0` (replay do PEL);
`confirmar` → `XACK`; `EventoBruto::desserializar::<T>()` reconstrói o envelope tipado.

### (e) `lib.rs` / exports
- Declara `auth_tokens, cache, connection, envelope, errors, event_bus, keys` e reexporta:
  `RefreshTokenStore, RegistroRefresh, TokenBlocklist, CachePermissoes,
  TTL_FLOW_PERMISSIONS_SEGUNDOS, criar_cliente, criar_conexao_com_url, criar_conexao_redis, ping,
  TenantEnvelope, RedisError`, as funções de `event_bus` e de `keys`.

## FASE V — Validation (Test Writer + Backend Specialist)

- Integração contra Redis real no **banco lógico 15** (`REDIS_URL` + `/15`), com `FLUSHDB` por
  execução e `RUST_TEST_THREADS=1`. Helpers em `tests/common/mod.rs`
  (`carregar_env_teste`, `url_redis_teste`, `conexao_limpa`).
- Cobertura (8 testes de integração + 2 unit): rotação de refresh válido; reuso → revogação da
  família; `NotFound`; blocklist (`jti`); cache de flow_permissions (gravar/ler/invalidar);
  event bus (publicar→consumir→confirmar e replay de pendentes); display de `RedisError`; chaves.
- Comandos: `cargo test -p infrastructure_redis`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check`. **Resultado: 10/10 verdes.**

## FASE C — Confirmation (Backend Specialist)

- `.env.example` (raiz e `server/`) com `REDIS_URL` e nota do banco lógico 15.
- Registro em `doc_dev/planejamento/04-infraestrutura-redis.md` e canonização dotcontext (este
  conjunto de artefatos). Commits em inglês, sem auto-referência ao modelo; comentários em pt-br.

---

## Correções aplicadas

> Itens validados contra a central de libs (todas `✅ ATUALIZADA`) e contra o build/testes reais.
> Como a crate já estava implementada, estas são as decisões consolidadas (não reescritas).

1. **`uuid` feature `v7`** somada às existentes (`v4`, `serde`) — `Uuid::now_v7()` para `event_id`
   ordenável. Mudança **aditiva**: `infrastructure_postgres` recompila sem alteração. *(Cargo.toml)*
2. **`redis` 0.25.0** com features exatas `aio, tokio-comp, connection-manager, streams` — bate com
   a central (`redis.md`, verif. 2026-05-31). *(workspace.dependencies)*
3. **`XADD ... MAXLEN ~ 10000`** (aproximado) em vez de trim exato — evita custo por escrita.
4. **`BUSYGROUP` tolerado** via `e.code() == Some("BUSYGROUP")` em `garantir_consumer_group` —
   idempotência do `XGROUP CREATE`.
5. **`SET ... KEEPTTL`** na rotação do refresh — preserva o TTL ao marcar `rotacionado=true`,
   em vez de regravar com TTL recalculado.
6. **Conexão dedicada para `BLOCK`** documentada na assinatura de `consumir(..., block_ms)` —
   evita travar a conexão multiplexada do `ConnectionManager`.
7. **Apenas hash do refresh token no Redis** — token em claro nunca é persistido; reuse-detection
   por família.

## Verificação end-to-end

```bash
# 1. Subir Redis local (ou via túnel/docker compose data.yml)
redis-server --port 6380 --requirepass SENHA --daemonize yes --save '' --appendonly no

# 2. Configurar REDIS_URL (server/.env): redis://:SENHA@localhost:6380
#    Os testes anexam o banco lógico 15 automaticamente.

# 3. Build da crate
cargo build -p infrastructure_redis

# 4. Testes de integração (Redis real, DB lógico 15, FLUSHDB por execução)
RUST_TEST_THREADS=1 cargo test -p infrastructure_redis

# 5. Garantir que infrastructure_postgres segue compilando (uuid v7 é aditivo)
SQLX_OFFLINE=true cargo build -p infrastructure_postgres

# 6. Lint e formatação
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

Branch de desenvolvimento: `claude/user-auth-module-plan-dykMV` (a partir de `dev`); commits sem
auto-referência ao modelo; comentários em pt-br.
