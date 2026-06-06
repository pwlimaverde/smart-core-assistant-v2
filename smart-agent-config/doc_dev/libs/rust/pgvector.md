# Pgvector Rust (pgvector)

- **Versão Recomendada:** 0.4.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-01
- **Propósito no Projeto:** Suporte ao tipo vetorial no SQLx para salvar e consultar embeddings (1536 dimensões) da busca semântica (RAG) no PostgreSQL único.
- **Documentação Oficial:** [https://github.com/pgvector/pgvector-rust](https://github.com/pgvector/pgvector-rust)
- **Library ID (Context7):** `/pgvector/pgvector`

---

## 1. Contexto e Uso no Projeto

O RAG do chatbot persiste chunks de conhecimento vetorizados. As colunas `embedding` em `oraculo_documento` e `treinamento_querycompose` são `vector(1536)` (compatível com `text-embedding-3-small`). A crate `pgvector` estende o **SQLx 0.8** com a struct `Vector` (implementa `Encode`/`Decode`), permitindo enviar/ler `Vec<f32>` diretamente.

### Operadores de distância

| Operador | Métrica | Observação |
|---|---|---|
| `<=>` | Cosseno | **Usado no projeto** (`vector_cosine_ops` no índice HNSW) |
| `<->` | L2 (euclidiana) | — |
| `<#>` | Produto interno | Retorna o negativo |

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Inserindo embeddings

```rust
use pgvector::Vector;

let vector_payload = Vector::from(embedding); // embedding: Vec<f32>
sqlx::query!(
    r#"INSERT INTO oraculo_documento (tenant_id, treinamento_id, conteudo, embedding, ordem, data_criacao)
       VALUES ($1, $2, $3, $4, $5, NOW())"#,
    tenant_id,
    treinamento_id,
    conteudo,
    vector_payload as _, // 'as _' coerciona o tipo customizado dentro da macro
    ordem
)
.execute(&mut **tx)
.await?;
```

### 2.2 Busca por similaridade (cosseno) — sempre com `tenant_id` explícito

> [!IMPORTANT]
> Mesmo com o RLS ativo, inclua `d.tenant_id = $2` explicitamente: garante o uso dos índices compostos e a performance da busca vetorial multi-tenant.

```rust
pub async fn buscar_documentos_similares(
    tx: &mut Transaction<'_, Postgres>,
    tenant_id: Uuid,
    query_embedding: Vec<f32>,
    limit: i64,
    distance_threshold: f64,
) -> Result<Vec<(i32, f64)>, sqlx::Error> {
    let query_vector = Vector::from(query_embedding);
    let records = sqlx::query!(
        r#"
        SELECT d.id, (d.embedding <=> $1) AS "distancia!"
        FROM oraculo_documento d
        INNER JOIN oraculo_treinamento t ON d.treinamento_id = t.id
        WHERE d.tenant_id = $2
          AND t.treinamento_finalizado = true
          AND d.embedding IS NOT NULL
          AND (d.embedding <=> $1) <= $3
        ORDER BY d.embedding <=> $1
        LIMIT $4
        "#,
        query_vector as _, tenant_id, distance_threshold, limit
    )
    .fetch_all(&mut **tx)
    .await?;
    Ok(records.into_iter().map(|r| (r.id, r.distancia)).collect())
}
```

### 2.3 Dimensão fixa e índice HNSW

A dimensão é fixada no schema (`vector(1536)`); enviar tamanho diferente causa erro no Postgres. Crie o índice HNSW para acelerar a busca:

```sql
CREATE INDEX oraculo_documento_embedding_hnsw
    ON oraculo_documento USING hnsw (embedding vector_cosine_ops);
```

---

## 3. Histórico de Atualizações

- **2026-06-01:** Bump 0.3.0 → 0.4.0 (compatível com SQLx 0.8; sem breaking changes na API `Vector`). Exemplos corrigidos para a arquitetura de **banco único**: filtro `tenant_id = $2` explícito na busca vetorial e uso de transação (`&mut **tx`) em vez de `PgPool` por tenant.
- **2026-05-31:** Documentação inicial da biblioteca.
