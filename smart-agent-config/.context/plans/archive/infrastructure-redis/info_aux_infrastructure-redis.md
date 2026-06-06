# Documentação Auxiliar — Fundação `infrastructure_redis`

> Gerado em: 2026-06-02
> Plano canônico: `.context/plans/archive/infrastructure-redis/infrastructure-redis.md`
> Plano completo: `.context/plans/archive/infrastructure-redis/plano_completo_infrastructure-redis.md`
> Origem do plano-base: `doc_dev/planejamento/04-infraestrutura-redis.md` (registro do crate já implementado).

Esta referência consolida a documentação **atual** das libs Rust e demais decisões técnicas que
sustentam a crate. Todas as libs abaixo foram reaproveitadas da central local
`doc_dev/libs/rust/` **(central local)** — todas estão `✅ ATUALIZADA` e cobrem os recursos usados,
sem necessidade de Context7. Validação empírica adicional: a crate **compila** (`cargo build -p
infrastructure_redis`), passa `clippy --all-targets -D warnings` + `fmt --check`, e os **10 testes**
(2 unit + 8 integração contra Redis real) passam — o código é a fonte da verdade das assinaturas.

---

## Grupo A — Libs Rust

### redis (0.25.0) — (central local, `doc_dev/libs/rust/redis.md`, verif. 2026-05-31)
- Versão da central **bate exatamente** com o `[workspace.dependencies]` (`0.25.0`).
- Features usadas: `aio`, `tokio-comp`, `connection-manager`, `streams`.
- `ConnectionManager` (`redis::aio::ConnectionManager`): multiplexado, `Clone`, reconexão
  automática — usado para todos os comandos não-bloqueantes.
- Comandos **bloqueantes** (`XREADGROUP ... BLOCK`) ou pub/sub exigem **conexão dedicada**
  (`Client::get_async_connection` / `get_async_pubsub`), pois travam a conexão multiplexada.
- Streams: `xadd_maxlen(key, StreamMaxlen::Approx(n), "*", &[(campo, valor)...])`;
  leitura via `xread_options(&[stream], &[id], &StreamReadOptions)` → `StreamReadReply`;
  `xack(stream, grupo, &[id])`. `StreamReadOptions::default().group(g, c).count(n).block(ms)`.
- `XGROUP CREATE ... $ MKSTREAM` via `redis::cmd(...)`; idempotência tratando
  `e.code() == Some("BUSYGROUP")` como sucesso.
- Comandos genéricos: `set_ex`, `set` + `KEEPTTL` (via `redis::cmd("SET")...arg("KEEPTTL")`),
  `get`, `del`, `exists`, `sadd`, `smembers`, `ttl`, `flushdb` (testes).
- `from_redis_value::<String>` para extrair campos do `StreamReadReply`.

### serde / serde_json (1.0.x) — (central local, `serde.md`, verif. 2026-05-31)
- `#[derive(Serialize, Deserialize)]` em `TenantEnvelope<T>` e `RegistroRefresh`.
- `serde_json::{to_string, from_str}` para serializar payloads de evento e o registro de refresh
  token gravado em Redis. `serde_json::Error` flui para `RedisError::Serde` via `#[from]`.

### uuid (1.x, central recomenda 1.10.0) — (central local, `uuid.md`, verif. 2026-06-01)
- ⚠️ **Adição desta entrega:** feature `v7` somada às já existentes (`v4`, `serde`) no workspace.
  `Uuid::now_v7()` gera `event_id` ordenável no tempo (idempotência/ordenação no event bus);
  `Uuid::new_v4()` segue para identificadores aleatórios. `Uuid::parse_str` na desserialização.
- Mudança aditiva e segura: `infrastructure_postgres` recompila sem alterações.

### chrono (0.4.x) — (central local, `chrono.md`, verif. 2026-05-31)
- `DateTime<Utc>` no campo `timestamp` do envelope; `Utc::now()` na criação;
  `DateTime::parse_from_rfc3339(...).with_timezone(&Utc)` na reconstrução a partir do stream.

### thiserror (1.0.x) — (central local, `thiserror_anyhow.md`, verif. 2026-05-31)
- `#[derive(thiserror::Error)]` no enum único `RedisError`, espelhando o padrão de `DbError`.
  Variantes com `#[from]` para `redis::RedisError` e `serde_json::Error`.

### tracing (0.1.40) — (central local, `tracing.md`, verif. 2026-05-31) — REMOVIDO no final-review
- Disponível para instrumentação dos fluxos (sem logar tokens/segredos/PII). **Não usado nesta
  entrega** — o gate de final-review removeu a dependência por estar declarada sem uso; re-adicionar
  `tracing.workspace = true` quando a instrumentação for implementada.

### tokio (1.x) — (central local, `tokio.md`, verif. 2026-05-31)
- Apenas em `[dev-dependencies]` (`macros`, `rt-multi-thread`) para os testes `#[tokio::test]`.
  O runtime real é injetado pelo binário consumidor; a crate é runtime-agnóstica.

---

## Grupo B — Serviços Externos

- **Redis Server (7.x).** Único alvo de I/O. Já provisionado em `docker/compose/data.yml`
  (`redis:7-alpine`, `requirepass`, AOF, `maxmemory 150mb` / `allkeys-lru`). Acesso em dev via
  túnel SSH; `REDIS_URL` (ex.: `redis://:SENHA@localhost:6380`).
  - **Auth:** senha via `requirepass` embutida na URL.
  - **Testes:** banco lógico **15** (`REDIS_URL` + `/15`), com `FLUSHDB` por execução e
    `RUST_TEST_THREADS=1` para sequência.
- Nenhuma API HTTP/gRPC de terceiros nesta crate (event bus é interno ao Redis).

---

## Notas Gerais / Gotchas

1. **Crate única de Redis:** nenhuma outra crate do workspace importa `redis` diretamente —
   espelha o papel-ponte de `infrastructure_postgres`.
2. **`ConnectionManager` vs conexão dedicada:** comando bloqueante (`BLOCK > 0`) **trava** a
   conexão multiplexada; documentado nas assinaturas (`consumir(..., block_ms)`).
3. **Namespacing obrigatório:** chaves de cache por tenant `tenant:<uuid>:<recurso>:<chave>`;
   chaves de auth com prefixo `auth:` (precedem a seleção de tenant; o `tenant_id` vai no registro).
4. **Segurança de refresh token:** o Redis nunca vê o token em claro — só o **hash**. Rotação com
   `SET ... KEEPTTL` preserva o TTL ao marcar `rotacionado=true`; reuso de token rotacionado
   dispara revogação da **família inteira** (`TokenReuse`).
5. **Idempotência de evento:** `event_id` é UUID **v7** (ordenável) e viaja como campo do stream;
   o `stream_id` (`<ms>-<seq>`) atribuído pelo Redis serve para `XACK`/replay.
6. **MAXLEN aproximado (`~`):** `XADD ... MAXLEN ~ 10000` evita crescimento ilimitado sem o custo
   de trim exato a cada escrita.
7. **`BUSYGROUP`:** `garantir_consumer_group` é idempotente — cria o grupo (`$ MKSTREAM`) e ignora
   o erro `BUSYGROUP` quando já existe.
8. **Migração futura do envelope:** quando existir a crate `contracts`, `TenantEnvelope<T>` migra
   para lá; hoje vive na crate Redis por ser o produtor/consumidor inicial.
