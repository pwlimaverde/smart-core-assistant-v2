# 04 — Infraestrutura Redis (`infrastructure_redis`)

> **Histórico.** Este documento foi canonizado pela skill `plan-restructuring` para o dotcontext.
> A fonte da verdade passa a ser o plano canônico em
> `.context/plans/archive/infrastructure-redis/infrastructure-redis.md` (+ `plano_completo` e
> `info_aux` na mesma pasta). Mantido aqui como registro original.

> Registro de planejamento do crate de cache/barramento. Documenta a arquitetura, o que está
> implementado nesta entrega e o que fica para fases futuras. Idioma: pt-br; identificadores e
> nomes de função seguem o estilo do `infrastructure_postgres` (verbos em pt-br: `criar_*`,
> `publicar_*`, `consumir_*`).

## 1. Objetivo

Centralizar **todo** o acesso ao Redis em uma única crate (`server/crates/infrastructure_redis`),
análoga à ponte `infrastructure_postgres`. O Redis é o coração de sincronização assíncrona da v2:
barramento de eventos (Streams), cache de baixa latência e suporte à autenticação (refresh tokens
e blocklist). Esta crate é a **única** do workspace que fala com o cliente Redis.

## 2. Escopo

**Implementado nesta entrega:**
- Conexão (`ConnectionManager`) + `ping`, lendo `REDIS_URL`.
- Namespacing obrigatório por tenant (`tenant:<uuid>:<recurso>:<chave>`).
- **Auth (driver imediato):** refresh tokens com rotação e detecção de reuso por família;
  blocklist de access tokens (jti); cache de `flow_permissions` (TTL curto).
- **Event bus (Etapa 3.3):** Redis Streams + consumer groups com `TenantEnvelope`
  (publicar / consumir / confirmar / reprocessar pendentes).
- Testes de integração contra Redis real (banco lógico 15).

**Fora desta entrega (fases futuras — ver §9):** pub/sub de invalidação de config e cache
`tenant:config:{id}`; fan-out realtime por tenant (WebSocket); lock de debounce por contato;
delayed tasks (sorted-set por ETA); presença/typing.

## 3. Arquitetura e decisões

1. **Crate única de Redis.** Nenhuma outra crate importa o cliente `redis` diretamente.
2. **Cliente:** `redis = 0.25` com `ConnectionManager` (multiplexado, `Clone`, reconexão
   automática) para comandos. Para loops **bloqueantes** (`XREADGROUP` com `BLOCK`) ou pub/sub,
   usar conexão **dedicada** (`criar_cliente` → `get_async_connection`/`get_async_pubsub`), pois
   comandos bloqueantes travam uma conexão multiplexada.
3. **Namespacing por tenant** em toda chave de cache: `tenant:<uuid>:<recurso>:<chave>`. Chaves de
   auth usam prefixo `auth:` (precedem a seleção de tenant; o `tenant_id` vai dentro do registro).
4. **Erro único por crate:** `RedisError` (via `thiserror`), espelhando o padrão de `DbError`.
5. **Sem `unwrap()/expect()` em produção;** uso de `?`/`Result`. Comentários em pt-br.
6. **Envelope obrigatório** para eventos: `TenantEnvelope<T>` com `tenant_id` na raiz e `event_id`
   UUID v7 (ordenável/idempotente). Quando existir a crate `contracts`, o tipo migra para lá.

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Conexão e health | `criar_conexao_redis()`, `criar_conexao_com_url(url)`, `criar_cliente(url)`, `ping(con)` |
| `errors.rs` | Erro único | `RedisError { Redis, Serde, ConfigError, NotFound, TokenReuse }` |
| `keys.rs` | Namespacing | `chave_tenant`, `chave_flow_permissions`, `chave_refresh`, `chave_refresh_familia`, `chave_blocklist` |
| `envelope.rs` | Contrato de evento | `TenantEnvelope<T>` + `TenantEnvelope::novo(...)` |
| `cache.rs` | Cache de permissões | `CachePermissoes::{definir,obter,invalidar}_flow_permissions`, `TTL_FLOW_PERMISSIONS_SEGUNDOS=60` |
| `auth_tokens.rs` | Tokens de auth | `RefreshTokenStore`, `TokenBlocklist`, `RegistroRefresh` |
| `event_bus.rs` | Streams | `publicar_evento`, `garantir_consumer_group`, `consumir`, `reprocessar_pendentes`, `confirmar`, `EventoBruto` |

## 5. Modelo de chaves

| Recurso | Chave | TTL | Observação |
|---|---|---|---|
| flow_permissions | `tenant:{tenant_id}:flow_permissions:{user_id}` | 60s | JSON `[i32]`; curto p/ refletir revogação sem esperar o JWT |
| refresh token | `auth:refresh:{token_hash}` | vida do refresh | guarda `RegistroRefresh`; só o **hash** do token toca o Redis |
| família de refresh | `auth:refresh_family:{family_id}` | renovado a cada token | Set com os hashes da família (revogação em massa) |
| blocklist (logout) | `auth:blocklist:{jti}` | tempo restante do access | valor `"1"` |
| event bus | `events:stream` (Stream) | MAXLEN ~10.000 | um único stream; segregação lógica por `tenant_id` no envelope |

## 6. Fluxos detalhados

### 6.1 Refresh tokens (rotação + detecção de reuso)
- **Emitir:** `armazenar(token_hash, user_id, tenant_id, family_id, ttl)` grava o `RegistroRefresh`
  (`rotacionado=false`) e indexa o hash na família.
- **Renovar:** `validar_e_rotacionar(token_hash)`:
  - inexistente/expirado/revogado → `NotFound`;
  - já rotacionado (**reuso**) → revoga a **família inteira** e retorna `TokenReuse`;
  - válido → marca `rotacionado=true` preservando o TTL (`SET ... KEEPTTL`) e retorna o registro
    original para o caller emitir um novo par na mesma família.
- **Revogar:** `revogar(token_hash)` (um token) e `revogar_familia(family_id)` (logout global /
  resposta a reuso).
- **Premissa:** a geração do token aleatório e o seu hashing (ex.: SHA-256) ficam na camada de
  auth; o Redis nunca vê o token em claro.

### 6.2 Blocklist de access token
- `bloquear(jti, ttl)` com `ttl` = tempo restante de vida do access token; `esta_bloqueado(jti)`
  consultado pelo interceptor/middleware a cada requisição.

### 6.3 Cache de `flow_permissions`
- `definir_flow_permissions(tenant, user, &[i32], ttl=60)` na emissão; `obter_flow_permissions`
  no interceptor (cache miss → recarrega do Postgres); `invalidar` ao mudar permissões.

### 6.4 Event bus (Streams + consumer groups)
- `publicar_evento(con, &TenantEnvelope<T>)`: `XADD events:stream MAXLEN ~ 10000 *` — o ID do
  stream é atribuído pelo Redis; o `event_id` (UUID v7) viaja como campo para idempotência.
- `garantir_consumer_group(con, grupo)`: `XGROUP CREATE ... $ MKSTREAM` (idempotente; ignora
  `BUSYGROUP`).
- `consumir(con, grupo, consumidor, qtd, block_ms)`: `XREADGROUP ... >`; `block_ms>0` ativa modo
  bloqueante (use conexão dedicada).
- `reprocessar_pendentes(con, grupo, consumidor, qtd)`: `XREADGROUP ... 0` relê o PEL do
  consumidor (replay após falha/reinício).
- `confirmar(con, grupo, stream_id)`: `XACK`.
- `EventoBruto::desserializar::<T>()` reconstrói o `TenantEnvelope<T>` tipado.

## 7. Configuração e ambiente

- **Variável:** `REDIS_URL` (ex.: `redis://:SENHA@localhost:6380`). Já presente no `.env.example` da
  raiz e adicionada ao `server/.env.example`.
- **Docker:** serviço `redis:7-alpine` já definido em `docker/compose/data.yml` (requirepass, AOF,
  maxmemory 150mb / `allkeys-lru`). Sem mudança de infra.
- **Workspace:** `redis` adicionado a `[workspace.dependencies]`
  (`features = ["aio","tokio-comp","connection-manager","streams"]`); `uuid` ganhou a feature `v7`.

## 8. Testes

- Integração contra Redis real no **banco lógico 15** (`REDIS_URL` + `/15`), com `FLUSHDB` por
  execução; `RUST_TEST_THREADS=1` garante sequência.
- Cobertura: rotação de refresh; reuso → revogação da família; `NotFound`; blocklist; cache de
  flow_permissions (gravar/ler/invalidar); event bus (publicar→consumir→confirmar e replay de
  pendentes).
- Comandos: `cargo test -p infrastructure_redis`, `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check`.

## 9. Responsabilidades futuras (mapeadas por fase)

| Responsabilidade | Fase | Chave/Canal sugerido |
|---|---|---|
| Cache `RuntimeConfig` + pub/sub de invalidação | F2/F5 | `tenant:config:{tenant_id}` / canal `tenant:config:invalidate` |
| Fan-out realtime por tenant (WebSocket) | F6 | pub/sub por canal do tenant |
| Lock de debounce por contato | F4 | `tenant:{id}:lock:debounce:{contact_id}` (SET NX EX) |
| Delayed tasks (feedback/purga de mídia) | F4 | sorted-set por ETA |
| Presença/typing do atendente | F6 | `tenant:{id}:presence:agent_{id}` |

## 10. Próximo passo

Com a fundação Redis pronta, o módulo de **cadastro/login + JWT** passa a usar o `RefreshTokenStore`
(refresh) e o `CachePermissoes` (flow_permissions). Retomar a partir de
`03-comunicacao-e-autenticacao.md` (decisões em aberto: escopo da entrega e resolução multi-tenant).
