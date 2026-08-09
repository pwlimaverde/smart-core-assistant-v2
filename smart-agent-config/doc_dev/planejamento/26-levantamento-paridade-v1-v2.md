# Levantamento de paridade v1 → v2 (auditoria de código)

> **Data:** 2026-08-08 · **Método:** varredura de `old/smart-core-assistant-painel/`
> (models, urls, views, services, selectors, tasks, `tenant_admin.py`,
> `CELERY_BEAT_SCHEDULE`, management commands) confrontada com o código real da
> v2 (`server/`, `clients/`, `ia_engine/`, migrations, `.proto`, rotas
> registradas em `data_*`/`runtime_api`).
> **Nada aqui é inferido do planejamento** — cada linha foi verificada no código.
>
> **Duas passadas.** A primeira comparou *superfícies* (rotas, models, telas). A
> segunda entrou nas *regras* (orquestrador, buffer de mensagens, selectors,
> escrita de colunas) e encontrou **10 itens a mais**, três deles defeitos de
> comportamento — não lacunas de tela. Passada por superfície não pega
> divergência de regra: `is_group` existe no tipo e ninguém lê.
>
> Este documento é o **inventário**; o cronograma derivado dele vive em
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md) (fases N9–N12).
> Ele sucede e absorve `infra/PLANO_PARIDADE_V1.md` (etapas 1–8, executadas entre
> 31/07 e 06/08/2026) e `infra/PLANO_ROBUSTEZ_CLIENTE.md`.

---

## 1. Resumo executivo

O port está **funcionalmente maduro no eixo de gestão** (tenant, planos,
onboarding, equipe, fluxos, treinamento, quadro) e **incompleto no eixo da
conversa** — que é o produto. A v2 hoje trata a mensagem como texto: mídia
recebida vira resumo textual e mídia enviada não existe.

| Eixo | v1 | v2 | Situação |
|---|---|---|---|
| Autenticação/usuários | 7 rotas | 3 RPCs + convites | ⚠️ sem e-mail e sem recuperação de senha |
| Tenants/planos/billing/onboarding | 23 rotas | 21 RPCs + 2 apps Flutter | ✅ **superior à v1** (vouchers, self-service) |
| Configuração global e do tenant | 7 rotas | 7 RPCs | ⚠️ falta gestão da whitelist |
| WhatsApp/Evolution | 19 rotas | 8 RPCs de borda | ⚠️ 6 lacunas operacionais |
| Conversa/chat | 10 rotas JSON | 8 RPCs | ❌ **maior lacuna** (mídia, leitura, presença) |
| Quadro/Kanban | 13 rotas JSON | 6 RPCs | ⚠️ falta atribuir, transferir, exportar, timeline |
| Contatos/clientes | admin do tenant | 1 RPC (leitura) | ⚠️ sem edição, sem PJ |
| Equipe (deptos/atendentes) | admin do tenant | 8 RPCs + tela | ✅ |
| Treinamento/RAG | 6 telas | 10 RPCs + 3 abas | ⚠️ falta arquivo e feedback |
| Integrações (Trello/ClickUp/Notion) | 3 integrações | — | 🚫 descartado por decisão |
| Agendamentos (Celery beat) | 2 jobs | 4 jobs | ⚠️ falta keepalive |

**Contagem de lacunas verificadas: 47** — 18 na conversa/quadro, 8 na IA,
9 em conexões/roteamento/pipeline, 6 em cadastros/pessoas, 6 em
operação/produção. Nove têm **capacidade instalada no servidor sem nenhum
chamador** (código pronto e inalcançável) — as mais baratas de fechar.

**Três não são lacunas, são defeitos** (a v2 se comporta diferente da v1 num
caminho que já roda):

1. **Mensagem de grupo vira atendimento individual.** `NormalizedMessage.is_group`
   é preenchido e **nenhum consumidor o lê**. A v1 descartava explicitamente
   (`_is_group_message`, com fallback por JID `@g.us`), porque o `push_name` de
   evento de grupo é do remetente, não do contato — o resultado é um atendimento
   com o nome errado para cada participante que escrever no grupo.
2. **O bot responde ao fragmento inicial.** A v1 **acumula** as mensagens do
   contato num buffer (`TIME_CACHE`, default 5 s, configurável) e responde ao
   texto compilado (`"\n".join`). A v2 usa um lock `SET NX EX 2` — **a primeira
   mensagem ganha e responde sozinha**; as seguintes só são persistidas. Quem
   escreve "oi" / "quero o preço" / "do produto X" recebe resposta ao "oi".
3. **A satisfação expira sem nunca ter sido pedida.** A v1 envia a solicitação de
   nota 1–5 ao finalizar e grava `avaliacao`/`feedback` analisando a resposta. Na
   v2 as duas colunas **só aparecem em SELECT**; o scheduler roda
   `MarcarFeedbackExpirado` sobre um feedback que nunca foi solicitado.

E **quatro colunas mortas** no `oraculo_atendimento` — lidas, nunca escritas:
`prioridade` (sempre `normal`, sem caminho de alteração), `tags` (sempre `[]`),
`contexto_conversa` (sempre `{}`) e `data_primeira_resposta` (**sem ela não há
métrica de tempo de primeira resposta**).

---

## 2. Inventário do v1 (o que existe no legado)

### 2.1 Apps Django e seu papel

| App | Papel | Superfície |
|---|---|---|
| `usuarios` | cadastro, login/logout, recuperação de senha | 7 rotas + e-mail |
| `tenants` | onboarding em 4 passos, backoffice, configs, convites, ativação | 23 rotas |
| `settings_manager` | `CoreSettings` (config global cifrada) + whitelist | 7 rotas |
| `evolution_sync` | instâncias WhatsApp, contatos, whitelist, webhook, buffer | 19 rotas |
| `atendimentos` | `Atendimento`/`Mensagem`/`MovimentoFluxo` + orquestração | serviços |
| `atendimento_unificado` | workspace (chat+quadro), SSE, campos personalizados | 5 rotas + SSE |
| `chat_evolution` | API JSON do chat (mensagens, envio, mídia, leitura) | 10 rotas |
| `gestao_kanban` | API JSON do quadro (board, mover, atribuir, etiquetas, notas) | 13 rotas |
| `operacional` | `Departamento`/`Atendente`/`AppInstance`/`Fluxo`/`Etapa` | 2 rotas + admin |
| `clientes` | `Contato` (PF) e `Cliente` (PJ) | só admin |
| `treinamento` | `Treinamento`/`Documento`/`QueryCompose`/feedback | 6 rotas |
| `trello_sync` | espelho do quadro no Trello (boards/lists/cards/members) | 2 rotas + 18 tasks |
| `core` | landing, dashboard, health, admin Django, `tenant-admin` | 15 rotas |

### 2.2 O `tenant-admin` (Django admin por tenant)

Ponto fácil de subestimar: além das telas próprias, a v1 dá ao tenant um CRUD
genérico sobre **17 modelos** via `tenant_admin_site` — `Atendimento`,
`Mensagem`, `CampoPersonalizado`, `ValorCampoAtendimento`, `Etiqueta`,
`EtiquetaAtendimento`, `Nota`, `Contato`, `Cliente`, `EvolutionInstance`,
`EvolutionContact`, `WhiteList`, `Departamento`, `Atendente`, `AppInstance`,
`FluxoAtendimento`, `EtapaFluxo`, `MovimentoFluxo`, `Treinamento`, `Documento`,
`QueryCompose`.

A v2 **não replica o admin genérico** (decisão implícita e correta: tela por
caso de uso, não por tabela) — mas isso significa que cada CRUD precisa existir
explicitamente. As lacunas de "Cliente", "campos personalizados", "whitelist" e
"EvolutionContact" saem daqui.

### 2.3 Agendamentos (`CELERY_BEAT_SCHEDULE`)

| Job v1 | Período | Equivalente v2 |
|---|---|---|
| `keepalive_evolution_instances` | 60 s | ❌ **não existe** |
| `purge_old_media_all_tenants` | 03:30 diário | ✅ `processar_midia_expirada` |
| `verificar_feedback_atendimento` (por atendimento) | agendado | ⚠️ `processar_feedback_vencido` expira, mas **nada solicita** o feedback |
| `check_subscription_expirations` / `notify_expiring` | diário | ⚠️ status de assinatura existe; sem job de expiração/aviso |
| `extract_custom_fields_async` (por mensagem) | sob demanda | ❌ não existe |
| `task_gerar_embedding_*` (fila `ai_processing`) | sob demanda | ✅ `processar_vetorizacao_pendente` + `processar_intents_sem_embedding` (➕ v2) |

A v2 acrescentou dois jobs que a v1 não tinha: `processar_vetorizacao_pendente`
e `processar_intents_sem_embedding`.

---

## 3. Matriz de paridade por domínio

Legenda: ✅ paridade · ⚠️ parcial · ❌ ausente · 🚫 descartado por decisão ·
🔌 **capacidade instalada sem chamador** (existe no servidor, inalcançável pela UI).

### 3.1 Autenticação e usuários

| v1 | v2 | Status |
|---|---|---|
| `login`, `logout` | `AuthService.Login/Logout/Refresh` (JWT + rotação + reuse-detection) | ✅ superior |
| `cadastro` | `OnboardingService.StartSignup` + `AcceptInvite` | ✅ |
| `password_reset` (4 rotas, com e-mail) | — | ❌ **nenhuma recuperação de senha** |
| `activate_account/<token>` | `ConfirmPayment`/`ActivateSignup` | ✅ |
| `user_invite` com e-mail | `CreateInvite` → **link exibido na tela para copiar** | ⚠️ sem entrega |
| `user_invite_resend` | — | ❌ |
| `user_permissions` | `UpdateTenantUser` (role/escopos/`flow_permissions`) | ✅ |

> **Nenhum envio de e-mail existe na v2** (`grep lettre|smtp|sendgrid` no
> `server/`: zero ocorrências). Isso bloqueia três funcionalidades da v1 de uma
> vez: convite, ativação e recuperação de senha. O link de convite ainda é
> relativo (`/aceitar-convite?token=…`), sem host — quem convida precisa montar
> a URL à mão.

### 3.2 Tenants, planos, billing e onboarding

| v1 | v2 | Status |
|---|---|---|
| `onboarding_step_1..4`, `api_check_slug` | `CheckSlug`, `StartSignup`, `SelectPlan`, `ConfirmPayment`, `GetSignupStatus` + `onboarding_module` | ✅ |
| `backoffice_dashboard`, `register_payment` | `GetDashboardSummary`, `RegisterPayment`, `ListPayments` | ✅ |
| `Plan`/`Subscription` | `ListPlans`, `CreatePlan`, `UpdatePlan`, `ListSubscriptions` + quotas | ✅ superior |
| — | **vouchers** (`CreateVoucher`, `RevokeVoucher`, `ListVoucherRedemptions`) | ➕ novo |
| — | configuração guiada pós-cadastro (`SetOnboardingProgress`, 4 telas) | ➕ novo |
| `config_database`, `run_migrations`, `test_connection` | — | 🚫 base única com RLS |
| `config_debug` | — | 🚫 baixa prioridade |

### 3.3 Configuração global e do tenant

| v1 | v2 | Status |
|---|---|---|
| `CoreSettings` CRUD | `ListCoreSettings`, `UpsertCoreSetting`, `DeleteCoreSetting` | ✅ |
| `export_core_settings` / `import_core_settings` / `bootstrap_core_settings` / `load_core_settings` (4 comandos: backup, restauração e semeadura a partir de env/JSON) | — | ❌ sem backup/restauração de configuração |
| prompts nomeados em `CoreSettings` (`PROMPT_*`) | migration 0026: `tenants_tenantconfig.prompts` JSONB + chaves globais, cascata tenant > global > default no código | ✅ superior |
| `config_ai` (persona, prompts, providers, chaves) | `GetMyTenantConfig`/`UpdateMyTenantConfig` + cascata `TenantConfig > CoreSettings` publicada no Redis | ✅ superior |
| `whitelist` (listar, adicionar, editar, excluir, alternar, buscar contato) | tabela `whatsapp_whitelist` + `IsPhoneWhitelisted` (leitura no `webhook_ingress`) | ⚠️ 🔌 **sem CRUD nem tela** |
| branding (`brand_name`, cores, timezone, idioma) | campos existem em `tenants_tenantconfig` | ⚠️ sem tela |

### 3.4 WhatsApp / Evolution

| v1 | v2 | Status |
|---|---|---|
| `instance_list`, `instance_detail` | `ListMyWhatsappInstances` + `/tenant/conexoes` | ✅ |
| `instance_create` | `CreateMyWhatsappInstance` (onboarding) | ✅ |
| `instance_delete` | `DeleteMyWhatsappInstance` | ✅ |
| `instance_status` | `GetMyWhatsappInstanceStatus` | ✅ |
| `instance_qrcode` (a qualquer momento) | só dentro do onboarding | ⚠️ |
| `instance_toggle_bot` | — | ❌ |
| `instance_update` (renomear) / `instance_webhook` | — | ❌ |
| `instance_logout` | `ReconnectMyWhatsappInstance` (parcial) | ⚠️ |
| `instance_refresh_all` | `AdminBulkDisconnectInstances` (admin) | ⚠️ |
| `keepalive_evolution_instances` (60 s) | — | ❌ **risco operacional** |
| `EvolutionContact` (nome de perfil, foto) | `whatsapp_contact` + `GetWhatsappProfilePicture` | ⚠️ 🔌 **sem chamador** |
| `AppInstance` → departamento por `api_key` | roteamento usa **o primeiro fluxo ativo do tenant** | ❌ **sem roteamento por conexão** |
| webhook de ingestão | `webhook_ingress` autenticado + whitelist + idempotência | ✅ superior |
| `message_buffer` (debounce) | lock de debounce no Redis (worker) | ✅ |

> `AppInstance` é a lacuna estrutural aqui: um tenant com duas conexões (ex.
> Vendas e Suporte) não tem como mandar cada uma para o seu departamento. O
> `data_postgres` resolve `resolver_atendimento_para_contato` com
> `buscar_primeiro_ativo` do fluxo — correto para um tenant com um fluxo só,
> silenciosamente errado para dois.

### 3.5 Conversa e chat — **maior concentração de lacunas**

| v1 (`chat_evolution`) | v2 | Status |
|---|---|---|
| `conversations_list` | `ListAtendimentos` | ✅ |
| `conversation_messages` | `GetThread` | ✅ |
| `conversation_detail` | `GetDetalheAtendimento` (etiquetas + notas) | ✅ |
| `conversation_send` (texto) | `SendOutboundMessage` | ✅ |
| `conversation_upload` (enviar mídia) | `SendWhatsappMedia` no `data_whatsapp` | ❌ 🔌 **sem chamador nem UI** |
| `conversation_medias` + `mensagem_media` (ver/baixar) | `arquivo_midia` gravado no R2; chat mostra **só o resumo textual** | ❌ |
| `conversation_mark_read` | `marcar_como_lida` (repo) + `MarkWhatsappMessageRead` | ❌ 🔌 **sem chamador** |
| `notifications_unread_count` | coluna `lido` existe | ❌ sem contador |
| `conversation_presence` ("digitando") | `SetWhatsappPresence` | ❌ 🔌 **sem chamador** |
| citação de mensagem (`mensagem_citada_id`, `quoted_preview`) | colunas existem; **fora do `.proto`** | ❌ |
| status de entrega/leitura | `status_envio` no proto; `data_entregue`/`data_lida` não | ⚠️ |
| SSE do workspace | `StreamAtendimentos` (gRPC Server Streaming, Redis Pub/Sub) | ✅ superior |
| — | reação a mensagem (`SendWhatsappReaction`) | 🔌 instalado, sem uso |

### 3.5b Pipeline de mensagem — regras internas (2ª passada)

Comparação de `AttendanceOrchestrator` + `message_buffer` + `webhook.py` (v1)
com `webhook_ingress` + `worker` (v2).

| Regra v1 | v2 | Status |
|---|---|---|
| **Descarta mensagem de grupo** (`_is_group_message` + fallback `@g.us`) | `is_group` no `NormalizedMessage`, **sem nenhum leitor** | ❌ **defeito** |
| Ignora `fromMe`/`send.message` (eco do próprio bot) | `is_from_me` tratado (vira mensagem de atendente, não aciona bot) | ✅ |
| **Buffer de agregação** por contato (`TIME_CACHE`, default 5 s, dedupe por `message_id`) → compila `"\n".join(texts)` numa única mensagem | lock `SET NX EX 2` — primeira ganha, demais só persistem; janela **fixa em código** | ❌ **defeito** |
| Evento **MESSAGE_UPDATE** → atualiza `status_envio` | `whatsapp.message.status` consumido pelo worker | ✅ |
| Evento **CONNECTION** → atualiza `connection_state` da instância | normalizado e publicado; **worker não consome**. O estado só muda quando alguém consulta o status ou no bulk disconnect | ❌ |
| Evento **CONTACTS** → sincroniza contato (nome/foto) | normalizado e publicado; sem consumidor | ❌ |
| Evento **PRESENCE** → presença do contato | normalizado e publicado; sem consumidor | ❌ |
| 12 tipos de mensagem mapeados | texto, imagem, áudio, vídeo, documento, localização, sticker, contato; **enquete/lista/botões** caem em `Other` | ⚠️ |
| Histórico da conversa no prompt (`carregar_historico_mensagens`) | `ChatHistory` montado pelo worker | ✅ |
| `msg_fallback` (falha da IA) e `msg_sem_info` (RAG vazio) do tenant | publicados no `RuntimeConfig` e **nunca aplicados** — o worker usa `BOT_TEXT_FALLBACK`, constante no código | ❌ mesma classe dos bugs de persona/transferência corrigidos em 28/07 |
| `_enviar_solicitacao_feedback` (nota 1–5 ao encerrar) + `_check_and_process_feedback` → grava `avaliacao`/`feedback` | colunas só em SELECT; scheduler só marca expirado | ❌ **defeito** |
| `atualizar_contexto`/`get_contexto` (estado da conversa) | `contexto_conversa` só em SELECT | ❌ coluna morta |
| `data_primeira_resposta` (SLA) | só em SELECT | ❌ coluna morta |
| `prioridade` (choices + admin) | só em SELECT — sempre `normal` | ❌ coluna morta |
| `tags` do atendimento | só em SELECT — sempre `[]` | ❌ coluna morta |

### 3.6 Quadro (Kanban) e fluxo

| v1 (`gestao_kanban`) | v2 | Status |
|---|---|---|
| `board_snapshot` | `ListMyEtapasFluxo` + `ListAtendimentos` (colunas vêm do fluxo) | ✅ |
| `board_move` | `MoveAtendimentoEtapa` (+ `SetAtendimentoStatus` simétrico) | ✅ |
| regras de `tipo_etapa` | paridade conferida contra `board_service` (5 colunas, nome decide desfecho, assumir desliga bot, voltar à fila não religa, `historico_status`) | ✅ |
| saudação ao assumir | mensagem na mesma transação, cargo/empresa do cadastro | ✅ |
| `board_assign` (atribuir a alguém) | só assume quem arrasta | ❌ |
| `board_transfer_fluxo` (manual) | `TransferirAtendimentoParaFluxo` só pela IA (worker) | ⚠️ 🔌 |
| `export` (CSV do quadro) | `ExportTenantsCsv` é do admin, não do quadro | ❌ |
| `conversation_timeline` (movimentos) | `oraculo_movimento_fluxo` gravado; **sem RPC de leitura** | ❌ |
| **busca** por nome/perfil/telefone/assunto na fila e no quadro (`q` nos selectors) | `ListAtendimentosRequest` = `status` + `departamento_id` + `limit` | ❌ |
| **filtro por atendente** (`atendente_id_filtro`) | — | ❌ |
| paginação (`offset`) na fila | só `limit` | ⚠️ |
| filtro por fluxos acessíveis (`list_fluxos_acessiveis`, respeita RBAC) | `flow_permissions` aplicado na fila | ✅ |
| `etiquetas_list`, `etiqueta_toggle` | `CreateEtiqueta`, `AlternarEtiqueta` | ⚠️ sem editar/desativar |
| `notas` (criar/deletar) | `CreateNota` | ⚠️ sem excluir |
| `custom_field_patch` | catálogo lido só para o `Responder` | ❌ |

### 3.7 Contatos e clientes

| v1 | v2 | Status |
|---|---|---|
| `Contato` (listar/buscar) | `ListMyContatos` com busca ILIKE no servidor + `/tenant/contatos` | ✅ |
| editar contato (nome, e-mail, tags) | — | ❌ |
| histórico de atendimentos do contato | — | ❌ (depende do timeline) |
| `Cliente` (PJ) + vínculo N:N com contatos | `oraculo_cliente`, `oraculo_cliente_contatos` + `ClienteRepository` completo | ❌ 🔌 **sem RPC nem tela** |
| foto de perfil / nome do WhatsApp | colunas em `whatsapp_contact` | ⚠️ preenchidas só pelo webhook |

### 3.8 Equipe (departamentos, atendentes, fluxos)

| v1 | v2 | Status |
|---|---|---|
| `Departamento` CRUD | `ListMyDepartamentos`, `CreateMyDepartamento`, `UpdateMyDepartamento`, `DesativarMyDepartamento` | ✅ |
| `Atendente` CRUD | `ListMyAtendentes`, `CreateMyAtendente`, `UpdateMyAtendente`, `DesativarMyAtendente` | ✅ |
| `FluxoAtendimento`/`EtapaFluxo` | 8 RPCs (CRUD + reordenação, com as 3 regras explicadas) | ✅ **superior** (a v1 só tinha admin genérico) |
| `is_available`/`current_load` (capacidade) | `max_conversas` cadastrado | ⚠️ cadastrado, não aplicado |
| `AppInstance` (api_key → departamento) | tabela existe, sem uso no roteamento | ❌ (ver 3.4) |

### 3.9 Treinamento, RAG e IA

| v1 | v2 | Status |
|---|---|---|
| `treinar_ia` (texto) | `CreateMyTreinamento` + `treinamento_module` | ✅ |
| `treinar_ia` (**upload** .pdf/.doc/.docx/.txt/.xls/.xlsx/.csv) | — | ❌ **só texto colado** |
| `pre_processamento`, `verificar_treinamentos_vetorizados` | `GetMyTreinamento`, `FinalizarMyTreinamento` + job de vetorização | ✅ |
| `cadastrar/verificar_query_compose` | CRUD de intents (4 RPCs) + aba "Intenções" | ✅ |
| `testar_resposta_query` | `TestarPergunta` (mesmo caminho da mensagem real, com trechos e distância) | ✅ superior |
| `feedback_resposta_query` (`QueryTestFeedback`) | tabela existe; **sem RPC** | ❌ |
| `analise_previa_mensagem` (intents/entidades) | `IaEngineService.Analyse` implementado e testado nos dois lados | ❌ 🔌 **nunca chamado pelo worker** |
| `process_contact_entities` (enriquecer contato) | — | ❌ |
| `_auto_fill_subject` (assunto automático) | — | ❌ |
| `_sync_intent_tags` (etiquetar por intenção) | — | ❌ |
| `transcribe_audio` | `Transcribe` ligado ao pipeline | ✅ |
| `interpret_media` | `InterpretMedia` ligado | ✅ |
| `analise_avaliacao` | `Sentimento` ligado + persistido | ✅ |
| `generate_chunks` + `generate_embeddings` | `Embed` + corte por parágrafo no scheduler | ✅ |
| RAG (`QueryCompose`, pgvector 1536) | `QueryCompose` no `data_postgres` | ✅ |
| persona/prompts do tenant no prompt | via `RuntimeConfig` no Redis | ✅ |

> **`Analyse` é a lacuna de IA mais cara**: as colunas
> `oraculo_mensagem.intent_detectado` e `entidades_extraidas` existem desde a
> migration 0006 e estão sempre vazias. Quatro comportamentos da v1 dependem
> dela (etiqueta automática, assunto, enriquecimento do contato, e o próprio
> relatório de intenções).

### 3.10 Integrações externas — 🚫 descartadas por decisão

| v1 | Decisão v2 |
|---|---|
| `trello_sync` inteiro (5 modelos, 18 tasks, webhooks, `config_trello`) | 🚫 substituído pelo **quadro próprio** — o cartão nasce do atendimento, não de um espelho |
| ClickUp (`clicup_adapter`, `clickup_callback`) | 🚫 |
| Notion (`notion_adapter`) | 🚫 |
| `unifield_data_services` (fachada das três) | 🚫 |

Decisão registrada em `infra/PLANO_PARIDADE_V1.md` e reafirmada aqui.

### 3.11 Operação, produção e observabilidade

| Item | Status |
|---|---|
| Stack LGTM, tracing OTLP, auditoria com `user_agent` | ✅ superior à v1 |
| `watchdog` (reinicia serviço travado) + `healthcheck` | ➕ novo, sem equivalente na v1 |
| Enforce de quotas (`SMARTCORE_QUOTA_ENFORCE`) | ⚠️ ainda `false` — janela log-only não foi encerrada |
| ETL v1→v2 (`infra/migracao-v1/`) | ⚠️ código pronto e testado (75 testes); **execução real contra produção pendente** |
| Cutover (DNS, desligar Django) | ❌ o domínio de produção ainda serve o painel v1 no fallback do Caddy |
| Validações manuais da N7.5 (rajada, dashboards com tráfego real, E2E) | ❌ pendentes |
| `ReprocessarDeadLetter` | 🔌 sem chamador na borda |
| `LocalEngineFfiDataSource` (offline no desktop) | ⚠️ classe pronta, não registrada no DI de produção |

---

## 4. Lacunas consolidadas por severidade

> As 47 lacunas das matrizes acima aparecem aqui agrupadas em **33 frentes de
> trabalho** — itens que se resolvem no mesmo ciclo foram unidos (ex.: os quatro
> comportamentos que dependem do `Analyse` são uma frente só).

### Defeito em caminho que já roda — corrigir antes de features

1. **Mensagem de grupo vira atendimento** (`is_group` sem leitor).
2. **Bot responde ao fragmento** (lock de 2 s em vez do buffer de agregação da v1).
3. **Satisfação expira sem ser pedida** (`avaliacao`/`feedback` nunca escritos).
4. **`msg_fallback`/`msg_sem_info` do tenant não têm efeito** (constante no código).
5. **Estado da conexão só atualiza por consulta** — o evento `CONNECTION` chega ao
   barramento e ninguém consome.

### Bloqueia operar (o usuário sente todo dia)

6. Enviar mídia pelo chat (🔌 `SendWhatsappMedia`).
7. Ver/baixar a mídia recebida (hoje só o resumo textual).
8. Marcar como lida + contador de não lidas (🔌 `MarkWhatsappMessageRead`).
9. Buscar conversa por nome/telefone/assunto e filtrar por atendente.
10. Ligar/desligar o bot por conexão.
11. Keepalive das sessões Evolution (sessão ociosa cai; a v1 reconectava a cada 60 s).
12. Roteamento por conexão → departamento (`AppInstance`).
13. Recuperação de senha e entrega de convite por e-mail.

### Degrada o produto (a v1 fazia melhor)

14. `Analyse` no fluxo vivo → intents/entidades, assunto automático, etiquetas
    automáticas, enriquecimento do contato.
15. Campos personalizados: catálogo, preenchimento manual e extração por IA.
16. Timeline do atendimento (movimentos) e histórico por contato.
17. Atribuir conversa a outro atendente; transferir de fluxo manualmente.
18. Prioridade do atendimento (coluna sem caminho de escrita).
19. `data_primeira_resposta` — sem ela não há métrica de SLA de resposta.
20. Treinamento por upload de arquivo.
21. Gestão da whitelist.
22. Editar contato; cadastro de cliente PJ.
23. Presença "digitando"; citação de mensagem.
24. Exportar o quadro; excluir nota; editar/desativar etiqueta do catálogo.
25. Feedback do teste de resposta.
26. Sincronização de contato/foto pelo evento `CONTACTS`.
27. Enquete, lista e botões caem em `Other` na normalização.

### Operação e fim do port

28. Executar o ETL contra produção; virar o cutover; desligar o legado.
29. Ligar o enforce de quotas depois da janela observada.
30. Validações manuais da N7.5.
31. Expor `ReprocessarDeadLetter`; registrar `LocalEngineFfiDataSource` no DI.
32. Job de expiração/aviso de assinatura.
33. Export/import de `CoreSettings` (backup e restauração de configuração).

---

## 5. O que a v2 já tem além da v1

Para não dar a impressão de que o port é só dívida:

- **Cadastro self-service com vouchers** e pagamento como porta plugável.
- **Configuração guiada** pós-cadastro (conta criada → operando), retomável.
- **Fluxos e etapas com CRUD e regras explicadas** — na v1 isso era admin genérico.
- **Teste de pergunta** percorrendo o caminho real, com trechos e semelhança.
- **RBAC fino por fluxo** (`flow_permissions`) fim a fim, com RLS como segunda barreira.
- **Realtime por gRPC streaming** com reconexão e backoff (v1: SSE).
- **Observabilidade**: trace único webhook→resposta, auditoria com `user_agent`,
  watchdog publicando `smartcore_service_up` de fora dos serviços.
- **Offline/desktop**: `local_engine` com índice SQLite, fila LWW e cache de mídia.
- **Idempotência e dead-letter** no caminho de escrita.
- **Cifragem AES-256-GCM** de credenciais (v1: Fernet), inclusive `api_key` de instância.

---

*Auditoria de código realizada em 2026-08-08 sobre `dev` @ `cf30905`.*
