# LangChain

- **Versão Recomendada:** 1.0.0+ (atual: 1.x com semântica estável)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-06
- **Propósito no Projeto:** Orquestração de chamadas de LLMs, geração de embeddings, chains LCEL (LangChain Expression Language) e manipulação do RAG (Retrieval-Augmented Generation).
- **Documentação Oficial:** [https://docs.langchain.com/oss/python](https://docs.langchain.com/oss/python)

---

## Histórico de Atualizações

- **2026-07-06** — Atualizado de 0.1.20 para versão estável 1.x em preparação à implementação da fase N2 (ia_engine). Context7 consultado para validar LCEL, chat models, prompt templates, output parsers, embeddings e document loaders.

---

## 1. Versão Estável Atual e Política de Versão

**LangChain 1.0.0+** é a versão estável recomendada desde Dezembro/2025. A biblioteca adota **semântica de versão**:

- **Versão 1.x:** Mantém estabilidade durante todo o ciclo 1.x; features depreciadas continuam funcionando.
- **Breaking changes** ocorrem apenas em major releases (ex.: 2.0).
- **Instalação:** `pip install -U langchain langchain-core` (sempre manter sincronizadas).

**Nota:** A versão 0.1.x usada no projeto original está significativamente desatualizada. O porte para 1.x é recomendado e aborda:
- Reorganização de imports (core, integrations específicas).
- Remoção da classe legada `LLMChain` (substituída por LCEL + pipe operator).
- Migração de estruturas de dados (versão antiga usava dicts, nova versão usa Runnable objects).

### 1.1 Migração 0.1.x → 1.x (confirmado no Context7 em 2026-07-06)

- **`langchain-classic`:** chains legadas (`LLMChain`, `langchain.chains.*`), retrievers antigos, indexing API e o módulo `hub` saíram do pacote `langchain` e vivem em `langchain-classic` (não recomendado para projeto novo — no porte da `FeaturesCompose`, reescrever em LCEL em vez de depender do classic).
- **Pydantic v2 nativo:** o shim `langchain_core.pydantic_v1` foi removido — usar `pydantic.BaseModel` (v2) direto, inclusive em `with_structured_output`.
- **Namespace 1.x:** agentes em `langchain.agents` (`create_agent`); mensagens re-exportadas em `langchain.messages`; tools em `langchain.tools`; inicialização unificada de chat models em `langchain.chat_models` (`init_chat_model`); embeddings em `langchain.embeddings`.
- **Integrações:** provedores em pacotes próprios (`langchain-openai`, `langchain-community`…); `OpenAIEmbeddings`/`ChatOpenAI` vêm de `langchain_openai`.
- **LCEL:** composição por pipe (`prompt | llm | parser`) é o padrão; `StrOutputParser`/`PydanticOutputParser` em `langchain_core.output_parsers`.

---

## 2. Contexto e Uso no Projeto

O motor de IA (`ia_engine` escrito em Python) utiliza a stack do **LangChain** para encapsular e padronizar toda a lógica cognitiva do chatbot:
- **Intents e Entidades:** Classificação semântica da intenção do contato e extração de chaves.
- **RAG (Busca Vetorial):** Busca de dados em documentos de treinamento do tenant (armazenados via pgvector) para enriquecer o contexto de resposta da LLM.
- **Geração de Resposta:** Prompt chains com histórico de mensagens e persona do bot configurado.

---

## 3. Padrões de Implementação e Boas Práticas

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
