# LangChain Google Generative AI

- **Versão Recomendada:** 0.1.0+
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-17
- **Propósito no Projeto:** Fallback de provedor LLM/embeddings no ia_engine (fase N6.4) para acesso a modelos Gemini (Google Generative AI) e Gemma. Fornece ChatGoogleGenerativeAI para chat e GoogleGenerativeAIEmbeddings para geração de vetores (compatível com pgvector via output_dimensionality).
- **Documentação Oficial:** [https://github.com/langchain-ai/langchain-google](https://github.com/langchain-ai/langchain-google)
- **Context7 Library ID:** `/langchain-ai/langchain-google`

---

## Histórico de Atualizações

- **2026-07-17** — Documentação inicial criada via Context7. Foco em ChatGoogleGenerativeAI, GoogleGenerativeAIEmbeddings, suporte a structured output com pydantic v2, compatibilidade de dimensões de embedding (1536 para pgvector) e init_chat_model.

---

## 1. Instalação e Configuração

### Instalação

```bash
uv add langchain-google-genai
```

**Dependências Recomendadas:**
- `langchain-core>=0.1.0`
- `pydantic>=2.0` (obrigatório para structured output)
- `google-generativeai>=0.5.0` (cliente underlayer da Gemini API)

### Autenticação

A biblioteca carrega automaticamente da variável de ambiente `GOOGLE_API_KEY`:

```python
from langchain_google_genai import ChatGoogleGenerativeAI

# A partir de GOOGLE_API_KEY (ou GEMINI_API_KEY como fallback)
llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")

# Ou injetar explicitamente (recomendado para multi-tenant)
llm = ChatGoogleGenerativeAI(
    model="gemini-3.5-flash",
    google_api_key=tenant_config.api_key,
    temperature=0.2,
)
```

**Suporte Vertex AI (Google Cloud):**
A biblioteca também oferece autenticação via Vertex AI com Application Default Credentials (ADC):

```python
llm = ChatGoogleGenerativeAI(
    model="gemini-3.5-flash",
    vertexai=True,                    # Usar Vertex AI backend
    project="seu-projeto-gcp",        # Project ID do Google Cloud
)
```

---

## 2. Assinatura Atual de ChatGoogleGenerativeAI

### Parâmetros Principais

```python
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatGoogleGenerativeAI(
    # Obrigatório
    model: str,                              # Identificador do modelo (ex: "gemini-3.5-flash", "gemini-3.1-pro-preview")
    
    # Autenticação
    google_api_key: str | None = None,      # Se não fornecido, usa GOOGLE_API_KEY ou GEMINI_API_KEY
    api_key: str | None = None,             # Alias para google_api_key
    
    # Vertex AI (alternativa à API key)
    vertexai: bool | None = None,           # Ativar Vertex AI backend
    project: str | None = None,             # Google Cloud Project ID (Vertex AI)
    credentials: Any = None,                # Credenciais customizadas (Vertex AI)
    
    # Comportamento
    temperature: float = 0.7,                # Criatividade (0.0 a 2.0)
    max_tokens: int | None = None,          # Limite de tokens na resposta
    top_p: float | None = None,             # Nucleus sampling
    top_k: int | None = None,               # Top-k sampling
    
    # Parâmetros de streaming
    streaming: bool = False,                # Ativar streaming de tokens
)
```

### Exemplo Básico

```python
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatGoogleGenerativeAI(
    model="gemini-3.5-flash",
    temperature=0.2,
    max_tokens=1024,
)

response = llm.invoke("Qual é a capital da França?")
print(response.content)  # "Paris é a capital da França."
```

---

## 3. Modelos Suportados

A plataforma Google Generative AI oferece acesso a modelos Gemini e Gemma:

| Modelo | Entrada | Saída | Visão | Tool Calling | Structured Output |
|--------|---------|-------|-------|--------------|------------------|
| `gemini-3.5-flash` | 1M tokens | 8k tokens | ✅ | ✅ | ✅ |
| `gemini-3.1-pro-preview` | 1M tokens | 32k tokens | ✅ | ✅ | ✅ |
| `gemini-pro` | 32k tokens | 8k tokens | ❌ | ❌ | ❌ |
| `gemma-4-31b-it` (open weights) | 262k tokens | 32k tokens | ✅ | ✅ | ✅ |
| `gemma-2-9b-it` (open weights) | 8k tokens | 8k tokens | ❌ | ✅ | ✅ |

**Nota:** Verificar a documentação oficial para a lista completa de modelos atualizados.

---

## 4. Structured Output com Pydantic v2

A biblioteca suporta `with_structured_output()` para garantir respostas JSON validadas contra um schema Pydantic:

```python
from pydantic import BaseModel, Field
from langchain_google_genai import ChatGoogleGenerativeAI

class PersonExtraction(BaseModel):
    """Extração de informações de uma pessoa."""
    name: str = Field(description="Nome completo")
    age: int = Field(description="Idade em anos")
    email: str = Field(description="Endereço de e-mail")

llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")

# Usar with_structured_output com método json_schema
structured_llm = llm.with_structured_output(PersonExtraction, method="json_schema")

result = structured_llm.invoke(
    "Extraia informações: João Silva tem 35 anos e contato em joao@example.com"
)
print(result)
# PersonExtraction(name='João Silva', age=35, email='joao@example.com')
```

---

## 5. Suporte a Imagens (Vision)

Modelos Gemini suportam visão por meio de URLs ou Base64:

```python
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.messages import HumanMessage

llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")

message = HumanMessage(
    content=[
        {"type": "text", "text": "Descreva esta imagem em detalhes."},
        {
            "type": "image_url",
            "image_url": {"url": "https://example.com/image.jpg"},
        },
    ]
)

response = llm.invoke([message])
print(response.content)
```

---

## 6. GoogleGenerativeAIEmbeddings

Para geração de vetores de embedding (compatível com pgvector):

### Assinatura

```python
from langchain_google_genai import GoogleGenerativeAIEmbeddings

embeddings = GoogleGenerativeAIEmbeddings(
    # Autenticação
    google_api_key: str | None = None,      # Se não fornecido, usa GOOGLE_API_KEY
    api_key: str | None = None,             # Alias para google_api_key
    
    # Configuração de modelo (opcional)
    model: str = "models/embedding-001",    # Modelo de embedding padrão
    
    # Dimensionalidade customizável
    output_dimensionality: int | None = 768, # Dimensões de output (padrão: 768, compatível com pgvector)
)
```

### Uso para Embeddings

```python
from langchain_google_genai import GoogleGenerativeAIEmbeddings

# Usar com dimensionalidade de 1536 para compatibilidade com pgvector do projeto
embeddings = GoogleGenerativeAIEmbeddings(
    output_dimensionality=1536  # Ajuste conforme necessário
)

# Embeddings de documentos
texts = ["Python é uma linguagem de programação", "LangChain facilita a integração de LLMs"]
vectors = embeddings.embed_documents(texts)
print(len(vectors[0]))  # 1536

# Embedding de query (para busca vetorial)
query_vector = embeddings.embed_query("Qual é a melhor linguagem de programação?")
print(len(query_vector))  # 1536
```

### Batch Processing

```python
embeddings = GoogleGenerativeAIEmbeddings(output_dimensionality=1536)

# embed_documents usa batching automático (padrão: batch_size=100)
texts = ["Texto 1", "Texto 2", ..., "Texto 1000"]
vectors = embeddings.embed_documents(texts, batch_size=100)  # Processa em lotes de 100
```

---

## 7. Tool Calling (Function Calling)

Modelos Gemini suportam tool calling para integração com funções externas:

```python
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.tools import tool

@tool
def get_weather(location: str) -> str:
    """Obter o clima de uma localização."""
    return f"Clima em {location}: 25°C"

llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")
llm_with_tools = llm.bind_tools([get_weather])

response = llm_with_tools.invoke("Qual é o clima em São Paulo?")
print(response.tool_calls)
```

---

## 8. Streaming Nativo e Async

### Streaming de Tokens

```python
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")

for chunk in llm.stream("Escreva um poema sobre IA"):
    print(chunk.content, end="", flush=True)
```

### Execução Assíncrona

```python
import asyncio
from langchain_google_genai import ChatGoogleGenerativeAI

async def main():
    llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")
    response = await llm.ainvoke("Qual é a raiz quadrada de 16?")
    print(response.content)

asyncio.run(main())
```

---

## 9. Compatibilidade com init_chat_model

A biblioteca é compatível com a inicialização unificada do LangChain 1.x:

```python
from langchain.chat_models import init_chat_model

# Usar string de identificação "google_genai:<model>"
llm = init_chat_model(
    "google_genai:gemini-3.5-flash",
    model_provider="google_genai",
    temperature=0.2,
)

response = llm.invoke("Hello")
print(response.content)
```

### Inicializar Embeddings com init_embeddings

```python
from langchain.embeddings import init_embeddings

embeddings = init_embeddings(
    "google_genai:models/embedding-001",
    embeddings_provider="google_genai",
    output_dimensionality=1536,
)

vectors = embeddings.embed_documents(["Seu texto aqui"])
```

---

## 10. Tratamento de Erros

```python
from langchain_google_genai import ChatGoogleGenerativeAI

llm = ChatGoogleGenerativeAI(model="gemini-3.5-flash")

try:
    response = llm.invoke("Teste")
except Exception as e:
    print(f"Erro ao chamar Google Generative AI: {e}")
    # Implementar fallback para outro provedor
```

---

## 11. Dimensionalidade de Embeddings para pgvector

O projeto usa **pgvector com dimensão 1536** no banco de dados. A biblioteca Google Generative AI permite customizar a dimensionalidade via `output_dimensionality`:

```python
embeddings = GoogleGenerativeAIEmbeddings(
    output_dimensionality=1536  # ✅ Compatível com pgvector do projeto
)

# Alternativas (se necessário):
# output_dimensionality=768   # Dimensão padrão (menor overhead)
# output_dimensionality=1536  # Alto-dimensional (maior precisão)
```

**Nota:** Confirmar com a equipe o tamanho de dimensão efetivamente configurado no pgvector antes de usar.

---

## 12. Notas de Compatibilidade

- **Python >= 3.9** (validado com 3.13)
- **Pydantic v2:** Obrigatório para structured output; usar `BaseModel` direto
- **LangChain 1.x:** Funciona nativamente; não requer `langchain-classic`
- **Quota de Rate Limiting:** Google Generative AI aplica limites por minuto e por dia; implementar retry com backoff exponencial
- **Custo:** API gratuita até limite de requisições; verificar pricing para produção

---

## 13. Referências

- [GitHub LangChain Google](https://github.com/langchain-ai/langchain-google)
- [Google AI Studio](https://aistudio.google.com) — Obter chave de API
- [Documentação Gemini](https://ai.google.dev/docs)
- [Modelos Disponíveis](https://ai.google.dev/models)
