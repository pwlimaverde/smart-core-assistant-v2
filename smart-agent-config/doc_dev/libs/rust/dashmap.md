# DashMap

- **Versão Recomendada:** 5.5.3
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Cache concorrente de alto desempenho e thread-safe em memória para gerenciar múltiplos pools de conexão dos bancos de dados dos tenants de forma dinâmica.
- **Documentação Oficial:** [https://github.com/xacrimon/dashmap](https://github.com/xacrimon/dashmap)

---

## 1. Contexto e Uso no Projeto

No Smart Core Assistant v2, operamos sob uma arquitetura de múltiplos bancos de dados PostgreSQL (um para cada tenant). A criação de conexões com bancos de dados é uma operação lenta e custosa. Portanto, não podemos criar um novo pool a cada requisição.

Para resolver isso, mantemos um cache dos pools de conexão ativos (`PgPool`) em memória. Como a aplicação atende a requisições HTTP e eventos assíncronos em paralelo (usando `Tokio`), este cache precisa ser thread-safe e altamente concorrente. A crate `dashmap` fornece um `DashMap` que funciona como um `HashMap` seguro para concorrência, subdividindo internamente as travas (locks) para evitar gargalos de performance comuns em travas globais (`Mutex<HashMap>`).

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Estrutura do Gerenciador de Pools (TenantPoolManager)

Abaixo está o padrão recomendado para encapsular o `DashMap` dentro da estrutura que gerencia os pools de conexão.

```rust
use std::sync::Arc;
use dashmap::DashMap;
use sqlx::PgPool;
use uuid::Uuid;

pub struct TenantPoolManager {
    // Banco padrão (contém o mapeamento de credenciais dos inquilinos)
    core_pool: PgPool,
    // Cache de pools ativos: Tenant ID -> Pool do Postgres específico do inquilino
    tenant_pools: DashMap<Uuid, PgPool>,
}

impl TenantPoolManager {
    pub fn new(core_pool: PgPool) -> Self {
        Self {
            core_pool,
            tenant_pools: DashMap::new(),
        }
    }

    /// Obtém ou inicializa o PgPool para o tenant correspondente
    pub async fn get_or_create_pool(&self, tenant_id: Uuid) -> Result<PgPool, sqlx::Error> {
        // 1. Tentar leitura rápida no cache
        if let Some(pool) = self.tenant_pools.get(&tenant_id) {
            return Ok(pool.clone());
        }

        // 2. Resolver conexão a partir das credenciais no banco core
        let connection_string = self.resolve_connection_string(tenant_id).await?;
        
        // 3. Estabelecer o PgPool (configurando limites baixos para otimizar conexões do cluster)
        let new_pool = PgPool::connect_with(
            connection_string.parse().map_err(|e| sqlx::Error::Configuration(Box::new(e)))?
        ).await?;

        // 4. Inserir no DashMap e retornar
        // DashMap cuida da inserção concorrente segura
        self.tenant_pools.insert(tenant_id, new_pool.clone());

        Ok(new_pool)
    }

    /// Remove o pool do cache para forçar reconexão ou liberar recursos
    pub fn remove_pool(&self, tenant_id: &Uuid) -> Option<(Uuid, PgPool)> {
        self.tenant_pools.remove(tenant_id)
    }

    /// Resolve a string de conexão no banco central
    async fn resolve_connection_string(&self, tenant_id: Uuid) -> Result<String, sqlx::Error> {
        // Query de exemplo na base Core
        let db_record = sqlx::query!(
            r#"
            SELECT db_name, db_user, db_password, db_host, db_port 
            FROM tenants_tenantdatabase 
            WHERE tenant_id = $1
            "#,
            tenant_id
        )
        .fetch_one(&self.core_pool)
        .await?;

        // Decodificação da senha (AES-GCM) deve ser feita aqui
        let decrypted_password = decrypt_password(&db_record.db_password);

        let conn_str = format!(
            "postgres://{}:{}@{}:{}/{}",
            db_record.db_user,
            decrypted_password,
            db_record.db_host,
            db_record.db_port,
            db_record.db_name
        );

        Ok(conn_str)
    }
}

// Stub para simular descriptografia
fn decrypt_password(encrypted: &str) -> String {
    // Implementação real com AES-GCM
    encrypted.to_string()
}
```

### 2.2 Prevenção de Deadlocks

Embora o `DashMap` seja extremamente rápido, ele realiza o bloqueio (locking) das entradas retornadas por referências inteligentes como `Ref` ou `RefMut`. Segurar essas referências por muito tempo ou através de limites de pontos `.await` assíncronos pode causar deadlocks ou bloquear outras threads que tentam ler ou gravar no mapa.

*Regras críticas:*
1. **Nunca segure um `Ref` ou `RefMut` do DashMap através de um ponto `.await`**:
   O compilador do Rust emitirá alertas ou erros de que o tipo retornado não implementa `Send`, impedindo seu envio entre threads do Tokio. Sempre libere ou extraia a informação e deixe o `Ref` sair de escopo antes de realizar operações assíncronas.
2. **Use `.clone()` em tipos baratos**:
   O `PgPool` do SQLx é internamente envolto em um `Arc`. Cloná-lo é uma operação muito barata que incrementa apenas um contador de referência. Em vez de retornar um `Ref<'_, Uuid, PgPool>`, clone o pool e retorne `PgPool`.

*Exemplo Correto:*
```rust
// CORRETO: O Ref temporário é descartado imediatamente após clonar o pool
let pool = {
    self.tenant_pools.get(&tenant_id).map(|r| r.clone())
};
```

---

## 3. Histórico de Atualizações

- **2026-05-31:** Inclusão da biblioteca na documentação inicial do projeto para apoiar o design dinâmico de conexões multitenant.
