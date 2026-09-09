# Documentação Auxiliar — Módulo `mcp_server` (Fase N13)

> Gerado em: 2026-09-06
> Plano canônico: `.context/plans/n13-mcp-agentes.md`
> Plano completo: `.context/plans/n13-mcp-agentes/plano_completo_n13-mcp-agentes.md`
> Plano de origem (histórico): `doc_dev/planejamento/29-modulo-mcp-agentes.md`
>
> **Nota de método:** o MCP `context7` **não estava autenticado** nesta sessão
> (sessão não interativa, OAuth impossível). A coleta de libs foi feita por
> WebSearch/WebFetch em fontes oficiais, e os pontos que mudam o desenho foram
> **reverificados diretamente na fonte primária** pela sessão principal (PyPI JSON
> API e `modelcontextprotocol.io/specification/2026-07-28/*`), porque os relatórios
> dos subagentes traziam alegações posteriores ao conhecimento base e com sinais de
> baixo aterramento. Tudo marcado **[VERIFICADO]** abaixo foi lido na fonte.

---

## 1. Especificação MCP — revisão `2026-07-28` **[VERIFICADO]**

Fonte: <https://modelcontextprotocol.io/specification/> e subpáginas
`/2026-07-28/server/tools`, `/2026-07-28/basic/authorization`.

### 1.1 Mudança estrutural: o protocolo virou **stateless**

O overview da spec declara, textualmente, como característica do protocolo base:

> * JSON-RPC message format
> * **Stateless, self-contained requests**
> * Per-request capability negotiation

E a seção "Stateful Tools" reforça:

> MCP has no protocol-level session, so a server cannot rely on implicit
> per-connection state to relate one tool call to the next.

**Consequência direta para o projeto:** não existe estado de sessão para pendurar
o JWT. A credencial é **entrada por requisição**. Isso valida — e torna obrigatório
— o desenho de validar o access token a cada chamada, e elimina a necessidade de
sticky sessions no Caddy.

### 1.2 `tools/list` filtrado por autorização é **explicitamente conforme**

Citação normativa da página de tools:

> Servers that declare the `tools` capability **MUST** respond to `tools/list`
> requests with the set of tools currently available to the requesting client.
> This set **MAY** be empty and **MAY** change over time […] but **MUST NOT** vary
> per-connection or as a side effect of other requests on the connection. **The set
> MAY vary by the authorization presented on the request — for example, returning
> only the tools the caller's granted scopes permit — since credentials are
> per-request input, not connection state.**

Ou seja: o filtro de `tools/list` por escopo do token não é gambiarra, é o padrão
previsto pela spec. Requisito adicional:

> Servers **SHOULD** return tools in a deterministic order.

### 1.3 Cache de `tools/list` — **armadilha de segurança**

A resposta de `tools/list` admite `ttlMs` e `cacheScope`:

```json
{ "result": { "resultType": "complete", "tools": [ … ],
              "nextCursor": null, "ttlMs": 300000, "cacheScope": "public" } }
```

Como a nossa lista **varia por token**, `cacheScope: "public"` permitiria a um
intermediário cachear a lista de um usuário e servi-la a outro — vazamento da
superfície de ferramentas entre tenants. **Nunca usar `cacheScope: "public"` neste
servidor.**

### 1.4 Multi Round-Trip Requests (MRTR) — confirmação com **humano** no laço

A spec define `InputRequiredResult`: o servidor pode responder a um `tools/call`
pedindo entrada adicional antes de concluir.

**Resposta do servidor:**

```json
{
  "jsonrpc": "2.0", "id": 2,
  "result": {
    "resultType": "input_required",
    "inputRequests": {
      "confirmar_desativacao": {
        "method": "elicitation/create",
        "params": {
          "mode": "form",
          "message": "Confirma desativar o fluxo 'Funil de Vendas'?",
          "requestedSchema": {
            "type": "object",
            "properties": { "confirmado": { "type": "boolean" } },
            "required": ["confirmado"]
          }
        }
      }
    },
    "requestState": "eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..."
  }
}
```

**Retry do cliente** (com `id` JSON-RPC **obrigatoriamente diferente**):

```json
{
  "jsonrpc": "2.0", "id": 3, "method": "tools/call",
  "params": {
    "name": "desativar_fluxo",
    "arguments": { "fluxo_id": "…" },
    "inputResponses": {
      "confirmar_desativacao": { "action": "accept", "content": { "confirmado": true } }
    },
    "requestState": "eyJsb2NhdGlvbiI6Ik5ldyBZb3JrIn0..."
  }
}
```

`Elicitation` é uma **capacidade do cliente** ("Clients may offer the following
features to servers: **Elicitation**"), negociada por requisição. Portanto **não é
garantida** — o servidor precisa de caminho alternativo quando o cliente não a
oferece.

### 1.5 Anotações de tool — hint, **não** controle de segurança

Campo `annotations` no Tool, com os hints `readOnlyHint`, `destructiveHint`,
`idempotentHint`, `openWorldHint`. Aviso normativo da própria spec:

> For trust & safety and security, clients **MUST** consider tool annotations to be
> untrusted unless they come from trusted servers.

Servem para o cliente decidir se auto-executa ou pede confirmação. **Não substituem
nenhuma barreira do servidor.**

### 1.6 Erros: `isError` vs. erro de protocolo

- **Protocol Errors** (JSON-RPC `error`): tool desconhecida, request malformado,
  erro do servidor. "Clients **MAY** provide protocol errors to language models,
  though these are less likely to result in successful recovery."
- **Tool Execution Errors** (`result.isError: true` + texto no `content`): falha de
  API, validação de entrada, **erro de regra de negócio**. "Clients **SHOULD**
  provide tool execution errors to language models to enable self-correction."

**Regra para o projeto:** negação por escopo, confirmação divergente e estouro de
rate limit são **erros de execução** (`isError: true`) com texto acionável — é o que
faz o agente corrigir sozinho em vez de travar.

### 1.7 Segurança — obrigações do servidor (normativo)

> Servers **MUST**: Validate all tool inputs · Implement proper access controls ·
> **Rate limit tool invocations** · Sanitize tool outputs

O rate limit da §7.4 do plano é **exigência da spec**, não zelo extra.

### 1.8 Outros pontos relevantes

- **Paginação** é protocolar: `params.cursor` → `result.nextCursor`. Usar isso nas
  tools de listagem, não paginação inventada.
- **`outputSchema`** é opcional; se declarado, "Servers **MUST** provide structured
  results that conform to this schema", devolvidos em `structuredContent`.
- **Nomes de tool**: 1–128 chars, `[A-Za-z0-9_.-]`, sem espaço, case-sensitive,
  únicos no servidor.
- **`x-mcp-header`**: espelha parâmetro de tool em header HTTP `Mcp-Param-*` para
  roteamento por intermediários. Aviso da spec: "Server developers **SHOULD NOT**
  mark sensitive parameters (passwords, API keys, tokens, PII) with `x-mcp-header`".
  **Não usar** neste servidor.
- **Extensões** opt-in negociadas: **Tasks** (execução assíncrona longa), **MCP
  Apps** (UI inline), **Skills over MCP**. Fora do escopo da v1.

---

## 2. Autorização MCP — o ponto que corrige o plano **[VERIFICADO]**

Fonte: <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>

### 2.1 O que a spec exige

> Authorization is **OPTIONAL** for MCP implementations. When supported:
> * Implementations using an HTTP-based transport **SHOULD** conform to this
>   specification.

Mas, **uma vez que se conforma**:

> 1. Authorization servers **MUST** implement OAuth 2.1 […]
> 4. **MCP servers MUST implement OAuth 2.0 Protected Resource Metadata
>    ([RFC9728])**. MCP clients **MUST** use OAuth 2.0 Protected Resource Metadata
>    for authorization server discovery.

E sobre tokens:

> MCP servers **MUST** validate that access tokens were issued specifically for them
> as the intended audience, according to RFC 8707 §2. […] MCP servers **MUST NOT**
> accept or transit any other tokens.

### 2.2 Leitura honesta para o projeto — **revisada em 2026-09-06**

> **Esta seção foi reescrita.** A primeira leitura concluía que o Bearer opaco
> atendia "3 dos 4 alvos". Isso estava **errado por omissão**: eu havia olhado só
> os clientes que leem arquivo de configuração local, não a **UI de conector**.

Cruzando com o suporte real dos clientes (§4), o quadro verdadeiro é:

| Caminho | Bearer estático | OAuth 2.1 |
|---|---|---|
| `claude mcp add --header` (Claude Code CLI) | ✅ | ✅ |
| `claude_desktop_config.json` (arquivo local) | ✅ | ✅ |
| `~/.cursor/mcp.json` (arquivo local) | ✅ | ✅ |
| **Conector do Claude** (web, Desktop, mobile, Cowork) | ❌ | ✅ |
| **ChatGPT** (Responses API / Developer Mode) | ❌ | ✅ |

Ou seja: o Bearer opaco não era "Claude sim, GPT não" — era **"conector nenhum"**.
Como Claude web e mobile só funcionam por conector, o token opaco excluiria boa
parte da própria base do Claude, além do ChatGPT.

**Decisão decorrente (2026-09-06):** a v1 usa **OAuth 2.1 com authorization server
próprio**; o token opaco sai do escopo. Ver C18–C22 no plano completo.

### 2.3 O que o AS próprio precisa entregar

Requisitos normativos, com as citações:

> 4. **MCP servers MUST implement OAuth 2.0 Protected Resource Metadata
>    ([RFC9728])**. MCP clients **MUST** use OAuth 2.0 Protected Resource Metadata
>    for authorization server discovery.

> MCP servers **MUST** validate that access tokens were issued specifically for
> them as the intended audience, according to RFC 8707 §2. […] MCP servers
> **MUST NOT** accept or transit any other tokens.

> If the MCP server makes requests to upstream APIs, it may act as an OAuth client
> to them. The access token used at the upstream API is a separate token, issued by
> the upstream authorization server. **The MCP server MUST NOT pass through the
> token it received from the MCP client.**

Esse último é o que transforma a troca por JWT interno de conveniência em
**obrigação** (D8 / C21).

**Registro de cliente:** a spec oferece três mecanismos e a ordem de preferência é
pré-registro → **CIMD** → DCR → pedir ao usuário. **Dynamic Client Registration
está deprecado** ("New implementations should use Client ID Metadata Documents
instead"). Com CIMD, o `client_id` **é** uma URL HTTPS que serve o JSON de
metadata; o AS busca, valida que `client_id` == URL e valida o `redirect_uri`.
Não há nada para armazenar — é mais simples que DCR. Anunciamos com
`"client_id_metadata_document_supported": true`.

**Obrigações de segurança** (página de security considerations), todas viradas em
teste na §4.6 do plano completo: HTTPS; `redirect_uri` só localhost ou HTTPS;
PKCE **S256** com `code_challenge_methods_supported` publicado (se ausente, o
cliente **MUST** recusar); `redirect_uri` validado por **igualdade exata**; `iss`
na resposta de autorização (RFC 9207, anti mix-up); rotação de refresh token para
clientes públicos; e cuidado com **SSRF** no fetch do CIMD, além de exibir o
hostname do `redirect_uri` no consentimento e avisar quando for só `localhost`.

### 2.4 Desafios `WWW-Authenticate`

**401 — sem token / token inválido:**

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer resource_metadata="https://mcp.smartcoreassistant.com.br/.well-known/oauth-protected-resource",
                         error="invalid_token"
```

**403 — token válido, escopo insuficiente** (é o código certo para a nossa
barreira 1, melhor que erro genérico):

```http
HTTP/1.1 403 Forbidden
WWW-Authenticate: Bearer error="insufficient_scope",
                         scope="configuracoes:write",
                         resource_metadata="https://mcp.smartcoreassistant.com.br/.well-known/oauth-protected-resource",
                         error_description="Edição de configuração do tenant"
```

Regra da spec sobre escopos no desafio:

> servers **SHOULD** include all scopes required for the current operation in a
> single challenge. Challenging incrementally […] degrades user experience.

E o `/.well-known/oauth-protected-resource` (RFC 9728) pode ser servido já
apontando para o futuro authorization server, deixando o caminho de OAuth aberto
sem implementá-lo agora.

---

## 3. Libs Python

### 3.1 `mcp` — SDK oficial Python **[VERIFICADO]**

Fonte: <https://pypi.org/pypi/mcp/json> · doc local:
`doc_dev/libs/python/mcp.md` (criado nesta reestruturação, 2026-09-06)

- **Versão:** `2.1.1`
- **Classe do servidor:** `MCPServer`. **`FastMCP` não existe mais** na v2 — foi a
  API da v1. O padrão de derivar o schema da tool a partir de type hints +
  `pydantic.Field(description=…)` + docstring **permanece**; só o nome da classe e
  o pattern de handler mudaram.
- **Dependências de runtime declaradas** (relevantes para o `pyproject.toml`):

  | Pacote | Restrição |
  |---|---|
  | `mcp-types` | `==2.1.1` (pareado com o SDK) |
  | `pydantic` | `>=2.12.0` |
  | `httpx2` | `>=2.5.0` — **major novo**, não é o `httpx` 0.x |
  | `starlette` | `>=0.27` (`>=0.48.0` em Python 3.14+) |
  | `uvicorn` | `>=0.31.1` |
  | `sse-starlette` | `>=3.0.0` |
  | `pyjwt[crypto]` | `>=2.10.1` |
  | `opentelemetry-api` | `>=1.28.0` |
  | `jsonschema` | `>=4.20.0` |
  | `anyio` | `>=4.9` (`>=4.10` em Python 3.14+) |
  | `python-multipart` | `>=0.0.9` |
  | `typing-extensions` / `typing-inspection` | `>=4.13.0` / `>=0.4.1` |

  Extras: `cli` (`typer`, `python-dotenv`), `rich`.

- **Ponto de atenção de dependência:** o SDK traz `httpx2`, `starlette`, `uvicorn`
  e `pyjwt` para dentro do módulo. Como o `mcp_server` é uma imagem separada do
  `ia_engine`, não há conflito de resolução entre os dois — mas o `uv.lock` do
  novo módulo é independente e não deve ser derivado do `ia_engine`.
- **Autenticação no SDK:** há `TokenVerifier` (interface de verificação de token)
  e acesso ao token autenticado dentro do handler. O SDK cobre o caminho de
  validação; a decisão de *o que* o token significa é nossa.
- **Filtro dinâmico de `tools/list`:** possível sobrescrevendo o handler de
  listagem / usando o contexto de requisição. Alinhado com §1.2 da spec.
- **Erros:** o SDK expõe erro de tool (`isError`) distinto de erro de protocolo,
  conforme §1.6.

#### API verificada via Context7 (índice `/websites/py_sdk_modelcontextprotocol_io_v2`)

O MCP `context7` foi instalado e autenticado em 2026-09-06, o que permitiu
reverificar as assinaturas contra o índice oficial da **v2**. O que segue é
literal da doc do SDK.

**Servidor e tool:**

```python
from mcp.server import MCPServer

mcp = MCPServer("Demo")

@mcp.tool()
def add(a: int, b: int) -> int:
    """Add two numbers."""   # ← a docstring vira a description da tool
    return a + b
```

**Transporte — mudou de lugar na v2:** parâmetros saíram do construtor e foram
para o `run()`.

```python
# v1 (não usar)
mcp = FastMCP("Demo", json_response=True, stateless_http=True)
mcp.run(transport="streamable-http")

# v2
mcp = MCPServer("Demo")
mcp.run(transport="streamable-http", host="0.0.0.0", port=9000,
        json_response=True, stateless_http=True)
```

**App ASGI para servir atrás do Caddy:**

```python
app = mcp.streamable_http_app()   # Starlette ASGI app, servida por uvicorn
```

`stateless_http=True` é coerente com **D7** e com o protocolo stateless.

**Token autenticado por requisição** — via contextvar, não parâmetro. Atenção ao
caminho de import, que é longo (o atalho `from mcp.server.auth import …` **não**
é o documentado):

```python
from mcp.server.auth.middleware.auth_context import get_access_token

token = get_access_token()      # None quando não autenticado
client_id = token.client_id if token else None
```

Da doc do SDK, sobre o objeto retornado:

> The `AccessToken` object returned by `get_access_token()` is the same object
> built by your verifier. It includes `client_id`, `scopes`, `subject`,
> `expires_at`, and any extra `claims`. This allows for **per-tool rules based on
> scopes, such as refusing access if required scopes are missing**. If the request
> is not an authenticated HTTP request, or if it's over `stdio` or in-memory,
> `get_access_token()` returns `None`.

**Encaixe direto no desenho:** o nosso `TokenVerifier` valida o access token
(assinatura, `iss`, `exp` e **`aud`** — §4.4 do plano completo) e devolve um
`AccessToken` com `scopes` = escopos efetivos e `subject`/`claims` carregando
`tenant_id`, `user_id` e `grant_id`. A partir daí, `get_access_token().scopes` é a **única**
fonte que o filtro de `tools/list` e os guards precisam consultar — não há estado
paralelo a manter, o que é coerente com D7.

**⚠️ `list_tools()` NÃO recebe o contexto da requisição.** O handler interno é:

```python
async def _handle_list_tools(
    self, ctx: ServerRequestContext[LifespanResultT], params: PaginatedRequestParams | None
) -> ListToolsResult:
    return ListToolsResult(tools=await self.list_tools())
```

O `ctx` existe no handler mas **não é repassado** para `list_tools()`. Portanto o
filtro por escopo (§1.2) **tem** de ler o token do **contextvar de autenticação**
(`get_access_token()`), que é acessível de qualquer ponto da mesma task — não de um
argumento. Sobrescrever `_handle_list_tools` é API privada e frágil; o caminho pelo
contextvar é o suportado.

Note também que `_handle_list_tools` **ignora `params`** — a paginação protocolar
de `tools/list` não está fiada. Irrelevante para nós (dezenas de tools, não
milhares), mas registrado.

**Erro de tool → `isError: true`** (confirma a correção C6):

```python
async def _handle_call_tool(self, ctx, params) -> CallToolResult | InputRequiredResult:
    try:
        return await self.call_tool(params.name, params.arguments or {}, context)
    except MCPError:
        raise                                   # → erro de PROTOCOLO (JSON-RPC error)
    except Exception as exc:
        if isinstance(exc, ToolError) and not isinstance(exc, UnexpectedToolError):
            ...
            logger.info("Tool %r failed: %r", params.name, str(exc))
        else:
            logger.exception("Tool %r raised an unexpected exception", params.name)
        return CallToolResult(content=[TextContent(type="text", text=str(exc))], is_error=True)
```

Mapeamento para o projeto: **negação de escopo, confirmação divergente e rate
limit → `raise ToolError(...)`**, que vira `isError: true` com o texto no
`content`. `MCPError` fica para erro de protocolo real.

O retorno `CallToolResult | InputRequiredResult` confirma que o SDK suporta o
MRTR/elicitation da §1.4 nativamente.

**⚠️ Achado de sanitização:** a linha
`logger.info("Tool %r failed: %r", params.name, str(exc))` **loga a mensagem do
`ToolError`**. Logo, o texto de erro que ensina o agente **não pode conter PII** —
nem nome de contato, nem telefone, nem conteúdo de mensagem. Só nome de tool,
escopo exigido e identificadores. (O SDK já é cuidadoso no caso de `ValidationError`:
loga **só os nomes dos campos**, com o comentário "the rejected values are the
caller's data" — mas o `str(exc)` do nosso `ToolError` é responsabilidade nossa.)

### 3.2 `pydantic`

Doc local atualizado nesta reestruturação: `doc_dev/libs/python/pydantic.md`
(2.7.1 → **2.13.5**, verificado 2026-09-06). `pydantic-settings` → 2.15.0.

Relevante para o plano:
- `Annotated[T, Field(description=…)]` e `Literal[…]` são o mecanismo pelo qual a
  descrição da tool chega ao agente — requisito central de N13.5.
- `model_json_schema()`, `WithJsonSchema`, `GenerateJsonSchema` para controlar o
  JSON Schema emitido (o `inputSchema` da tool).
- Breaking desde 2.7: `model_fields` em **instância** emite deprecation (usar na
  classe); `create_model()` mudou em 2.11; Python ≥3.9.
- O SDK `mcp` 2.1.1 exige `pydantic>=2.12.0` — o piso do módulo.

### 3.3 `grpcio` / `grpcio-tools`

Doc local atualizado: `doc_dev/libs/python/grpcio.md`
(1.62.1 → **1.83.1**, verificado 2026-09-06).

Relevante:
- `python -m grpc_tools.protoc` com `--pyi_out` para type hints dos stubs —
  necessário para o `mypy` passar no novo módulo.
- **`grpc.aio`**: canal assíncrono, `metadata` na chamada unária (é por onde vão
  `traceparent` e `authorization`), `timeout`/deadline por chamada.
- `grpcio-health-checking` para o healthcheck.
- **v1.82.0 foi yanked** do PyPI (issue #42906) — pinar `>=1.82.1`.
- Python ≥3.10 a partir das versões recentes.

### 3.4 Libs reaproveitadas da central (**USAR LOCAL**, sem Context7)

| Lib | Stack | Doc local | Última verificação |
|---|---|---|---|
| `opentelemetry` (Python) | python | `doc_dev/libs/python/opentelemetry.md` | 2026-07-06 |
| `loguru` | python | `doc_dev/libs/python/loguru.md` | 2026-05-31 |
| `pytest-cov` | python | `doc_dev/libs/python/pytest_cov.md` | 2026-07-20 |
| `argon2` (0.5.3) | rust | `doc_dev/libs/rust/argon2.md` | 2026-05-31 |
| `sqlx` (0.9.0) | rust | `doc_dev/libs/rust/sqlx.md` | 2026-06-10 |
| `tonic` (0.14.6) | rust | `doc_dev/libs/rust/tonic.md` | 2026-06-04 |
| `jsonwebtoken` (9.x) | rust | `doc_dev/libs/rust/jsonwebtoken.md` | 2026-06-02 |
| `secrecy` (0.10.3) | rust | `doc_dev/libs/rust/secrecy.md` | 2026-06-01 |
| `tracing` (0.1.40) | rust | `doc_dev/libs/rust/tracing.md` | 2026-05-31 |
| `flutter_bloc`, `go_router`, `flutter_secure_storage` | flutter | `doc_dev/libs/flutter/*.md` | — |

Nenhuma delas é usada de forma nova por este plano: `argon2` faz o hash do token
como já faz o de senha; `sqlx` faz a migration `0030` e o repositório; `tonic`
recebe o RPC novo no `AuthService`; `secrecy` protege o token em memória no lado
Rust; `jsonwebtoken` emite o JWT curto da troca.

---

## 4. Clientes — como o usuário final conecta

Coleta por subagente (WebSearch/WebFetch em docs oficiais). Os pontos que decidem
escopo (**ChatGPT exige OAuth**) foram cruzados com a §2 da spec.

### 4.1 Claude Desktop

Dois caminhos:

- **Connectors (UI):** Settings → Connectors → "Add Connector" → URL do servidor.
  Suporta OAuth Client ID/Secret em "Advanced settings".
- **Arquivo de configuração**, para servidor HTTP com header estático:

```json
{
  "mcpServers": {
    "smartcore": {
      "type": "http",
      "url": "https://mcp.smartcoreassistant.com.br/mcp",
      "headers": { "Authorization": "Bearer <TOKEN>" }
    }
  }
}
```

Suporta interpolação `${VAR}` / `${VAR:-default}`. Servidor precisa ser alcançável
pela internet pública.

### 4.2 Claude Code (CLI)

```bash
claude mcp add --transport http smartcore https://mcp.smartcoreassistant.com.br/mcp \
  --header "Authorization: Bearer <TOKEN>"
```

Flags: `-t/--transport` (http|sse|stdio|ws), `-H/--header` (repetível),
`-s/--scope` (local|project|user), `-e/--env`, `--client-id`, `--client-secret`,
`--callback-port`. Verificar com `claude mcp list` (`✔ Connected`).

### 4.3 Cursor

`~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "smartcore": {
      "url": "https://mcp.smartcoreassistant.com.br/mcp",
      "headers": { "Authorization": "Bearer ${env:SMARTCORE_MCP_TOKEN}" }
    }
  }
}
```

Interpolação `${env:VAR}` em `url`, `headers`, `env`, `command`, `args`. HTTPS
obrigatório. Token **não** deve ser hardcoded no arquivo.

### 4.4 ChatGPT — **restrição que corta escopo**

- MCP entra pela **Responses API** e pelo Developer Mode; é superfície beta.
- Campo `authorization` existe no bloco de configuração do servidor, mas a
  orientação oficial é **OAuth 2.1** (CIMD ou private_key_jwt).
- **Não suporta autenticação machine-to-machine** (client credentials, JWT bearer
  assertion), **não aceita API key customizada** nem mTLS.
- Exige HTTPS público e validação completa do token no servidor (assinatura,
  issuer, audience, expiry).

**Conclusão:** com token opaco estático, **o ChatGPT não conecta** — e, como se
viu na §4.5, o **conector do Claude também não**. Foi o que motivou a troca para
OAuth 2.1 (C18).

### 4.5 Conector do Claude — o que decidiu a arquitetura

Da doc oficial de custom connectors (`support.claude.com`):

- **Onde configura:** Pro/Max em *Customize → Connectors → + → Add custom
  connector*, informando a URL do servidor. Team/Enterprise: o owner adiciona em
  *Organization settings → Connectors* e cada membro autentica individualmente.
- **Autenticação:** **OAuth**. O usuário pode opcionalmente informar *OAuth Client
  ID* e *Client Secret* em configurações avançadas. **Bearer/header não é
  documentado nesse caminho.**
- **Superfícies:** Claude web (claude.ai), Desktop, Cowork e apps mobile — todas
  com o mesmo conector, porque *"the connection to your MCP server originates from
  Anthropic's servers, not from your machine's network interface"*.
- **Planos:** Free, Pro, Max, Team e Enterprise (Free limitado a 1 conector).

Duas consequências práticas: (1) o servidor **precisa ser alcançável pela internet
pública** — já é, via Caddy; (2) não há como usar token estático pelo conector,
que é justamente a UX pedida.

### 4.6 ChatGPT — requisitos confirmados

Da doc da OpenAI (`developers.openai.com/apps-sdk/build/auth`):

- *"anything that exposes customer-specific data or write actions should
  authenticate users"* — o nosso caso, inteiro.
- **Registro de cliente:** CIMD (preferido), DCR, ou cliente pré-definido.
- **Obrigatório implementar:** `/.well-known/oauth-protected-resource`; **PKCE
  S256**; eco do parâmetro `resource` por todo o fluxo; verificação de token a cada
  requisição (issuer, audience, expiração, escopos); desafios `WWW-Authenticate`
  no 401.
- **Token estático: não aceito.** *"ChatGPT uses OAuth 2.1 flows exclusively."*
- Superfície **Developer Mode / beta**.

### 4.7 Quadro-resumo (corrigido)

| Recurso | Conector Claude (web/desktop/mobile/Cowork) | Claude Code CLI | Cursor | ChatGPT |
|---|---|---|---|---|
| Servidor remoto HTTP | ✅ | ✅ | ✅ | ✅ (Responses API) |
| **Bearer estático** | ❌ | ✅ | ✅ | ❌ |
| **OAuth 2.1** | ✅ | ✅ | ✅ | ✅ (obrigatório) |
| HTTPS obrigatório | ✅ | ✅ | ✅ | ✅ |
| Maturidade | estável | estável | estável | beta |

**Só OAuth 2.1 aparece como ✅ na linha inteira.** É o que justifica C18.

---

## 5. Grupo C — Observabilidade e auditoria por etapa

Levantamento transversal exigido pela skill, cruzado com
`doc_dev/planejamento/05-observabilidade.md` e
`doc_dev/modelagem_dados/08_diretrizes_seguranca.md` §4 e §4.2.

| Etapa | Logs / spans (`tracing`) | `audit_log` | Risco de vazamento |
|---|---|---|---|
| **N13.1** Authorization server | Spans `oauth.authorize`, `oauth.consent`, `oauth.token`, `oauth.cimd_fetch` com `client_id`, `tenant_id`, `user_id`, resultado. O `oauth.cimd_fetch` registra o **host buscado** — é o span que denuncia tentativa de SSRF. | `oauth.consentimento_concedido` / `_negado`, `oauth.grant_revogado` (INFO); `oauth.refresh_reutilizado` (**WARN**, sinal de roubo); `oauth.cimd_rejeitado` (WARN, com motivo). Concessão de permissão é evento crítico por 08 §4.2. | **Nunca** logar `code`, `code_verifier`, refresh token, access token nem hashes; `SecretString` no Rust. O `state` do cliente é opaco e também não se loga. |
| **N13.2** Grants e revogação | Repositório sob `run_in_tenant_transaction` + `#[instrument(skip_all)]`, com `tenant_id`, `user_id`, `grant_id`, `client_id`. Nunca o refresh token nem o hash. | `oauth.grant_revogado` já é emitido em N13.1 e **não se duplica** aqui; listar os próprios grants não é auditado (leitura própria, viraria ruído). | `client_name` vem do CIMD, ou seja, é **texto de terceiro**: escapar na renderização e limitar tamanho ao persistir. |
| **N13.3** RBAC fino | Já existe `tracing` nas rotas; acrescentar `error_code` na negação e o escopo exigido no span. | `permissao.negada` (WARN) com `event_type`, rota e escopo faltante. Mudança de política de acesso é evento crítico. | Nenhum segredo novo. Cuidado para não logar o corpo do request ao negar. |
| **N13.4** Skeleton | OTel Python: span raiz por requisição HTTP; `service.name=mcp_server`; `traceparent` extraído do cliente (se houver) e **injetado** no metadata gRPC ao `runtime_api`. | **Sem evento de auditoria** — é bootstrap de processo, não acesso a dado. Declarado intencionalmente. | Config por `pydantic-settings`; endpoint e segredos nunca em log de startup. |
| **N13.5** Tools leitura/config | Span `mcp.tool.<nome>` com `tool`, `grant_id`, `tenant_id`, `dry_run`, `result`. | Config sensível → `configuracao.alterada` / `api_key.update` já previstos em 08 §4.2, agora com `source: "mcp"` e `grant_id` no `context`. | **`get_tenant_config` NUNCA devolve `api_keys` descriptografadas** — só quais provedores existem. Contato/telefone não entram em log nem em span. |
| **N13.6** Envio/destrutivas | Span com `confirmado`, `dry_run`, categoria e resultado. Negação por guard emite evento WARN com motivo. | **Toda** ação irreversível auditada: `mensagem.enviada`, `<entidade>.desativada`, `<entidade>.removida`, com `grant_id`, `tool`, `user_id`, `ip_address`, `user_agent`. | **Conteúdo da mensagem é PII — proibido em log, span, métrica e no `context` da auditoria.** Registrar só o `atendimento_id` e o tamanho. **E o texto do `ToolError` também não pode conter PII** — o SDK o loga (C16). |
| **N13.7** Observabilidade | Métricas `smartcore_mcp_tool_total{tool,result}`, `smartcore_mcp_tool_duration_ms{tool}`, `smartcore_mcp_denied_total{tool,motivo}`. Atenção ao `add_metric_suffixes: false` já corrigido no collector. | **Sem evento próprio** (é a infraestrutura da trilha, não um acesso). Declarado intencionalmente. | Cardinalidade: `grant_id` **não** entra como label de métrica (explode a série e é identificador). Fica só na auditoria e no span. |
| **N13.8** Tela Aplicativos conectados | Log de UI padrão do `tenant_module`; sem telemetria nova. | Herda `oauth.grant_revogado` de N13.1 — a auditoria é server-side. | **Nenhum token trafega pela tela**, o que elimina a classe inteira de risco de "segredo copiado, colado e esquecido". `client_name` é escapado na renderização. |
| **N13.9** Documentação | — | **Sem evento de auditoria.** | Exemplos de configuração usam `<TOKEN>` como placeholder, nunca um token real. |

**Política de instrumentação herdada:** `#[tracing::instrument(err)]` só onde todo
erro é falha real de infra; repositórios de tenant via `run_in_tenant_transaction`
+ `#[instrument(skip_all)]`. A trilha vai assíncrona pelo `transport::bus`
(`STREAM_SEGURANCA`) e é persistida pelo `data_postgres` — a `observability` não
depende do Postgres de forma síncrona.

---

## 6. Notas gerais / armadilhas

1. **`cacheScope` público vaza superfície entre tenants** (§1.3). Item de segurança,
   não de performance.
2. **Elicitation não é garantida** (§1.4): precisa de caminho alternativo por
   argumento de confirmação quando o cliente não a oferece.
3. **Anotações de tool são untrusted por contrato** (§1.5): nunca contar com
   `destructiveHint` como barreira.
4. **Rate limit é `MUST` da spec** (§1.7).
5. **Bearer opaco é desvio `SHOULD` da spec de autorização** (§2.2) e **exclui o
   ChatGPT** (§4.4).
6. **`httpx2` é dependência nova e major** trazida pelo SDK (§3.1) — não confundir
   com `httpx` 0.x; `uv.lock` do módulo é independente do `ia_engine`.
7. **grpcio 1.82.0 foi yanked** (§3.3) — pinar `>=1.82.1`.
8. **Paginação e erros seguem o protocolo** (§1.6, §1.8), não convenções próprias.
9. **Timeout de cliente**: operações de tool devem responder rápido; o caminho
   `SendOutboundMessage` já usa 5s de deadline no `runtime_api` e
   `encaminhar_tenant` usa 30s (por causa da Evolution) — o deadline do
   `mcp_server` precisa ser coerente com isso, não menor.
