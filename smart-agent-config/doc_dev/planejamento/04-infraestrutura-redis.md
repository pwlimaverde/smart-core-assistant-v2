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

A crate `infrastructure_redis` serve como uma **biblioteca interna exclusiva** do aplicativo `apps/data_redis`. O Redis atua em dois papéis distintos no sistema, que foram desmembrados no refator modular:
- **Cache, Tokens e Locks (Síncrono)**: Gerenciado por esta crate e exposto via RPC pelo serviço `data_redis`. Centraliza namespacing, cache de permissões, rotação de refresh tokens e blocklist de acesso.
- **Barramento de Eventos (Assíncrono)**: O tráfego do Redis Streams foi movido para a biblioteca de base `crates/transport` (`transport::bus`), permitindo que qualquer módulo interaja com o barramento de eventos sem carregar dependências de cache.

---

## 1.1 O Serviço de Dados `data_redis`

O aplicativo `apps/data_redis` é o processo servidor UDS que expõe via RPC (FlatBuffers padrão, gRPC fallback) os seguintes recursos de persistência do Redis em tempo de execução:
- Validação e rotação de Refresh Tokens (com detecção de reuso).
- Verificação de blocklist de Access Tokens (jti) para logout imediato.
- Cache síncrono de permissões por fluxo e tenant (`flow_permissions`).
- Locks atômicos para debounce por contato.

---

## 2. Escopo do Cache e Persistência (`data_redis`)

**Implementado:**
- Conexão (`ConnectionManager`) multiplexada e com reconexão automática.
- Namespacing obrigatório por tenant (`tenant:<uuid>:<recurso>:<chave>`).
- Rotação de refresh tokens com detecção de reuso e revogação de família.
- Blocklist de access tokens (jti) e cache de permissões.
- Locks distribuídos baseados em chaves de curta duração para debounce e concorrência.
- Cobertura por testes de integração.

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
6. **Dois envelopes coexistem em `contracts`** (não há substituição): o
   `TenantEnvelope<T>` (genérico Rust, serde/JSON) embrulha **eventos do barramento**
   Redis Streams (`tenant_id`, `event_id` UUIDv7, `event_type`, `timestamp`,
   `traceparent`, `payload`); o `Envelope` protobuf/FlatBuffers embrulha as
   **chamadas RPC IPC/gRPC**. Cada um serve a um transporte.
7. **Barramento de Eventos**: O event bus foi implementado fisicamente em
   `transport::bus`, publicando/consumindo `TenantEnvelope<T>`.

## 4. Estrutura de módulos (`src/`)

| Módulo | Responsabilidade | API principal |
|---|---|---|
| `connection.rs` | Conexão e health | `criar_conexao_redis()`, `criar_conexao_com_url(url)`, `criar_cliente(url)`, `ping(con)` |
| `errors.rs` | Erro único | `RedisError { Redis, Serde, ConfigError, NotFound, TokenReuse }` |
| `keys.rs` | Namespacing | `chave_tenant`, `chave_flow_permissions`, `chave_refresh`, `chave_refresh_familia`, `chave_blocklist` |
| `cache.rs` | Cache de permissões | `CachePermissoes::{definir,obter,invalidar}_flow_permissions` |
| `auth_tokens.rs` | Tokens de auth | `RefreshTokenStore`, `TokenBlocklist`, `RegistroRefresh` |
| `locks.rs` | Locks distribuídos | `LockManager` (debounce e concorrência) |

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

### 6.4 Event bus (Redis Streams + consumer groups)
- **Implementação**: A publicação, consumo, confirmação e replay de pendentes baseados em Redis Streams foram delegados para a biblioteca `transport::bus` na crate `crates/transport`. Ela gerencia as conexões bloqueantes dedicadas e publica envelopes unificados `Envelope` de `contracts`.

### 6.5 Relação de chamadas RPC de dados
- O cache de permissões, verificação de blocklist, rotação de refresh e locks atômicos de debounce são requisitados pelos demais módulos através do cliente tipado de RPC conectando-se no socket de `apps/data_redis`. O app realiza as chamadas síncronas contra esta crate.

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
| Fan-out realtime por tenant (gRPC Server Streaming) | F6 | pub/sub por canal do tenant |
| Lock de debounce por contato | F4 | `tenant:{id}:lock:debounce:{contact_id}` (SET NX EX) |
| Delayed tasks (feedback/purga de mídia) | F4 | sorted-set por ETA |
| Presença/typing do atendente | F6 | `tenant:{id}:presence:agent_{id}` |

## 10. Próximo passo

Com a fundação Redis pronta, o módulo de **cadastro/login + JWT** passa a usar o `RefreshTokenStore`
(refresh) e o `CachePermissoes` (flow_permissions). Retomar a partir de
`09-comunicacao-e-autenticacao.md` (decisões em aberto: escopo da entrega e resolução multi-tenant).
