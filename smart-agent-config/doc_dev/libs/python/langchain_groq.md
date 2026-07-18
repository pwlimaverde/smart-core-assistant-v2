# LangChain Groq

- **Versão Recomendada:** 0.1.0+
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-17
- **Propósito no Projeto:** Fallback de provedor LLM no ia_engine (fase N6.4) para casos de indisponibilidade de OpenAI/Google. ChatGroq oferece modelos de chat rápidos via plataforma Groq com suporte a tool calling, structured output e streaming nativo.
- **Documentação Oficial:** [https://docs.langchain.com/oss/python/integrations/chat/groq](https://docs.langchain.com/oss/python/integrations/chat/groq)
- **Context7 Library ID:** `/websites/langchain_oss`

---

## Histórico de Atualizações

- **2026-07-17** — Documentação inicial criada via Context7. Foco em integração ChatGroq com LangChain 1.x, modelos suportados, structured output com pydantic v2 e compatibilidade com init_chat_model.

---

## 1. Instalação e Configuração

### Instalação

```bash
uv add langchain-groq
```

**Dependências Recomendadas:**
- `langchain-core>=0.1.0`
- `pydantic>=2.0` (obrigatório para structured output)

### Autenticação

A biblioteca carrega automaticamente a chave de API da variável de ambiente `GROQ_API_KEY`:

```python
import os
from langchain_groq import ChatGroq

# A partir de GROQ_API_KEY
llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")

# Ou injetar explicitamente (recomendado para multi-tenant)
llm = ChatGroq(
    model="meta-llama/llama-4-scout-17b-16e-instruct",
    groq_api_key=tenant_config.api_key,
    temperature=0.2,
)
```

---

## 2. Assinatura Atual do ChatGroq

### Parâmetros Principais

```python
from langchain_groq import ChatGroq

llm = ChatGroq(
    # Obrigatório
    model: str,                    # Identificador do modelo (ex: "meta-llama/llama-4-scout-17b-16e-instruct")
    
    # Autenticação
    groq_api_key: str | None = None,  # Se não fornecido, usa GROQ_API_KEY
    
    # Comportamento
    temperature: float = 0.7,      # Criatividade (0.0 a 2.0)
    max_tokens: int | None = None, # Limite de tokens na resposta
    timeout: float | None = None,  # Timeout em segundos
    
    # Parâmetros de streaming e async
    streaming: bool = False,       # Ativar streaming de tokens
)
```

### Exemplo Básico

```python
from langchain_groq import ChatGroq

llm = ChatGroq(
    model="meta-llama/llama-4-scout-17b-16e-instruct",
    temperature=0.2,
    max_tokens=1024,
)

response = llm.invoke("Qual é a capital da França?")
print(response.content)  # "Paris é a capital da França."
```

---

## 3. Modelos Suportados

A plataforma Groq disponibiliza modelos otimizados para latência ultra-baixa:

| Modelo | Tokens de Entrada | Tokens de Saída | Visão | Tool Calling | Structured Output |
|--------|-------------------|-----------------|-------|--------------|------------------|
| `meta-llama/llama-4-scout-17b-16e-instruct` | ~128k | ~8k | ✅ | ✅ | ✅ |
| `mixtral-8x7b-32768` | 32k | 4k | ❌ | ✅ | ✅ |
| `gemma-2-9b-it` | 8k | 8k | ❌ | ✅ | ✅ |

**Nota:** Verifique a documentação oficial da Groq para a lista completa de modelos atualizados.

---

## 4. Structured Output com Pydantic v2

A biblioteca suporta `with_structured_output()` para garantir respostas JSON validadas contra um schema Pydantic:

```python
from pydantic import BaseModel, Field
from langchain_groq import ChatGroq

class PersonExtraction(BaseModel):
    """Extração de informações de uma pessoa."""
    name: str = Field(description="Nome completo")
    age: int = Field(description="Idade em anos")
    email: str = Field(description="Endereço de e-mail")

llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")

# Usar with_structured_output com método json_mode
structured_llm = llm.with_structured_output(PersonExtraction, method="json_mode")

result = structured_llm.invoke(
    "Extraia informações: João Silva tem 35 anos e contato em joao@example.com"
)
print(result)
# PersonExtraction(name='João Silva', age=35, email='joao@example.com')
```

---

## 5. Suporte a Imagens (Vision)

O modelo `llama-4-scout-17b` suporta input de imagens via URL:

```python
from langchain_groq import ChatGroq
from langchain_core.messages import HumanMessage

llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")

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

## 6. Streaming Nativo e Async

### Streaming de Tokens

```python
from langchain_groq import ChatGroq

llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")

for chunk in llm.stream("Escreva um poema sobre IA"):
    print(chunk.content, end="", flush=True)
```

### Execução Assíncrona

```python
import asyncio
from langchain_groq import ChatGroq

async def main():
    llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")
    response = await llm.ainvoke("Qual é a raiz quadrada de 16?")
    print(response.content)

asyncio.run(main())
```

---

## 7. Compatibilidade com init_chat_model

A biblioteca é compatível com a inicialização unificada do LangChain 1.x:

```python
from langchain.chat_models import init_chat_model

# Usar string de identificação "groq:<model>"
llm = init_chat_model(
    "groq:meta-llama/llama-4-scout-17b-16e-instruct",
    model_provider="groq",
    temperature=0.2,
)

response = llm.invoke("Hello")
print(response.content)
```

---

## 8. Tratamento de Erros

A biblioteca pode lançar exceções de autenticação, rate limiting ou indisponibilidade da API:

```python
from langchain_groq import ChatGroq
from langchain_core.exceptions import LangChainException

llm = ChatGroq(model="meta-llama/llama-4-scout-17b-16e-instruct")

try:
    response = llm.invoke("Teste")
except Exception as e:
    print(f"Erro ao chamar Groq: {e}")
    # Implementar fallback para outro provedor
```

---

## 9. Notas de Compatibilidade

- **Python >= 3.9** (validado com 3.13)
- **Pydantic v2:** Obrigatório para structured output; usar `BaseModel` direto, não shimmed
- **LangChain 1.x:** Funciona nativamente; não requer `langchain-classic`
- **Latência:** Groq oferece as menores latências de mercado (otimização de hardware especializador)

---

## 10. Referências

- [Documentação LangChain Groq](https://docs.langchain.com/oss/python/integrations/chat/groq)
- [Console Groq](https://console.groq.com) — Obter chave de API
- [Modelos Suportados (Groq)](https://console.groq.com/docs/models)
