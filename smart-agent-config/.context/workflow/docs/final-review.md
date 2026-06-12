# Final Review — user-auth-module
Data: 2026-06-12 · Modelo: Opus · Diff: working tree (feature/user-auth-module)

## Veredito: CORRIGIDO

A implementação cobre a maior parte do escopo (login real, refresh, logout, interceptor
wrapper, extensão aditiva do Envelope, eliminação dos contextos forjados e rotas admin de
configuração). Foram encontrados e **corrigidos** bugs de segurança/lógica (panic na extração
de token, sessão de superusuário quebrada no refresh, reuso de token não auditado, escopo
coringa do superusuário ignorado, tenant alvo perdido nas rotas admin de config). Restam
**pendências de escopo** (rate limiting de login e a maior parte da suíte de testes do DoD
§6.4) que NÃO são bugs e sim sub-features ainda não construídas — registradas na seção 5.

---

## 1. Plano vs. Implementado

| # | Item do escopo | Status | Observação |
|---|---|---|---|
| 1 | Login real: JWT HS256 (claims doc 09 §6.1), `OnceLock`, `JWT_SECRET` ≥32B, refresh opaco 32B→base64url, SHA-256 ao Redis, TTLs via env, `MuxClient` no boot, `StoreRefreshToken` com tenant real | ✅ conforme | `jwt.rs`/`tokens.rs`/`login.rs` corretos. `VerifyCredentials` estendido (aditivo) p/ devolver `tenant_id`/`role`/`module_permissions` (via `TenantUserRepository`) — decisão R4 cumprida. `JWT_SECRET` tem fallback de dev (≥32B) — aceitável p/ dev, ver §3. |
| 1b | Rate limiting (`AUTH_LOGIN_RATE_LIMIT`) | ❌ não feito | Nenhum `RegisterLoginAttempt`/INCR+EXPIRE. Sub-feature ausente → pendência (§5), não construída. |
| 2 | Rotas Refresh/Logout: ValidateAndRotate mantendo family_id; reuso→401+auditoria `token_reuse_detected`; Logout→BlockToken(jti, TTL=exp-now)+RevokeFamily | ⚠️→✅ corrigido | Rotação/family_id OK; BlockToken c/ TTL=max(1,exp-now) OK; RevokeFamily OK. **Auditoria de reuso ausente** → adicionada (correções #3/#4/#5). |
| 3 | Interceptor Camada 1 como wrapper sobre `transport::Server`; aplica a tudo exceto Login/Refresh; valida assinatura/exp local; blocklist via data_redis; sobrescreve tenant_id (claims>body); guard superuser | ⚠️→✅ corrigido | Wrapper `exigir_auth` correto e aplicado a Logout/Stream/admin. **Extração de token frágil/perigosa** (heurística `len()>30`, leitura de `traceparent`, `[7..]` com risco de panic) → reescrita em `extrair_bearer` (correções #1/#2). |
| 4 | Extensão ADITIVA do envelope.proto + FBS/codec regenerados e simétricos | ✅ conforme | Campos 11–13 (`auth_user_id`/`auth_scopes`/`auth_is_superuser`) ao final do proto; `.fbs` (envelope + all_schemas) e `codec.rs` (encode/decode) simétricos; `runtime.rs`/clients atualizados. `schema_version` preservado. |
| 5 | RequestContext unificado; data_postgres monta contexto do Envelope; elimina os 4 contextos forjados (427/491/889/994) | ✅ conforme | `contexto_do_envelope(env)` substitui os 4 blocos `user_id:1`. `application::RequestContext` removido; canônico = `infrastructure_postgres`. `auth_user_id:1` remanescentes só em testes. |
| 6 | Rotas admin config (guard superuser): List/Upsert/Delete CoreSettings (cifra+máscara), Get/UpdateTenantConfig (api_keys cifradas+máscara), invalidação do cache, auditoria de mutações | ⚠️→✅ corrigido | **Implementadas no `data_postgres`** (queries diretas; `infrastructure_postgres` NÃO foi alterado, mas a fase FOI feita — diferente da hipótese da tarefa). Cifra via `CipherManager`, máscara `••••••••`, `config_cache.invalidate`, auditoria via `publicar_evento_seguranca`. **Bug:** tenant alvo perdido (interceptor zera tenant do superusuário) → corrigido (correção #6). |
| 7 | Testes do DoD §6.4 (feliz, senha errada, inativo, refresh expirado, reuso, logout+bloqueado, admin com/sem superuser) | ⚠️ parcial | Só 2 testes (login feliz + credenciais inválidas) c/ stubs TCP. Faltam inativo, refresh expirado, reuso, logout+bloqueado e admin. Pendência (§5). |
| + | `GetUserIdentity` (RPC nova no data_postgres + rota guard-superuser na runtime_api) | ➕ extra | Usada pelo refresh p/ reidratar escopos/is_active/is_superuser. Boa decisão. |

---

## 2. Correções Aplicadas

| # | Arquivo:linha | Problema | Correção |
|---|---|---|---|
| 1 | `runtime_api/src/main.rs` (`exigir_auth`) | Extração de token via heurística frágil (`causation_id.len()>30`) e leitura de `traceparent` como Bearer (traceparent é W3C trace, nunca token). Vetor de erro/bypass. | Novo helper `extrair_bearer(env)`: lê de `causation_id` (com/sem `Bearer `), valida formato JWT (≥2 pontos), retorna `Option`, sem fatiar por índice. |
| 2 | `runtime_api/src/main.rs` (`handler_logout`) | `&env.traceparent[7..]` causa **panic** quando `traceparent` tem <7 chars (entrada do cliente). | Passou a usar `extrair_bearer`; `None`→401, sem panic. |
| 3 | `data_redis/src/main.rs` (`handler_validate_and_rotate`) | Reuso (`RedisError::TokenReuse`) mapeado p/ `AppError::Cache` (`CACHE_KEY_NOT_FOUND`), indistinguível de `NotFound`; forçava inspeção de Debug string. | Reuso → `AppError::Auth("token_reuse_detected")` (marcador estável); NotFound segue Cache. |
| 4 | `application/src/auth/refresh.rs` | Detecção de reuso por `format!("{err:?}")` (match em Debug) — frágil; e perdia a auditoria. | Detecta pelo marcador `REUSE_MARKER` na `error.message`; `pub const REUSE_MARKER` exportada e propagada como `AppError::Auth(REUSE_MARKER)`. |
| 5 | `runtime_api/src/main.rs` (`handler_refresh` + boot) + `runtime_api/Cargo.toml` | Reuso de refresh **não publicava** `token_reuse_detected` no security:stream (plano item 2 / doc 09 §6.2). | Adicionado `bus` (`criar_conexao_com_timeouts`) no boot; `handler_refresh` detecta o marcador e chama `publicar_reuso_detectado`→`publicar_evento_seguranca` (sem logar token). Deps `redis`/`infrastructure_redis` adicionadas. |
| 6 | `data_postgres/src/main.rs` (`handler_get_tenant_config`/`handler_update_tenant_config`) | Interceptor zera o `tenant_id` do Envelope p/ superusuários (claims>body) → rotas admin tenant-scoped operavam sobre `Uuid::nil()`; impossível configurar tenant alvo. | Helper `resolver_tenant_alvo(env, payload)`: usa `payload.tenant_id` quando presente (rota é guard-superuser), Envelope como fallback; rejeita `nil` com `Validation`. |
| 7 | `application/src/auth/refresh.rs` | `is_superuser = tenant_opt.is_none()`, mas o login persiste refresh do superusuário com tenant `Uuid::nil()` (≠None) → superusuário recebia `is_superuser=false` + tenant nil falso ao renovar. | `tenant_opt` filtra `nil`; `is_superuser` sobrescrito pela identidade autoritativa de `GetUserIdentity`. |
| 8 | `infrastructure_postgres/src/security.rs` (`has_permission`) | Escopo coringa `"*"` (do superusuário) não satisfazia checagens exatas → superusuário c/ `["*"]` barrado por `exigir_qualquer`. | `has_permission` aceita `"*"` como coringa. (Decisão autônoma — §3.) |

### Correções complementares (revisão do agente principal, 2026-06-12)

| # | Arquivo:linha | Problema | Correção |
|---|---|---|---|
| 9 | `runtime_api/src/main.rs` (boot) | `JWT_SECRET` com **fallback hardcoded** — segredo conhecido no repositório permitiria forjar tokens se a env faltasse em produção (doc 09 §4 define a var como obrigatória). | Removido o fallback: boot falha com mensagem clara se `JWT_SECRET` ausente. Testes não dependiam do fallback (inicializam as próprias chaves). |
| 10 | `runtime_api/src/main.rs` (boot) | Alias não documentado `SMARTCORE_REFRESH_TTL_S` com precedência sobre `AUTH_REFRESH_TTL_S` (doc 09 §6.5 só define a segunda). | Mantida apenas `AUTH_REFRESH_TTL_S`. |
| 11 | `runtime_api/src/main.rs` (`handler_admin_forward`, `handler_stream_atendimentos`) | **JWT vazava para os serviços internos**: os forwards repassavam `..env.clone()` incluindo o `causation_id` (que transporta o Bearer na borda) ao `data_postgres`. | Request interna passa `causation_id = env.message_id` (causalidade correta + token não sai da borda). |
| 12 | `application/src/auth/refresh.rs` | **Fail-open**: se `GetUserIdentity` respondesse Error (ex.: usuário removido), o refresh emitia token com escopos de fallback; `is_active` default `true`; usuário comum sem tenant receberia claims com tenant vazio. | Falha fechada: identidade não resolvida → `Auth("sessão inválida")`; `is_active` default `false`; usuário comum sem tenant rejeitado (espelha o login). Removida a heurística mutável de `is_superuser`. |

---

## 3. Decisões Autônomas (revisar depois)

1. **`has_permission` aceita `"*"`** (`infrastructure_postgres/src/security.rs`): alinha o escopo
   `["*"]` que o login concede ao superusuário com as checagens exatas dos repositórios. Alternativa:
   nunca conceder `"*"` e sim lista admin explícita; mantido `"*"` por já vir do login.
2. **Tenant alvo das rotas admin config vem de `payload.tenant_id`** (`resolver_tenant_alvo`): forma
   mínima de reconciliar "claims > body" (superuser sem tenant) com operações tenant-scoped. O contrato
   dessas RPCs passa a exigir `tenant_id` no payload — confirmar com o app Flutter (plano 11).
3. **Auditoria de reuso na `runtime_api`, não na `application`**: p/ manter a crate `application` livre
   de infraestrutura (redis), o `bus` ficou no `runtime_api` (deps `redis`/`infrastructure_redis`
   adicionadas ao app). Coerente com a arquitetura de camadas.
4. ~~**`JWT_SECRET` com fallback de dev**~~ — **resolvido na revisão complementar** (correção #9):
   a variável passou a ser obrigatória no boot, sem fallback.

---

## 4. Revalidação (em `server/`, `SQLX_OFFLINE=true`)

| Gate | Resultado |
|---|---|
| `cargo fmt --check` | ✅ PASS (após `cargo fmt`) |
| `cargo clippy --workspace --all-targets -- -D warnings` | ✅ PASS (0 warnings) |
| `cargo build --workspace` | ✅ PASS |
| `cargo test -p application -p transport` | ✅ PASS (application: 2/2 login; transport: 18 unit + 6 integ, inclui RPC e bus Redis local) |

**Re-execução após as correções complementares (#9–#12):** `cargo fmt --check` ✅ ·
`cargo clippy --workspace --all-targets -- -D warnings` ✅ · `application` 2/2 ✅ ·
`transport` testes RPC 4/4 ✅. Os 2 testes do bus (`test_redis_bus_*`) falharam por
**infraestrutura indisponível no momento** (conexão Redis 6380 recusada — túnel fora do ar);
não tocam o código deste ciclo e haviam passado na primeira rodada com o túnel ativo.

Suíte completa de integração do DoD §6.4 (refresh/reuso/logout/admin contra Postgres+Redis remotos
via túnel) **não executada** — esses testes ainda não existem (ver §5); os testes presentes que
exigiriam o túnel rodaram com stubs/Redis local e passaram.

---

## 5. Pendências (sub-features ausentes — não construídas pela auditoria)

1. ~~**Rate limiting de login (`AUTH_LOGIN_RATE_LIMIT`)**~~ — **resolvido no fechamento (2026-06-12)**:
   `registrar_tentativa_login` (INCR+EXPIRE) em `infrastructure_redis`, rota `RegisterLoginAttempt`
   no `data_redis`, corte fail-closed em `application::login` (hash SHA-256 do e-mail, nunca em claro)
   e parse de `AUTH_LOGIN_RATE_LIMIT` ("N/Ms", padrão 5/60s) no boot da `runtime_api`.
2. ~~**Testes do DoD §6.4 incompletos**~~ — **resolvidos**: suíte criada em
   `application/tests/{login,refresh,logout,jwt,tokens}` (20+ testes: inativo, refresh
   expirado/inexistente, reuso, logout, superusuário) + 6 testes da `runtime_api` (interceptor,
   handlers, auditoria de reuso) + teste de rate limit excedido + teste do handler no `data_redis`.
3. **Contrato das RPCs admin tenant-scoped** — passam a exigir `tenant_id` no payload (correção #6);
   refletir no contrato consumido pelo app Flutter (plano 11) e documentar no doc 11.
4. ~~**`JWT_SECRET` obrigatório em produção**~~ — resolvido (correção #9 da revisão complementar).

## 6. Fechamento (2026-06-12)

Rate limiting implementado e suíte de testes do DoD criada/validada. Com isso o DoD §6.4
fica completo no backend. Item 3 permanece como nota de integração para o plano 11
(app Flutter de configuração).
