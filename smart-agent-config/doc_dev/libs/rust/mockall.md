# mockall

- **Versão Recomendada:** 0.13.x
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-21
- **Propósito no Projeto:** Framework de mocking automático para testes unitários Rust; gera `MockXxx` a partir de traits via `#[automock]` ou `#[cfg_attr(test, mockall::automock)]`.
- **Documentação Oficial:** https://docs.rs/mockall
- **Library ID (Context7):** /websites/rs_mockall_0_13_1_mockall

---

## 1. Contexto e Uso no Projeto

A biblioteca `mockall` é a solução primária de mocking para testes unitários no projeto Rust. Seu principal objetivo é **gerar automaticamente structs mock** a partir de definições de traits, eliminando a necessidade de escrever implementações manual de mocks.

### Quando usar:
- Testes unitários que precisam isolar componentes via trait mocking
- Mockar métodos síncronos e assíncronos
- Validar chamadas de método (contagem, argumentos, sequência)
- Trabalhar com trait objects (`&dyn Trait`)
- Integrar com `async-trait` para métodos assíncronos

---

## 2. Padrões de Implementação

### 2.1 Sintaxe Básica com `#[automock]`

O atributo `#[automock]` é o mais comum. Coloca-se **antes da definição do trait** e gera uma struct `MockXxx` automaticamente:

```rust
use mockall::automock;
use mockall::predicate::*;

#[automock]
trait MyTrait {
    fn foo(&self, x: u32) -> u32;
}

#[test]
fn test_trait() {
    let mut mock = MockMyTrait::new();
    
    // Configura expectativa
    mock.expect_foo()
        .with(eq(4))
        .times(1)
        .returning(|x| x + 1);
    
    assert_eq!(5, mock.foo(4));
}
```

**Comportamento:**
- `MockMyTrait::new()` — cria nova instância do mock
- `expect_foo()` — configura expectativa para o método `foo`
- `.with(predicate)` — define matcher para argumentos
- `.times(n)` — especifica número exato de chamadas esperadas (panics se não atender)
- `.returning(closure)` — define closure que retorna valor quando chamado

### 2.2 Sintaxe com `#[cfg_attr(test, mockall::automock)]`

Aplicar mocking **apenas em compilações de teste**:

```rust
#[cfg_attr(test, mockall::automock)]
trait MyTrait {
    fn bar(&self) -> String;
}
```

Isso reduz sobrecarga de compilação em builds de produção.

### 2.3 APIs Principais

#### MockXxx::new()
```rust
let mut mock = MockMyTrait::new();
```
Cria instância nova com zero expectativas configuradas.

#### expect_nome_metodo()
```rust
mock.expect_foo()
    .with(predicate::eq(5))
    .returning(|x| x * 2)
```
Retorna um builder para configurar expectativa do método específico.

#### Métodos de Contagem

| API | Comportamento |
|-----|--------------|
| `.times(1)` | Exatamente 1 chamada (default) |
| `.times(2)` | Exatamente 2 chamadas |
| `.times(0..=5)` | Entre 0 e 5 chamadas (range) |
| `.once()` | Alias para `.times(1)` |
| `.never()` | Exatamente 0 chamadas |
| `.checkpoint()` | Valida expectativas no ponto e limpa delas |

#### Métodos de Retorno

| API | Uso |
|-----|-----|
| `.returning(\|args\| value)` | Closure mutable que retorna valor a cada chamada |
| `.return_const(value)` | Valor constante retornado em cada chamada (clona) |
| `.return_once(fn)` | Closure que executa uma única vez (consome) |

#### Matchers de Argumento

```rust
use mockall::predicate::*;

mock.expect_foo()
    .with(eq(4))                    // igualdade
    .returning(|x| x + 1);

mock.expect_bar()
    .withf(|x, y| x == y)           // função customizada
    .return_const(());

mock.expect_baz()
    .with(always())                 // aceita qualquer coisa
    .returning(|_| 42);
```

Predicados comuns: `eq()`, `ne()`, `gt()`, `lt()`, `always()`, custom `withf(|args| bool)`.

---

## 3. Integração com async-trait

Para mockar traits com métodos assíncronos (`async fn`), deve-se usar `#[automock]` **antes** de `#[async_trait]`:

```rust
use async_trait::async_trait;
use mockall::automock;

#[automock]
#[async_trait]
pub trait AsyncService {
    async fn fetch_data(&self, id: u32) -> String;
}

#[tokio::test]
async fn test_async_mock() {
    let mut mock = MockAsyncService::new();
    
    mock.expect_fetch_data()
        .with(mockall::predicate::eq(42))
        .returning(|_| Box::pin(async { "data".to_string() }));
    
    let result = mock.fetch_data(42).await;
    assert_eq!(result, "data");
}
```

**Ordem é crítica:** `#[automock]` vem **antes** de `#[async_trait]`.

### 3.1 Trait Objects (`&dyn Trait`)

Mockall suporta automaticamente trait objects. Métodos que retornam `&dyn Display` geram expectativas com `Box<dyn Display>`:

```rust
#[automock]
trait Foo {
    fn name(&self) -> &dyn std::fmt::Display;
}

let mut mock = MockFoo::new();
mock.expect_name()
    .return_const(Box::new("test"));

assert_eq!("test", format!("{}", mock.name()));
```

### 3.2 impl Trait Return Types

Métodos retornando `impl Trait` são internamente transformados para `Box<dyn Trait>`:

```rust
#[automock]
trait Processor {
    fn process(&self) -> impl std::fmt::Debug;
}

let mut mock = MockProcessor::new();
mock.expect_process()
    .returning(|| Box::new(String::from("result")));
```

---

## 4. Limitações e Gotchas

### 4.1 Limitações Conhecidas na Versão 0.13

1. **Genéricos em Traits:** Mockall gera mocks para **cada combinação de tipo genérico** usado em testes. Pode gerar código verboso para traits altamente genéricos.

2. **Lifetime Parameters:** Lifetimes em métodos podem gerar comportamentos inesperados; preferir evitar lifetimes em traits a mockar.

3. **Self Types:** Métodos que retornam `Self` ou `impl Trait` requerem tratamento especial via `Box<dyn Trait>`.

4. **Métodos Privados:** Mockall não pode mockar métodos privados (limitação intencional de design).

5. **Macros em Traits:** Traits com macros invocation nos métodos podem não ser suportados.

### 4.2 Gotchas Comuns

**Panic em Checkpoint:** Chamar `.checkpoint()` panics se alguma expectativa não atendeu sua contagem:

```rust
let mut mock = MockFoo::new();
mock.expect_foo().times(2);

mock.foo();  // Chamou 1 vez, esperava 2

mock.checkpoint();  // PANICS aqui!
```

**Expectativas Cumulativas:** Chamar `expect_foo()` múltiplas vezes **adiciona** expectativas, não substitui:

```rust
mock.expect_foo().returning(|| 1);
mock.expect_foo().returning(|| 2);  // Cria DUAS expectativas, não sobrescreve
```

**Ordem de Múltiplas Expectativas:** Sem `Sequence`, múltiplas expectativas podem ser chamadas em qualquer ordem.

**Type Bounds no Mock:** Se o trait requer `Clone`, `Send`, `Sync`, o mock herda esses bounds. Closures em `.returning()` precisam ser `Send + 'static` por padrão (usar `_st` variants para single-threaded tests).

### 4.3 Breaking Changes: 0.12 → 0.13

A versão 0.13 é estável e compatível com a 0.12 em sua maioria. Não houve breaking changes documentadas significativas; a API permaneceu consistente.

### 4.4 Integração com `#[tokio::test]`

Funciona naturalmente com `#[tokio::test]`:

```rust
#[tokio::test]
async fn test_async_behavior() {
    let mut mock = MockAsyncService::new();
    mock.expect_fetch()
        .returning(|| Box::pin(async { Ok(42) }));
    
    let result = mock.fetch().await;
    assert!(result.is_ok());
}
```

---

## 5. Exemplo Completo: Teste com Validação

```rust
use mockall::automock;
use mockall::Sequence;

#[automock]
trait Database {
    fn get(&self, key: &str) -> Option<String>;
    fn set(&self, key: &str, value: String);
}

#[test]
fn test_database_sequence() {
    let mut mock = MockDatabase::new();
    let mut seq = Sequence::new();
    
    mock.expect_set()
        .withf(|k, _| k == "name")
        .return_const(())
        .times(1)
        .in_sequence(&mut seq);
    
    mock.expect_get()
        .withf(|k| k == "name")
        .return_const(Some("Alice".to_string()))
        .times(1)
        .in_sequence(&mut seq);
    
    // Deve chamar set ANTES de get, caso contrário panics
    mock.set("name", "Alice".into());
    assert_eq!(mock.get("name"), Some("Alice".to_string()));
    
    mock.checkpoint();  // Valida que ambas chamadas ocorreram
}
```

---

## Referências Rápidas

| Tarefa | Padrão |
|--------|--------|
| Mockar trait simples | `#[automock] trait Foo { fn bar(&self); }` |
| Mockar método async | `#[automock] #[async_trait] trait Foo { async fn bar(&self); }` |
| Teste de contagem | `.times(n)` ou `.once()` ou `.never()` |
| Matcher customizado | `.withf(\|args\| bool)` |
| Retorno assíncrono | `.returning(\|args\| Box::pin(async { ... }))` |
| Validar mid-test | `.checkpoint()` (panics se expectativas não atendidas) |
| Sequência obrigatória | `Sequence::new()` + `.in_sequence(&mut seq)` |
| Somente testes | `#[cfg_attr(test, mockall::automock)]` |
