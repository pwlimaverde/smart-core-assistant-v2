# Axum

- **Versão Recomendada:** 0.7.5
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Router e framework Web HTTP/WebSocket para o executável `runtime_api`.
- **Documentação Oficial:** [https://docs.rs/axum/latest/axum/](https://docs.rs/axum/latest/axum/)

---

## 1. Contexto e Uso no Projeto

O executável `runtime_api` utiliza o **Axum** para expor a API de comandos/consultas para as aplicações Flutter (desktop e web), além de fornecer conexões WebSockets persistentes para push de atualizações do painel em tempo real.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Injeção de Estado Compartilhado (State)
Nunca utilize variáveis estáticas mutáveis globais para guardar instâncias de banco de dados, conexão com Redis ou chaves. Utilize o mecanismo `State` do Axum para injetar dependências thread-safe nos handlers de forma segura.

```rust
use axum::{routing::get, Extension, Router, extract::State};
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

async fn list_tickets(
    State(state): State<AppState>,
) -> Result<axum::Json<Vec<TicketDto>>, AppError> {
    let tickets = fetch_tickets_from_db(&state.db_pool).await?;
    Ok(axum::Json(tickets))
}
```

### 2.2 Tratamento de Erros de API (IntoResponse)
Erros internos do sistema (ex: erro de banco SQL, falha de comunicação gRPC com o motor Python) **nunca** devem vazar para o cliente frontend por questões de segurança e clareza. 
Implemente o trait `IntoResponse` para o enum de erro central da camada de API, convertendo os erros internos em códigos HTTP correspondentes com payload JSON estruturado.

```rust
use axum::{
    response::{IntoResponse, Response},
    http::StatusCode,
    Json,
};
use serde_json::json;

pub enum ApiError {
    Unauthorized,
    NotFound(String),
    Internal(anyhow::Error),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "Acesso não autorizado.".to_string()),
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            ApiError::Internal(err) => {
                // Loga o erro real internamente para depuração
                log::error!("Erro interno na API: {:?}", err);
                // Retorna erro genérico e seguro para o cliente
                (StatusCode::INTERNAL_SERVER_ERROR, "Ocorreu um erro interno no servidor.".to_string())
            }
        };

        let body = Json(json!({
            "success": false,
            "error": error_message
        }));

        (status, body).into_response()
    }
}
```

### 2.3 WebSockets com Isolamento de Tenant
As conexões WebSocket de tempo real devem validar o `tenant_id` logo no handshake (via parâmetros ou cabeçalhos de auth) e rotear a sessão de forma a receber eventos específicos do canal do tenant no Redis (fan-out segregado).

```rust
use axum::extract::ws::{WebSocketUpgrade, WebSocket};

async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    // Extrai o tenant_id autenticado previamente por um middleware de auth
    Extension(tenant_id): Extension<Uuid>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state, tenant_id))
}

async fn handle_socket(mut socket: WebSocket, state: AppState, tenant_id: Uuid) {
    // Escuta eventos do Redis Stream sob a chave do tenant_id correspondente
    // e despacha no socket
}
```
