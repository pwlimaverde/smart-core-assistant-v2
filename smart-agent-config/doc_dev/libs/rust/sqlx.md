# SQLx

- **Versão Recomendada:** 0.9.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-10
- **Propósito no Projeto:** Driver assíncrono para conexão, execução de consultas validadas em tempo de compilação, transações e migrações do PostgreSQL único (com RLS).
- **Documentação Oficial:** [https://github.com/launchbadge/sqlx](https://github.com/launchbadge/sqlx)
- **Library ID (Context7):** `/websites/rs_sqlx`

---

## 1. Contexto e Uso no Projeto

O Smart Core Assistant v2 utiliza um **único banco de dados PostgreSQL** compartilhado. O isolamento de dados entre os inquilinos (Tenants) é garantido por políticas de **Row-Level Security (RLS)** ativas em todas as tabelas de domínio do tenant.

O **SQLx** é o executor das queries assíncronas no backend Rust (crate `infrastructure_postgres`). A aplicação inicializa apenas um pool global de conexões (`PgPool`). Cada operação de negócio do tenant abre uma transação local e configura o ID do inquilino para RLS.

### Features de Cargo utilizadas

```toml
sqlx = { version = "0.8.2", default-features = false, features = [
    "postgres", "runtime-tokio-rustls", "macros", "migrate",
    "uuid", "chrono", "rust_decimal", "json"
] }
```

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Injeção do contexto RLS: use `set_config`, NÃO `SET LOCAL ... = $1`

> [!IMPORTANT]
> O comando `SET` do PostgreSQL **não aceita parâmetros vinculados** (placeholders `$1`) pelo protocolo estendido (prepared statements) que o SQLx usa. O padrão `sqlx::query("SET LOCAL app.current_tenant = $1").bind(...)` **falha em runtime**.
> Use a função `set_config('app.current_tenant', $1, true)` via `SELECT`. O terceiro argumento `true` (`is_local`) restringe o valor à transação atual — equivalente a `SET LOCAL`.

```rust
use sqlx::{PgPool, Transaction, Postgres};
use uuid::Uuid;

/// Inicia uma transação e injeta o tenant_id para ativar o RLS da sessão local.
pub async fn abrir_tx_tenant<'a>(
    pool: &'a PgPool,
    tenant_id: Uuid,
) -> Result<Transaction<'a, Postgres>, sqlx::Error> {
    let mut tx = pool.begin().await?;

    // set_config aceita bind; SET LOCAL = $1 NÃO aceita.
    // Convertemos o UUID para text porque set_config recebe text.
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;

    Ok(tx)
}
```

### 2.2 Macros `query!` / `query_as!` com verificação em tempo de compilação

Sempre que possível, prefira `sqlx::query!`, `sqlx::query_as!` e `sqlx::query_scalar!` para validar SQL e mapeamento contra o schema durante o build. Inclua sempre `WHERE tenant_id = $1` explícito (dupla barreira com o RLS e uso de índices compostos).

```rust
#[derive(Debug, serde::Serialize, sqlx::FromRow)]
pub struct ContatoRow {
    pub id: i32,
    pub tenant_id: Uuid,
    pub telefone: String,
    pub nome_contato: Option<String>,
}

pub async fn buscar_contato_por_telefone(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    telefone: &str,
) -> Result<Option<ContatoRow>, sqlx::Error> {
    sqlx::query_as!(
        ContatoRow,
        r#"
        SELECT id, tenant_id, telefone, nome_contato
        FROM oraculo_contato
        WHERE tenant_id = $1 AND telefone = $2
        "#,
        tenant_id,
        telefone
    )
    .fetch_optional(&mut **tx) // dentro de transação: &mut **tx
    .await
}
```

### 2.3 Modo Offline (`.sqlx/`) para CI

As macros exigem `DATABASE_URL` ativa OU o cache offline preparado. Gere o cache e versione-o:

```bash
# Com o túnel SSH aberto e DATABASE_URL apontando para o Postgres real:
cargo sqlx prepare        # gera o diretório .sqlx/ (commitar no git)

# No CI (sem banco):
SQLX_OFFLINE=true cargo build
```

### 2.4 Testes de integração com banco real

Não mocke o banco — mocks ocultam erros de tipo SQL e falhas de RLS. Rode contra o Postgres real (via túnel) e use `rollback` ao final. O teste-chave valida o isolamento: gravar sob `tenant_a`, trocar o `set_config` para `tenant_b` e confirmar que a leitura retorna vazio.

```rust
#[tokio::test]
async fn rls_bloqueia_acesso_cross_tenant() {
    let pool = setup_test_db().await;
    let mut tx = pool.begin().await.unwrap();
    let (tenant_a, tenant_b) = (Uuid::new_v4(), Uuid::new_v4());

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_a.to_string()).execute(&mut *tx).await.unwrap();
    sqlx::query!(
        "INSERT INTO oraculo_contato (tenant_id, telefone, nome_contato, data_cadastro, ultima_interacao)
         VALUES ($1, $2, $3, NOW(), NOW())",
        tenant_a, "5511999999999", "Contato A"
    ).execute(&mut *tx).await.unwrap();

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_b.to_string()).execute(&mut *tx).await.unwrap();
    let row = sqlx::query!(
        "SELECT nome_contato FROM oraculo_contato WHERE telefone = $1", "5511999999999"
    ).fetch_optional(&mut *tx).await.unwrap();

    assert!(row.is_none(), "RLS falhou: Tenant B leu dado do Tenant A!");
    tx.rollback().await.unwrap();
}
```

---

## 3. Pool de Conexões — Configuração e Introspecção

### 3.1 PgPoolOptions: Assinaturas de Configuração

`PgPoolOptions` é um alias para `PoolOptions<Postgres>` que permite configurar o comportamento do pool de conexões. Todos os métodos de timeout recebem `Duration` (ou `impl Into<Option<Duration>>` para timeouts opcionais).

**Métodos principais (versão 0.9):**

```rust
// Criação
pub fn new() -> PoolOptions<Postgres>

// Máximo/mínimo de conexões (recebem u32)
pub fn max_connections(self, max: u32) -> PoolOptions<Postgres>
pub fn get_max_connections(&self) -> u32

pub fn min_connections(self, min: u32) -> PoolOptions<Postgres>
pub fn get_min_connections(&self) -> u32

// Timeouts (recebem Duration ou impl Into<Option<Duration>>)
pub fn acquire_timeout(self, timeout: Duration) -> PoolOptions<Postgres>
pub fn get_acquire_timeout(&self) -> Duration

pub fn idle_timeout(self, timeout: impl Into<Option<Duration>>) -> PoolOptions<Postgres>
pub fn max_lifetime(self, lifetime: impl Into<Option<Duration>>) -> PoolOptions<Postgres>

// Connect para criar o pool
pub async fn connect(self, url: &str) -> Result<PgPool, Error>

// Logging de aquisição lenta (opcional)
pub fn acquire_slow_threshold(self, threshold: Duration) -> PoolOptions<Postgres>
pub fn get_acquire_slow_threshold(&self) -> Duration
```

**Exemplo de configuração com timeout:**

```rust
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

let pool = PgPoolOptions::new()
    .max_connections(20)
    .min_connections(5)
    .acquire_timeout(Duration::from_secs(30))
    .idle_timeout(Duration::from_secs(600))      // 10 min
    .max_lifetime(Duration::from_secs(3600))     // 1 hora
    .connect("postgresql://user:pass@localhost/db")
    .await?;
```

### 3.2 Pool<Postgres> / PgPool: Introspecção em Runtime

Métodos para consultar estado atual do pool:

```rust
// Retorna u32: número total de conexões ATIVAS (incluindo idle)
pub fn size(&self) -> u32

// Retorna usize: número de conexões IDLE (disponíveis para uso)
pub fn num_idle(&self) -> usize
```

**Uso em observabilidade:**

```rust
let total = pool.size();           // u32
let idle = pool.num_idle();        // usize
let in_use = total as usize - idle;

tracing::info!(
    "pool_state size={} idle={} in_use={}",
    total, idle, in_use
);
```

### 3.3 Transaction::begin() — Ponto de Aquisição

O método `pool.begin()` (equivalente a `pool.acquire()` implicitamente) é onde a espera por `acquire_timeout` ocorre:

```rust
pub async fn begin(&self) -> Result<Transaction<'_, Postgres>, Error>
```

Se não houver conexões livres, o pool aguarda até `acquire_timeout`. Se o tempo expirar, retorna erro `PoolError::AcquireTimeout`.

### 3.4 Mudanças de 0.8 → 0.9

Nenhuma breaking change nos métodos de pool utilizados neste projeto. Versão 0.9 é totalmente compatível com 0.8 para configuração e introspecção de pool.

---

## 4. Histórico de Atualizações

- **2026-06-10:** Adicionada seção "## Pool de Conexões — Configuração e Introspecção" com assinaturas exatas de `PgPoolOptions` (versão 0.9), métodos de introspecção `size()` e `num_idle()`, tipos de retorno, e exemplo de configuração de timeouts. Coletada documentação via Context7 library ID `/websites/rs_sqlx`. Nenhuma breaking change detectada de 0.8 → 0.9.
- **2026-06-01 (b):** Bump 0.8.2 → **0.9.0**. Necessário para unificar a versão de `sqlx` no grafo: `pgvector 0.4.2` exige `sqlx >= 0.8, < 0.10` e o Cargo resolvia `pgvector` para `sqlx 0.9.0`, gerando duas versões de `sqlx-core` no mesmo build. Validado contra o banco real (migrations + `cargo sqlx prepare --workspace --all-targets` + suíte de integração). APIs utilizadas (macros, `PgPool`, `Transaction`, `migrate`, `set_config`) permanecem compatíveis.
- **2026-06-01 (a):** Bump 0.7.3 → 0.8.2 (alinhamento com a `estrategia_implementacao_rust.md` do projeto). **Correção de padrão:** substituído o anti-padrão `SET LOCAL app.current_tenant = $1` (que falha por `SET` não aceitar bind) por `SELECT set_config('app.current_tenant', $1, true)`.
- **2026-05-31:** Documentação inicial da biblioteca.
