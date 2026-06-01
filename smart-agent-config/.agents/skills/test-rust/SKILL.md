---
name: test-rust
description: Diretrizes e padronizações para a criação de testes unitários e de integração em Rust no projeto Smart Core Assistant v2. Foco em testes assíncronos, isolamento por transação de banco de dados e políticas de Row-Level Security (RLS).
---

# Diretrizes de Testes em Rust

Este guia define o padrão técnico e arquitetural para a implementação de testes na stack Rust do projeto, garantindo consistência, determinismo e alta cobertura sem corromper o banco de dados de desenvolvimento ou violar o isolamento de inquilinos (tenants).

## 1. Estrutura dos Testes

1. **Testes Unitários (Puros/Lógicos)**:
   - Devem ser escritos inline no próprio arquivo sob teste.
   - Encapsulados em um submódulo privado `mod tests` anotado com `#[cfg(test)]`.
   - Testam a lógica de funções puras, manipulação de erros lógica, criptografia e utilitários sem I/O persistente.

2. **Testes de Integração (Banco de Dados / RLS)**:
   - Localizados no diretório `tests/` na raiz da crate correspondente.
   - **Estrutura Espelhada**: Devem seguir rigorosamente a mesma hierarquia de pastas de `src/` (ex: `tests/tenants/mod.rs`, `tests/clientes/mod.rs`, etc.) para manter a organização de domínios.
   - **Ponto de Entrada Único**: Para otimizar o tempo de compilação do Rust, deve-se criar um único arquivo target de testes na raiz de `tests/` (ex: `tests/integration_tests.rs`) que expõe cada subpasta como submódulo (`mod tenants;`, `mod clientes;`).
   - Testem a persistência real, repositórios SQLx, migrations e o isolamento de Row-Level Security (RLS).
   - Devem utilizar um banco PostgreSQL real (acessível via túnel ou ambiente local).

---

## 2. Isolamento de Banco de Dados via Transações (Regra de Ouro)

Para testes que envolvem escrita ou leitura no PostgreSQL, **cada teste deve executar dentro de uma transação exclusiva que sofre Rollback ao final**. Isso assegura que:
- O banco de dados não seja poluído com dados de teste.
- Testes concorrentes não interfiram entre si.
- O estado de início de cada teste seja determinístico.

### Padrão de Teste com Banco e Rollback:

```rust
#[tokio::test]
async fn test_salvar_contato_com_sucesso() {
    // 1. Arrange: Obtém pool global e inicia transação
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.expect("Falha ao iniciar transação");

    // Configura o tenant no RLS
    let tenant_id = uuid::Uuid::new_v4();
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    let repo = PostgresContatoRepository;
    let ctx = criar_contexto_teste(tenant_id);

    // 2. Act: Executa o código sob teste (passando a referência mutável desreferenciada)
    let resultado = repo.criar(&mut tx, &ctx, "5511999999999", "Contato Teste").await;

    // 3. Assert: Valida resultados
    assert!(resultado.is_ok());
    let contato = resultado.unwrap();
    assert_eq!(contato.nome, "Contato Teste");

    // 4. Teardown: Força o rollback da transação (descartando alterações)
    tx.rollback().await.expect("Falha ao reverter transação");
}
```

---

## 3. Testando Isolamento Cross-Tenant (RLS)

O isolamento é o requisito de segurança mais crítico da infraestrutura de banco de dados. Os testes de persistência devem verificar explicitamente que as políticas de RLS estão funcionando.

### Padrão de Teste para RLS:

```rust
#[tokio::test]
async fn test_rls_impedir_acesso_cross_tenant() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    let tenant_a = uuid::Uuid::new_v4();
    let tenant_b = uuid::Uuid::new_v4();

    // 1. Criar registro sob o escopo do Tenant A
    configurar_tenant_transacao(&mut tx, tenant_a).await;
    let contato_a = criar_contato_teste(&mut tx, tenant_a, "5511988888888").await;

    // 2. Tentar ler o registro alterando o contexto para Tenant B
    configurar_tenant_transacao(&mut tx, tenant_b).await;
    
    let repo = PostgresContatoRepository;
    let ctx_b = criar_contexto_teste(tenant_b);
    let resultado = repo.buscar_por_id(&mut tx, &ctx_b, contato_a.id).await;

    // 3. Assert: O Tenant B não deve encontrar o registro do Tenant A
    assert!(resultado.is_ok());
    assert!(resultado.unwrap().is_none(), "Tenant B acessou dados do Tenant A!");

    tx.rollback().await.unwrap();
}
```

---

## 4. Diretrizes de Qualidade dos Testes

- **Idioma**: Os nomes de funções de teste devem ser escritos em **Inglês** (ex: `test_save_contact_success`, `test_rls_isolation_enforced`), mas os comentários explicativos dentro do código devem ser escritos em **Português**.
- **Independência**: Um teste não deve depender do resultado de outro teste.
- **Fail-Closed**: Sempre teste o comportamento de falha ou negação de acesso (ex: consultar tabelas RLS com tenant não configurado deve retornar zero registros).
- **Sem Logs em Caso de Sucesso**: Evite usar `println!` em testes bem-sucedidos; em vez disso, use `tracing` se necessário para debugar falhas.
- **Mocking**: Restrinja mocks às dependências que dependem de rede externa (como requisições HTTP a serviços de IA). Não crie mocks para o banco de dados; utilize o PostgreSQL real sob transações com rollback.
