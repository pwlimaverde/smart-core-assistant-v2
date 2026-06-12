# Documentação Auxiliar — User Auth Module (revisão jun/2026)

> Gerado em: 2026-06-02 · **Revisado em: 2026-06-12** (pós-refatoração modular)
> Plano canônico: `.context/plans/user-auth-module.md`
> Plano completo: `.context/plans/user-auth-module/plano_completo_user-auth-module.md`
>
> Esta revisão substitui a versão original: a borda deixou de ser um servidor Tonic
> dedicado e passou a ser o `transport` próprio (UDS/FlatBuffers + fallback gRPC,
> `Envelope` unificado). Os snippets de libs continuam válidos; a seção de
> "Estado real do código" abaixo é o inventário de partida da implementação.

---

## 1. Estado real do código (inventário verificado em 2026-06-12)

### 1.1 Transporte (crate `transport`) — pronto, reusar

| API | Assinatura real | Uso no plano |
|---|---|---|
| Servidor RPC | `transport::Server::from_env("RUNTIME_API").route("Método", handler).run()` | rotas `Login`/`Refresh`/`Logout` e rotas admin |
| Handler | `Fn(Envelope) -> Pin<Box<dyn Future<Output = Envelope>>>` | interceptor = wrapper de handler (não existe middleware global) |
| Cliente | `transport::conectar_cliente("data_postgres").await? -> MuxClient` | criar **uma vez no boot** e compartilhar via estado (é multiplexado e reconecta sozinho) |
| Chamada | `MuxClient::call(env: Envelope, prazo: Duration) -> Result<Envelope, TransportError>` | todas as RPCs internas |
| Auditoria | `transport::bus::publicar_evento_seguranca(...)` (Redis Streams `security:stream`) | eventos `login_failed`, `token_reuse_detected`, mutações admin |

> **Windows (dev):** UDS não funciona — exportar `SMARTCORE_<SVC>_ENDPOINT=tcp://...`
> (já documentado; os serviços leem endpoint/codec do env via `from_env`).

### 1.2 `Envelope` (`contracts/schemas/envelope.proto`)

Campos atuais: `tenant_id`, `schema_version`, `message_id`, `causation_id`,
`traceparent`, `occurred_at`, `kind` (REQUEST/REPLY/EVENT/STREAM_ITEM/ERROR),
`method`, `payload` (bytes), `error`.
**Não há campos de identidade** (`user_id`/`scopes`/`is_superuser`) — a propagação do
contexto autenticado da Camada 1 → Camada 2 exige **extensão aditiva do proto**
(decisão de design da fase R; manter `schema_version`).

### 1.3 Autenticação — pronto e testado (reusar, não reescrever)

| Peça | Onde | Assinatura/observação |
|---|---|---|
| Argon2id | `infrastructure_postgres/src/auth/password.rs` | `hash_password(s)`, `verify_password_async(senha, hash)` (spawn_blocking) |
| Repo `auth_user` | `infrastructure_postgres/src/auth/users.rs` | `buscar_por_email`, `atualizar_ultimo_login`, campos `is_active`, `is_superuser` |
| `RefreshTokenStore` | `infrastructure_redis/src/auth_tokens.rs` | `armazenar(token_hash, user_id, tenant_id: Option<Uuid>, family_id, ttl_segundos)`; `validar_e_rotacionar(hash)` → `RegistroRefresh {user_id, tenant_id, family_id, rotacionado}`, erros `NotFound`/`TokenReuse` (reuso revoga família via KEEPTTL); `revogar_familia(family_id)` |
| `TokenBlocklist` | idem | bloquear `jti` com TTL; consulta `esta_bloqueado` |
| Rotas `data_redis` | `apps/data_redis/src/main.rs` | `GetCache`, `SetCache`, `StoreRefreshToken`, `ValidateAndRotate`, `RevokeFamily`, `BlockToken`, `IsTokenBlocked` |
| `VerifyCredentials` | `apps/data_postgres/src/main.rs:1038` | real e testado: timing-safe (hash dummy em `OnceLock`), rejeita inativo, `atualizar_ultimo_login` em background; **reply:** `{id, username, email, is_superuser}` |
| Bootstrap superuser | `control_plane create-superuser/delete-superuser` | cliente fino via RPC `CreateSuperuser`; env `SUPERUSER_*` |

### 1.4 Placeholders a substituir (o "porquê" deste plano)

1. `application/src/auth/login.rs` — tokens **mockados** (UUID v4) e "hash"
   `format!("hash_{token}")`; TTL 86400 hardcoded; cliente RPC criado a cada chamada.
2. `apps/runtime_api/src/main.rs` — só `Login` e `StreamAtendimentos`; `AppState {}`
   vazio; sem interceptor; `tenant_id` vem do cliente (violando claims > body).
3. `apps/data_postgres/src/main.rs` — handlers montam `RequestContext` **forjado**
   (`user_id: 1`, escopos fixos) em ~4 pontos (linhas 427, 491, 889, 994).
4. **Dois `RequestContext`:** `application::RequestContext`
   `{tenant_id, user_id, user_scopes, traceparent}` vs
   `infrastructure_postgres::security::RequestContext`
   `{tenant_id, user_id, user_scopes, flow_permissions}` (este tem `exigir_qualquer`,
   `has_flow_permission`). Unificar ou definir conversão única.
5. `contracts/schemas/queries/auth.proto` — só mensagens `RegisterRequest`/
   `LoginRequest`/`AuthResponse`; sem `Refresh`/`Logout` e sem service admin.

### 1.5 Config dinâmica de tenants — o "ServiceHub v2" já tem fundação no banco

Equivalência com a v1 (`old/.../modules/services/features/service_hub.py` +
`app/settings_manager/models.py` — `CoreSettings {key, value, encrypted, description}`
e `ConfigProvider`/`RuntimeConfig` por requisição):

| Peça v2 | Onde | Estado |
|---|---|---|
| `RuntimeConfig` resolvido (prompts, mensagens, LLM, embeddings, thresholds, api_keys como `SecretString`) | `infrastructure_postgres/src/config_cache.rs` | ✅ pronto |
| `TenantConfigCache` (DashMap por tenant) | idem | ✅ pronto (falta **invalidação** ao atualizar config) |
| Cascata Tenant > CoreSettings | `tenants/config.rs::resolve_runtime_config` (RLS via `set_config('app.current_tenant')`) | ✅ pronto |
| CoreSettings global | `tenants/settings.rs` → tabela `settings_manager_coresettings`; `load_all_settings` (decripta `ct:nonce:tag`), `upsert_setting` | ✅ pronto (falta `delete`/listagem p/ admin) |
| Cifra AES-256-GCM | `crypto.rs::CipherManager` (env `ENCRYPTION_KEY`, base64 32 bytes) | ✅ pronto |
| **Exposição RPC/admin** dessas peças | — | ❌ **não existe** — é o gap que o app Windows do superusuário precisa (estilo Django admin do `settings_manager` + `TenantConfig`) |

> Destino final: painel admin (doc 11) fala **só com `runtime_api`**; rotas admin exigem
> `is_superuser = true`. Este plano entrega o subconjunto "configurações" (CoreSettings +
> TenantConfig) — o restante do painel (planos, assinaturas, pagamentos) fica no plano 11.

### 1.6 Variáveis de ambiente

Existentes (`server/.env.example`): `DATABASE_URL`, `ENCRYPTION_KEY`, `REDIS_URL`,
`REDIS_BUS_URL`, `S3_*`, `SUPERUSER_*`, `SMARTCORE_<SVC>_ENDPOINT`.
**Novas** (doc 09 §6.5): `JWT_SECRET` (≥32 bytes), `AUTH_ACCESS_TTL_S` (900),
`AUTH_REFRESH_TTL_S` (604800), `AUTH_LOGIN_RATE_LIMIT` (5/60s).

### 1.7 Dependências de workspace — o que falta adicionar

`server/Cargo.toml` já tem: `tonic 0.14.6`, `prost 0.13.3`, `base64 0.22.1`,
`uuid (v4,v7,serde)`, `argon2 0.5`, `redis 0.25`, `sqlx 0.9`, `secrecy 0.10.3`,
`aes-gcm 0.10.3`, `dashmap 6.1`, `chrono`, `thiserror`, `flatbuffers 25`.
**Faltam:** `jsonwebtoken = "9"`, `sha2 = "0.10"`, `rand_core = "0.6"`
(e opcional `base16ct = { version = "0.2", features = ["alloc"] }` — alternativa
manual `format!("{:02x}")` sem dependência extra).

---

## 2. Libs Rust — todas USAR LOCAL (central `doc_dev/libs/rust/`)

| Lib | Versão | Doc local (Última Verificação) | Recursos usados |
|---|---|---|---|
| jsonwebtoken | 9.x | `jsonwebtoken.md` (2026-06-02) | encode/decode HS256, `Validation`, `OnceLock` |
| sha2 | 0.10.x | `sha2.md` (2026-06-02) | `Sha256::digest` do refresh token |
| rand / rand_core | 0.10 / 0.6 | `rand.md` (2026-06-02) | bytes CSPRNG do refresh (usar `rand_core 0.6::OsRng`) |
| base64 | 0.22.1 | `base64.md` (2026-06-01) | `URL_SAFE_NO_PAD` p/ refresh token |
| uuid | 1.x (workspace) | `uuid.md` (2026-06-01) | `jti`/`family_id` (v4), `message_id` (v7) |
| argon2 | 0.5.3 | `argon2.md` (2026-05-31) | já implementado — não tocar |
| redis | 0.25.0 | `redis.md` (2026-06-10) | INCR+EXPIRE p/ rate limit; já usado nos stores |
| sqlx | 0.9 | `sqlx.md` (2026-06-10) | queries macro + `.sqlx` offline; RLS `set_config` |
| secrecy | 0.10.3 | `secrecy.md` (2026-06-01) | `SecretString` nas api_keys do RuntimeConfig |
| aes-gcm | 0.10.3 | `aes_gcm.md` (2026-05-31) | `CipherManager` já implementado |
| dashmap | 6.1.0 | `dashmap.md` (2026-06-01) | `TenantConfigCache` já implementado |
| tonic | 0.14.6 | `tonic.md` (2026-06-04) | fallback gRPC do transport (já implementado) |

### 2.1 JWT — emissão e validação (jsonwebtoken 9)

Claims conforme doc 09 §6.1 (formato canônico):

```rust
use std::sync::OnceLock;
use jsonwebtoken::{encode, decode, Header, Algorithm, EncodingKey, DecodingKey, Validation};
use serde::{Deserialize, Serialize};

static ENCODING_KEY: OnceLock<EncodingKey> = OnceLock::new();
static DECODING_KEY: OnceLock<DecodingKey> = OnceLock::new();

/// Claims do access token (doc 09 §6.1). `tenant_id` vazio = superusuário (contexto global).
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,            // auth_user.id como string
    pub tenant_id: String,      // UUID ou "" para superusuário
    pub scopes: Vec<String>,    // catálogo canônico de escopos
    pub is_superuser: bool,
    pub jti: String,            // UUID v7 — blocklist no logout
    pub iat: usize,
    pub exp: usize,
}

pub fn inicializar_chaves(secret: &str) -> Result<(), AppError> {
    if secret.len() < 32 {
        return Err(AppError::Config("JWT_SECRET deve ter ao menos 32 bytes".into()));
    }
    let _ = ENCODING_KEY.set(EncodingKey::from_secret(secret.as_bytes()));
    let _ = DECODING_KEY.set(DecodingKey::from_secret(secret.as_bytes()));
    Ok(())
}

pub fn gerar_access_token(claims: &Claims) -> Result<String, AppError> { /* encode HS256 */ }
pub fn validar_access_token(token: &str) -> Result<Claims, AppError> {
    // Validation::new(Algorithm::HS256); validate_exp = true por padrão
}
```

Erros relevantes: `ErrorKind::{ExpiredSignature, InvalidSignature}` → tratar como
não autenticado (erro genérico ao cliente).

### 2.2 Refresh token opaco (rand_core + base64 + sha2)

```rust
use rand_core::{OsRng, RngCore};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use sha2::{Digest, Sha256};

/// 32 bytes CSPRNG → base64url sem padding (~43 chars). Nunca persistir em claro.
pub fn gerar_refresh_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// SHA-256 hex minúsculo (64 chars) — é isso que vai ao data_redis.
pub fn hash_refresh_token(token: &str) -> String {
    Sha256::digest(token.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}
```

> **rand 0.10 renomeou `OsRng` → `SysRng`** (API `TryRng`). Decisão mantida: usar
> `rand_core = "0.6"` (já transitivo via `argon2`), que preserva `OsRng` estável.

### 2.3 Rate limiting de login (redis 0.25, INCR+EXPIRE)

```rust
/// Chave auth:rate_limit:<sha256(email|ip)>; primeira tentativa define o EXPIRE da janela.
pub async fn registrar_tentativa(con: &mut ConnectionManager, chave: &str, janela_s: i64)
    -> Result<u64, RedisError> {
    let total: u64 = con.incr(chave, 1).await?;
    if total == 1 { let _: bool = con.expire(chave, janela_s).await?; }
    Ok(total)
}
```

---

## 3. Notas gerais e gotchas

1. **Interceptor ≠ tonic Interceptor.** A borda usa o `transport` próprio; o
   "interceptor" da Camada 1 é um **wrapper de handler** (fn que valida o JWT do
   Envelope/metadata, checa blocklist via `data_redis` e injeta o contexto validado
   no Envelope antes de chamar o handler real). O padrão tonic da revisão anterior
   só vale para o fallback gRPC externo (futuro gRPC-Web/Flutter).
2. **Claims > body:** o `tenant_id` do Envelope deve ser **sobrescrito** pelo
   interceptor com o valor das claims — o cliente nunca define tenant.
3. **Propagação de identidade:** o Envelope precisa ganhar campos aditivos
   (ex.: `auth_user_id`, `auth_scopes`, `auth_is_superuser`) ou um sub-message;
   regenerar FlatBuffers/prost via `contracts/build.rs` (decisão na fase R).
4. **KEEPTTL** (Redis 6+) já usado no `RefreshTokenStore` — reuso detectável até a
   expiração natural; reuso revoga a família inteira automaticamente no store.
5. **`OnceLock`** (std, Rust 1.70+) para chaves JWT e hash dummy — sem `once_cell`.
6. **Invalidação do `TenantConfigCache`:** ao `UpdateTenantConfig`/`UpsertSetting`,
   o `data_postgres` deve invalidar a entrada do cache (e/ou publicar evento para
   os demais processos — worker tem o próprio cache em memória).
7. **Campos cifrados nunca voltam em claro ao admin:** leitura devolve máscara
   (`••••••••`); escrita substitui via `CipherManager::encrypt` (doc 11 §7).
8. **SQLX offline:** novas queries exigem `cargo sqlx prepare` com túnel aberto
   (test_support sobe o túnel sozinho nos testes; ver memória do projeto).
9. **Superusuário sem tenant:** `tenant_id` vazio nas claims; nas RPCs globais usar
   `Uuid::nil()` no Envelope (padrão já usado pelo `control_plane`).

## 4. Referência v1 (origem funcional do app de configuração)

- `old/smart-core-assistant-painel/src/.../modules/services/features/service_hub.py`
  — singleton `SERVICEHUB` expondo prompts/chaves/modelos via `ConfigProvider`.
- `old/.../modules/services/config/context.py` — `RuntimeConfig` (dataclass frozen)
  por requisição via `ContextVar`; equivalente v2 = `config_cache::RuntimeConfig`.
- `old/.../app/settings_manager/models.py` — `CoreSettings {key, value, encrypted,
  description}`; equivalente v2 = tabela `settings_manager_coresettings` (já migrada).
- Telas-alvo: doc 11 §3.7 (TenantConfig — LLM, persona, mensagens, api_keys
  mascaradas) e §6 (contratos `AdminService`).
