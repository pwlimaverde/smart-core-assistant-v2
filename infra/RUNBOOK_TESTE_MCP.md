# Runbook — primeiro teste prático do servidor MCP (N13)

Como verificar que o módulo subiu e como conduzir o primeiro teste com um agente
real. Escrito para ser seguido de cima para baixo; cada passo tem o que se espera
ver, e o que fazer quando não é isso que aparece.

**Ambiente:** DEV (`dev.smartcoreassistant.com.br`). Nada aqui toca produção.

---

## 0. Antes de começar

| Item | Como conferir |
|---|---|
| Par de chaves RSA provisionado | `ls -l /opt/smartcore/dev/env/mcp_oauth_key*.pem` → dois arquivos, `600`, dono `gh-runner` |
| Segredo de serviço | `grep -c MCP_SERVICE_SECRET /opt/smartcore/dev/env/dev.env` → `1` |
| DNS | `getent hosts mcp.dev.smartcoreassistant.com.br` → resolve (há curinga) |
| Deploy concluído | `gh run list --workflow=deploy-dev.yml --branch dev --limit 1` → `success` |

Se o deploy falhou, **pare aqui**. A stack antiga continua no ar (o `deploy-dev`
é pulado quando o build falha), então não há incidente — mas o módulo novo não
existe ainda.

---

## 1. Os dois containers novos subiram?

```bash
docker ps --filter name=mcp_server --format '{{.Names}}\t{{.Status}}'
docker ps --filter name=control_plane --format '{{.Names}}\t{{.Status}}'
```

**Esperado:** `mcp_server` e `control_plane` com `Up ... (healthy)`.

O healthcheck do `mcp_server` bate no próprio endpoint **sem token e espera 401**.
Parece invertido; não é. Um 401 prova três coisas ao mesmo tempo: o processo está
de pé, o roteamento funciona e a camada de autenticação está montada. Um **200**
ali seria falha — significaria servidor aceitando requisição sem autorização.

**Se ficar `unhealthy`:**

```bash
docker logs --tail 50 smart-core-v2-dev-mcp_server-1
```

Os dois motivos prováveis, os dois com mensagem própria no log:
`MCP_OAUTH_PUBLIC_KEY_PEM ausente` ou `MCP_SERVICE_SECRET ausente`. O processo
recusa subir sem eles em vez de ficar verde sem atender ninguém.

---

## 2. O authorization server responde?

```bash
curl -s https://auth.dev.smartcoreassistant.com.br/.well-known/oauth-authorization-server | jq .
```

**Esperado:** JSON com `issuer`, `authorization_endpoint`, `token_endpoint` e —
o campo que não pode faltar — `"code_challenge_methods_supported": ["S256"]`.
Sem ele, um cliente MCP conforme **recusa prosseguir**, e é a primeira coisa a
conferir se o Claude disser que não consegue conectar.

Confira também que `issuer` é **idêntido** à URL de onde o documento veio. Uma
barra sobrando ali faz o cliente rejeitar o AS inteiro.

---

## 3. O resource server anuncia onde autorizar?

```bash
curl -si https://mcp.dev.smartcoreassistant.com.br/mcp \
  -X POST -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | head -20
```

**Esperado:** `HTTP/2 401` com um header
`WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource"`.

Esse header é o que faz a descoberta funcionar: é por ele que o cliente sabe
**onde** pedir autorização. Sem ele o Claude mostra "não foi possível conectar"
sem mais detalhe.

```bash
curl -s https://mcp.dev.smartcoreassistant.com.br/.well-known/oauth-protected-resource | jq .
```

**Esperado:** `resource` apontando para `mcp.dev…` e `authorization_servers`
contendo `auth.dev…`.

---

## 4. A migration aplicou?

```bash
docker exec smart-core-v2-dev-postgres-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "\d mcp_oauth_grant" -c "SELECT version, description FROM _sqlx_migrations ORDER BY version DESC LIMIT 3;"
```

**Esperado:** a tabela existe, com RLS, e `0032 | mcp oauth grant` no topo da
lista de migrations.

> A migration nasceu como `0030` e virou `0032` porque a `dev` usou `0030` e
> `0031` enquanto a N13 era escrita. Duas migrations com a mesma versão fazem o
> `sqlx::migrate!` recusar a aplicação — o motivo está na própria migration.

---

## 5. Conectar um agente de verdade

O caminho mais curto para o primeiro teste é o Claude Code, porque ele mostra o
fluxo no terminal:

```bash
claude mcp add --transport http smartcore-dev https://mcp.dev.smartcoreassistant.com.br/mcp
```

Na primeira chamada ele abre o navegador. O que deve acontecer, em ordem:

1. **Tela de login** com o nome do aplicativo no topo.
2. **Tela de consentimento** mostrando: o nome do aplicativo, o **host de
   retorno** e a lista de permissões.
3. Depois de aprovar, o cliente passa a listar as tools.

### O que olhar nessa tela — é aqui que o desenho se prova

| Verificar | Por que importa |
|---|---|
| A lista só oferece permissões que **este** usuário tem | É a regra do subconjunto, e ela é estrutural: um `staff` não vê `tenant:admin` para marcar. Entre com uma conta não-admin para conferir |
| O host de retorno aparece | O nome do aplicativo é escolhido por ele e pode mentir; o host é o que o usuário reconhece |
| Desmarcar um item reduz o acesso de verdade | Desmarque tudo menos leitura e confira no passo 6 que as tools de escrita **não aparecem** |

---

## 6. O teste de aceitação do plano

Com um agente conectado por uma conta **admin**, e partindo de um tenant vazio,
peça exatamente isto e **não ajude**:

> Configure um funil de vendas com 4 etapas e um departamento comercial.

**Aprovado quando:** o agente conclui sozinho — cria o departamento, cria o
fluxo, cria as quatro etapas na ordem.

**Se ele travar ou errar**, o defeito está nas **descrições das tools**, não no
código. É o que o plano diz e é a leitura certa: a descrição é a interface, e o
agente só acerta se ela disser o que faz, quando usar e quando não usar. Anote
onde ele hesitou — isso é o material para melhorar a descrição.

### Os outros três testes que valem fazer no primeiro dia

1. **Filtro por escopo.** Conecte uma segunda vez com conta `staff` e compare a
   lista de tools. Precisam ser **diferentes**, e a do `staff` não pode ter
   `create_fluxo` nem `get_tenant_config`.
2. **Confirmação de ação irreversível.** Peça para desativar um fluxo. O agente
   deve ser recusado na primeira tentativa e precisar informar o **nome exato**
   do fluxo. Um id inventado não passa.
3. **Desconectar.** Na tela *Configurações → Aplicativos conectados*, desconecte
   e peça algo ao agente. Ele deve falhar pedindo para reconectar — em até 15
   minutos, que é a janela real e está escrita na tela.

---

## 7. Onde olhar quando algo não funcionar

```bash
# O que o servidor MCP registrou
docker logs --tail 100 smart-core-v2-dev-mcp_server-1

# O fluxo OAuth (login, consentimento, troca de token) — spans oauth.*
docker logs --tail 100 smart-core-v2-dev-control_plane-1 | grep -i oauth

# A trilha: o que o agente fez, com origem marcada
docker exec smart-core-v2-dev-postgres-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT created_at, event_type, user_agent FROM audit_log
    WHERE user_agent LIKE 'SmartCoreAssistant-MCP%' ORDER BY created_at DESC LIMIT 20;"
```

No Grafana, o dashboard **"Smart Core v2 — Agentes de IA (MCP)"**. O painel que
importa é **Recusas por motivo**: pico de `rate_limit` ou de `escopo` é a
assinatura de agente em laço ou de token vazado sendo sondado.

### Sintomas e causas prováveis

| Sintoma | Provável causa |
|---|---|
| Claude: "não foi possível conectar" | Passo 3 — falta o `WWW-Authenticate`, ou o `issuer` da metadata não bate com a URL |
| Login aceita e a tela de consentimento não abre | Ticket expirado (10 min) ou Redis fora; ver log do `control_plane` |
| "chave inválida" em toda troca de token | O PEM chegou com `\n` literal e a normalização não rodou. Os dois lados normalizam — se aparecer, o valor no `.env` está em outro formato |
| Agente lista zero tools | O token não tem escopo nenhum que case, ou o usuário foi desativado |
| Toda tool recusa por permissão | Escopo concedido menor que o necessário: reconectar concedendo mais |

---

## 8. Se precisar reverter

O módulo é **aditivo**: nada do que já existia depende dele.

```bash
# 1. Derruba só o servidor MCP. O resto da stack não se mexe.
cd /opt/smartcore/ops/smart-core-assistant-v2/docker/dev
docker compose --env-file .env stop mcp_server

# 2. Se precisar desligar o authorization server sem derrubar o control_plane:
#    apague MCP_OAUTH_PRIVATE_KEY_PEM do dev.env e recrie o serviço. Sem a chave
#    ele não inicia o AS e segue atendendo o RPC interno normalmente.
```

**A migration não precisa ser revertida.** A tabela `mcp_oauth_grant` vazia não
afeta nada; reverter é trabalho sem benefício, e a trilha de auditoria referencia
`grant_id`.

**O que NÃO reverter sem pensar:** as mudanças de RBAC (N13.3). Elas **ampliam**
acesso nas rotas de configuração (um `manager` passa a editar fluxo) e
**restringem** nas operacionais (um `viewer` para de enviar mensagem). Reverter
devolve o defeito de segurança junto com o resto.

---

*Escrito em 2026-09-11, na publicação da N13 na `dev`. Aterrado no plano
`.context/plans/n13-mcp-agentes.md` e no `mcp_server/README.md`.*
