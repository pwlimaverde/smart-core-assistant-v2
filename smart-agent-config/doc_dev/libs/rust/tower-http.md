# Tower-HTTP

- **Versão Recomendada:** 0.6.x (fixa no workspace)
- **Tower (dependência):** 0.5.x (fixa no workspace)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-10-03
- **Propósito no Projeto:** Middleware HTTP para servir arquivos estáticos, CORS, compressão e tracing/logging em serviços Tower/Axum.
- **Documentação Oficial:** [https://docs.rs/tower-http/latest/tower_http/](https://docs.rs/tower-http/latest/tower_http/)
- **Library ID (Context7):** `/websites/rs_tower-http`

**Nota:** Verificado contra `server/Cargo.toml`: `tower-http = 0.6`, `tower = 0.5`. Usar via `workspace = true` para manter sincronizado.

---

## 1. Visão Geral

`tower-http` fornece middlewares especializados para aplicações HTTP construídas com [Tower](https://docs.rs/tower/latest/tower/):

- **File Serving:** `ServeDir` (diretório) e `ServeFile` (arquivo único)
- **CORS:** `CorsLayer` para gerenciar política de cross-origin
- **Compression:** `CompressionLayer` para compressão de resposta com suporte a gzip, Brotli, Deflate, Zstd
- **Tracing:** `TraceLayer` para logging/observabilidade de ciclo de vida HTTP

Todos são compatíveis com **Axum** e outros frameworks que usam Tower.

---

## 2. File Serving (ServeDir/ServeFile)

### 2.1 ServeDir — Servir Diretório Completo

```rust
use tower_http::services::ServeDir;
use tower::ServiceBuilder;

// Criar middleware para servir conteúdo de um diretório
let serve_files = ServeDir::new("./public");

// Integrar com Axum
let app = Router::new()
    .nest_service("/", serve_files);
```

**Assinatura:**
```rust
pub fn new<P: AsRef<Path>>(path: P) -> Self
```

### 2.2 ServeFile — Servir Arquivo Único

```rust
use tower_http::services::ServeFile;

// Auto-detecta Content-Type pela extensão
let serve_single = ServeFile::new("./public/index.html");

// Ou especificar mime type explicitamente
use mime::TEXT_HTML_UTF_8;
let serve_with_mime = ServeFile::new_with_mime("./public/index.html", &TEXT_HTML_UTF_8);
```

**Assinaturas:**
```rust
pub fn new<P: AsRef<Path>>(path: P) -> Self
pub fn new_with_mime<P: AsRef<Path>>(path: P, mime: &Mime) -> Self
```

### 2.3 Precompressed Variants (Compressão Pré-Processada)

ServeFile busca automaticamente versões comprimidas do arquivo antes de enviar:

```rust
use tower_http::services::ServeFile;

let serve = ServeFile::new("./public/app.js")
    .precompressed_gzip()      // Busca ./public/app.js.gz
    .precompressed_br()        // Busca ./public/app.js.br (Brotli)
    .precompressed_deflate()   // Busca ./public/app.js.zz
    .precompressed_zstd();     // Busca ./public/app.js.zst
```

**Métodos Disponíveis:**
- `precompressed_gzip(self) -> Self`
- `precompressed_br(self) -> Self`
- `precompressed_deflate(self) -> Self`
- `precompressed_zstd(self) -> Self`

### 2.4 Configuração de Buffer

```rust
use tower_http::services::ServeFile;

let serve = ServeFile::new("./file.bin")
    .with_buf_chunk_size(32 * 1024);  // 32KB chunks (default: 64KB)
```

---

## 3. CORS (CorsLayer)

### 3.1 Configuração Básica

```rust
use tower_http::cors::{CorsLayer, Any};
use http::Method;
use tower::ServiceBuilder;
use axum::Router;

// Permitir GET/POST de qualquer origem
let cors = CorsLayer::new()
    .allow_methods([Method::GET, Method::POST])
    .allow_origin(Any);

let app = Router::new()
    .route("/api/data", get(handler))
    .layer(cors);
```

### 3.2 Presets Rápidos

```rust
use tower_http::cors::CorsLayer;

// Permissivo: permite tudo
let cors_permissive = CorsLayer::permissive();

// Muito permissivo: permite credentials, echo dinâmico de headers/origins/methods
let cors_very_permissive = CorsLayer::very_permissive();
```

### 3.3 Configuração Avançada

```rust
use tower_http::cors::CorsLayer;
use http::Method;

let cors = CorsLayer::new()
    .allow_methods([Method::GET, Method::POST, Method::PUT])
    .allow_origin(Any)
    .expose_headers(["X-Custom-Header".parse().unwrap()].into())
    .allow_private_network(true);
```

**Métodos de Configuração:**
- `allow_methods(methods)` — Métodos HTTP permitidos
- `allow_origin(origin)` — Origens permitidas (Any, lista, ou predicado)
- `expose_headers(headers)` — Headers expostos ao cliente
- `allow_private_network(bool)` — Access-Control-Allow-Private-Network

---

## 4. Compression (CompressionLayer)

### 4.1 Uso Básico

```rust
use tower_http::compression::CompressionLayer;
use tower::ServiceBuilder;

let compression = CompressionLayer::new();

let service = ServiceBuilder::new()
    .layer(compression)
    .service_fn(handle_request);
```

**CompressionLayer seleciona o encoding baseado no header `Accept-Encoding` do cliente.**

### 4.2 Ativar/Desativar Específicos Encodings

Cada encoding requer uma feature Cargo correspondente:

```rust
use tower_http::compression::CompressionLayer;

let compression = CompressionLayer::new()
    .gzip(true)      // Feature: compression-gzip
    .br(true)        // Feature: compression-br (Brotli)
    .deflate(true)   // Feature: compression-deflate
    .zstd(true);     // Feature: compression-zstd
```

**Métodos de Desabilitação:**
- `no_gzip(self) -> Self`
- `no_br(self) -> Self`
- `no_deflate(self) -> Self`
- `no_zstd(self) -> Self`

### 4.3 Qualidade de Compressão

```rust
use tower_http::compression::{CompressionLayer, CompressionLevel};

let compression = CompressionLayer::new()
    .quality(CompressionLevel::Precise(5));
```

### 4.4 Predicado Customizado

```rust
use tower_http::compression::CompressionLayer;
use http::Request;

let compression = CompressionLayer::new()
    .compress_when(|req: &Request<_>| {
        // Compressão condicional: ex., não compressá JSON pequeno
        req.uri().path().starts_with("/api/large")
    });
```

---

## 5. Tracing (TraceLayer)

### 5.1 Inicialização Rápida

```rust
use tower_http::trace::TraceLayer;
use tower::ServiceBuilder;

// Para HTTP
let trace = TraceLayer::new_for_http();

// Para gRPC
let trace = TraceLayer::new_for_grpc();

let service = ServiceBuilder::new()
    .layer(trace)
    .service_fn(handler);
```

### 5.2 Customização de Span

```rust
use tower_http::trace::TraceLayer;
use http::Request;
use tracing::Span;

let trace = TraceLayer::new_for_http()
    .make_span_with(|request: &Request<_>| {
        tracing::debug_span!("http-request", method = ?request.method(), uri = ?request.uri())
    });
```

### 5.3 Callbacks (Hooks)

```rust
use tower_http::trace::TraceLayer;
use http::Response;
use std::time::Duration;
use tracing::Span;
use bytes::Bytes;

let trace = TraceLayer::new_for_http()
    .on_request(|request: &Request<_>, _span: &Span| {
        tracing::debug!(">>> {} {}", request.method(), request.uri().path());
    })
    .on_response(|response: &Response<_>, latency: Duration, _span: &Span| {
        tracing::debug!("<<< {} in {:?}", response.status(), latency);
    })
    .on_body_chunk(|chunk: &Bytes, latency: Duration, _span: &Span| {
        tracing::trace!("chunk {} bytes, latency: {:?}", chunk.len(), latency);
    })
    .on_eos(
        |_trailers: Option<&HeaderMap>, latency: Duration, _span: &Span| {
            tracing::debug!("EOS after {:?}", latency);
        }
    )
    .on_failure(
        |failure: ServerErrorsFailureClass, latency: Duration, _span: &Span| {
            tracing::warn!("error: {:?} after {:?}", failure, latency);
        }
    );
```

**Métodos Disponíveis:**
- `make_span_with<F>(f: F)` — Customizar criação de span
- `on_request<F>(f: F)` — Callback ao receber request
- `on_response<F>(f: F)` — Callback ao enviar response
- `on_body_chunk<F>(f: F)` — Callback ao processar chunk
- `on_eos<F>(f: F)` — Callback ao fim do stream
- `on_failure<F>(f: F)` — Callback em erro

---

## 6. Exemplo Integrado (Axum + tower-http)

```rust
use axum::{Router, routing::get};
use tower_http::cors::CorsLayer;
use tower_http::compression::CompressionLayer;
use tower_http::trace::TraceLayer;
use tower_http::services::ServeDir;
use tower::ServiceBuilder;
use http::Method;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Inicializar tracing
    tracing_subscriber::fmt::init();

    // Middlewares
    let cors = CorsLayer::new()
        .allow_methods([Method::GET, Method::POST])
        .allow_origin(tower_http::cors::Any);

    let compression = CompressionLayer::new();
    let trace = TraceLayer::new_for_http();

    // Rotas
    let app = Router::new()
        .route("/api/data", get(|| async { "Hello" }))
        .nest_service("/static", ServeDir::new("./public"))
        .layer(ServiceBuilder::new()
            .layer(trace)
            .layer(compression)
            .layer(cors));

    // Servidor
    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await?;
    axum::serve(listener, app).await?;

    Ok(())
}
```

---

## 7. Dependências Cargo

```toml
[dependencies]
tower-http = { version = "0.5", features = [
    "trace",
    "cors",
    "compression-gzip",
    "compression-br",
    "fs",
] }
tower = "0.4"
axum = "0.8"  # ou 0.7.5
tokio = { version = "1", features = ["full"] }
tracing = "0.1"
tracing-subscriber = "0.3"
```

---

## 8. API Deprecadas / Breaking Changes

**Nenhuma API deprecada ou breaking change encontrada** na versão 0.5.x.

A biblioteca mantém compatibilidade com Tower e Axum seguindo as versões mais recentes de ambas.

---

## Referências Rápidas

| Componente | Feature Cargo | Propósito |
|---|---|---|
| `ServeDir` / `ServeFile` | `fs` | Servir arquivos estáticos |
| `CorsLayer` | `cors` | Middleware CORS |
| `CompressionLayer` | `compression-gzip`, `compression-br`, etc. | Compressão de resposta |
| `TraceLayer` | `trace` | Tracing/logging de ciclo de vida HTTP |

---

**Última atualização:** 2026-10-03  
**Verificado contra:** Context7 `/websites/rs_tower-http` (score 87.89, High reputation, 3987 code snippets)
