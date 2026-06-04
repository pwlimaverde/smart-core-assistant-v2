# Plano Completo — Observabilidade e Auditoria

> **Origem:** `doc_dev/planejamento/05-observabilidade.md` + contexto de auditoria fornecido pelo usuário.
> **Reestruturado em:** 2026-06-04
> **Documentação auxiliar:** `.context/plans/observabilidade-e-auditoria/info_aux_observabilidade-e-auditoria.md`

---

## Resumo do Objetivo

Implementar o sistema completo de **observabilidade** (logs estruturados, métricas e traces distribuídos) e **auditoria de negócio** (logs de ações críticas no PostgreSQL) para o Smart Core Assistant v2. O plano está dividido em duas dimensões complementares:

1. **Logs de Aplicação (técnicos):** JSON estruturado no stdout → Docker → Loki via Promtail/Alloy. Nunca no banco.
2. **Logs de Auditoria (negócio/segurança):** Tabela dedicada `audit_log` no PostgreSQL com RLS, para rastrear ações críticas dos usuários (cadastros, logins, acessos não autorizados, operações sensíveis).

---

## Fase 1 — Infraestrutura do PostgreSQL para Auditoria (Pré-requisito)

> **Agente:** infrastructure / Sessão principal
> **PREVC:** P (Planning)
> **Dependência:** Nenhuma (executa antes da crate observability)

### 1.1 Migration `0010_audit_log.sql`

Nova migration em `server/crates/infrastructure_postgres/migrations/0010_audit_log.sql`:

```sql
-- ============================================================
-- Módulo Auditoria: logs de eventos de negócio e segurança
-- Tabela com RLS activa.
-- tenant_id NULLABLE — ações de superusuário/sistema não têm tenant.
-- ============================================================

CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID REFERENCES tenants_tenant(id) ON DELETE CASCADE, -- NULL = ação de superusuário ou sistema
    timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level       VARCHAR(10) NOT NULL DEFAULT 'INFO',
    service     VARCHAR(100) NOT NULL,
    trace_id    VARCHAR(64),
    event       VARCHAR(255) NOT NULL,
    message     TEXT NOT NULL,
    context     JSONB NOT NULL DEFAULT '{}',
    user_id     INTEGER REFERENCES auth_user(id) ON DELETE SET NULL,  -- NULL = ação automática ou externa
    ip_address  VARCHAR(45),       -- suporta IPv4 e IPv6
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_log IS
    'Logs de auditoria de eventos de negócio e segurança. '
    'tenant_id NULL indica ação de superusuário/sistema. '
    'Protegida por RLS com duas policies.';

-- ============================================================
-- Índices
-- ============================================================

-- Consultas por tenant (a maioria)
CREATE INDEX idx_audit_log_tenant_timestamp
    ON audit_log (tenant_id, timestamp DESC)
    WHERE tenant_id IS NOT NULL;

CREATE INDEX idx_audit_log_tenant_event
    ON audit_log (tenant_id, event)
    WHERE tenant_id IS NOT NULL;

CREATE INDEX idx_audit_log_tenant_user
    ON audit_log (tenant_id, user_id)
    WHERE tenant_id IS NOT NULL AND user_id IS NOT NULL;

-- Consultas de ações globais (superusuário) — sem tenant
CREATE INDEX idx_audit_log_global_timestamp
    ON audit_log (timestamp DESC)
    WHERE tenant_id IS NULL;

-- Consultas por nível de alerta
CREATE INDEX idx_audit_log_level
    ON audit_log (level, timestamp DESC)
    WHERE level IN ('WARN', 'ERROR');

-- Busca no JSONB context
CREATE INDEX idx_audit_log_context
    ON audit_log USING GIN (context jsonb_path_ops);

-- Busca por evento (cross-tenant, para dashboards admin)
CREATE INDEX idx_audit_log_event_timestamp
    ON audit_log (event, timestamp DESC);

-- ============================================================
-- RLS: Duas policies
-- 1. Tenant vê apenas seus próprios logs (quando app.current_tenant está setado)
-- 2. Ações globais (tenant_id IS NULL) só visíveis via admin pool (BYPASSRLS)
-- ============================================================

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;

-- Policy para operações do tenant: vê apenas registros do seu tenant
CREATE POLICY audit_log_tenant_isolation ON audit_log
    FOR ALL
    USING (
        tenant_id IS NOT NULL
        AND tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    );

-- Nota: registros com tenant_id IS NULL NÃO são visíveis por nenhuma policy.
-- Somente o pool admin (BYPASSRLS, criar_admin_pool) consegue ler/gravar.
-- Isso garante que ações de superusuário são invisíveis para tenants comuns.
```

**Decisões de design:**

| Aspecto | Decisão | Racional |
|---------|---------|----------|
| PK | UUID (gen_random_uuid) | Consistente com o projeto; não expõe sequência |
| `tenant_id` | **UUID nullable** | NULL = ação de superusuário/sistema (sem contexto de tenant) |
| `level` | VARCHAR(10) | INFO, WARN, ERROR — alinhado com tracing levels |
| `context` | JSONB | Flexível para diferentes tipos de evento sem alterar schema |
| `trace_id` | VARCHAR(64) | Correlação com traces do OTel (W3C TraceContext tem 32 hex chars) |
| `user_id` | INTEGER nullable | Eventos automáticos/cron podem não ter user |
| `ip_address` | VARCHAR(45) | Armazena IPs IPv4 ou IPv6 como texto; evita dependência do tipo INET no sqlx |
| RLS | **Duas policies** separadas | Tenant vê só os seus; registros globais (NULL) só via admin BYPASSRLS |
| Particionamento | Não nesta fase | Volume esperado baixo; reavaliar quando >1M registros/mês |

> **Regra de ouro:** Todo INSERT de log de auditoria com `tenant_id = NULL` (superusuário)
> DEVE usar o **admin pool** (`criar_admin_pool` — BYPASSRLS), pois a policy RLS
> normal não permite gravar registros sem tenant. Inserções com tenant usam
> `run_in_tenant_transaction` normalmente.

### 1.2 Repositório `audit_log` em `infrastructure_postgres`

Novo módulo `server/crates/infrastructure_postgres/src/auditoria/`:

```
src/auditoria/
├── mod.rs          # pub mod audit_log;
└── audit_log.rs    # AuditLogRepository + AuditLogEntry struct
```

#### `audit_log.rs`

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, Transaction, Row};
use uuid::Uuid;

use crate::errors::DbError;

/// Registro de um evento de auditoria.
/// `tenant_id` é `Option` — NULL indica ação de superusuário/sistema.
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct AuditLogEntry {
    pub id: Uuid,
    pub tenant_id: Option<Uuid>,  // NULL = superusuário/sistema
    pub timestamp: DateTime<Utc>,
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Dados para inserir um novo registro de auditoria.
#[derive(Debug, Clone)]
pub struct NewAuditLogEntry {
    pub tenant_id: Option<Uuid>,  // None = ação global (superusuário)
    pub level: String,
    pub service: String,
    pub trace_id: Option<String>,
    pub event: String,
    pub message: String,
    pub context: serde_json::Value,
    pub user_id: Option<i32>,
    pub ip_address: Option<String>,
}

// ============================================================
// Inserção — duas variantes: com tenant (RLS) e global (admin)
// ============================================================

/// Insere um registro de auditoria COM tenant_id (dentro de transação com RLS ativo).
/// Usar para ações de usuários regulares dentro de um tenant.
pub async fn inserir_audit_log(
    tx: &mut Transaction<'_, Postgres>,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id
        "#
    )
    .bind(entry.tenant_id)
    .bind(&entry.level)
    .bind(&entry.service)
    .bind(&entry.trace_id)
    .bind(&entry.event)
    .bind(&entry.message)
    .bind(&entry.context)
    .bind(entry.user_id)
    .bind(&entry.ip_address)
    .fetch_one(&mut **tx)
    .await?;

    let id: Uuid = row.get("id");
    Ok(id)
}

/// Insere um registro de auditoria GLOBAL (sem tenant) usando o admin pool (BYPASSRLS).
/// Usar para ações de superusuário, sistema, cron jobs, etc.
pub async fn inserir_audit_log_global(
    admin_pool: &PgPool,
    entry: &NewAuditLogEntry,
) -> Result<Uuid, DbError> {
    let row = sqlx::query(
        r#"
        INSERT INTO audit_log (tenant_id, level, service, trace_id, event, message, context, user_id, ip_address)
        VALUES (NULL, $1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
        "#
    )
    .bind(&entry.level)
    .bind(&entry.service)
    .bind(&entry.trace_id)
    .bind(&entry.event)
    .bind(&entry.message)
    .bind(&entry.context)
    .bind(entry.user_id)
    .bind(&entry.ip_address)
    .fetch_one(admin_pool)
    .await?;

    let id: Uuid = row.get("id");
    Ok(id)
}

// ============================================================
// Consultas
// ============================================================

/// Busca registros de auditoria do tenant com paginação.
/// Usa transação com RLS — o tenant só vê seus próprios registros.
pub async fn buscar_audit_logs(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id = $1
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#
    )
    .bind(tenant_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(rows)
}

/// Busca registros de auditoria filtrados por evento.
pub async fn buscar_audit_logs_por_evento(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    event: &str,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id = $1 AND event = $2
        ORDER BY timestamp DESC
        LIMIT $3 OFFSET $4
        "#
    )
    .bind(tenant_id)
    .bind(event)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut **tx)
    .await?;

    Ok(rows)
}

/// Busca TODOS os registros de auditoria (cross-tenant + globais).
/// Requer admin pool (BYPASSRLS). Uso exclusivo do painel administrativo.
pub async fn buscar_audit_logs_admin(
    admin_pool: &PgPool,
    event_filter: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE ($1::text IS NULL OR event = $1)
        ORDER BY timestamp DESC
        LIMIT $2 OFFSET $3
        "#
    )
    .bind(event_filter)
    .bind(limit)
    .bind(offset)
    .fetch_all(admin_pool)
    .await?;

    Ok(rows)
}

/// Busca registros globais (sem tenant) — ações de superusuário.
/// Requer admin pool (BYPASSRLS).
pub async fn buscar_audit_logs_globais(
    admin_pool: &PgPool,
    limit: i64,
    offset: i64,
) -> Result<Vec<AuditLogEntry>, DbError> {
    let rows = sqlx::query_as::<_, AuditLogEntry>(
        r#"
        SELECT id, tenant_id, timestamp, level, service, trace_id,
               event, message, context, user_id, ip_address, created_at
        FROM audit_log
        WHERE tenant_id IS NULL
        ORDER BY timestamp DESC
        LIMIT $1 OFFSET $2
        "#
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(admin_pool)
    .await?;

    Ok(rows)
}
```

### 1.3 Registrar o módulo em `lib.rs`

Adicionar `pub mod auditoria;` ao `lib.rs` da crate `infrastructure_postgres`, e re-exports de conveniência.

---

## Fase 2 — Crate `observability` (Instrumentação Rust) — F0.4

> **Agente:** backend-rust
> **PREVC:** E (Execution)
> **Dependência:** Fase 1 (migration de auditoria aplicada)

### 2.1 Estrutura da Crate

Nova crate `server/crates/observability`:

```
server/crates/observability/
├── Cargo.toml
└── src/
    ├── lib.rs          # reexports + doc
    ├── telemetry.rs    # init_telemetry(), shutdown_telemetry()
    ├── audit.rs        # AuditLogger (fire-and-forget para o Postgres)
    ├── propagation.rs  # Context propagation carriers para Redis/HashMaps
    └── span_helpers.rs # macros/helpers para tenant_id span
```

### 2.2 `Cargo.toml`

```toml
[package]
name    = "observability"
version = "0.1.0"
edition.workspace = true

[dependencies]
# Tracing
tracing.workspace            = true
tracing-subscriber = { version = "0.3", features = ["json", "env-filter", "fmt", "registry"] }

# OpenTelemetry
opentelemetry       = "0.24"
opentelemetry_sdk   = { version = "0.24", features = ["rt-tokio"] }
opentelemetry-otlp  = { version = "0.17", features = ["grpc-tonic", "trace"] }
tracing-opentelemetry = "0.25"

# Runtime e serialização
tokio.workspace              = true
serde.workspace              = true
serde_json.workspace         = true
chrono.workspace             = true
uuid.workspace               = true

# Infra Postgres (para o AuditLogger)
infrastructure_postgres = { path = "../infrastructure_postgres" }
sqlx.workspace               = true
```

### 2.3 `telemetry.rs` — Inicialização

```rust
use opentelemetry::global;
use opentelemetry::KeyValue;
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{
    propagation::TraceContextPropagator,
    trace::Config,
    Resource,
};
use tracing_opentelemetry::OpenTelemetryLayer;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};

pub fn init_telemetry(
    service_name: &str,
    env: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    global::set_text_map_propagator(TraceContextPropagator::new());

    let otlp_endpoint = std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4317".into());

    let resource = Resource::new(vec![
        KeyValue::new("service.name", service_name.to_string()),
        KeyValue::new("deployment.environment", env.to_string()),
    ]);

    use opentelemetry::trace::TracerProvider as _;

    let provider = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint(otlp_endpoint),
        )
        .with_trace_config(Config::default().with_resource(resource))
        .install_batch(opentelemetry_sdk::runtime::Tokio)?;

    let tracer = provider.tracer(service_name.to_string());
    let otel_layer = OpenTelemetryLayer::new(tracer);

    let json_layer = fmt::layer()
        .json()
        .with_target(true)
        .with_thread_ids(true)
        .with_file(true)
        .with_line_number(true);

    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    Registry::default()
        .with(env_filter)
        .with(json_layer)
        .with(otel_layer)
        .init();

    tracing::info!(
        service = service_name,
        environment = env,
        "Telemetria inicializada com sucesso (stdout JSON + OTLP gRPC)."
    );

    Ok(())
}

pub fn shutdown_telemetry() {
    tracing::info!("Encerrando telemetria — flushing spans pendentes...");
    global::shutdown_tracer_provider();
}
```

### 2.4 `audit.rs` — AuditLogger (fire-and-forget para Postgres)

```rust
use infrastructure_postgres::{
    inserir_audit_log, inserir_audit_log_global, NewAuditLogEntry,
};
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Clone)]
pub struct AuditLogger {
    tenant_pool: PgPool,
    admin_pool: PgPool,
    service_name: String,
}

impl AuditLogger {
    pub fn new(tenant_pool: PgPool, admin_pool: PgPool, service_name: &str) -> Self {
        Self {
            tenant_pool,
            admin_pool,
            service_name: service_name.to_string(),
        }
    }

    pub fn log_tenant_event(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        let pool = self.tenant_pool.clone();
        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();

        tokio::spawn(async move {
            let entry = NewAuditLogEntry {
                tenant_id: Some(tenant_id),
                level,
                service,
                trace_id,
                event: event.clone(),
                message,
                context,
                user_id,
                ip_address,
            };

            let result = infrastructure_postgres::run_in_tenant_transaction(
                &pool,
                tenant_id,
                |mut tx| async move {
                    let id = inserir_audit_log(&mut tx, &entry).await?;
                    Ok((id, tx))
                },
            )
            .await;

            if let Err(e) = result {
                tracing::error!(
                    error = ?e,
                    audit_event = %event,
                    tenant_id = %tenant_id,
                    "Falha ao persistir log de auditoria do inquilino no banco."
                );
            }
        });
    }

    pub fn log_global_event(
        &self,
        event: &str,
        message: &str,
        level: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        let admin_pool = self.admin_pool.clone();
        let service = self.service_name.clone();
        let event = event.to_string();
        let message = message.to_string();
        let level = level.to_string();

        tokio::spawn(async move {
            let entry = NewAuditLogEntry {
                tenant_id: None,
                level,
                service,
                trace_id,
                event: event.clone(),
                message,
                context,
                user_id,
                ip_address,
            };

            let result = inserir_audit_log_global(&admin_pool, &entry).await;

            if let Err(e) = result {
                tracing::error!(
                    error = ?e,
                    audit_event = %event,
                    "Falha ao persistir log de auditoria global no banco."
                );
            }
        });
    }

    pub fn info(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "INFO", context, user_id, ip_address, trace_id);
    }

    pub fn warn(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "WARN", context, user_id, ip_address, trace_id);
    }

    pub fn error(
        &self,
        tenant_id: Uuid,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_tenant_event(tenant_id, event, message, "ERROR", context, user_id, ip_address, trace_id);
    }

    pub fn info_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "INFO", context, user_id, ip_address, trace_id);
    }

    pub fn warn_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "WARN", context, user_id, ip_address, trace_id);
    }

    pub fn error_global(
        &self,
        event: &str,
        message: &str,
        context: serde_json::Value,
        user_id: Option<i32>,
        ip_address: Option<String>,
        trace_id: Option<String>,
    ) {
        self.log_global_event(event, message, "ERROR", context, user_id, ip_address, trace_id);
    }
}
```

### 2.5 `span_helpers.rs` — Helpers de Span com `tenant_id`

```rust
#[macro_export]
macro_rules! tenant_span {
    ($tenant_id:expr, $name:expr) => {
        tracing::info_span!($name, tenant_id = %$tenant_id)
    };
    ($tenant_id:expr, $trace_id:expr, $name:expr) => {
        tracing::info_span!($name, tenant_id = %$tenant_id, trace_id = %$trace_id)
    };
}
```

---

## Fase 3 — Stack LGTM Self-Hosted (Docker Compose) — F9.1

> **Agente:** devops / Sessão principal
> **PREVC:** E (Execution)
> **Dependência:** Crate observability compilando

### 3.1 compose/observability.yml
Ver [observability.yml](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/docker/compose/observability.yml)

### 3.2 Configurações de Serviço (`docker/observability/`)
Configs criadas para otel-collector, loki, tempo, prometheus e promtail.

---

## Fase 4 — Métricas e Spans Avançados — F4–F6

Helpers de propagação do TraceContext implementados no Rust para HashMaps em `propagation.rs` genérico.

---

## Fase 5 — Health Checks, Alertas e Dashboards — F9.1

Dashboards e fontes de dados Grafana provisionados as-code.

---

## Correções Aplicadas
Ver seção respectiva no [walkthrough.md](file:///C:/Users/pwlim/.gemini/antigravity-ide/brain/4269e0b8-8219-4853-9eb1-e5b6b84047bb/walkthrough.md).
