# Loguru

- **Versão Recomendada:** 0.7.2
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Logging estruturado e formatado para o motor de IA (`ai-engine`), substituindo o módulo de log padrão do Python.
- **Documentação Oficial:** [https://github.com/Delgan/loguru](https://github.com/Delgan/loguru)

---

## 1. Contexto e Uso no Projeto

O monitoramento do comportamento dos prompts, embeddings e conexões de APIs de terceiros (OpenAI, Groq) exige logs detalhados e fáceis de filtrar no console e arquivos. O **Loguru** é a biblioteca padrão escolhida pela sua simplicidade e capacidade de serializar saídas estruturadas em JSON no ambiente de produção.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Uso Correto dos Níveis de Log
Evite classificar tudo como `INFO` ou `ERROR`. Siga a matriz de criticidade:

*   **`DEBUG`**: Detalhes finos de execução técnica. Ex: Duração da query vetorial, contagem de tokens consumidos no prompt, payloads parciais.
*   **`INFO`**: Eventos marcantes no fluxo normal do sistema. Ex: Inicialização do servidor gRPC, carregamento de chaves de um novo tenant, finalização de processamento de áudio.
*   **`WARNING`**: Situações incomuns que não quebram o fluxo, mas exigem atenção. Ex: Fallback automático de modelo (ex: OpenAI caiu e mudou para Groq), lentidão incomum na API de LLM.
*   **`ERROR`**: Falhas graves no processamento de um request individual que afetam a resposta do usuário. Ex: Chave de API inválida fornecida pelo tenant, falha de validação irreversível.
*   **`CRITICAL`**: Falhas que impedem o funcionamento de todo o serviço do `ai-engine`. Ex: Sem portas de rede disponíveis, falha de variáveis de ambiente do sistema geral no bootstrap.

### 2.2 Proibição Absoluta do `print()`
Nunca utilize a função nativa `print()` em código de produção. Prints ignoram o controle de níveis de log do sistema e prejudicam a leitura no painel de observabilidade da VM Hostinger.

*   **Incorreto (Não Faça):**
    ```python
    print(f"Buscando documentos no pgvector para o tenant {tenant_id}")
    ```
*   **Correto (Faça):**
    ```python
    from loguru import logger

    logger.debug("Buscando documentos no pgvector para o tenant {tenant}", tenant=tenant_id)
    ```

### 2.3 Logs com Contexto Adicional (Structured Logging)
Utilize o método `.bind()` para anexar metadados permanentes (como `tenant_id`, `contact_id`) a um contexto de log sem precisar concatenar strings manualmente na mensagem.

```python
# Cria um logger contextualizado para o request atual
req_logger = logger.bind(tenant_id="uuid-123", handler="Summarizer")

req_logger.info("Iniciando transcrição de áudio.")
# O log gerado incluirá implicitamente nos metadados: {"tenant_id": "uuid-123", "handler": "Summarizer"}
```

### 2.4 Intercepção Segura de Exceções (Catch)
Use o decorador ou gerenciador de contexto `@logger.catch` para capturar exceções inesperadas, gerando automaticamente stacktraces detalhados e formatados no log, impedindo que a aplicação quebre abruptamente sem rastreabilidade.

```python
@logger.catch
def unsafe_model_interaction(data: str) -> str:
    # Se esta função lançar ZeroDivisionError ou IndexError, o loguru
    # captura e imprime o trace detalhado indicando os valores das variáveis
    return interact_with_llm(data)
```
