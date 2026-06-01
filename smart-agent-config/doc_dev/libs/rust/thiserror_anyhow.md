# Thiserror e Anyhow

- **Versões Recomendadas:** `thiserror` (1.0.61), `anyhow` (1.0.86)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Gerenciamento estruturado de erros e modelagem de falhas.
- **Documentação Oficial:** [https://docs.rs/thiserror](https://docs.rs/thiserror) | [https://docs.rs/anyhow](https://docs.rs/anyhow)

---

## 1. Contexto e Divisão de Papéis

Para manter o código previsível e manutenível, o tratamento de erros é segregado de acordo com a camada arquitetural:

1.  **`thiserror` nas Crates de Domínio e Infraestrutura (`crates/`):**
    *   Utilizado para modelar erros previsíveis de domínio e negócios (ex: cota esgotada, ticket não encontrado).
    *   Erros são modelados via Enums fortemente tipados que implementam o trait `std::error::Error` de forma declarativa.
2.  **`anyhow` nos Binários Executáveis (`apps/`) e Camada `application`:**
    *   Utilizado para agrupar erros diversos de I/O, rede, e banco de dados que ocorrem na orquestração dos casos de uso, onde o tratamento detalhado do tipo de erro não altera o fluxo (apenas loga e retorna um erro genérico HTTP 500).
    *   Fornece facilidades para adicionar contexto (`.context()`) e capturar backtraces.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Modelagem de Erros com `thiserror`
Toda crate sob `crates/domain_*` deve expor um tipo de erro baseado em Enum.

```rust
use thiserror::Error;

#[derive(Error, Debug, PartialEq, Eq)]
pub enum TicketError {
    #[error("Inquilino está sem saldo de mensagens disponível.")]
    QuotaExhausted,

    #[error("Ticket {ticket_id} não foi encontrado para o tenant {tenant_id}.")]
    NotFound {
        ticket_id: uuid::Uuid,
        tenant_id: uuid::Uuid,
    },

    #[error("Não é possível mover um ticket da etapa {from} para {to}.")]
    InvalidTransition {
        from: String,
        to: String,
    },
}
```

### 2.2 Propagação e Enriquecimento de Contexto com `anyhow`
Nas funções orquestradoras e handlers da API, use `anyhow::Result<T>` para propagar erros e enriquecer o contexto de depuração.

```rust
use anyhow::{Context, Result};
use uuid::Uuid;

async fn process_ticket_assignment(ticket_id: Uuid, agent_id: Uuid) -> Result<()> {
    // Busca o ticket
    let ticket = db::fetch_ticket(ticket_id)
        .await
        .context("Falha ao recuperar o ticket no banco de dados")?; // anyhow anexa a mensagem ao erro original

    // Aplica regra de negócio que retorna TicketError (thiserror)
    ticket.assign_to(agent_id)
        .context("Falha de validação nas regras de atribuição de ticket")?;

    Ok(())
}
```

### 2.3 Conversão Implícita de Erros
O operador `?` realiza automaticamente a conversão de erros específicos definidos com `thiserror` para a struct genérica do `anyhow::Error`, facilitando a codificação na camada de aplicação.

```rust
// A função retorna anyhow::Result, mas a chamada interna retorna Result<_, TicketError>
fn run_use_case() -> anyhow::Result<()> {
    let mut domain_entity = DomainEntity::new();
    
    // O operador ? converte implicitamente TicketError em anyhow::Error
    domain_entity.execute_rule()?; 
    
    Ok(())
}
```

### 2.4 Proibição Absoluta de Pânicos (`unwrap`/`expect`)
*   Nunca utilize `.unwrap()` ou `.expect()` em código que roda no servidor. 
*   Pânicos derrubam a thread do runtime e podem indisponibilizar a API para outros inquilinos.
*   Retorne sempre um `Result` e propague os erros adequadamente.
