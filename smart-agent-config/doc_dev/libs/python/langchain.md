# LangChain

- **Versão Recomendada:** 0.1.20
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Orquestração de chamadas de LLMs, geração de embeddings, chains e manipulação do RAG (Retrieval-Augmented Generation).
- **Documentação Oficial:** [https://python.langchain.com/](https://python.langchain.com/)

---

## 1. Contexto e Uso no Projeto

O motor de IA (`ai-engine` escrito em Python) utiliza a stack do **LangChain** para encapsular e padronizar toda a lógica cognitiva do chatbot:
- **Intents e Entidades:** Classificação semântica da intenção do contato e extração de chaves.
- **RAG (Busca Vetorial):** Busca de dados em documentos de treinamento do tenant (armazenados via pgvector) para enriquecer o contexto de resposta da LLM.
- **Geração de Resposta:** Prompt chains com histórico de mensagens e persona do bot configurado.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Injeção de Dependências de Modelos (Sem Inicialização Hardcoded)
Nunca instancie clientes de LLM (como `ChatOpenAI`, `ChatGroq`) diretamente dentro das classes de serviço. Injete-os via construtores para facilitar o mocking durante os testes de lógica pura e manter o desacoplamento de provedores.

*   **Incorreto (Não Faça):**
    ```python
    class SummarizerService:
        def __init__(self) -> None:
            # Acoplamento rígido de provedor e carregamento de chaves oculto
            self.llm = ChatOpenAI(model="gpt-4o")
    ```
*   **Correto (Faça):**
    ```python
    from langchain_core.language_models import BaseChatModel

    class SummarizerService:
        def __init__(self, llm: BaseChatModel) -> None:
            # LLM injetada externamente
            self.llm = llm
            
        def summarize(self, text: str) -> str:
            prompt = f"Resuma em português: {text}"
            return self.llm.invoke(prompt).content
    ```

### 2.2 Isolamento de API Keys (Chaves de API)
As credenciais e tokens dos provedores não devem residir em variáveis globais ou constantes. Elas devem ser injetadas a partir de arquivos `.env` gerenciados pela Pydantic Settings na inicialização do serviço central (`server.py`).

Quando o tenant provê sua própria chave de API (`tenant_config.api_keys`), o sistema deve instanciar a classe da LLM dinamicamente usando aquela chave específica.

```python
from langchain_openai import ChatOpenAI

def get_tenant_llm(api_key: str, model_name: str) -> ChatOpenAI:
    return ChatOpenAI(
        openai_api_key=api_key,
        model=model_name,
        temperature=0.2,
    )
```

### 2.3 Utilização de Prompt Templates em Português
Todos os prompts devem estar em português e ser estruturados usando `ChatPromptTemplate` do LangChain para lidar corretamente com papéis do sistema (`system`), mensagens do usuário (`user`) e histórico (`placeholder`).

```python
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

prompt_template = ChatPromptTemplate.from_messages([
    ("system", "Você é {bot_name}, atendente virtual da empresa {company_name}. Responda com base na persona: {persona}."),
    MessagesPlaceholder(variable_name="chat_history"),
    ("user", "{input_message}"),
])
```

### 2.4 Escrita de Testes Unitários Isolados de Rede (Mocking)
Chamadas de IA geram custo e latência. Portanto, todos os testes unitários que usam LangChain devem utilizar `pytest-mock` para mocar a chamada `.invoke()` ou `.stream()` do modelo.

```python
def test_should_summarize_successfully(mocker):
    # Arrange
    mock_llm = mocker.MagicMock()
    mock_llm.invoke.return_value.content = "Texto resumido pelo Mock."
    
    service = SummarizerService(llm=mock_llm)
    
    # Act
    summary = service.summarize("Algum texto longo para resumir")
    
    # Assert
    assert summary == "Texto resumido pelo Mock."
    mock_llm.invoke.assert_called_once()
```
