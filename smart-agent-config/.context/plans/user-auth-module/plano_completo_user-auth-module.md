# Plano Completo — Módulo de Autenticação de Usuário (`user-auth-module`)

> Verdade técnica detalhada do módulo de autenticação. Reestruturado a partir de
> `doc_dev/planejamento/03-comunicacao-e-autenticacao.md` e validado contra a central de libs
> (`doc_dev/libs/rust/`), contra a documentação atual coletada via Context7 (`info_aux`) e contra
> o **código já implementado** em `infrastructure_postgres` e `infrastructure_redis`.
> Idioma: pt-br; identificadores em inglês, verbos de função em pt-br (`criar_*`, `validar_*`,
> `gerar_*`), espelhando as crates de infraestrutura existentes.

## Objetivo

Implementar o **módulo de autenticação de usuário** da v2: emissão e validação de JWT (HS256),
ciclo de vida de sessão (access + refresh tokens com rotação por família), e o primeiro ponto de
entrada gRPC real (`apps/runtime_api`) com interceptor de autenticação que constrói o
`RequestContext`. O módulo **consome** as fundações já entregues (`infrastructure_postgres`:
`AuthUser`, `Tenant`, `TenantUser`, Argon2, RLS; `infrastructure_redis`: `RefreshTokenStore`,
`TokenBlocklist`, `CachePermissoes`) e fecha a defesa-em-3-camadas descrita no doc 03.

## Escopo

**Dentro do escopo:**
- Dependências de workspace: `jsonwebtoken`, `sha2`, `base16ct`, `rand_core`, `tonic`, `prost`,
  `tower`, `http`, `tonic-build`.
- Crate `contracts` com `proto/auth.proto` (serviço `AuthService` + mensagens).
- Módulo JWT: `Claims`, `gerar_access_token`, `validar_access_token`, chaves via `OnceLock`.
- Geração e hashing de refresh tokens (`rand_core::OsRng` → base64url → SHA-256 hex).
- Validação de política de senha (camada de aplicação).
- Extensões em `infrastructure_postgres`: `TenantUserRepository::criar_owner` (bootstrap sem
  `RequestContext`) e `criar_admin_pool` (pool BYPASSRLS lendo `DATABASE_ADMIN_URL`).
- Rate limiting de login no Redis (`auth:rate_limit:<ip_hash>`).
- Crate `application` com `AuthService`: `Register`, `Login`, `RefreshToken`, `Logout`,
  `InviteUser`, `AcceptInvite`.
- App `runtime_api`: servidor Tonic gRPC + `AuthInterceptor` + injeção de `RequestContext`.
- Scaffold de handshake WebSocket autenticado (Axum) — validação de token, sem fan-out ainda.
- Testes de integração dos quatro fluxos contra PostgreSQL + Redis reais.

**Fora do escopo (fases futuras):** fan-out realtime por tenant (WebSocket pub/sub completo);
seleção de tenant múltiplo (hoje a relação é 1-para-1); recuperação de senha por e-mail; MFA/2FA;
refresh token binding por device; OAuth/social login; envio real de e-mail de convite (apenas o
registro do `TenantInvite` é criado).

## Arquitetura (invariantes obrigatórias)

1. **Defesa em 3 camadas** (doc 03 §4): Interceptor JWT → validação de escopos em Rust → RLS no
   PostgreSQL. Nenhuma query de tenant corre fora de `run_in_tenant_transaction`.
2. **`tenant_id` só vem das Claims do JWT** (via `RequestContext`), nunca do body da requisição.
3. **Segredos nunca em claro:** senha só como hash Argon2id; refresh token só como hash SHA-256.
4. **`JWT_SECRET` lido uma vez** via `std::sync::OnceLock` (sem `once_cell`/`lazy_static`).
5. **Pool admin (BYPASSRLS) isolado:** usado **exclusivamente** em lookups pré-tenant
   (login, aceite de convite). Todo o resto usa o pool tenant-scoped + RLS.
6. **Erro por crate:** `application` define `AuthError` (thiserror), mapeado para `tonic::Status`
   na borda do `runtime_api`. Não vazar erros internos ao cliente.
7. **Sem `unwrap()/expect()` em produção;** `?`/`Result`. Comentários em pt-br.
8. **Rotas públicas** (`Register`, `Login`, `RefreshToken`, `AcceptInvite`) não passam pelo
   `AuthInterceptor`.

---

# FASES (mapeadas ao PREVC)

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo, decisões de transporte/sessão e contrato | Backend Specialist | ✅ completed |
| **R** | Review — contrato proto, modelo de token/JWT e estratégia de pools | Backend Specialist (+ Security Auditor) | ⬜ pending |
| **E** | Execution — deps, JWT, refresh, application e `runtime_api` | Backend Specialist | ⬜ pending |
| **V** | Validation — testes de integração dos 4 fluxos (PG + Redis reais) | Test Writer (+ Backend Specialist) | ⬜ pending |
| **C** | Confirmation — final-review e arquivamento dotcontext | Backend Specialist | ⬜ pending |

---

## FASE P — Planning (concluída)

Saídas: `doc_dev/planejamento/03-comunicacao-e-autenticacao.md` (registro original, agora
histórico), este `plano_completo` e o `info_aux`. Decisões-chave já fechadas no doc 03:

- **Transporte:** gRPC (tonic) para comandos/consultas + WebSocket (axum) para realtime.
- **JWT HS256**, access 15 min, refresh opaco 7 dias com rotação por família.
- **Multi-tenant 1-para-1** resolvido automaticamente no login (`UNIQUE(user_id)` em
  `tenants_tenantuser`).
- **Argon2id** via `Argon2::default()` (já implementado).
- **Escopo da entrega:** Opção B (serviço de domínio + `runtime_api` mínimo).

---

## FASE R — Review (Backend Specialist + Security Auditor)

Revisar **antes** de codar:

1. **Contrato `auth.proto`** — assinaturas das RPCs e mensagens (§Etapa 2). Confirmar que
   `AuthResponse` não vaza dados sensíveis e que erros usam `Status` (não campos de erro no body).
2. **Modelo de token** — confirmar claims (incl. `family_id` e `iat`), TTLs, e que o `jti` da
   blocklist usa TTL = `exp - now()`.
3. **Estratégia de pools** — validar o isolamento do pool admin (BYPASSRLS) e que ele só é tocado
   nos lookups pré-tenant. Risco de vazamento cross-tenant se usado em query de negócio.
4. **`rand_core` vs `rand`** — confirmar a decisão de usar `rand_core 0.6` (`OsRng` estável) em vez
   de `rand 0.10` (`SysRng`). Ver `info_aux` §Notas Gerais.
5. **Segurança do query-param do WebSocket** — revisar mitigações (token curto, logs anonimizados).

Saída: aprovação do contrato e do modelo de segurança; ajustes registrados aqui.

---

## FASE E — Execution (Backend Specialist)

### Etapa 1 — Workspace e dependências

`server/Cargo.toml` — adicionar aos `members` os novos crates e às `[workspace.dependencies]`:

```toml
members = [
    "crates/infrastructure_postgres",
    "crates/infrastructure_redis",
    "crates/contracts",
    "crates/application",
    "apps/runtime_api",
]

[workspace.dependencies]
# ... existentes ...
jsonwebtoken = "9"
sha2         = "0.10"
base16ct     = { version = "0.2", features = ["alloc"] }
rand_core    = "0.6"                       # OsRng estável (ver info_aux)
tonic        = "0.14"
prost        = "0.14"
tower        = "0.4"
http         = "1.0"
tonic-build  = "0.14"                      # build-dependency
```

> **Nota de versão:** `tonic 0.14.6` + `prost 0.14` (confirmado via Context7, 2026-06-02).
> Não usar 0.12.x. `rand_core 0.6` já é dependência transitiva de `argon2` — preferido a
> introduzir `rand 0.10` (que renomeou `OsRng` → `SysRng`).

### Etapa 2 — Crate `contracts` + `auth.proto`

Criar `server/crates/contracts/` com `proto/auth.proto`, `build.rs` e `src/lib.rs`.

`proto/auth.proto`:
```protobuf
syntax = "proto3";
package smartcore.auth.v1;

import "google/protobuf/empty.proto";

service AuthService {
  rpc Register     (RegisterRequest)     returns (AuthResponse);
  rpc Login        (LoginRequest)        returns (AuthResponse);
  rpc RefreshToken (RefreshRequest)      returns (AuthResponse);
  rpc Logout       (LogoutRequest)       returns (google.protobuf.Empty);
  rpc InviteUser   (InviteUserRequest)   returns (google.protobuf.Empty);
  rpc AcceptInvite (AcceptInviteRequest) returns (AuthResponse);
}

message RegisterRequest {
  string username     = 1;
  string email        = 2;
  string password     = 3;
  string full_name    = 4;
  string company_name = 5;
  string company_slug = 6;
}

message LoginRequest {
  string identifier = 1; // email OU username
  string password   = 2;
}

message RefreshRequest { string refresh_token = 1; }
message LogoutRequest  { string refresh_token = 1; } // access vem no metadata Authorization

message InviteUserRequest {
  string email = 1;
  string name  = 2;
  string role  = 3;
}

message AcceptInviteRequest {
  string token    = 1; // token do convite
  string username = 2;
  string password = 3;
}

message AuthResponse {
  string access_token  = 1;
  string refresh_token = 2;
}
```

`build.rs`:
```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(true) // cliente útil para testes de integração e Flutter (via proto)
        .compile_protos(&["proto/auth.proto"], &["proto"])?;
    Ok(())
}
```

`src/lib.rs`:
```rust
//! Contratos gRPC compartilhados entre runtime_api e clientes.
pub mod auth {
    tonic::include_proto!("smartcore.auth.v1");
}
```

### Etapa 3 — Módulo JWT (no crate `application`)

`application/src/jwt.rs`:
```rust
use std::sync::OnceLock;
use jsonwebtoken::{encode, decode, Header, Algorithm, EncodingKey, DecodingKey, Validation};
use serde::{Serialize, Deserialize};

static ENCODING_KEY: OnceLock<EncodingKey> = OnceLock::new();
static DECODING_KEY: OnceLock<DecodingKey> = OnceLock::new();

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub iss: String,
    pub sub: String,                 // user_id como string
    pub iat: usize,
    pub exp: usize,
    pub email: String,
    pub tenant_id: Option<String>,   // None para superuser
    pub role: String,
    pub scopes: Vec<String>,
    pub jti: String,
    pub family_id: String,
}

/// Inicializa as chaves HMAC a partir do JWT_SECRET (chamado uma vez no boot do runtime_api).
pub fn inicializar_chaves(secret: &str) -> Result<(), AuthError> {
    if secret.len() < 32 {
        return Err(AuthError::Config("JWT_SECRET deve ter ao menos 32 bytes".into()));
    }
    let _ = ENCODING_KEY.set(EncodingKey::from_secret(secret.as_bytes()));
    let _ = DECODING_KEY.set(DecodingKey::from_secret(secret.as_bytes()));
    Ok(())
}

pub fn gerar_access_token(claims: &Claims) -> Result<String, AuthError> {
    let key = ENCODING_KEY.get().ok_or(AuthError::Config("chaves JWT não inicializadas".into()))?;
    encode(&Header::new(Algorithm::HS256), claims, key).map_err(|_| AuthError::TokenInvalido)
}

pub fn validar_access_token(token: &str) -> Result<Claims, AuthError> {
    let key = DECODING_KEY.get().ok_or(AuthError::Config("chaves JWT não inicializadas".into()))?;
    let mut validation = Validation::new(Algorithm::HS256);
    validation.set_issuer(&["smartcore"]);
    decode::<Claims>(token, key, &validation)
        .map(|d| d.claims)
        .map_err(|_| AuthError::TokenInvalido)
}
```

> Fonte das assinaturas: `doc_dev/libs/rust/jsonwebtoken.md` (Context7 `/keats/jsonwebtoken`).
> `validate_exp = true` é o default da `Validation` — não precisa setar.

### Etapa 4 — Refresh token e política de senha

`application/src/tokens.rs`:
```rust
use rand_core::{OsRng, RngCore};
use sha2::{Sha256, Digest};
use base16ct::lower;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

/// Gera um refresh token opaco (32 bytes → base64url sem padding, ~43 chars).
pub fn gerar_refresh_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// Hash SHA-256 (hex minúsculo, 64 chars) para indexar no Redis. Nunca grava o token em claro.
pub fn hash_refresh_token(token: &str) -> String {
    lower::encode_string(&Sha256::digest(token.as_bytes()))
}
```

`application/src/password_policy.rs`:
```rust
/// Valida a complexidade da senha (doc 03 §3.3). Retorna lista de violações (vazia = OK).
pub fn validar_politica_senha(senha: &str) -> Result<(), AuthError> {
    let mut faltas = Vec::new();
    if senha.chars().count() < 8 { faltas.push("mínimo 8 caracteres"); }
    if !senha.chars().any(|c| c.is_ascii_uppercase()) { faltas.push("uma letra maiúscula"); }
    if !senha.chars().any(|c| c.is_ascii_lowercase()) { faltas.push("uma letra minúscula"); }
    if !senha.chars().any(|c| c.is_ascii_digit())     { faltas.push("um número"); }
    if !senha.chars().any(|c| !c.is_alphanumeric())   { faltas.push("um caractere especial"); }
    if faltas.is_empty() { Ok(()) }
    else { Err(AuthError::SenhaFraca(faltas.join(", "))) }
}
```

### Etapa 5 — Extensões em `infrastructure_postgres`

**(a) `criar_admin_pool`** em `connection.rs` (GAP: hoje só existe `criar_pool` lendo
`DATABASE_URL`):
```rust
/// Pool administrativo com BYPASSRLS, lido de DATABASE_ADMIN_URL. Uso EXCLUSIVO em
/// lookups pré-tenant (login, aceite de convite). NUNCA usar em query de negócio.
pub async fn criar_admin_pool(max_connections: u32) -> Result<PgPool, DbError> {
    let url = std::env::var("DATABASE_ADMIN_URL")
        .map_err(|_| DbError::ConfigError("DATABASE_ADMIN_URL não configurada".into()))?;
    let pool = PgPoolOptions::new().max_connections(max_connections).connect(&url).await?;
    Ok(pool)
}
```

**(b) `TenantUserRepository::criar_owner`** em `tenants/tenants.rs` — bootstrap sem
`RequestContext` (doc 03 §3.4). O método `criar` existente continua para convites de admin logado:
```rust
async fn criar_owner(
    &self,
    tx: &mut Transaction<'_, Postgres>,
    user_id: i32,
    tenant_id: Uuid,
    role: &str,
) -> Result<TenantUser, DbError> {
    // app.current_tenant já foi setado por TenantRepository::criar nesta mesma tx.
    let row = sqlx::query_as!(
        TenantUser,
        r#"INSERT INTO tenants_tenantuser (user_id, tenant_id, role, created_by_id)
           VALUES ($1, $2, $3, $1)
           RETURNING id, user_id, tenant_id, role, module_permissions,
                     flow_permissions, is_active, created_at, created_by_id"#,
        user_id, tenant_id, role
    )
    .fetch_one(&mut **tx)
    .await
    .map_err(DbError::from_sqlx_unique)?;
    Ok(row)
}
```

> Adicionar `criar_owner` à trait `TenantUserRepository` e à impl `PostgresTenantUserRepository`.
> Re-exportar nada novo é necessário (já exportado via `tenants`).

### Etapa 6 — Rate limiting de login (Redis)

Adicionar em `infrastructure_redis` um helper simples (ou implementar no `application` usando o
`ConnectionManager`). Chave `auth:rate_limit:<ip_hash>`, `INCR` + `EXPIRE`:
```rust
/// Incrementa o contador de tentativas e retorna o total na janela. Primeira chamada seta EXPIRE.
pub async fn registrar_tentativa_login(
    con: &mut ConnectionManager, ip_hash: &str, janela_segundos: u64,
) -> Result<u64, RedisError> {
    let chave = format!("auth:rate_limit:{ip_hash}");
    let total: u64 = con.incr(&chave, 1).await?;
    if total == 1 { let _: bool = con.expire(&chave, janela_segundos as i64).await?; }
    Ok(total)
}
```
O `AuthService::login` checa `total > LOGIN_RATE_LIMIT_MAX` → `AuthError::RateLimited`.

### Etapa 7 — Crate `application` — `AuthService`

`server/crates/application/` depende de `infrastructure_postgres`, `infrastructure_redis`,
`contracts`, `jsonwebtoken`, `sha2`, `base16ct`, `rand_core`, `base64`, `tonic`, `thiserror`,
`chrono`, `uuid`.

`application/src/errors.rs` — `AuthError` (thiserror) + `From<AuthError> for tonic::Status`:
```rust
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("credenciais inválidas")]            CredenciaisInvalidas,
    #[error("sessão inválida ou expirada")]      SessaoInvalida,
    #[error("token inválido")]                   TokenInvalido,
    #[error("senha fraca: {0}")]                 SenhaFraca(String),
    #[error("muitas tentativas de login")]       RateLimited,
    #[error("conflito: {0}")]                    Conflito(String),     // email/username/slug
    #[error("convite inválido ou expirado")]     ConviteInvalido,
    #[error("erro de configuração: {0}")]        Config(String),
    #[error(transparent)]                        Db(#[from] infrastructure_postgres::DbError),
    #[error(transparent)]                        Redis(#[from] infrastructure_redis::RedisError),
}

impl From<AuthError> for tonic::Status {
    fn from(e: AuthError) -> Self {
        use AuthError::*;
        match e {
            CredenciaisInvalidas | SessaoInvalida | TokenInvalido => tonic::Status::unauthenticated(e.to_string()),
            RateLimited => tonic::Status::resource_exhausted(e.to_string()),
            SenhaFraca(_) | Conflito(_) | ConviteInvalido => tonic::Status::invalid_argument(e.to_string()),
            Config(_) | Db(_) | Redis(_) => tonic::Status::internal("erro interno"), // não vaza detalhe
        }
    }
}
```

`application/src/auth_service.rs` — orquestra os fluxos (doc 03 §5). Estrutura:
```rust
pub struct AuthService {
    pub pool: PgPool,            // tenant-scoped (RLS)
    pub admin_pool: PgPool,      // BYPASSRLS (lookups pré-tenant)
    pub redis: ConnectionManager,
    pub jwt_expiry_secs: i64,
    pub refresh_ttl_secs: u64,
}
```

**Fluxos (resumo — detalhe canônico no doc 03 §5):**

- **`register`** (§5.1): valida senha + slug + unicidade → `run_in_tenant_transaction` não serve
  aqui porque o tenant ainda não existe; usar transação manual: `criar` auth_user (admin_pool ou
  pool), `TenantRepository::criar` (seta `app.current_tenant`), `criar_owner(role="admin")` →
  commit → gera `family_id`, par de tokens, `RefreshTokenStore::armazenar`. Retorna `AuthResponse`.
- **`login`** (§5.2): rate limit → `buscar_por_email`/`buscar_por_username` (admin_pool) → erro
  genérico se inexistente/inativo → `verify_password` → `buscar_por_user_id` (admin_pool) →
  monta `Claims` (incl. `family_id` novo, `jti`, `iat`, `exp`) → `gerar_access_token` →
  `gerar_refresh_token` + `armazenar(hash)` → `atualizar_ultimo_login` (via `tokio::spawn`) →
  `AuthResponse`.
- **`refresh_token`** (§5.3): `hash_refresh_token` → `RefreshTokenStore::validar_e_rotacionar`
  (mapeia `NotFound`→`SessaoInvalida`, `TokenReuse`→`SessaoInvalida`) → recarrega scopes
  (re-deriva de `buscar_por_user_id` ou cache) → novo `jti`/`iat`, mesmo `family_id` → novo par →
  `armazenar` novo hash com mesmo `family_id`.
- **`logout`** (§5.4): extrai `jti`/`exp`/`family_id` do `RequestContext` (injetado pelo
  interceptor) → `ttl = max(1, exp - now)` → `TokenBlocklist::bloquear(jti, ttl)` →
  `RefreshTokenStore::revogar_familia(family_id)`.
- **`invite_user`** (§5.5): exige `RequestContext` com `tenant:admin` → `TenantInviteRepository::criar`
  com token UUID e `expires_at = now + 72h`.
- **`accept_invite`** (§5.5): `buscar_por_token` (admin_pool) → valida `expires_at`/`used` →
  transação: cria auth_user + `criar_owner(role do convite, tenant do convite)` +
  `marcar_usado` → par de tokens.

### Etapa 8 — App `runtime_api`

`server/apps/runtime_api/src/main.rs`:
```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Carregar config de ambiente (ver doc 03 §7)
    let jwt_secret = std::env::var("JWT_SECRET")?;
    application::jwt::inicializar_chaves(&jwt_secret)?;

    // 2. Pools e Redis
    let pool = infrastructure_postgres::criar_pool(10).await?;
    let admin_pool = infrastructure_postgres::criar_admin_pool(4).await?;
    let redis = infrastructure_redis::criar_conexao_redis().await?;

    // 3. Serviço + interceptor
    let svc = application::AuthService { pool, admin_pool, redis, jwt_expiry_secs: 900, refresh_ttl_secs: 604_800 };
    let auth_grpc = contracts::auth::auth_service_server::AuthServiceServer::new(svc);

    let addr = format!("0.0.0.0:{}", std::env::var("GRPC_PORT").unwrap_or("50051".into())).parse()?;
    tonic::transport::Server::builder()
        .add_service(auth_grpc) // rotas públicas: o interceptor por-rota é aplicado nos handlers protegidos
        .serve(addr)
        .await?;
    Ok(())
}
```

**`AuthInterceptor`** (`runtime_api/src/interceptor.rs`) — conforme `info_aux` (tonic):
extrai `authorization: Bearer <jwt>` do `metadata`, `validar_access_token`, checa
`TokenBlocklist::esta_bloqueado(jti)`, carrega `flow_permissions` do `CachePermissoes` (TTL 60s),
constrói `RequestContext` e `request.extensions_mut().insert(ctx)`. Erros → `Status::unauthenticated`.

> **Rotas públicas:** `Register`, `Login`, `RefreshToken`, `AcceptInvite` não exigem JWT. Como o
> interceptor do tonic é global por padrão, separar os handlers públicos: usar `interceptor` apenas
> no(s) serviço(s) protegido(s), ou checar o método no interceptor e pular as rotas públicas.

### Etapa 9 — WebSocket handshake autenticado (scaffold)

`runtime_api/src/ws.rs` (Axum, conforme `doc_dev/libs/rust/axum.md`): aceitar `Authorization:
Bearer` OU `?token=<jwt>`; `validar_access_token` + checagem de blocklist no upgrade; rejeitar com
close code `4401` se inválido. Sem fan-out por tenant ainda (fase futura) — apenas estabelece e
valida a sessão. Servidor Axum em porta separada (`WS_PORT`, padrão 8080).

---

## FASE V — Validation (Test Writer + Backend Specialist)

Testes de integração (banco lógico Redis 15 + PostgreSQL de teste com RLS), `RUST_TEST_THREADS=1`:

1. **Register** → cria auth_user + tenant + tenant_user(admin); retorna par válido; access decoda
   com `tenant_id` correto; refresh existe no Redis (como hash).
2. **Login** sucesso/falha: senha errada → `unauthenticated` genérico; usuário inativo → idem;
   rate limit dispara `resource_exhausted` após N tentativas.
3. **Refresh** feliz: rotação emite novo par, mesmo `family_id`; **reuso**: reenviar o token
   anterior dispara `TokenReuse` → família revogada → `unauthenticated`.
4. **Logout**: `jti` entra na blocklist (interceptor passa a rejeitar); `revogar_familia` apaga os
   refresh tokens da sessão.
5. **Interceptor**: requisição protegida sem token → `unauthenticated`; com token blocklisted →
   `unauthenticated`; com escopo insuficiente em endpoint protegido → `permission_denied`.
6. **AcceptInvite**: convite válido cria usuário no tenant correto; expirado/usado → erro.

Gates de qualidade: `cargo build` workspace; `cargo clippy --all-targets -D warnings`;
`cargo fmt --check`; `SQLX_OFFLINE=true` para o build CI.

---

## FASE C — Confirmation

`prevc-final-review` (subagente Opus) compara o implementado contra este plano; corrige desvios;
libera o arquivamento. Depois consolidar o canônico dentro da pasta e mover para `archive/`
(skill `plan-restructuring` §7).

---

## Correções aplicadas (vs. plano base do doc 03)

| # | Correção | Motivo / Fonte |
|---|----------|----------------|
| 1 | `rand::rngs::OsRng` → **`rand_core 0.6` `OsRng`** | `rand 0.10` renomeou `OsRng`→`SysRng` (API `TryRng`); `rand_core 0.6` é estável e já transitivo via `argon2`. Context7 `/rust-random/rand`. |
| 2 | **`tonic 0.14.6` + `prost 0.14`** (plano citava genérico/0.12) | Versões atuais confirmadas via Context7 `/hyperium/tonic` (2026-06-02). |
| 3 | Adicionado **`criar_admin_pool`** (`DATABASE_ADMIN_URL`) | GAP real: `connection.rs` só tinha `criar_pool`(`DATABASE_URL`); os repos de lookup pré-tenant exigem pool BYPASSRLS. |
| 4 | Hash do refresh via **`sha2` + `base16ct`** (hex) | Padrão idiomático atual; `RefreshTokenStore` espera o hash, não o token. Context7 `/rustcrypto/hashes`. |
| 5 | **`std::sync::OnceLock`** em vez de `once_cell`/`lazy_static` | Estável desde Rust 1.70; remove dependência. |
| 6 | `criar_owner` **separado** de `criar` (sem `RequestContext`) | `TenantUserRepository::criar` exige `tenant:admin`; no registro inicial não há contexto (doc 03 §3.4). |
| 7 | Erros mapeados para **`tonic::Status`** (não HTTP) | Transporte é gRPC; doc 03 já corrigido para `unauthenticated`/`permission_denied`. |
| 8 | `Claims` inclui **`iat` e `family_id`** | `family_id` necessário ao logout; `iat` para auditoria. Confirmado contra `jsonwebtoken` (campos livres no struct). |
| 9 | `AcceptInvite` adicionado às **rotas públicas** | O convidado não tem JWT no aceite. |
| 10 | Política de senha retorna **lista de violações** | Melhor DX no cliente do que erro genérico. |

## Verificação

`docker compose -f docker/compose/data.yml up -d` (PostgreSQL + Redis) → exportar `JWT_SECRET`,
`DATABASE_URL`, `DATABASE_ADMIN_URL`, `REDIS_URL` → `cargo build` (workspace) →
`RUST_TEST_THREADS=1 cargo test -p application -p infrastructure_postgres -p infrastructure_redis`
→ `cargo clippy --all-targets -D warnings` + `cargo fmt --check`. Branch
`claude/user-auth-module-plan-dykMV` a partir de `dev`; commits sem auto-referência ao modelo;
comentários em pt-br.
