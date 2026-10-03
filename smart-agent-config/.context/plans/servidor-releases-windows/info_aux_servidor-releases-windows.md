# Documentação Auxiliar — Servidor de Releases Windows

> Gerado em: 2026-10-03  
> Plano canônico: `.context/plans/servidor-releases-windows.md`  
> Plano completo: `.context/plans/servidor-releases-windows/plano_completo_servidor-releases-windows.md`

---

## Libs Rust

### Axum (0.8.x)
**Fonte:** `doc_dev/libs/rust/axum.md` (Última Verificação: 2026-06-20)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Web framework HTTP para servidor de releases (GET /api/releases, POST /upload, GET /download/{version}/{filename})

**Principais recursos:**
- Router construction
- Handler functions com State
- Middleware integration (CORS, compression, logging)
- File serving (StaticFiles)
- Multipart form handling

**Sintaxe (v0.8):**
```rust
use axum::{Router, routing::{get, post}, extract::State};

let app = Router::new()
    .route("/api/releases", get(get_releases))
    .route("/upload", post(upload_release))
    .with_state(state);
```

**Breaking changes relevantes (0.7→0.8):**
- `Extension` removido → use `State`
- `axum::Server::bind` descontinuado → use `axum::serve` com `tokio::net::TcpListener`
- `.with_state()` obrigatório para handlers com `State`

---

### Tokio (1.38)
**Fonte:** `doc_dev/libs/rust/tokio.md` (Última Verificação: ??)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Async runtime para servidor HTTP (tasks, TcpListener, file I/O)

**Principais recursos:**
- `tokio::net::TcpListener`
- `tokio::spawn` para tasks assíncronas
- File I/O utilities (`tokio::fs`)

---

### Serde (1.0)
**Fonte:** `doc_dev/libs/rust/serde.md` (Última Verificação: ??)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Serialization/deserialization de JSON (releases.json, /api/releases response)

**Principais recursos:**
- `#[derive(Serialize, Deserialize)]`
- `serde_json::to_string`, `from_str`

---

### Tracing (0.1.40)
**Fonte:** `doc_dev/libs/rust/tracing.md` (Última Verificação: ??)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Structured logging para uploads, downloads, erros

**Principais recursos:**
- `#[tracing::instrument]` para funções
- `tracing::info!`, `tracing::warn!`, `tracing::error!`
- Correlation IDs via `trace_id`

**Observabilidade no servidor:**
```rust
#[tracing::instrument(skip(payload))]
async fn upload_release(
    State(state): State<AppState>,
    auth: BearerAuth,
    mut payload: Multipart,
) -> Result<Json<UploadResponse>, ApiError> {
    tracing::info!("Upload iniciado");
    // ...
    tracing::info!("Upload concluído para versão {version}");
}
```

---

### UUID (1.0)
**Fonte:** `doc_dev/libs/rust/uuid.md` (Última Verificação: ??)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Identificadores únicos para uploads (request IDs, version IDs)

---

### Tower-HTTP (0.5.x)
**Fonte:** `doc_dev/libs/rust/tower-http.md` (Criado 2026-10-03)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Middleware HTTP para Axum (file serving, CORS, compression, tracing)

**Principais recursos:**

#### ServeDir/ServeFile (File Serving)
```rust
use tower_http::services::{ServeDir, ServeFile};

let serve_dir = ServeDir::new("/opt/smartcore/releases");
let serve_file = ServeFile::new("/path/to/file.nupkg");

// Com precompressed variants (detecta .gz, .br, .zst automaticamente)
let serve = ServeDir::new("/releases")
    .with_buf_chunk_size(64 * 1024); // 64KB chunks
```

#### CorsLayer (CORS)
```rust
use tower_http::cors::CorsLayer;

let cors = CorsLayer::new()
    .allow_origin("https://app.smartcoreassistant.com.br".parse()?)
    .allow_methods(vec![Method::GET, Method::POST])
    .expose_headers(vec![CONTENT_LENGTH, CONTENT_TYPE]);
```

#### CompressionLayer (Gzip/Brotli)
```rust
use tower_http::compression::CompressionLayer;

let compression = CompressionLayer::new()
    .gzip(true)
    .br(true)
    .compress_when(|headers| {
        // Comprime .nupkg se cliente suporta
        headers.get("accept-encoding").is_some()
    });
```

#### TraceLayer (Logging)
```rust
use tower_http::trace::TraceLayer;

let trace = TraceLayer::new_for_http()
    .make_span_with(DefaultMakeSpan::new())
    .on_response(DefaultOnResponse::new());
```

**Compatibilidade:** Tower 0.4+, Axum 0.7.5 / 0.8.x

---

### Tokio-Util (0.7.12)
**Fonte:** `doc_dev/libs/rust/tokio-util.md` (Criado 2026-10-03)  
**Status:** ✅ ATUALIZADA

**Uso no plano:** Utilitários para streaming de arquivos .nupkg (AsyncReadExt, codecs)

**Principais recursos:**

#### AsyncReadExt/AsyncWriteExt (I/O Assíncrono)
```rust
use tokio::fs::File;
use tokio_util::io::AsyncReadExt;

let mut file = File::open("app-1.1.0-delta.nupkg").await?;
let mut buf = Vec::new();
file.read_to_end(&mut buf).await?; // Lê arquivo assincronamente
```

#### Framed (Streaming com Codec)
```rust
use tokio_util::codec::{Framed, LinesCodec};

let stream = socket.into_io();
let mut framed = Framed::new(stream, LinesCodec::new());

// Envia/recebe linhas automaticamente
framed.send("versão=1.1.0".into()).await?;
```

#### Compat Layer (Compatibilidade com futures)
```rust
use tokio_util::compat::TokioAsyncReadCompatExt;

let async_read = File::open("file.txt").await?;
let compat_read = async_read.compat(); // Converte para futures::io::AsyncRead
```

**Compatibilidade:** tokio-util 0.7.12 + Tokio 1.38+

---

## Serviços Externos

**Nenhum serviço externo obrigatório.** O servidor é autossuficiente:
- Hospedagem de arquivos: local (`/opt/smartcore/releases/`)
- Autenticação: Bearer token local (sem OAuth/terceiros)
- Notificação: cliente checa por polling (sem webhook externo)

---

## Observabilidade & Auditoria

### Logs Estruturados (Tracing)

**GET /api/releases:**
```rust
#[tracing::instrument(skip(state))]
async fn get_releases(
    Query(params): Query<ReleaseQuery>,
    State(state): State<AppState>,
) -> Json<ReleaseInfo> {
    tracing::debug!("Checando releases", channel = %params.channel, version = %params.version);
    // ...
    tracing::info!("Releases entregue", version = latest_version);
}
```
- Nível: `DEBUG` (check), `INFO` (sucesso)
- Campos: `channel`, `version`, `client_ip`
- **Sem token no log**

**POST /upload:**
```rust
#[tracing::instrument(skip(payload, auth))]
async fn upload_release(...) -> Result<Json<UploadResponse>, ApiError> {
    tracing::info!("Upload autorizado", token_length = auth.token().len());
    // ... (nunca log completo do token)
    tracing::info!("Arquivo salvo", version = version, size_bytes = size);
}
```
- Nível: `INFO` (sucesso), `WARN` (tamanho excepcional), `ERROR` (falha)
- Campos: `version`, `file_hash_sha256` (truncado), `size_bytes`
- **Sanitização:** Bearer token apenas conta caracteres, nunca impresso

**GET /download/{version}/{filename}:**
```rust
tracing::debug!("Download iniciado", version = version, filename = filename);
tracing::info!("Download concluído", version = version, bytes_sent = size);
```
- Nível: `DEBUG` (inicio), `INFO` (fim)
- Campos: `version`, `filename`, `bytes_sent`

### Auditoria no Banco

**Resultado:** Sem evento de auditoria.

Justificativa: O servidor de releases não acessa dados de tenant, não modifica state crítico (apenas adiciona versões em disco e JSON de metadados). Não há `TenantUser`, `Subscription`, ou `TenantConfig` envolvidos. Logs estruturados (tracing) e manutenção de hash SHA256 dos arquivos fornece auditoria de integridade.

Se necessário no futuro, criar tabela `releases_audit_log` com: timestamp UTC, upload_token_hash, version, file_hash_sha256, size_bytes, uploader_ip.

### Sanitização / Não-Vazamento

| Campo Sensível | Como Proteger |
|---|---|
| Bearer token (upload) | Usar `secrecy::SecretString`, contar length no log, nunca imprimir |
| File hash (SHA256) | Armazenar completo em `releases.json`, imprimir primeiros 8 chars no log |
| Client IP | Permitido em logs (não PII por lei), usar para rate limiting |
| Filename (cliente) | Permitido (é público) |

---

## Notas Gerais

- **Versionamento de API:** `/api/v1/releases` (para futuras mudanças)
- **Channels:** `stable` (padrão), `beta` (opcional no futuro)
- **Rate limiting:** 100 req/min por IP (via tower middleware)
- **CORS:** Permitir `https://app.smartcoreassistant.com.br` (cliente Windows)
- **Retenção de arquivos:** Manter últimas 10 versões, deletar versões muito antigas (cron job)
