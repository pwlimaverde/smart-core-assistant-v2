# MCP Python SDK (mcp / MCPServer)

- **Versão Recomendada:** 2.1.1
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-09-06 (WebSearch/WebFetch — context7 indisponível na sessão)
- **Propósito no Projeto:** SDK oficial para construir servidores MCP que exponham ferramentas, recursos e prompts ao Claude e outros hosts LLM de forma padronizada e segura.
- **Documentação Oficial:** [https://py.sdk.modelcontextprotocol.io/](https://py.sdk.modelcontextprotocol.io/)

---

> **Nota do projeto (revisada em 2026-09-09):** o `mcp_server` da fase N13 é
> **resource server OAuth 2.1**, com authorization server próprio no
> `control_plane` (`server/apps/control_plane/src/oauth/`).
>
> A versão anterior desta nota dizia que a v1 usaria **token opaco**. Isso foi
> revertido, e o motivo vale registrar: a **UI de conector** do Claude (web,
> desktop, mobile, Cowork) é OAuth. Header/bearer estático só funciona em
> `claude mcp add --header`, no arquivo de configuração do Desktop e no `mcp.json`
> do Cursor. Com token opaco não ficaríamos "fora do ChatGPT" — ficaríamos fora do
> **conector do próprio Claude**, e portanto do Claude web e do mobile. Ver C18–C22
> em `.context/plans/n13-mcp-agentes/plano_completo_n13-mcp-agentes.md`.
>
> O que o SDK já entrega e por isso **não** escrevemos à mão: o
> `/.well-known/oauth-protected-resource` (RFC 9728) e o `WWW-Authenticate` com
> `resource_metadata` em 401/403, ambos montados quando
> `AuthSettings.resource_server_url` está preenchido.
>
> Detalhes de implementação que custaram tempo e ficam registrados aqui:
> `MCPServer.list_tools()` não recebe contexto (a identidade vem de
> `get_access_token()`, do contextvar); os parâmetros de transporte vão no `run()`
> e não no construtor; e o SDK **loga `str(exc)`** no caminho de erro de tool — por
> isso nenhuma mensagem de `ToolError` do módulo pode conter PII.

---

## 1. Contexto e Uso no Projeto

O **Model Context Protocol (MCP)** é um protocolo padronizado que permite que aplicações forneçam contexto a modelos de linguagem de forma segura e estruturada. O SDK Python v2 é a implementação oficial, lançada em 28 de julho de 2026, que suporta a especificação MCP 2026-07-28 e é totalmente retrocompatível com servidores v1.

O projeto usa MCP para:
- Expor **ferramentas (tools)** que agentes Claude podem invocar
- Documentar automaticamente schemas via type hints Python e Pydantic
- Implementar autenticação via OAuth 2.1 Bearer tokens (HTTP Streamable)
- Gerenciar permissões dinâmicas por sessão/usuário

### Requisitos Mínimos
- Python 3.10+
- Instalação: `pip install mcp` ou `uv add mcp[cli]`
- Para CLI tooling (`mcp dev`, `mcp run`): `pip install "mcp[cli]"` ou `uv add "mcp[cli]"`

---

## 2. Guia de Uso Rápido

### 2.1 FastMCP → MCPServer (Renomeação v1 → v2)

No SDK v2, **`FastMCP` foi renomeado para `MCPServer`**. Atualize imports:

```python
# ❌ Antigas (v1)
# from mcp.server.fastmcp import FastMCP
# server = FastMCP("MyApp")

# ✅ Novas (v2)
from mcp.server import MCPServer

server = MCPServer("MyApp")
```

### 2.2 Decorador @mcp.tool() e Schema via Type Hints + Pydantic

O SDK **gera automaticamente o JSON Schema** a partir de:
1. **Type hints** Python (obrigatório)
2. **Docstring** (descrição da ferramenta)
3. **Pydantic `Field()` e `Annotated`** (validação, descrições de parâmetros, constraints)

#### Exemplo Básico

```python
from mcp.server import MCPServer
from typing import Annotated, Literal
from pydantic import Field

server = MCPServer("BookshopAPI")

# Tool simples
@server.tool()
def add(a: int, b: int) -> int:
    """Soma dois números inteiros."""
    return a + b

# Tool com validação e descrições
@server.tool()
def search_books(
    query: Annotated[str, Field(description="Título ou autor a buscar.")],
    limit: Annotated[int, Field(ge=1, le=50, description="Máximo de resultados.")] = 10,
    genre: Annotated[
        Literal["ficção", "não-ficção", "poesia"] | None,
        Field(description="Filtro por gênero (opcional).")
    ] = None,
) -> str:
    """Busca livros no catálogo por título, autor ou gênero.
    
    Retorna uma lista formatada com os resultados encontrados.
    """
    # Implementação...
    return f"Resultados para '{query}' (limite: {limit})"

# Tool assíncrona
@server.tool()
async def fetch_weather(city: str) -> dict:
    """Busca previsão de tempo para uma cidade."""
    # Implementação com await...
    return {"city": city, "temp": 25}
```

**Pontos-chave:**
- **Type hints obrigatório**: Sem eles, a tool não é registrada.
- **Docstring é a descrição**: A primeira linha torna-se a descrição da tool no MCP.
- **`Annotated[tipo, Field(...)]`**: Para adicionar descrições e validação por parâmetro.
- **`Literal[...]`**: Restringe valores possíveis; gera `enum` no JSON Schema.
- **Async/sync**: Ambas são suportadas; async é preferível para I/O.

#### Parâmetros Complexos com Pydantic Models

```python
from pydantic import BaseModel, Field

class SearchFilter(BaseModel):
    """Filtros de busca para livros."""
    genre: str = Field(description="Gênero literário")
    min_year: int = Field(ge=1900, description="Ano de publicação mínimo")
    max_price: float | None = Field(default=None, description="Preço máximo (opcional)")

@server.tool()
def search_books_advanced(query: str, filters: SearchFilter) -> list[dict]:
    """Busca avançada com múltiplos filtros."""
    # Pydantic já valida `filters` antes de chegar à função
    return [...]
```

### 2.3 Transporte HTTP Streamable: Servindo via ASGI

O MCP suporta três transports: **stdio**, **SSE (Server-Sent Events)**, e **Streamable HTTP** (o recomendado para produção).

#### Rodando Standalone com `mcp.run()`

```python
from mcp.server import MCPServer

server = MCPServer("WeatherAPI")

@server.tool()
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"Sunny in {city}"

# Roda com `uv run file.py` após chamar:
if __name__ == "__main__":
    # Inicia servidor HTTP em http://localhost:8000/mcp (default)
    mcp.run(
        transport="streamable-http",
        host="127.0.0.1",
        port=8000,
        stateless_http=True,  # Sem session state (recomendado para load-balancing)
        json_response=True    # JSON em vez de SSE
    )
```

#### Montando em Starlette/FastAPI Existente

```python
from starlette.applications import Starlette
from starlette.routing import Mount
import uvicorn

server = MCPServer("MyService")

@server.tool()
def greet(name: str) -> str:
    """Greets a person."""
    return f"Hello, {name}!"

# Monta o app ASGI do MCP em um prefixo de rota
app = Starlette(
    routes=[
        Mount("/mcp", app=server.streamable_http_app()),
    ]
)

# Roda com: uvicorn file:app --reload
# Clientes conectam a: http://localhost:8000/mcp
```

**Path configurável:**

```python
# Por default, endpoints estão em `/mcp/process` (path relativo)
# Para customizar:
server.streamable_http_app(
    streamable_http_path="/"  # Endpoints em `/process` no Mount
)
```

**Caminho padrão:** `/mcp` para o Handler MCP dentro de qualquer Mount.

### 2.4 Autenticação: Bearer Token e Contexto de Requisição

O SDK trata o servidor MCP como um **OAuth 2.1 resource server**. Você implementa `TokenVerifier` para validar tokens do header `Authorization: Bearer <token>`.

#### Implementar TokenVerifier

```python
from mcp.server import MCPServer
from mcp.server.auth import TokenVerifier, AccessToken

class MyTokenVerifier(TokenVerifier):
    """Valida Bearer tokens contra um repositório conhecido."""
    
    async def verify_token(self, token: str) -> AccessToken | None:
        """Retorna AccessToken se válido, None caso contrário."""
        if token == "known-secret-token-123":
            return AccessToken(
                subject="user@example.com",
                scopes=["tools:read", "tools:write"],
                # custom_claims (opcional) para informações adicionais
            )
        return None

server = MCPServer("MyAPI")

@server.tool()
def protected_operation(data: str) -> str:
    """Operação que requer autenticação."""
    return f"Processado: {data}"

# Ativa autenticação
server.set_token_verifier(MyTokenVerifier())
```

#### Acessar Token e Contexto Dentro de uma Tool

```python
from mcp.server.auth.middleware.auth_context import get_access_token

@server.tool()
def user_specific_action(action: str) -> str:
    """Ação que precisa saber quem está chamando."""
    token = get_access_token()
    if token:
        user_id = token.subject  # "user@example.com"
        scopes = token.scopes    # ["tools:read", "tools:write"]
        return f"Executando '{action}' para {user_id}"
    else:
        return "Token não encontrado"

# Headers HTTP entrada:
# Authorization: Bearer known-secret-token-123
```

**Configuração OAuth 2.1 (AuthSettings):**

```python
from mcp.server.auth import AuthSettings

server.set_token_verifier(
    verifier=MyTokenVerifier(),
    auth_settings=AuthSettings(
        issuer_url="https://auth0.example.com",           # Seu provedor
        resource_server_url="https://api.example.com",    # URL pública do MCP
        required_scopes=["tools:read"],                   # Scopes obrigatórios
        validate_token_resource=True,                      # Verifica audience do token
    )
)
```

**⚠️ Importante:**
- Autenticação funciona **apenas em HTTP** (Streamable HTTP, SSE). Stdio não suporta.
- Se nenhum token verifier for setado, requisições sem `Authorization` passam (modo aberto).
- Requisições sem autenticação recebem HTTP 401 com endpoint de descoberta RFC 9728.

### 2.5 Filtro Dinâmico de Ferramentas por Sessão/Permissão

O SDK não oferece suporte **nativo** para filtrar `tools/list` por permissão. As soluções são:

#### A) Sobrescrever `list_tools()` em Subclasse

```python
from mcp.server import MCPServer
from mcp.server.auth.middleware.auth_context import get_access_token

class FilteredMCPServer(MCPServer):
    """Server que filtra tools por escopo do usuário."""
    
    async def list_tools(self) -> list:
        """Lista apenas tools que o usuário tem permissão."""
        token = get_access_token()
        all_tools = await super().list_tools()
        
        if not token:
            # Sem autenticação: retorna tools públicas
            return [t for t in all_tools if t.name in ["public_tool1"]]
        
        if "admin" in token.scopes:
            return all_tools  # Admin vê tudo
        
        # Usuário comum vê subset
        return [t for t in all_tools if not t.name.startswith("admin_")]
```

#### B) Middleware/Contexto por Requisição

Para filtrar com mais granularidade (multi-tenant, por time, etc.), use **middleware ASGI**:

```python
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from contextvars import ContextVar

user_context: ContextVar[dict] = ContextVar("user_context", default={})

class UserContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Extrai info do token no Authorization header
        auth_header = request.headers.get("Authorization", "")
        user_id = extract_user_id_from_bearer(auth_header)
        user_context.set({"user_id": user_id})
        return await call_next(request)

# Depois na tool:
@server.tool()
def user_operation() -> str:
    ctx = user_context.get()
    user_id = ctx.get("user_id")
    return f"Executado para {user_id}"
```

#### C) Proxy Filtering (Alternativa)

Se controle fino é crítico, use um **proxy MCP intermediário** (exemplo: projeto `mcp-filter` no GitHub) que filtra o upstream tool surface.

### 2.6 Tratamento de Erros

Tools podem sinalizar erros de duas formas:

#### A) Exceção `ToolError` (Recomendado)

```python
from mcp.server.exceptions import ToolError

@server.tool()
def divide(a: int, b: int) -> float:
    """Divide a por b."""
    if b == 0:
        raise ToolError("Divisão por zero não é permitida.")
    return a / b
```

A exceção é capturada automaticamente e retornada como `tool_error` no protocolo MCP.

#### B) CallToolResult com `is_error=True` (Controle Total)

```python
from mcp.types import CallToolResult, TextContent

@server.tool()
def risky_operation() -> CallToolResult:
    """Operação que pode falhar de formas diferentes."""
    try:
        result = do_something()
        return CallToolResult(
            content=[TextContent(type="text", text=f"Sucesso: {result}")]
        )
    except ValueError as e:
        # Retorna erro formatado, sem quebrar
        return CallToolResult(
            content=[TextContent(type="text", text=f"Erro de validação: {str(e)}")],
            is_error=True
        )
```

#### Exceções Não Capturadas

Se uma tool lançar uma exceção não prevista, o SDK:
1. A captura automaticamente
2. Retorna como erro MCP com mensagem sanitizada (para segurança, não expõe stacktraces ao LLM por padrão)
3. Não quebra o servidor

**Boas práticas:**
- Prefira `ToolError` para erros esperados
- Use `CallToolResult(is_error=True)` se precisar customizar a resposta
- Evite deixar erros não tratados escaparem; sempre capture e retorne graciosamente

### 2.7 Versão da Especificação MCP

O SDK v2.1.1 implementa a **especificação MCP 2026-07-28** (lançada em 28 de julho de 2026).

**Mudanças principais da especificação 2026-07-28:**
- **Remoção de handshake iniciais**: Protocol agora é stateless por padrão (inicialize mudou para per-request)
- **Multi-round-trip requests**: SEP-2322 permite requisições multi-passo mais complexas
- **Sessões client-side apenas**: Servidor não mantém estado de sessão (modelo stateless)
- **Extension framework**: Novo framework de extensões (SEP-2133) substitui capacidades fixas
- **Deprecações**: Roots, Sampling, Logging (setLevel) ainda funcionam mas são advertidas para protocolos antigos

**Retrocompatibilidade:**
O SDK é totalmente retrocompatível com servidores e clientes MCP 2024-11-05:
- Clientes negociam automaticamente downgrade para handshake legacy
- Servidores aceitam `initialize` requests de clientes antigos

---

## 3. APIs Depreciadas / Removidas (v1 → v2)

| Aspecto | v1 | v2 | Status |
|---|---|---|---|
| Nome do servidor | `FastMCP` | `MCPServer` | ❌ Removido |
| Naming de fields | `inputSchema`, `isError` | `input_schema`, `is_error` | ✅ Snake_case obrigatório |
| Transporte HTTP | Requer config extra | `mcp.run()` nativo | ✅ Simplificado |
| Handler pattern | Decoradores soltos | Métodos de classe | ✅ Mais organizado |
| Tipo de URL de recurso | `AnyUrl` (strict) | `str` (permite relativos) | ✅ Mais flexível |
| Dependencies | `httpx` | `httpx2` | ⚠️ Upgrade necessário |

---

## 4. Breaking Changes Recentes (2026-09)

1. **Renomeação FastMCP → MCPServer**: Afeta todo código v1
2. **Mudança de transporte padrão**: `mcp.run()` agora padrão é stateless HTTP
3. **Field naming**: Acesso a fields de Pydantic agora é `snake_case` apenas
4. **Handlers síncronos**: Executam em worker threads (não no event loop) — atenção com thread-safety

---

## 5. Referências e Recursos

- **Documentação Official**: [https://py.sdk.modelcontextprotocol.io/](https://py.sdk.modelcontextprotocol.io/)
- **GitHub Oficial**: [https://github.com/modelcontextprotocol/python-sdk](https://github.com/modelcontextprotocol/python-sdk)
- **Especificação MCP**: [https://modelcontextprotocol.io/docs/2026-07-28/](https://modelcontextprotocol.io/docs/2026-07-28/)
- **Tutorial Rápido (Weather Server)**: [https://modelcontextprotocol.io/docs/develop/build-server](https://modelcontextprotocol.io/docs/develop/build-server)
- **Migration Guide (v1 → v2)**: [https://py.sdk.modelcontextprotocol.io/migration/](https://py.sdk.modelcontextprotocol.io/migration/)
- **PyPI**: [https://pypi.org/project/mcp/](https://pypi.org/project/mcp/)
