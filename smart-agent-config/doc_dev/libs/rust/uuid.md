# uuid

- **Versão Recomendada:** 1.10.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Tipo `Uuid` usado como chave primária dos Tenants e em todo o `tenant_id` que trafega pela camada de persistência e pelo RLS.
- **Documentação Oficial:** [https://docs.rs/uuid](https://docs.rs/uuid)
- **Library ID (Context7):** `/uuid-rs/uuid`

---

## 1. Contexto e Uso no Projeto

`tenant_id` é `UUID` em todas as tabelas de negócio. O backend gera UUIDs v4 para novos tenants, faz parse de UUIDs vindos das Claims do JWT e os vincula nas queries SQLx. A integração com o SQLx é feita pela feature `uuid` do próprio SQLx (mapeia coluna `UUID` ↔ `uuid::Uuid`).

### Features de Cargo

```toml
uuid = { version = "1.10.0", features = ["v4", "serde"] }
```

---

## 2. Guia de Uso Rápido

```rust
use uuid::Uuid;

// Gerar UUID v4 (novo tenant)
let tenant_id = Uuid::new_v4();

// Parse seguro a partir das Claims do JWT (string -> Uuid)
let tenant_id = Uuid::parse_str(&claims.tenant_id)
    .map_err(|_| StatusCode::UNAUTHORIZED)?;

// Conversão para text (necessária para set_config do RLS, que recebe text)
sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
    .bind(tenant_id.to_string())
    .execute(&mut *tx)
    .await?;
```

- `Uuid::new_v4()` — gera identificador aleatório (requer feature `v4`).
- `Uuid::parse_str(&str)` — parse com validação; retorna `Result`.
- Feature `serde` — permite `#[derive(Serialize, Deserialize)]` em structs com `Uuid` (DTOs, `RuntimeConfig`).

---

## 3. Histórico de Atualizações

- **2026-06-01:** Documento criado durante a reestruturação do plano `infrastructure-postgres`. Versão alinhada à série 1.x estável.
