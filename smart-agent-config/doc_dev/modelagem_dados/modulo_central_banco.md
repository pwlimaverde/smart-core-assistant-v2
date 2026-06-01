# Arquitetura de Módulo de Banco de Dados Centralizado (Crate `infrastructure_postgres`)

Este documento descreve as diretrizes para a crate de persistência do ecossistema Rust, localizada em `server/crates/infrastructure_postgres/`. Ela gerencia conexões, migrações, políticas RLS, validações de acesso e queries SQL de forma centralizada e organizada dentro do Cargo Workspace.

---

## 1. Por que Centralizar a Persistência em uma Crate Dedicada?

No ecossistema Rust (Cargo Workspaces), isolar todo acesso ao banco em uma crate de infraestrutura (`infrastructure_postgres`) é a prática recomendada.

### Principais Vantagens Técnicas:

1. **Otimização do Tempo de Compilação:**
   O driver SQLx, a extensão pgvector e bibliotecas como `rust_decimal` e `aes-gcm` são pesados para compilar. Mantendo-os em uma única crate física, apenas `infrastructure_postgres` os compila. As crates de domínio (`domain_*`) e os binários (`apps/`) importam apenas structs e traits leves, sem recompilar drivers.
2. **Simplificação do CI/CD e Modo Offline do SQLx:**
   As macros `sqlx::query!` exigem `DATABASE_URL` ativa ou o arquivo `.sqlx/` preparado (modo offline). Centralizar as queries em uma única crate significa executar `cargo sqlx prepare` apenas nesta pasta, simplificando o pipeline de CI.
3. **Gestão Única de Migrações:**
   As migrations ficam em `server/crates/infrastructure_postgres/migrations/`, embutidas no binário desta crate. Nenhum outro binário carrega migrações separadamente.
4. **Isolamento de I/O nos Domínios:**
   As crates `domain_*` não importam `infrastructure_postgres`. Todo I/O passa pela camada de aplicação (`crates/application/`) que orquestra os repositórios definidos aqui.

---

## 2. Estrutura de Diretórios da Crate

A crate está organizada internamente por domínios de negócio. A estrutura reflete os módulos funcionais do banco de dados unificado:

```
server/crates/infrastructure_postgres/
├── Cargo.toml              # Declara sqlx, pgvector, dashmap, aes-gcm, rust_decimal, etc.
├── migrations/             # Migrations únicas do banco unificado (embutidas no binário)
│   ├── 0001_create_rls_function.sql
│   ├── 0002_tenants.sql
│   ├── 0003_plans_subscriptions.sql
│   ├── 0004_clientes_contatos.sql
│   ├── 0005_operacional.sql
│   ├── 0006_atendimentos.sql
│   ├── 0007_treinamento_rag.sql
│   ├── 0008_evolution_sync.sql
│   └── 0009_settings_manager.sql
└── src/
    ├── lib.rs              # Exporta sub-módulos, pool global e TenantConfigCache
    ├── errors.rs           # DbError: mapeia sqlx::Error, violações de constraint, permissões
    ├── connection.rs       # run_in_tenant_transaction + inicializar_banco_dados
    ├── security.rs         # RequestContext (tenant_id, user_id, user_scopes)
    ├── config_cache.rs     # TenantConfigCache (DashMap) + RuntimeConfig
    ├── tenants/            # Repositórios do módulo de tenants e configurações
    │   ├── mod.rs
    │   ├── tenants.rs      # CRUD de Tenant, TenantUser, TenantInvite
    │   ├── plans.rs        # CRUD de Plan, Subscription, PaymentRecord
    │   ├── config.rs       # Leitura de TenantConfig + resolução de fallback CoreSettings
    │   └── settings.rs     # CRUD de CoreSettings
    ├── clientes/           # Repositórios do módulo de clientes e contatos
    │   ├── mod.rs
    │   ├── contatos.rs     # CRUD e queries de Contato (oraculo_contato)
    │   └── clientes.rs     # CRUD e queries de Cliente (oraculo_cliente)
    ├── operacional/        # Repositórios do módulo operacional
    │   ├── mod.rs
    │   ├── departamentos.rs
    │   ├── atendentes.rs
    │   └── fluxos.rs       # FluxoAtendimento + EtapaFluxo
    ├── atendimentos/       # Repositórios do módulo de atendimentos e mensagens
    │   ├── mod.rs
    │   ├── atendimentos.rs
    │   ├── mensagens.rs
    │   ├── movimentos.rs   # MovimentoFluxo (histórico Kanban)
    │   └── campos.rs       # CampoPersonalizado + ValorCampoAtendimento
    ├── treinamento/        # Repositórios do módulo RAG
    │   ├── mod.rs
    │   ├── treinamentos.rs
    │   ├── documentos.rs   # Busca vetorial pgvector
    │   └── query_compose.rs
    └── integracoes/        # Repositórios do módulo de integrações WhatsApp
        ├── mod.rs
        ├── evolution.rs    # EvolutionInstance + EvolutionContact
        └── whitelist.rs
```

---

## 3. Padrão de Isolamento com RLS: Pool Global Único

**Decisão arquitetural:** O sistema usa **um único `PgPool` global** conectado ao banco unificado. Não existem múltiplos pools por tenant. O isolamento de dados é garantido exclusivamente pelo RLS do PostgreSQL, ativado via `SET LOCAL app.current_tenant` no início de cada transação.

```rust
// Localização: server/crates/infrastructure_postgres/src/connection.rs
use sqlx::{PgPool, Transaction, Postgres};
use uuid::Uuid;
use crate::errors::DbError;

/// Executa um bloco de código sob transação configurada com o tenant_id para RLS.
/// É a única forma de executar queries em tabelas isoladas por tenant.
pub async fn run_in_tenant_transaction<F, T, Fut>(
    pool: &PgPool,
    tenant_id: Uuid,
    callback: F,
) -> Result<T, DbError>
where
    F: FnOnce(Transaction<'_, Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<(T, Transaction<'_, Postgres>), DbError>>,
{
    let mut tx = pool.begin().await.map_err(DbError::SqlxError)?;

    // Ativa o filtro de RLS para todas as queries desta transação
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_id)
        .execute(&mut *tx)
        .await
        .map_err(DbError::SqlxError)?;

    let (result, tx_final) = callback(tx).await?;
    tx_final.commit().await.map_err(DbError::SqlxError)?;

    Ok(result)
}

/// Aplica as migrations do diretório unificado na inicialização da aplicação.
pub async fn inicializar_banco_dados(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}
```

---

## 4. Contexto de Requisição e Permissões

A struct `RequestContext` trafega informações de escopo do usuário e do inquilino requisitante em toda operação de banco:

```rust
// Localização: server/crates/infrastructure_postgres/src/security.rs
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct RequestContext {
    pub tenant_id: Uuid,
    pub user_id: i32,
    pub user_scopes: Vec<String>,
}

impl RequestContext {
    pub fn has_permission(&self, permission: &str) -> bool {
        self.user_scopes.iter().any(|p| p == permission)
    }
}
```

---

## 5. Exemplo de Repositório com RLS

```rust
// Localização: server/crates/infrastructure_postgres/src/clientes/contatos.rs
use async_trait::async_trait;
use sqlx::{Postgres, Transaction};
use chrono::{DateTime, Utc};
use crate::errors::DbError;
use crate::security::RequestContext;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, sqlx::FromRow)]
pub struct Contato {
    pub id: i32,
    pub tenant_id: uuid::Uuid,
    pub telefone: String,
    pub nome_contato: Option<String>,
    pub data_cadastro: DateTime<Utc>,
}

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

pub struct PostgresContatoRepository;

#[async_trait]
impl ContatoRepository for PostgresContatoRepository {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato: &Contato,
    ) -> Result<(), DbError> {
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
        // tenant_id explícito além do RLS garante uso de índice composto
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

## 6. Consumo pelos Binários (Handlers Axum)

Os handlers dos binários (`apps/runtime_api`, `apps/worker`, `apps/control_plane`) importam apenas tipos e funções da crate de infraestrutura. O pool global é injetado via estado do Axum:

```rust
// Localização: server/apps/runtime_api/src/handlers/contato.rs
use std::sync::Arc;
use axum::{extract::State, Extension, Json, response::IntoResponse, http::StatusCode};
use sqlx::PgPool;
use infrastructure_postgres::security::RequestContext;
use infrastructure_postgres::clientes::contatos::{Contato, ContatoRepository};
use infrastructure_postgres::connection::run_in_tenant_transaction;

pub async fn criar_contato_handler(
    State(pool): State<PgPool>,                                    // Pool global único
    State(contato_repo): State<Arc<dyn ContatoRepository>>,        // Injetado via DI
    Extension(ctx): Extension<RequestContext>,                      // Extraído do JWT via middleware
    Json(payload): Json<ContatoPayload>,
) -> Result<impl IntoResponse, AppError> {

    let novo_contato = run_in_tenant_transaction(&pool, ctx.tenant_id, |mut tx| async move {
        let contato = Contato {
            id: 0,
            tenant_id: ctx.tenant_id,
            telefone: payload.telefone,
            nome_contato: Some(payload.nome),
            data_cadastro: chrono::Utc::now(),
        };

        contato_repo.salvar(&mut tx, &ctx, &contato).await?;
        Ok((contato, tx))
    })
    .await?;

    Ok((StatusCode::CREATED, Json(novo_contato)))
}
```

---

## 7. Regras de Ouro para Evitar Acoplamento Nocivo

1. **Sem Regras de Negócio Funcionais:**
   A crate `infrastructure_postgres` **não deve** conter lógica como "enviar mensagem no WhatsApp", "verificar regras de resposta da LLM" ou "chamar integrações externas". Valida permissões, executa SQL e trata erros de banco — nada além disso.
2. **Sem Conexão Direta ao PostgreSQL fora desta Crate:**
   Nenhum outro crate do workspace (domínio ou aplicação) usa `sqlx` diretamente. Todo acesso ao banco passa pelos repositórios definidos aqui.
3. **Tratamento de Erros Isolado:**
   A crate define seu próprio enum `DbError` (mapeando erros do SQLx, decodificação e violações de constraint). Os handlers de API convertem `DbError` em respostas HTTP JSON de forma independente.
4. **Sem `tenant_id` omitido:**
   Toda query em tabela de negócio de tenant inclui `WHERE tenant_id = $1` explicitamente além do RLS. Dupla barreira de proteção e melhor desempenho de planejador.
5. **Divisão Estrita de Arquivos:**
   Nunca escreva queries de domínios diferentes no mesmo arquivo. A estrutura de pastas (`tenants/`, `clientes/`, `atendimentos/`, etc.) mapeia um-para-um com os módulos de negócio.
