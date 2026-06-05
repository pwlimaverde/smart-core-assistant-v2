# Documentação Auxiliar — Tratamento de Erros (`error_core`)

> Gerado em: 2026-06-04
> Plano canônico: `.context/plans/tratamento-de-erros.md`
> Plano completo: `.context/plans/tratamento-de-erros/plano_completo_tratamento-de-erros.md`

Todas as libs abaixo são puramente internas (Rust). Nenhum serviço externo envolvido.
Fontes: central local `doc_dev/libs/rust/` — todas com status ✅ ATUALIZADA.

---

## Libs Rust

### thiserror (1.0)

> Fonte: `doc_dev/libs/rust/thiserror_anyhow.md` — Última Verificação: 2026-05-31

**Propósito no plano:** derivar automaticamente `std::error::Error` para o enum `AppError`
e para os erros por crate (`DbError`, `RedisError`, `StorageError`, `AuthError`).

**Padrão adotado no projeto:**

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("Erro de banco de dados: {0}")]
    Database(#[from] DbError),

    #[error("Erro de cache: {0}")]
    Cache(#[from] RedisError),

    #[error("Erro de armazenamento: {0}")]
    Storage(#[from] StorageError),

    #[error("Erro de autenticação: {0}")]
    Auth(#[from] AuthError),
}
```

- `#[from]` gera `impl From<X> for AppError` automaticamente.
- Cada crate mantém seu próprio erro (`thiserror`); `AppError` os agrega na camada `application`.
- **Proibido** `unwrap()`/`expect()` em código de produção — usar sempre `?`/`Result<_, AppError>`.

---

### serde (1.0)

> Fonte: `doc_dev/libs/rust/serde.md` — Última Verificação: 2026-05-31

**Propósito no plano:** serializar `ErrorCode` para string estável (uso em logs JSON,
métricas e resposta ao cliente).

**Padrão adotado:**

```rust
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    AuthInvalidToken,
    AuthExpiredToken,
    StorageNotFound,
    DbConnectionFailed,
    // ...
}
```

- `rename_all = "SCREAMING_SNAKE_CASE"` → serializa para `"AUTH_INVALID_TOKEN"` etc.,
  estável para clientes e sistemas de alerta.
- Ative a feature `features = ["derive"]` no `Cargo.toml` (já no workspace).

---

### tracing (0.1.40)

> Fonte: `doc_dev/libs/rust/tracing.md` — Última Verificação: 2026-05-31

**Propósito no plano:** registrar erros com correlação (`trace_id`, `tenant_id`,
`error_code`) via `error!()` e `warn!()`, sem vazar PII.

**Padrão adotado:**

```rust
use tracing::{error, warn};

pub fn registrar(err: &AppError, ctx: &ErrorContext) {
    let report = ErrorReport::from(err, ctx);

    match report.severity {
        Severity::Error => error!(
            error_code = %report.error_code,
            trace_id   = %report.trace_id,
            tenant_id  = %report.tenant_id,
            message    = %report.public_message,
            "Erro de aplicação registrado"
        ),
        Severity::Warn => warn!(
            error_code = %report.error_code,
            trace_id   = %report.trace_id,
            tenant_id  = %report.tenant_id,
            message    = %report.public_message,
            "Aviso de aplicação registrado"
        ),
    }
}
```

- Nunca usar `println!` — todos os logs passam pelo Tracing.
- O Tracing já está configurado pela crate `observability` (doc 05).
- Campos sensitivos (senhas, tokens) **nunca** entram no log.

---

### tonic (0.14.6, feature opcional)

> Fonte: `doc_dev/libs/rust/tonic.md` — Última Verificação: 2026-06-04

**Propósito no plano:** `to_status() -> tonic::Status` — converte `ErrorCode` para
o código gRPC correto na borda do handler (mapeamento único, sem reinventar em cada handler).

**Mapeamento ErrorCode → tonic::Code:**

```rust
use tonic::{Code, Status};

impl AppError {
    pub fn to_status(&self) -> Status {
        let code = self.error_code();
        let msg  = self.public_message();

        let grpc_code = match code {
            ErrorCode::AuthInvalidToken
            | ErrorCode::AuthExpiredToken
            | ErrorCode::AuthMissingToken   => Code::Unauthenticated,

            ErrorCode::AuthInsufficientScope => Code::PermissionDenied,

            ErrorCode::StorageNotFound
            | ErrorCode::DbRecordNotFound    => Code::NotFound,

            ErrorCode::DbConnectionFailed
            | ErrorCode::CacheUnavailable    => Code::Internal,

            ErrorCode::ValidationFailed      => Code::InvalidArgument,

            _                                => Code::Internal,
        };

        Status::new(grpc_code, msg)
    }
}
```

- `tonic` é **dependência opcional** na crate `error_core` (feature `grpc`).
  Quem não usa gRPC não precisa carregar a dep.
- Mapeamento alinha ao doc 09 (defesa-em-3-camadas): `unauthenticated` /
  `permission_denied` / `not_found` / `internal` / `invalid_argument`.

---

## Grupo B — Serviços Externos

Nenhum. A crate `error_core` é puramente interna — sem HTTP externo, sem gRPC client,
sem banco de dados próprio.

---

## Notas Gerais

- `tonic` não está nas `[workspace.dependencies]` do `server/Cargo.toml` atual.
  Será necessário adicioná-lo antes de usar em `error_core` (via feature opcional).
- Versão confirmada pela central local: `tonic = "0.14.6"` (compatível com `tokio 1.x`).
- O `tracing` configurado pelo `observability` deve ser inicializado **antes** de qualquer
  chamada ao helper `registrar`. Em testes, use um subscriber simplificado com
  `tracing_subscriber::fmt().init()` ou `tracing-test`.
- Erro por crate (`DbError`, `RedisError`, `StorageError`, `AuthError`) — cada um fica
  em sua crate; só são convertidos para `AppError` via `From<>` na camada `application`.
