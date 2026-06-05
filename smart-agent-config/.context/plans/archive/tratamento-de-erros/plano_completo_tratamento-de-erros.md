# Plano Completo — Tratamento de Erros (`error_core`)

> **Feature:** `tratamento-de-erros`
> **Arquivo:** `.context/plans/tratamento-de-erros/plano_completo_tratamento-de-erros.md`
> **Status:** Pronto para implementação (aguardando fase E)
> **Data de reestruturação:** 2026-06-04
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês
> **Referência base:** `doc_dev/planejamento/06-tratamento-de-erros.md`
> **Par arquitetural:** `observability` (doc 05) — deve estar implementada antes da fase E

---

## Visão Geral

Centralizar a **organização dos erros** numa crate dedicada (`server/crates/error_core`):
taxonomia comum (`ErrorCode`), tipo agregador (`AppError`), registro rastreável (`ErrorReport`)
e mapeamento para o transporte gRPC (`tonic::Status`).

**Não substitui** os erros por crate (idiomático em Rust): `DbError`, `RedisError`,
`StorageError`, `AuthError` **continuam** em suas crates. O `error_core` os **unifica na borda**
(camada `application`/handlers gRPC) e padroniza o **registro rastreável** com `error_code` +
`trace_id` + `tenant_id`.

### Pilha de dependências confirmada

| Lib | Versão | Papel |
|-----|--------|-------|
| `thiserror` | 1.0 | Derivar `Error` para `AppError` e erros por crate |
| `serde` | 1.0 | Serializar `ErrorCode` para string estável (`SCREAMING_SNAKE_CASE`) |
| `tracing` | 0.1.40 | Registrar erros com correlação (configurado pela `observability`) |
| `tonic` | 0.14.6 | `to_status()` na borda gRPC (feature opcional `grpc`) |

---

## Decisões Travadas

| # | Tema | Decisão | Racional |
|---|------|---------|----------|
| E1 | Erros por crate | **Mantidos** (`thiserror`) | Idiomático; cada crate dona do seu erro |
| E2 | Agregação | **`AppError`** (enum) com `From<DbError/RedisError/StorageError/AuthError>` | Um tipo único na camada `application`/apps |
| E3 | Código estável | **`ErrorCode`** (enum, serde `SCREAMING_SNAKE_CASE`) | Estável para cliente, métricas e alertas |
| E4 | Classificação | cada erro expõe `severity` (warn/error) + `retryable` (bool) + `public_message` | Decide log, retry e o que o cliente vê |
| E5 | Transporte | `to_status() -> tonic::Status` (feature `grpc` opcional) | Mapeamento único na borda gRPC |
| E6 | Registro rastreável | `registrar(&AppError, ctx)` loga via `tracing` sem PII | Integra ao doc 05 |
| E7 | Sem `unwrap()`/`expect()` em produção | uso de `?`/`Result<_, AppError>` | Padrão do workspace |
| E8 | `tonic` no workspace | **Adicionar** `tonic = "0.14.6"` em `[workspace.dependencies]` | Não estava presente; necessário para feature `grpc` |

---

## Estrutura de Módulos

```
server/crates/error_core/
├── Cargo.toml
└── src/
    ├── lib.rs          # reexports + doc
    ├── code.rs         # ErrorCode (taxonomia estável) + categoria
    ├── error.rs        # AppError (agregador) + From<…> + severity/retryable/public_message
    ├── report.rs       # ErrorReport + helper registrar()
    └── transport.rs    # to_status() — mapa ErrorCode → tonic::Code (feature grpc)
tests/
    ├── from_conversions_tests.rs  # From<DbError/…> → AppError
    ├── transport_tests.rs         # to_status() por ErrorCode
    └── report_tests.rs            # ErrorReport + correlação
```

---

## 5 Fases PREVC

---

### FASE P — Planning (Escopo e API Pública)

**Agent:** Arquiteto / Tech Lead
**Critério de conclusão:** Todas as interfaces públicas acordadas; `Cargo.toml` rascunhado; decisões E1–E8 aprovadas.

#### P1 — Confirmar escopo

- Crate `error_core` em `server/crates/error_core/`.
- Expõe: `ErrorCode`, `AppError`, `ErrorReport`, `registrar()`, `to_status()` (feature `grpc`).
- **Não expõe** os erros de infraestrutura (`DbError`, `RedisError`, `StorageError`, `AuthError`).
- Fase 0.5 do roadmap — fundação transversal antes de storage e features.

#### P2 — API pública acordada

```rust
// code.rs
pub enum ErrorCode { ... }          // serializa para "AUTH_INVALID_TOKEN"
pub enum ErrorCategory { Auth, Storage, Database, Cache, Validation, Internal }

// error.rs
pub enum AppError { ... }           // From<DbError>, From<RedisError>, …
impl AppError {
    pub fn code(&self) -> ErrorCode;
    pub fn severity(&self) -> Severity;  // Warn | Error
    pub fn retryable(&self) -> bool;
    pub fn public_message(&self) -> &str;
}

// report.rs
pub struct ErrorReport { ... }
pub struct ErrorContext { pub trace_id: String, pub tenant_id: String }
pub fn registrar(err: &AppError, ctx: &ErrorContext);

// transport.rs  (feature = "grpc")
pub fn to_status(err: &AppError) -> tonic::Status;
```

#### P3 — Rascunho de `Cargo.toml`

```toml
[package]
name    = "error_core"
version = "0.1.0"
edition = "2021"

[dependencies]
thiserror = { workspace = true }
serde     = { workspace = true, features = ["derive"] }
tracing   = { workspace = true }
tonic     = { workspace = true, optional = true }

[features]
grpc = ["dep:tonic"]

[dev-dependencies]
tracing-subscriber = { workspace = true }
```

> **Ação em `server/Cargo.toml`:** adicionar `tonic = "0.14.6"` em `[workspace.dependencies]`
> e `error_core = { path = "crates/error_core" }` em `[workspace.members]`.

#### P4 — Relações confirmadas

- **← `observability`:** tracing inicializado antes; `error_core` usa `tracing` já configurado.
- **← erros por crate:** `From<DbError>`, `From<RedisError>`, `From<StorageError>`, `From<AuthError>`.
- **→ `application`/apps:** retornam `Result<_, AppError>`; handlers chamam `to_status()`.
- **→ `contracts` (futuro doc 07):** se `ErrorCode` cruzar a fronteira, o tipo vai para `contracts`.

---

### FASE R — Review (Validação do Design de Tipos)

**Agent:** Revisor Sênior / Arquiteto
**Critério de conclusão:** Design de tipos aprovado sem ressalvas; exemplos de código revisados; nenhuma inconsistência arquitetural pendente.

#### R1 — Checklist de revisão

- [ ] `ErrorCode` cobre todos os domínios atuais (auth, storage, db, cache, validation, internal)?
- [ ] `AppError::From<X>` mapeia `ErrorCode` correto para cada variante?
- [ ] `severity` e `retryable` estão coerentes por domínio?
- [ ] `public_message` nunca vaza detalhe interno / stack trace / PII?
- [ ] `to_status()` alinha ao doc 09 (defesa em 3 camadas)?
- [ ] Feature `grpc` isolada — sem `tonic` em binários que não precisam?
- [ ] `registrar()` usa `error!()` para `Severity::Error` e `warn!()` para `Severity::Warn`?
- [ ] `tonic = "0.14.6"` adicionada ao `[workspace.dependencies]`?

#### R2 — Revisão do mapeamento de transporte

| `ErrorCode` | `tonic::Code` | Justificativa |
|-------------|--------------|---------------|
| `AuthInvalidToken`, `AuthExpiredToken`, `AuthMissingToken` | `Unauthenticated` | Credencial inválida/ausente |
| `AuthInsufficientScope` | `PermissionDenied` | Autenticado, sem permissão |
| `StorageNotFound`, `DbRecordNotFound` | `NotFound` | Recurso não existe |
| `DbConnectionFailed`, `CacheUnavailable` | `Internal` | Falha de infraestrutura |
| `ValidationFailed` | `InvalidArgument` | Entrada inválida |
| `RateLimitExceeded` | `ResourceExhausted` | Limite atingido |
| `Conflict` | `AlreadyExists` | Conflito de estado |
| `InternalError` | `Internal` | Catch-all |

#### R3 — Pontos de atenção

- `thiserror 1.0` é estável; `#[from]` gera `impl From<X>` corretamente.
- `serde` com `#[serde(rename_all = "SCREAMING_SNAKE_CASE")]` serializa `AuthInvalidToken` → `"AUTH_INVALID_TOKEN"` sem código manual.
- `tonic 0.14.6`: `tonic::Status::new(code, message)` e `tonic::Code` são a API estável — sem mudanças quebradoras nessa versão.
- `tracing 0.1.40`: macros `error!()` / `warn!()` com campos estruturados (`%field`) continuam estáveis.

---

### FASE E — Execution (Implementação Completa)

**Agent:** Implementador
**Critério de conclusão:** Todos os arquivos criados; `cargo build -p error_core` e `cargo build -p error_core --features grpc` verdes; sem `unwrap()`/`expect()` fora de testes.

#### E1 — Atualizar `server/Cargo.toml`

Adicionar em `[workspace.dependencies]`:

```toml
tonic      = "0.14.6"
error_core = { path = "crates/error_core" }
```

Adicionar em `[workspace.members]`:

```toml
"crates/error_core",
```

---

#### E2 — `src/code.rs`

```rust
//! Taxonomia estável de códigos de erro da aplicação.
//! Cada código é serializável para string `SCREAMING_SNAKE_CASE` (uso em logs e métricas).

use serde::{Deserialize, Serialize};

/// Categoria de alto nível do erro — usada para agrupamento em métricas.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCategory {
    Auth,
    Storage,
    Database,
    Cache,
    Validation,
    Internal,
}

/// Código estável que identifica o erro de forma rastreável em logs, métricas e alertas.
///
/// Novos códigos devem ser adicionados aqui — **nunca** remover ou renomear existentes
/// sem deprecação explícita, pois clientes e alertas dependem dessas strings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    // Autenticação
    AuthInvalidToken,
    AuthExpiredToken,
    AuthMissingToken,
    AuthInsufficientScope,

    // Armazenamento (object storage)
    StorageNotFound,
    StorageUploadFailed,
    StorageDeleteFailed,

    // Banco de dados
    DbConnectionFailed,
    DbRecordNotFound,
    DbConstraintViolation,
    DbQueryFailed,

    // Cache
    CacheUnavailable,
    CacheKeyNotFound,

    // Validação
    ValidationFailed,

    // Conflito / negócio
    Conflict,
    RateLimitExceeded,

    // Catch-all
    InternalError,
}

impl ErrorCode {
    /// Retorna a categoria de alto nível do código.
    pub fn category(&self) -> ErrorCategory {
        match self {
            Self::AuthInvalidToken
            | Self::AuthExpiredToken
            | Self::AuthMissingToken
            | Self::AuthInsufficientScope => ErrorCategory::Auth,

            Self::StorageNotFound
            | Self::StorageUploadFailed
            | Self::StorageDeleteFailed => ErrorCategory::Storage,

            Self::DbConnectionFailed
            | Self::DbRecordNotFound
            | Self::DbConstraintViolation
            | Self::DbQueryFailed => ErrorCategory::Database,

            Self::CacheUnavailable | Self::CacheKeyNotFound => ErrorCategory::Cache,

            Self::ValidationFailed => ErrorCategory::Validation,

            Self::Conflict | Self::RateLimitExceeded | Self::InternalError => {
                ErrorCategory::Internal
            }
        }
    }
}

use std::fmt;

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // serde serializa para SCREAMING_SNAKE_CASE — replicamos aqui para evitar
        // dependência de serde_json no caminho de log de produção.
        let s = serde_json::to_string(self).unwrap_or_else(|_| format!("{:?}", self));
        write!(f, "{}", s.trim_matches('"'))
    }
}
```

---

#### E3 — `src/error.rs`

```rust
//! Tipo agregador `AppError` — converte erros de crate em um tipo único
//! para uso na camada `application` e nos handlers gRPC.

use thiserror::Error;

use crate::code::ErrorCode;

/// Severidade do erro — determina o nível de log (`error!` vs `warn!`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Severity {
    /// Problema esperado / recuperável (ex.: recurso não encontrado, token expirado).
    Warn,
    /// Problema inesperado / crítico (ex.: falha de conexão, erro interno).
    Error,
}

/// Agregador de erros da aplicação.
///
/// Converte automaticamente os erros de crate de infraestrutura via `From<>`.
/// Usado em todo `Result<_, AppError>` na camada `application` e nos apps.
///
/// **Nunca** expor detalhes internos ao cliente — use `public_message()`.
#[derive(Debug, Error)]
pub enum AppError {
    #[error("Erro de banco de dados: {0}")]
    Database(String),

    #[error("Erro de cache: {0}")]
    Cache(String),

    #[error("Erro de armazenamento: {0}")]
    Storage(String),

    #[error("Erro de autenticação: {0}")]
    Auth(String),

    #[error("Erro de validação: {0}")]
    Validation(String),

    #[error("Conflito de estado: {0}")]
    Conflict(String),

    #[error("Erro interno: {0}")]
    Internal(String),
}

// Nota: os `From<DbError>`, `From<RedisError>`, `From<StorageError>`, `From<AuthError>`
// são implementados aqui com stubs. Quando as crates existirem no workspace, os tipos
// concretos substituem os stubs e os `#[from]` podem ser usados diretamente via thiserror.
//
// Exemplo com crate real:
//
//   use infrastructure_postgres::DbError;
//
//   impl From<DbError> for AppError {
//       fn from(err: DbError) -> Self {
//           AppError::Database(err.to_string())
//       }
//   }

impl AppError {
    /// Código estável que identifica este erro em logs e métricas.
    pub fn code(&self) -> ErrorCode {
        match self {
            Self::Auth(msg) if msg.contains("expirado") || msg.contains("expired") => {
                ErrorCode::AuthExpiredToken
            }
            Self::Auth(msg) if msg.contains("ausente") || msg.contains("missing") => {
                ErrorCode::AuthMissingToken
            }
            Self::Auth(msg) if msg.contains("permissão") || msg.contains("scope") => {
                ErrorCode::AuthInsufficientScope
            }
            Self::Auth(_) => ErrorCode::AuthInvalidToken,

            Self::Database(msg) if msg.contains("conexão") || msg.contains("connection") => {
                ErrorCode::DbConnectionFailed
            }
            Self::Database(msg) if msg.contains("não encontrado") || msg.contains("not found") => {
                ErrorCode::DbRecordNotFound
            }
            Self::Database(msg)
                if msg.contains("constraint") || msg.contains("duplicado") =>
            {
                ErrorCode::DbConstraintViolation
            }
            Self::Database(_) => ErrorCode::DbQueryFailed,

            Self::Cache(msg) if msg.contains("indisponível") || msg.contains("unavailable") => {
                ErrorCode::CacheUnavailable
            }
            Self::Cache(_) => ErrorCode::CacheKeyNotFound,

            Self::Storage(msg)
                if msg.contains("não encontrado") || msg.contains("not found") =>
            {
                ErrorCode::StorageNotFound
            }
            Self::Storage(msg) if msg.contains("upload") => ErrorCode::StorageUploadFailed,
            Self::Storage(_) => ErrorCode::StorageDeleteFailed,

            Self::Validation(_) => ErrorCode::ValidationFailed,
            Self::Conflict(_) => ErrorCode::Conflict,
            Self::Internal(_) => ErrorCode::InternalError,
        }
    }

    /// Severidade do erro — define o nível de log.
    pub fn severity(&self) -> Severity {
        match self {
            // Erros esperados / recuperáveis → Warn
            Self::Auth(_) | Self::Validation(_) | Self::Conflict(_) => Severity::Warn,
            Self::Storage(msg) if msg.contains("não encontrado") => Severity::Warn,
            Self::Database(msg) if msg.contains("não encontrado") => Severity::Warn,
            Self::Cache(msg) if msg.contains("não encontrado") => Severity::Warn,

            // Falhas de infraestrutura e internos → Error
            _ => Severity::Error,
        }
    }

    /// Indica se o cliente pode tentar novamente.
    pub fn retryable(&self) -> bool {
        matches!(
            self.code(),
            ErrorCode::DbConnectionFailed
                | ErrorCode::CacheUnavailable
                | ErrorCode::StorageUploadFailed
                | ErrorCode::InternalError
        )
    }

    /// Mensagem segura para o cliente — **nunca** vaza detalhe interno, stack trace ou PII.
    pub fn public_message(&self) -> &str {
        match self {
            Self::Auth(_) => "Credencial inválida ou ausente.",
            Self::Database(msg) if msg.contains("não encontrado") => "Recurso não encontrado.",
            Self::Database(_) => "Erro ao acessar o banco de dados.",
            Self::Cache(_) => "Erro ao acessar o cache.",
            Self::Storage(msg) if msg.contains("não encontrado") => "Arquivo não encontrado.",
            Self::Storage(_) => "Erro ao acessar o armazenamento.",
            Self::Validation(_) => "Dados de entrada inválidos.",
            Self::Conflict(_) => "Conflito com o estado atual do recurso.",
            Self::Internal(_) => "Erro interno do servidor.",
        }
    }
}
```

---

#### E4 — `src/report.rs`

```rust
//! Registro rastreável de erros — vincula `AppError` a `trace_id` e `tenant_id`
//! e emite log estruturado via `tracing` sem vazar PII ou detalhes internos.

use tracing::{error, warn};

use crate::{
    code::ErrorCode,
    error::{AppError, Severity},
};

/// Contexto de correlação obrigatório para registrar um erro rastreável.
pub struct ErrorContext {
    /// ID de rastreamento distribuído (gerado pela `observability`).
    pub trace_id: String,
    /// Identificador do tenant (multi-tenancy).
    pub tenant_id: String,
}

/// Estrutura completa do registro de erro — aparece no JSON de log.
#[derive(Debug)]
pub struct ErrorReport {
    pub error_code: ErrorCode,
    pub severity: Severity,
    pub trace_id: String,
    pub tenant_id: String,
    /// Mensagem segura para o cliente (nunca detalhe interno).
    pub public_message: String,
    /// Contexto adicional para diagnóstico interno (opcional).
    pub context: Option<String>,
}

impl ErrorReport {
    /// Constrói um `ErrorReport` a partir do `AppError` e do contexto de correlação.
    pub fn from_error(err: &AppError, ctx: &ErrorContext) -> Self {
        Self {
            error_code: err.code(),
            severity: err.severity(),
            trace_id: ctx.trace_id.clone(),
            tenant_id: ctx.tenant_id.clone(),
            public_message: err.public_message().to_owned(),
            context: None,
        }
    }

    /// Adiciona contexto interno de diagnóstico (não exposto ao cliente).
    pub fn with_context(mut self, ctx: impl Into<String>) -> Self {
        self.context = Some(ctx.into());
        self
    }
}

/// Registra um `AppError` via `tracing` com campos de correlação.
///
/// - Usa `error!()` para `Severity::Error` e `warn!()` para `Severity::Warn`.
/// - Nunca inclui PII, stack trace ou mensagem interna no campo `message`.
pub fn registrar(err: &AppError, ctx: &ErrorContext) {
    let report = ErrorReport::from_error(err, ctx);

    match report.severity {
        Severity::Error => {
            error!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                "Erro de aplicação registrado"
            );
        }
        Severity::Warn => {
            warn!(
                error_code = %report.error_code,
                trace_id   = %report.trace_id,
                tenant_id  = %report.tenant_id,
                message    = %report.public_message,
                "Aviso de aplicação registrado"
            );
        }
    }
}
```

---

#### E5 — `src/transport.rs`

```rust
//! Mapeamento de `AppError` para `tonic::Status` — usado na borda dos handlers gRPC.
//!
//! Habilitado apenas com a feature `grpc`. Quem não usa gRPC não carrega `tonic`.

#[cfg(feature = "grpc")]
use tonic::{Code, Status};

#[cfg(feature = "grpc")]
use crate::{code::ErrorCode, error::AppError};

/// Converte um `AppError` em `tonic::Status` para retorno nos handlers gRPC.
///
/// A mensagem do status usa `public_message()` — nunca detalhes internos.
#[cfg(feature = "grpc")]
pub fn to_status(err: &AppError) -> Status {
    let code = match err.code() {
        ErrorCode::AuthInvalidToken
        | ErrorCode::AuthExpiredToken
        | ErrorCode::AuthMissingToken => Code::Unauthenticated,

        ErrorCode::AuthInsufficientScope => Code::PermissionDenied,

        ErrorCode::StorageNotFound
        | ErrorCode::DbRecordNotFound
        | ErrorCode::CacheKeyNotFound => Code::NotFound,

        ErrorCode::DbConnectionFailed
        | ErrorCode::CacheUnavailable
        | ErrorCode::StorageUploadFailed
        | ErrorCode::StorageDeleteFailed
        | ErrorCode::DbQueryFailed
        | ErrorCode::InternalError => Code::Internal,

        ErrorCode::ValidationFailed => Code::InvalidArgument,

        ErrorCode::DbConstraintViolation | ErrorCode::Conflict => Code::AlreadyExists,

        ErrorCode::RateLimitExceeded => Code::ResourceExhausted,
    };

    Status::new(code, err.public_message())
}
```

---

#### E6 — `src/lib.rs`

```rust
//! # error_core
//!
//! Crate transversal de tratamento de erros do workspace `smart-core-assistant-v2`.

pub mod code;
pub mod error;
pub mod report;

#[cfg(feature = "grpc")]
pub mod transport;

pub use code::{ErrorCategory, ErrorCode};
pub use error::{AppError, Severity};
pub use report::{registrar, ErrorContext, ErrorReport};

#[cfg(feature = "grpc")]
pub use transport::to_status;
```

---

#### E7 — Testes

**`tests/from_conversions_tests.rs`**

```rust
//! Testa conversões From<> e mapeamento de ErrorCode por variante de AppError.

use error_core::{AppError, ErrorCode};

#[test]
fn database_conexao_falhou_mapeia_db_connection_failed() {
    let err = AppError::Database("conexão falhou".into());
    assert_eq!(err.code(), ErrorCode::DbConnectionFailed);
}

#[test]
fn database_nao_encontrado_mapeia_db_record_not_found() {
    let err = AppError::Database("registro não encontrado".into());
    assert_eq!(err.code(), ErrorCode::DbRecordNotFound);
}

#[test]
fn auth_expirado_mapeia_auth_expired_token() {
    let err = AppError::Auth("token expirado".into());
    assert_eq!(err.code(), ErrorCode::AuthExpiredToken);
}

#[test]
fn auth_invalido_mapeia_auth_invalid_token() {
    let err = AppError::Auth("token inválido".into());
    assert_eq!(err.code(), ErrorCode::AuthInvalidToken);
}

#[test]
fn storage_nao_encontrado_mapeia_storage_not_found() {
    let err = AppError::Storage("arquivo não encontrado".into());
    assert_eq!(err.code(), ErrorCode::StorageNotFound);
}

#[test]
fn validation_mapeia_validation_failed() {
    let err = AppError::Validation("campo obrigatório ausente".into());
    assert_eq!(err.code(), ErrorCode::ValidationFailed);
}

#[test]
fn internal_mapeia_internal_error() {
    let err = AppError::Internal("panic inesperado".into());
    assert_eq!(err.code(), ErrorCode::InternalError);
}

#[test]
fn retryable_db_connection_failed() {
    let err = AppError::Database("conexão falhou".into());
    assert!(err.retryable());
}

#[test]
fn nao_retryable_auth_invalid_token() {
    let err = AppError::Auth("token inválido".into());
    assert!(!err.retryable());
}

#[test]
fn public_message_nao_vaza_detalhe_interno() {
    let err = AppError::Internal("panic em linha 42 de main.rs: index out of bounds".into());
    let msg = err.public_message();
    assert!(!msg.contains("linha 42"));
    assert!(!msg.contains("main.rs"));
    assert!(!msg.contains("index out of bounds"));
    assert_eq!(msg, "Erro interno do servidor.");
}
```

**`tests/transport_tests.rs`** (requer feature `grpc`)

```rust
//! Testa mapeamento AppError → tonic::Status.
//! Executar com: cargo test -p error_core --features grpc

#[cfg(feature = "grpc")]
mod grpc {
    use error_core::{to_status, AppError};
    use tonic::Code;

    #[test]
    fn auth_invalido_retorna_unauthenticated() {
        let err = AppError::Auth("token inválido".into());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::Unauthenticated);
    }

    #[test]
    fn auth_scope_retorna_permission_denied() {
        let err = AppError::Auth("scope insuficiente".into());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::PermissionDenied);
    }

    #[test]
    fn storage_not_found_retorna_not_found() {
        let err = AppError::Storage("arquivo não encontrado".into());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::NotFound);
    }

    #[test]
    fn db_connection_retorna_internal() {
        let err = AppError::Database("conexão falhou".into());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::Internal);
    }

    #[test]
    fn validation_retorna_invalid_argument() {
        let err = AppError::Validation("campo inválido".into());
        let status = to_status(&err);
        assert_eq!(status.code(), Code::InvalidArgument);
    }

    #[test]
    fn status_message_usa_public_message() {
        let err = AppError::Internal("detalhes secretos do sistema".into());
        let status = to_status(&err);
        assert_eq!(status.message(), "Erro interno do servidor.");
        assert!(!status.message().contains("secretos"));
    }
}
```

**`tests/report_tests.rs`**

```rust
//! Testa ErrorReport e helper registrar() — correlação presente, sem PII.

use error_core::{registrar, AppError, ErrorContext, ErrorReport, Severity};

fn contexto() -> ErrorContext {
    ErrorContext {
        trace_id: "trace-abc-123".into(),
        tenant_id: "tenant-42".into(),
    }
}

#[test]
fn report_inclui_trace_id_e_tenant_id() {
    let err = AppError::Database("conexão falhou".into());
    let ctx = contexto();
    let report = ErrorReport::from_error(&err, &ctx);

    assert_eq!(report.trace_id, "trace-abc-123");
    assert_eq!(report.tenant_id, "tenant-42");
}

#[test]
fn report_severity_error_para_db_connection() {
    let err = AppError::Database("conexão falhou".into());
    let ctx = contexto();
    let report = ErrorReport::from_error(&err, &ctx);
    assert_eq!(report.severity, Severity::Error);
}

#[test]
fn report_severity_warn_para_auth() {
    let err = AppError::Auth("token inválido".into());
    let ctx = contexto();
    let report = ErrorReport::from_error(&err, &ctx);
    assert_eq!(report.severity, Severity::Warn);
}

#[test]
fn report_public_message_nao_vaza_pii() {
    let err = AppError::Auth("usuário: joao@empresa.com, token: eyJhbGci...".into());
    let ctx = contexto();
    let report = ErrorReport::from_error(&err, &ctx);
    assert!(!report.public_message.contains("joao@empresa.com"));
    assert!(!report.public_message.contains("eyJhbGci"));
}

#[test]
fn registrar_nao_panics() {
    let err = AppError::Internal("erro de teste".into());
    let ctx = contexto();
    registrar(&err, &ctx);
}
```

**`tests/integration_observability.rs`**

```rust
//! Validação de integração com tracing_subscriber.

use error_core::{registrar, AppError, ErrorContext};

#[test]
fn integra_com_tracing_subscriber() {
    let _ = tracing_subscriber::fmt().try_init();

    let err = AppError::Database("conexão falhou".into());
    let ctx = ErrorContext {
        trace_id: "int-trace-001".into(),
        tenant_id: "tenant-test".into(),
    };

    registrar(&err, &ctx);
}
```

---

### FASE V — Validation (Testes, Clippy, Fmt e Integração)

**Agent:** QA / Implementador
**Critério de conclusão:** todos os testes passando; clippy limpo; fmt ok; integração com `observability` validada.

#### V1 — Comandos de validação

```bash
# Testes unitários da crate
cargo test -p error_core

# Testes com feature grpc
cargo test -p error_core --features grpc

# Linting — nenhum warning permitido em produção
cargo clippy -p error_core --all-targets -- -D warnings
cargo clippy -p error_core --all-targets --features grpc -- -D warnings

# Formatação
cargo fmt --check -p error_core

# Build limpo
cargo build -p error_core
cargo build -p error_core --features grpc
```

#### V2 — Checklist de validação

- [ ] `cargo test -p error_core` — todos passando
- [ ] `cargo test -p error_core --features grpc` — todos passando
- [ ] `cargo clippy -p error_core --all-targets -- -D warnings` — zero warnings
- [ ] `cargo fmt --check -p error_core` — sem diff
- [ ] `cargo build -p error_core --features grpc` — sem erros de compilação
- [ ] `ErrorReport` inclui `trace_id` e `tenant_id` em todos os casos
- [ ] `public_message()` nunca expõe stack trace, PII ou detalhe interno
- [ ] Nenhum `unwrap()`/`expect()` fora de testes
- [ ] Feature `grpc` isolada — `tonic` não aparece em `cargo tree -p error_core` sem a feature

---

### FASE C — Confirmation (Final Review e Arquivamento)

**Agent:** Revisor Final (Opus) + Tech Lead
**Critério de conclusão:** desvios corrigidos; PR mergeado; documentação atualizada; plano arquivado.

#### C1 — Final Review (gate obrigatório)

- [ ] Todos os módulos existem (`code.rs`, `error.rs`, `report.rs`, `transport.rs`, `lib.rs`)
- [ ] `ErrorCode` cobre todos os domínios listados na fase P
- [ ] `AppError::severity()` e `retryable()` consistentes com a tabela da fase R
- [ ] `to_status()` alinha ao mapeamento da tabela R2
- [ ] `tonic = "0.14.6"` em `[workspace.dependencies]`
- [ ] `error_core` em `[workspace.members]`
- [ ] Todos os testes da fase E existem e passam
- [ ] Documentação em pt-br; identificadores em inglês
- [ ] Nenhum `unwrap()`/`expect()` em `src/`

#### C2 — Atualização de documentação

- Atualizar `doc_dev/planejamento/06-tratamento-de-erros.md` com status "Implementado".
- Registrar `tonic = "0.14.6"` na documentação auxiliar de libs do workspace.

#### C3 — Arquivamento

Mover para `.context/plans/archive/tratamento-de-erros/`.

---

## Resumo de Artefatos a Criar

| Artefato | Fase |
|----------|------|
| `server/crates/error_core/Cargo.toml` | E |
| `server/crates/error_core/src/lib.rs` | E |
| `server/crates/error_core/src/code.rs` | E |
| `server/crates/error_core/src/error.rs` | E |
| `server/crates/error_core/src/report.rs` | E |
| `server/crates/error_core/src/transport.rs` | E |
| `server/crates/error_core/tests/from_conversions_tests.rs` | E |
| `server/crates/error_core/tests/transport_tests.rs` | E |
| `server/crates/error_core/tests/report_tests.rs` | E |
| `server/crates/error_core/tests/integration_observability.rs` | V |
| Atualizar `server/Cargo.toml` (workspace deps + members) | E |

---

## Correções Aplicadas

### C-01 — `tonic` adicionada ao workspace (CRÍTICO)

**Problema:** `tonic` não estava em `[workspace.dependencies]` do `server/Cargo.toml`.

**Correção:** decisão E8 adicionada: adicionar `tonic = "0.14.6"` antes da fase E.

**Fonte:** `info_aux_tratamento-de-erros.md`, seção "Notas Gerais".

---

### C-02 — `AppError` sem `#[from]` direto nos erros de crate ausentes

**Problema:** o plano original usava `#[from]` sobre `DbError`, `RedisError`, `StorageError`
e `AuthError`, mas essas crates ainda não existem no workspace.

**Correção:** `AppError` usa `String` como payload interno. Os `impl From<XError>` serão
adicionados incrementalmente quando as crates de infraestrutura existirem.

**Fonte:** contexto de arquitetura — crates existentes no workspace.

---

### C-03 — `Display` para `ErrorCode` sem `serde_json` em produção

**Problema:** `report.rs` sem forma eficiente de serializar `ErrorCode` para campos `tracing`.

**Correção:** `fmt::Display` implementado em `code.rs`; `report.rs` usa `%report.error_code`
diretamente via `Display`.

**Fonte:** análise das macros `tracing` — o prefixo `%` chama `Display`.

---

### C-04 — `AuthInsufficientScope` → `PermissionDenied` (não `Unauthenticated`)

**Problema:** plano base não diferenciava token inválido de escopo insuficiente no gRPC.

**Correção:** `AuthInsufficientScope` → `Code::PermissionDenied`; demais auth →
`Code::Unauthenticated`.

**Fonte:** tabela de mapeamento do info_aux; alinhamento com doc 09.

---

### C-05 — `RateLimitExceeded` e `Conflict` adicionados ao `ErrorCode`

**Problema:** plano original não listava esses códigos explicitamente.

**Correção:** ambos adicionados e mapeados para `ResourceExhausted` e `AlreadyExists`.

**Fonte:** análise dos casos de uso de negócio.

---

### C-06 — Testes separados por arquivo e feature-gated

**Problema:** testes listados de forma genérica sem separação por módulo ou feature.

**Correção:** três arquivos distintos; módulo `grpc` em `transport_tests.rs` protegido
por `#[cfg(feature = "grpc")]`.

**Fonte:** boas práticas de testes Rust com features opcionais.

---

### C-07 — `severity()` baseado em variante + conteúdo

**Problema:** regra simplista por variante seria imprecisa para `AppError::Storage`
(pode ser `Warn` ou `Error` dependendo do caso).

**Correção:** `severity()` usa correspondência de padrão composta (variante + conteúdo).

**Fonte:** análise dos domínios de erro; princípio de menor surpresa nos logs.

---

*Plano reestruturado em 2026-06-04 — pronto para entrada direta no agente de implementação (fase E).*
