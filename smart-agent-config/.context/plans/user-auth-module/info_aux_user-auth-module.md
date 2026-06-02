# Documentação Auxiliar — User Auth Module

> Gerado em: 2026-06-02
> Plano canônico: `.context/plans/user-auth-module.md`
> Plano completo: `.context/plans/user-auth-module/plano_completo_user-auth-module.md`

---

## Libs Rust — USAR LOCAL (central curada)

### argon2 (0.5.3) — ✅ ATUALIZADA (2026-05-31)
> Fonte: `doc_dev/libs/rust/argon2.md`

Já implementado em `infrastructure_postgres/src/auth/password.rs`. API estável.
Parâmetros reais do `Argon2::default()` com versão 0.5.3: `m_cost = 19456 KB, t_cost = 2, p_cost = 1`
(nota: a `doc_dev/libs/rust/argon2.md` cita 65536 KB — divergência na doc local; o código
real usa `Argon2::default()` e o resultado real deve ser validado rodando o build).

**OsRng via argon2 (reexportado):**
```rust
use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::rand_core::RngCore;
```
`OsRng` está disponível transitivamente via `argon2`. Para gerar bytes de refresh token
sem adicionar `rand` como dependência direta, prefira `rand_core = "0.6"` no workspace.

---

### base64 (0.22.1) — ✅ ATUALIZADA (2026-06-01)
> Fonte: `doc_dev/libs/rust/base64.md`

Já no workspace. Para codificar refresh tokens em base64url sem padding:
```rust
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};

let token_str = URL_SAFE_NO_PAD.encode(&bytes);           // bytes → base64url
let bytes = URL_SAFE_NO_PAD.decode(&token_str)?;          // base64url → bytes
```

---

### axum (0.7.5) — ✅ ATUALIZADA (2026-05-31)
> Fonte: `doc_dev/libs/rust/axum.md`

WebSocket no handshake com autenticação:
```rust
use axum::extract::ws::{WebSocketUpgrade, WebSocket};

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Extension(ctx): Extension<RequestContext>, // injetado pelo middleware
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state, ctx))
}
```

**Nota de segurança (query param):** Axum aceita extração via `Query<T>` para o token
WS quando headers não são suportados pelo cliente. O token deve ser validado imediatamente
no `on_upgrade` e nunca logar a query string com o token.

---

### uuid (1.10.0) — ✅ ATUALIZADA (2026-06-01)
> Fonte: `doc_dev/libs/rust/uuid.md`

Já no workspace com features `v4`, `v7`, `serde`. Para `jti` e `family_id` usar `v4`:
```rust
let jti = Uuid::new_v4().to_string();
let family_id = Uuid::new_v4().to_string();
```

---

## Libs Rust — CRIAR (novas no projeto)

### jsonwebtoken (9.x) — Context7 `/keats/jsonwebtoken`

**Cargo.toml:**
```toml
jsonwebtoken = "9"
```

**Claims struct:**
```rust
#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub iss: String,         // "smartcore"
    pub sub: String,         // user_id como string
    pub iat: usize,          // issued at (Unix seconds)
    pub exp: usize,          // expiry (Unix seconds)
    pub email: String,
    pub tenant_id: Option<String>, // None para superuser
    pub role: String,
    pub scopes: Vec<String>,
    pub jti: String,         // UUID v4 para blocklist
    pub family_id: String,   // UUID v4 para revogação de família
}
```

**Encode:**
```rust
use jsonwebtoken::{encode, Header, EncodingKey, Algorithm};

let header = Header::new(Algorithm::HS256);
let key = EncodingKey::from_secret(jwt_secret.as_bytes());
let token = encode(&header, &claims, &key)?;
```

**Decode/Validate:**
```rust
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};

let mut validation = Validation::new(Algorithm::HS256);
validation.set_issuer(&["smartcore"]);
// validate_exp = true por padrão

let token_data = decode::<Claims>(&token, &key, &validation)?;
```

**Erros importantes:**
- `ErrorKind::ExpiredSignature` → retornar `UNAUTHENTICATED`
- `ErrorKind::InvalidSignature` → retornar `UNAUTHENTICATED`
- `ErrorKind::InvalidIssuer` → retornar `UNAUTHENTICATED`

**Carregamento do segredo com `OnceLock` (sem `once_cell` ou `lazy_static`):**
```rust
use std::sync::OnceLock;
use jsonwebtoken::{EncodingKey, DecodingKey};

static ENCODING_KEY: OnceLock<EncodingKey> = OnceLock::new();
static DECODING_KEY: OnceLock<DecodingKey> = OnceLock::new();

pub fn init_jwt_keys(secret: &str) {
    ENCODING_KEY.set(EncodingKey::from_secret(secret.as_bytes())).ok();
    DECODING_KEY.set(DecodingKey::from_secret(secret.as_bytes())).ok();
}
```

---

### sha2 (0.10.x) + base16ct (0.2.x) — Context7 `/rustcrypto/hashes`

**Cargo.toml:**
```toml
sha2 = "0.10"
base16ct = { version = "0.2", features = ["alloc"] }
```

**Hashing do refresh token para Redis (hex minúsculo):**
```rust
use sha2::{Sha256, Digest};
use base16ct::lower;

pub fn hash_refresh_token(token: &str) -> String {
    let hash = Sha256::digest(token.as_bytes());
    lower::encode_string(&hash) // 64 chars hex
}
```

**Alternativa sem base16ct (sem dependência extra):**
```rust
use sha2::{Sha256, Digest};

pub fn hash_refresh_token(token: &str) -> String {
    let hash = Sha256::digest(token.as_bytes());
    hash.iter().map(|b| format!("{:02x}", b)).collect()
}
```

---

### rand_core (0.6.x) — para geração segura de bytes do refresh token

**DECISÃO:** Em vez de adicionar `rand 0.10` (que mudou `OsRng` → `SysRng`), usar
**`rand_core = "0.6"`** diretamente — já é dependência transitiva de `argon2`.
Isso evita uma dependência extra e usa a API estável de `OsRng`.

**Cargo.toml:**
```toml
rand_core = "0.6"
```

**Geração de 32 bytes seguros:**
```rust
use rand_core::{OsRng, RngCore};

pub fn generate_refresh_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    URL_SAFE_NO_PAD.encode(bytes) // ~43 chars base64url sem padding
}
```

> **Nota sobre rand 0.10:** A versão 0.10 do crate `rand` removeu `OsRng` como tipo
> separado, substituindo por `SysRng` (com API `TryRng`). Para este projeto, prefira
> `rand_core 0.6` (que mantém `OsRng`) até o ecossistema RustCrypto consolidar a
> migração para rand 0.9+.

---

### tonic (0.14.6) + tonic-build (0.14.6) + prost (0.14) — Context7 `/hyperium/tonic`

**Cargo.toml (workspace):**
```toml
tonic = "0.14"
prost = "0.14"
tower = "0.4"
http = "1.0"

[build-dependencies]
tonic-build = "0.14"
```

**build.rs:**
```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile_protos(&["proto/auth.proto"], &["proto/"])?;
    Ok(())
}
```

**Interceptor JWT (padrão canônico):**
```rust
use tonic::{Request, Status};
use tonic::service::Interceptor;

#[derive(Clone)]
pub struct AuthInterceptor;

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        let token = request
            .metadata()
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| Status::unauthenticated("Token ausente"))?;

        let ctx = validate_jwt(token)
            .map_err(|_| Status::unauthenticated("Token inválido ou expirado"))?;

        request.extensions_mut().insert(ctx);
        Ok(request)
    }
}
```

**Recuperar contexto no handler:**
```rust
async fn login(
    &self,
    request: Request<LoginRequest>,
) -> Result<Response<AuthResponse>, Status> {
    let ctx = request.extensions().get::<RequestContext>()
        .ok_or_else(|| Status::internal("Contexto ausente"))?;
    // ...
}
```

**Status codes:**
- `Status::unauthenticated("msg")` — JWT ausente/inválido/expirado/blocklisted (gRPC 16)
- `Status::permission_denied("msg")` — Escopo insuficiente (gRPC 7)
- `Status::resource_exhausted("msg")` — Rate limit de login (gRPC 8)
- `Status::invalid_argument("msg")` — Campos inválidos (gRPC 3)

**Rotas públicas (sem interceptor):**
Register, Login, RefreshToken e AcceptInvite NÃO passam pelo `AuthInterceptor`
(são configurados antes do `interceptor()` no builder do servidor).

---

## Notas Gerais e Correções ao Plano Base

1. **`rand::rngs::OsRng` obsoleto no rand 0.10** — usar `rand_core 0.6` com `OsRng`
   ou `rand 0.10` com `SysRng` (API `TryRng`). Recomendação: `rand_core = "0.6"`.

2. **`base16ct`** é necessário se usar a API idiomática de `sha2` para hex. Alternativa:
   iteração manual sem dependência extra (`format!("{:02x}", b)`).

3. **`std::sync::OnceLock`** (Rust estável 1.70+) substitui `once_cell` e `lazy_static`
   para inicialização de chaves JWT — sem dependência extra.

4. **`family_id` nas claims JWT** — obrigatório para o fluxo de logout revogar a família
   de tokens sem necessitar que o Refresh Token seja válido.

5. **Bootstrap de permissão no cadastro** — `TenantUserRepository::criar` exige
   `RequestContext` com `tenant:admin`. Precisa de método `criar_owner` sem permissão
   para o fluxo de registro inicial.

6. **tonic 0.14.6 + prost 0.14** (não 0.12.x como mencionado no plano base).

7. **Proto location:** `server/crates/contracts/proto/auth.proto` — compilado pelo
   `build.rs` de cada binário que usa o contrato.
