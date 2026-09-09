# 29 — Módulo `mcp_server` (servidor MCP para agentes de IA)

> ## ⚠️ Documento histórico — a fonte da verdade mudou de lugar
>
> Este é o **plano-base**, preservado como registro do raciocínio inicial. Depois
> da reestruturação de 2026-09-06 (skill `plan-restructuring`), a verdade passou a
> ser:
>
> - **Canônico:** [`.context/plans/n13-mcp-agentes.md`](../../.context/plans/n13-mcp-agentes.md)
> - **Plano completo:** [`.context/plans/n13-mcp-agentes/plano_completo_n13-mcp-agentes.md`](../../.context/plans/n13-mcp-agentes/plano_completo_n13-mcp-agentes.md)
> - **Documentação auxiliar:** [`.context/plans/n13-mcp-agentes/info_aux_n13-mcp-agentes.md`](../../.context/plans/n13-mcp-agentes/info_aux_n13-mcp-agentes.md)
>
> **Duas coisas neste arquivo estão desatualizadas de propósito:**
>
> 1. **A numeração da fase.** Ela nasceu como N10, mas N10, N11 e N12 já estavam
>    ocupadas. A fase é **N13**; as sub-fases foram renumeradas no corpo, mas a
>    ordem delas mudou depois.
> 2. **A autenticação.** Este documento descreve **token opaco**
>    (`mcp_access_token` + `ExchangeMcpToken`). Isso foi **revertido**: a v1 usa
>    **OAuth 2.1 com authorization server próprio**, porque a UI de conector do
>    Claude (web, desktop, mobile, Cowork) é OAuth e o token estático só funciona
>    em arquivo de config local — o desenho original não entregaria conector
>    nenhum, nem no Claude, além de excluir o ChatGPT. Ver C18–C22 no plano
>    completo.
>
> O aterramento contra o código (§0) e a análise de RBAC (§0.1, §5.1) seguem
> válidos e foram transportados.

> **Status:** Plano de execução — criado em **2026-09-06**. Fase **N13** — as fases
> N10 (IA analítica), N11 (operação/cadastros) e N12 (cutover) já estão canonizadas
> em `.context/plans/`. **Independente das três:** o MCP projeta contratos que já
> existem, então não bloqueia nem é bloqueado por elas. A única sobreposição real é
> N13.3 ↔ N11, que também mexe em rotas do `runtime_api` — ver §18.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** entregar um **servidor MCP (Model Context Protocol)** que permite a
> agentes de IA externos — Claude Desktop/Code, ChatGPT, Cursor — configurar e operar
> o tenant do usuário, acelerando configuração e atendimento por delegação.
> **Limite inegociável:** o agente **nunca** pode fazer nada que o usuário dono do
> token não pudesse fazer sozinho no painel. Escopo de token é **subconjunto**, nunca
> superconjunto, dos escopos do emissor.
> **Regra transversal:** o `mcp_server` **não** fala com o banco. Toda leitura e
> escrita passa pelo `runtime_api` por gRPC — herdando autenticação, RLS e auditoria
> que já existem, sem duplicar uma linha de lógica de permissão.

---

## 0. Estado real (aterramento)

Tudo nesta tabela foi verificado no código em 2026-09-06, não presumido.

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Superfície de operações do tenant | `server/crates/contracts/schemas/queries/admin.proto` | **87 RPCs** no `AdminService`, dos quais **37 são `My*`** (fluxos, etapas, departamentos, atendentes, treinamentos, intents, instâncias WhatsApp, config, onboarding, painel). | O MCP é uma **projeção** desse contrato, não um backend novo. N13.5/N13.6 mapeiam tools 1:1 sobre RPCs existentes. |
| Envelope de identidade | `contracts/schemas/envelope.proto` campos 11–15 | `auth_user_id`, `auth_scopes`, `auth_is_superuser`, `flow_permissions`, `user_agent`. Preenchidos **pelo `runtime_api`**; os `data_*` os consomem como verdade. | Base do **D2**: quem preenche o envelope define quem você é. Só o `runtime_api` pode fazê-lo. |
| Gate dos RPCs `My*` | `runtime_api/src/grpc_web.rs:840`, dentro de `encaminhar_tenant` | `exigir_escopo_tenant_admin(&claims)?` roda **incondicionalmente** para as **40 chamadas** de `encaminhar_tenant`. | **Fechado demais:** um `manager`/`staff`/`viewer` não alcança **nenhum** RPC de configuração. Ver §5.1. |
| Gate dos RPCs operacionais | handlers manuais: `list_atendimentos:4138`, `get_thread:4276`, `enviar_midia_atendimento:4564`, `send_outbound_message:5075` | Exigem **apenas `exigir_autenticado_do_metadata`** — nenhuma checagem de escopo. | **Aberto demais:** hoje qualquer usuário autenticado, inclusive `viewer`, envia mensagem a cliente final. Ver §5.1. |
| `flow_permissions` no envelope | `resolver_flow_permissions_web:434` | Resolvido em **6** handlers (4160, 4458, 4579, 4652, 4736, 4989). **`send_outbound_message` não é um deles** — sai com o campo vazio. | N13.3 fecha essa lacuna nos RPCs que o MCP expõe. |
| RBAC fino nos repositórios | `infrastructure_postgres/src/security.rs` | `RequestContext::has_permission` existe e é testado, mas há **0 chamadas fora do próprio `security.rs`**. | O catálogo do doc 09 §3 está **documentado e não aplicado**. N13.3 o aplica na superfície exposta. |
| Catálogo de escopos | `modelagem_dados/09_diretrizes_permissoes_acesso.md` §3 | 14 escopos canônicos + mapeamento role→escopo no `control_plane` na emissão do JWT. | Fonte de verdade das tools. **Nenhum escopo novo será inventado.** |
| Credencial por usuário | `tenants_tenant.api_key`, `tenants_tenantconfig.api_keys` | A primeira é do **tenant inteiro**; a segunda guarda chaves de provedores terceiros (AES-GCM-256). | **Não existe token pessoal.** Conceito novo — N13.1. |
| Modelo de isolamento a copiar | `ia_engine/` | Pasta na raiz, `pyproject.toml` com `uv`, `Dockerfile` com contexto na raiz gerando stubs do `.proto` canônico (`scripts/gen_proto.py`), serviço próprio no compose, imagem `smartcore-ia-engine` no GHCR (`deploy-dev.yml:202`), job próprio no CI (`ci.yml:236`) com ruff + mypy + pytest `--cov-fail-under=95`. | N13.4 replica o padrão inteiro. |
| Última migration | `infrastructure_postgres/migrations/0029_metadados_midia.sql` | — | A tabela de token entra como **`0030_mcp_access_token.sql`**. |
| Borda | `docker/edge/Caddyfile` | Caddy ocupa 80/443 e roteia o site inteiro, incluindo o painel v1 em produção. `grafana.smartcoreassistant.com.br:152` é o padrão de subdomínio simples. | N13.4 acrescenta `mcp.smartcoreassistant.com.br`. **Config inválida derruba tudo** — validar antes de recarregar. |
| Redes do compose | `docker/dev/compose.yml:36` | `internal`, `observability`, `evolution_net`. `runtime_api:295` está em `[internal, observability]`. | N13.4 cria **`mcp_net`**, para que o `mcp_server` alcance o `runtime_api` **sem** alcançar `postgres`/`data_postgres`/`redis`. Ver §4.2. |

> **Conclusão do aterramento:** o trabalho de backend do MCP é pequeno — a superfície
> já existe e a porta de entrada já autentica. O trabalho real está em (a) inventar a
> credencial por usuário, que não existe; (b) **corrigir o RBAC dos RPCs que o MCP vai
> expor**, hoje simultaneamente rígido demais na configuração e frouxo demais na
> operação; e (c) descrever as tools bem o bastante para o agente acertar de primeira.

### 0.1 Correção ao levantamento preliminar

O prompt que originou este plano afirmava que "qualquer `TenantUser` autenticado
alcança a maior parte dos `My*`". **É o inverso.** A leitura de
`grpc_web.rs:832-840` mostra `exigir_escopo_tenant_admin` **dentro** de
`encaminhar_tenant`, logo todas as 40 rotas que passam por ele exigem
`tenant:admin`. A frouxidão real está na **outra** família — os handlers
operacionais escritos à mão, que exigem só sessão válida. As duas metades da §5.1
existem por causa dessa correção.

---

## 1. Escopo

### Dentro do escopo

- **N13.1** Credencial: migration `0030`, RLS, RPCs de gestão de token.
- **N13.2** `ExchangeMcpToken` — troca do token opaco por JWT de vida curta.
- **N13.3** RBAC fino **na superfície exposta pelo MCP** (§5.1).
- **N13.4** Skeleton do `mcp_server` (Python + FastMCP, Docker, compose, CI, Caddy).
- **N13.5** Catálogo de tools — leitura e configuração.
- **N13.6** Tools de envio e destrutivas + salvaguardas.
- **N13.7** Auditoria com origem `mcp`, traces e métricas por tool.
- **N13.8** Tela **Integrações** no painel do tenant (`tenant_module`).
- **N13.9** Documentação de uso para o cliente final.

### Fora do escopo

- **Tokens de superusuário** (D4). Só usuários de tenant na v1.
- **Enforcement fino do RBAC fora da superfície do MCP** (D5) — os demais RPCs do
  `AdminService` ficam como estão; fechar a dívida inteira do doc 09 é fase própria.
- **OAuth 2.1 do MCP.** A v1 usa token opaco de vida longa. OAuth entra quando
  houver demanda de integrador terceiro.
- **Modo stdio local.** Pode virar um segundo empacotamento depois, reaproveitando
  o mesmo núcleo de tools.
- **Agente autônomo de operação do servidor** (doc 28 §5) — outro assunto, outro
  risco, outra sessão.
- **Elicitation / sampling / resources do MCP.** Só `tools` na v1.

---

## 2. Decisões travadas

**D1 — Stack: Python.** Mesmo padrão do `ia_engine` (`uv`, hatchling, ruff, mypy,
pytest, loguru, OpenTelemetry). Razão além da simetria: o SDK oficial MCP em Python
é o de referência, e o `FastMCP` deriva o schema da tool de tipos Pydantic. A
qualidade da descrição da tool é o que determina se o agente acerta de primeira — é
o requisito central de "documentar e dar as ferramentas". TypeScript foi descartado
por introduzir uma 4ª linguagem no monorepo; Rust, por SDK MCP mais novo e ergonomia
pior para descrever tools, além de misturar um serviço voltado para fora no
workspace dos serviços internos.

**D2 — Caminho de dados: `MCP → runtime_api → data_postgres → Postgres`.**
O `mcp_server` **não** entra na rede `internal`, **não** tem `DATABASE_URL`, e
**não** fala com `data_postgres`, `data_redis` ou `data_storage`. Falar direto com o
`data_postgres` seria bypass total do RBAC: aquela camada **confia** nos campos 11–13
do envelope em vez de verificá-los, então um cliente que os preenche declara as
próprias permissões. O `runtime_api` é o único componente que cunha um envelope
confiável, e é por ele que o MCP entra — exatamente como o app Flutter.

**D3 — Transporte: Streamable HTTP com token.** Servidor hospedado no VPS, exposto
em `mcp.smartcoreassistant.com.br` pelo Caddy da borda, com `Authorization: Bearer`.
O usuário cola URL + token na configuração do Claude/GPT: nada a instalar na máquina
dele, revogação imediata e centralizada, versão sempre atualizada.

**D4 — Sem tokens de superusuário na v1.** Um token vazado alcança no máximo um
tenant. O superusuário segue operando pelo painel admin. Reavaliar quando a trilha de
auditoria do MCP tiver rodagem real.

**D5 — RBAC fino só na superfície do MCP.** Validação de escopo específico apenas nos
RPCs que o MCP expõe. Misturar isso com uma varredura em todos os 87 RPCs arrisca
quebrar comportamento que o app Flutter hoje assume.

**D6 — Superfície completa na v1, salvaguardas junto.** Envio a cliente final e ações
destrutivas entram na v1 (decisão do responsável, 2026-09-06), **com** as salvaguardas
da §7 tratadas como parte da entrega, nunca como refinamento posterior.

---

## 3. Contrato de observabilidade (DoD transversal)

- **Auditoria:** toda execução de tool grava em `audit_log` via o caminho que já
  existe (`observability::AuditLogger` → `STREAM_SEGURANCA` →
  `processar_eventos_auditoria_lote`), com `context` marcando `source: "mcp"`,
  `token_id`, `tool`, `dry_run` e argumentos **sanitizados**. Ação de agente precisa
  ser distinguível de ação humana na trilha, sem consulta cruzada.
- **Telemetria:** o `mcp_server` abre um span por tool (`mcp.tool.<nome>`) e injeta
  `traceparent` W3C no metadata gRPC da chamada ao `runtime_api`, continuando o trace
  até o Postgres — mesmo mecanismo do `ia_engine`. Validável no Tempo.
- **Métricas:** `smartcore_mcp_tool_total{tool,result}`,
  `smartcore_mcp_tool_duration_ms{tool}` e
  `smartcore_mcp_denied_total{tool,motivo}` pelo pipeline OTLP existente.
  Atenção ao `add_metric_suffixes: false` já corrigido no `otel-collector-config.yml`
  — não reintroduzir sufixo duplicado no nome do histograma.
- **Sanitização — proibido logar:** conteúdo de mensagem, PII de contato, token em
  claro (nem prefixo além dos 8 primeiros caracteres), chave de provedor, prompt
  completo. Regra herdada do contrato do `ia_engine` (doc 17 §2).
- **Healthcheck:** módulo `mcp_server.healthcheck` no padrão do `ia_engine`, usado
  pelo `healthcheck:` do compose.

---

## 4. Arquitetura

### 4.1 Fluxo de uma chamada

```
Claude/GPT ──Streamable HTTP + Bearer──▶ Caddy (mcp.smartcoreassistant.com.br)
                                            │
                                            ▼
                                       mcp_server (Python, FastMCP)
                                            │  1. resolve token → JWT (cache ~60s)
                                            │  2. filtra tools por escopo
                                            │  3. valida args (Pydantic)
                                            ▼
                                       runtime_api  ──gRPC──▶ data_postgres ──▶ Postgres
                                       (autentica JWT, cunha o envelope,      (RLS + auditoria)
                                        aplica escopo — §5.1)
```

O `mcp_server` é um **cliente**, não um par dos serviços internos. Ele não tem
privilégio nenhum que um usuário logado não tenha.

### 4.2 Isolamento de rede (barreira física, não convenção)

Nova rede `mcp_net` no compose, com **apenas** `mcp_server` e `runtime_api`. O
`mcp_server` fica em `[mcp_net, observability]` — nunca em `internal`. Consequência
prática: dentro do container do MCP, os nomes `postgres`, `data_postgres`,
`data_redis` e `data_storage` **não resolvem**. A D2 deixa de depender de disciplina
de código e passa a ser topologia.

### 4.3 Layout do módulo

```
mcp_server/
  pyproject.toml          # uv + hatchling, espelhando ia_engine/pyproject.toml
  uv.lock
  Dockerfile              # contexto na RAIZ do repo (stubs do .proto canônico)
  scripts/gen_proto.py    # mesmo padrão do ia_engine
  README.md
  src/mcp_server/
    __init__.py
    server.py             # bootstrap FastMCP + Streamable HTTP
    settings.py           # pydantic-settings
    telemetry.py          # OTel (traces + métricas)
    healthcheck.py
    auth/
      token_resolver.py   # token opaco → JWT, com cache Redis-less em memória + TTL
      scopes.py           # catálogo do doc 09 §3, espelhado e testado contra ele
    grpc/
      runtime_client.py   # cliente gRPC único do AdminService
      contracts/          # stubs gerados (omitido da cobertura)
    tools/
      registry.py         # registro + filtro por escopo
      guards.py           # confirmação, dry_run, rate limit
      fluxos.py  etapas.py  departamentos.py  atendentes.py
      treinamentos.py  intents.py  conexoes.py  config.py
      contatos.py  atendimentos.py  mensagens.py
  tests/
    unit/  integration/
```

---

## 5. Modelo de permissão

### 5.1 As duas metades a corrigir (N13.3)

| Família | Hoje | Problema | Correção na superfície do MCP |
|---|---|---|---|
| 40 RPCs via `encaminhar_tenant` | `tenant:admin` obrigatório para todos | **Rígido demais** — `manager` não edita fluxo, `staff` não cria treinamento. O agente de um `manager` não faria nada. | Parametrizar `encaminhar_tenant` com o escopo exigido por rota, conforme o catálogo (ex.: `ListMyFluxos` → `kanban:admin` ou `operacional:read`; `UpdateMyTenantConfig` → `configuracoes:write`). `tenant:admin` continua implicando todos. |
| Handlers operacionais manuais (`send_outbound_message`, `enviar_midia_atendimento`, `move_atendimento_etapa`, `set_atendimento_status`, `create_etiqueta`, `create_nota`, `list_atendimentos`, `get_thread`) | só `exigir_autenticado` | **Frouxo demais** — um `viewer` envia mensagem a cliente final. | Exigir escopo explícito (`atendimentos:read` / `atendimentos:write` / `clientes:read`) e resolver `flow_permissions` também em `send_outbound_message`, que hoje sai com o campo vazio. |

Ambas as correções valem para **todos** os clientes, inclusive o app Flutter — por
isso N13.3 tem um passo obrigatório de conferência contra o mapa de telas (doc 27) e
o `tenant_module`, para que nenhuma tela em uso hoje perca acesso.

### 5.2 Duas barreiras, como manda o doc 09

1. **No `mcp_server`** — falha rápido, com mensagem que **ensina o agente**
   (`"esta tool exige o escopo configuracoes:write; seu token tem apenas
   configuracoes:read"`). É ergonomia, não segurança.
2. **No `runtime_api`/repositório** — a barreira real, que não confia no cliente.
   Um MCP comprometido não ganha nada além do que o JWT já permite.

### 5.3 Filtro do `tools/list`

`tools/list` retorna **apenas** as tools que aquele token pode executar. Um agente
sem `configuracoes:write` não enxerga `update_tenant_config` — não tem como alucinar
a chamada, e o prompt do agente não desperdiça contexto com ferramentas proibidas.

---

## 6. Modelo de credencial

### 6.1 Tabela `mcp_access_token` (migration `0030`)

| Coluna | Tipo | Nota |
|---|---|---|
| `id` | `uuid` PK | UUIDv7 |
| `tenant_id` | `uuid` NOT NULL FK | sujeito a RLS como toda tabela por tenant |
| `user_id` | `int` NOT NULL FK `auth_user` | dono do token |
| `name` | `text` NOT NULL | rótulo dado pelo usuário ("Claude do meu notebook") |
| `token_hash` | `text` NOT NULL | **argon2id** — o token em claro nunca é persistido |
| `token_prefix` | `text` NOT NULL | 8 primeiros caracteres, só para identificar na lista |
| `scopes` | `jsonb` NOT NULL | subconjunto dos escopos do emissor |
| `expires_at` | `timestamptz` NULL | opcional; padrão sugerido 90 dias |
| `last_used_at` | `timestamptz` NULL | atualizado de forma preguiçosa |
| `revoked_at` | `timestamptz` NULL | revogação é soft, para a trilha sobreviver |
| `created_at` | `timestamptz` NOT NULL | |
| `created_ip` | `inet` NULL | |

Política RLS idêntica às demais tabelas por tenant (`app.current_tenant`), mais
índice em `token_prefix` para a busca do resolver.

### 6.2 Regra central — subconjunto, nunca superconjunto

Os escopos do token são **obrigatoriamente** um subconjunto dos escopos que o usuário
emissor possui **no momento da emissão**. Um `staff` não consegue cunhar um token com
`tenant:admin`. O usuário pode **reduzir** deliberadamente — um token só-leitura para
um agente exploratório é o caso de uso recomendado — mas **nunca ampliar**.

Esta é a resposta direta ao requisito de origem: *"não correr o risco de um usuário
comum alterar dados do administrador"*.

A validação é feita **no servidor**, na emissão, não na tela. E é re-verificada na
troca (§6.4): se o usuário for rebaixado de `admin` para `staff` depois de emitir o
token, a interseção passa a valer na chamada seguinte.

### 6.3 Revogação imediata

O token é resolvido a cada troca, com cache curto (TTL ~60s), mesmo padrão já usado
para `flow_permissions`. Revogar no painel derruba o agente na chamada seguinte, sem
esperar expiração. O TTL é o limite superior explícito da janela de revogação — e
precisa estar escrito na tela, para o usuário saber o que esperar.

### 6.4 Troca por JWT (`ExchangeMcpToken`)

Novo RPC no `AuthService` (`contracts/schemas/queries/auth.proto`, hoje com
`Login`/`Refresh`/`Logout`), trocando o token opaco por um JWT de vida curta com as
claims usuais (`sub`, `tenant_id`, `scopes`, `exp`), onde `scopes` é a **interseção**
entre os escopos do token e os escopos atuais do usuário.

A partir daí o `mcp_server` é indistinguível de qualquer outro cliente autenticado —
e é exatamente isso que faz RLS, escopo e auditoria continuarem valendo de graça.

---

## 7. Superfície de tools e salvaguardas

### 7.1 Categorias

| Categoria | Exemplos de tool | Escopo exigido | Salvaguardas |
|---|---|---|---|
| **Leitura** | `list_fluxos`, `list_atendimentos`, `get_thread`, `list_contatos`, `get_tenant_config`, `get_painel` | `*:read` correspondente | paginação obrigatória; teto de resultados |
| **Configuração** | `create_fluxo`, `update_etapa`, `create_departamento`, `create_treinamento`, `update_tenant_config`, `set_bot_persona` | `*:write` / `configuracoes:write` | `dry_run` |
| **Envio** | `send_message`, `send_media` | `atendimentos:write` | `dry_run` + **confirmação explícita** + rate limit próprio |
| **Destrutivas** | `desativar_fluxo`, `desativar_atendente`, `remover_treinamento`, `delete_whatsapp_instance`, `revoke_invite` | `operacional:admin` / `tenant:admin` | `dry_run` + **confirmação explícita** + rate limit próprio |

`get_tenant_config` **nunca** devolve `api_keys` descriptografadas — apenas quais
provedores estão configurados. Um agente externo não precisa da chave de outro
provedor de IA, e o risco de ela acabar no contexto de um LLM de terceiros é real.

### 7.2 Confirmação explícita

Toda tool de envio ou destrutiva recebe um argumento obrigatório
`confirmar: str`, que o agente precisa preencher com o **nome** do alvo, não o id:

```
desativar_fluxo(fluxo_id="…", confirmar="Funil de Vendas")
```

O servidor compara com o nome real e recusa se divergir. O objetivo é forçar o agente
a ter buscado o objeto antes — um id alucinado não passa, porque ele não teria o nome
para casar. É a diferença entre "o agente decidiu" e "o agente errou o alvo".

### 7.3 `dry_run`

Toda tool de escrita aceita `dry_run: bool = False`. Com `True`, valida tudo,
resolve o alvo, descreve o efeito que teria sido produzido e **não escreve**.
Auditado igualmente (com `dry_run: true` no contexto), sem rate limit da categoria.
É o que permite ao agente confirmar com o humano antes de agir.

### 7.4 Rate limit por token

Tetos separados por categoria, aplicados no `mcp_server` por `token_id`:

| Categoria | Teto sugerido |
|---|---|
| Leitura | 300 / min |
| Configuração | 60 / min |
| Envio | **10 / min, 100 / dia** |
| Destrutivas | **5 / min, 30 / dia** |

Estouro devolve erro de tool com o tempo de espera — o agente entende e recua, em vez
de martelar. Cada estouro incrementa `smartcore_mcp_denied_total{motivo="rate_limit"}`,
que é a métrica que revela um agente em loop antes de o cliente perceber.

### 7.5 Qualidade da descrição (não é cosmético)

Cada tool descreve, na docstring que vira o schema MCP: o que faz, **quando usar e
quando não usar**, o efeito colateral no mundo real, e o formato de cada argumento.
Cada campo Pydantic leva `Field(description=...)`. Enumerações são `Literal`, nunca
`str` livre. Erros retornam mensagem acionável, não stack trace.

Esse é o núcleo do requisito "documentar e dar as ferramentas": a descrição é a
interface, e uma descrição ruim produz um agente que erra com confiança.

---

## 8. N13.1 — Fundação de credencial

**Tarefas**
1. Migration `0030_mcp_access_token.sql`: tabela da §6.1, política RLS,
   índice em `token_prefix`, FKs com `ON DELETE CASCADE` a partir de
   `tenants_tenant` e `auth_user`.
2. Repositório em `infrastructure_postgres` (criar, listar por usuário, revogar,
   marcar `last_used_at`), com o hash argon2id reaproveitando o utilitário de senha
   já existente no `application`.
3. RPCs no `AdminService`: `CreateMcpToken`, `ListMcpTokens`, `RevokeMcpToken`.
   Escopo exigido: apenas sessão autenticada (qualquer usuário pode gerar **seu**
   token); a restrição está nos escopos que ele consegue pedir.
4. Validação de subconjunto (§6.2) no **servidor**, com teste que prova que um
   `staff` recebe `permission_denied` ao pedir `tenant:admin`.
5. Auditoria: `mcp.token_criado` (INFO), `mcp.token_revogado` (INFO),
   `mcp.token_escopo_negado` (WARN).

**DoD:** migration aplica e reverte; um usuário lista/revoga **apenas os próprios**
tokens (provado por teste de isolamento entre dois usuários do mesmo tenant); o token
em claro aparece uma única vez na resposta de criação e não existe em lugar nenhum
depois; escalada de escopo negada com teste.

---

## 9. N13.2 — `ExchangeMcpToken`

**Tarefas**
1. RPC `ExchangeMcpToken(token) → AuthResponse` no `AuthService`. Rota **pública**
   quanto a sessão (o token é a credencial), mas com rate limit de borda próprio
   contra força bruta.
2. Resolução: `token_prefix` → candidato → verificação argon2id →
   checagem de `revoked_at`/`expires_at` → interseção de escopos (§6.4) → JWT curto
   (sugerido 15 min).
3. Cache de resolução com TTL ~60s, invalidado na revogação.
4. Auditoria: `mcp.token_trocado` (INFO), `mcp.token_invalido` (WARN, com
   `token_prefix` e IP — **nunca** o token).

**DoD:** troca devolve JWT com escopos corretos; token revogado falha em no máximo
60s; token de usuário rebaixado devolve os escopos **reduzidos**, provado por teste;
tentativa com token inexistente não distingue "não existe" de "revogado" na mensagem
de erro (mesma resposta, mesmo tempo).

---

## 10. N13.3 — RBAC fino na superfície exposta

**Tarefas**
1. Parametrizar `encaminhar_tenant` com o escopo exigido por rota, substituindo o
   `exigir_escopo_tenant_admin` fixo de `grpc_web.rs:840`. Mapa rota→escopo derivado
   do catálogo do doc 09 §3, em um único lugar, testável.
2. Acrescentar checagem de escopo aos handlers operacionais manuais da §5.1.
3. Resolver `flow_permissions` em `send_outbound_message` e nos demais handlers
   operacionais que hoje saem com o campo vazio.
4. Fazer os repositórios correspondentes chamarem `ctx.has_permission()` — hoje com
   zero chamadas fora de `security.rs` —, conforme o check-list do doc 09 §7.
5. **Conferência de regressão de UI:** cruzar o mapa de telas (doc 27) e o
   `tenant_module` para garantir que nenhuma tela em uso perde acesso. Este passo é
   obrigatório e é onde mora o risco da fase.

**DoD:** um `manager` edita fluxo (hoje não consegue); um `viewer` **não** envia
mensagem (hoje consegue); `flutter test` do `tenant_module` verde; suíte Rust verde;
tabela rota→escopo documentada no doc 09 e coberta por teste que falha se uma rota
nova entrar sem escopo declarado.

---

## 11. N13.4 — Skeleton do `mcp_server`

**Tarefas**
1. Criar `mcp_server/` no layout da §4.3, com `uv`, hatchling, ruff (line-length 88,
   `select = E,F,I,UP,B`), mypy e pytest — espelhando `ia_engine/pyproject.toml`.
2. `scripts/gen_proto.py` gerando stubs do `.proto` canônico
   (`server/crates/contracts/schemas/queries/{admin,auth}.proto`); `Dockerfile` com
   contexto na **raiz** do repo, como o do `ia_engine`.
3. Servidor FastMCP em Streamable HTTP, com autenticação por `Authorization: Bearer`
   e `healthcheck.py`.
4. Compose (`docker/{dev,prod}/compose.yml`): serviço `mcp_server`, rede **`mcp_net`**
   (§4.2), `[mcp_net, observability]`, `mem_limit` conservador, healthcheck,
   `MCP_RUNTIME_ENDPOINT` apontando para `runtime_api:50051`.
5. CI: job `mcp_server` em `ci.yml` no molde do job `ia_engine` (ruff + mypy +
   pytest com ratchet de cobertura); job `build-mcp-server` publicando
   `ghcr.io/…/smartcore-mcp-server` em `deploy-dev.yml`/`deploy-prod.yml`.
6. Caddy: bloco `mcp.smartcoreassistant.com.br`. **Validar antes de recarregar**
   (`caddy validate --config /etc/caddy/Caddyfile`) — a borda roteia o site inteiro,
   incluindo o painel v1 em produção. Registro DNS do subdomínio antes do deploy.

**DoD:** `mcp_server` sobe no compose, responde healthcheck, e um cliente MCP real
(Claude Desktop) conecta em `https://mcp.smartcoreassistant.com.br` e lista **zero**
tools com token inválido / **as tools permitidas** com token válido. Ruff, mypy e
pytest limpos no CI. Container **sem** rota para `postgres` (provado por teste de
resolução de nome dentro do container).

---

## 12. N13.5 — Tools de leitura e configuração

**Tarefas**
1. `registry.py`: decorador que associa cada tool ao escopo exigido e à categoria,
   e filtra `tools/list` pelos escopos do JWT corrente (§5.3).
2. Implementar as tools de leitura e de configuração da §7.1 sobre os RPCs `My*`.
3. Descrições no padrão da §7.5, com exemplo de uso em cada uma.
4. `dry_run` nas de configuração.
5. Testes: unitários por tool (mock do cliente gRPC) + integração contra o
   `runtime_api` real com um tenant de fixture.

**DoD:** um agente, partindo de um tenant vazio e só com o prompt "configure um funil
de vendas com 4 etapas e um departamento comercial", conclui a tarefa sem intervenção
humana. Este é o teste de aceitação da fase — se ele falhar, o problema está nas
descrições, não no código.

---

## 13. N13.6 — Tools de envio e destrutivas

**Tarefas**
1. `guards.py`: confirmação explícita (§7.2), `dry_run` (§7.3), rate limit por
   `token_id` e categoria (§7.4).
2. Implementar `send_message`, `send_media` e a família destrutiva.
3. Testes de recusa: confirmação divergente, escopo insuficiente, estouro de rate
   limit — cada um com asserção sobre a **mensagem** devolvida, que precisa ser
   acionável pelo agente.
4. Teste de que uma tool destrutiva **não aparece** no `tools/list` de um token
   sem o escopo correspondente.

**DoD:** nenhuma escrita irreversível acontece sem confirmação casada com o nome do
alvo; `dry_run` nunca escreve (provado contra o banco); rate limit de envio corta em
10/min; toda ação irreversível tem linha em `audit_log` com `source: "mcp"` e
`token_id`.

---

## 14. N13.7 — Auditoria, traces e métricas

**Tarefas**
1. Propagar `traceparent` do `mcp_server` ao `runtime_api` e adiante; span por tool.
2. Enriquecer a auditoria das rotas usadas pelo MCP com `source`, `token_id`, `tool`
   e `dry_run` no `context` — sem inventar tabela nova, reaproveitando o pipeline
   `AuditLogger` → `STREAM_SEGURANCA` → `audit_log`.
3. Métricas da §3 e um painel Grafana `mcp_agentes.json`: chamadas por tool,
   latência, taxa de negação, top tokens.
4. Regra de alerta: pico anômalo de negações ou de tools destrutivas por token —
   é a assinatura de um token vazado ou de um agente em loop.

**DoD:** trace contínuo do Claude ao Postgres visível no Tempo; `QueryAuditLog`
consegue responder "o que o agente do fulano fez ontem" com um único filtro; painel
preenchendo com dados reais.

---

## 15. N13.8 — Tela Integrações no painel do tenant

**Tarefas**
1. Nova feature `integracoes` em `clients/modulos/tenant_module/lib/src/features/`,
   no padrão das existentes (`config`, `conexoes`, `usuarios`).
2. Fluxo: listar tokens (nome, prefixo, escopos, último uso, expiração) → criar
   (nome + seleção de escopos, **limitada aos escopos do próprio usuário**) →
   exibir o token **uma única vez**, com botão de copiar e aviso claro → revogar.
3. Bloco de "como conectar", com o JSON de configuração pronto para colar no Claude
   Desktop e a instrução equivalente para ChatGPT/Cursor, já com a URL preenchida.
4. Aviso explícito da janela de revogação (~60s, §6.3) e do que o token permite.

**DoD:** `flutter analyze` limpo; teste de widget cobrindo "token exibido uma vez" e
"escopos indisponíveis aparecem desabilitados, não ocultos" (o usuário precisa
entender que existem e que ele não os tem); percurso completo contra o `runtime_api`
real.

---

## 16. N13.9 — Documentação

**Tarefas**
1. `mcp_server/README.md`: arquitetura, como rodar local, como gerar stubs.
2. Documento de uso para o cliente final (`doc_dev/` ou base de ajuda): como gerar o
   token, como plugar no Claude/GPT, o que cada escopo libera, o que fazer se o token
   vazar.
3. Atualizar `06_modulo_integracoes.md` — hoje "Integrações" descreve apenas
   WhatsApp/Evolution; passa a ter uma segunda família.
4. Atualizar `09_diretrizes_permissoes_acesso.md` com a tabela rota→escopo de N13.3
   e com a existência de credenciais não-interativas.
5. Atualizar `27-mapa-telas-rotas-v2.md` com a tela Integrações.

**DoD:** um usuário que nunca viu MCP conecta o Claude ao próprio tenant seguindo só
a documentação, sem perguntar nada.

---

## 17. SOLID / Ports & Adapters

- **Python:** cada tool é um caso de uso isolado (SRP). O acesso ao backend fica atrás
  de um único `RuntimeApiClient` (port) — trocar transporte não toca tool nenhuma.
  Os guards (confirmação, `dry_run`, rate limit) são **decoradores** aplicados no
  registro, não `if` espalhado dentro de cada tool.
- **Rust:** o mapa rota→escopo de N13.3 vive em **um** lugar declarativo, consultado
  por `encaminhar_tenant` e pelos handlers manuais — não replicado por rota.
- **Contratos:** o `.proto` canônico segue sendo a única fonte; o Python consome
  stubs gerados, nunca um DTO escrito à mão.

---

## 18. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| **Agente envia mensagem errada a cliente real** — único efeito da lista sem desfazer | Dano de imagem direto ao cliente do cliente | Confirmação casada por nome (§7.2), `dry_run`, rate limit 10/min, escopo `atendimentos:write` obrigatório, auditoria com `token_id` |
| **N13.3 quebra tela em uso** | Regressão em produção | Passo obrigatório de conferência contra doc 27 + `tenant_module`; suíte Flutter no DoD; a mudança de `encaminhar_tenant` **amplia** acesso (de `tenant:admin` para escopos específicos), então o risco concentra-se nos handlers operacionais, que **restringem** |
| **Token vazado no disco do usuário** | Acesso ao tenant pelo escopo do token | Escopo mínimo incentivado na UI; expiração padrão; revogação em ~60s; alerta de anomalia (§14); D4 impede que o vazamento alcance mais de um tenant |
| **`get_tenant_config` expõe chave de provedor ao LLM de terceiros** | Vazamento de segredo para fora | A tool **nunca** devolve `api_keys` descriptografadas (§7.1) — só quais provedores existem |
| **Descrição de tool ruim → agente erra com confiança** | Produto inutilizável na prática | §7.5 como requisito de DoD; teste de aceitação de N13.5 é um agente real cumprindo tarefa real |
| **Agente em loop consome cota do provedor / martela o backend** | Custo e carga | Rate limit por categoria; `smartcore_mcp_denied_total`; alerta de anomalia |
| **`mcp_server` acaba com acesso ao banco por descuido futuro** | Bypass total do RBAC | Barreira topológica (`mcp_net`, §4.2) + teste que prova que `postgres` não resolve dentro do container |
| **Caddy inválido derruba o painel v1 em produção** | Site inteiro fora | `caddy validate` antes de recarregar; DNS do subdomínio antes do deploy |

---

## 19. Ordem de execução e dependências

```
N13.1 (credencial) ──▶ N13.2 (troca) ──▶ N13.4 (skeleton) ──▶ N13.5 (tools leitura/config)
                                                │                      │
N13.3 (RBAC fino) ──────────────────────────────┘                      ▼
   (independente de N13.1/N13.2; pode correr em paralelo)        N13.6 (envio/destrutivas)
                                                                       │
N13.8 (UI) depende de N13.1 ─────────────────────────────────▶ N13.7 (observabilidade)
                                                                       │
                                                                 N13.9 (docs)
```

**Primeiro corte utilizável:** N13.1 + N13.2 + N13.4 + N13.5 já entregam um MCP de
leitura e configuração funcionando de ponta a ponta. N13.3 é pré-requisito de
**qualidade** — sem ele, os tokens de `manager`/`staff` não configuram nada e os de
`viewer` enviam mensagem. Não vale entregar N13.6 antes de N13.3.

---

## 20. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N13** | Credencial por usuário + projeção MCP do `AdminService` | Aprovar schema `mcp_access_token`, mapa rota→escopo e catálogo de tools | Credencial→troca→RBAC→skeleton→tools→salvaguardas→observabilidade→UI→docs | Suíte Rust + `pytest` do `mcp_server` + `flutter test`; teste de aceitação com agente real | Agente configura tenant ponta-a-ponta; nenhuma escalada de escopo; toda ação auditada com origem `mcp` |

*Plano aterrado no `admin.proto` (87 RPCs), em `grpc_web.rs:832-840` e nos handlers
operacionais (leitura de 2026-09-06), no catálogo de escopos do doc 09 §3, no padrão
de isolamento do `ia_engine` e nas decisões D1–D6 travadas com o responsável.*
