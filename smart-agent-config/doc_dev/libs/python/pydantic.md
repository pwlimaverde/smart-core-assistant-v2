# Pydantic

- **Versão Recomendada:** 2.13.5 (publicada em 2026-08-28); `pydantic-settings` 2.15.0
- **Pisos nos manifestos:** o `ia_engine` exige `pydantic>=2.9`; o `mcp_server` exige `>=2.12`, porque o SDK `mcp` 2.1.1 o impõe
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-10 (PyPI JSON API, ao resolver o conflito de merge entre duas verificações divergentes)
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

---

## 3. JSON Schema e Geração de Schemas

O Pydantic continua oferecendo métodos robustos para geração de JSON Schema, essencial para a derivação de schemas de tools MCP via FastMCP:

### 3.1 Método `model_json_schema()`
```python
from pydantic import BaseModel, Field

class MyModel(BaseModel):
    name: str = Field(description="Nome do usuário")
    age: int = Field(description="Idade em anos", ge=0)

# Gera JSON Schema
schema = MyModel.model_json_schema()
# Você pode controlar aliases e outras opções:
schema_by_alias = MyModel.model_json_schema(by_alias=True)
```

### 3.2 `WithJsonSchema` para Customização
Use a anotação `WithJsonSchema` para override customizado do schema sem implementar geradores complexos:

```python
from pydantic import BaseModel, WithJsonSchema
from typing import Annotated

class MyModel(BaseModel):
    # Override o schema gerado automaticamente
    custom_field: Annotated[str, WithJsonSchema({"type": "string", "pattern": "^[A-Z]"})]
```

### 3.3 `GenerateJsonSchema` Customizado
Para controle fino sobre toda a geração, estenda `GenerateJsonSchema`:

```python
from pydantic.json_schema import GenerateJsonSchema

class CustomJsonSchema(GenerateJsonSchema):
    def string_schema(self, schema):
        # Customiza geração de schemas de string
        json_schema = super().string_schema(schema)
        # Sua lógica aqui
        return json_schema
```

---

## 4. Breaking Changes e Migrações (2.7.1 → 2.13.5)

### 4.1 Requisitos de Python
- **Remover:** Python 3.8 (descontinuado em v2.11)
- **Novo:** Python 3.14 suportado (v2.12), mas Pydantic V1 namespace é incompatível com 3.14+

### 4.2 Acesso a `model_fields` e `model_computed_fields`
Desde v2.11, acessar esses atributos em **instâncias** de modelo (não em classes) dispara deprecation warning:

```python
# ❌ Deprecado (v2.11+)
instance = MyModel(...)
fields = instance.model_fields  # Gera warning!

# ✅ Correto
fields = MyModel.model_fields  # Sempre na classe
```

### 4.3 `create_model()` — Formato Reworked (v2.11)
Se você usa `create_model()` dinamicamente, verifique a mudança de formato na v2.11 (definições de campo foram reorganizadas).

### 4.4 `polymorphic_serialization` (v2.13)
Nova opção para resolver inconsistências com `serialize_as_any` (introduzido em v2.12):

```python
class MyModel(BaseModel):
    model_config = ConfigDict(polymorphic_serialization=True)
```

### 4.5 Validator/Serializer Alignment (v2.13)
Em v2.13.0b1, a lógica de `field_serializer` foi alinhada com `field_validator`, afetando comportamento de validadores customizados. Revise se você implementa ambos.

### 4.6 Merge de pydantic-core (v2.13)
O repositório `pydantic-core` foi merged no main `pydantic` em v2.13.0b1. A build/dependencies agora são gerenciadas de forma integrada. Isso simplifica o setup, mas confirme compatibilidade se você estende `pydantic-core` diretamente.

---

## 5. Novas Features Relevantes (v2.8 → v2.13)

- **`exclude_if`** (v2.13): Exclusão condicional em nível de campo durante serialização
- **`ValidateAs`** (v2.13): Anotação helper para validação flexível de tipos
- **`exclude_computed_fields`** (v2.13): Opção de serialização para excluir campos computados
- **PEP 728 Support** (v2.13): TypedDict com variadic keyword arguments
- **UUID v6, v7, v8** (v2.13): Novos tipos UUID para standards modernos
- **`SocketPath`** (v2.13): Tipo para caminhos de socket Unix no Linux

---

## 6. Histórico de Atualizações

| Data | Versão | Motivo da Atualização |
|------|--------|----------------------|
| 2026-09-06 | 2.7.1 → 2.13.5 | Verificação regular: versão antiga tinha >90 dias. Adicionadas seções sobre JSON Schema, breaking changes, novas features. pydantic-settings atualizado para 2.15.0. |
| 2026-05-31 | 2.7.1 | Última verificação anterior |

## 3. Saída estruturada de LLM (2026-09-07)

Base do bloco **C1** do plano `painel-crm-e-campos-do-cartao`: o `Responder`
precisa devolver campos extraídos da conversa em forma tipada, e não em texto
livre. O caminho é `BaseModel` + `with_structured_output` do LangChain — que
desde a 1.x usa **`pydantic.BaseModel` (v2) direto**, sem o shim
`langchain_core.pydantic_v1`, removido.

```python
from pydantic import BaseModel, Field

class CampoExtraido(BaseModel):
    slug: str = Field(description="slug exato do campo pendente; nunca invente")
    valor_json: str = Field(description="valor na forma tipada do campo")
    confianca: float = Field(ge=0.0, le=1.0)

class RespostaDoResponder(BaseModel):
    resposta_texto: str
    transferir_atendimento: bool = False
    fluxo_transferencia: str = ""
    confiabilidade: float = Field(ge=0.0, le=1.0)
    # Lista vazia é o resultado esperado na maioria das mensagens:
    # omitir é sempre preferível a inferir.
    campos_extraidos: list[CampoExtraido] = Field(default_factory=list)
```

O schema é derivado por `model_json_schema()`; a validação da resposta do
modelo, por `model_validate`. Ambos estáveis de 2.7 a 2.13.

> ⚠️ **O schema restringe a forma, não a verdade.** Um modelo pode devolver um
> `slug` que não existe e um `valor_json` inventado, ambos perfeitamente
> válidos para o Pydantic. A validação semântica (slug no catálogo, valor
> compatível com o tipo, piso de confiança) é do servidor — ver as cinco
> guardas de C1.

## Histórico de Atualizações

- **2026-09-07** — Versão recomendada corrigida de 2.7.1 para 2.13.4; o
  manifesto do `ia_engine` já exigia `>=2.9`, e o doc apontava uma versão
  anterior à do próprio projeto. Verificado o changelog oficial: entre 2.7 e
  2.13 **nada quebra** em `BaseModel`, `Field`, `model_validate` ou
  `model_json_schema`. Mudanças de ruptura ficaram em áreas que o projeto não
  usa: remoção do Python 3.8, `model_fields` acessado em instância (agora
  deprecado), formato de campos do `create_model` e comportamento de
  `serialize_as_any`. Seção 3 acrescentada para a saída estruturada do
  `Responder` (plano `painel-crm-e-campos-do-cartao`, bloco C1).

