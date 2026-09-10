# 31 — Superfície completa da v1: reverificação e delta sobre o doc 26

> **Este documento não descobre a superfície da v1 — ele a reverifica.** O
> inventário já existia no doc [26](./26-levantamento-paridade-v1-v2.md), de
> **2026-08-08**, que mapeou os 13 apps, o `tenant-admin`, o
> `CELERY_BEAT_SCHEDULE` e consolidou **33 frentes de trabalho**.
>
> O que esta varredura acrescenta, um mês depois:
>
> 1. **O estado atual de cada frente** — quatro dos cinco "defeitos em caminho
>    que já roda" foram corrigidos desde então;
> 2. **Duas correções a afirmações dos docs 29 e 30**, vindas do próprio
>    checklist da v1 (N3 e N4);
> 3. **A reconciliação das quatro taxonomias** que passaram a coexistir — as 33
>    frentes do doc 26, os L do 29, os F do 30 e os D/C/I/O/U do 00-0609 (§7);
> 4. Os números exatos: **115 rotas**, **25 tarefas Celery**, **8 módulos de
>    permissão**, **4 papéis**.
>
> Levantado em 2026-09-06 por leitura direta de `urls.py`, `tasks.py`,
> `admin.py`, `tenant_admin.py`, `settings.py` e `permissions.py` da v1,
> cruzados com o `admin.proto`, o `scheduler.rs` e as rotas do Flutter da v2.

---

## 1. Os dois admins da v1 — confirmando o doc 26 §2.2

O doc 26 já registrava isto ("ponto fácil de subestimar"). A reverificação
confirma e fecha a contagem: são **21 modelos** registrados no
`tenant_admin_site`, não 17 como diz o texto de lá (a lista dele já trazia 21;
o número no corpo estava desatualizado).

```
core/urls.py
  path("admin/",        admin.site.urls)        → Django admin (superusuário)
  path("tenant-admin/", tenant_admin_site.urls) → Painel do Cliente (o tenant)
```

`TenantAdminSite` (`tenants/admin_client.py`) é um `AdminSite` próprio, com
`has_permission` que resolve o tenant pelo usuário logado e exige ser **dono** ou
ter `has_module_permission(PAINEL_ADMIN, "view")` — ou, na falta dele, `view` em
`CLIENTES`, `OPERACIONAL` ou `ATENDIMENTOS`.

**Consequência para a v2** — e o doc 26 já concluía o mesmo: o tenant da v1
tinha CRUD completo, gratuito e gerado pelo Django. A v2 **não replica admin
genérico**, e essa é a decisão certa (tela por caso de uso, não por tabela) —
mas significa que cada CRUD precisa existir explicitamente.

### Os 21 modelos do tenant-admin (fora Trello) × v2

| Modelo (v1 `tenant_admin.py`) | Onde está na v2 | Situação |
|---|---|---|
| `Atendimento` | `/atendimentos` (Kanban) | ✅ |
| `Mensagem` | chat do Kanban | ⚠️ sem mídia (F11) e sem lida (F12) |
| `CampoPersonalizado` | — | ❌ **sem tela e sem RPC** |
| `ValorCampoAtendimento` | — | ❌ sem write-back (F14) e sem exibição na ficha |
| `Etiqueta` | Kanban | ✅ `CreateEtiqueta`, `AlternarEtiqueta` |
| `EtiquetaAtendimento` | Kanban | ✅ |
| `Nota` | Kanban | ✅ `CreateNota` |
| `Contato` | `/tenant/contatos` | ✅ |
| `Cliente` | — | ❌ **F13** — tabela com RLS e índice de CNPJ, zero código |
| `EvolutionInstance` | `/tenant/conexoes` | ✅ |
| `EvolutionContact` | `/tenant/contatos` | ✅ |
| `WhiteList` | — | ❌ **F9** — regra aplicada, sem tela |
| `Departamento` | `/tenant/equipe` (aba) | ✅ |
| `Atendente` | `/tenant/equipe` (aba) | ✅ |
| `AppInstance` | `whatsapp_instance` | ⚠️ perdeu `resposta_bot` (F2) e `departamento` (F5) |
| `FluxoAtendimento` | `/tenant/fluxos` | ✅ |
| `EtapaFluxo` | `/tenant/fluxos/:id/etapas` | ✅ |
| `MovimentoFluxo` | `oraculo_movimento_fluxo` | ✅ gravado e lido em `movimentos.rs` |
| `Treinamento` | `/tenant/treinamento` | ✅ |
| `Documento` | `/tenant/treinamento` | ✅ |
| `QueryCompose` | intents em `/tenant/treinamento` | ✅ `ListMy/Create/Update/RemoveMyIntent` |

**Placar:** 17 cobertos, 2 parciais, 4 ausentes — `CampoPersonalizado`,
`ValorCampoAtendimento`, `Cliente` e `WhiteList`.

### Django admin (superusuário) × v2

| v1 | v2 | Situação |
|---|---|---|
| `Plan` | `CreatePlan` / `UpdatePlan` | ✅ |
| `Tenant` | `/admin/tenants` | ✅ |
| `Subscription` | `/admin/billing` | ✅ |
| `PaymentRecord` | — | ❌ tabela existe e está vazia; sem tela (ver doc 29 §5) |
| `CoreSettings` | `/admin/core-settings` | ✅ |
| `User` | — | ⚠️ sem gestão global de usuários pelo superusuário |

A v2 acrescenta o que a v1 não tinha: `/admin/audit`, `/admin/feature-flags`,
`/admin/evolution`, `/admin/tenant-config`, `/admin/dashboard`.

---

## 2. Permissões: o que a v1 realmente fazia

`TenantModule` (`tenants/permissions.py`) tem **8 módulos**:
`painel_admin`, `clientes`, `operacional`, `treinamento`, `atendimentos`,
`atendimento` (workspace), `configuracoes`, `usuarios` — cada um com
`view`/`edit`/`delete`.

`TenantRoleType` tem **4 papéis**: `admin`, `manager`, `staff`, `viewer`.

E `has_module_permission` **era efetivamente aplicado**: é ele que decide o
acesso ao tenant-admin inteiro.

→ Isto **confirma a L3 revisada** do doc 29: a v2 não abandonou permissão, trocou
o formato (matriz módulo × ação → lista plana de escopos) e perdeu dois papéis.
O risco continua sendo o mesmo já registrado: **não existe papel
somente-leitura**, porque o fallback dá escrita a qualquer não-admin.

---

## 3. Celery: as 25 tarefas da v1

### Agendamento real (`CELERY_BEAT_SCHEDULE`)

Só **duas** tarefas eram periódicas de fato:

| Tarefa | Cadência v1 | v2 | Situação |
|---|---|---|---|
| `keepalive_evolution_instances` | **60 s** | `reconciliar_conexoes_whatsapp` | ✅ criada nesta sessão |
| `purge_old_media_all_tenants` | diária, 03:30 | `processar_midia_expirada` (30 d) | ✅ |

O `CELERY_BEAT_SCHEDULER` era o `DatabaseScheduler`, então outras rotinas
**poderiam** ser agendadas pelo admin — mas nenhuma outra aparece no código.

### Tarefas por evento

| Tarefa v1 | App | Equivalente v2 | Situação |
|---|---|---|---|
| `process_contact_response_task` | atendimentos | `buffer_mensagens.rs` | ✅ |
| `verificar_feedback_atendimento` | atendimentos | `processar_feedback_vencido` | ✅ |
| `extract_custom_fields_async` | atendimento_unificado | — | ❌ **F14** |
| `check_subscription_expirations` | tenants | — | ❌ **novo — ver N1 abaixo** |
| `notify_expiring_subscriptions` | tenants | — | ⚠️ era **stub** na v1 (ver N2) |
| `task_gerar_embedding_documento` | treinamento | `processar_vetorizacao_pendente` | ✅ |
| `task_gerar_embedding_query_compose` | treinamento | `processar_intents_sem_embedding` | ✅ |
| `task_gerar_documentos_treinamento` | treinamento | `processar_vetorizacao_pendente` (chunking) | ✅ |
| 14 tarefas `trello_sync` | trello_sync | — | ⛔ **descontinuado** |

**Placar Celery:** das 11 tarefas não-Trello, **8 cobertas**, 1 ausente (F14),
1 ausente nova (N1) e 1 que nunca funcionou na v1 (N2).

---

## 4. Achados novos desta varredura

### N1 — Assinatura vencida não suspende ninguém 🔴 **novo**

A v1 tinha `check_subscription_expirations`: busca `Subscription` `ACTIVE` com
`current_period_end < now` e muda o status para `SUSPENDED`.

O `scheduler.rs` da v2 tem cinco rotinas e **nenhuma olha para assinatura**.
Nada em `data_postgres` suspende por vencimento — `period_end` só é escrito no
momento da confirmação de pagamento.

**Consequência:** uma assinatura vence e o tenant continua operando
indefinidamente. É o espelho do beco sem saída tratado no plano
`cadastro-retomavel-e-pagamento` — e o mesmo assunto.
→ **Entra naquele plano**, não nos dois novos.

### N2 — A v1 nunca notificou vencimento (não portar uma ilusão) ⚪

`notify_expiring_subscriptions` existe, mas o corpo é `logger.info(...)` com o
comentário literal *"AQUI IMPLEMENTAR ENVIO DE EMAIL FUTURAMENTE"*. Nunca foi
agendada e nunca enviou nada.

→ Não é lacuna de portabilidade; é funcionalidade nova, e depende do canal de
e-mail da E1 do plano de equipe.

### N3 — A v1 **não** encerrava por inatividade 🟠 **corrige o F6**

O doc 30 afirmava, com base no diagrama de fluxo, que a v1 encerrava atendimento
parado em 30 min. **O código não faz isso.** O único timeout é o da **pesquisa
de satisfação** (5 min, `verificar_feedback_atendimento`).

A origem da afirmação é `RESUMO_FLUXO_RECEBIMENTO_MENSAGEM.md:140` — *"Cliente
inativo: 30 minutos (configurável)"* — descrição do fluxo desejado. O próprio
`CHECKLIST_IMPLEMENTACAO.md:158` da v1 marca **❌ "Timeout de atendente com
notificações"** como não implementado.

→ O F6 continua no plano (é decisão de produto do usuário: 30 min por tenant),
mas muda de natureza: **não é portar, é construir**. Sem referência de
implementação na v1.

### N4 — O F7 também nunca existiu na v1 🟠 **corrige o F7**

Mesmo checklist, mesma seção: **❌ "Notificações push para novos atendimentos"**,
**❌ "Dashboard em tempo real para atendentes"**, **❌ "Sistema de retry para
busca de atendente"**, **❌ "Escalação automática"**.

→ O F7 é construção nova. Isso **reduz a urgência** dele e reforça deixá-lo por
último, depois de F3 e F8.

> ⚠️ **Cuidado com a documentação da v1 em geral.** O `CHECKLIST_IMPLEMENTACAO.md`
> é de **julho de 2025** e marca como ausente coisas que a v1 depois construiu
> (a resposta automática do bot, por exemplo). Ele serve para **derrubar**
> afirmações dos diagramas, não para provar ausência no estado final. Onde os
> dois divergem, vale o código.

### N5 — Timeline da conversa 🟢 **novo**

`gestao_kanban/api_urls.py` tinha `conversations/<id>/timeline/`. A v2 não tem
RPC de timeline. O `historico_status` e o `oraculo_movimento_fluxo` existem e são
gravados — a matéria-prima está lá, falta a leitura.

### N6 — Exportação do quadro 🟢 **novo**

A v1 tinha `kanban/api/export/`. A v2 só tem `ExportTenantsCsv`, que é do
**superusuário** e exporta tenants, não o quadro do cliente.

### N7 — Ciclo de feedback do treinamento 🟢 **novo**

A v1 tinha três rotas de ensaio: `testar-query`, `testar-resposta` e
**`feedback-resposta`**. A v2 tem `TestarPergunta` ligado ponta a ponta
(runtime_api + datasource Flutter), mas **não tem o feedback** — o retorno que
alimentaria a melhoria do RAG.

> Nota sobre o sintoma relatado no teste ("o teste de IA não respondeu"):
> `TestarPergunta` **existe e está ligado nas duas pontas**. É defeito de
> execução, não lacuna de superfície — investigar como bug.

### N8 — Utilidades de configuração do tenant 🟢 **novo**

`TestConnectionView` (`config/test-connection/<service_type>/`) testava a conexão
com cada serviço externo, e `RunMigrationsView` rodava migrações pelo painel.
A v2 não tem equivalente do primeiro — útil para o dono descobrir sozinho que a
chave de API está errada. O segundo não faz sentido na arquitetura da v2.

---

## 5. Rotas da v1 sem equivalente na v2 — lista fechada

Das 115 rotas, estas são as que **não** têm destino na v2 (excluídas as 4 de
Trello e as de ClickUp, que é `include` para um pacote inexistente, sob
condicional):

| Rota v1 | Assunto | Destino |
|---|---|---|
| `tenant-admin/**` (20 modelos) | CRUD do tenant | §1 — 4 modelos sem tela |
| `configuracoes/whitelist*` (6 rotas) | whitelist | **F9** |
| `usuarios/password-reset*` (4 rotas) | recuperação de senha | **L5** |
| `apps/tenants/users/<id>/permissions/` | editor de permissões | **L4** (existe, cru) |
| `apps/tenants/users/invite/<id>/resend/` | reenviar convite | **L1** |
| `apps/tenants/bo/tenant/<id>/register-payment/` | pagamento manual | doc 29 §5 |
| `apps/tenants/config/test-connection/<tipo>/` | testar conexão | **N8** |
| `workspace/kanban/api/export/` | exportar quadro | **N6** |
| `workspace/kanban/api/conversations/<id>/timeline/` | linha do tempo | **N5** |
| `workspace/kanban/api/conversations/<id>/custom-fields/<slug>/` | campos personalizados | **F14** |
| `workspace/chat/api/conversations/<id>/upload/` | enviar mídia | **F10 + F11** |
| `workspace/chat/api/conversations/<id>/medias/` | galeria de mídia | **F11** |
| `workspace/chat/api/messages/<id>/media/` | baixar mídia | **F11** |
| `workspace/chat/api/conversations/<id>/mark-read/` | marcar lida | **F12** |
| `workspace/chat/api/notifications/unread-count/` | não lidas | **F12** |
| `workspace/chat/api/conversations/<id>/presence/` | presença | ⚪ existe como evento realtime |
| `treinamento/feedback-resposta/` | feedback do ensaio | **N7** |
| `sync/evolution/instances/<pk>/toggle-bot/` | liga/desliga bot | **F2** |
| `sync/evolution/instances/<pk>/logout/` | desconectar sessão | ⚪ avaliar |
| `sync/evolution/instances/departments/` | departamento da instância | **F5** |

Tudo o mais tem destino: landing, health, login, logout, cadastro, onboarding
(4 passos + check-slug), dashboard, backoffice, configurações de IA/Evolution/
banco/debug, instâncias, treinamento, kanban, chat e webhooks.

---

## 6. Reconciliação: o estado das 33 frentes do doc 26

Reverificadas uma a uma contra o código de hoje (2026-09-06). É a lista que
manda — os L, F e N são recortes dela.

### Defeitos em caminho que já roda — **4 dos 5 caíram**

| # | Frente | Estado hoje |
|---|---|---|
| 1 | Mensagem de grupo vira atendimento | ✅ **corrigido** — `evento_de_grupo` descarta na ingestão, checagem dupla, 8 testes |
| 2 | Bot responde ao fragmento | ✅ **corrigido** — `buffer_mensagens.rs` agrega a rajada |
| 3 | Satisfação expira sem ser pedida | ✅ **corrigido** — `solicitar_pesquisa_satisfacao` é chamada na mudança de status |
| 4 | `msg_fallback`/`msg_sem_info` sem efeito | ✅ **corrigido** — `config_tenant.rs` honra a config do tenant |
| 5 | Estado da conexão só por consulta | ✅ **corrigido** — handler de `whatsapp.conexao` + reconciliação periódica |

> O doc 26 tinha razão nos cinco. Todos foram fechados entre agosto e esta
> sessão. **Nenhum entra nos planos novos.**

### Bloqueia operar

| # | Frente | Estado | Onde está |
|---|---|---|---|
| 6 | Enviar mídia pelo chat | ❌ | **F10 + F11** — plano do núcleo, E1/E2 |
| 7 | Ver/baixar mídia recebida | ❌ | **F11** — núcleo, E2 |
| 8 | Marcar como lida + não lidas | ❌ | **F12** — núcleo, E9 |
| 9 | **Buscar conversa e filtrar por atendente** | ❌ | 🆕 **não estava nos planos** — nenhum RPC de busca no `admin.proto` |
| 10 | Ligar/desligar bot por conexão | ❌ | **F2** — núcleo, E5 |
| 11 | Keepalive das sessões | ✅ **corrigido** nesta sessão | — |
| 12 | Roteamento conexão → departamento | ❌ | **F5** — núcleo, E7 |
| 13 | Senha e convite por e-mail | ❌ | **L1 + L5** — equipe, E1/E2/E5 |

### Degrada o produto

| # | Frente | Estado | Onde está |
|---|---|---|---|
| 14 | `Analyse` no fluxo vivo | ❌ | **F14** — núcleo, E6 |
| 15 | Campos personalizados | ❌ | **E9** equipe (tela) + **E6** núcleo (write-back) |
| 16 | Timeline e histórico por contato | ❌ | **N5** — núcleo, E11 |
| 17 | **Atribuir a outro atendente; transferir de fluxo manualmente** | ⚠️ parcial | 🆕 há `MoveAtendimentoEtapa` e `SetAtendimentoStatus`; **não há RPC de atribuir a alguém** |
| 18 | **Prioridade do atendimento** | ❌ | 🆕 coluna existe, **sem caminho de escrita** |
| 19 | **`data_primeira_resposta`** | ❌ | 🆕 coluna lida em 5 `SELECT`s e **nunca escrita** — sem ela não há SLA de resposta |
| 20 | Treinamento por upload | ❌ | **F15** — equipe, E14 |
| 21 | Gestão da whitelist | ❌ | **F9** — equipe, E8 |
| 22 | Editar contato; cliente PJ | ❌ | **F13** — equipe, E10 |
| 23 | **Presença "digitando"; citação de mensagem** | ⚠️ parcial | 🆕 `whatsapp.presenca` é publicado e a citação **está no proto**; falta a UI |
| 24 | Exportar quadro; excluir nota; editar etiqueta | ❌ | **N6** (export) — núcleo, E12. **Excluir nota e editar etiqueta** 🆕 |
| 25 | Feedback do teste de resposta | ❌ | **N7** — equipe, E11 |
| 26 | **Sincronização de contato/foto (`CONTACTS`)** | ❌ | 🆕 nenhum handler do evento no worker |
| 27 | **Enquete, lista e botões caem em `Other`** | ❌ | 🆕 normalização incompleta |

### Operação e fim do port

| # | Frente | Estado |
|---|---|---|
| 28 | ETL, cutover, desligar legado | ⚪ v1 já desligada nesta sessão; ETL segue pendente |
| 29 | Enforce de quotas | ⚪ fora destes planos |
| 30 | Validações manuais N7.5 | ⚪ fora destes planos |
| 31 | **`ReprocessarDeadLetter`; `LocalEngineFfiDataSource` no DI** | ❌ 🆕 zero ocorrências de ambos |
| 32 | Job de expiração de assinatura | ❌ **N1** — plano de pagamento, E6 |
| 33 | **Export/import de `CoreSettings`** | ⚠️ há RPC de `CoreSettings`; export/import não confirmado 🆕 |

### As 10 frentes que faltavam nos planos

🆕 **9** busca e filtro de conversa · **17** atribuir a outro atendente ·
**18** prioridade · **19** `data_primeira_resposta` (SLA) · **23** presença e
citação na UI · **24** excluir nota e editar etiqueta · **26** evento
`CONTACTS` · **27** enquete/lista/botões · **31** dead-letter e FFI no DI ·
**33** export/import de `CoreSettings`.

Todas entram nos planos na §7.

---

## 7. O que muda nos planos

| Plano | Ajuste |
|---|---|
| `cadastro-retomavel-e-pagamento` | **+#32/N1** suspensão automática de assinatura vencida |
| **Núcleo do atendimento** | F6 e F7 **reclassificados** para construção nova (N3, N4). **+#9** busca e filtro de conversa · **+#17** atribuir a outro atendente · **+#18** prioridade · **+#19** `data_primeira_resposta` · **+#23** presença e citação na UI · **+#24** excluir nota e editar etiqueta · **+#26** evento `CONTACTS` · **+#27** enquete/lista/botões · **+N5** timeline · **+N6** exportar quadro |
| **Equipe e configuração** | **+`CampoPersonalizado`** (tela e RPC) · **+N7** feedback do ensaio · **+N8** testar conexão · **+`PaymentRecord`** · **+gestão global de usuários** · **+#31** `ReprocessarDeadLetter` e `LocalEngineFfiDataSource` no DI · **+#33** export/import de `CoreSettings` |

### Frentes deliberadamente fora dos três planos

- **#28 ETL e cutover** — a v1 já foi desligada nesta sessão; o ETL de dados
  históricos é trabalho próprio, com janela e rollback próprios.
- **#29 enforce de quotas** e **#30 validações manuais da N7.5** — pertencem ao
  endurecimento (doc 22), não à paridade.
- **Trello** (14 tarefas Celery, 5 modelos, 2 rotas) — **descontinuado** por
  decisão de produto em 2026-09-06.
- **ClickUp** — nunca existiu como app: o `include` no `core/urls.py` da v1
  aponta para um pacote ausente, sob condicional.
- **`RunMigrationsView`** — não faz sentido na arquitetura da v2.

### Nota de método

Onde a documentação da v1 e o código da v1 divergem, **vale o código**. O
`CHECKLIST_IMPLEMENTACAO.md` (julho/2025) serve para derrubar afirmações dos
diagramas — foi assim que N3 e N4 apareceram —, mas não prova ausência no estado
final: ele marca como ❌ coisas que a v1 construiu depois, como a resposta
automática do bot.

Com esta reconciliação, as **33 frentes do doc 26** estão todas endereçadas:
5 corrigidas, 1 corrigida nesta sessão, 22 distribuídas nos três planos e
5 deliberadamente fora.
