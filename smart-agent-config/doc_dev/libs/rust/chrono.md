# Chrono

- **Versão Recomendada:** 0.4.31
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Manipulação robusta de datas, horas e fusos horários no backend, mapeando diretamente o tipo `TIMESTAMPTZ` do PostgreSQL no SQLx.
- **Documentação Oficial:** [https://github.com/chronotope/chrono](https://github.com/chronotope/chrono)

---

## 1. Contexto e Uso no Projeto

No Smart Core Assistant v2, todas as tabelas registram momentos no tempo (como `data_criacao`, `data_atualizacao`, `data_pagamento`, data de envio de mensagens e agendamentos). Para garantir consistência global e evitar problemas com fusos horários de servidores, **todos os registros de data e hora do banco PostgreSQL usam o tipo `TIMESTAMPTZ` (timestamp with time zone)**.

No Rust, mapeamos esses campos para `chrono::DateTime<chrono::Utc>`. Para habilitar o mapeamento no SQLx e o suporte ao Serde, configure a crate no `Cargo.toml` com:
```toml
chrono = { version = "0.4", features = ["serde"] }
```

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uso de DateTime no Mapeamento de Entidades

Ao construir modelos com campos de data/hora:

```rust
use chrono::{DateTime, Utc};
use serde::{Serialize, Deserialize};
use sqlx::FromRow;

#[derive(Debug, FromRow, Serialize, Deserialize)]
pub struct Contato {
    pub id: i32,
    pub nome: String,
    pub telefone: String,
    // TIMESTAMPTZ no banco mapeado como DateTime<Utc> no Rust
    pub data_criacao: DateTime<Utc>,
    pub data_atualizacao: DateTime<Utc>,
}
```

### 2.2 Criação e Operações de Tempo

*   **Obter a hora atual em UTC:**
    ```rust
    use chrono::Utc;
    let agora = Utc::now();
    ```
*   **Criar um timestamp específico:**
    ```rust
    use chrono::{TimeZone, Utc};
    let data_especifica = Utc.with_ymd_and_hms(2026, 6, 1, 12, 0, 0).unwrap();
    ```
*   **Adicionar ou subtrair períodos de tempo:**
    Use `chrono::Duration`:
    ```rust
    use chrono::{Utc, Duration};
    let expira_em = Utc::now() + Duration::days(30);
    ```

### 2.3 Formatação e Serialização

*   **Formatando como String (ISO 8601 / RFC 3339):**
    ```rust
    use chrono::Utc;
    let agora = Utc::now();
    let iso_str = agora.to_rfc3339(); // ex: "2026-06-01T15:30:00Z"
    ```
*   **Parsing a partir de String:**
    ```rust
    use chrono::{DateTime, Utc};
    let data_parsed = DateTime::parse_from_rfc3339("2026-06-01T15:30:00Z")
        .unwrap()
        .with_timezone(&Utc);
    ```

---

## 3. Histórico de Atualizações

- **2026-05-31:** Adicionado para padronizar o manuseio de datas/tempo em todos os módulos do sistema.
