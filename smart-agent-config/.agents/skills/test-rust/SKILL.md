---
name: test-rust
description: Guia profissional para escrever testes em Rust (unitários, integração, doctests, parametrizados, property-based, snapshot e assíncronos com Tokio) seguindo as melhores práticas da comunidade. Cobre organização física dos arquivos, padrão AAA, retorno Result com `?`, tratamento de panics, isolamento e paralelismo, testes de banco com transação+rollback/`#[sqlx::test]`, mocking de fronteiras externas, fixtures e ferramentas (cargo-nextest, cobertura). Aplica-se a qualquer crate/serviço da stack Rust do Smart Core Assistant v2.
---

# Diretrizes de Testes em Rust

Guia técnico e arquitetural para escrever testes na stack Rust do projeto, garantindo
consistência, determinismo, isolamento e alta cobertura. As regras valem para qualquer
crate de biblioteca (`crates/`) ou serviço executável (`apps/`) do **Cargo Workspace**.

> Princípio-mestre: **um teste bom é determinístico, independente, rápido e legível.**
> Se você precisa rodar duas vezes para "ver se passa", o teste está errado, não o código.

---

## 1. Taxonomia dos Testes

O Rust suporta nativamente vários tipos de teste. Escolha o tipo certo para cada caso.

| Tipo | Onde mora | Acessa código privado? | Quando usar |
| --- | --- | --- | --- |
| **Unitário** | inline no `src/`, em `mod tests` com `#[cfg(test)]` | **Sim** | Lógica pura, algoritmos, conversões, validações, branches de erro |
| **Integração** | pasta `tests/` vizinha ao `Cargo.toml` | Não — só a API `pub` | Fluxos reais ponta a ponta, banco, cache, rede, contratos públicos |
| **Doctest** | dentro de comentários `///` no código | Só a API `pub` | Garantir que os exemplos da documentação compilam e funcionam |
| **Parametrizado** | qualquer um dos acima (via `rstest`) | conforme o local | Mesma lógica contra uma tabela de casos (table-driven) |
| **Property-based** | qualquer um dos acima (via `proptest`) | conforme o local | Invariantes que devem valer para um universo grande de entradas |
| **Snapshot** | qualquer um dos acima (via `insta`) | conforme o local | Saídas grandes/complexas difíceis de comparar campo a campo |
| **Benchmark** | `benches/` (via `criterion`) | Só API `pub` | Medir performance — **não** é teste de correção |

Em projetos de produção esses tipos **coexistem**: unitários para lógica, integração para
contratos, property para casos de borda, snapshot para saídas complexas.

---

## 2. Estrutura e Organização Física

### 2.1. Testes Unitários (lógica interna / privada)

- **Localização**: inline no próprio arquivo sob teste (ex.: `src/auth/login.rs`), sob um
  submódulo `mod tests` anotado com `#[cfg(test)]`.
- **Por que inline?**: testes fora de `src/` são módulos externos e só enxergam itens `pub`.
  Para testar funções, structs e campos privados, o teste precisa estar fisicamente dentro
  do módulo de produção.
- **Importe o módulo pai** com `use super::*;` para acessar os itens locais.
- `#[cfg(test)]` garante que o módulo de teste **só compila em `cargo test`** — zero custo
  no binário de release.

```rust
// src/parsing/telefone.rs

/// Normaliza um telefone para o formato E.164 sem o '+'.
pub fn normalizar(bruto: &str) -> Option<String> {
    let digitos: String = bruto.chars().filter(|c| c.is_ascii_digit()).collect();
    (digitos.len() >= 10).then_some(digitos)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_phone_stripping_symbols() {
        // Arrange / Act
        let resultado = normalizar("+55 (11) 99999-8888");
        // Assert
        assert_eq!(resultado.as_deref(), Some("5511999998888"));
    }

    #[test]
    fn returns_none_for_short_input() {
        assert_eq!(normalizar("123"), None);
    }
}
```

### 2.2. Testes de Integração (fluxos reais / banco / rede)

- **Localização**: pasta `tests/` no **mesmo nível do `src/`** de cada crate (vizinha ao
  seu `Cargo.toml`). Em um workspace, **cada crate tem o seu `tests/`** — testes de
  integração não são centralizados.
- **Estrutura espelhada**: os arquivos em `tests/` seguem a hierarquia de domínios do
  `src/` (ex.: `tests/tenants/mod.rs`, `tests/clientes/mod.rs`).
- **Ponto de entrada único**: o Cargo compila **cada arquivo `.rs` na raiz de `tests/` como
  uma crate de teste separada**. Para acelerar a compilação e compartilhar helpers, crie um
  único arquivo agregador (ex.: `tests/integration_tests.rs`) que declara os demais módulos:

  ```rust
  // tests/integration_tests.rs — único ponto de entrada
  mod common;      // helpers compartilhados (não vira binário próprio aqui)
  mod tenants;
  mod clientes;
  ```

- **Helpers compartilhados**: coloque utilitários em `tests/common/mod.rs`. Usar
  `common/mod.rs` (e não `common.rs`) faz o Cargo **não** tratá-lo como uma suíte de teste
  independente, evitando o aviso "0 tests run".

### 2.3. Nomenclatura

- **Arquivos de integração**: por padronização do projeto, use o sufixo `_tests.rs`
  (ex.: `login_tests.rs`, `bus_tests.rs`). O Cargo aceita qualquer `.rs`, mas a consistência
  ajuda a localizar.
- **Funções de teste**: nomes em **Inglês**, descritivos e orientados a comportamento. Os
  **comentários explicativos dentro do teste** ficam em **Português**.
  - ❌ Vago: `fn test_login()`, `fn it_works()`
  - ✅ Comportamental: `fn rejects_login_with_expired_token()`,
    `fn save_contact_is_idempotent_on_conflict()`
  - Convenção útil: `metodo_condicao_resultadoEsperado`
    (ex.: `parse_invalid_input_returns_error`).
  - Se houver um ticket/bug associado, inclua o id (ex.: `regression_bug_512_*`).

---

## 3. Anatomia de um Teste — Padrão AAA

Estruture todo teste em três blocos explícitos (também chamado *Given/When/Then*):

1. **Arrange** — prepara o estado: cria objetos, fixtures, contexto, conexões.
2. **Act** — executa **uma** ação: a função/método sob teste.
3. **Assert** — verifica o resultado esperado.

Mantenha **um Act por teste**. Se você precisa de vários "Act", provavelmente são vários
testes. Separe os blocos visualmente (linha em branco ou comentário `// Arrange`).

```rust
#[test]
fn discount_applies_only_above_threshold() {
    // Arrange
    let carrinho = Carrinho::com_total(150.0);

    // Act
    let total = carrinho.aplicar_cupom(Cupom::acima_de(100.0, 0.10));

    // Assert
    assert_eq!(total, 135.0);
}
```

---

## 4. Asserções e Resultados

### 4.1. Macros de asserção

- `assert!(cond)` — condição booleana.
- `assert_eq!(a, b)` / `assert_ne!(a, b)` — preferíveis a `assert!(a == b)` porque
  **imprimem os dois valores** ao falhar.
- **Mensagem de contexto** quando o motivo não for óbvio:
  `assert!(saldo >= 0.0, "saldo ficou negativo: {saldo}");`
- Para structs grandes ou saídas complexas, prefira **snapshot** (`insta`) a dezenas de
  `assert_eq!` (ver §9.3).

### 4.2. Retornar `Result<(), E>` e usar `?` (recomendado)

Testes podem retornar `Result<(), E>`, o que permite usar o operador `?` e elimina cascatas
de `.unwrap()`/`.expect()`. O teste **passa se retornar `Ok(())`** e falha em qualquer `Err`.

```rust
#[tokio::test]
async fn loads_user_from_repository() -> anyhow::Result<()> {
    let repo = repo_em_memoria();
    let usuario = repo.buscar(42).await?;       // `?` propaga erro como falha do teste
    assert_eq!(usuario.nome, "Ana");
    Ok(())
}
```

- Use `?` para o **encanamento** (setup que não deveria falhar) e `assert*!` para a
  **verificação** que é o objeto do teste.
- ⚠️ **Não dá para combinar** `#[should_panic]` com retorno `Result`. Para checar erro
  esperado num teste que retorna `Result`, **não** use `?` no valor sob teste — use
  `assert!(valor.is_err())` ou faça pattern match no erro.

### 4.3. Testando erros e panics

- **Caminho de erro normal** (a função devolve `Result::Err`): verifique o `Err`
  explicitamente — é o caminho preferido, pois não derruba a thread.

  ```rust
  #[test]
  fn parse_rejects_empty_string() {
      let err = parse("").unwrap_err();
      assert!(matches!(err, ParseError::Empty));   // valida a *variante*, não só "deu erro"
  }
  ```

- **Panics genuínos** (invariantes/`assert!` internos): use `#[should_panic]` **sempre com
  `expected`** para não capturar um panic pelo motivo errado.

  ```rust
  #[test]
  #[should_panic(expected = "índice fora dos limites")]
  fn indexing_out_of_bounds_panics() {
      let v = vec![1, 2, 3];
      let _ = acessar(&v, 99);
  }
  ```

- Prefira validar **a variante/mensagem** do erro, não apenas "que houve um erro". Um teste
  que só checa `is_err()` passa mesmo quando o código falha pelo motivo errado.

### 4.4. `#[ignore]`

Marque com `#[ignore = "motivo"]` testes caros/manuais que não devem rodar no `cargo test`
padrão. Rode-os sob demanda com `cargo test -- --ignored`.

---

## 5. Testes Assíncronos (Tokio)

- Anote funções `async` com `#[tokio::test]` (não com `#[test]`). Por padrão isso cria um
  runtime **current-thread** por teste — isolado e barato.
- **Flavor multi-thread** quando o teste exercita concorrência real (ex.: `tokio::spawn` em
  múltiplas tasks que precisam progredir em paralelo):

  ```rust
  #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
  async fn processes_two_streams_concurrently() { /* ... */ }
  ```

- **Sempre coloque timeout** em operações que podem pendurar (I/O, rede, locks). Um teste
  que trava degrada a suíte inteira. Na expiração, afirme o `Err` e registre contexto:

  ```rust
  use tokio::time::{timeout, Duration};

  #[tokio::test]
  async fn request_times_out_when_server_silent() {
      let resultado = timeout(Duration::from_secs(2), cliente.chamar()).await;
      assert!(resultado.is_err(), "a chamada deveria estourar o timeout");
  }
  ```

- Evite `tokio::time::sleep` real para "esperar" estado. Prefira `tokio::time::pause()` +
  `advance()` (relógio virtual) ou sincronização explícita (canais, `Notify`).

---

## 6. Isolamento e Paralelismo

- O Cargo roda os testes **em paralelo, em múltiplas threads, dentro de cada binário**.
  Cada arquivo na raiz de `tests/` é um **processo separado**.
- **Independência absoluta**: nenhum teste pode depender da ordem de execução nem do
  resultado de outro. Não compartilhe estado mutável global entre testes.
- **Recursos compartilhados** (mesmo arquivo, mesma porta, mesma tabela sem isolamento)
  causam corrida. Soluções, em ordem de preferência:
  1. **Isolar o recurso por teste** (transação com rollback, banco/tabela/diretório únicos
     por teste, porta efêmera `:0`). — *Preferível: preserva o paralelismo.*
  2. **Serializar** com o crate `serial_test` (`#[serial]`) quando o recurso é
     genuinamente único e não isolável.
  3. Último recurso: `cargo test -- --test-threads=1` (perde paralelismo da suíte toda).
- Inicialização única e idempotente (ex.: subir um túnel, instalar um subscriber de
  `tracing`) deve usar `std::sync::Once` / `OnceLock` para rodar uma vez por processo.

---

## 7. Testes com Banco de Dados (PostgreSQL / SQLx)

Banco é a fonte clássica de testes lentos e instáveis. Duas estratégias, ambas válidas:

### 7.1. Transação por teste com Rollback (regra de ouro)

Cada teste roda dentro de **uma transação exclusiva que sofre `rollback()` ao final**. Isso
garante: banco não poluído, isolamento entre testes concorrentes e estado inicial
determinístico. Como a transação nunca dá commit, **o rollback é automático** mesmo que o
teste entre em panic antes do `rollback()` explícito.

```rust
#[tokio::test]
async fn saves_contact_successfully() {
    // Arrange — pool global + transação isolada
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.expect("falha ao iniciar transação");

    let repo = PostgresContatoRepository;
    let ctx  = criar_contexto_teste(/* ... */);

    // Act — passa a referência mutável desreferenciada (`&mut *tx`)
    let resultado = repo.criar(&mut tx, &ctx, "5511999999999", "Contato Teste").await;

    // Assert
    let contato = resultado.expect("criar contato deveria suceder");
    assert_eq!(contato.nome, "Contato Teste");

    // Teardown — descarta tudo (idempotente; o drop também faria rollback)
    tx.rollback().await.expect("falha ao reverter transação");
}
```

### 7.2. `#[sqlx::test]` — banco/transação gerenciados pela macro

A macro `#[sqlx::test]` substitui `#[tokio::test]`, **injeta um `PgPool`** e, conforme a
configuração, cria um banco isolado por teste e/ou envolve tudo numa transação revertida ao
final. Suporta **fixtures** (scripts SQL compostos, parecidos com migrations, mas só para
semear dados de teste). Use quando quiser delegar o ciclo de vida do banco à própria SQLx.

```rust
#[sqlx::test(fixtures("tenants", "contatos"))]
async fn lists_contacts_for_tenant(pool: sqlx::PgPool) -> sqlx::Result<()> {
    let contatos = listar_contatos(&pool, tenant_id).await?;
    assert_eq!(contatos.len(), 2);
    Ok(())
}
```

### 7.3. Regras para testes de banco

- **Não faça mock do banco.** Use o PostgreSQL real sob transação/rollback. Mock de banco
  testa o seu mock, não o seu SQL.
- **Fail-closed / segurança**: teste explicitamente a **negação de acesso** — ex.: consultar
  uma tabela com RLS sem tenant configurado deve retornar **zero** registros; um tenant não
  deve enxergar dados de outro (isolamento cross-tenant).
- Centralize setup repetitivo (pool, contexto, criação de tenant, configuração de RLS) em
  helpers no módulo `common`, mantendo os testes enxutos e focados no comportamento.

```rust
#[tokio::test]
async fn rls_blocks_cross_tenant_read() {
    let pool = obter_pool_teste().await;
    let mut tx = pool.begin().await.unwrap();

    // Cria registro sob o Tenant A
    let tenant_a = configurar_tenant(&mut tx, novo_tenant()).await;
    let contato_a = criar_contato(&mut tx, &tenant_a, "5511988888888").await;

    // Troca o contexto para o Tenant B e tenta ler
    let tenant_b = configurar_tenant(&mut tx, novo_tenant()).await;
    let achado = repo.buscar_por_id(&mut tx, &ctx(tenant_b), contato_a.id).await.unwrap();

    // Assert — o RLS deve esconder o registro do Tenant A
    assert!(achado.is_none(), "Tenant B acessou dados do Tenant A!");

    tx.rollback().await.unwrap();
}
```

---

## 8. Mocking — só nas fronteiras externas

- **Faça mock apenas de dependências de rede/serviços externos** (HTTP para um serviço de
  IA, gateway de pagamento, etc.). **Não** faça mock de banco, cache ou da sua própria
  lógica de domínio.
- Em Rust, mock é feito sobre **traits**. O crate `mockall` gera mocks automaticamente a
  partir de um trait, permitindo definir retornos e expectativas de chamada.

```rust
#[cfg_attr(test, mockall::automock)]
#[async_trait::async_trait]
pub trait ClienteIa {
    async fn classificar(&self, texto: &str) -> Result<Intencao, IaError>;
}

#[tokio::test]
async fn routes_message_based_on_intent() {
    let mut ia = MockClienteIa::new();
    ia.expect_classificar()
        .withf(|t| t.contains("fatura"))
        .times(1)
        .returning(|_| Ok(Intencao::Financeiro));

    let roteador = Roteador::new(ia);
    assert_eq!(roteador.rotear("quero a fatura").await.unwrap(), Fila::Financeiro);
}
```

- Para HTTP, considere um servidor de mock (ex.: `wiremock`) em vez de mockar o cliente,
  mantendo o teste mais próximo do comportamento real do protocolo.

---

## 9. Casos Avançados — escolha a ferramenta certa

### 9.1. Parametrizado / table-driven (`rstest`)

Evita duplicação rodando a **mesma lógica** contra uma tabela de casos. Também oferece
*fixtures* injetáveis por argumento.

```rust
use rstest::rstest;

#[rstest]
#[case("5511999998888", true)]
#[case("123", false)]
#[case("", false)]
fn validates_phone(#[case] entrada: &str, #[case] esperado: bool) {
    assert_eq!(telefone_valido(entrada), esperado);
}
```

### 9.2. Property-based (`proptest`)

Em vez de exemplos pontuais, declare **invariantes** e deixe o framework gerar centenas de
entradas (com *shrinking* automático do contraexemplo mínimo). Ótimo complemento aos testes
por exemplo: exemplos documentam, properties caçam bordas inesperadas.

```rust
proptest::proptest! {
    #[test]
    fn encode_decode_roundtrips(s in ".*") {
        let codificado = codificar(&s);
        proptest::prop_assert_eq!(decodificar(&codificado).unwrap(), s);
    }
}
```

### 9.3. Snapshot (`insta`)

Captura a saída e compara com um snapshot salvo; ao mudar, o teste falha e você revisa o
diff (`cargo insta review`). Ideal para structs grandes, JSON, ASTs e saídas de
renderização — onde dezenas de `assert_eq!` seriam frágeis e ilegíveis.

```rust
#[test]
fn renders_invoice_summary() {
    let resumo = gerar_resumo(&fatura_exemplo());
    insta::assert_yaml_snapshot!(resumo);
}
```

### Matriz de decisão rápida

- **Espaço de entrada** → poucos exemplos: `#[test]`; muitos casos similares: `rstest`;
  universo/invariantes: `proptest`.
- **Tipo de saída** → valor simples: `assert_eq!`; estrutura grande/complexa: `insta`.
- **Dependência externa de rede** → `mockall`/`wiremock`. Banco → transação real + rollback.
- **Documentação executável** → doctest (`///` com bloco ```` ```rust ````).

---

## 10. Diretrizes de Qualidade

- **Idioma**: nomes de teste em **Inglês**; comentários explicativos em **Português**.
- **Determinismo**: nada de `Instant::now`, `rand` sem semente, ordem de `HashMap` ou sleeps
  arbitrários influenciando o resultado. Injete relógio/aleatoriedade quando precisar
  controlá-los.
- **Independência**: um teste não depende de outro nem de ordem de execução.
- **Foco**: um conceito por teste; um `Act` por teste. Nome diz exatamente o que validam.
- **Fail-closed**: sempre teste o caminho de falha/negação, não só o caminho feliz.
- **Sem ruído**: evite `println!` em testes que passam; use `tracing` (com subscriber de
  teste) apenas para depurar falhas.
- **Sem testes "flaky"**: um teste intermitente é um bug — conserte a causa (corrida,
  timeout curto, dependência de tempo), não o re-execute até passar.
- **Rápido**: testes lentos não são rodados. Isole o caro com `#[ignore]` ou mova para uma
  suíte dedicada.

---

## 11. Ferramentas e Execução

- **Rodar tudo**: `cargo test` (workspace: `cargo test --workspace`).
- **Filtrar**: `cargo test nome_parcial`; só ignorados: `cargo test -- --ignored`.
- **Ver saída de testes que passam**: `cargo test -- --nocapture`.
- **`cargo-nextest`** (recomendado): executor de testes mais rápido e com melhor saída
  (`cargo nextest run`). Cada teste roda em seu processo, o que reforça o isolamento.
- **Doctests**: rodam com `cargo test --doc` (não são executados pelo nextest).
- **Cobertura**: `cargo llvm-cov` (preciso, baseado em LLVM) ou `cargo tarpaulin`. Use como
  bússola, **não** como meta cega — 100% de cobertura com asserções fracas não vale nada.
- **Lints em teste**: rode `cargo clippy --all-targets` para cobrir também o código de teste.

---

## 12. Como Executar Testes Neste Projeto (Smart Core Assistant v2)

O projeto opera com **três ambientes distintos** para testes:

| Ambiente | Onde roda | Suite | Gatilho |
|----------|-----------|-------|---------|
| **Local** | máquina do dev (Windows) | completa: unit + integração | manual, pré-push |
| **CI (dev/prod)** | GitHub Actions ubuntu-latest | somente `--lib --bins` | push/PR automático |
| **Hostinger (dev/prod)** | VPS remota | deploy automático pós-CI verde | CI verde em `dev`/`main` |

### 12.1. Workflow ao escrever um novo teste

A regra prática depende do **tipo** de teste que você escreveu:

#### Teste **unitário** (inline em `src/`, sem banco/cache/rede) → roda isolado via `cargo`

Rode diretamente, filtrando pelo nome ou pela crate — é o caminho de feedback rápido:

```powershell
# a partir de server/
cargo test nome_parcial_do_teste
cargo test -p data_postgres login            # filtrar por crate
cargo test nome_parcial_do_teste -- --nocapture   # ver saída
```

Como não tocam em recursos externos, unitários não precisam de túnel nem de `.env`.

#### Teste **de integração** (pasta `tests/`, depende de Postgres/Redis) → roda **a partir do script**

**Não** rode testes de integração chamando `cargo test` direto. As conexões (túnel SSH
para os bancos da Hostinger, variáveis de ambiente, ordem dos gates) são orquestradas pelo
script `infra/test-local.ps1` — é ele que prepara o ambiente para a integração funcionar:

```powershell
# da raiz do repo ou da pasta infra/
.\infra\test-local.ps1                  # esteira completa: fmt → clippy → cargo test --workspace → sqlx prepare --check
.\infra\test-local.ps1 -ResetTunnel     # idem, derrubando túneis SSH antigos antes (após mudança de portas)
```

O script roda a **suíte completa** (`cargo test --workspace`, unit + integração) com os
gates na mesma ordem do CI. É essa a forma correta de validar testes de integração e o que
você **deve** rodar antes de qualquer push.

#### Modo rápido / sem banco

Quando você só quer revalidar lint + unitários (ou não tem o túnel disponível):

```powershell
.\infra\test-local.ps1 -Fast            # fmt → clippy → cargo test --workspace --lib --bins (sem banco)
```

> `-Fast` é idêntico ao que o CI roda. **Não substitui** a esteira completa: sempre rode o
> modo completo (sem flags) antes do push para exercitar a integração.

### 12.2. Topologia do túnel SSH (local → Hostinger)

Quando você roda o script, o `test_support::ensure_tunnel()` (acionado pela primeira suíte
que precisa do banco) abre o túnel sozinho; `-ResetTunnel` mata processos `ssh` residuais
quando os mapeamentos de porta ficam obsoletos.

| Porta local | Serviço | Porta remota (host) | Política Redis |
|-------------|---------|---------------------|----------------|
| `5434` | PostgreSQL | `POSTGRES_PORT` | — |
| `6379` | Redis **cache** | `REDIS_PORT` | allkeys-lru |
| `6380` | Redis **bus** | `REDIS_BUS_PORT` | noeviction |

### 12.3. Pré-requisitos para testes de integração locais

- `infra/.env.deploy` — credenciais SSH (chave `id_hostinger_root`) para abrir o túnel.
- `server/.env` — variáveis `DATABASE_URL`, `DATABASE_ADMIN_URL`, `REDIS_URL`,
  `REDIS_BUS_URL` apontando para as portas locais do túnel (`5434`/`6379`/`6380`).

### 12.4. O que o CI faz (e o que ele **não** faz)

O CI (`ci.yml`) roda a mesma sequência de gates — `cargo fmt`, `cargo clippy`,
`cargo test`, `cargo sqlx prepare --check` — mas com Postgres e Redis **efêmeros** do
runner e **somente `--lib --bins`** (sem testes de integração da pasta `tests/`). A suíte
completa de integração **é responsabilidade do dev rodar localmente** antes do push.

Ao subir serviços nas mesmas portas (`5434`, `6380`) que o `test_support` monitora, o CI
faz o código "achar" o banco sem abrir túnel — o mecanismo é o mesmo, apenas a infra muda.

---

## Referências (boas práticas consultadas)

- [The Rust Book — Test Organization](https://doc.rust-lang.org/book/ch11-03-test-organization.html)
- [The Rust Book — How to Write Tests](https://doc.rust-lang.org/book/ch11-01-writing-tests.html)
- [Rust By Example — Unit Testing](https://doc.rust-lang.org/rust-by-example/testing/unit_testing.html)
- [`sqlx::test` — documentação oficial](https://docs.rs/sqlx/latest/sqlx/attr.test.html)
- [rstest](https://rstest.rs/) · [proptest](https://proptest-rs.github.io/proptest/) · [insta](https://insta.rs/) · [mockall](https://docs.rs/mockall/)
- [cargo-nextest](https://nexte.st/) · [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov)
