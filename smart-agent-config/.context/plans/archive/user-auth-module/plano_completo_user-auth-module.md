# Plano Completo — Login Real + Rotas Admin de Configuração (`user-auth-module`)

> **Reestruturado em 2026-06-12** contra o estado REAL do código (pós-refatoração modular).
> Fontes da verdade: `info_aux_user-auth-module.md` (inventário verificado), doc 09 §5–6
> (spec canônica do login real) e doc 11 §2/§3.7/§5/§6/§7 (subconjunto "configurações" do
> painel admin). Substitui integralmente a versão anterior (que assumia servidor Tonic
> dedicado na borda, fluxos Register/Invite, pools de Postgres na `application` e WebSocket
> Axum — tudo **descartado**).
>
> Idioma: pt-br na documentação/comentários; identificadores em inglês; verbos de função em
> pt-br (`gerar_*`, `validar_*`, `criar_*`), espelhando as crates de infraestrutura existentes.

## Objetivo

Implementar a **autenticação REAL** da v2 (substituindo os mocks da `application::auth::login`)
e expor as **rotas admin de configuração** (CoreSettings + TenantConfig, estilo `service_hub`/
`settings_manager` da v1), de modo que ao final o backend esteja **pronto para plugar o app
Windows (Flutter) de configuração do superusuário** — todas as RPCs autenticadas e funcionais
via `runtime_api`. O Flutter em si fica **fora de escopo** (é o plano 11); o critério é "backend
pronto para plugar".

O módulo **consome** as fundações já entregues e testadas — não as reescreve:
- `infrastructure_postgres`: Argon2id (`auth/password.rs`), repo `auth_user` (`auth/users.rs`),
  `RequestContext` + `exigir_qualquer` (`security.rs`), `CipherManager` (`crypto.rs`),
  `CoreSettings` (`tenants/settings.rs`), `resolve_runtime_config` (`tenants/config.rs`),
  `TenantConfigCache` com `invalidate` (`config_cache.rs`).
- `infrastructure_redis`: `RefreshTokenStore` + `TokenBlocklist` (`auth_tokens.rs`).
- `data_postgres`: `VerifyCredentials` real e testado (`main.rs:1038`).
- `data_redis`: rotas `StoreRefreshToken`/`ValidateAndRotate`/`RevokeFamily`/`BlockToken`/
  `IsTokenBlocked` (todas implementadas e testadas).
- `transport`: `Server::from_env().route().run()`, `conectar_cliente -> MuxClient`,
  `MuxClient::call(env, prazo)`, `bus::publicar_evento_seguranca`.

## Escopo

**Dentro do escopo:**
1. **F6.1 Login real** — JWT HS256 (claims do doc 09 §6.1), refresh opaco 32B + SHA-256,
   TTLs via env, rate limiting, `MuxClient` compartilhado no boot (`AppState`),
   `StoreRefreshToken` com `tenant_id` real.
2. **F6.1 Refresh e Logout** — novas rotas `Refresh`/`Logout` na `runtime_api` orquestrando
   `ValidateAndRotate`/`RevokeFamily`/`BlockToken`; auditoria de `token_reuse_detected`.
3. **F6.2/6.3 Interceptor (Camada 1)** — **wrapper de handler** sobre o `transport` próprio
   (NÃO `tonic::Interceptor`): valida JWT local, checa blocklist, monta contexto, **sobrescreve
   `tenant_id` do Envelope** (claims > body); guard `is_superuser` para rotas admin.
4. **RequestContext unificado** — resolver a duplicação `application` vs `infrastructure_postgres`;
   **extensão ADITIVA** do `envelope.proto` para propagar identidade (`auth_user_id`,
   `auth_scopes`, `auth_is_superuser`); `data_postgres` monta o contexto a partir do Envelope e
   elimina os **4 contextos forjados** (`main.rs` linhas 427, 491, 889, 994).
5. **Rotas admin de configuração** — `data_postgres` + `runtime_api` (guard superuser):
   listar/upsert/delete `CoreSettings` (valores `encrypted` cifrados com `CipherManager`, leitura
   mascarada), `Get/UpdateTenantConfig` (api_keys JSONB cifradas, máscara na leitura), invalidação
   do `TenantConfigCache` ao atualizar, auditoria de toda mutação via `publicar_evento_seguranca`.
6. **Testes** (doc 09 §6.4): fluxo feliz, senha errada, usuário inativo, refresh expirado, reuso
   de refresh, logout + uso de token bloqueado, rotas admin com/sem superuser.

**Fora de escopo (planos/fases futuras):** frontend Flutter (plano 11 etapa B); CRUD de tenants/
planos/assinaturas/pagamentos (plano 11 P1, etapa A do doc 11); `TestEvolutionConnection`/
`TestDatabaseConnection`; provisionamento via `control_plane`; recuperação de senha, MFA, OAuth,
device binding; fan-out realtime por tenant; fluxos `Register`/`InviteUser`/`AcceptInvite`
(o cadastro de usuário/superusuário já é feito pelo `control_plane create-superuser`).

## Arquitetura (invariantes obrigatórias — NÃO violar)

1. **Banco tem UMA porta:** `data_postgres` via RPC. `runtime_api`/`control_plane`/`application`
   são **clientes finos** — **proibido** abrir pool de Postgres na `runtime_api` ou na
   `application`. Nada de `criar_admin_pool` fora do `data_postgres`.
2. **Interceptor ≠ tonic Interceptor.** A borda é o `transport` próprio. O "interceptor" é um
   **wrapper de handler** (`Fn(Envelope) -> BoxFuture<Envelope>` que envolve o handler real).
3. **Claims > body:** o `tenant_id` (e identidade) do Envelope é **sobrescrito** pelo wrapper a
   partir das claims do JWT — o cliente nunca define `tenant_id`/identidade.
4. **`error_core::AppError` é a base** dos erros; usar `to_error_envelope`/`from_envelope` no
   transporte (não inventar tipo de erro novo na borda).
5. **Segredos nunca em claro:** senha só como hash Argon2id; refresh só como SHA-256; api_keys/
   CoreSettings `encrypted` só cifradas (AES-256-GCM via `CipherManager`); leitura ao admin
   devolve máscara `••••••••`.
6. **`OnceLock`** (std) para chaves JWT e hash dummy — sem `once_cell`/`lazy_static`.
7. **Evolução de schema proto é ADITIVA:** manter `schema_version`; só adicionar campos ao final.
8. **Sem `unwrap()/expect()` em produção;** `?`/`Result`. `tracing` instrumentado **sem vazar
   segredos** (token/senha/api_key fora dos spans).
9. **Superusuário sem tenant:** `tenant_id` vazio nas claims → `Uuid::nil()` no Envelope das RPCs
   globais (padrão já usado pelo `control_plane`).
10. **gitflow:** branch `feature/*` a partir de `dev`; commits **sem** auto-referência ao modelo.

---

# FASES (mapeadas ao PREVC)

| Fase | Nome | Agente sugerido | Status |
|---|---|---|---|
| **P** | Planning — escopo real, inventário, decisões fechadas | Backend Specialist | ✅ completed |
| **R** | Review — extensão do Envelope, unificação do RequestContext, catálogo de escopos, contratos | Architect Specialist (+ Security Auditor) | ⬜ pending |
| **E** | Execution — deps, JWT/refresh, login/refresh/logout, wrapper-interceptor, contexto via Envelope, rotas admin de config | Backend Specialist | ⬜ pending |
| **V** | Validation — testes de integração (login, refresh, reuso, logout, admin) com túnel automático | Test Writer (+ Backend Specialist) | ⬜ pending |
| **C** | Confirmation — final-review (Opus) + arquivamento dotcontext | Backend Specialist | ⬜ pending |

---

## FASE P — Planning (concluída)

Saídas: `info_aux_user-auth-module.md` (inventário verificado em 2026-06-12), doc 09 §5–6, doc 11
(subconjunto config) e este `plano_completo`. **Decisões já fechadas:**

- **Transporte da borda:** `transport` próprio (UDS/FlatBuffers + fallback gRPC, `Envelope`
  unificado). NÃO há servidor Tonic dedicado nem middleware global — o interceptor é wrapper.
- **JWT HS256**, access 15 min (`AUTH_ACCESS_TTL_S=900`); refresh opaco 32B, SHA-256, 7 dias
  (`AUTH_REFRESH_TTL_S=604800`); rotação por família + detecção de reuso já no `RefreshTokenStore`.
- **Infra de auth já pronta e testada** (ver §Objetivo) — reusar, não reescrever.
- **Escopo de auth:** apenas Login/Refresh/Logout + interceptor (sem Register/Invite).
- **Escopo de config:** CoreSettings + TenantConfig (o resto do painel 11 fica para depois).
- **`rand_core 0.6` `OsRng`** (estável, já transitivo via `argon2`) em vez de `rand 0.10`
  (`SysRng`).

---

## FASE R — Review (Architect Specialist + Security Auditor)

Decisões de design a **fechar e registrar aqui antes de codar**:

### R1 — Extensão aditiva do `envelope.proto` (propagação de identidade)

O `Envelope` hoje só tem `tenant_id` — **não há identidade** (`user_id`/`scopes`/`is_superuser`).
A Camada 1 → Camada 2 precisa propagar o contexto autenticado. **Decisão proposta:** adicionar
campos aditivos ao final do `message Envelope` (campos 11–13), **mantendo `schema_version`**:

```proto
message Envelope {
  // ... campos 1..10 existentes (não tocar) ...
  // --- Identidade autenticada (preenchida só pelo interceptor da Camada 1; claims > body) ---
  int32  auth_user_id     = 11;  // auth_user.id (0 = não autenticado / rota pública)
  repeated string auth_scopes = 12;  // catálogo canônico de escopos
  bool   auth_is_superuser = 13;  // guard das rotas admin
}
```

> Regenerar prost/FlatBuffers via `contracts/build.rs`. Alternativa avaliada (sub-message
> `AuthContext`) — rejeitada por custo de codec maior; campos planos bastam. **A revisar:**
> nomes finais dos campos e se `flow_permissions` (Vec<i32>) entra no Envelope ou continua
> resolvido sob demanda no `data_postgres` (recomendação: manter `flow_permissions` fora do
> Envelope; carregar via cache `GetCache`/`SetCache` quando o handler precisar do Kanban).

### R2 — Unificação do `RequestContext`

Existem dois tipos (info_aux §1.4):
- `application::RequestContext { tenant_id, user_id, user_scopes, traceparent }` (lib.rs:8).
- `infrastructure_postgres::security::RequestContext { tenant_id, user_id, user_scopes,
  flow_permissions }` (tem `has_permission`, `has_flow_permission`, `exigir_qualquer`).

**Decisão proposta:** o **`infrastructure_postgres::security::RequestContext` é o canônico**
(é o que os repositórios já consomem em `run_in_tenant_transaction`). Ações:
- Adicionar `traceparent: String` a ele (campo aditivo) **ou** mantê-lo fora e propagar o
  traceparent separadamente pelo Envelope (recomendação: manter `traceparent` no Envelope, não
  no contexto — o contexto é sobre identidade/autorização, não trace).
- **Remover** `application::RequestContext` e re-exportar o de `infrastructure_postgres` via
  `application` (`pub use infrastructure_postgres::RequestContext;`), ou fazer a `application`
  parar de depender de um contexto próprio (o login não precisa de contexto — ver E3).
- Decidir o catálogo canônico de escopos (R3) que alimenta `user_scopes`.

### R3 — Catálogo canônico de escopos

Hoje os escopos são strings hardcoded nos handlers (`"atendimentos:read"`, `"clientes:write"`,
`"kanban:admin"`, `"tenant:admin"`). **Fechar nesta fase** o catálogo mínimo necessário para:
- handlers existentes do `data_postgres` (atendimentos, clientes, mensagens);
- rotas admin de config: definir o escopo/condição (recomendação: rotas admin exigem
  `is_superuser == true` **diretamente** via guard, independente de escopos — doc 11 §5).

Saída: tabela `escopo → operações` registrada aqui; de onde os escopos vêm ao montar as claims
no login (recomendação inicial: superusuário recebe `["*"]` ou lista admin; usuário comum recebe
escopos derivados do `TenantUser` — **a definir** se já há leitura de `TenantUser.scopes`/
`module_permissions` ou se entra como follow-up).

### R4 — Contratos das novas RPCs

Fechar as mensagens (proto e/ou JSON payload sobre o Envelope) de:
- `Refresh` / `Logout` na `runtime_api`.
- Admin config: `ListCoreSettings`, `UpsertCoreSetting`, `DeleteCoreSetting`,
  `GetTenantConfig`, `UpdateTenantConfig`.

> Como os handlers atuais usam **payload JSON sobre o Envelope** (não FlatBuffers tipado ainda),
> a recomendação é manter JSON nestes payloads novos (consistência com `VerifyCredentials`,
> `StoreRefreshToken` etc.), reservando o proto tipado para quando o Flutter consumir via gRPC.
> Decisão a confirmar com o Architect.

### R5 — Segurança (Security Auditor)

- Confirmar TTL do `BlockToken` = `max(1, exp - now)` (nunca TTL fixo).
- Confirmar que erros ao cliente são **genéricos** (`unauthenticated`/"credenciais inválidas") —
  nunca revelar se foi senha, usuário inexistente ou inativo (o `VerifyCredentials` já faz isso).
- Confirmar que `token`/`senha`/`api_key`/`JWT_SECRET` ficam **fora** de todo span/log.
- Confirmar máscara `••••••••` na leitura de campos cifrados (nunca decriptar para o admin).

**Saída da fase R:** decisões R1–R5 aprovadas e registradas; ajustes refletidos na fase E.

---

## FASE E — Execution (Backend Specialist)

### Etapa E1 — Dependências de workspace

`server/Cargo.toml` — adicionar a `[workspace.dependencies]` (deps existentes confirmadas:
`tonic 0.14.6`, `prost 0.13.3`, `base64 0.22.1`, `uuid`, `argon2 0.5`, `redis 0.25`, `sqlx 0.9`,
`secrecy 0.10.3`, `aes-gcm 0.10.3`, `dashmap 6.1`, `chrono`, `thiserror`, `flatbuffers 25`):

```toml
[workspace.dependencies]
# ... existentes ...
jsonwebtoken = "9"
sha2         = "0.10"
rand_core    = "0.6"   # OsRng estável (transitivo via argon2); rand 0.10 renomeou p/ SysRng
# base16ct opcional; alternativa sem dep: format!("{b:02x}") (ver E2)
```

A crate `application` passa a depender de `jsonwebtoken`, `sha2`, `rand_core`, `base64`, `uuid`,
`chrono`, `serde`, `serde_json` (já tem `transport`, `contracts`, `error_core`).

### Etapa E2 — Módulo JWT + refresh (crate `application`)

`application/src/jwt.rs` — claims do doc 09 §6.1, chaves via `OnceLock`:

```rust
use std::sync::OnceLock;
use jsonwebtoken::{encode, decode, Header, Algorithm, EncodingKey, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use error_core::AppError;

static ENCODING_KEY: OnceLock<EncodingKey> = OnceLock::new();
static DECODING_KEY: OnceLock<DecodingKey> = OnceLock::new();

/// Claims do access token (doc 09 §6.1). `tenant_id` vazio = superusuário (contexto global).
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,          // auth_user.id como string
    pub tenant_id: String,    // UUID ou "" para superusuário
    pub scopes: Vec<String>,  // catálogo canônico de escopos (fase R3)
    pub is_superuser: bool,
    pub jti: String,          // UUID v7 — blocklist no logout
    pub iat: usize,
    pub exp: usize,
}

/// Inicializa as chaves HMAC a partir do JWT_SECRET (uma vez no boot da runtime_api).
pub fn inicializar_chaves(secret: &str) -> Result<(), AppError> {
    if secret.len() < 32 {
        return Err(AppError::Config("JWT_SECRET deve ter ao menos 32 bytes".into()));
    }
    let _ = ENCODING_KEY.set(EncodingKey::from_secret(secret.as_bytes()));
    let _ = DECODING_KEY.set(DecodingKey::from_secret(secret.as_bytes()));
    Ok(())
}

pub fn gerar_access_token(claims: &Claims) -> Result<String, AppError> {
    let key = ENCODING_KEY.get()
        .ok_or_else(|| AppError::Config("chaves JWT não inicializadas".into()))?;
    encode(&Header::new(Algorithm::HS256), claims, key)
        .map_err(|_| AppError::Auth("falha ao emitir token".into()))
}

/// Valida assinatura e exp (validate_exp = true por padrão na Validation).
pub fn validar_access_token(token: &str) -> Result<Claims, AppError> {
    let key = DECODING_KEY.get()
        .ok_or_else(|| AppError::Config("chaves JWT não inicializadas".into()))?;
    let validation = Validation::new(Algorithm::HS256);
    decode::<Claims>(token, key, &validation)
        .map(|d| d.claims)
        .map_err(|_| AppError::Auth("token inválido ou expirado".into()))
}
```

`application/src/tokens.rs` — refresh opaco + hash (rand_core 0.6, base64url, sha2):

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

/// SHA-256 hex minúsculo (64 chars) — é o que vai ao data_redis (StoreRefreshToken).
pub fn hash_refresh_token(token: &str) -> String {
    Sha256::digest(token.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}
```

> `AppError::Config`/`AppError::Auth` já existem em `error_core` (usados em todo o repo). Se
> `Config` não existir, usar a variante equivalente confirmada na fase R.

### Etapa E3 — Login real (substituir `application/src/auth/login.rs`)

Reescrever `login` **sem** tokens mockados, **sem** `conectar_cliente` por request (recebe os
`MuxClient` do `AppState`), **com** TTLs por env e `tenant_id` real no `StoreRefreshToken`.
Assinatura nova (clientes injetados):

```rust
use contracts::{Envelope, MessageKind};
use error_core::AppError;
use std::time::Duration;
use transport::MuxClient;
use uuid::Uuid;
use crate::jwt::{self, Claims};
use crate::tokens::{gerar_refresh_token, hash_refresh_token};

pub struct AuthDeps {
    pub pg: MuxClient,                 // cliente data_postgres compartilhado (boot)
    pub redis: MuxClient,              // cliente data_redis compartilhado (boot)
    pub access_ttl_s: i64,             // AUTH_ACCESS_TTL_S (900)
    pub refresh_ttl_s: u64,            // AUTH_REFRESH_TTL_S (604800)
}

/// Login real: VerifyCredentials → emite JWT + refresh opaco → StoreRefreshToken.
pub async fn login(
    deps: &AuthDeps,
    traceparent: &str,
    email: &str,
    password: &str,
) -> Result<serde_json::Value, AppError> {
    // 1. VerifyCredentials no data_postgres (Argon2id + is_active + timing-safe).
    let verify_req = montar_envelope(
        Uuid::nil(), traceparent, "VerifyCredentials",
        &serde_json::json!({ "email": email, "password": password }),
    );
    let verify_resp = deps.pg.call(verify_req, Duration::from_secs(5)).await
        .map_err(|e| AppError::Database(format!("RPC VerifyCredentials falhou: {e:?}")))?;
    if verify_resp.kind == MessageKind::Error as i32 {
        // Erro genérico — não revela se foi senha/usuário/inativo.
        return Err(verify_resp.error.map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Auth("credenciais inválidas".into())));
    }
    let user: serde_json::Value = serde_json::from_slice(&verify_resp.payload)
        .map_err(|e| AppError::Internal(format!("payload de credenciais inválido: {e}")))?;
    let user_id = user.get("id").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let is_superuser = user.get("is_superuser").and_then(|v| v.as_bool()).unwrap_or(false);

    // 2. Resolve tenant_id real do usuário (superusuário = vazio/nil).
    //    Recomendação: VerifyCredentials passa a devolver tenant_id (extensão aditiva do reply)
    //    OU resolve-se via RPC dedicada. Decisão na fase R4. Aqui assumimos o reply estendido:
    let tenant_str = user.get("tenant_id").and_then(|v| v.as_str()).unwrap_or("");
    let tenant_opt = Uuid::parse_str(tenant_str).ok().filter(|_| !is_superuser);

    // 3. Monta claims e emite os tokens.
    let agora = chrono::Utc::now().timestamp() as usize;
    let jti = Uuid::now_v7().to_string();
    let family_id = Uuid::now_v7().to_string();
    let claims = Claims {
        sub: user_id.to_string(),
        tenant_id: tenant_opt.map(|t| t.to_string()).unwrap_or_default(),
        scopes: derivar_escopos(is_superuser, &user), // fase R3
        is_superuser,
        jti,
        iat: agora,
        exp: agora + deps.access_ttl_s as usize,
    };
    let access_token = jwt::gerar_access_token(&claims)?;
    let refresh_token = gerar_refresh_token();
    let refresh_hash = hash_refresh_token(&refresh_token);

    // 4. StoreRefreshToken no data_redis com tenant_id REAL (não mais 86400 hardcoded).
    let store_req = montar_envelope(
        tenant_opt.unwrap_or_else(Uuid::nil), traceparent, "StoreRefreshToken",
        &serde_json::json!({
            "token_hash": refresh_hash,
            "user_id": user_id,
            "family_id": family_id,
            "ttl": deps.refresh_ttl_s,
        }),
    );
    let store_resp = deps.redis.call(store_req, Duration::from_secs(5)).await
        .map_err(|e| AppError::Cache(format!("RPC StoreRefreshToken falhou: {e:?}")))?;
    if store_resp.kind == MessageKind::Error as i32 {
        return Err(store_resp.error.map(|e| AppError::from_envelope(&e))
            .unwrap_or_else(|| AppError::Cache("falha ao salvar refresh".into())));
    }

    Ok(serde_json::json!({
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_in": deps.access_ttl_s,
    }))
}
```

> Helper `montar_envelope(tenant, traceparent, method, payload)` cria o `Envelope` REQUEST com
> `message_id = Uuid::now_v7()`, `schema_version` atual, `occurred_at = now_millis()`. Centraliza
> a construção repetida hoje copiada em `login.rs`/`data_redis`.
> **`derivar_escopos`** implementa a decisão R3. **Nota de fase R4:** o `VerifyCredentials` atual
> (`data_postgres:1038`) devolve `{id, username, email, is_superuser}` — **não** devolve
> `tenant_id`; estender o reply (aditivo) com `tenant_id` resolvido do `TenantUser`, ou criar RPC
> `ResolveUserTenant`. Decidir e implementar nesta etapa.

### Etapa E4 — Rate limiting de login (Redis via data_redis ou helper)

Recomendação: novo handler `RegisterLoginAttempt` no `data_redis` (INCR+EXPIRE), chamado **antes**
do `VerifyCredentials`; ao exceder `AUTH_LOGIN_RATE_LIMIT` → `AppError::Auth`/`RateLimited`.

```rust
// infrastructure_redis (novo helper) — chave auth:rate_limit:<sha256(email|ip)>
pub async fn registrar_tentativa(
    con: &mut ConnectionManager, chave: &str, janela_s: i64,
) -> Result<u64, RedisError> {
    let total: u64 = con.incr(chave, 1).await?;
    if total == 1 { let _: bool = con.expire(chave, janela_s).await?; }
    Ok(total)
}
```

> Alternativa mínima: implementar o INCR+EXPIRE direto no handler do `data_redis` reusando o
> `ConnectionManager` do `AppState`. A `application::login` chama a rota e decide o corte.

### Etapa E5 — Rotas Refresh e Logout (`runtime_api`) + `application`

`application/src/auth/refresh.rs`:
1. `hash_refresh_token(refresh)` → `ValidateAndRotate` no `data_redis`.
2. Reply de erro: `NotFound`→`AppError::Auth` (401); `TokenReuse`→`AppError::Auth` **+** publicar
   `token_reuse_detected` no `security:stream` via `bus::publicar_evento_seguranca`.
3. Sucesso: o reply traz `RegistroRefresh {user_id, tenant_id, family_id, rotacionado}`; emitir
   **novo par mantendo `family_id`**; `StoreRefreshToken` do novo hash (mesmo `family_id`).

`application/src/auth/logout.rs`:
1. `BlockToken` do `jti` (extraído das claims do access atual) com TTL = `max(1, exp - now)`.
2. `RevokeFamily` da família do refresh (logout do dispositivo/sessão).

`runtime_api/src/main.rs` — registrar as novas rotas e o `AppState` com clientes compartilhados:

```rust
#[derive(Clone)]
struct AppState {
    pg: transport::MuxClient,      // criado UMA vez no boot
    redis: transport::MuxClient,   // idem
    bus: redis::aio::ConnectionManager, // para publicar_evento_seguranca
    access_ttl_s: i64,
    refresh_ttl_s: u64,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init_telemetry("runtime_api", "production")
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;
    let jwt_secret = std::env::var("JWT_SECRET")
        .map_err(|_| anyhow::anyhow!("JWT_SECRET não configurada"))?;
    application::jwt::inicializar_chaves(&jwt_secret)
        .map_err(|e| anyhow::anyhow!(e.to_string()))?;

    let pg = transport::conectar_cliente("data_postgres").await?;
    let redis = transport::conectar_cliente("data_redis").await?;
    let bus_url = std::env::var("REDIS_BUS_URL")
        .or_else(|_| std::env::var("REDIS_URL"))
        .unwrap_or_else(|_| "redis://127.0.0.1:6379".into());
    let bus = infrastructure_redis::criar_conexao_com_timeouts(&bus_url).await?;

    let state = AppState {
        pg, redis, bus,
        access_ttl_s: env_i64("AUTH_ACCESS_TTL_S", 900),
        refresh_ttl_s: env_u64("AUTH_REFRESH_TTL_S", 604_800),
    };

    // Rotas PÚBLICAS (sem interceptor): Login, Refresh.
    // Rotas PROTEGIDAS (com wrapper-interceptor): StreamAtendimentos, Logout, admin de config.
    let s_login = state.clone();
    let s_refresh = state.clone();
    let s_logout = state.clone();
    let server = Server::from_env("RUNTIME_API")
        .route("Login",   move |env| { let s = s_login.clone();   Box::pin(async move { handler_login(s, env).await }) })
        .route("Refresh", move |env| { let s = s_refresh.clone(); Box::pin(async move { handler_refresh(s, env).await }) })
        .route("Logout",  exigir_auth(state.clone(), false, |s, env| Box::pin(handler_logout(s, env))))
        .route("StreamAtendimentos", exigir_auth(state.clone(), false, |s, env| Box::pin(handler_stream(s, env))))
        // rotas admin (guard superuser = true) registradas em E7
        ;
    server.run().await?;
    Ok(())
}
```

### Etapa E6 — Wrapper-interceptor (Camada 1) + contexto via Envelope

O `transport::Server::route` recebe `Fn(Envelope) -> BoxFuture<'static, Envelope>` (confirmado em
`transport/src/runtime.rs:372`). O interceptor é uma **função de ordem superior** que devolve esse
mesmo tipo, validando o JWT antes de chamar o handler real:

```rust
/// Envolve um handler protegido: valida JWT (do payload/metadata), checa blocklist,
/// sobrescreve identidade/tenant no Envelope (claims > body) e, se `exigir_superuser`,
/// rejeita não-superusuários. Retorna o tipo aceito por Server::route.
fn exigir_auth<F>(
    state: AppState,
    exigir_superuser: bool,
    handler: F,
) -> impl Fn(Envelope) -> futures_util::future::BoxFuture<'static, Envelope> + Clone + Send + Sync + 'static
where
    F: Fn(AppState, Envelope) -> futures_util::future::BoxFuture<'static, Envelope>
        + Clone + Send + Sync + 'static,
{
    move |env: Envelope| {
        let state = state.clone();
        let handler = handler.clone();
        Box::pin(async move {
            // 1. Extrai o JWT (payload.access_token por ora; metadata Authorization no gRPC futuro).
            let token = extrair_bearer(&env);
            let claims = match application::jwt::validar_access_token(&token) {
                Ok(c) => c,
                Err(e) => return erro_envelope(e, &env, "runtime_api"),
            };
            // 2. Blocklist (IsTokenBlocked via data_redis).
            if token_bloqueado(&state.redis, &claims.jti, &env.traceparent).await {
                return erro_envelope(AppError::Auth("token revogado".into()), &env, "runtime_api");
            }
            // 3. Guard de superusuário (rotas admin).
            if exigir_superuser && !claims.is_superuser {
                return erro_envelope(AppError::Auth("acesso negado".into()), &env, "runtime_api");
            }
            // 4. Sobrescreve identidade e tenant no Envelope (claims > body).
            let tenant_id = if claims.tenant_id.is_empty() {
                Uuid::nil().to_string()
            } else {
                claims.tenant_id.clone()
            };
            let env_autenticado = Envelope {
                tenant_id,
                auth_user_id: claims.sub.parse().unwrap_or(0),
                auth_scopes: claims.scopes.clone(),
                auth_is_superuser: claims.is_superuser,
                ..env
            };
            handler(state, env_autenticado).await
        })
    }
}
```

`data_postgres` — substituir os **4 contextos forjados** (`main.rs` 427, 491, 889, 994) por uma
construção a partir do Envelope, eliminando `user_id: 1` e escopos fixos:

```rust
/// Monta o RequestContext canônico a partir da identidade já validada no Envelope (Camada 1).
fn contexto_do_envelope(env: &Envelope) -> RequestContext {
    RequestContext {
        tenant_id: Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil()),
        user_id: env.auth_user_id,
        user_scopes: env.auth_scopes.clone(),
        flow_permissions: vec![], // carregado sob demanda via cache quando o handler precisar (R1)
    }
}
```

> Cada um dos 4 handlers troca o bloco `let ctx = RequestContext { ... user_id: 1 ... }` por
> `let ctx = contexto_do_envelope(&env);`. Os repositórios continuam chamando `exigir_qualquer`
> internamente — agora com escopos reais, fechando o DoD "nenhum handler com user_id/escopos
> hardcoded".

### Etapa E7 — Rotas admin de configuração (data_postgres + runtime_api)

Reusam as peças prontas (`tenants/settings.rs`, `config.rs`, `crypto.rs`, `config_cache.rs`).
Adicionar **handlers no `data_postgres`** (e registrá-los em `Server::route`):

| Rota | Reusa | Observação |
|---|---|---|
| `ListCoreSettings` | `load_all_settings(pool, cipher)` | **mascarar** valores `encrypted` (`••••••••`) — NÃO retornar o decriptado ao admin |
| `UpsertCoreSetting` | `upsert_setting(pool, key, value, encrypted, desc)` | se `encrypted`, cifrar via `CipherManager::encrypt` → formato `ct_b64:nonce_b64:tag_b64` antes de gravar |
| `DeleteCoreSetting` | **novo** `delete_setting(pool, key)` (GAP) | `DELETE FROM settings_manager_coresettings WHERE key=$1` |
| `GetTenantConfig` | `resolve_runtime_config` ou leitura crua de `tenants_tenantconfig` | api_keys exibidas **mascaradas por chave** (`groq_api_key: ••••`) |
| `UpdateTenantConfig` | UPDATE em `tenants_tenantconfig` (RLS via `set_config`) | api_keys cifradas no JSONB (`{ciphertext,nonce,tag}` — formato já lido por `decrypt_from_jsonb`); ao final **invalidar** o `TenantConfigCache` (`cache.invalidate(&tenant_id)`) |

Exemplo de `UpsertCoreSetting` (cifragem + auditoria):

```rust
async fn handler_upsert_core_setting(
    pool: PgPool, cipher: Arc<CipherManager>, mut bus: ConnectionManager, env: Envelope,
) -> Envelope {
    let p: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let key = p.get("key").and_then(|v| v.as_str()).unwrap_or("");
    let raw = p.get("value").and_then(|v| v.as_str()).unwrap_or("");
    let encrypted = p.get("encrypted").and_then(|v| v.as_bool()).unwrap_or(false);
    let desc = p.get("description").and_then(|v| v.as_str()).unwrap_or("");

    // Cifra quando marcado encrypted (formato compatível com load_all_settings: ct:nonce:tag).
    let value = if encrypted {
        match cipher.encrypt(raw.as_bytes()) {
            Ok((ct, nonce, tag)) => format!("{ct}:{nonce}:{tag}"),
            Err(e) => return erro(error_core::AppError::Internal(e.to_string()), &env),
        }
    } else { raw.to_string() };

    if let Err(e) = infrastructure_postgres::tenants::settings::upsert_setting(
        &pool, key, &value, encrypted, desc).await {
        return erro(error_core::AppError::Database(e.to_string()), &env);
    }
    // Auditoria da mutação (sem logar o valor).
    publicar_auditoria(&mut bus, &env, "core_setting_upserted",
        serde_json::json!({ "key": key, "encrypted": encrypted })).await;

    ok_reply(&env, "UpsertCoreSettingReply", serde_json::json!({ "status": "success" }))
}
```

`runtime_api` — expor cada rota admin **com `exigir_auth(state, /*superuser=*/true, ...)`** e
repassar ao `data_postgres` via `state.pg.call(...)` (cliente fino; sem pool). O guard garante
`is_superuser == true` (doc 11 §5). Toda mutação no `data_postgres` publica auditoria via
`publicar_evento_seguranca` (consumida pelo `audit_consumer` → `audit_log`).

> O `data_postgres` precisa de `CipherManager` (`new_from_env`, lê `ENCRYPTION_KEY`) e do
> `TenantConfigCache` no `AppState` para cifrar/mascarar e invalidar. Ambos já existem; basta
> instanciá-los no boot e injetar nos handlers (mesmo padrão de `pool`/`redis_conn`).

---

## FASE V — Validation (Test Writer + Backend Specialist)

Testes de integração seguindo o padrão do projeto: **túnel SSH automático via `test_support`**
(`test_support::ensure_tunnel()` no setup — ver `data_redis` tests) + `SQLX_OFFLINE=true` no build
CI; reset de schema remoto conforme a memória do projeto. Cobrir o DoD do doc 09 §6.4:

1. **Login feliz** — credenciais válidas → reply `{access_token, refresh_token, expires_in}`;
   o access decoda com `tenant_id`/`is_superuser` corretos; o refresh existe no Redis (como hash).
2. **Senha errada** → erro genérico (não revela motivo).
3. **Usuário inativo** → erro genérico (o `VerifyCredentials` já rejeita inativo).
4. **Refresh feliz** → novo par, **mesmo `family_id`**; o hash antigo fica `rotacionado`.
5. **Refresh expirado / inexistente** → `NotFound` → erro de sessão.
6. **Reuso de refresh** → reenviar o token já rotacionado dispara `TokenReuse` → família revogada
   pelo store → erro + evento `token_reuse_detected` no `security:stream`.
7. **Logout** → `jti` entra na blocklist (`IsTokenBlocked` passa a `true`); `RevokeFamily` apaga a
   família; uma chamada protegida com o token bloqueado é rejeitada pelo wrapper.
8. **Rotas admin com/sem superuser** — `is_superuser=false` ou sem token → rejeitado pelo guard;
   superusuário → `UpsertCoreSetting` cifra e persiste, `ListCoreSettings` devolve mascarado,
   `UpdateTenantConfig` cifra api_keys e **invalida** o cache.

Gates de qualidade: `cargo build` (workspace); `cargo clippy --all-targets -- -D warnings`;
`cargo fmt --check`; `cargo sqlx prepare` (com túnel aberto) para as queries novas (`delete_setting`,
UPDATE de `tenants_tenantconfig`).

---

## FASE C — Confirmation

`prevc-final-review` (subagente Opus) compara o implementado contra este plano; corrige desvios;
libera o arquivamento. Depois consolidar o canônico dentro da pasta e mover para `archive/`
(skill `plan-restructuring` §7). Branch `feature/user-auth-module` a partir de `dev`; commits sem
auto-referência ao modelo; comentários em pt-br.

---

## Correções aplicadas (vs. plano antigo)

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 1 | **Borda Tonic dedicada → wrapper de handler sobre `transport` próprio** | Não existe servidor Tonic na borda nem middleware global; `Server::route` aceita `Fn(Envelope)->BoxFuture<Envelope>` | info_aux §1.1, §3.1; `transport/src/runtime.rs:372` |
| 2 | **Removidos Register/Invite/AcceptInvite** | Cadastro de usuário/superusuário é feito pelo `control_plane create-superuser`; fora do escopo de login | info_aux §1.3; doc 09 §6 (só Login/Refresh/Logout) |
| 3 | **Removidos pools de Postgres na `application`/`runtime_api` e `criar_admin_pool` na borda** | Banco tem 1 porta (`data_postgres` via RPC); apps são clientes finos | memória "banco só via infra/RPC"; restrição arquitetural §1 |
| 4 | **Removido WebSocket Axum handshake** | Realtime é gRPC Server Streaming (doc 09 §1.2); o scaffold WS não pertence a este plano | doc 09 §1.2, §7 |
| 5 | **Cliente RPC criado UMA vez no boot (AppState) — não por request** | `login.rs` e o `worker` chamam `conectar_cliente` a cada chamada; `MuxClient` é multiplexado e reconecta | doc 09 §5.2-5; info_aux §1.1 |
| 6 | **Claims do JWT alinhadas ao doc 09 §6.1** (`sub`, `tenant_id`, `scopes`, `is_superuser`, `jti`, `iat`, `exp`) — removidos `iss`/`role`/`email`/`family_id` das claims | `family_id` vive no `RefreshTokenStore`, não nas claims; superusuário identificado por `is_superuser`/tenant vazio | doc 09 §6.1; `auth_tokens.rs` |
| 7 | **Hash do refresh via `format!("{b:02x}")`** (sem `base16ct` obrigatório) | Remove dependência extra; `sha2` basta | info_aux §2.2 |
| 8 | **`RefreshTokenStore::armazenar` recebe `tenant_id: Option<Uuid>` real** (não `86400` hardcoded nem sem tenant) | Assinatura real do store; TTL agora via `AUTH_REFRESH_TTL_S` | `auth_tokens.rs:42`; doc 09 §6.5 |
| 9 | **Interceptor sobrescreve `tenant_id`/identidade no Envelope (claims > body)** | O `handler_login` atual lê `tenant_id` do cliente; viola o princípio | info_aux §3.2; doc 09 §6.3 |
| 10 | **Extensão ADITIVA do `envelope.proto`** (`auth_user_id`/`auth_scopes`/`auth_is_superuser`) | Envelope não tem identidade; precisa propagar Camada 1 → Camada 2 mantendo `schema_version` | info_aux §1.2, §3.3; `envelope.proto` |
| 11 | **`RequestContext` unificado no de `infrastructure_postgres`** (canônico) | Há dois tipos; o da infra já é consumido pelos repositórios e tem `exigir_qualquer` | info_aux §1.4; `security.rs`, `lib.rs:8` |
| 12 | **Eliminar 4 contextos forjados no `data_postgres`** (linhas 427/491/889/994) | `user_id:1` + escopos fixos; o real vem do Envelope | info_aux §1.4; `data_postgres/main.rs` |
| 13 | **Adicionadas rotas admin de config (CoreSettings + TenantConfig)** com cifra/máscara/invalidação/auditoria | Gap real: a fundação está no banco mas não há exposição RPC | info_aux §1.5; doc 11 §3.7, §6, §7 |
| 14 | **`TokenBlocklist::bloquear` com TTL = `max(1, exp-now)`** | Nunca TTL fixo; a infra já existe | doc 09 §6.2; `auth_tokens.rs:156` |
| 15 | **Removido `prost 0.14`/`tonic 0.14` "atualização"** — workspace já tem `tonic 0.14.6` + `prost 0.13.3` | Versões reais confirmadas no `Cargo.toml` | `server/Cargo.toml` |
| 16 | **`AppError` (error_core) é a base; sem `AuthError` próprio na borda** | Padrão único de erro com `to_error_envelope`/`from_envelope` | restrição arquitetural §4; código atual |

---

## Critérios de Aceite (DoD consolidado)

**Auth (doc 09 §6.4):**
- [ ] JWT HS256 real emitido/validado; access expira em 15 min; refresh rotaciona.
- [ ] Reuso de refresh rotacionado revoga a família e audita `token_reuse_detected`.
- [ ] Logout bloqueia o `jti` (TTL = exp-now) e revoga a família (verificável por `IsTokenBlocked`).
- [ ] Nenhum handler do `data_postgres` com `user_id`/escopos hardcoded (4 contextos eliminados).
- [ ] `RequestContext` único no workspace (canônico = `infrastructure_postgres`).
- [ ] Clientes RPC (`MuxClient`) compartilhados no `AppState` (sem `conectar_cliente` por request).
- [ ] Rate limiting de login (por email/IP, via Redis).
- [ ] Interceptor sobrescreve `tenant_id`/identidade do Envelope a partir das claims (claims > body).
- [ ] Testes: feliz, senha errada, inativo, refresh expirado, reuso, logout + token bloqueado.

**Pronto para plugar o app de configuração (doc 11 subconjunto config):**
- [ ] `runtime_api` expõe rotas admin de config com guard `is_superuser == true` (rejeita comum/sem token).
- [ ] `ListCoreSettings`/`UpsertCoreSetting`/`DeleteCoreSetting` funcionais; valores `encrypted` cifrados via `CipherManager`, leitura **mascarada**.
- [ ] `GetTenantConfig`/`UpdateTenantConfig` funcionais; api_keys cifradas no JSONB, leitura mascarada por chave.
- [ ] `UpdateTenantConfig`/`UpsertCoreSetting` invalidam o `TenantConfigCache`.
- [ ] Toda mutação admin gera evento de auditoria via `publicar_evento_seguranca` (→ `audit_log`).
- [ ] Campos cifrados nunca retornam em claro nem aparecem em logs/spans.

**Qualidade:** `cargo build` + `cargo clippy --all-targets -- -D warnings` + `cargo fmt --check`
limpos; `.sqlx` atualizado; comentários pt-br; sem `unwrap/expect` em produção; commits sem
auto-referência ao modelo.

## Variáveis de ambiente novas (doc 09 §6.5)

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `JWT_SECRET` | ✅ | — | Chave HMAC-SHA256 do access token (≥ 32 bytes). |
| `AUTH_ACCESS_TTL_S` | ⬜ | `900` | Vida útil do access token (15 min). |
| `AUTH_REFRESH_TTL_S` | ⬜ | `604800` | Vida útil do refresh token (7 dias). |
| `AUTH_LOGIN_RATE_LIMIT` | ⬜ | `5/60s` | Tentativas de login por janela (email+IP). |

Já existentes e reusadas: `ENCRYPTION_KEY` (CipherManager), `REDIS_URL`/`REDIS_BUS_URL`,
`DATABASE_URL`, `SMARTCORE_<SVC>_ENDPOINT` (em Windows: `tcp://...`).
