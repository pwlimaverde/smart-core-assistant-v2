# Final Review — infrastructure-redis
Data: 2026-06-02 · Modelo: Opus · Diff: origin/dev...HEAD (server/crates/infrastructure_redis)

## Veredito: CORRIGIDO — ciclo COMPLETO (libera arquivamento)

Fases PREVC: P ✅ · R ✅ · E ✅ · V ✅ (testes contra Redis real 10/10, clippy/fmt limpos) ·
C (este gate). A implementação está conforme o plano aprovado; o auditor Opus aplicou 1 correção
não-bloqueante (remoção de dependência não usada) e revalidou com sucesso.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---------------|--------|------------|
| Crate única de Redis nos `members` do workspace | ✅ | `server/Cargo.toml` adiciona `crates/infrastructure_redis`; nenhuma outra crate importa `redis`. |
| `redis` em `[workspace.dependencies]` com features `aio, tokio-comp, connection-manager, streams` (0.25.0) | ✅ | Confere exatamente com o plano e a central de libs. |
| `uuid` feature `v7` somada (aditiva) | ✅ | `["v4","v7","serde"]`; `infrastructure_postgres` segue compilando. |
| Cargo.toml do crate: deps `redis, serde, serde_json, chrono, uuid, thiserror` + dev-dep tokio | ⚠️→✅ | `tracing` estava declarado mas **não usado** em `src/` (dep não utilizada). Removido. Demais conforme. |
| `connection.rs` — `criar_conexao_redis`, `criar_conexao_com_url`, `criar_cliente`, `ping` | ✅ | Todas presentes; doc da conexão dedicada para bloqueantes na docstring. |
| `errors.rs` — `RedisError {Redis, Serde, ConfigError, NotFound, TokenReuse}` (thiserror) | ✅ | Enum único com `#[from]` para `redis::RedisError` e `serde_json::Error`. |
| `keys.rs` — `chave_tenant, chave_flow_permissions, chave_refresh, chave_refresh_familia, chave_blocklist` | ✅ | Namespacing `tenant:<uuid>:...` e prefixo `auth:` corretos. |
| `envelope.rs` — `TenantEnvelope<T>` + `::novo` com UUID v7 | ✅ | `event_id = Uuid::now_v7()`; `tenant_id` na raiz. |
| `cache.rs` — `CachePermissoes::{definir,obter,invalidar}` + `TTL_FLOW_PERMISSIONS_SEGUNDOS=60` | ✅ | TTL curto via `SET ... EX`; miss retorna `Ok(None)`. |
| `auth_tokens.rs` — `RefreshTokenStore`, `TokenBlocklist`, `RegistroRefresh` | ✅ | Rotação com `SET ... KEEPTTL`; reuso → `revogar_familia` + `TokenReuse`; `NotFound` para inexistente. |
| `event_bus.rs` — publicar/garantir_group/consumir/reprocessar/confirmar + `EventoBruto` | ✅ | `XADD MAXLEN ~ 10000`; `BUSYGROUP` tolerado; `block_ms>0` documentado p/ conexão dedicada. |
| `lib.rs` — módulos + re-exports | ✅ | Todos os símbolos do plano reexportados (+ `STREAM_EVENTOS`). |
| Modelo de chaves (5 recursos) | ✅ | flow_permissions, refresh, refresh_family, blocklist, `events:stream` conforme tabela. |
| Refresh token só como hash | ✅ | Apenas `token_hash` toca o Redis; docstring reforça responsabilidade do caller. |
| Testes integração (DB 15, FLUSHDB, RUST_TEST_THREADS=1) | ✅ | 10/10 verdes contra Redis real (2 unit + 8 integração). |
| `.env.example` (server) com `REDIS_URL` + nota DB 15 | ✅ | Presente. |
| `STREAM_EVENTOS` reexportado | ➕ | Constante pública útil além do plano; sem impacto negativo. |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| server/crates/infrastructure_redis/Cargo.toml:13 | Dependência `tracing` declarada mas não utilizada em nenhum arquivo de `src/` (viola "sem dependências não usadas"). | Removida a linha `tracing.workspace = true`. Build/clippy/fmt seguem limpos. |

## 3. Decisões Autônomas (revisar depois)
- Remoção do `tracing` (decisão tomada autonomamente): a info_aux o listava como "disponível para
  instrumentação (futuro)". Foi removido por estar genuinamente sem uso. Se a instrumentação for
  adicionada num próximo ciclo, basta re-adicionar `tracing.workspace = true`. Baixo risco —
  dependência era build-only e não afeta a lógica nem os testes.

## 4. Revalidação
- fmt: ✅
- clippy: ✅ (`-D warnings`, `--all-targets`, limpo)
- build (infrastructure_redis): ✅
- build (infrastructure_postgres / uuid v7 aditivo): ✅ (`SQLX_OFFLINE=true`)
- testes integração: ✅ (Redis local, `RUST_TEST_THREADS=1` → 10/10 verdes; a remoção do `tracing`
  é build-only e não altera os testes)

## 5. Pendências (escopo extra ou fora do plano)
- Nenhuma pendência funcional. Único `unwrap()` em `src/` está em `keys.rs` dentro de `#[cfg(test)]`
  — permitido (não é código de produção).
- O `.env.example` da **raiz** do repo também contém `REDIS_URL` (fora do escopo de diff declarado;
  não auditado/alterado) — consistente com o do `server/`.
- Itens explicitamente fora do escopo desta fundação (pub/sub de invalidação de config, fan-out
  realtime, debounce lock, delayed tasks, presença, módulo de auth) corretamente não implementados
  — fases futuras.
