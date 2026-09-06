# 29 — Mapeamento de lacunas v1 → v2: usuários, permissões e configuração

> Levantado em 2026-09-06 comparando `old/smart-core-assistant-painel` (Django,
> v1) com a v2 em execução no dev. Motivado por três sintomas reais do teste:
> atendente cadastrado sem convite por e-mail, tela de usuários mostrando só o
> admin, e configuração do tenant "incompleta".
>
> **Método:** schema do banco (v1 `models.py` × v2 `information_schema`),
> contratos (`admin.proto`), telas (`templates/apps/**` × rotas do Flutter) e
> rastreio de uso no código Rust. Nada aqui é suposição — o que não pôde ser
> confirmado está marcado como **a confirmar**.

---

## 1. Resumo executivo

O **schema** da v2 está completo — em vários pontos é superconjunto da v1.
O que falta é **comportamento e superfície**: campos que existem no banco e
ninguém edita, permissões que são gravadas e nunca aplicadas, e um fluxo de
convite que não entrega o convite.

| Área | Schema | Contrato | Tela | Veredito |
|---|---|---|---|---|
| Config do tenant | ✅ 33 campos (v1: 12) | ✅ | ⚠️ **6 editáveis** | Tela incompleta |
| Papéis/permissões | ✅ role + module + flow | ⚠️ parcial | ❌ sem editor | `module_permissions` inerte |
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

**L3 — `module_permissions` é inerte.** Aparece só em `INSERT`/`UPDATE`
(`signup.rs`, `tenant.rs`); **nenhum ponto do código lê para autorizar**. Os
escopos vêm do `role`. Já `flow_permissions` **é aplicado de verdade** (RBAC
fino por fluxo, resolvido em `grpc_web.rs:434` e usado no `data_postgres` —
há teste `listar_por_status_filtra_por_flow_permission`).
→ Ou implementar a checagem por módulo, ou remover o campo. Hoje ele **promete
uma segurança que não existe** — o pior dos dois mundos.

**L4 — Sem editor de permissões.** A v1 tinha `edit_permissions.html` com os
módulos e as ações. A v2 tem `UpdateTenantUser`, mas **a confirmar** se a tela
`/tenant/usuarios` expõe módulos e fluxos ou apenas ativa/desativa.

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

**A confirmar:** se a v2 desliga o bot ao assumir o atendimento (a v1 fazia).
Há indício de que sim — o commit `cf30905` menciona "assumir a conversa não
avisava o contato" — mas não foi verificado neste levantamento.

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
| `trello_sync/*` | — | integração Trello inteira (fora de escopo?) |
| `core/dashboard.html` | `/tenant/painel` | equivalente |

---

## 6. Ordem sugerida de correção

1. **L7 — liga/desliga do bot.** Perda de capacidade operacional; sem ele o
   atendimento humano não tem como silenciar a IA.
2. **L1 + L2 — convite entregue e atendente virando usuário.** É o que trava a
   entrada de equipe hoje; sem isso o tenant é de uma pessoa só.
3. **L3 — decidir sobre `module_permissions`.** Aplicar ou remover; manter
   inerte é risco de segurança presumida.
4. **L6 — completar a tela de configuração**, definindo a fronteira tenant ×
   superusuário.
5. **L5 — recuperação de senha** (depende do canal de e-mail de L1).
6. **L4 — editor de permissões**, depois que L3 estiver decidido.

**Dependência transversal:** L1 e L5 exigem **canal de e-mail**, que a v2 não
tem em lugar nenhum. Essa é a primeira decisão a tomar (SMTP próprio, SES,
Resend…), e ela também serve ao alerta de operação descrito em
`28-operacao-autonoma-e-alertas.md`.

## 7. Pontos a confirmar antes de planejar

- O que `/tenant/usuarios` e `/tenant/convites` já expõem na prática (a leitura
  foi do schema e das rotas, não da UI renderizada).
- O que `/admin/tenant-config` (superusuário) edita hoje — para não duplicar
  superfície com a tela do tenant.
- Se a v2 já silencia o bot ao assumir o atendimento.
- Se a integração Trello (`trello_sync`, 5 models na v1) entra no escopo da v2
  ou foi descontinuada por decisão de produto.
