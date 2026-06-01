# Padrão Arquitetural de Persistência (Repository Pattern com Crate `db_access`)

Este documento estabelece as diretrizes de design de software para a camada de persistência de dados do **Smart Core Assistant v2** em **Rust** sob uma arquitetura de **banco de dados único com isolamento lógico via Row-Level Security (RLS)**.

---

## 1. Organização de Crates e Isolamento Lógico

A camada de persistência física é unificada dentro do Cargo Workspace na crate **`db_access`**. Esta biblioteca encapsula todos os acessos SQL, definições de modelos, migrações e o gerenciamento do cache de configurações, servindo como uma dependência direta para o aplicativo executável principal (`web_api` ou workers).

### O Fluxo Unidirecional de Dependência:

```
   ┌────────────────────────────────────────────────┐
   │             Core App (web_api / workers)       │
   │   Consome modelos, traits e funções de banco.  │
   └───────────────────────┬────────────────────────┘
                           │ Depende de
                           ▼
   ┌────────────────────────────────────────────────┐
   │             Crate `db_access` (Biblioteca)     │
   │  Define modelos de dados, traits, migrations,  │
   │  TenantConfigCache e transações RLS.           │
   └────────────────────────────────────────────────┘
```

---

## 2. Padrão de Isolamento com Row-Level Security (RLS)

Com a decisão de unificar todos os inquilinos na mesma base física, a proteção de dados deve ser garantida no nível do PostgreSQL. As políticas de RLS ativas em tabelas de negócio do tenant filtram registros com base na sessão atual `app.current_tenant`.

Para garantir que toda query do SQLx seja executada sob o escopo correto, **a camada de persistência de negócio deve rodar dentro de uma transação que configura o RLS**.

### 2.1 A Estrutura de Contexto da Requisição

A struct `RequestContext` trafega informações de escopo do usuário e do inquilino requisitante:

```rust
// Localização: db_access/src/security.rs
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

## 3. Estrutura de Repositório com Transação RLS

Diferente de consultas em banco aberto, os repositórios concretos do `db_access` recebem uma referência mutável da transação SQLx (`&mut Transaction<'_, Postgres>`) que já teve seu contexto de tenant inicializado.

### 3.1 Definição da Trait de Repositório

```rust
// Localização: db_access/src/tenant/clientes.rs
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
// Localização: db_access/src/tenant/clientes.rs
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
// Localização: web_api/src/handlers/contato.rs
use std::sync::Arc;
use axum::{extract::State, Extension, Json, response::IntoResponse, http::StatusCode};
use sqlx::PgPool;
use db_access::security::RequestContext;
use db_access::tenant::clientes::{Contato, ContatoRepository};
use db_access::connection::run_in_tenant_transaction; // Helper de transação RLS

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

## 5. Prós da Mudança para Banco Único com RLS

1. **Simplicidade de Infraestrutura:** A aplicação Rust não precisa lidar com centenas de pools de conexão dinâmicos simultâneos em memória. Um único pool robusto do PostgreSQL atende a toda a carga.
2. **Consistência de Testabilidade:** Para mockar o banco em testes de unidade, basta mockar a transação ou injetar o repositório in-memory convencional. A lógica de RLS é imposta de forma isolada na camada de infraestrutura SQLx.
3. **Segurança no Banco:** Se um erro de programação nas camadas superiores falhar em filtrar a query por `tenant_id`, a política RLS ativa no cluster PostgreSQL barreira o leak de dados para outros inquilinos automaticamente, agindo como uma dupla barreira de proteção de dados.
