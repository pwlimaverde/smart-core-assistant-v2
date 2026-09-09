# Plano Completo — Fase N13: Módulo `mcp_server` (servidor MCP para agentes de IA)

> **Reestruturado em 2026-09-06** a partir de
> `doc_dev/planejamento/29-modulo-mcp-agentes.md`, com a documentação atual de
> libs e da especificação MCP coletada em
> `.context/plans/n13-mcp-agentes/info_aux_n13-mcp-agentes.md`.
>
> **Objetivo:** servidor MCP que permite a agentes de IA externos configurar e
> operar o tenant do usuário, acelerando configuração e atendimento por delegação.
>
> **Limite inegociável:** o agente **nunca** pode fazer nada que o usuário dono do
> token não pudesse fazer sozinho no painel. Escopo de token é **subconjunto**,
> nunca superconjunto, dos escopos do emissor.
>
> **Regra transversal:** o `mcp_server` **não** fala com o banco. Toda leitura e
> escrita passa pelo `runtime_api` por gRPC — herdando autenticação, RLS e
> auditoria que já existem, sem duplicar uma linha de lógica de permissão.

---

## Correções aplicadas na reestruturação

Cada item abaixo mudou em relação ao plano de origem. Fonte entre colchetes.

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| **C1** | **`FastMCP` não existe mais.** O SDK `mcp` está na **v2.1.1** e a classe do servidor é **`MCPServer`**. O mecanismo que interessava (schema derivado de type hints + `pydantic.Field(description=…)` + docstring) permanece. | O plano prescrevia uma API removida. A justificativa de D1 sobrevive; o nome, não. | PyPI `mcp` 2.1.1 (verificado na sessão) |
| **C2** | **A spec MCP virou stateless** na revisão `2026-07-28`: "Stateless, self-contained requests", "MCP has no protocol-level session". | Confirma e torna obrigatório resolver o token **a cada requisição**. Elimina sticky sessions no Caddy e simplifica escala horizontal. | `modelcontextprotocol.io/specification/` |
| **C3** | **Filtrar `tools/list` por autorização é explicitamente conforme** — a spec cita o caso de uso literal. Acrescentados dois requisitos que o plano não tinha: **ordem determinística** e **`cacheScope` nunca `"public"`**. | O segundo é achado de **segurança**: com lista filtrada por token, cache público permitiria a um intermediário servir a superfície de um usuário a outro. | `/2026-07-28/server/tools` |
| **C4** | **Confirmação de ação destrutiva passa a usar MRTR/`elicitation/create`** (`resultType: "input_required"` + retry com `inputResponses`), com o argumento `confirmar` como **fallback**. | Upgrade real de segurança: elicitation coloca o **humano** no laço, não só o agente. Mas é capacidade **opcional do cliente**, então o fallback é obrigatório. | `/2026-07-28/server/tools` §Input Required |
| **C5** | **Bearer opaco é desvio `SHOULD` da spec de autorização**, não "conforme". Acrescentados à v1: endpoint `/.well-known/oauth-protected-resource` (RFC 9728) e `WWW-Authenticate` correto em 401/403. **E o ChatGPT sai do escopo da v1** — ele exige OAuth 2.1 e não aceita Bearer estático. | O plano prometia "Claude Desktop/Code, ChatGPT, Cursor". Três dos quatro funcionam; o ChatGPT não, e prometer o contrário seria falso. | `/2026-07-28/basic/authorization` + docs OpenAI |
| **C6** | **Negação por escopo, confirmação divergente e rate limit passam a ser erro de execução (`isError: true`)**, não erro de protocolo. | A spec: clients **SHOULD** entregar erros de execução ao modelo para auto-correção; erros de protocolo "are less likely to result in successful recovery". É o que faz o agente se corrigir em vez de travar. | `/2026-07-28/server/tools` §Error Handling |
| **C7** | **Rate limit deixa de ser zelo extra e vira requisito normativo.** | "Servers **MUST**: […] Rate limit tool invocations". | idem §Security Considerations |
| **C8** | **Paginação passa a usar o cursor do protocolo** (`params.cursor` → `result.nextCursor`), não convenção própria. | Interoperabilidade; o cliente já sabe paginar. | idem |
| **C9** | **Pisos de dependência fixados:** `pydantic>=2.12` (exigido pelo SDK), `grpcio>=1.82.1` (1.82.0 foi *yanked*), e o SDK arrasta `httpx2`, `starlette`, `uvicorn`, `sse-starlette`, `pyjwt[crypto]`, `opentelemetry-api`. | O `pyproject.toml` do `ia_engine` não serve como cópia direta. `httpx2` é major novo, não o `httpx` 0.x. | PyPI `mcp` 2.1.1 |
| **C10** | **Anotações de tool** (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) passam a ser **declaradas** — mas com nota explícita de que **não são barreira**. | A spec obriga o cliente a tratá-las como não confiáveis. Ajudam o cliente a pedir confirmação; não substituem nenhum guard do servidor. | `/2026-07-28/server/tools` |
| **C11** | **Fase renumerada de N10 para N13.** | N10 (IA analítica), N11 (operação/cadastros) e N12 (cutover) já estão canonizadas em `.context/plans/`. | `.context/plans/` |
| **C12** | **Aterramento de RBAC corrigido** (já refletido no doc 29): `exigir_escopo_tenant_admin` está **dentro** de `encaminhar_tenant:840`, então as 40 rotas `My*` exigem `tenant:admin` (rígido demais); a frouxidão está nos handlers operacionais manuais, que exigem só sessão. | O levantamento preliminar afirmava o inverso. Isso inverte metade de N13.3. | `runtime_api/src/grpc_web.rs` |
| **C13** | **`x-mcp-header` proibido neste servidor.** | A spec: "Server developers **SHOULD NOT** mark sensitive parameters (passwords, API keys, tokens, PII) with `x-mcp-header`" — e a maior parte dos nossos parâmetros identifica dado de tenant. | `/2026-07-28/server/tools` §x-mcp-header |
| **C14** | **Risco novo registrado:** sobreposição N13.3 ↔ N11, que também altera rotas do `runtime_api`. | Duas fases mexendo nas mesmas rotas em paralelo é conflito garantido se não for sequenciado. | `.context/plans/n11-operacao-cadastros.md` |
| **C15** | **O filtro de `tools/list` tem de ler o token do contextvar de autenticação**, não de um parâmetro: o handler interno `_handle_list_tools(ctx, params)` **não repassa** o `ctx` para `list_tools()`. Usar `get_access_token()` de `mcp.server.auth.middleware.auth_context`. | Sem isso, o filtro por escopo simplesmente não teria como saber quem está chamando — e a alternativa (sobrescrever `_handle_list_tools`) é API privada e frágil. Registrado também que esse handler ignora `params`, ou seja, a paginação protocolar de `tools/list` não está fiada (irrelevante na nossa escala). | Context7 `/websites/py_sdk_modelcontextprotocol_io_v2` |
| **C16** | **O texto do `ToolError` não pode conter PII.** O SDK loga `logger.info("Tool %r failed: %r", params.name, str(exc))` no caminho de erro de tool. | A mensagem "acionável para o agente" da §5.5 vai parar no log do processo. Nome de contato, telefone ou conteúdo de mensagem numa mensagem de erro viraria vazamento em log — exatamente o que o contrato de observabilidade proíbe. | idem |
| **C17** | **Parâmetros de transporte migraram do construtor para o `run()`** na v2 (`mcp.run(transport="streamable-http", host=…, port=…, json_response=…, stateless_http=True)`), e o app ASGI vem de `mcp.streamable_http_app()`. `stateless_http=True` é coerente com D7. | Código escrito no padrão v1 não sobe. | idem |

### Revisão de 2026-09-06 (segunda rodada) — troca do modelo de autenticação

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| **C18** | **O token opaco sai da v1. A autenticação passa a ser OAuth 2.1 com authorization server próprio.** Isso reverte a parte de D3 e **elimina** o `ExchangeMcpToken` como RPC público e a tabela `mcp_access_token` na forma anterior. | Descoberta que inverte a decisão: a **UI de conector do Claude** (web, desktop, mobile, Cowork) é **OAuth**; header/bearer estático só funciona em `claude mcp add --header`, no arquivo de config do Desktop e no `mcp.json` do Cursor. Com token opaco, ficaríamos de fora do conector do próprio Claude, do Claude web e do mobile — além do ChatGPT. O token opaco não era "Claude sim, GPT não": era "conector nenhum". | `support.claude.com` (custom connectors) + `developers.openai.com/apps-sdk/build/auth` |
| **C19** | **ChatGPT volta ao escopo, com conformidade e sem promessa de prazo.** | *"ChatGPT uses OAuth 2.1 flows exclusively"*; bearer estático não é aceito. Com OAuth conforme, ele passa a ser alcançável. Mas MCP no ChatGPT é Developer Mode/beta, então entra como validação, não como gate de entrega (decisão do responsável, 2026-09-06). | idem |
| **C20** | **A regra do subconjunto vira a tela de consentimento.** Em vez de o usuário escolher escopos ao cunhar um token, o consentimento OAuth só **oferece** os escopos que o usuário logado realmente possui. | Mesma garantia de segurança, UX melhor e menos superfície: não existe caminho de emissão em que se possa pedir escopo a mais. | decisão de desenho |
| **C21** | **A troca por um token interno deixa de ser conveniência e vira exigência normativa.** | *"If the MCP server makes requests to upstream APIs… The access token used at the upstream API is a separate token… The MCP server **MUST NOT** pass through the token it received from the MCP client."* O que era o `ExchangeMcpToken` continua existindo — como troca **interna** entre `mcp_server` e `control_plane`, não como RPC público. | `/2026-07-28/basic/authorization/security-considerations` |
| **C22** | **Risco novo: SSRF no fetch de Client ID Metadata Document.** O AS busca por HTTP um JSON numa URL controlada pelo cliente. | A spec manda considerar SSRF explicitamente, além de exigir validação exata de `redirect_uri`, aviso para `redirect_uri` só-localhost e exibição do hostname no consentimento. | idem |

---

## 0. Estado real (aterramento)

Verificado no código em 2026-09-06.

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Superfície de operações do tenant | `contracts/schemas/queries/admin.proto` | **87 RPCs** no `AdminService`, **37 `My*`**. | O MCP é uma **projeção** filtrada por permissão, não backend novo. |
| Envelope de identidade | `contracts/schemas/envelope.proto` campos 11–15 | `auth_user_id`, `auth_scopes`, `auth_is_superuser`, `flow_permissions`, `user_agent` — preenchidos **pelo `runtime_api`**; os `data_*` os consomem como verdade. | Base de **D2**: quem preenche o envelope define quem você é. |
| Gate dos `My*` | `runtime_api/src/grpc_web.rs:840` | `exigir_escopo_tenant_admin` **dentro** de `encaminhar_tenant` → as **40 chamadas** exigem `tenant:admin`. | **Rígido demais.** `manager`/`staff`/`viewer` não configuram nada. |
| Gate dos operacionais | `list_atendimentos:4138`, `get_thread:4276`, `enviar_midia_atendimento:4564`, `send_outbound_message:5075` | Só `exigir_autenticado_do_metadata`. | **Frouxo demais.** Um `viewer` envia mensagem a cliente final. |
| `flow_permissions` | `resolver_flow_permissions_web:434` | Resolvido em 6 handlers; **`send_outbound_message` não é um deles**. | Sai com o campo vazio no envelope. |
| RBAC nos repositórios | `infrastructure_postgres/src/security.rs` | `has_permission` existe, com **0 chamadas fora do próprio arquivo**. | Catálogo do doc 09 §3 documentado e não aplicado. |
| Credencial por usuário | `tenants_tenant.api_key`, `tenants_tenantconfig.api_keys` | A 1ª é do tenant inteiro; a 2ª guarda chaves de terceiros (AES-GCM-256). | **Token pessoal não existe.** Conceito novo. |
| Isolamento a copiar | `ia_engine/` | `uv`, `Dockerfile` com contexto na raiz, `scripts/gen_proto.py`, serviço no compose, imagem GHCR (`deploy-dev.yml:202`), job no CI (`ci.yml:236`) com ruff+mypy+pytest `--cov-fail-under=95`. | N13.4 replica — **exceto o `pyproject.toml`**, ver C9. |
| Última migration | `migrations/0029_metadados_midia.sql` | — | A tabela de grants entra como `0030_mcp_oauth_grant.sql`. |
| Borda | `docker/edge/Caddyfile` | Caddy ocupa 80/443 e roteia o site inteiro, incl. painel v1. `grafana.smartcoreassistant.com.br:152` é o padrão de subdomínio. | Config inválida derruba tudo. |
| Redes | `docker/dev/compose.yml:36` | `internal`, `observability`, `evolution_net`; `runtime_api:295` em `[internal, observability]`. | N13.4 cria `mcp_net`. |

---

## 1. Decisões travadas

**D1 — Stack: Python, SDK oficial `mcp` 2.1.1.** Mesmo padrão do `ia_engine`
(`uv`, hatchling, ruff, mypy, pytest, loguru, OpenTelemetry). A razão de fundo
permanece: o SDK Python é o de referência e deriva o `inputSchema` da tool de type
hints + `pydantic.Field(description=…)` + docstring — e a qualidade da descrição é
o que determina se o agente acerta de primeira. **Correção C1:** a classe é
`MCPServer`; `FastMCP` era a API da v1 e não existe mais. TypeScript foi descartado
(4ª linguagem no monorepo); Rust, por SDK mais novo, ergonomia pior para descrever
tools e por misturar serviço voltado para fora no workspace dos serviços internos.

**D2 — Caminho de dados: `MCP → runtime_api → data_postgres → Postgres`.**
O `mcp_server` não entra na rede `internal`, não tem `DATABASE_URL` e não fala com
`data_postgres`/`data_redis`/`data_storage`. Falar direto com o `data_postgres`
seria bypass total do RBAC: aquela camada **confia** nos campos 11–13 do envelope
em vez de verificá-los. O `runtime_api` é o único componente que cunha um envelope
confiável.

**D3 — Transporte: Streamable HTTP; autenticação: OAuth 2.1 com authorization
server próprio.** O `mcp_server` é o **resource server** em
`mcp.smartcoreassistant.com.br`; o **authorization server** vive no
`control_plane`, que já autentica usuário e emite JWT. Revisado em 2026-09-06
(C18): a versão anterior desta decisão usava Bearer opaco, o que teria excluído o
conector do Claude, o Claude web e o mobile, além do ChatGPT.

Isso é o que entrega a UX pedida: o usuário clica **Conectar** no cliente, abre o
navegador na nossa tela, faz login, vê o que está concedendo, aprova. **Não copia
configuração nenhuma.**

**D4 — Sem tokens de superusuário na v1.** Um token vazado alcança no máximo um
tenant. O superusuário segue no painel admin.

**D5 — RBAC fino só na superfície do MCP.** Varrer os 87 RPCs arriscaria quebrar
comportamento que o app Flutter assume.

**D6 — Superfície completa na v1, salvaguardas junto.** Envio a cliente final e
ações destrutivas entram na v1 (decisão do responsável, 2026-09-06), **com** as
salvaguardas da §5 como parte da entrega.

**D7 — Sem estado de sessão.** Decorrência de C2: o servidor é stateless, valida o
access token por requisição, e qualquer estado entre tools viaja como handle
explícito no argumento, nunca implícito na conexão.

**D8 (nova) — Dois tokens, nunca um.** O access token que o cliente MCP apresenta
tem audiência = o `mcp_server` e **não** é repassado ao `runtime_api`. O
`mcp_server` troca esse token por um **JWT interno de vida curta** junto ao
`control_plane` antes de chamar o backend. Exigência normativa (C21), não escolha.

### 1.1 Escopo

**Dentro:** N13.1 authorization server OAuth 2.1 · N13.2 grants e revogação ·
N13.3 RBAC fino na superfície exposta · N13.4 `mcp_server` como resource server ·
N13.5 tools de leitura/configuração · N13.6 tools de envio/destrutivas +
salvaguardas · N13.7 auditoria/traces/métricas · N13.8 tela Aplicativos conectados ·
N13.9 documentação.

**Clientes atendidos:** Claude web, Claude Desktop, Claude mobile, Cowork, Claude
Code, Cursor e **ChatGPT** — este último com **conformidade sim, garantia não**
(C19): implementamos o que a OpenAI exige e validamos, mas MCP no ChatGPT é
Developer Mode/beta e **não** entra como gate de entrega.

**Fora:**
- Tokens de superusuário (D4).
- RBAC fino fora da superfície do MCP (D5).
- **Credencial estática / token opaco** (C18). Se um dia houver demanda real de
  script ou CI, entra como caminho secundário — não na v1, para não manter duas
  superfícies de credencial e duas telas de revogação.
- **Dynamic Client Registration (RFC 7591)** — deprecado pela spec. Usamos CIMD.
- Modo stdio local (segundo empacotamento futuro sobre o mesmo núcleo de tools).
- Extensões MCP **Tasks**, **MCP Apps**, **Skills over MCP** — opt-in, fora da v1.
- `resources` e `prompts` do MCP: só `tools` na v1.
- Agente autônomo de operação do servidor (doc 28 §5).

---

## 2. Arquitetura

### 2.1 Fluxo de uma chamada

**Ligação (uma vez, por usuário e por cliente):**

```
Usuário clica "Conectar" no Claude / ChatGPT / Cursor
   │
   ├─▶ cliente chama POST /mcp sem token
   │      mcp_server responde 401 + WWW-Authenticate: Bearer resource_metadata="…"
   │
   ├─▶ cliente busca /.well-known/oauth-protected-resource   → descobre o AS
   ├─▶ cliente busca /.well-known/oauth-authorization-server → descobre endpoints + PKCE
   │
   ├─▶ navegador abre GET /oauth/authorize?client_id=<URL do CIMD>&resource=…
   │      &code_challenge=…&code_challenge_method=S256&redirect_uri=…&state=…
   │        · AS busca o CIMD do cliente e valida (client_id == URL, redirect_uri exato)
   │        · usuário faz LOGIN (fluxo que já existe)
   │        · TELA DE CONSENTIMENTO: mostra o nome do cliente, o hostname do
   │          redirect_uri, e SÓ os escopos que este usuário possui  ← regra do subconjunto
   │        · aprova → grava o grant → redirect com code + iss
   │
   └─▶ cliente troca code + code_verifier no POST /oauth/token
          → access token (aud = mcp.smartcoreassistant.com.br) + refresh token rotativo
```

**Operação (cada chamada de tool):**

```
Claude / ChatGPT / Cursor
        │  POST /mcp  (Streamable HTTP, Authorization: Bearer <access token>)
        ▼
   Caddy  (mcp.smartcoreassistant.com.br)
        │  preserva Authorization; SSE sem buffering
        ▼
   mcp_server  (Python, MCPServer)  ← RESOURCE SERVER
        │  1. valida o token: assinatura, issuer, EXPIRAÇÃO e AUDIÊNCIA
        │  2. troca por JWT interno junto ao control_plane   ← D8: nunca repassa
        │  3. filtra tools/list pelo escopo (contextvar, ordem determinística)
        │  4. valida args (pydantic) + guards (confirmação, dry_run, rate limit)
        ▼  gRPC (metadata: authorization=<JWT interno>, traceparent)
   runtime_api  →  data_postgres  →  Postgres
   (autentica, cunha envelope,      (RLS + trilha de auditoria)
    aplica escopo — §3)
```

### 2.2 Isolamento de rede (barreira física, não convenção)

Nova rede `mcp_net` no compose, com **apenas** `mcp_server` e `runtime_api`. O
`mcp_server` fica em `[mcp_net, observability]` — **nunca** em `internal`.
Consequência: dentro do container do MCP, os nomes `postgres`, `data_postgres`,
`data_redis` e `data_storage` **não resolvem**. D2 deixa de depender de disciplina
de código e vira topologia, verificável por teste.

### 2.3 Layout do módulo

```
mcp_server/
  pyproject.toml          # uv + hatchling — NÃO copiar o do ia_engine (ver C9)
  uv.lock                 # independente do ia_engine
  Dockerfile              # contexto na RAIZ do repo (stubs do .proto canônico)
  scripts/gen_proto.py    # grpc_tools.protoc com --pyi_out (mypy)
  README.md
  src/mcp_server/
    __init__.py
    server.py             # bootstrap MCPServer + Streamable HTTP (starlette/uvicorn)
    settings.py           # pydantic-settings
    telemetry.py          # OTel: traces + métricas
    healthcheck.py
    auth/
      token_verifier.py   # valida access token (iss/exp/aud) + troca por JWT interno
      scopes.py           # espelho do catálogo do doc 09 §3, testado contra ele
      challenges.py       # WWW-Authenticate 401/403 + metadata RFC 9728
    grpc/
      runtime_client.py   # cliente grpc.aio único do AdminService/AuthService
      contracts/          # stubs gerados (omitido da cobertura)
    tools/
      registry.py         # registro, escopo exigido, categoria, filtro de tools/list
      guards.py           # elicitation/confirmar, dry_run, rate limit
      fluxos.py  etapas.py  departamentos.py  atendentes.py
      treinamentos.py  intents.py  conexoes.py  config.py
      contatos.py  atendimentos.py  mensagens.py
  tests/
    unit/  integration/
```

### 2.4 Dependências (C9)

Runtime: `mcp==2.1.1` (arrasta `mcp-types`, `httpx2>=2.5.0`, `starlette`,
`uvicorn`, `sse-starlette`, `pyjwt[crypto]`, `opentelemetry-api>=1.28.0`,
`jsonschema`, `anyio`, `python-multipart`), `pydantic>=2.12`,
`pydantic-settings`, `grpcio>=1.82.1`, `grpcio-health-checking`, `protobuf`,
`loguru`, `opentelemetry-sdk` + `opentelemetry-exporter-otlp-proto-grpc` +
`opentelemetry-instrumentation-grpc`.

Dev: `grpcio-tools`, `pytest`, `pytest-asyncio`, `pytest-cov`, `ruff`, `mypy`.

Ruff: `line-length = 88`, `select = ["E","F","I","UP","B"]`, `target-version` do
Python do módulo. Cobertura omite `src/mcp_server/grpc/contracts/*`, `server.py`,
`settings.py`, `telemetry.py` — mesmo recorte do `ia_engine`.

---

## 3. Modelo de permissão

### 3.1 As duas metades a corrigir (N13.3)

| Família | Hoje | Problema | Correção (só na superfície do MCP) |
|---|---|---|---|
| 40 RPCs via `encaminhar_tenant` | `tenant:admin` para todos | **Rígido demais** — o agente de um `manager` não faria nada | Parametrizar `encaminhar_tenant` com o escopo exigido por rota, do catálogo do doc 09 §3. `tenant:admin` segue implicando todos |
| Handlers operacionais manuais | só `exigir_autenticado` | **Frouxo demais** — `viewer` envia mensagem a cliente | Exigir escopo explícito (`atendimentos:read`/`:write`, `clientes:read`) e resolver `flow_permissions` também em `send_outbound_message` |

Ambas valem para **todos** os clientes, inclusive o app Flutter — por isso N13.3
tem passo obrigatório de conferência contra o doc 27 e o `tenant_module`.

### 3.2 Duas barreiras (doc 09)

1. **No `mcp_server`** — falha rápido, com mensagem que **ensina o agente**.
   Em nível HTTP, quando a requisição inteira não tem escopo: `403` com
   `WWW-Authenticate: Bearer error="insufficient_scope", scope="…"`. Em nível de
   tool: erro de execução `isError: true` (C6). É ergonomia, não segurança.
2. **No `runtime_api`/repositório** — a barreira real, que não confia no cliente.
   Um `mcp_server` comprometido não ganha nada além do que o JWT já permite.

### 3.3 `tools/list` filtrado (C3)

Retorna **apenas** as tools que o token pode executar — caso de uso explicitamente
previsto pela spec. Requisitos adicionais:

- **Ordem determinística** entre chamadas com o mesmo conjunto de tools.
- **`cacheScope` nunca `"public"`.** Achado de segurança: a lista varia por token;
  cache público permitiria a um intermediário servir a superfície de um usuário a
  outro.
- `listChanged` declarado; `notifications/tools/list_changed` emitido quando os
  escopos do token mudarem (revogação, rebaixamento de role).

### 3.4 Anotações (C10)

Cada tool declara `annotations` coerentes com sua categoria — leitura
`readOnlyHint: true`; destrutiva `destructiveHint: true, idempotentHint: false`.
**Nota obrigatória no código:** a spec manda o cliente tratar anotações como não
confiáveis; elas melhoram a UX do cliente (pedir confirmação) e **não substituem
nenhum guard do servidor**.

---

## 4. Modelo de credencial — OAuth 2.1

### 4.0 O que já existe e o que é novo

**Já temos** (não refazer): `auth_user` global, argon2id, login, emissão de JWT com
`{sub, tenant_id, scopes, exp}` no `control_plane`, o catálogo de 14 escopos
(doc 09 §3), Redis para estado efêmero, e Caddy com TLS.

**É novo:** os endpoints OAuth, a tela de consentimento, o suporte a CIMD e o
registro de grants.

### 4.1 Documentos de descoberta

**No resource server** (`mcp_server`), RFC 9728 — a spec exige **ambos** os
mecanismos de descoberta (header e well-known):

```jsonc
// GET https://mcp.smartcoreassistant.com.br/.well-known/oauth-protected-resource
{
  "resource": "https://mcp.smartcoreassistant.com.br",
  "authorization_servers": ["https://auth.smartcoreassistant.com.br"],
  "scopes_supported": ["atendimentos:read", "clientes:read", "..."],
  "bearer_methods_supported": ["header"]
}
```

**No authorization server** (`control_plane`), RFC 8414:

```jsonc
// GET https://auth.smartcoreassistant.com.br/.well-known/oauth-authorization-server
{
  "issuer": "https://auth.smartcoreassistant.com.br",
  "authorization_endpoint": "https://auth.smartcoreassistant.com.br/oauth/authorize",
  "token_endpoint": "https://auth.smartcoreassistant.com.br/oauth/token",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],   // ← ausente = cliente MUST recusar
  "token_endpoint_auth_methods_supported": ["none"],
  "client_id_metadata_document_supported": true,  // ← dispensa DCR
  "authorization_response_iss_parameter_supported": true,
  "scopes_supported": ["...os 14 do doc 09 §3..."]
}
```

`code_challenge_methods_supported` é obrigatório: se ausente, **o cliente MUST
recusar prosseguir**. `issuer` no documento tem de bater exatamente com a URL de
onde foi buscado, senão o cliente rejeita.

### 4.2 Regra central — subconjunto, nunca superconjunto (agora no consentimento)

A tela de consentimento **só oferece os escopos que o usuário logado possui**. Um
`staff` não vê `tenant:admin` para marcar; não existe caminho em que se peça a
mais. O `scope` concedido é gravado no grant e re-interseccionado com os escopos
atuais do usuário **a cada emissão de access token** — se ele for rebaixado depois
de conectar, o token seguinte já sai reduzido.

Esta é a resposta direta ao requisito de origem: *"não correr o risco de um usuário
comum alterar dados do administrador"* — e agora ela é estrutural, não uma
validação que alguém pode esquecer de chamar.

### 4.3 Tabela `mcp_oauth_grant` (migration `0030`)

Substitui a `mcp_access_token` do desenho anterior. É o registro de "este usuário
autorizou este cliente", que alimenta a tela de revogação.

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | UUIDv7 |
| `tenant_id` | `uuid` NOT NULL FK | RLS como toda tabela por tenant |
| `user_id` | `int` NOT NULL FK `auth_user` | quem autorizou |
| `client_id` | `text` NOT NULL | URL do CIMD (é o identificador do cliente) |
| `client_name` | `text` NOT NULL | nome exibido, vindo do CIMD ("Claude") |
| `redirect_uri` | `text` NOT NULL | o exato usado, para a trilha |
| `scopes` | `jsonb` NOT NULL | escopos concedidos no consentimento |
| `refresh_token_hash` | `text` NULL | **argon2id**; rotacionado a cada uso |
| `last_used_at` | `timestamptz` NULL | atualizado de forma preguiçosa |
| `revoked_at` | `timestamptz` NULL | revogação soft, para a trilha sobreviver |
| `created_at` | `timestamptz` NOT NULL | |
| `created_ip` | `inet` NULL | |

RLS por `app.current_tenant`; FKs `ON DELETE CASCADE` de `tenants_tenant` e
`auth_user`; índice em `(user_id, client_id)`.

**Códigos de autorização** vivem no **Redis**, não no Postgres: TTL curto (~60s),
**uso único**, e carregam `code_challenge`, `redirect_uri`, `resource`, `scopes`,
`user_id`, `tenant_id`. Consumo é atômico (`GETDEL`), para que replay não funcione.

### 4.4 Emissão e validação de token

- **Access token:** JWT curto (~15 min) assinado pelo `control_plane`, com
  `aud` = `https://mcp.smartcoreassistant.com.br` (o `resource` da RFC 8707),
  `iss`, `exp`, `sub`, `tenant_id`, `scopes` e `grant_id`.
- **Refresh token:** opaco, hash argon2id no grant, **rotativo** — a spec exige
  rotação para clientes públicos. Reuso de um refresh já rotacionado invalida o
  grant inteiro (detecção de roubo).
- **Validação no `mcp_server`:** assinatura, `iss`, `exp` e **`aud`**. Token cuja
  audiência não seja este servidor é **rejeitado** — sem exceção, sem "passthrough".
- **Troca interna (D8):** validado o token, o `mcp_server` obtém do `control_plane`
  um **JWT interno** para falar com o `runtime_api`. O token do cliente **nunca**
  sai do `mcp_server`.

**Revogação:** revogar o grant no painel invalida o refresh imediatamente; o access
token em curso morre no `exp` (≤15 min). Essa é a janela real, e **precisa estar
escrita na tela** (N13.8) — é honestidade com o usuário, não detalhe.

### 4.5 Desafios `WWW-Authenticate`

- **401** sem token / token inválido/expirado:
  `WWW-Authenticate: Bearer resource_metadata="https://mcp.smartcoreassistant.com.br/.well-known/oauth-protected-resource", error="invalid_token"`
- **403** token válido, escopo insuficiente:
  `WWW-Authenticate: Bearer error="insufficient_scope", scope="<todos os escopos da operação>", resource_metadata="…"`
  A spec pede **todos** os escopos da operação em **um** desafio, não incremental.

### 4.6 Obrigações de segurança do AS (normativas)

Lista fechada, tirada da página de security considerations. Cada item vira teste:

1. **HTTPS** em todos os endpoints; `redirect_uri` só `localhost` ou HTTPS.
2. **PKCE S256** verificado no token endpoint; `code_challenge_methods_supported`
   publicado.
3. **`redirect_uri` validado por igualdade exata** contra o que o CIMD declara —
   nunca prefixo, nunca wildcard.
4. **`iss` na resposta de autorização** (RFC 9207), inclusive nas de erro.
5. **Audiência**: honrar o `resource` (RFC 8707) e emitir o token com o `aud`
   correspondente. O RS rejeita audiência alheia.
6. **Rotação de refresh token** para clientes públicos, com invalidação do grant
   ao detectar reuso.
7. **CIMD**: validar que `client_id` é idêntico à URL do documento; validar
   estrutura; cachear respeitando headers HTTP.
8. **SSRF no fetch do CIMD (C22)**: só HTTPS, bloquear IP privado/loopback/link-local
   e metadata de nuvem, limitar redirects, timeout curto e teto de tamanho de corpo.
9. **Consentimento**: exibir `client_name`, **o hostname do `redirect_uri`**, e
   aviso adicional quando o cliente declarar apenas `redirect_uri` de `localhost`.
10. **Código de autorização**: uso único, TTL curto, ligado ao `code_challenge` e
    ao `redirect_uri` da requisição original.

---

## 5. Superfície de tools e salvaguardas

### 5.1 Categorias

| Categoria | Exemplos | Escopo exigido | `annotations` | Salvaguardas |
|---|---|---|---|---|
| **Leitura** | `list_fluxos`, `list_atendimentos`, `get_thread`, `list_contatos`, `get_tenant_config`, `get_painel` | `*:read` correspondente | `readOnlyHint: true` | paginação por cursor do protocolo; teto de itens |
| **Configuração** | `create_fluxo`, `update_etapa`, `create_departamento`, `create_treinamento`, `update_tenant_config`, `set_bot_persona` | `*:write` / `configuracoes:write` | `readOnlyHint: false`, `destructiveHint: false` | `dry_run` |
| **Envio** | `send_message`, `send_media` | `atendimentos:write` | `destructiveHint: true`, `idempotentHint: false` | `dry_run` + **confirmação** (§5.2) + rate limit próprio |
| **Destrutivas** | `desativar_fluxo`, `desativar_atendente`, `remover_treinamento`, `delete_whatsapp_instance`, `revoke_invite` | `operacional:admin` / `tenant:admin` | `destructiveHint: true`, `idempotentHint: false` | `dry_run` + **confirmação** (§5.2) + rate limit próprio |

`get_tenant_config` **nunca** devolve `api_keys` descriptografadas — apenas quais
provedores estão configurados. Um agente externo não precisa da chave de outro
provedor, e o risco de ela cair no contexto de um LLM de terceiros é real.

**`x-mcp-header` não é usado em nenhuma tool** (C13).

### 5.2 Confirmação em dois níveis (C4)

**Nível 1 — MRTR / elicitation (preferido, humano no laço).** A tool responde ao
primeiro `tools/call` com:

```json
{
  "resultType": "input_required",
  "inputRequests": {
    "confirmar": {
      "method": "elicitation/create",
      "params": {
        "mode": "form",
        "message": "Confirma desativar o fluxo 'Funil de Vendas' (12 atendimentos ativos)?",
        "requestedSchema": {
          "type": "object",
          "properties": { "confirmado": { "type": "boolean" } },
          "required": ["confirmado"]
        }
      }
    }
  },
  "requestState": "<estado opaco assinado, TTL curto>"
}
```

O cliente pergunta **ao usuário** e repete o `tools/call` com `inputResponses` +
`requestState` e **`id` JSON-RPC diferente**. O `requestState` é assinado e
expira — não é canal de estado livre.

**Nível 2 — argumento `confirmar` (fallback obrigatório).** Elicitation é
capacidade **opcional** do cliente. Quando não negociada, a tool exige
`confirmar: str` preenchido com o **nome** do alvo, não o id:

```
desativar_fluxo(fluxo_id="…", confirmar="Funil de Vendas")
```

O servidor compara com o nome real e recusa se divergir — o que força o agente a
ter buscado o objeto antes; um id alucinado não passa, porque ele não teria o nome
para casar.

O nível 1 é estritamente melhor (aprovação humana explícita); o nível 2 garante que
a salvaguarda existe em todo cliente.

### 5.3 `dry_run`

Toda tool de escrita aceita `dry_run: bool = False`. Com `True`: valida, resolve o
alvo, descreve o efeito que teria sido produzido e **não escreve**. Auditado
(com `dry_run: true` no `context`), sem consumir o rate limit da categoria. É o que
permite ao agente confirmar com o humano antes de agir.

### 5.4 Rate limit por token (C7 — requisito normativo)

Por `token_id`, separado por categoria:

| Categoria | Teto |
|---|---|
| Leitura | 300 / min |
| Configuração | 60 / min |
| Envio | **10 / min, 100 / dia** |
| Destrutivas | **5 / min, 30 / dia** |

Estouro devolve **erro de execução** (`isError: true`) com o tempo de espera — o
agente entende e recua, em vez de martelar (C6). Incrementa
`smartcore_mcp_denied_total{motivo="rate_limit"}`, que é a métrica que revela um
agente em loop antes de o cliente perceber.

### 5.5 Qualidade da descrição (não é cosmético)

A docstring da tool vira a descrição no `inputSchema`; cada campo leva
`Annotated[T, Field(description=…)]`; enumerações são `Literal`, nunca `str`
livre; a descrição diz **o que faz, quando usar, quando NÃO usar** e o efeito
colateral no mundo real. Nomes de tool em `[A-Za-z0-9_.-]`, ≤128 chars, únicos.

Esse é o núcleo do requisito "documentar e dar as ferramentas": a descrição **é** a
interface, e uma descrição ruim produz um agente que erra com confiança.

---

## 6. Fases

### N13.1 — Authorization Server OAuth 2.1 no `control_plane`

É a fase de maior risco de segurança do plano inteiro: um AS caseiro mal feito é
pior que nenhum. A §4.6 é a lista fechada de obrigações e **cada item vira teste**.

**Tarefas**
1. Subdomínio `auth.smartcoreassistant.com.br` no Caddy + DNS, apontando para o
   `control_plane`. Validar o Caddyfile antes de recarregar.
2. `GET /.well-known/oauth-authorization-server` — metadata da §4.1, com
   `code_challenge_methods_supported: ["S256"]`,
   `client_id_metadata_document_supported: true`,
   `authorization_response_iss_parameter_supported: true`. `issuer` idêntico à URL.
3. **Suporte a CIMD:** buscar o documento na URL do `client_id`, validar que
   `client_id` == URL, validar estrutura e `redirect_uris`, cachear respeitando
   headers HTTP. **Guarda anti-SSRF (C22):** só HTTPS, bloqueio de
   loopback/privado/link-local e de endpoints de metadata de nuvem, teto de
   redirects, timeout curto e limite de tamanho de corpo.
4. `GET /oauth/authorize`: valida `client_id`/`redirect_uri`/`resource`/PKCE →
   exige login (fluxo existente) → **tela de consentimento** exibindo
   `client_name`, o **hostname do `redirect_uri`** e **apenas os escopos que o
   usuário possui** (§4.2), com aviso reforçado para `redirect_uri` só-localhost →
   grava o grant → redirect com `code` + `iss`.
5. Código de autorização no Redis: TTL ~60s, **uso único** por `GETDEL`, ligado a
   `code_challenge`, `redirect_uri` e `resource`.
6. `POST /oauth/token`: `authorization_code` com verificação **PKCE S256** e
   `refresh_token` **com rotação**; emite access token JWT (~15 min) com `aud` =
   `resource`; reuso de refresh rotacionado **invalida o grant inteiro**.
7. Interseção de escopos na emissão: `scopes` do grant ∩ escopos atuais do usuário.

**DoD**
- Um cliente MCP real (Claude Code, via `claude mcp add --transport http <url>`)
  completa o fluxo de ponta a ponta e passa a listar tools.
- **Testes de recusa, um por item da §4.6:** `redirect_uri` divergente por um
  caractere; PKCE ausente; `code_verifier` errado; código reutilizado; código
  expirado; refresh reutilizado após rotação (derruba o grant); CIMD com
  `client_id` ≠ URL; CIMD apontando para IP privado (SSRF).
- Metadata sem `code_challenge_methods_supported` faz cliente conforme recusar —
  verificar que o campo está publicado.
- `staff` **não vê** `tenant:admin` na tela de consentimento.
- Usuário rebaixado após conectar recebe access token com escopos reduzidos na
  renovação seguinte.

**Observabilidade & Auditoria**
- *(a)* Spans `oauth.authorize`, `oauth.consent`, `oauth.token`, `oauth.cimd_fetch`
  com `client_id`, `tenant_id`, `user_id`, resultado. `oauth.cimd_fetch` registra o
  host buscado — é o span que denuncia tentativa de SSRF.
- *(b)* `oauth.consentimento_concedido` (INFO, com `client_id`, `client_name` e
  escopos), `oauth.grant_revogado` (INFO), `oauth.consentimento_negado` (INFO),
  `oauth.refresh_reutilizado` (**WARN** — é sinal de roubo de token),
  `oauth.cimd_rejeitado` (WARN, com motivo). Concessão de permissão é evento
  crítico por 08 §4.2.
- *(c)* **Nunca** logar: `code`, `code_verifier`, refresh token, access token,
  nem o hash. `SecretString` no caminho Rust. O `state` do cliente é opaco e
  também não se loga.

---

### N13.2 — Grants e revogação

**Tarefas**
1. Migration `0030_mcp_oauth_grant.sql`: tabela da §4.3, RLS por
   `app.current_tenant`, índice `(user_id, client_id)`, FKs `ON DELETE CASCADE`.
2. Repositório em `infrastructure_postgres`: registrar consentimento, listar por
   usuário, revogar, rotacionar `refresh_token_hash`, marcar `last_used_at`.
   Reaproveita o utilitário argon2id já usado em senha.
3. RPCs no `AdminService`: `ListMcpGrants`, `RevokeMcpGrant`. Só sessão
   autenticada — cada usuário enxerga e revoga **apenas os próprios** grants.
4. Reconsentimento: se o cliente pedir escopos além dos já concedidos, o fluxo
   passa pelo consentimento de novo (step-up), nunca amplia em silêncio.

**DoD**
- Migration aplica e reverte.
- Teste de isolamento: dois usuários do mesmo tenant não enxergam nem revogam os
  grants um do outro.
- Revogar o grant invalida o refresh **imediatamente**; o access token em curso
  expira em ≤15 min — e esse número aparece na tela (N13.8).
- Nenhum refresh token em claro persiste em lugar nenhum.

**Observabilidade & Auditoria**
- *(a)* Repositório sob `run_in_tenant_transaction` + `#[instrument(skip_all)]`,
  com `tenant_id`, `user_id`, `grant_id`, `client_id`. Nunca o token nem o hash.
- *(b)* `mcp.grant_listado` não é auditado (leitura própria, ruído);
  `oauth.grant_revogado` é auditado em N13.1 e não se duplica aqui.
- *(c)* `client_name` vem do CIMD, ou seja, é **texto de terceiro** — tratar como
  não confiável: escapar na renderização da tela e limitar tamanho ao persistir.

---

### N13.3 — RBAC fino na superfície exposta

**Tarefas**
1. Parametrizar `encaminhar_tenant` com o escopo exigido por rota, substituindo o
   `exigir_escopo_tenant_admin` fixo de `grpc_web.rs:840`. Mapa rota→escopo
   derivado do doc 09 §3, em **um único lugar** declarativo e testável.
2. Acrescentar checagem de escopo aos handlers operacionais manuais (§3.1).
3. Resolver `flow_permissions` em `send_outbound_message` e nos demais handlers
   operacionais que hoje saem com o campo vazio.
4. Fazer os repositórios correspondentes chamarem `ctx.has_permission()` — hoje com
   zero chamadas fora de `security.rs` —, conforme o check-list do doc 09 §7.
5. **Conferência de regressão de UI:** cruzar o mapa de telas (doc 27) e o
   `tenant_module` para garantir que nenhuma tela em uso perde acesso. Passo
   obrigatório; é onde mora o risco da fase.

**DoD**
- Um `manager` edita fluxo (hoje não consegue).
- Um `viewer` **não** envia mensagem (hoje consegue).
- `flutter test` do `tenant_module` verde; suíte Rust verde.
- Tabela rota→escopo documentada no doc 09 e coberta por teste que **falha se uma
  rota nova entrar sem escopo declarado**.

**Observabilidade & Auditoria**
- *(a)* Nas rotas afetadas, o span passa a carregar o escopo exigido e, na negação,
  `error_code`. Sem `#[instrument(err)]` aqui: negação de permissão é resultado
  esperado, não falha de infra.
- *(b)* `permissao.negada` (WARN) com `event_type`, rota e escopo faltante —
  mudança de política de acesso é evento crítico por 08 §4.2. As rotas que já
  auditavam continuam auditando; nenhuma perde evento.
- *(c)* Ao negar, **não** logar o corpo do request (pode conter conteúdo de
  mensagem ou dado de contato).

---

### N13.4 — Skeleton do `mcp_server`

**Tarefas**
1. Criar `mcp_server/` no layout da §2.3, com as dependências da §2.4 — **sem
   copiar o `pyproject.toml` do `ia_engine`** (C9).
2. `scripts/gen_proto.py` gerando stubs de
   `contracts/schemas/queries/{admin,auth}.proto` com `--pyi_out` (mypy);
   `Dockerfile` com contexto na **raiz** do repo.
3. Servidor `MCPServer` em Streamable HTTP: app ASGI de `mcp.streamable_http_app()`
   servido por uvicorn, com os parâmetros de transporte no **`run()`** e não no
   construtor (C17), `stateless_http=True` (D7). Token lido **por requisição** via
   `get_access_token()` do contextvar de autenticação (C15). `healthcheck.py`.
4. **`TokenVerifier` como resource server:** valida assinatura, `iss`, `exp` e
   **`aud`** do access token; devolve um `AccessToken` com `scopes` efetivos e
   `claims` carregando `tenant_id`, `user_id`, `grant_id`. **Rejeita** token cuja
   audiência não seja este servidor — sem exceção.
5. **Troca interna (D8):** obtido o token do cliente, buscar do `control_plane` um
   JWT interno de vida curta para falar com o `runtime_api`. O token do cliente
   **nunca** é repassado adiante.
6. `/.well-known/oauth-protected-resource` (§4.1) + `WWW-Authenticate` de 401/403
   (§4.5) — a spec exige **os dois** mecanismos de descoberta.
7. Compose (`docker/{dev,prod}/compose.yml`): serviço `mcp_server`, rede
   **`mcp_net`** (§2.2), `[mcp_net, observability]`, `mem_limit` conservador,
   healthcheck, `MCP_RUNTIME_ENDPOINT` → `runtime_api:50051`.
8. CI: job `mcp_server` em `ci.yml` no molde do `ia_engine` (ruff + mypy + pytest
   com ratchet de cobertura); job `build-mcp-server` publicando
   `ghcr.io/…/smartcore-mcp-server` em `deploy-dev.yml`/`deploy-prod.yml`.
9. Caddy: bloco `mcp.smartcoreassistant.com.br`. Preservar `Authorization`; **não
   bufferizar SSE**; timeouts folgados para stream. **Validar antes de recarregar**
   (`caddy validate --config /etc/caddy/Caddyfile`) — a borda roteia o site
   inteiro, incluindo o painel v1 em produção. DNS do subdomínio antes do deploy.

**DoD**
- `mcp_server` sobe no compose e responde healthcheck.
- **Conexão real por conector**, não por config colada: o usuário adiciona
  `https://mcp.smartcoreassistant.com.br/mcp` no Claude, é levado ao login,
  consente e passa a ver as tools permitidas.
- Sem token: `401` + `WWW-Authenticate` com `resource_metadata`. Token de audiência
  alheia: **rejeitado** (teste explícito — é a defesa contra token passthrough).
- Escopo insuficiente: `403` + `WWW-Authenticate` com `error="insufficient_scope"`
  e todos os escopos da operação em um só desafio.
- O token do cliente **não** aparece em nenhuma chamada gRPC ao `runtime_api` —
  provado por teste sobre o metadata enviado.
- Ruff, mypy e pytest limpos no CI.
- Container **sem** rota para `postgres` — provado por teste de resolução de nome
  dentro do container.
- `caddy validate` verde e painel v1 intacto após o reload.

**Observabilidade & Auditoria**
- *(a)* OTel Python: span raiz por requisição HTTP, `service.name=mcp_server`,
  `deployment.environment` vindo de `OTEL_SERVICE_NAMESPACE`; `traceparent`
  extraído do cliente quando houver e **injetado** no metadata gRPC ao
  `runtime_api`, continuando o trace até o Postgres.
- *(b)* **Sem evento de auditoria** — é bootstrap de processo, não acesso a dado.
  Declarado intencionalmente.
- *(c)* Config por `pydantic-settings`; endpoint, segredo e token nunca em log de
  startup. Log estruturado JSON no stdout, coletado pelo promtail como os demais.

---

### N13.5 — Tools de leitura e configuração

**Tarefas**
1. `registry.py`: associa cada tool a escopo exigido, categoria e `annotations`;
   filtra `tools/list` pelos escopos do JWT corrente, em **ordem determinística**,
   com `cacheScope` **não público** (§3.3). O escopo é lido do **contextvar de
   autenticação** (`get_access_token()`), porque `_handle_list_tools` não repassa o
   `ctx` para `list_tools()` (C15) — **não** sobrescrever o handler privado.
2. Implementar as tools de leitura e configuração da §5.1 sobre os RPCs `My*`,
   com paginação pelo **cursor do protocolo** (C8).
3. Descrições no padrão da §5.5, com exemplo de uso em cada tool.
4. `dry_run` nas de configuração.
5. `outputSchema` nas tools cujo retorno é estruturado — se declarado, o retorno
   **MUST** conformar, então só onde o formato for estável.
6. Emitir `notifications/tools/list_changed` quando os escopos do token mudarem.
7. Testes: unitários por tool (cliente gRPC mockado) + integração contra o
   `runtime_api` real com tenant de fixture.

**DoD**
- **Teste de aceitação:** um agente, partindo de tenant vazio e só com o prompt
  *"configure um funil de vendas com 4 etapas e um departamento comercial"*,
  conclui a tarefa sem intervenção humana. Se falhar, o defeito está nas
  descrições, não no código.
- Token só-leitura **não enxerga** nenhuma tool de escrita em `tools/list`.
- Dois tokens de escopos diferentes recebem listas diferentes e determinísticas.

**Observabilidade & Auditoria**
- *(a)* Span `mcp.tool.<nome>` com `tool`, `token_id`, `tenant_id`, `dry_run`,
  `result`; erro de execução não vira span de erro de infra.
- *(b)* Config sensível já é evento crítico em 08 §4.2 (`configuracao.alterada`,
  `api_key.update`); agora com `source: "mcp"`, `token_id` e `tool` no `context`,
  para distinguir ação de agente de ação humana com um filtro só. Leitura de dado
  protegido também é auditada, conforme 08 §4.2.
- *(c)* **`get_tenant_config` nunca devolve `api_keys` descriptografadas.** Nome e
  telefone de contato **não** entram em log nem em span — só ids. Argumentos vão
  **sanitizados** para o `context` da auditoria.

---

### N13.6 — Tools de envio e destrutivas

**Tarefas**
1. `guards.py`: confirmação em dois níveis (§5.2 — elicitation com fallback por
   argumento), `dry_run` (§5.3), rate limit por `token_id` e categoria (§5.4).
2. `requestState` assinado, com TTL curto, para o retry do MRTR.
3. Implementar `send_message`, `send_media` e a família destrutiva.
4. Deadlines coerentes com o backend: `encaminhar_tenant` usa 30s (Evolution) e
   `send_outbound_message` usa 5s — o cliente gRPC do MCP não pode ser mais curto.
5. Testes de recusa: confirmação divergente, escopo insuficiente, estouro de rate
   limit, `requestState` expirado — cada um com asserção sobre a **mensagem**
   devolvida, que precisa ser acionável pelo agente.
6. Teste de que tool destrutiva **não aparece** no `tools/list` de token sem o
   escopo correspondente.

**DoD**
- Nenhuma escrita irreversível sem confirmação — por elicitation quando o cliente
  a oferece, por argumento casado com o nome do alvo quando não.
- `dry_run` nunca escreve — provado contra o banco.
- Rate limit de envio corta em 10/min e devolve `isError: true` com tempo de espera.
- Toda ação irreversível tem linha em `audit_log` com `source: "mcp"` e `token_id`.

**Observabilidade & Auditoria**
- *(a)* Span com `confirmado`, `confirmacao_via` (`elicitation`|`argumento`),
  `dry_run`, categoria e resultado. Negação por guard emite evento WARN com motivo.
- *(b)* **Toda** ação irreversível auditada: `mensagem.enviada`,
  `<entidade>.desativada`, `<entidade>.removida`, com timestamp UTC, `user_id`,
  `ip_address`, `user_agent`, `event_type`, e no `context`: `token_id`, `tool`,
  `confirmacao_via`, `dry_run`.
- *(c)* **Conteúdo da mensagem é PII — proibido em log, span, métrica e no
  `context` da auditoria.** Registrar apenas `atendimento_id` e o tamanho do
  conteúdo. Vale também para o `message` da elicitation: pode citar o **nome** do
  alvo, nunca o texto da mensagem a ser enviada.
  **E vale para o texto do `ToolError` (C16):** o SDK loga `str(exc)` no caminho de
  erro de tool, então a mensagem que ensina o agente carrega só nome de tool,
  escopo exigido e identificadores — **nunca** nome de contato, telefone ou trecho
  de mensagem. Teste de DoD: nenhuma mensagem de erro do catálogo contém PII.

---

### N13.7 — Auditoria, traces e métricas

**Tarefas**
1. Fechar a propagação de `traceparent` do `mcp_server` ao `runtime_api` e adiante.
2. Enriquecer a auditoria das rotas usadas pelo MCP com `source`, `token_id`,
   `tool`, `confirmacao_via` e `dry_run` no `context` — **sem tabela nova**,
   reaproveitando `AuditLogger` → `STREAM_SEGURANCA` → `audit_log`.
3. Métricas: `smartcore_mcp_tool_total{tool,result}`,
   `smartcore_mcp_tool_duration_ms{tool}`,
   `smartcore_mcp_denied_total{tool,motivo}`.
4. Painel Grafana `mcp_agentes.json`: chamadas por tool, latência, taxa de negação,
   aplicativos mais ativos (por `client_name`/`grant_id`, vindo da auditoria —
   **não** de label de métrica).
5. Regra de alerta: pico anômalo de negações ou de tools destrutivas por token — é
   a assinatura de token vazado ou agente em loop.

**DoD**
- Trace contínuo do cliente MCP ao Postgres, visível no Tempo.
- `QueryAuditLog` responde "o que o agente do fulano fez ontem" com **um** filtro.
- Painel preenchendo com dados reais.
- Alerta dispara em teste sintético e chega ao canal de e-mail já configurado.

**Observabilidade & Auditoria**
- *(a)* É a própria fase de instrumentação; o DoD é a validação ponta a ponta.
- *(b)* **Sem evento de auditoria próprio** — é a infraestrutura da trilha, não um
  acesso a dado. Declarado intencionalmente.
- *(c)* **Cardinalidade:** `token_id` **não** entra como label de métrica (explode
  a série temporal e é identificador). Fica na auditoria e no span. Atenção ao
  `add_metric_suffixes: false` já corrigido no `otel-collector-config.yml` — não
  reintroduzir sufixo duplicado no nome do histograma.

---

### N13.8 — Tela "Aplicativos conectados" no painel do tenant

Com OAuth, a tela deixa de ser uma fábrica de tokens e vira o que o usuário
realmente precisa: **ver o que está conectado e conseguir desconectar**.

**Tarefas**
1. Nova feature `integracoes` em `clients/modulos/tenant_module/lib/src/features/`,
   no padrão de `config`, `conexoes`, `usuarios`.
2. **Lista de aplicativos conectados**: `client_name`, hostname do `redirect_uri`,
   escopos concedidos em linguagem de negócio (não `atendimentos:write` cru),
   quando conectou, último uso, e botão **Desconectar**.
3. **Bloco "Conectar um agente"**: exibe a URL do servidor
   (`https://mcp.smartcoreassistant.com.br/mcp`) para colar no conector do
   Claude/ChatGPT, com o passo a passo por cliente vindo do `info_aux` §4. Não há
   token para copiar — o resto acontece no navegador.
4. Aviso honesto da janela de revogação: desconectar corta o refresh na hora, e o
   acesso em curso termina em até 15 min (§4.4).

**DoD**
- `flutter analyze` limpo.
- Teste de widget: lista vazia tem estado inicial que ensina a conectar;
  desconectar pede confirmação e some da lista.
- `client_name` vindo do CIMD é **escapado** na renderização — é texto de terceiro.
- Percurso completo contra o `runtime_api` real.

**Observabilidade & Auditoria**
- *(a)* Log de UI padrão do `tenant_module`; sem telemetria nova.
- *(b)* Herda `oauth.grant_revogado` de N13.1 — a auditoria é server-side.
- *(c)* Nenhum token trafega pela tela, o que elimina de uma vez a classe inteira
  de risco de "segredo copiado, colado e esquecido" do desenho anterior.

---

### N13.9 — Documentação

**Tarefas**
1. `mcp_server/README.md`: arquitetura, rodar local, gerar stubs.
2. Documento de uso para o cliente final: gerar o token, plugar em Claude
   Desktop/Code/Cursor, o que cada escopo libera, o que fazer se o token vazar.
3. Atualizar `06_modulo_integracoes.md` — hoje "Integrações" é só
   WhatsApp/Evolution; passa a ter uma segunda família.
4. Atualizar `09_diretrizes_permissoes_acesso.md` com a tabela rota→escopo de
   N13.3 e com a existência de credenciais não-interativas.
5. Atualizar `27-mapa-telas-rotas-v2.md` com a tela Integrações.

**DoD**
- Um usuário que nunca viu MCP conecta o Claude ao próprio tenant seguindo só a
  documentação, sem perguntar nada.

**Observabilidade & Auditoria**
- *(a)*, *(b)* **Sem evento de auditoria** — documentação não toca comportamento.
  Declarado intencionalmente.
- *(c)* Exemplos usam `<TOKEN>` como placeholder; **nenhum token real** em
  documento versionado.

---

## 7. SOLID / Ports & Adapters

- **Python:** cada tool é um caso de uso isolado (SRP). O acesso ao backend fica
  atrás de um único `RuntimeApiClient` (port) — trocar transporte não toca tool
  nenhuma. Os guards (confirmação, `dry_run`, rate limit) são **decoradores**
  aplicados no registro, não `if` espalhado dentro de cada tool.
- **Rust:** o mapa rota→escopo de N13.3 vive em **um** lugar declarativo, consultado
  por `encaminhar_tenant` e pelos handlers manuais — não replicado por rota.
- **Contratos:** o `.proto` canônico segue sendo a única fonte; o Python consome
  stubs gerados, nunca DTO escrito à mão.

---

## 8. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| **Agente envia mensagem errada a cliente real** — único efeito sem desfazer | Dano direto ao cliente do cliente | Confirmação em dois níveis (§5.2), com elicitation colocando o humano no laço; `dry_run`; rate limit 10/min; escopo `atendimentos:write`; auditoria com `token_id` |
| **N13.3 quebra tela em uso** | Regressão em produção | Conferência obrigatória contra doc 27 + `tenant_module`; suíte Flutter no DoD. A mudança em `encaminhar_tenant` **amplia** acesso; o risco concentra-se nos handlers operacionais, que **restringem** |
| **Conflito N13.3 ↔ N11** (C14) | Merge conflict e regressão cruzada | N11 também altera rotas do `runtime_api`. **Sequenciar:** N13.3 entra depois de N11 fechar, ou as duas dividem explicitamente o conjunto de rotas antes de começar |
| **`cacheScope: "public"` vaza superfície entre tenants** | Um usuário vê as tools de outro | Proibido por §3.3; teste que falha se `cacheScope` público for emitido |
| **AS caseiro mal implementado** — é a maior superfície de risco do plano | Escalada de privilégio, roubo de conta | §4.6 é lista fechada e **cada item vira teste de recusa** em N13.1; auditoria de segurança é agente designado da fase R; nada de "OAuth artesanal" fora do que a spec manda |
| **SSRF no fetch do CIMD** (C22) | Servidor usado para varrer a rede interna | Só HTTPS; bloqueio de loopback/privado/link-local e de metadata de nuvem; teto de redirects, timeout e tamanho de corpo; span `oauth.cimd_fetch` registra o host |
| **Token passthrough para o `runtime_api`** | Violação normativa e confusão de audiência | D8: troca obrigatória por JWT interno; teste sobre o metadata gRPC prova que o token do cliente não sai do `mcp_server` |
| **Roubo de refresh token** | Sessão persistente do atacante | Rotação obrigatória; reuso de refresh rotacionado **invalida o grant inteiro**; `oauth.refresh_reutilizado` em WARN é o sinal de detecção |
| **`client_name` do CIMD é texto de terceiro** | XSS/spoofing na tela de consentimento e no painel | Escapar na renderização, limitar tamanho, exibir sempre o **hostname do `redirect_uri`** junto — é ele que o usuário precisa reconhecer, não o nome |
| **Access token vazado** | Acesso ao tenant no escopo concedido | Vida curta (~15 min), audiência amarrada, revogação do grant corta o refresh na hora; alerta de anomalia (N13.7); D4 limita o alcance a um tenant |
| **MCP no ChatGPT é beta e pode mudar** | Retrabalho ou promessa quebrada | C19: conformidade sim, garantia não — não é gate de entrega |
| **`get_tenant_config` expõe chave de provedor ao LLM de terceiros** | Vazamento de segredo | A tool **nunca** devolve `api_keys` descriptografadas |
| **Descrição de tool ruim → agente erra com confiança** | Produto inutilizável na prática | §5.5 como requisito de DoD; o teste de aceitação de N13.5 é um agente real cumprindo tarefa real |
| **Agente em loop consome cota e martela o backend** | Custo e carga | Rate limit por categoria (requisito da spec); `smartcore_mcp_denied_total`; alerta de anomalia |
| **`mcp_server` ganha acesso ao banco por descuido futuro** | Bypass total do RBAC | Barreira topológica (`mcp_net`, §2.2) + teste que prova que `postgres` não resolve no container |
| **Caddy inválido derruba o painel v1 em produção** | Site inteiro fora | `caddy validate` antes de recarregar; DNS do subdomínio antes do deploy |
| **Spec MCP evolui rápido** (3 revisões em ~13 meses) | Retrabalho | Pinar a revisão implementada; `MCP-Protocol-Version` explícito; `doc_dev/libs/python/mcp.md` como ponto único de atualização |
| **`httpx2` conflita com dependência futura** | Build quebrado | `uv.lock` do módulo independente do `ia_engine`; imagens separadas |

---

## 9. Ordem de execução

```
N13.1 (auth server) ──▶ N13.2 (grants) ──▶ N13.4 (resource server) ──▶ N13.5 (tools leitura/config)
                                                  │                             │
N13.3 (RBAC fino) ────────────────────────────────┘                             ▼
   (após N11 — ver C14)                                              N13.6 (envio/destrutivas)
                                                                                │
N13.8 (UI) depende de N13.2 ────────────────────────────────────────▶ N13.7 (observabilidade)
                                                                                │
                                                                          N13.9 (docs)
```

**Primeiro corte utilizável:** N13.1 + N13.2 + N13.4 + N13.5 entregam o conector
funcionando de ponta a ponta — o usuário conecta pelo navegador e o agente lê e
configura o tenant.

N13.1 e N13.2 são fortemente acopladas (o consentimento é o que produz o grant) e
devem ser feitas juntas, não em sprints separadas.

N13.3 é pré-requisito de **qualidade**: sem ele, agentes de `manager`/`staff` não
configuram nada e os de `viewer` enviam mensagem. **Não entregar N13.6 antes de
N13.3.**

**Ponto de atenção de cronograma:** N13.1 agora carrega o maior risco e o maior
esforço do plano. Se a fase precisar ser cortada, o corte é em superfície de tools
(adiar N13.6), **nunca** em item da §4.6.

---

## 10. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N13** | OAuth 2.1 próprio + projeção MCP do `AdminService` | Aprovar as obrigações da §4.6, o schema `mcp_oauth_grant`, o mapa rota→escopo e o catálogo de tools | AS→grants→RBAC→resource server→tools→salvaguardas→observabilidade→UI→docs | Suíte Rust + `pytest` do `mcp_server` + `flutter test`; teste de aceitação com agente real | Agente configura tenant ponta-a-ponta; nenhuma escalada de escopo; toda ação auditada com origem `mcp` |

---

*Plano aterrado no `admin.proto` (87 RPCs), em `grpc_web.rs:832-840` e nos handlers
operacionais (leitura de 2026-09-06), no catálogo de escopos do doc 09 §3, no padrão
de isolamento do `ia_engine`, na especificação MCP `2026-07-28` e no SDK `mcp`
2.1.1 (ambos verificados na fonte primária), e nas decisões D1–D7.*
