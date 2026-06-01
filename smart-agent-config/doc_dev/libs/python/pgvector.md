# Pgvector Python (pgvector)

- **Versão Recomendada:** 0.2.5
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Suporte e integração de tipos vetoriais no driver do PostgreSQL em Python para leitura e gravação de embeddings no RAG.
- **Documentação Oficial:** [https://github.com/pgvector/pgvector-python](https://github.com/pgvector/pgvector-python)

---

## 1. Contexto e Uso no Projeto

No `ai-engine` (Python), a geração de embeddings (representação numérica de palavras/textos de 1536 floats) é realizada após a entrada de novos documentos de treinamento de um tenant. 

O pacote **`pgvector`** em Python estende o driver psycopg3/asyncpg, permitindo ler e gravar vetores em listas float nativas do Python nas consultas do banco de dados PostgreSQL.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Integração com Psycopg3 (Async)
Ao inicializar a conexão assíncrona com o PostgreSQL, registre a extensão do `pgvector` na conexão para que os adaptadores convertam arrays NumPy ou listas de floats automaticamente para o tipo SQL `vector`.

```python
import psycopg
from pgvector.psycopg import register_vector
import numpy as np

async fn save_embedding_to_db(
    conn_str: str, 
    tenant_id: str, 
    content: str, 
    embedding: list[float]
) -> None:
    # 1. Abre a conexão assíncrona
    async with await psycopg.AsyncConnection.connect(conn_str) as conn:
        # 2. Registrar o adaptador de vetor na conexão ativa
        await register_vector(conn)
        
        # Convertemos a lista float em array NumPy (formato preferido do pgvector-python)
        embedding_array = np.array(embedding)
        
        # 3. Executar inserção
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO training_document (id, tenant_id, content, embedding) "
                "VALUES (gen_random_uuid(), %s, %s, %s)",
                (tenant_id, content, embedding_array),
            )
```

### 2.2 Busca Semântica de Documentos no Python
Embora o `worker` Rust possa fazer a busca vetorial diretamente com SQLx, o `ai-engine` pode precisar realizar a busca vetorial internamente em seus algoritmos de RAG.

```python
async fn fetch_similar_docs(
    conn_str: str, 
    tenant_id: str, 
    query_embedding: list[float], 
    limit: int = 3
) -> list[dict]:
    
    async with await psycopg.AsyncConnection.connect(conn_str) as conn:
        await register_vector(conn)
        
        embedding_array = np.array(query_embedding)
        
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT content, embedding <=> %s as distance "
                "FROM training_document "
                "WHERE tenant_id = %s "
                "ORDER BY embedding <=> %s LIMIT %s",
                (embedding_array, tenant_id, embedding_array, limit),
            )
            
            rows = await cur.fetchall()
            return [
                {"content": r[0], "distance": float(r[1])} 
                for r in rows
            ]
```

### 2.3 Tratamento Seguro de Arrays e NaN
Evite enviar arrays contendo valores `None`, `NaN` ou floats infinitos para o banco de dados. Filtre a saída da LLM/gerador de embeddings antes de converter para array NumPy, garantindo que o array de float esteja limpo para evitar erros de validação SQL.
