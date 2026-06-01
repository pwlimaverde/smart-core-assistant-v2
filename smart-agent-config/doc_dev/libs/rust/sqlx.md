# SQLx

- **Versão Recomendada:** 0.7.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Driver assíncrono para conexão, execução de consultas e gerenciamento de transações e migrações do PostgreSQL.
- **Documentação Oficial:** [https://github.com/launchbadge/sqlx](https://github.com/launchbadge/sqlx)

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 utiliza um **único banco de dados PostgreSQL** compartilhado. O isolamento de dados entre os inquilinos (Tenants) é garantido fisicamente por políticas de **Row-Level Security (RLS)** ativas em todas as tabelas de domínio.

O **SQLx** é o executor das queries assíncronas no backend Rust. A aplicação inicializa apenas um pool global de conexões (`PgPool`) na inicialização. Cada requisição de negócio do tenant abre uma transação local e configura o ID do inquilino para RLS executando a instrução SQL:
```sql
SET LOCAL app.current_tenant = 'tenant_uuid';
```

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uso Obrigatório de Transações com Contexto RLS

Em queries de escrita ou leitura de tabelas de negócio do tenant, você não deve executar comandos diretamente no `PgPool` global. É obrigatório criar uma transação (`Transaction`) e injetar o contexto de RLS:

```rust
use sqlx::{PgPool, Transaction, Postgres};
use uuid::Uuid;

pub async fn salvar_mensagem(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    conteudo: &str,
    atendimento_id: i32,
) -> Result<(), sqlx::Error> {
    // 1. Configurar contexto RLS da transação local (obrigatório se não feito pelo helper externo)
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_id)
        .execute(&mut **tx)
        .await?;

    // 2. Executar inserção (a política RLS validará a gravação)
    sqlx::query!(
        r#"
        INSERT INTO oraculo_mensagem (tenant_id, atendimento_id, conteudo, remetente, timestamp) 
        VALUES ($1, $2, $3, 'bot', NOW())
        "#
        tenant_id,
        atendimento_id,
        conteudo
    )
    .execute(&mut **tx)
    .await?;

    Ok(())
}
```

### 2.2 Uso do Macro `query!` para Verificação em Tempo de Compilação

Sempre que possível, utilize o macro `sqlx::query!` ou `sqlx::query_as!` em vez de `sqlx::query` para garantir que as queries SQL e as estruturas de mapeamento sejam validadas estaticamente contra o schema do banco durante o build (`cargo build`).

> [!NOTE]
> Para compilar o projeto em ambientes CI onde não há banco PostgreSQL ativo ou para validar queries no banco unificado de testes, configure o modo offline do SQLx rodando `cargo sqlx prepare` e enviando os metadados gerados na pasta `.sqlx/` ao controle de versão.

Exemplo com mapeamento de struct tipada a partir do banco unificado contendo o campo `tenant_id`:
```rust
#[derive(Debug, serde::Serialize)]
pub struct ContactDto {
    pub id: i32,
    pub tenant_id: Uuid,
    pub telefone: String,
    pub nome_contato: Option<String>,
}

pub async fn buscar_contato_por_telefone(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    phone: &str,
) -> Result<Option<ContactDto>, sqlx::Error> {
    let result = sqlx::query_as!(
        ContactDto,
        r#"
        SELECT id, tenant_id, telefone, nome_contato
        FROM oraculo_contato
        WHERE tenant_id = $1 AND telefone = $2
        "#,
        tenant_id,
        phone
    )
    .fetch_optional(&mut **tx)
    .await?;

    Ok(result)
}
```

### 2.3 Regras de Testes de Integração com Banco Real

Não utilize mocks para simular o banco de dados. Mocks ocultam incompatibilidades de tipos SQL e bugs nas políticas de RLS do Postgres.
* Todo teste que envolve a persistência SQL deve rodar contra uma instância real de testes do PostgreSQL (via Docker).
* Use uma transação de testes com `rollback` ao final para manter a base limpa:

```rust
#[tokio::test]
async fn test_should_deny_cross_tenant_access() {
    let pool = setup_test_db().await; // Inicia banco unificado de testes
    let mut tx = pool.begin().await.unwrap();

    let tenant_a = Uuid::new_v4();
    let tenant_b = Uuid::new_v4();

    // 1. Injeta tenant A e grava contato
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_a)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query!(
        "INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato, data_cadastro) VALUES ($1, $2, $3, NOW())",
        tenant_a,
        "5511999999999",
        "Contato A"
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    // 2. Altera o contexto RLS para o Tenant B
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_b)
        .execute(&mut *tx)
        .await
        .unwrap();

    // 3. Tenta buscar o contato sob o contexto de B
    // A query deve retornar vazia devido à política de RLS, mesmo que o registro esteja fisicamente lá
    let record = sqlx::query!(
        "SELECT nome_contato FROM oraculo_contato WHERE telefone = $1",
        "5511999999999"
    )
    .fetch_optional(&mut *tx)
    .await
    .unwrap();

    assert!(record.is_none(), "RLS falhou: Tenant B conseguiu ler contato do Tenant A!");

    tx.rollback().await.unwrap();
}
```
