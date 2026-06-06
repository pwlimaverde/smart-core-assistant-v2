# Rust Decimal (rust_decimal)

- **Versão Recomendada:** 1.32.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Representação de números decimais de alta precisão para valores monetários (como taxas de planos, faturamento e registros de pagamento) mapeando diretamente ao tipo `NUMERIC` do PostgreSQL no SQLx.
- **Documentação Oficial:** [https://github.com/paupino/rust-decimal](https://github.com/paupino/rust-decimal)

---

## 1. Contexto e Uso no Projeto

Valores financeiros (como preços de planos na tabela `Plan` e registros de pagamentos na tabela `PaymentRecord`) não devem ser processados usando tipos de ponto flutuante (`f32` ou `f64`) devido a erros acumulados de arredondamento.

No PostgreSQL, estes campos são do tipo `NUMERIC(p, s)` (ex: `NUMERIC(10, 2)`). No Rust, o mapeamento do SQLx é feito utilizando a struct `Decimal` da biblioteca `rust_decimal`. Ela garante precisão exata de até 28 dígitos significativos.

Para habilitar a integração com o SQLx e a serialização do JSON (Serde), a crate deve ser instalada no `Cargo.toml` com as seguintes features ativadas:
```toml
rust_decimal = { version = "1.32", features = ["db-postgres", "serde-float"] }
```

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uso de Structs de Domínio com SQLx

Abaixo é apresentado o mapeamento de um registro de pagamento (`PaymentRecord`) contendo decimais:

```rust
use rust_decimal::Decimal;
use serde::{Serialize, Deserialize};
use sqlx::FromRow;
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct PaymentRecord {
    pub id: i32,
    pub subscription_id: i32,
    // Mapeamento correto de NUMERIC para Decimal
    pub valor: Decimal,
    pub status: String,
    pub transacao_id: Option<String>,
    pub data_pagamento: Option<DateTime<Utc>>,
}
```

### 2.2 Criando e Manipulando Decimais

Para inicializar valores decimais no código:

*   **Usando a macro `dec!` (recomendado para valores estáticos ou constantes):**
    ```rust
    use rust_decimal_macros::dec;

    let preco_base = dec!(49.90);
    let desconto = dec!(0.10); // 10%
    let preco_final = preco_base * (dec!(1.0) - desconto);
    ```
*   **A partir de strings em tempo de execução:**
    ```rust
    use std::str::FromStr;
    use rust_decimal::Decimal;

    let valor_str = "150.75";
    let valor_decimal = Decimal::from_str(valor_str).expect("String de decimal inválida");
    ```

### 2.3 Arredondamentos e Exibição

Ao persistir no banco ou retornar para APIs, certifique-se de definir a escala de arredondamento adequada (ex: 2 casas decimais para dinheiro):

```rust
use rust_decimal::{Decimal, RoundingStrategy};

let mut valor = Decimal::from_str("123.4567").unwrap();
// Arredondar para duas casas decimais
let valor_arredondado = valor.round_dp_with_strategy(2, RoundingStrategy::RoundHalfUp);
assert_eq!(valor_arredondado.to_string(), "123.46");
```

---

## 3. Histórico de Atualizações

- **2026-05-31:** Adicionado para dar suporte ao mapeamento financeiro da tabela de pagamentos e assinaturas do módulo Core (`default`).
