# Pydantic

- **Versão Recomendada:** 2.7.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Validação de tipos em tempo de execução, parsing de dados JSON e gerenciamento de configurações de ambiente.
- **Documentação Oficial:** [https://docs.pydantic.dev/](https://docs.pydantic.dev/)

---

## 1. Contexto e Uso no Projeto

No módulo `ia_engine` (Python), a validação de tipos é crítica porque os dados de entrada e saída serão trocados localmente ou via gRPC com o backend escrito em Rust. Divergências de schemas na camada FFI/gRPC causariam erros catastróficos no backend. 

O **Pydantic** garante que:
- Contratos (Requests/Responses) recebidos da FFI em formato JSON sejam validados estritamente e convertidos em tipos Python nativos.
- Configurações do arquivo `.env` sejam mapeadas com segurança.

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Declaração Estrita de Modelos (BaseModel)
Toda entrada e saída de funções de serviço deve ser representada por uma subclasse de `BaseModel` do Pydantic. Use tipagem estática pura em todas as propriedades e adicione anotações explicativas.

```python
from pydantic import BaseModel, Field

class SummaryRequest(BaseModel):
    """Contrato de entrada para solicitação de resumo de conversa."""
    text: str = Field(
        min_length=1, 
        description="Texto da conversa a ser resumido. Não pode ser vazio."
    )
    max_length: int = Field(
        default=250, 
        gt=0, 
        description="Limite máximo de caracteres para o resumo."
    )

class SummaryResponse(BaseModel):
    """Contrato de retorno para o Rust."""
    success: bool
    summary: str
    error_message: str | None = None
```

### 2.2 Tratamento de Configurações com `pydantic-settings`
Utilize `SettingsConfigDict` para carregar as chaves de API e configurações de ambiente do arquivo `.env` de forma declarativa e fortemente tipada.

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class AppConfig(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore" # Ignora variáveis extras no .env que não pertencem a esta classe
    )

    openai_api_key: str
    groq_api_key: str | None = None
    ai_engine_port: int = 50051
    debug_mode: bool = False
```

### 2.3 Tratamento de Exceções de Validação
Ao expor funções via FFI ou gRPC, intercepte `ValidationError` do Pydantic na fronteira do sistema para evitar pânicos no runtime e retorne um modelo de erro elegante contendo detalhes da validação.

```python
from pydantic import ValidationError

def ffi_summarize(json_payload: str) -> str:
    try:
        # Tenta desserializar e validar
        request = SummaryRequest.model_validate_json(json_payload)
        
        # Executa o serviço de IA
        response = run_summarizer(request)
        return response.model_dump_json()
        
    except ValidationError as val_error:
        # Retorna erro amigável em vez de lançar exceção
        error_response = SummaryResponse(
            success=False,
            summary="",
            error_message=f"Erro de validação nos dados de entrada: {val_error.errors()}"
        )
        return error_response.model_dump_json()
```

### 2.4 Proibição do tipo `Any`
Não utilize `Any` em propriedades de modelos do Pydantic. Se uma propriedade puder aceitar mais de um tipo, utilize tipos união (`str | int`) ou tipagem estrutural.
