# Estratégia de Implementação de Banco de Dados em Rust (Crate `db_access`)

Este documento descreve a arquitetura técnica revisada e detalhada para a implementação da persistência de dados em um **banco de dados único com Row-Level Security (RLS)**, mapeamento de modelos, gerenciamento de cache de configurações em memória e busca vetorial (IA) em **Rust**.

---

## 1. Stack Tecnológica de Banco de Dados

A stack do backend Rust foi selecionada para priorizar a validação estática de queries, segurança de tipos e alta performance de concorrência com o banco unificado.

| Crate Rust | Versão | Função Principal | Justificativa Técnica |
| :--- | :--- | :--- | :--- |
| **`sqlx`** | `0.7.3` | Driver PostgreSQL Assíncrono | Validação estática de queries SQL em tempo de compilação. Sem overhead de ORM tradicional. |
| **`pgvector`** | `0.3.0` | Integração Vetorial | Suporte nativo ao tipo `vector` no PostgreSQL e compatibilidade com macros do SQLx. |
| **`dashmap`** | `5.5.3` | Cache Concorrente em Memória | Usado para manter as configurações ativas de IA de cada tenant (`TenantConfig`) em memória de forma thread-safe, evitando queries repetidas. |
| **`rust_decimal`**| `1.32.0`| Precisão Monetária | Manipulação de valores financeiros (`NUMERIC` no PostgreSQL) nas tabelas de faturamento. |
| **`chrono`** | `0.4.31`| Controle Temporal | Mapeamento nativo de campos `TIMESTAMPTZ` com fuso horário UTC consistente. |
| **`serde` / `json`**| `1.0.108`| Serialização | Processamento de campos estruturados JSONB (`metadata` do RAG e payloads de integrações). |
| **`aes-gcm`** | `0.10.3`| Criptografia | Descriptografia simétrica das chaves de API locais salvas na tabela `TenantConfig`. |

---

## 2. Arquitetura de Banco Único e Isolamento Lógico (RLS)

O sistema adota uma arquitetura de **Isolamento Lógico via Row-Level Security (RLS)** no PostgreSQL. Toda a aplicação conecta-se a um único pool global de conexões (`PgPool`) conectado ao banco de dados unificado.

### 2.1 O Fluxo de Isolamento de Transação RLS

Antes de executar qualquer leitura ou escrita que afete tabelas de negócio do tenant, a transação SQLx deve configurar o contexto do `tenant_id` atual:

```mermaid
sequenceDiagram
    participant App as Handler HTTP / Event Consumer
    participant DB as Crate db_access
    participant Pool as PgPool (Global)
    participant PG as PostgreSQL (Banco Único)

    App->>DB: Executa ação (ex: buscar_contatos, tenant_id)
    DB->>Pool: Inicia Transação (Transaction)
    Pool-->>DB: Retorna Transação local
    DB->>PG: SET LOCAL app.current_tenant = tenant_id
    Note over PG: O PostgreSQL ativa o filtro de RLS<br/>para todas as queries seguintes nesta transação
    DB->>PG: SELECT * FROM clientes_contato WHERE...
    PG-->>DB: Retorna apenas dados do tenant_id
    DB->>Pool: Commit / Rollback
    DB-->>App: Retorna resultado
```

### 2.2 Padrão de Execução de Queries com Contexto RLS no SQLx

Abaixo está o padrão recomendado para encapsular a inicialização da transação com a injeção obrigatória do contexto do tenant:

```rust
use sqlx::{PgPool, Transaction, Postgres};
use uuid::Uuid;
use crate::errors::DbError;

/// Executa um bloco de código sob transação configurada com o tenant_id para RLS
pub async fn run_in_tenant_transaction<F, T, Fut>(
    pool: &PgPool,
    tenant_id: Uuid,
    callback: F,
) -> Result<T, DbError>
where
    F: FnOnce(Transaction<'_, Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<(T, Transaction<'_, Postgres>), DbError>>,
{
    // 1. Iniciar transação no pool global
    let mut tx = pool.begin().await.map_err(DbError::SqlxError)?;

    // 2. Seta o contexto do tenant na sessão local da transação
    // O valor fica restrito a esta transação devido ao modificador LOCAL
    sqlx::query("SET LOCAL app.current_tenant = $1")
        .bind(tenant_id)
        .execute(&mut *tx)
        .await
        .map_err(DbError::SqlxError)?;

    // 3. Executar o callback que contém as queries específicas
    let (result, tx_final) = callback(tx).await?;

    // 4. Efetuar o commit final
    tx_final.commit().await.map_err(DbError::SqlxError)?;

    Ok(result)
}
```

---

## 3. Cache Concorrente de Configurações (`TenantConfigCache`)

Como as requisições HTTP e webhooks consultam constantemente os dados de persona, chaves de API locais e thresholds de IA, buscar esses parâmetros no banco a cada mensagem geraria latência excessiva. A biblioteca `db_access` mantém um cache concorrente em memória via `DashMap`:

```rust
use std::sync::Arc;
use dashmap::DashMap;
use sqlx::PgPool;
use uuid::Uuid;

pub struct TenantConfigCache {
    pool: PgPool,
    // ID do Tenant -> Struct com configurações resolvidas em memória
    cache: DashMap<Uuid, Arc<RuntimeConfig>>,
}

#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub dados_empresa: String,
    pub persona_bot: String,
    pub bot_agent_name: String,
    pub similarity_threshold: f64,
    pub vector_distance_threshold: f64,
    pub groq_api_key: String,
    pub openai_api_key: String,
}

impl TenantConfigCache {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            cache: DashMap::new(),
        }
    }

    /// Obtém as configurações do tenant. Caso não estejam no cache, busca do banco.
    pub async fn get_config(&self, tenant_id: Uuid) -> Result<Arc<RuntimeConfig>, DbError> {
        if let Some(config_ref) = self.cache.get(&tenant_id) {
            return Ok(config_ref.clone());
        }

        // Busca do banco de dados unificado
        let db_config = sqlx::query!(
            r#"
            SELECT dados_empresa, persona_bot, bot_agent_name, similarity_threshold, vector_distance_threshold, api_keys
            FROM tenants_tenantconfig
            WHERE tenant_id = $1
            "#,
            tenant_id
        )
        .fetch_one(&self.pool)
        .await
        .map_err(DbError::from)?;

        // Decodificação de chaves locais do JSONB seria realizada aqui
        let config = Arc::new(RuntimeConfig {
            dados_empresa: db_config.dados_empresa.unwrap_or_default(),
            persona_bot: db_config.persona_bot.unwrap_or_default(),
            bot_agent_name: db_config.bot_agent_name.unwrap_or_default(),
            similarity_threshold: db_config.similarity_threshold.unwrap_or(0.40).to_f64().unwrap_or(0.40),
            vector_distance_threshold: db_config.vector_distance_threshold.unwrap_or(0.25).to_f64().unwrap_or(0.25),
            groq_api_key: "".to_string(), // Extraído do JSONB e decodificado
            openai_api_key: "".to_string(),
        });

        self.cache.insert(tenant_id, config.clone());
        Ok(config)
    }

    /// Invalida o cache do tenant (acionado por webhook de alteração de configurações no painel)
    pub fn invalidate(&self, tenant_id: &Uuid) {
        self.cache.remove(tenant_id);
    }
}
```

---

## 4. Gerenciamento de Migrações e Inicialização

Diferente da arquitetura de múltiplos bancos em que precisávamos provisionar em runtime, na arquitetura de banco de dados único **todas as migrações (Core e tabelas do Tenant) são embutidas e aplicadas na inicialização da aplicação** de forma sequencial.

```rust
/// Inicializa e atualiza o banco de dados unificado aplicando as migrations
pub async fn inicializar_banco_dados(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    // Aplica as migrations do diretório unificado
    sqlx::migrate!("./migrations")
        .run(pool)
        .await?;

    Ok(())
}
```

---

## 5. Implementação de pgvector no Banco Único

Embora o RLS esteja ativo na transação, a busca de similaridade vetorial deve incluir explicitamente a cláusula `tenant_id = $1` para garantir a máxima performance usando índices vetoriais do PostgreSQL (como HNSW indexado com escopo do tenant).

### Exemplo de Busca de Similaridade Vetorial:

```rust
use pgvector::Vector;

pub async fn buscar_documentos_similares(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    query_embedding: Vec<f32>,
    limit: i64,
    distance_threshold: f64,
) -> Result<Vec<(Documento, f64)>, sqlx::Error> {
    let query_vector = Vector::from(query_embedding);

    let records = sqlx::query!(
        r#"
        SELECT 
            d.id, d.treinamento_id, d.conteudo, d.metadata, d.ordem, d.data_criacao,
            (d.embedding <=> $1) as "distancia!"
        FROM oraculo_documento d
        INNER JOIN oraculo_treinamento t ON d.treinamento_id = t.id
        WHERE d.tenant_id = $2
          AND t.treinamento_finalizado = true
          AND d.embedding IS NOT NULL
          AND (d.embedding <=> $1) <= $3
        ORDER BY d.embedding <=> $1
        LIMIT $4
        "#,
        query_vector as _,
        tenant_id,
        distance_threshold,
        limit
    )
    .fetch_all(&mut **tx)
    .await?;

    // Mapeamento para struct Documento...
    Ok(documentos)
}
```

---

## 6. Próximos Passos de Desenvolvimento

1. **Scripts de Migrações do PostgreSQL:**
   Configurar a criação e habilitação do RLS nas tabelas do tenant no arquivo de migração:
   ```sql
   ALTER TABLE oraculo_contato ENABLE ROW LEVEL SECURITY;
   CREATE POLICY contato_tenant_isolation ON oraculo_contato 
   USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
   ```
2. **Middleware do Axum de Contexto:**
   Construir o middleware responsável por capturar o `tenant_id` da requisição HTTP, instanciar o `RequestContext` correspondente e preparar a transação local do SQLx para ser injetada nos handlers da API.
