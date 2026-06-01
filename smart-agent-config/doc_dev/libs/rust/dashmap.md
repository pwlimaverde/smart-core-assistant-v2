# DashMap

- **Versão Recomendada:** 6.1.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Cache concorrente, thread-safe e de baixa latência em memória para as configurações resolvidas de cada tenant (`TenantConfigCache`), evitando consultas repetidas ao PostgreSQL a cada mensagem.
- **Documentação Oficial:** [https://github.com/xacrimon/dashmap](https://github.com/xacrimon/dashmap)
- **Library ID (Context7):** `/xacrimon/dashmap`

---

## 1. Contexto e Uso no Projeto

> [!IMPORTANT]
> **Correção arquitetural (2026-06-01):** a arquitetura do projeto passou a ser **banco de dados único com RLS** — **não** há mais múltiplos `PgPool` por tenant. Portanto o DashMap **não** guarda pools de conexão; ele guarda o `RuntimeConfig` resolvido de cada tenant.

No Smart Core Assistant v2, requisições HTTP e webhooks consultam constantemente persona, chaves de API locais e thresholds de IA de cada tenant. Buscar isso no banco a cada mensagem geraria latência excessiva. A crate `infrastructure_postgres` mantém um cache concorrente em memória via `DashMap<Uuid, Arc<RuntimeConfig>>`. O `DashMap` subdivide internamente as travas por shard, evitando o gargalo de um `Mutex<HashMap>` global.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Estrutura do `TenantConfigCache`

```rust
use std::sync::Arc;
use dashmap::DashMap;
use sqlx::PgPool;
use uuid::Uuid;

pub struct TenantConfigCache {
    pool: PgPool,
    cache: DashMap<Uuid, Arc<RuntimeConfig>>,
}

impl TenantConfigCache {
    pub fn new(pool: PgPool) -> Self {
        Self { pool, cache: DashMap::new() }
    }

    /// Leitura rápida no cache; em miss, resolve do banco e popula.
    pub async fn get_config(&self, tenant_id: Uuid) -> Result<Arc<RuntimeConfig>, DbError> {
        if let Some(entry) = self.cache.get(&tenant_id) {
            return Ok(entry.clone()); // Arc::clone é O(1); o Ref é descartado já aqui
        }
        let config = Arc::new(self.resolve_from_db(tenant_id).await?);
        self.cache.insert(tenant_id, config.clone());
        Ok(config)
    }

    /// Invalida a entrada local (chamado pela ponte Redis ao receber Pub/Sub).
    pub fn invalidate(&self, tenant_id: &Uuid) {
        self.cache.remove(tenant_id);
    }
}
```

### 2.2 Prevenção de Deadlocks (regras críticas)

O `DashMap` retorna guardas inteligentes (`Ref`/`RefMut`) que mantêm a trava do shard. Segurá-los através de um `.await` causa erro de compilação (`Ref` não é `Send`) ou deadlock.

1. **Nunca segure um `Ref`/`RefMut` através de um ponto `.await`.** Extraia/clone o valor e deixe o guard sair de escopo antes de qualquer I/O assíncrono.
2. **Clone tipos baratos.** `Arc<RuntimeConfig>` e `PgPool` são `Arc` internamente — clonar incrementa apenas o contador de referência.

```rust
// CORRETO: o Ref temporário é descartado imediatamente após o clone
let config = { self.cache.get(&tenant_id).map(|r| r.clone()) };
// ... agora pode fazer .await com segurança
```

---

## 3. Histórico de Atualizações

- **2026-06-01:** Bump 5.5.3 → 6.1.0 (alinhamento com a `estrategia_implementacao_rust.md`). A major 6 é **backward-compatible** com 5.x nas APIs usadas (`new`/`insert`/`get`/`remove`); apenas otimizações internas de sharding. **Correção arquitetural:** removido o padrão obsoleto `TenantPoolManager` com `DashMap<Uuid, PgPool>` e a tabela `tenants_tenantdatabase` (eram da arquitetura antiga de múltiplos bancos). O uso canônico agora é `DashMap<Uuid, Arc<RuntimeConfig>>` no `TenantConfigCache`.
- **2026-05-31:** Documentação inicial da biblioteca.
