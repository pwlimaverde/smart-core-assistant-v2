# Arquitetura de Módulo de Banco de Dados Centralizado (Crate `db_access`)

Este documento descreve as diretrizes para unificar a infraestrutura de dados em um único módulo físico (crate de biblioteca) no ecossistema Rust, gerenciando conexões, migrações, validações de acesso e queries SQL de forma centralizada e organizada.

---

## 1. Por que Unificar a Persistência em uma Crate?

No ecossistema Rust (especialmente usando **Cargo Workspaces**), a criação de uma crate dedicada (ex: `smart_core_db` ou `db_access`) para gerenciar todo o acesso ao banco de dados é considerada uma **excelente prática**.

### Principais Vantagens Técnicas:

1. **Otimização do Tempo de Compilação:** 
   O driver SQLx, a extensão pgvector e bibliotecas como `rust_decimal` e `aes-gcm` são pesados para compilar. Mantendo-os em um único módulo físico, apenas essa crate de banco os compila. As outras partes do sistema (como a API Web, workers assíncronos e sincronizadores) importam apenas a assinatura de funções e structs leves da crate de banco.
2. **Simplificação do CI/CD e Modo Offline do SQLx:**
   Como a validação estática das macros `sqlx::query!` exige a variável de ambiente `DATABASE_URL` ativa ou o arquivo `.sqlx/` preparado (modo offline), centralizar as queries em uma única crate significa que você só precisa executar o comando `cargo sqlx prepare` nesta pasta, facilitando o workflow de integração contínua (CI).
3. **Gestão Única de Migrações:**
   As migrations físicas (`/migrations/core` e `/migrations/tenant`) ficam embutidas no binário desta única crate, evitando duplicações ou arquivos perdidos no projeto.

---

## 2. Desenho Arquitetural do Módulo Central (`db_access`)

Embora a persistência fique fisicamente centralizada em uma única crate do workspace, ela **deve ser organizada internamente por escopos e domínios** para evitar arquivos gigantescos e ilegíveis ("God Files").

### Estrutura de Diretórios Recomendada:

```
db_access/                  # Crate de biblioteca de dados
├── Cargo.toml              # Declara dependências de sqlx, pgvector, etc.
├── migrations/             # Migrações embutidas no binário
│   ├── core/               # Tabelas do banco default (central)
│   └── tenant/             # Tabelas do banco de cada inquilino
├── src/
│   ├── lib.rs              # Ponto de entrada, exporta sub-módulos e pools
│   ├── errors.rs           # Definição comum de erros de banco
│   ├── connection.rs       # Implementação do TenantPoolManager
│   ├── security.rs         # Sistema unificado de permissões de acesso
│   ├── core/               # Persistência do Banco Central (default)
│   │   ├── mod.rs          
│   │   ├── tenants.rs      # CRUD de inquilinos e bancos
│   │   └── plans.rs        # CRUD de planos e assinaturas
│   └── tenant/             # Persistência do Banco do Inquilino
│       ├── mod.rs
│       ├── clientes.rs     # CRUD e queries de contatos e clientes
│       ├── atendimentos.rs # CRUD e queries de atendimentos e mensagens
│       └── treinamento.rs  # Busca vetorial RAG (pgvector)
```

---

## 3. Padrão de Implementação da Crate Unificada

### 3.1 Resolvendo Conexões e Aplicando Permissões

Para realizar transações com segurança, criamos uma struct `RequestContext` que trafega informações de quem está fazendo a requisição (Tenant ID, User ID e Escopos/Permissões de Acesso).

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

### 3.2 O Repositório Modularizado de Domínio

Dentro de `db_access/src/tenant/clientes.rs`, definimos as structs de banco e as funções de persistência. A segurança e a separação são feitas via `RequestContext`:

```rust
// Localização: db_access/src/tenant/clientes.rs
use sqlx::PgPool;
use crate::errors::DbError;
use crate::security::RequestContext;
use crate::tenant::models::Contato;

pub struct ClientesPersistence;

impl ClientesPersistence {
    /// Salva ou atualiza um contato no banco do tenant correspondente
    pub async fn salvar_contato(
        pool: &PgPool,
        ctx: &RequestContext,
        contato: &Contato,
    ) -> Result<(), DbError> {
        // Validação de segurança em tempo de execução
        if !ctx.has_permission("clientes:write") {
            return Err(DbError::PermissionDenied);
        }

        // Execução da Query validada em tempo de compilação
        sqlx::query!(
            r#"
            INSERT INTO clientes_contato (id, telefone, nome, data_criacao)
            VALUES ($1, $2, $3, NOW())
            ON CONFLICT (id) DO UPDATE SET nome = EXCLUDED.nome, telefone = EXCLUDED.telefone
            "#,
            contato.id,
            contato.telefone,
            contato.nome
        )
        .execute(pool)
        .await
        .map_err(|e| DbError::SqlxError(e))?;

        Ok(())
    }
}
```

---

## 4. Como a Aplicação Consome a Crate de Banco

Os handlers do servidor Web Axum importam apenas o `RequestContext`, o `TenantPoolManager` e o módulo de persistência da crate central:

```rust
// Localização: web_api/src/handlers/contato.rs
use std::sync::Arc;
use axum::{extract::State, Extension, Json, response::IntoResponse};
use db_access::connection::TenantPoolManager;
use db_access::security::RequestContext;
use db_access::tenant::clientes::ClientesPersistence;

pub async fn post_contato_handler(
    State(pool_manager): State<Arc<TenantPoolManager>>,
    Extension(request_context): Extension<RequestContext>, // Injetado via Middleware de Auth
    Json(payload): Json<ContatoPayload>,
) -> Result<impl IntoResponse, AppError> {
    // 1. Obtém o pool do tenant a partir do manager unificado
    let tenant_pool = pool_manager.get_pool(request_context.tenant_id).await?;

    // 2. Constrói a entidade de banco
    let contato = db_access::tenant::models::Contato {
        id: payload.id,
        telefone: payload.telefone,
        nome: payload.nome,
    };

    // 3. Executa a gravação delegando ao módulo de persistência
    ClientesPersistence::salvar_contato(&tenant_pool, &request_context, &contato).await?;

    Ok(axum::http::StatusCode::CREATED)
}
```

---

## 5. Regras de Ouro para Evitar Acoplamento Nocivo

Para que essa centralização em um módulo de banco não vire um "antipattern" (monólito acoplado), siga estas diretrizes:

1. **Sem Regras de Negócio Funcionais:**
   O módulo de banco **não deve** conter lógica como "enviar mensagem no WhatsApp", "verificar regras de resposta da LLM" ou "chamar integrações externas". Ele deve apenas validar se os dados a serem salvos são compatíveis, se o usuário tem permissão e executar as transações no Postgres.
2. **Tratamento de Erros Isolado:**
   A crate deve definir seu próprio enum `DbError` (mapeando erros do SQLx, erros de decodificação e violações de chaves/restrições). Os handlers de API convertem esse `DbError` em respostas HTTP JSON de forma independente.
3. **Divisão de Arquivos:**
   Nunca escreva queries de domínios diferentes no mesmo arquivo. Mantenha a estrutura de pastas proposta (`core/` e `tenant/`) com submódulos separados por domínios.
