# Axum

- **Versão Recomendada:** 0.7.5 (`runtime_api`) / 0.8.x (`webhook_ingress`)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-20
- **Propósito no Projeto:** Router e framework Web HTTP/WebSocket para `runtime_api` (v0.7.5) e `webhook_ingress` (v0.8).
- **Documentação Oficial:** [https://docs.rs/axum/latest/axum/](https://docs.rs/axum/latest/axum/)
- **Library ID (Context7):** `/tokio-rs/axum/axum_v0_8_4`

---

## 1. Contexto e Uso no Projeto

O projeto usa duas versões do Axum:
- **`runtime_api`**: usa `axum 0.7.5` — API de comandos/consultas para apps Flutter + WebSockets de realtime.
- **`webhook_ingress`**: usa `axum 0.8.x` — receptor HTTP de webhooks do WhatsApp (Evolution API).

As duas versões **não devem ser misturadas** dentro do mesmo binário.

---

## 2. Breaking Changes: 0.7.x → 0.8

### 🔴 `Extension` removido — use `State`
```rust
// ❌ 0.7 (não funciona em 0.8)
async fn handler(Extension(state): Extension<AppState>) {}

// ✅ 0.8
async fn handler(State(state): State<AppState>) {}
```

### 🔴 `axum::Server::bind` descontinuado — use `axum::serve`
```rust
// ❌ 0.7 (descontinuado)
axum::Server::bind(&"0.0.0.0:3000".parse().unwrap())
    .serve(app.into_make_service())
    .await?;

// ✅ 0.8
let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await?;
axum::serve(listener, app).await?;
```

### 🔴 `.with_state()` obrigatório
Em 0.8, todos os handlers com `State<T>` exigem `.with_state()` no router:
```rust
let app = Router::new()
    .route("/webhook/{provider}/{tenant_id}/{instance_id}", post(handle_webhook))
    .with_state(state);  // ← obrigatório
```

### ⚠️ Validação de rotas com `:` e `*`
0.8 rejeita por padrão rotas no estilo antigo (`:param`). Use `{param}` ou desabilite com `.without_v07_checks()`:
```rust
// ❌ 0.7 style (panics em 0.8)
.route("/:provider/:tenant_id", post(handler))

// ✅ 0.8 style
.route("/{provider}/{tenant_id}", post(handler))
```

---

## 3. Padrões de Implementação (0.8)

### 3.1 Path Extractor — Múltiplos Parâmetros
```rust
use axum::extract::Path;
use serde::Deserialize;

#[derive(Deserialize)]
struct WebhookPath {
    provider: String,
    tenant_id: uuid::Uuid,
    instance_id: i32,
}

async fn handle_webhook(
    Path(params): Path<WebhookPath>,
    State(state): State<AppState>,
    body: axum::body::Bytes,
) -> impl IntoResponse {
    // params.provider, params.tenant_id, params.instance_id
}

// Rota correspondente (0.8):
.route("/webhook/{provider}/{tenant_id}/{instance_id}", post(handle_webhook))
```

### 3.2 Estado Compartilhado
```rust
use axum::extract::State;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub redis: Arc<redis::Client>,
}

async fn handler(State(state): State<AppState>) -> impl IntoResponse {
    // usa state.redis
}

let app = Router::new()
    .route("/...", post(handler))
    .with_state(AppState { redis: Arc::new(client) });
```

### 3.3 Servidor (0.8)
```rust
let listener = tokio::net::TcpListener::bind("0.0.0.0:9200").await?;
axum::serve(listener, app).await?;
```

### 3.4 Tratamento de Erros (IntoResponse)
```rust
use axum::{response::{IntoResponse, Response}, http::StatusCode, Json};
use serde_json::json;

pub enum WebhookError {
    UnknownProvider(String),
    Internal(String),
}

impl IntoResponse for WebhookError {
    fn into_response(self) -> Response {
        let (status, msg) = match self {
            WebhookError::UnknownProvider(p) => (StatusCode::BAD_REQUEST, format!("Provedor desconhecido: {p}")),
            WebhookError::Internal(e) => (StatusCode::INTERNAL_SERVER_ERROR, e),
        };
        (status, Json(json!({ "error": msg }))).into_response()
    }
}
```

---

## 4. Padrões de Implementação (0.7.5 — `runtime_api`)

### 4.1 Injeção de Estado Compartilhado
```rust
use axum::{routing::get, Router, extract::State};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db_pool: sqlx::PgPool,
    pub redis_client: Arc<redis::Client>,
}

pub fn create_router(state: AppState) -> Router {
    Router::new()
        .route("/tickets", get(list_tickets))
        .with_state(state)
}
```

### 4.2 WebSockets com Isolamento de Tenant
```rust
use axum::extract::ws::{WebSocketUpgrade, WebSocket};

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Extension(tenant_id): Extension<Uuid>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state, tenant_id))
}
```

---

## Tabela Comparativa Rápida

| Recurso | 0.7.5 | 0.8.x |
|---------|-------|-------|
| Estado compartilhado | `Extension<T>` ou `State<T>` | `State<T>` (Extension removido) |
| Parâmetro de path | `:param` ou `{param}` | `{param}` (`:param` dá panic) |
| Iniciar servidor | `axum::Server::bind().serve()` | `axum::serve(listener, app)` |
| Json extractor | `Json<T>` | `Json<T>` ✅ igual |
| Bytes extractor | `Bytes` | `Bytes` ✅ igual |
| IntoResponse com tupla | ✅ | ✅ igual |
