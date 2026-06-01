# Pgvector Rust (pgvector)

- **Versão Recomendada:** 0.3.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Suporte a tipos vetoriais no SQLx para salvar e consultar embeddings de busca semântica (RAG) diretamente no PostgreSQL.
- **Documentação Oficial:** [https://github.com/pgvector/pgvector-rust](https://github.com/pgvector/pgvector-rust)

---

## 1. Contexto e Uso no Projeto

O RAG (Retrieval-Augmented Generation) do chatbot requer a persistência de chunks de conhecimento vetorizados. No banco de dados do tenant, o campo `embedding` na tabela `oraculo_documento` e o campo `embedding` na tabela `treinamento_querycompose` são do tipo `vector(1536)` (dimensão correspondente aos embeddings da OpenAI, `text-embedding-3-small` ou similar).

A crate Rust **`pgvector`** estende o **SQLx**, fornecendo a struct `Vector` que implementa `Encode` e `Decode` nativos, permitindo enviar e ler arrays de floats (`Vec<f32>`) nas queries do SQLx de forma direta e limpa.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Inserindo Documentos com Embeddings
Ao salvar chunks de conhecimento no banco do tenant, converta o `Vec<f32>` obtido na API da OpenAI em `pgvector::Vector`:

```rust
use pgvector::Vector;
use sqlx::PgPool;

pub async fn insert_documento_chunk(
    tenant_pool: &PgPool,
    treinamento_id: i32,
    conteudo: &str,
    embedding: Vec<f32>,
    ordem: i32,
) -> Result<(), sqlx::Error> {
    // 1. Converter Vec<f32> para o tipo Vector do pgvector
    let vector_payload = Vector::from(embedding);

    // 2. Executar inserção no banco de dados isolado do tenant
    sqlx::query!(
        r#"
        INSERT INTO oraculo_documento (treinamento_id, conteudo, embedding, ordem, data_criacao) 
        VALUES ($1, $2, $3, $4, NOW())
        "#,
        treinamento_id,
        conteudo,
        vector_payload as _, // Necessário 'as _' para coercionar o tipo customizado no macro
        ordem
    )
    .execute(tenant_pool)
    .await?;

    Ok(())
}
```

### 2.2 Busca por Similaridade Vetorial (Cosine Distance)
Para realizar a busca semântica em Rust, usamos o operador de distância de cosseno `<=>` da extensão `pgvector`. A query é executada no pool de conexões do tenant e filtra apenas chunks cujos treinamentos pais foram finalizados.

```rust
pub struct SimilarChunk {
    pub id: i32,
    pub conteudo: Option<String>,
    pub distancia: f64,
}

pub async fn buscar_documentos_similares(
    tenant_pool: &PgPool,
    query_embedding: Vec<f32>,
    limit: i64,
    distance_threshold: f64,
) -> Result<Vec<SimilarChunk>, sqlx::Error> {
    let query_vector = Vector::from(query_embedding);

    // <=> calcula a distância de cosseno. 
    // Filtramos pela distância máxima aceitável (threshold)
    let records = sqlx::query!(
        r#"
        SELECT 
            d.id, 
            d.conteudo, 
            (d.embedding <=> $1) as "distancia!"
        FROM oraculo_documento d
        INNER JOIN oraculo_treinamento t ON d.treinamento_id = t.id
        WHERE t.treinamento_finalizado = true
          AND d.embedding IS NOT NULL
          AND (d.embedding <=> $1) <= $2
        ORDER BY d.embedding <=> $1
        LIMIT $3
        "#,
        query_vector as _,
        distance_threshold,
        limit
    )
    .fetch_all(tenant_pool)
    .await?;

    let chunks = records.into_iter()
        .map(|r| SimilarChunk {
            id: r.id,
            conteudo: r.conteudo,
            distancia: r.distancia,
        })
        .collect();

    Ok(chunks)
}
```

### 2.3 Cuidado com a Dimensão do Vetor
A dimensão da coluna vetorial é fixada na criação do banco de dados (ex: `embedding vector(1536)`). Se o Rust tentar enviar um vetor com tamanho diferente (ex: 768 ou 384) para a query, o PostgreSQL rejeitará a gravação retornando erro. Garanta que o payload gerado no Python (AI Engine) utilize o mesmo modelo configurado.

---

## 3. Histórico de Atualizações

- **2026-05-31:** Atualização da documentação para remover colunas e tabelas legadas redundantes (como `tenant_id` no banco do tenant) e alinhar com a nova arquitetura física separada.

