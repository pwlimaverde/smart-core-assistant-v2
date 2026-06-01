# SQLx

- **Versão Recomendada:** 0.7.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Driver assíncrono para conexão, execução de consultas e gerenciamento de transações e migrações do PostgreSQL.
- **Documentação Oficial:** [https://github.com/launchbadge/sqlx](https://github.com/launchbadge/sqlx)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 adota uma arquitetura **Multitenant SaaS com Bancos de Dados Separados**. O SQLx atua nas seguintes camadas:

1. **Base Core (default):** Um banco central contendo os registros de inquilinos (`Tenant`), suas credenciais de conexão criptografadas (`TenantDatabase`), assinaturas e acessos administrativos de usuários.
2. **Bases do Tenant (específicas):** Cada inquilino ativo possui um banco de dados PostgreSQL fisicamente separado contendo tabelas de atendimentos, clientes, contatos e chunks vetorizados para a IA.

O **SQLx** é o executor das queries assíncronas no backend Rust. Para evitar latência, a aplicação utiliza a crate `dashmap` para manter um cache concorrente de pools de conexão (`PgPool`) em memória, resolvendo e instanciando conexões de forma dinâmica e sob demanda (Connection Pooling Multitenant).

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uso de Conexões Dinâmicas (TenantPoolManager)

Ao contrário de uma aplicação com banco fixo, em que injetamos o `PgPool` globalmente nos handlers, as requisições de negócio do Smart Core Assistant v2 devem resolver o pool do inquilino a partir do `TenantPoolManager`:

```rust
use axum::{extract::State, Extension, response::IntoResponse, Json};
use sqlx::PgPool;
use std::sync::Arc;
use uuid::Uuid;

// Handler de exemplo no Axum
pub async fn get_messages_handler(
    State(pool_manager): State<Arc<TenantPoolManager>>,
    Extension(tenant_id): Extension<Uuid>, // Identificado via Middleware (ex: JWT ou slug)
) -> Result<impl IntoResponse, AppError> {
    // 1. Obter ou criar o pool de conexão dinamicamente
    let tenant_pool = pool_manager.get_or_create_pool(tenant_id).await?;

    // 2. Executar queries no banco isolado do Tenant
    let mensagens = sqlx::query!(
        r#"
        SELECT id, conteudo, data_criacao 
        FROM atendimentos_mensagem 
        ORDER BY data_criacao DESC 
        LIMIT 50
        "#
    )
    .fetch_all(&tenant_pool)
    .await?;

    Ok(Json(mensagens))
}
```

### 2.2 Uso do Macro `query!` para Verificação em Tempo de Compilação

Sempre que possível, utilize o macro `sqlx::query!` ou `sqlx::query_as!` em vez de `sqlx::query` para garantir que as queries SQL e as estruturas de mapeamento sejam validadas estaticamente contra o schema do banco durante o build (`cargo build`).

> [!NOTE]
> Para compilar o projeto em ambientes CI onde não há banco PostgreSQL ativo ou para validar queries em múltiplos esquemas, configure o modo offline do SQLx rodando `cargo sqlx prepare` e enviando os metadados gerados na pasta `.sqlx/` ao controle de versão.

Exemplo com mapeamento de struct tipada a partir do banco do tenant (sem o acoplamento de `tenant_id` em cada linha):
```rust
#[derive(Debug, serde::Serialize)]
pub struct ContactDto {
    pub id: i32,
    pub telefone: String,
    pub nome: String,
}

pub async fn find_contact_by_phone(
    tenant_pool: &PgPool,
    phone: &str,
) -> Result<Option<ContactDto>, sqlx::Error> {
    let result = sqlx::query_as!(
        ContactDto,
        r#"
        SELECT id, telefone, nome
        FROM clientes_contato
        WHERE telefone = $1
        "#,
        phone
    )
    .fetch_optional(tenant_pool)
    .await?;

    Ok(result)
}
```

### 2.3 Regras de Testes de Integração com Banco Real

Não utilize mocks para simular o banco de dados. Mocks ocultam incompatibilidades de tipos SQL e bugs nas migrações.
* Todo teste que envolve a persistência SQL deve rodar contra uma instância real de testes do PostgreSQL (via Docker).
* Use bancos de teste isolados para o core e para a simulação de inquilinos.
* Abra uma transação no início do teste e execute um **`rollback`** no final para manter o banco limpo para o próximo cenário.

```rust
#[tokio::test]
async fn test_should_save_and_retrieve_contact() {
    // 1. Inicializa o pool de testes da database temporária do inquilino
    let tenant_pool = setup_test_tenant_db().await;
    let mut tx = tenant_pool.begin().await.unwrap();

    // 2. Executa a inserção sob transação
    sqlx::query!(
        "INSERT INTO clientes_contato (id, telefone, nome) VALUES ($1, $2, $3)",
        1,
        "5585999999999",
        "João da Silva"
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    // 3. Valida a leitura na mesma transação
    let contact = sqlx::query_as!(
        ContactDto,
        "SELECT id, telefone, nome FROM clientes_contato WHERE id = $1",
        1
    )
    .fetch_one(&mut *tx)
    .await
    .unwrap();

    assert_eq!(contact.nome, "João da Silva");

    // 4. Rollback limpa tudo
    tx.rollback().await.unwrap();
}
```
