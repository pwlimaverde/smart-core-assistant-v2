# 29 — Mapeamento de lacunas v1 → v2: usuários, permissões e configuração

> Levantado em 2026-09-06 comparando `old/smart-core-assistant-painel` (Django,
> v1) com a v2 em execução no dev. Motivado por três sintomas reais do teste:
> atendente cadastrado sem convite por e-mail, tela de usuários mostrando só o
> admin, e configuração do tenant "incompleta".
>
> **Método:** schema do banco (v1 `models.py` × v2 `information_schema`),
> contratos (`admin.proto`), telas (`templates/apps/**` × rotas do Flutter) e
> rastreio de uso no código Rust. Nada aqui é suposição.
>
> **Revisado em 2026-09-06:** os quatro pontos que estavam "a confirmar" foram
> fechados (seção 7) e **duas conclusões foram corrigidas** — L3 e L4. Ver os
> avisos ⚠️ no corpo delas.

---

## 1. Resumo executivo

O **schema** da v2 está completo — em vários pontos é superconjunto da v1.
O que falta é **comportamento e superfície**: campos que existem no banco e
ninguém edita, um fluxo de convite que não entrega o convite, e um fallback de
permissões que dá escrita a quem deveria só ler.

| Área | Schema | Contrato | Tela | Veredito |
|---|---|---|---|---|
| Config do tenant | ✅ 33 campos (v1: 12) | ✅ | ⚠️ **6 editáveis** | Tela incompleta |
| Papéis/permissões | ✅ role + module + flow | ✅ | ⚠️ editor cru | Sem papel somente-leitura |
| Convite de usuário | ✅ token, validade, revogação | ✅ | ✅ | ❌ **sem envio de e-mail** |
| Atendente ↔ usuário | ✅ `usuario_id` existe | ❌ | ❌ | **Não vincula** |
| Liga/desliga do bot | ❌ | ❌ | ❌ | **Perdido na migração** |
| Recuperação de senha | — | ❌ | ❌ | **Não portado** |

---

## 2. Usuários, papéis e convites

### 2.1 O que a v1 tinha

`TenantUser` (v1 `app/tenants/models.py`):

```python
role = CharField(choices=[
    ("admin",   "Administrador"),
    ("manager", "Gerente"),
    ("staff",   "Funcionário"),
    ("viewer",  "Visualizador"),
], default="staff")
module_permissions = JSONField()  # {modulo: {view, edit, delete}}
flow_permissions   = JSONField()  # [ids de FluxoAtendimento]
```

Módulos de permissão (`_available_permission_modules`):
`PAINEL_ADMIN` (Clientes, Operacional, Atendimentos), `TREINAMENTO`,
`CONFIGURACOES`, `USUARIOS` — cada um com `view`/`edit`/`delete`.

Telas (`templates/apps/tenants/users/`): `list`, `invite`, `invite_email`,
`activate`, `invite_expired`, `edit_permissions`.

Views (`app/tenants/views/invites.py`): `list_users`, `invite_user`,
`resend_invite`, `_send_invite_email`, `activate_account(token)`,
`edit_permissions(user_id)`.

### 2.2 O que a v2 tem

Schema **presente e equivalente**: `tenants_tenantuser` (role,
module_permissions, flow_permissions, is_active, created_by_id) e
`tenants_tenantinvite` (email, name, role, module_permissions,
flow_permissions, token, expires_at, used, **revoked**, revoked_at) — este
último inclusive melhor que a v1, que não tinha revogação.

RPCs: `CreateInvite`, `AcceptInvite` (pública), `ListInvites`, `RevokeInvite`,
`ListTenantUsers`, `UpdateTenantUser`. Telas: `/tenant/convites`,
`/tenant/usuarios`, `/aceitar-convite`.

### 2.3 Lacunas confirmadas

**L1 — Convite não é entregue.** `CreateInviteResponse` devolve o objeto com o
token; **não existe envio de e-mail em nenhum lugar do servidor** (busca por
`smtp|send_mail|lettre` no `server/` não retorna nada). Na v1,
`_send_invite_email` montava `EmailMultiAlternatives` com o template
`invite_email.html` e enviava, com `resend_invite` para reenviar.
→ Hoje o admin precisa copiar o link e mandar por fora. **Não há `resend`.**

**L2 — Cadastrar atendente não convida ninguém.** `CreateMyAtendenteRequest`
tem `nome, email, cargo, fluxo_id, departamento_id` e cria **apenas** a linha
em `oraculo_atendente`. A coluna `usuario_id` (FK para `auth_user`) existe e
fica **nula**. Por isso a tela de usuários mostra só o admin: ela lista
`tenants_tenantuser`, e o atendente nunca entra lá.
→ Falta decidir e implementar o elo: cadastrar atendente **cria convite** para
o e-mail informado, e o aceite preenche `usuario_id`.

**L3 — `module_permissions` ~~é inerte~~ mudou de forma, e o fallback é largo
demais.**

> ⚠️ **Correção (2026-09-06).** A primeira versão desta lacuna dizia que o campo
> era inerte. **Estava errado.** Ele é lido, e é a fonte primária dos escopos do
> token.

`derivar_escopos` (`application/src/auth/login.rs:244`, e o gêmeo em
`refresh.rs:133`) resolve os escopos do JWT nesta ordem:

1. superusuário → `["*"]`;
2. `module_permissions` como **array** → vira a lista de escopos tal e qual;
3. `module_permissions` como **objeto** → as chaves com valor `true`;
4. **fallback pelo `role`**, quando o campo está vazio.

Esses escopos são exigidos de verdade no `data_postgres`
(`ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])`). O campo
funciona. `flow_permissions` também (RBAC fino por fluxo, `grpc_web.rs:434`, com
teste `listar_por_status_filtra_por_flow_permission`).

O que **de fato** mudou em relação à v1 é a **forma** e o **alcance**:

| | v1 | v2 |
|---|---|---|
| Formato | `{modulo: {view, edit, delete}}` | lista plana de escopos (`"atendimentos:write"`) |
| Granularidade | por módulo × ação | por escopo, sem separar leitura de escrita por módulo |
| Papéis | `admin`, `manager`, `staff`, `viewer` | **só `admin` e `staff`** nas telas |

→ A lacuna real é outra, e é de **segurança**: o fallback do `role` dá a
**qualquer** não-admin `atendimentos:read`, `atendimentos:write` e
`clientes:write`. **Não existe papel somente-leitura** — o `viewer` da v1 não
tem equivalente possível hoje, porque um usuário sem `module_permissions` cai no
fallback e nasce podendo escrever.

**L4 — Editor de permissões existe, mas é cru.**

> ⚠️ **Correção (2026-09-06).** Confirmado na UI: `/tenant/usuarios` e
> `/tenant/convites` **já editam** papel, escopos e fluxos.

`tenant_users_page.dart` e `invites_page.dart` oferecem: dropdown de papel
(**só `admin` e `staff`**), `CheckboxListTile` por escopo e — este é o ponto —
um `AppTextField` com o rótulo *"IDs dos fluxos permitidos (separados por
vírgula)"*, hint `ex: 1,2,3`.

→ O que falta não é a tela, é o **acabamento**: escolher fluxo por nome em vez de
digitar ID, escopos com rótulo de negócio em vez de `atendimentos:write`, e os
papéis que faltam (`manager`, `viewer`) — este último bloqueado pela L3.

**L5 — Recuperação de senha não portada.** A v1 tinha o ciclo completo
(`password_reset_form`, `_done`, `_confirm`, `_complete`, `_email`). Na v2 não
há rota nem RPC. Um funcionário que esquece a senha **não tem saída** — e sem
e-mail (L1) não haveria como entregar o link mesmo que existisse.

---

## 3. Configuração do tenant

### 3.1 Campos

v1 (`TenantConfig`, 12): `dados_empresa, persona_bot, bot_agent_name,
msg_fallback, msg_sem_info, msg_transferencia, entity_types, llm_class, model,
transcription_provider, transcription_model` (+ tenant).

v2 (`tenants_tenantconfig`, 33): tudo isso **mais** `llm_temperature,
vision_provider, vision_model, embeddings_class, embeddings_model, chunk_size,
chunk_overlap, similarity_threshold, vector_distance_threshold, api_keys,
brand_name, primary_color, secondary_color, timezone, language_code,
transcription_enabled, prompts, msg_pesquisa_satisfacao,
pesquisa_satisfacao_ativa`.

**Nada foi perdido.** O banco da v2 é superconjunto.

### 3.2 Lacuna

**L6 — A tela expõe 6 de 33.** `tenant_own_config_page.dart` edita
`dados_empresa, persona_bot, bot_agent_name, msg_fallback, msg_sem_info,
msg_transferencia`, e mostra `LLM/model` como **texto read-only**. Ficam sem
superfície: identidade visual (brand/cores), fuso e idioma, pesquisa de
satisfação (mensagem e liga/desliga), transcrição (liga/desliga), prompts, e os
parâmetros de RAG.

A v1 dividia isso em telas próprias (`config_ai`, `config_evolution`,
`config_database`, `config_trello`, `config_debug`) — a v2 precisa decidir
**quais** desses pertencem ao tenant e quais são do superusuário
(`/admin/tenant-config` já existe e **a confirmar** o que expõe).

---

## 4. Resposta automática do bot

**L7 — Capacidade perdida.** A v1 tinha `AppInstance.resposta_bot`
(BooleanField, default True, *"Se True, o bot pode responder automaticamente
mensagens desta instância"*), a view `InstanceToggleBotView` (POST por
instância, com checagem de permissão) e o `bot_rules_engine` consultando
`_is_instance_bot_enabled(api_key)` **antes de responder**. Havia ainda o
desligamento implícito ao assumir: *"Atendente assumiu o atendimento (Bot
desativado)"*.

Na v2, `whatsapp_instance` tem `id, tenant_id, api_key, active, name,
instance_id, phone_number, provider, connection_state, last_state_check,
last_connection_state, media_storage_backend, subscribed_events, created_at` —
**nenhum equivalente**. `tenants_tenantconfig` também não: só
`transcription_enabled` e `pesquisa_satisfacao_ativa`.

→ É a lacuna mais sensível para a operação: **não há como calar o bot** quando
o dono quer atender manualmente. Requer migration, contrato, checagem no worker
(antes de acionar a IA) e o controle na tela.

**Confirmado (2026-09-06):** a v2 **desliga** o bot ao assumir —
`assumir_atendimento` grava `bot_pode_atender = false`
(`atendimentos.rs:461`), e `desatribuir` não religa, por decisão documentada no
trait. O que não existe é o caminho de volta: **nenhum `UPDATE` no servidor
devolve `bot_pode_atender` para `true`**, e o campo não aparece em nenhum arquivo
Dart. O interruptor da conversa é de mão única e sem botão. Ver F2 no doc 30.

---

## 5. Telas da v1 sem equivalente na v2

| v1 | v2 | Observação |
|---|---|---|
| `users/edit_permissions.html` | — | L4 |
| `users/invite_email.html` | — | L1 (não há e-mail) |
| `users/invite_expired.html` | — | convite expirado sem tela própria |
| `usuarios/password_reset_*` (5 telas) | — | L5 |
| `tenants/subscription_expired.html` | — | ver plano `cadastro-retomavel-e-pagamento` |
| `tenants/backoffice/register_payment.html` | — | registro manual de pagamento (`tenants_paymentrecord` existe, vazia) |
| `settings_manager/configuracoes/whitelist*` | — | `whatsapp_whitelist` existe no banco, sem tela |
| `evolution_sync/instance_detail.html` | `/tenant/conexoes` | parcial — sem detalhe nem toggle do bot |
| `trello_sync/*` | — | **descontinuado** por decisão de produto (2026-09-06) |
| `core/dashboard.html` | `/tenant/painel` | equivalente |

---

## 6. Ordem sugerida de correção

1. **L7 — liga/desliga do bot.** Perda de capacidade operacional; sem ele o
   atendimento humano não tem como silenciar a IA.
2. **L1 + L2 — convite entregue e atendente virando usuário.** É o que trava a
   entrada de equipe hoje; sem isso o tenant é de uma pessoa só.
3. **L3 — fechar o fallback de escopos.** Hoje qualquer não-admin nasce com
   `atendimentos:write` e `clientes:write`; falta o papel somente-leitura.
4. **L6 — completar a tela de configuração**, definindo a fronteira tenant ×
   superusuário.
5. **L5 — recuperação de senha** (depende do canal de e-mail de L1).
6. **L4 — editor de permissões**, depois que L3 estiver decidido.

**Dependência transversal:** L1 e L5 exigem **canal de e-mail**, que a v2 não
tem em lugar nenhum. Essa é a primeira decisão a tomar (SMTP próprio, SES,
Resend…), e ela também serve ao alerta de operação descrito em
`28-operacao-autonoma-e-alertas.md`.

## 7. Pontos confirmados em 2026-09-06

Os quatro pontos que ficaram em aberto foram fechados por leitura da UI e do
código:

- **`/tenant/usuarios` e `/tenant/convites`** editam papel, escopos e fluxos —
  L4 revisada acima. A tela existe; o acabamento é que falta.
- **`/admin/tenant-config`** (superusuário) edita **24 campos**: os seis prompts,
  LLM (classe/modelo/temperatura), transcrição, visão, embeddings, chunk,
  os dois limiares e as três chaves de API — com o tenant identificado por **UUID
  digitado à mão**. A fronteira, portanto, **já existe de fato**: motor de IA e
  segredos ficam com o superusuário; texto e identidade com o tenant.
  → O que **nenhuma das duas telas** edita: `brand_name`, `primary_color`,
  `secondary_color`, `timezone`, `language_code`, `transcription_enabled`,
  `prompts`, `msg_pesquisa_satisfacao`, `pesquisa_satisfacao_ativa`. São **9
  campos órfãos** — e a pesquisa de satisfação, que o scheduler já executa, não
  tem como ser ligada ou desligada por ninguém.
- **A v2 silencia o bot ao assumir** — confirmado na seção 4.
- **Trello: descontinuado** por decisão de produto (2026-09-06). Sai do escopo e
  da tabela da seção 5.
