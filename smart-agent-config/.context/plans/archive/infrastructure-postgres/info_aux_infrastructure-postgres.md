# Documentação Auxiliar — Fundação `infrastructure_postgres`

> Gerado em: 2026-06-01
> Plano canônico: `.context/plans/infrastructure-postgres.md`
> Plano completo: `.context/plans/infrastructure-postgres/plano_completo_infrastructure-postgres.md`
> Origem do plano-base: conversa (sessão de planejamento Rust sobre `doc_dev/modelagem_dados`).

Esta referência consolida a documentação **atual** das libs Rust e demais decisões técnicas
que sustentam a implementação. Libs marcadas **(central local)** foram reaproveitadas de
`doc_dev/libs/rust/`; as demais foram verificadas/atualizadas via Context7 em 2026-06-01.

---

## Grupo A — Libs Rust

### sqlx (0.8.2) — atualizada via Context7 `/launchbadge/sqlx`
- Macros `query!` / `query_as!` / `query_scalar!` com validação em tempo de compilação.
- **Modo offline:** `cargo sqlx prepare` gera `.sqlx/` (versionado); `SQLX_OFFLINE=true cargo build` no CI.
- `PgPoolOptions` (max_connections, timeouts); `pool.begin()` → `Transaction<'_, Postgres>`;
  dentro de tx usar `&mut *tx` (query simples) e `&mut **tx` (macros).
- `sqlx::migrate!("./migrations")` aplica migrations embutidas.
- **0.7 → 0.8:** sem breaking changes nas APIs usadas (pool, transações, macros, migrate).
- ⚠️ **Correção crítica (decisão do plano):** `SET LOCAL app.current_tenant = $1` **não funciona**
  (o comando `SET` não aceita bind via prepared statement). Usar
  `SELECT set_config('app.current_tenant', $1, true)` com `tenant_id.to_string()`.
- Features: `postgres, runtime-tokio-rustls, macros, migrate, uuid, chrono, rust_decimal, json`.

### pgvector (0.4.0) — atualizada via Context7 `/pgvector/pgvector`
- `pgvector::Vector::from(Vec<f32>)`; bind em macro com `vector_payload as _`.
- Operadores: `<=>` cosseno (usado), `<->` L2, `<#>` produto interno.
- Compatível com SQLx 0.8; sem breaking changes 0.3 → 0.4.
- Índice: `CREATE INDEX ... USING hnsw (embedding vector_cosine_ops)`.
- Busca **sempre** com `tenant_id = $N` explícito (índice + isolamento) e dimensão fixa `vector(1536)`.

### dashmap (6.1.0) — atualizada via Context7 `/xacrimon/dashmap`
- `DashMap<Uuid, Arc<RuntimeConfig>>` para o `TenantConfigCache` (não pools por tenant).
- `new`/`insert`/`get`(→`Ref`)/`remove`; major 6 backward-compatible com 5.x.
- **Deadlock:** nunca segurar `Ref`/`RefMut` através de `.await`; clonar (`Arc`/`PgPool` são O(1))
  e deixar o guard sair de escopo antes do I/O assíncrono.
- ⚠️ Doc local anterior descrevia arquitetura obsoleta (múltiplos bancos/`TenantPoolManager`) — corrigida.

### aes-gcm (0.10.3) — (central local, sem mudança)
- `Aes256Gcm`, `aead::{Aead, AeadCore, KeyInit, OsRng}`. Nonce de 96 bits via `OsRng`.
- `encrypt`/`decrypt`; o resultado concatena ciphertext + tag (16 bytes); split na descriptografia.

### rust_decimal (1.36.0) — (central local; patch sobre 1.32)
- `Decimal` para `NUMERIC` (valores `NUMERIC(10,2)`, temperatura/thresholds `NUMERIC(3,2)`).
- Conversão `decimal.to_f64()` ao montar o `RuntimeConfig`.

### chrono (0.4.38) — (central local; patch sobre 0.4.31)
- `DateTime<Utc>` para colunas `TIMESTAMPTZ`. `Utc::now()` nos inserts.

### serde / serde_json (1.0.219) — (central local; patch sobre 1.0.203)
- `#[derive(Serialize, Deserialize)]` em DTOs/`RuntimeConfig`; `serde_json::Value` para JSONB.

### thiserror (central local), tokio (1.38.x), tracing (0.1.40) — (central local)
- `thiserror::Error` no enum `DbError`; `tokio` runtime async; `tracing` para logs (sem PII/segredos).

### uuid (1.10.0) — criada via Context7 `/uuid-rs/uuid`
- `Uuid::new_v4()`, `Uuid::parse_str`; features `v4` + `serde`; mapeamento `UUID` via feature `uuid` do SQLx.

### async-trait (0.1.83) — criada via Context7 `/dtolnay/async-trait`
- `#[async_trait]` no trait **e** no impl; bound `Send + Sync` para `Arc<dyn Repository>`.

### base64 (0.22.1) — criada via Context7 `/marshallpierce/rust-base64`
- ⚠️ `base64::encode/decode` globais **removidas**; usar `engine::general_purpose::STANDARD` + trait `Engine`.

### secrecy (0.10.3) — criada via Context7 `/iqlusioninc/crates`
- `SecretString` (`Debug` = `[REDACTED]`, zeroize no Drop); `expose_secret()` para leitura pontual;
  feature `serde` só na ponte Redis (serialização opt-in).

---

## Grupo B — Serviços Externos

Nenhum nesta fundação. O único alvo de I/O é o **PostgreSQL único** (acessado via SQLx) com a
extensão **pgvector** (coberta pela lib). Redis, gRPC (`ia_engine`) e Evolution API ficam em
fases posteriores, fora do escopo desta crate.

---

## Notas Gerais / Gotchas

1. **RLS via `set_config`** (não `SET LOCAL = $1`) — ver sqlx acima. É o ajuste mais importante.
2. **Role do banco sem BYPASSRLS:** a app conecta como `smartcore_app` (NOBYPASSRLS), nunca como
   owner/superuser; tabelas usam `ENABLE` + `FORCE ROW LEVEL SECURITY` (`08_diretrizes_seguranca.md` §1).
3. **`auth_user`:** as FKs do legado Django apontam para `auth_user`. Como ainda não há módulo de
   usuários em Rust, criar tabela mínima `auth_user` (global, sem RLS) na migration `0001`.
4. **Tabelas globais (sem RLS):** `auth_user`, `tenants_plan`, `settings_manager_coresettings`.
   Todas as demais (com `tenant_id`) recebem política RLS.
5. **Infra já provisionada:** `docker/compose/data.yml` (Postgres pgvector pg16, Redis, MinIO);
   `docker/init-scripts/01-extensions.sql` cria `vector` e `uuid-ossp`; dev via `infra/tunnel.ps1`;
   variáveis em `.env.example` (`DATABASE_URL`, `ENCRYPTION_KEY`, `JWT_SECRET`, ...).
6. **`secrecy` + serialização:** `RuntimeConfig` será serializado p/ Redis numa fase futura; manter
   `SecretString` com feature `serde` e tratar a serialização só na ponte.
7. **base64 0.22:** revisar qualquer snippet antigo que use `base64::encode/decode` global.
