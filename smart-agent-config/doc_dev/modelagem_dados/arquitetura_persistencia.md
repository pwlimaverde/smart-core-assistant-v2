# Padrão Arquitetural de Persistência (Repository Pattern com Crate `infrastructure_postgres`)

Este documento estabelece as diretrizes de design de software para a camada de persistência de dados do **Smart Core Assistant v2** em **Rust** sob uma arquitetura de **banco de dados único com isolamento lógico via Row-Level Security (RLS)**.

---

## 1. Organização de Crates e Isolamento Lógico

A camada de persistência física é unificada dentro do Cargo Workspace na crate **`infrastructure_postgres`** (`server/crates/infrastructure_postgres/`). Esta biblioteca encapsula todos os acessos SQL, definições de modelos, migrações e o gerenciamento do cache de configurações, servindo como dependência de infraestrutura consumida pelos binários (`apps/`) e pela crate de aplicação (`crates/application/`).

### O Fluxo Unidirecional de Dependência:

```
   ┌──────────────────────────────────────────────────────────────────┐
   │         Binários (control_plane / runtime_api / worker)          │
   │   Consome modelos, traits e funções de banco via crate/application│
   └─────────────────────────────┬────────────────────────────────────┘
                                 │ Depende de
                                 ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │                   Crate `application`                            │
   │   Orquestra casos de uso; consome repositórios de infra.        │
   └─────────────────────────────┬────────────────────────────────────┘
                                 │ Depende de
                                 ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │         Crate `infrastructure_postgres` (Biblioteca)             │
   │  Define modelos de dados, traits de repositório, migrations,    │
   │  TenantConfigCache (DashMap) e transações RLS via SQLx.         │
   └──────────────────────────────────────────────────────────────────┘
```

---

## 2. Padrão de Isolamento com Row-Level Security (RLS)

Com a decisão de unificar todos os inquilinos na mesma base física, a proteção de dados deve ser garantida no nível do PostgreSQL. As políticas de RLS ativas em tabelas de negócio do tenant filtram registros com base na sessão atual `app.current_tenant`.

Para garantir que toda query do SQLx seja executada sob o escopo correto, **a camada de persistência de negócio deve rodar dentro de uma transação que configura o RLS**.

### 2.1 A Estrutura de Contexto da Requisição

A struct `RequestContext` trafega informações de escopo do usuário e do inquilino requisitante:

```rust
// Localização: server/crates/infrastructure_postgres/src/security.rs
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct RequestContext {
    pub tenant_id: Uuid,
    pub user_id: i32,
    pub user_scopes: Vec<String>,
    /// IDs de FluxoAtendimento liberados para o usuário (de TenantUser.flow_permissions).
    /// Carregado pelo middleware de JWT para evitar query extra por request.
    pub flow_permissions: Vec<i32>,
}

impl RequestContext {
    pub fn has_permission(&self, permission: &str) -> bool {
        self.user_scopes.iter().any(|p| p == permission)
    }

    pub fn has_flow_permission(&self, flow_id: i32) -> bool {
        // Admins com escopo total têm acesso a todos os fluxos
        if self.has_permission("kanban:admin") {
            return true;
        }
        self.flow_permissions.contains(&flow_id)
    }
}
```

---

## 3. Estrutura de Repositório com Transação RLS

Diferente de consultas em banco aberto, os repositórios concretos da `infrastructure_postgres` recebem uma referência mutável da transação SQLx (`&mut Transaction<'_, Postgres>`) que já teve seu contexto de tenant inicializado.

### 3.1 Definição da Trait de Repositório

```rust
// Localização: server/crates/infrastructure_postgres/src/clientes/contatos.rs
use async_trait::async_trait;
use sqlx::{Postgres, Transaction};
use chrono::{DateTime, Utc};
use crate::errors::DbError;
use crate::security::RequestContext;

// Struct do contato mapeada na tabela oraculo_contato
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, sqlx::FromRow)]
pub struct Contato {
    pub id: i32,
    pub tenant_id: uuid::Uuid,
    pub telefone: String,
    pub nome_contato: Option<String>,
    pub data_cadastro: DateTime<Utc>,
}

// Interface para persistência
#[async_trait]
pub trait ContatoRepository: Send + Sync {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato: &Contato,
    ) -> Result<(), DbError>;

    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError>;
}
```

### 3.2 Implementação Concreta no SQLx (com RLS Herdado)

Como as queries rodam na transação em que configuramos `SET LOCAL app.current_tenant`, não é estritamente obrigatório adicionar a cláusula `WHERE tenant_id = $1` em todas as leituras comuns (o Postgres filtra nativamente). No entanto, **como boa prática de performance e indexação do planejador do Postgres, incluímos o tenant_id explicitamente**:

```rust
// Localização: server/crates/infrastructure_postgres/src/clientes/contatos.rs
pub struct PostgresContatoRepository;

#[async_trait]
impl ContatoRepository for PostgresContatoRepository {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato: &Contato,
    ) -> Result<(), DbError> {
        // Validação de permissões
        if !ctx.has_permission("clientes:write") {
            return Err(DbError::PermissionDenied);
        }

        sqlx::query!(
            r#"
            INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato, data_cadastro, ultima_interacao)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (tenant_id, telefone) DO UPDATE SET nome_contato = EXCLUDED.nome_contato
            "#,
            ctx.tenant_id,
            contato.telefone,
            contato.nome_contato,
            contato.data_cadastro
        )
        .execute(&mut **tx)
        .await
        .map_err(DbError::SqlxError)?;

        Ok(())
    }

    async fn buscar_por_telefone(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        telefone: &str,
    ) -> Result<Option<Contato>, DbError> {
        let contato = sqlx::query_as!(
            Contato,
            r#"
            SELECT id, tenant_id, telefone, nome_contato, data_cadastro
            FROM oraculo_contato
            WHERE tenant_id = $1 AND telefone = $2
            "#,
            ctx.tenant_id,
            telefone
        )
        .fetch_optional(&mut **tx)
        .await
        .map_err(DbError::SqlxError)?;

        Ok(contato)
    }
}
```

---

## 4. Consumo no Aplicativo (Handlers HTTP / Axum)

Os handlers de rotas do aplicativo inicializam a transação de RLS através de uma função helper e injetam a transação no repositório de dados:

```rust
// Localização: server/apps/runtime_api/src/handlers/contato.rs
use std::sync::Arc;
use axum::{extract::State, Extension, Json, response::IntoResponse, http::StatusCode};
use sqlx::PgPool;
use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::clientes::contatos::{Contato, ContatoRepository};
use infrastructure_postgres::connection::run_in_tenant_transaction;

pub async fn criar_contato_handler(
    State(pool): State<PgPool>,                            // Pool global unificado
    State(contato_repo): State<Arc<dyn ContatoRepository>>, // Injetado via DI
    Extension(ctx): Extension<RequestContext>,            // Contexto do JWT
    Json(payload): Json<ContatoPayload>,
) -> Result<impl IntoResponse, AppError> {
    
    // Executa as operações de persistência envelopadas com RLS na transação
    let novo_contato = run_in_tenant_transaction(&pool, ctx.tenant_id, |mut tx| async move {
        let contato = Contato {
            id: 0,
            tenant_id: ctx.tenant_id,
            telefone: payload.telefone,
            nome_contato: Some(payload.nome),
            data_cadastro: chrono::Utc::now(),
        };

        // Passa a transação mutável ativa contendo o contexto RLS da sessão
        contato_repo.salvar(&mut tx, &ctx, &contato).await?;

        Ok((contato, tx))
    })
    .await?;

    Ok((StatusCode::CREATED, Json(novo_contato)))
}
```

---

## 5. Configuração do PostgreSQL para Produção

### 5.1 Timeouts de segurança (versionados via migration)

Os timeouts abaixo são aplicados pela migration inicial `0001_create_rls_function.sql` em nível de DATABASE/ROLE, sobrevivem a `pg_dump/restore` e não requerem reinício do servidor:

| Setting | Valor | Nível | Motivo |
|---|---|---|---|
| `idle_in_transaction_session_timeout` | `30s` | DATABASE | Mata transação idle; libera locks e conexão de volta ao pool |
| `lock_timeout` | `15s` | DATABASE | Aborta espera por lock; evita deadlock silencioso em cascata |
| `statement_timeout` | `30s` | ROLE `smartcore_app` | Mata queries longas; não afeta migrations rodando como admin |

### 5.2 `postgresql.conf` — tuning por tamanho de servidor

Estas settings exigem reload (`SELECT pg_reload_conf()`) ou restart (`shared_buffers`). Aplicar via `ALTER SYSTEM` ou editando o arquivo diretamente.

```ini
# ---------- Memória (ajustar pelo RAM disponível) ----------
# VPS 2 GB:  shared_buffers=512MB  effective_cache_size=1536MB  work_mem=8MB
# VPS 4 GB:  shared_buffers=1GB    effective_cache_size=3GB     work_mem=16MB
shared_buffers            = 512MB          # 25% da RAM
effective_cache_size      = 1536MB         # 75% da RAM
work_mem                  = 8MB            # por operação de sort/hash
maintenance_work_mem      = 128MB          # VACUUM, CREATE INDEX

# ---------- WAL / Checkpoint ----------
wal_buffers               = 16MB           # default auto é ~4MB, insuficiente
checkpoint_completion_target = 0.9         # default — manter
max_wal_size              = 1GB            # default — manter

# ---------- Planner (armazenamento SSD/cloud) ----------
random_page_cost          = 1.1            # SSD; default 4.0 é para HDD
effective_io_concurrency  = 200            # SSD; default 1

# ---------- Paralelismo (pgvector usa parallel workers) ----------
max_parallel_workers_per_gather = 2

# ---------- Logging ----------
log_min_duration_statement = 1000          # loga queries > 1s; útil para tuning
log_line_prefix = '%t [%p] user=%u db=%d app=%a '
```

### 5.3 Supervisão do processo (produção)

O Postgres deve ser gerenciado pelo systemd com restart automático. Sem isso, uma
queda do processo (OOM, kill) deixa o serviço fora até intervenção manual.

```ini
# /etc/systemd/system/postgresql@16-main.service.d/override.conf
[Service]
Restart=always
RestartSec=5s
```

---

## 6. Prós da Mudança para Banco Único com RLS

1. **Simplicidade de Infraestrutura:** A aplicação Rust não precisa lidar com centenas de pools de conexão dinâmicos simultâneos em memória. Um único pool robusto do PostgreSQL atende a toda a carga.
2. **Consistência de Testabilidade:** Para mockar o banco em testes de unidade, basta mockar a transação ou injetar o repositório in-memory convencional. A lógica de RLS é imposta de forma isolada na camada de infraestrutura SQLx.
3. **Segurança no Banco:** Se um erro de programação nas camadas superiores falhar em filtrar a query por `tenant_id`, a política RLS ativa no cluster PostgreSQL barreira o leak de dados para outros inquilinos automaticamente, agindo como uma dupla barreira de proteção de dados.
