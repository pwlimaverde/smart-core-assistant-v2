# async-trait

- **Versão Recomendada:** 0.1.83
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Permite declarar métodos `async fn` em traits de repositório (`ContatoRepository`, `FaturamentoRepository`, etc.), viabilizando injeção de dependência via `Arc<dyn Repository>`.
- **Documentação Oficial:** [https://docs.rs/async-trait](https://docs.rs/async-trait)
- **Library ID (Context7):** `/dtolnay/async-trait`

---

## 1. Contexto e Uso no Projeto

O Rust estável ainda não suporta `async fn` em traits de objeto seguro (`dyn Trait`) com todos os recursos necessários (ex.: bounds `Send`). A macro `#[async_trait]` reescreve cada `async fn` para retornar `Pin<Box<dyn Future + Send>>`, permitindo que os repositórios sejam usados como trait objects injetados nos handlers.

### Features de Cargo

```toml
async-trait = "0.1.83"
```

---

## 2. Guia de Uso Rápido

```rust
use async_trait::async_trait;
use sqlx::{Postgres, Transaction};
use crate::{errors::DbError, security::RequestContext};

#[async_trait]
pub trait ContatoRepository: Send + Sync {
    async fn salvar(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        ctx: &RequestContext,
        contato: &Contato,
    ) -> Result<(), DbError>;
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
        // ... validação de escopo + query SQLx
        Ok(())
    }
}
```

- Anote **tanto** o `trait` quanto cada `impl` com `#[async_trait]`.
- O bound `Send + Sync` no trait é necessário para usar `Arc<dyn ContatoRepository>` entre tasks do Tokio.

---

## 3. Histórico de Atualizações

- **2026-06-01:** Documento criado durante a reestruturação do plano `infrastructure-postgres`.
