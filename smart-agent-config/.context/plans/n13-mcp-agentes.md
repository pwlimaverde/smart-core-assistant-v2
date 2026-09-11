---
type: plan
name: "Fase N13 — Módulo mcp_server (servidor MCP para agentes de IA)"
planSlug: n13-mcp-agentes
description: "Servidor MCP que permite a agentes de IA externos (Claude web/Desktop/mobile/Cowork/Code, Cursor e ChatGPT) configurar e operar o tenant do usuário, projetando de forma documentada e filtrada por permissão os 87 RPCs do AdminService que já existem — 37 deles My*. Limite inegociável: o agente nunca faz nada que o usuário que autorizou não pudesse fazer no painel; a tela de consentimento só oferece os escopos que esse usuário possui, então é subconjunto por construção, nunca superconjunto. Módulo Python isolado como o ia_engine, que NÃO fala com o banco: toda leitura e escrita passa pelo runtime_api por gRPC, herdando o interceptor de autenticação, a RLS do Postgres e a trilha de auditoria já existentes. Inclui a correção do RBAC nas rotas que o MCP expõe, hoje simultaneamente rígido demais na configuração (encaminhar_tenant exige tenant:admin nas 40 rotas) e frouxo demais na operação (send_outbound_message exige só sessão)."
summary: "Autenticação é OAuth 2.1 com authorization server próprio no control_plane — revisado em 2026-09-06, porque a UI de conector do Claude (web, desktop, mobile, Cowork) é OAuth e o token opaco não a atenderia, nem ao ChatGPT. O usuário clica Conectar, faz login, consente e pronto: não copia configuração. O resto é projeção de contrato existente. Superfície completa na v1, incluindo envio e destrutivas, com salvaguardas como parte da entrega. N13.1 (auth server) é a fase de maior risco e esforço. N13.3 conflita com N11 (ambas alteram rotas do runtime_api) e precisa ser sequenciada depois dela."
status: filled
progress: 0
generated: "2026-09-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Authorization server OAuth 2.1 no control_plane (authorize/consent/token, PKCE, CIMD), grants no infrastructure_postgres, mapa rota→escopo no runtime_api"
  - type: "database-specialist"
    role: "Migration 0030 (mcp_oauth_grant) com RLS, índice (user_id, client_id) e FKs em cascata"
  - type: "ai-specialist"
    role: "Módulo Python mcp_server: MCPServer, catálogo de tools, guards e cliente gRPC do runtime_api"
  - type: "security-auditor"
    role: "Auditar o AS item a item (PKCE, redirect_uri exato, iss, audiência, rotação de refresh, SSRF no CIMD), regra do subconjunto no consentimento, PII e chave de provedor fora de log/span/auditoria, cacheScope de tools/list"
  - type: "devops-specialist"
    role: "Rede mcp_net, compose dev/prod, job de CI e imagem GHCR, blocos do Caddy e DNS de mcp. e auth."
  - type: "frontend-specialist"
    role: "Tela de consentimento OAuth e Aplicativos conectados no tenant_module: ver o que está conectado, com quais permissões, e desconectar"
  - type: "test-writer"
    role: "Testes de recusa do AS (um por obrigação normativa), isolamento entre usuários, escalada de escopo negada, dry_run que não escreve, teste de aceitação com agente real"
  - type: "documentation-writer"
    role: "README do módulo, guia do cliente final e atualização dos docs 06, 09 e 27"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
lastUpdated: "2026-09-09T22:28:51.807Z"
---

# Fase N13 — Módulo `mcp_server` (servidor MCP para agentes de IA)

> **Independente de N10, N11 e N12** — o MCP projeta contratos que já existem.
> **Exceção:** N13.3 altera rotas do `runtime_api` e **colide com N11**; entra
> depois dela, ou as duas dividem o conjunto de rotas antes de começar.
> **Invariante 1:** o `mcp_server` nunca alcança o banco. Sem `DATABASE_URL`, fora
> da rede `internal`, e a barreira é topológica (rede `mcp_net`), não convenção.
> **Invariante 2:** o access token do cliente **nunca** é repassado ao
> `runtime_api` — é trocado por um JWT interno. Exigência normativa da spec.
>
> **Revisão de 2026-09-06:** a autenticação passou de token opaco para **OAuth 2.1
> com authorization server próprio**. Motivo: a UI de conector do Claude (web,
> desktop, mobile, Cowork) é OAuth, e header estático só funciona em arquivo de
> config local — o desenho anterior não entregaria conector nenhum, nem no Claude.
> Ver C18–C22 no plano completo.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n13-mcp-agentes.md](./n13-mcp-agentes/plano_completo_n13-mcp-agentes.md)
- **Documentação auxiliar**: [info_aux_n13-mcp-agentes.md](./n13-mcp-agentes/info_aux_n13-mcp-agentes.md)

## Origem
- [29-modulo-mcp-agentes.md](../../doc_dev/planejamento/29-modulo-mcp-agentes.md) — plano-base (histórico)
- [09_diretrizes_permissoes_acesso.md](../../doc_dev/modelagem_dados/09_diretrizes_permissoes_acesso.md) §3 — catálogo canônico de 14 escopos
- [10_modulo_auth_usuarios.md](../../doc_dev/modelagem_dados/10_modulo_auth_usuarios.md) — hierarquia de usuário e claims do JWT
- [06_modulo_integracoes.md](../../doc_dev/modelagem_dados/06_modulo_integracoes.md) — "Integrações" ganha uma segunda família

## Etapas

**Estado em 2026-09-09: E1–E9 escritas e commitadas** em
`feature/n13-mcp-agentes` (2 commits). O que foi verificado nesta máquina e o que
depende do CI está na seção "Estado da implementação", mais abaixo — leia antes
de tratar qualquer etapa como concluída.

| # | Entregável | Área |
|---|---|---|
| E1 | **Authorization server OAuth 2.1** no `control_plane`: metadata RFC 8414, `/oauth/authorize` com **tela de consentimento**, `/oauth/token` com **PKCE S256**, suporte a **CIMD** (com guarda anti-SSRF), `iss` na resposta, rotação de refresh. Subdomínio `auth.` no Caddy | control_plane + docker/edge |
| E2 | **Grants e revogação**: migration `0030_mcp_oauth_grant` com RLS + repositório + `ListMcpGrants`/`RevokeMcpGrant` | migration + infrastructure_postgres + runtime_api |
| E3 | **RBAC fino na superfície exposta**: mapa rota→escopo substituindo o gate binário de `grpc_web.rs:840`; escopo nos handlers operacionais; `flow_permissions` em `send_outbound_message`; `has_permission()` nos repositórios | runtime_api + infrastructure_postgres |
| E4 | **`mcp_server` como resource server** (SDK `mcp` 2.1.1, Streamable HTTP): `TokenVerifier` com validação de **audiência**, troca por JWT interno, RFC 9728 + `WWW-Authenticate`, rede `mcp_net`, compose, CI, imagem GHCR, Caddy + DNS | mcp_server + docker + CI |
| E5 | Tools de **leitura e configuração** sobre os `My*`, com `tools/list` filtrado por escopo, ordem determinística e `cacheScope` não público | mcp_server |
| E6 | Tools de **envio e destrutivas** + salvaguardas: confirmação por MRTR/`elicitation` com fallback por argumento, `dry_run`, rate limit por categoria | mcp_server |
| E7 | Auditoria com `source: "mcp"`, trace contínuo até o Postgres, métricas por tool e painel/alerta | mcp_server + observability |
| E8 | Tela **Aplicativos conectados** no painel do tenant (ver o que está conectado, com quais permissões, e desconectar) | tenant_module |
| E9 | Documentação: README do módulo, guia do cliente final, docs 06/09/27 | docs |

**Ordem:** E1 → E2 → E4 → E5 → E6, com **E3 em paralelo (após N11)** e E8 dependendo
de E2. E7 fecha sobre E5/E6; E9 por último. **E1 e E2 são fortemente acopladas** —
o consentimento é o que produz o grant; fazer juntas.

**Primeiro corte utilizável:** E1 + E2 + E4 + E5 — o conector funciona ponta a
ponta: o usuário conecta pelo navegador e o agente lê e configura o tenant.

**Não entregar E6 antes de E3**, senão agentes de `viewer` enviam mensagem a
cliente final. Se a fase precisar encolher, o corte é em superfície de tools
(adiar E6), **nunca** em obrigação de segurança do AS.

## Decisões travadas

| # | Decisão |
|---|---|
| D1 | **Python + SDK `mcp` 2.1.1** (classe `MCPServer`; `FastMCP` era a API v1 e não existe mais). Schema da tool derivado de type hints + `pydantic.Field(description=…)` + docstring |
| D2 | **`MCP → runtime_api → data_postgres → Postgres`.** Falar direto com `data_postgres` seria bypass total do RBAC — aquela camada confia nos campos 11–13 do envelope em vez de verificá-los |
| D3 | **Streamable HTTP + OAuth 2.1 com AS próprio.** RS em `mcp.smartcoreassistant.com.br`, AS em `auth.smartcoreassistant.com.br` (no `control_plane`, que já autentica e emite JWT). Revisado em 2026-09-06 — ver C18 |
| D4 | **Sem tokens de superusuário na v1** — um token vazado alcança no máximo um tenant |
| D5 | **RBAC fino só na superfície do MCP** — varrer os 87 RPCs quebraria o que o app Flutter assume |
| D6 | **Superfície completa na v1**, incluindo envio e destrutivas, com salvaguardas como parte da entrega |
| D7 | **Sem estado de sessão** — a spec `2026-07-28` é stateless; o token é entrada por requisição |
| D8 | **Dois tokens, nunca um.** O access token tem `aud` = `mcp_server` e é trocado por JWT interno antes de falar com o `runtime_api`. *"The MCP server MUST NOT pass through the token it received from the MCP client."* |
| D9 | **ChatGPT: conformidade sim, garantia não.** Implementamos o que a OpenAI exige e validamos, mas MCP no ChatGPT é Developer Mode/beta e **não** é gate de entrega |

## Observabilidade & Auditoria (resumo)

**Auditar** com `source: "mcp"`, `grant_id` e `tool` no `context`:
`oauth.consentimento_concedido`, `oauth.consentimento_negado`,
`oauth.grant_revogado`, `oauth.refresh_reutilizado` (**WARN** — sinal de roubo),
`oauth.cimd_rejeitado` (WARN), `permissao.negada` (WARN), `mensagem.enviada`,
`<entidade>.desativada`, `<entidade>.removida`, além dos eventos de configuração
já previstos em 08 §4.2 (`configuracao.alterada`, `api_key.update`).

**Sem evento (intencional):** bootstrap do processo (E4), pipeline de métricas
(E7) e documentação (E9) — não acessam nem alteram dado.

**Nunca em log, span, métrica ou `context`:** `code`, `code_verifier`, refresh
token, access token, JWT interno e seus hashes; **conteúdo de mensagem** (só
`atendimento_id` e tamanho); telefone/nome de contato; chave de provedor —
`get_tenant_config` **nunca** devolve `api_keys` descriptografadas. O texto do
`ToolError` também não pode conter PII: o SDK o loga (C16).

**Cardinalidade:** `grant_id` não entra como label de métrica; fica na auditoria
e no span.

**Trace:** `traceparent` W3C injetado no metadata gRPC do `mcp_server` ao
`runtime_api` e adiante, como o `ia_engine` já faz.

## Estado da implementação (2026-09-09)

Tudo escrito. A distinção que importa não é "feito / não feito", é **o que foi
executado** e **o que só foi lido**.

### Verificado nesta máquina

| O que | Como |
|---|---|
| `mcp_server` | `ruff` + `mypy` limpos, **49 testes** passando; o servidor monta e registra as 28 tools |
| Caminho criptográfico | Token assinado com a chave RSA **real** do `dev.env` valida no `VerificadorDeToken`; audiência alheia e chave errada são recusadas |
| Sintaxe de todo o Rust novo | `rustfmt` parseia os 20 arquivos sem erro |
| `cargo fmt --all -- --check` | Passa nos arquivos tocados (é gate de CI) |
| Caddyfile | `caddy validate` contra o Caddy real → *Valid configuration*. A config no ar não foi tocada |
| Composes dev e prod | `docker compose config` válido |
| Workflows | YAML válido nos três |
| Stubs Dart do protobuf | Regenerados e `dart analyze` limpo. Confirmado antes que regenerar **sem** as mudanças dá arquivos byte-idênticos aos commitados |
| Proto | Compila em Python e em Dart |

### O que o CI achou (2026-09-11)

Publicado na `dev`; o CI foi o primeiro compilador a ver o Rust. Registro aqui
porque a lição vale além desta fase: **três dos seis defeitos só aparecem quando
os dois lados do merge coexistem**, e nenhum deles daria conflito de merge.

| # | Defeito | Como apareceu |
|---|---|---|
| 1 | `sqlx::query(&format!(…))` não compila | O sqlx 0.9 aceita só `&'static str` e recusa string dinâmica: *"dynamic SQL strings should be audited for possible injections"*. Eu havia extraído a lista de colunas para uma constante e a interpolava — conveniência que custou erro de compilação e um cheiro de injeção. As colunas voltaram a ser literais |
| 2 | `quitar_minha_assinatura` chamava `exigir_escopo_tenant_admin` | **Defeito de merge que o git não pega.** A `dev` acrescentou a rota usando a função que a N13.3 removeu. Nomes diferentes, pontos diferentes do arquivo: zero conflito, erro garantido |
| 3 | `MockMcpGrantStore` não existia em `crate::ports` | O `automock` gera o mock no módulo da trait; os outros dez ports o reexportam sob `#[cfg(test)]`. O meu não |
| 4 | `Clipboard`/`ClipboardData` indefinidos | Vivem em `flutter/services`, que o `dependencies_module` não reexporta |
| 5 | `prefer_initializing_formals` (2 infos) | Infos são **fatais** no `melos analyze`. O padrão da casa usa formal de inicialização privado |
| 6 | Cobertura 56% contra o piso de 70% | Piso que eu mesmo escrevi. Corrigido escrevendo 49 testes novos — não baixando o piso |

**`cargo fmt --check` passou de primeira**, porque instalei o toolchain só para
rodar `rustfmt` (que parseia, não compila) antes de publicar. Sem isso seria um
sétimo ciclo.

### NÃO verificado nesta máquina

| O que | Por quê |
|---|---|
| **Compilação do Rust** | Esta máquina não tem toolchain além do `rustfmt`; `cargo build` derruba a stack (2 vCPU, 7,8 GB). O CI compila |
| `cargo clippy -- -D warnings` | Exige compilar |
| `flutter analyze` / `flutter test` | Sem Flutter SDK. O CI roda |
| Migration `0032` | Não aplicada em banco nenhum aqui; o deploy a aplica |
| Fluxo OAuth ponta a ponta | Depende de deploy. **DNS não é bloqueio**: há curinga `*.smartcoreassistant.com.br` apontando para este servidor |

### Desvios do plano, com o motivo

| # | Plano dizia | Ficou | Por quê |
|---|---|---|---|
| 1 | `refresh_token_hash` em **argon2id** | **SHA-256** | O segredo tem 256 bits de CSPRNG — não há dicionário contra isso. Argon2 custaria ~100 ms por renovação e o salt aleatório inutilizaria o índice de busca. É o que `application::tokens::hash_refresh_token` já faz |
| 2 | Confirmação de `send_message` casada com o **nome** do contato | **`contato_id`** | Nenhum RPC do backend resolve contato por id, e o texto do `ToolError` vai para o log do processo — nome de cliente ali seria vazamento de PII. O `contato_id` preserva a propriedade que importa: só se obtém listando de verdade. As destrutivas seguem usando o nome |
| 3 | `challenges.py` no `mcp_server` | **não existe** | O SDK já monta o `/.well-known/oauth-protected-resource` e o `WWW-Authenticate` com `resource_metadata`. Escrever os nossos duplicaria a implementação conformante e divergiria dela na primeira atualização |
| 4 | Repositório com `sqlx::query_as!` | **queries verificadas em runtime** | O cache `.sqlx/` exige `cargo sqlx prepare` contra um banco, o que não é possível aqui, e um cache desatualizado quebra o `--check` do CI |
| 5 | Confirmação **nível 1** por `elicitation` | **só o nível 2** (argumento) | O nível 2 é o que o plano chama de garantido; o nível 1 depende de capacidade opcional do cliente. Fica como o primeiro incremento de N13.6 |
| 6 | — | **teto de vida de 30 dias no consentimento** | Não estava no plano. Um refresh rotacionado indefinidamente vale para sempre; o teto é medido sobre `created_at`, sem coluna nova |

### O que falta para funcionar

1. ~~DNS~~ — resolvido: há curinga apontando para o servidor, e `auth.dev.` e
   `mcp.dev.` já resolvem.
2. ~~Segredos~~ — par RSA e `MCP_SERVICE_SECRET` provisionados em
   `/opt/smartcore/dev/env/` (2026-09-09), com o PEM em linha única e `\n`
   escapado; os dois lados normalizam.
3. **CI verde e deploy concluído** — em andamento.
4. **O teste prático**: conectar um cliente MCP real e rodar o teste de aceitação
   do plano (*"configure um funil de vendas com 4 etapas e um departamento
   comercial"*, partindo de tenant vazio).
5. **A auditoria de segurança da fase R** continua devendo. Agora ela pode
   acontecer de verdade: o código compila e a migration aplica.

### Bug corrigido no caminho

`application/src/auth/login.rs` fazia `unwrap_or(0)` no `id` vindo de
`VerifyCredentials`: uma resposta malformada emitia JWT com `sub="0"` — sessão sem
dono. Agora falha fechado. Passou a ser bloqueante porque o consentimento OAuth
grava `user_id` com FK.

---

## Definition of Done

- [ ] **O conector funciona sem colar configuração:** o usuário adiciona a URL no Claude, é levado ao login, consente e o agente passa a operar.
- [ ] Um `staff` **não vê** `tenant:admin` na tela de consentimento.
- [ ] Usuário rebaixado após conectar passa a operar com escopos **reduzidos** na renovação seguinte.
- [ ] Desconectar no painel invalida o refresh na hora; o acesso em curso termina em ≤15 min — e esse número está escrito na tela.
- [ ] **Um teste de recusa por obrigação da §4.6:** `redirect_uri` divergente, PKCE ausente, `code_verifier` errado, código reutilizado, código expirado, refresh reutilizado (derruba o grant), CIMD com `client_id` ≠ URL, CIMD apontando para IP privado.
- [ ] Token de audiência alheia é **rejeitado** pelo `mcp_server`, e o token do cliente **não** aparece no metadata gRPC enviado ao `runtime_api`.
- [ ] Um `manager` edita fluxo (hoje não consegue); um `viewer` **não** envia mensagem (hoje consegue).
- [ ] Dois grants de escopos diferentes recebem `tools/list` diferentes, em ordem determinística e sem `cacheScope: "public"`.
- [ ] Nenhuma escrita irreversível sem confirmação — por `elicitation` quando o cliente a oferece, por argumento casado com o **nome** do alvo quando não.
- [ ] `dry_run` nunca escreve, provado contra o banco.
- [ ] Container do `mcp_server` **não resolve** `postgres`/`data_postgres`, provado por teste.
- [ ] **Teste de aceitação:** um agente real, partindo de tenant vazio e do prompt *"configure um funil de vendas com 4 etapas e um departamento comercial"*, conclui sem intervenção humana.
- [ ] `QueryAuditLog` responde "o que o agente do fulano fez ontem" com um único filtro.
- [ ] `cargo` + `pytest` (`ruff`/`mypy`) + `flutter test` verdes; `caddy validate` verde e painel v1 intacto.

## Execution History

> Last updated: 2026-09-09T22:28:51.807Z | Progress: 0%
