# `mcp_server` — servidor MCP do Smart Core Assistant v2

Permite que um agente de IA externo (Claude web/Desktop/mobile/Cowork/Code,
Cursor, ChatGPT) configure e opere o tenant **em nome do usuário que autorizou**,
com as permissões desse usuário e nunca mais do que elas.

O usuário não copia token nenhum: clica **Conectar** no cliente, o navegador abre
na nossa tela de login, ele aprova o que está concedendo, e pronto.

---

## Os dois invariantes

**1. Este processo não alcança o banco.** Não tem `DATABASE_URL`, não está na
rede `internal`, e dentro do container os nomes `postgres`, `data_postgres` e
`data_redis` não resolvem. Toda leitura e escrita passa pelo `runtime_api` por
gRPC — herdando o interceptor de autenticação, a RLS do Postgres e a trilha de
auditoria que já existem, sem duplicar uma linha de lógica de permissão. A
barreira é a rede `mcp_net` do compose, não uma convenção de código, e há teste
provando que continua valendo.

**2. O token do cliente nunca é repassado.** O access token que o cliente MCP
apresenta tem `aud` = este servidor e é trocado por um **JWT interno** de vida
curta junto ao `control_plane` antes de qualquer chamada ao backend. É exigência
normativa da spec (*"The MCP server MUST NOT pass through the token it received
from the MCP client"*), não conveniência.

## Arquitetura

```
Claude / ChatGPT / Cursor
        │  POST /mcp   (Streamable HTTP, Authorization: Bearer <access token>)
        ▼
   Caddy  (mcp.smartcoreassistant.com.br)
        ▼
   mcp_server  ← RESOURCE SERVER (este módulo)
        │  1. valida o token: assinatura RS256, iss, exp e AUDIÊNCIA
        │  2. troca por JWT interno no control_plane      ← nunca repassa
        │  3. filtra tools/list pelo escopo do token
        │  4. valida argumentos + guards (escopo, confirmação, dry_run, rate limit)
        ▼  gRPC (metadata: authorization=<JWT interno>, traceparent)
   runtime_api  →  data_postgres  →  Postgres
```

O **authorization server** não está aqui: vive no `control_plane`
(`server/apps/control_plane/src/oauth/`), publicado em
`auth.smartcoreassistant.com.br`.

## Layout

```
src/mcp_server/
  server.py            bootstrap: MCPServer + Streamable HTTP
  settings.py          configuração por ambiente (pydantic-settings)
  telemetry.py         OTel: traces + métricas
  healthcheck.py       sonda do container
  auth/
    token_verifier.py  valida o access token; troca pelo JWT interno
    scopes.py          espelho do catálogo de 14 escopos (doc 09 §3)
  grpc/
    runtime_client.py  cliente único do AdminService
    contracts/         stubs gerados (gitignored)
  tools/
    registry.py        escopo por tool + filtro de tools/list
    guards.py          escopo, confirmação, dry_run, rate limit
    leitura.py  configuracao.py  envio.py  destrutivas.py
```

Não há `challenges.py` (o plano previa um). O SDK já monta o
`/.well-known/oauth-protected-resource` (RFC 9728) e o header
`WWW-Authenticate` com `resource_metadata` quando `AuthSettings.resource_server_url`
está preenchido — escrever os nossos duplicaria a implementação conformante e a
faria divergir dela na primeira atualização do SDK.

## Rodar local

```bash
uv sync --dev
uv run python scripts/gen_proto.py     # stubs a partir do .proto canônico
uv run pytest
uv run ruff check . && uv run mypy src/mcp_server
```

Os stubs são **gerados**, nunca escritos à mão: o `.proto` em
`server/crates/contracts/schemas/queries/` é a única fonte, compartilhada com o
Rust.

### Variáveis de ambiente

| Variável | Para que serve |
|---|---|
| `MCP_OAUTH_RESOURCE` | URL pública deste servidor. É o `aud` exigido em todo token |
| `MCP_OAUTH_ISSUER` | URL do authorization server (`auth.`) |
| `MCP_OAUTH_PUBLIC_KEY_PEM` | Chave **pública** RSA do AS. Só confere token; não emite |
| `MCP_SERVICE_SECRET` | Segredo de serviço da troca interna de token |
| `MCP_TOKEN_EXCHANGE_URL` | Endpoint da troca no `control_plane` |
| `MCP_RUNTIME_ENDPOINT` | gRPC do `runtime_api` (padrão `runtime_api:50051`) |
| `MCP_PORT` | Porta HTTP (padrão 8099) |

Não existe `DATABASE_URL` aqui, e não deve passar a existir.

## Superfície de tools

| Categoria | Escopo | Salvaguardas |
|---|---|---|
| Leitura | `*:read` | paginação por cursor, teto de itens |
| Configuração | `*:write` / `configuracoes:write` | `dry_run` |
| Envio | `atendimentos:write` | `dry_run` + confirmação + 10/min, 100/dia |
| Destrutivas | `operacional:admin` / `kanban:admin` / `tenant:admin` | `dry_run` + confirmação + 5/min, 30/dia |

`get_tenant_config` **nunca** devolve `api_keys` descriptografadas — apenas quais
provedores estão configurados. A chave de um provedor não tem por que entrar no
contexto de um LLM de terceiros.

### Confirmação em dois níveis

1. **Elicitation** (preferido): coloca o humano no laço. É capacidade
   **opcional** do cliente.
2. **Argumento `confirmar`** (garantido): a tool exige o **nome** do alvo, não o
   id. O agente só consegue preencher se tiver buscado o objeto antes — um id
   alucinado não passa, porque o modelo não teria de onde tirar o nome.

## Observabilidade

Span `mcp.tool.<nome>` por execução, com `tool`, `tenant_id`, `dry_run` e
resultado. Métricas `smartcore_mcp_tool_total{tool,result}`,
`smartcore_mcp_tool_duration_ms{tool}` e `smartcore_mcp_denied_total{tool,motivo}`.

`grant_id` **não** é label de métrica (explode a série temporal e é
identificador): ele vive na auditoria e no span.

**Nunca em log, span ou métrica:** token, refresh, hash, conteúdo de mensagem,
telefone ou nome de contato, chave de provedor. Vale também para o texto de
`ToolError` — o SDK loga `str(exc)` no caminho de erro de tool.
