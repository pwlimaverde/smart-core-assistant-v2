# Smart Core Assistant v2 — Fases de Desenvolvimento

> **Status:** Guia operacional de construção (greenfield).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** Deriva de [00-planejamento-inicial.md](./00-planejamento-inicial.md)
> (visão/arquitetura) e [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md)
> (organização de pastas). Este documento define **o quê construir, em que ordem
> e como saber que está pronto**.

---

## Como usar este guia

- O desenvolvimento é dividido em **Fases** (marcos de valor) → **Etapas**
  (entregáveis coesos) → **Componentes/tarefas**.
- A ordem é por **dependência técnica**: cada fase assume as anteriores prontas.
- Cada etapa tem **entregáveis**, **dependências** e **critérios de aceite (DoD)**.
- Convenção de branch (gitflow): `feature/<fase>-<slug>` a partir de `dev`
  (ex.: `feature/f1-rls-schema`). Sem `Co-Authored-By` nem rodapés de IA.
- **Definition of Done global por etapa:** compila + lint limpo
  (`cargo clippy -- -D warnings` / `ruff` / `flutter analyze`) + testes da etapa
  passando + comentários em pt-br + sem segredos no código.

### Princípios invioláveis (revalidar a cada PR)
1. **O webhook nunca executa regra pesada** — só autentica, resolve tenant,
   persiste bruto e publica no bus.
2. **`tenant_id` em toda query** + **RLS** como segunda barreira.
3. **`domain_*` sem I/O** — nenhuma dependência de `infrastructure_*`.
4. **`local_engine` sem lógica multi-tenant sensível nem de webhook.**
5. **`DataSource` abstrato desde o dia 1** — garante o port Web sem reescrita.

### Mapa de dependências entre fases

```
F0 Fundação ──► F1 Banco+RLS ──► F2 Control Plane
                     │                  │
                     ├──► F3 Messaging Gateway + Evolution
                     │            │
                     │            ▼
                     └──► F4 Worker + Domínio ──► F5 ia_engine (gRPC)
                                  │                     │
                                  ▼                     │
                          F6 Runtime API + Realtime ◄───┘
                                  │
                                  ▼
                          F7 Flutter Windows (RemoteOnly)
                                  │
                                  ▼
                          F8 Local Engine (FFI) + mídia local
                                  │
                                  ▼
                          F9 Endurecimento + billing + deploy
                                  │
                                  ▼
                          F10 Port Web (RemoteOnly)
```

> **MVP funcional ponta-a-ponta** = F0→F6 (WhatsApp entra, bot responde, painel
> Web mínimo vê em tempo real). F7+ é experiência desktop; F8 é desempenho/offline.

---

## Fase 0 — Fundação do monorepo e infra local

**Objetivo:** esqueleto compilável de todas as stacks + ambiente local de dados.
**Dependências:** nenhuma.

### Etapa 0.1 — Esqueleto de diretórios
- Criar `server/`, `evolution/`, `clients/`, `ia_engine/`, `docker/` na raiz do
  monorepo (conforme [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md)).
- `.env.example` na raiz + `.gitignore` cobrindo `.env`, `target/`, `build/`,
  `.dart_tool/`, `__pycache__/`, `*.lock` (exceto os versionados).
- **DoD:** árvore de pastas criada; `.env.example` documenta todas as variáveis.

### Etapa 0.2 — Cargo workspace (skeleton)
- `server/Cargo.toml` (workspace) + `Cargo.lock` versionado.
- Criar todos os crates vazios (`apps/*`, `crates/*`) com `lib.rs`/`main.rs`
  mínimos que compilam.
- Definir versões base: `tokio`, `axum`, `tonic`, `sqlx`, `serde`, `tracing`,
  `redis`, `uuid`, `thiserror`.
- **DoD:** `cargo build` verde no workspace inteiro; `cargo fmt --check` limpo.

### Etapa 0.3 — Infra local de dados
- `docker/compose/data.yml`: **PostgreSQL 16 + pgvector**, **Redis 7**, **MinIO**.
- Script de extensões (`CREATE EXTENSION vector;`, `pgcrypto`).
- **DoD:** `docker compose -f docker/compose/data.yml up -d` sobe os 3 serviços
  saudáveis; `psql` conecta e `vector` está instalada.

### Etapa 0.4 — crate `observability`
- Logs estruturados (JSON) com `tracing` + `tracing-subscriber`.
- Inicialização padrão reusável pelos 4 binários (nível por env).
- Hooks de span com `tenant_id` quando presente.
- **DoD:** binário de exemplo emite log estruturado com nível configurável.

### Etapa 0.5 — crate `contracts` (base)
- `TenantEnvelope<T>` (todo evento/DTO carrega `tenant_id: Uuid`).
- Enum de eventos internos do bus: `MessageReceived`, `MessageUpdate`,
  `ConnectionUpdate`, etc. (nomes internos, desacoplados do Evolution).
- DTOs base e versão de schema dos eventos.
- **DoD:** tipos serializam/deserializam (serde) com testes de round-trip.

---

## Fase 1 — Banco unificado multi-tenant + RLS

**Objetivo:** persistência única com isolamento por tenant garantido pelo banco.
**Dependências:** F0.
**Risco-chave:** isolamento RLS — exige testes rigorosos (ver §17 do plano).

### Etapa 1.1 — `infrastructure_postgres` (fundação)
- Pool `sqlx` (Postgres), runner de migrations, healthcheck.
- Helper de **contexto de tenant**: `SET app.current_tenant = '<uuid>'` por
  conexão/transação.
- **DoD:** conexão + migration vazia aplicável; helper de contexto testado.

### Etapa 1.2 — Tenant context + policies RLS
- Função/guard que recusa query sem `app.current_tenant` setado.
- Template de policy RLS por tabela de domínio (`USING (tenant_id = current_setting(...)::uuid)`).
- **DoD:** tabela de teste com RLS recusa leitura/escrita sem contexto; aceita com contexto.

### Etapa 1.3 — Migrations do schema de domínio
Tabelas (todas com `tenant_id UUID NOT NULL` + RLS), conforme §12 do plano:
- **Control Plane:** `tenant`, `tenant_config`, `plan`, `subscription`,
  `payment_record`, `tenant_user`, `tenant_invite`, `evolution_instance`.
- **Domínio:** `contact`, `conversation`, `ticket`, `message`, `flow_movement`,
  `department`, `flow`, `stage`, `agent`.
- **IA/RAG:** `training_document` (embedding `vector(1536)`),
  `intent_behavior` (≈ `QueryCompose`, embedding `vector(1536)`).
- Índices herdados da v1 (status+departamento, etapa+atendente, tags, etc.).
- **DoD:** `migrate` aplica do zero; schema documentado; índices criados.

### Etapa 1.4 — Testes de isolamento multi-tenant
- Suíte que cria 2 tenants e prova que A não enxerga dados de B (via RLS e via
  filtro de aplicação — duas barreiras).
- **DoD:** testes de vazamento entre tenants passam; tentativa sem contexto falha.

---

## Fase 2 — Control Plane

**Objetivo:** back office — gestão de tenants, planos, RBAC, credenciais e
registro de instâncias Evolution.
**Dependências:** F1.

### Etapa 2.1 — `domain_tenant` (regras puras)
- Entidades: tenant, plano, quota, feature flags, assinatura, papéis (RBAC).
- Regras de quota (`max_instances`, `max_departments`) sem I/O.
- **DoD:** regras testadas em unidade, sem dependência de infra.

### Etapa 2.2 — Cifragem de credenciais
- `infrastructure_*` de cifragem (Fernet/AEAD) — espelha `encrypt_value`/
  `decrypt_value` da v1; chave-mestra via env.
- Aplicada a: api keys de provedores (`tenant_config.api_keys`), token/api_key
  de `evolution_instance`.
- **DoD:** round-trip cifra/decifra testado; segredos nunca em claro no banco.

### Etapa 2.3 — Binário `control_plane`
- CRUD: tenant, tenant_config (persona, prompts, branding, providers),
  plan/subscription/payment, tenant_user/tenant_invite (RBAC).
- API gRPC/HTTP de administração.
- **DoD:** criar tenant ponta-a-ponta; RBAC e quotas aplicados; testes de API.

### Etapa 2.4 — `infrastructure_evolution` (provisionamento)
- Cliente HTTP do Evolution Go: `/instance/create`, `/instance/connect`,
  `/instance/qr`, `/instance/pair`, `/instance/status`, `/instance/all`,
  delete. Autenticação **global key** (admin) × **token de instância**.
- Guard de quota por plano antes de criar instância.
- **DoD:** criar instância + obter QR/pair em ambiente de teste; status lido.

---

## Fase 3 — Messaging Gateway + Evolution multi-instância

**Objetivo:** ingestão confiável de webhooks → evento interno no bus.
**Dependências:** F1, F2 (resolução de tenant por instância).

### Etapa 3.1 — `evolution/` (infra do gateway WhatsApp)
- `docker/` (compose Evolution Go + 2 PG: `evogo_auth`, `evogo_users`;
  **sem Redis**; `DATABASE_SAVE_MESSAGES=false`).
- `config/` (eventos por instância) + `scripts/` de provisionamento.
- **DoD:** Evolution Go sobe local; instância de teste conecta e dispara webhook.

### Etapa 3.2 — `domain_whatsapp` (normalização)
- Mapeamento de tipos por chave JSON (`conversation`/`extendedTextMessage`/
  `imageMessage`/`audioMessage`/`documentMessage`/`videoMessage`/`stickerMessage`/
  `locationMessage`/...).
- Normalização do payload `messages.upsert` (key.remoteJid, fromMe, id,
  pushName, message, messageType, messageTimestamp) → evento interno.
- Resolução de `contextInfo.stanzaId` (reply) e `quoted_preview`.
- **DoD:** parsers cobertos por testes com payloads reais de cada tipo.

### Etapa 3.3 — `infrastructure_redis` (event bus)
- Redis Streams + consumer groups; namespace por tenant; helpers de
  publish/consume com `TenantEnvelope`.
- **DoD:** publish/consume com ack e replay testados.

### Etapa 3.4 — Binário `messaging_gateway`
- Recebe webhook → valida origem/assinatura → resolve `tenant_id` +
  `evolution_instance` (por `instance`/`apikey`) → persiste **evento bruto** →
  publica evento interno no bus. **Sem regra de negócio.**
- **Idempotência** por `message_id` (não republica duplicado).
- Trata eventos: `MESSAGES_UPSERT`, `MESSAGES_UPDATE`, `CONNECTION_UPDATE`,
  `QRCODE_UPDATED`, `CONTACTS_UPSERT`.
- **DoD:** webhook real → evento no bus com `tenant_id`; raw persistido; dup ignorada.

---

## Fase 4 — Worker + domínio (sem IA)

**Objetivo:** orquestrar conversa/ticket/kanban e enviar resposta — ainda sem LLM.
**Dependências:** F3.

### Etapa 4.1 — Crates de domínio (regras puras)
- `domain_contact`, `domain_conversation`, `domain_ticket`, `domain_kanban`.
- Regras herdadas da v1 (§10 do plano): ciclo de vida do atendimento
  (`FILA`→`EM_ATENDIMENTO`→`PENDENCIA`→`RESOLVIDO`/`CANCELADO`/`ARQUIVADO`),
  reaproveitamento de atendimento ativo, política de reabertura/feedback,
  transferência por departamento/fluxo/etapa.
- **DoD:** máquina de estados e políticas cobertas por testes unitários puros.

### Etapa 4.2 — `application` (casos de uso)
- `ReceiveMessage`, `DebounceByContact`, `ResolveConversation`,
  `DecideTicketPolicy` (reaproveita/reabre/cria), `ApplyKanbanStage`,
  `RegisterFlowMovement`, `CanBotRespond`, `TransferFlow`.
- **Mensagem primária**: mídia = mensagem própria; textos rápidos concatenados.
- **DoD:** casos de uso testados com repositórios fake; debounce determinístico.

### Etapa 4.3 — Binário `worker`
- Consome o bus, aplica **debounce por contato** (buffer + lock de agendamento),
  resolve conversa, aplica política de ticket, atualiza kanban + `flow_movement`.
- **DoD:** rajada de mensagens vira 1 processamento coeso; movimentos auditados.

### Etapa 4.3b — Scheduler do `worker` (substitui o Celery da v1)
- O `worker` assume os papéis do Celery da v1: **fila/processamento assíncrono**
  (via Redis Streams) e **agendamento temporal**.
- Tarefas agendadas a portar: **timeout de feedback** (a v1 agenda
  `verificar_feedback_atendimento` 5 min após `RESOLVIDO`) e **purga de mídia**
  periódica (`purge_old_media_all_tenants`).
- Implementação: delayed tasks no Redis (sorted-set por `ETA`) consumidas pelo
  worker + `tokio` timers para o processo vivo; cada tarefa carrega `tenant_id`.
- **DoD:** tarefa agendada dispara no tempo certo após restart do worker; sem
  perda de agendamento; isolada por tenant.

### Etapa 4.4 — Envio outbound
- Via `infrastructure_evolution`: `/message/sendText`, `/message/sendMedia`
  (token da instância) com **retry/backoff**.
- Atualiza `status_envio` (pending→sent→delivered→read) por `MESSAGES_UPDATE`.
- **DoD:** resposta sai pelo WhatsApp; read receipts refletidos na mensagem.

### Etapa 4.5 — `BotRulesEngine` (sem LLM)
- Bot responde **somente se**: instância permite (`resposta_bot=True`) **e** sem
  interação humana no atendimento **e** `bot_pode_atender=True`. Qualquer
  mensagem de `ATENDENTE_HUMANO` bloqueia o bot permanentemente.
- Resposta provisória (eco/fallback fixo) até a IA entrar na F5.
- **DoD:** matriz de decisão do bot testada (todas as combinações).

---

## Fase 5 — `ia_engine` (Python, serviço gRPC)

**Objetivo:** mídia→texto, intents/entidades, RAG, resposta e sentimento, como
**serviço Python independente** consumido pelo `worker` via **gRPC** (decisão
D3/§13.1 — FFI/PyO3 descartado).
**Dependências:** F4 (worker chama a IA), F1 (pgvector).

### Etapa 5.1 — `ia_engine` skeleton
- `uv` + `pyproject.toml` + `uv.lock`; `src/server.py` (servidor **gRPC**, com os
  handlers); `src/features/`; `src/llm/` (abstração OpenAI/Groq/Ollama);
  `src/contracts/` (DTOs Pydantic espelhando o `.proto`).
- **DoD:** servidor gRPC sobe; healthcheck; lint `ruff` + `pyright` limpos.

### Etapa 5.2 — Contratos `domain_ai` + protobuf
- `.proto` do serviço como **fonte única de tipos**; interfaces Rust em
  `domain_ai` (sem implementação) + stubs gerados nos dois lados (tonic no Rust,
  grpcio no Python); DTOs Pydantic espelhando as mensagens.
- Todo request carrega `tenant_id` (serviço stateless quanto a tenant).
- **DoD:** codegen gera stubs nos dois lados; contrato versionado; round-trip de
  um RPC simples (ex.: `GenerateEmbeddings`) testado worker↔ia_engine.

### Etapa 5.2b — Portar a facade `FeaturesCompose`
- Reaproveitar a facade de IA da v1 (`FeaturesCompose`) quase intacta como núcleo
  do serviço; mapear seus métodos para os RPCs (ver tabela em §13.2 do plano):
  `analise_previa_mensagem`→`AnalisePreviaMensagem`,
  `analise_mensage`→`AnaliseMensage`, `_transcribe_audio`→`TranscribeAudio`,
  `_interpret_media`→`InterpretMedia`, `generate_embeddings`→`GenerateEmbeddings`,
  `analise_avaliacao`→`AnaliseSentimento`, `extracao_campos`→`ExtracaoCampos`.
- **Não** trazer orquestração de domínio (`AttendanceOrchestrator`, política de
  ticket): isso é do `worker` (F4).
- **DoD:** cada método portado responde via gRPC com os mesmos resultados dos
  testes legados (fixtures reaproveitadas).

### Etapa 5.3 — Features de análise
- `transcribe_audio`, `interpret_media` (imagem/vídeo/documento),
  `analyse_message` (intents + entidades), `generate_embeddings` (1536).
- Override de provedor/modelo por `tenant_config`.
- **DoD:** cada feature testada isoladamente com fixtures.

### Etapa 5.4 — Resposta + RAG + sentimento
- `generate_response` (multi-turn com histórico + RAG via pgvector +
  `intent_behavior`/`QueryCompose`), `analyse_sentiment` (feedback/avaliação).
- Rastreabilidade `rag_sources` nos metadados da mensagem.
- **DoD:** resposta usa contexto recuperado; fontes RAG rastreáveis.

### Etapa 5.5 — Integração worker → IA + mídia
- Worker chama o `ia_engine` por **gRPC** (cliente tonic) com
  `tokio::time::timeout` + retry/backoff; degrada graciosamente se a IA estiver
  indisponível. Grava `resumo_midia` + `analise_midia` + **ponteiro** da mídia
  (storage_key, mimetype, size, **hash**); binário vai para storage transitório
  (`infrastructure_storage`/MinIO).
- Auto-assunto e tags (`intent:<x>`, `sentimento:<y>`) reavaliados por análise.
- **DoD:** fluxo da §11 do plano completo: mídia entra → resumo no banco →
  resposta da IA enviada; timeout/retry exercitados em teste.

---

## Fase 6 — Runtime API + Realtime  ⟶ MVP ponta-a-ponta

**Objetivo:** servir o cliente (comandos/consultas + tempo real).
**Dependências:** F4 (domínio), F2 (RBAC/auth).

### Etapa 6.1 — Binário `runtime_api`
- gRPC/HTTP: listar tickets/colunas/histórico, abrir/mover/assumir/transferir,
  enviar mensagem, configurar.
- Toda consulta com `tenant_id` + contexto RLS.
- **DoD:** comandos e consultas testados; autorização aplicada.

### Etapa 6.2 — crate `realtime` (WebSocket)
- Fan-out por tenant: nova mensagem, typing, presença, leitura, mudança de
  etapa, resposta da IA, atualização do Kanban.
- **DoD:** 2 clientes do mesmo tenant recebem eventos; isolamento entre tenants.

### Etapa 6.3 — Autenticação/autorização
- Tokens + refresh; RBAC por `tenant_user` (role + `module_permissions` +
  `flow_permissions`).
- **DoD:** acesso negado fora do escopo de fluxo/módulo; sessão expira/renova.

### Etapa 6.4 — Contrato cliente estável
- Congelar proto/DTOs em `contracts` para o Flutter (codegen Dart).
- **DoD:** contrato publicado; changelog de schema iniciado.

---

## Fase 7 — Flutter Windows (cliente, modo RemoteOnly)

**Objetivo:** painel desktop funcional consumindo o runtime_api.
**Dependências:** F6.

### Etapa 7.1 — Packages compartilhados
- `clients/packages/`: `domain_models` (DTOs), `api_client` (gRPC/HTTP+WS),
  `core_ui` (widgets/temas).
- **DoD:** packages compilam e testam (`flutter test`).

### Etapa 7.2 — Abstração `DataSource`
- Interface `DataSource` com implementação **`RemoteOnly`** (sem FFI).
- **DoD:** app roda 100% via rede; nenhuma dependência de `local_engine_ffi`.

### Etapa 7.3 — `flutter_windows` (telas)
- Login, lista de atendimentos (fila por departamento), chat, Kanban,
  configurações. Não-lidos por `message.lido` (fonte da verdade).
- **DoD:** atender ponta-a-ponta pelo desktop; build `flutter build windows`.

### Etapa 7.4 — Realtime no cliente
- Stores reagindo a eventos WebSocket (mensagem, etapa, status, presença).
- **DoD:** UI atualiza sem refresh; reconexão resiliente.

---

## Fase 8 — Local Engine (FFI) + mídia local

**Objetivo:** cache/offline de alto desempenho no Windows.
**Dependências:** F7.
**Risco-chave:** dual-target FFI (maior complexidade — ver §17 do plano).

### Etapa 8.1 — `local_engine` dual-target
- Crate compilável como **lib** (servidor) e **`cdylib`/`staticlib`** (FFI).
- Só lógica válida offline/cache; **nada multi-tenant sensível**.
- **DoD:** compila nos dois targets; sem símbolos de webhook/multi-tenant.

### Etapa 8.2 — Índice SQLite + cache de dados
- SQLite local: conversas/tickets/kanban em cache (leitura otimista).
- **DoD:** leitura local com baixa latência; coerência com servidor.

### Etapa 8.3 — Cache de mídia em disco
- Verificação por **hash**; download único do storage transitório; persistência
  local permanente. Servidor reentrega binário ao menos transitoriamente.
- **DoD:** 2ª visualização não toca o servidor; mídia ausente é rebaixada.

### Etapa 8.4 — `local_engine_ffi` + `DataSource: LocalEngineFFI`
- Bridge `flutter_rust_bridge`; `flutter_windows` troca para `LocalEngineFFI`.
- **DoD:** desktop usa cache local; fallback remoto quando ausente.

### Etapa 8.5 — Fila offline + sincronização
- Fila local de envios pendentes; reconciliação por WebSocket; estratégia de
  conflito definida (last-write-wins por timestamp do servidor + versionamento
  por evento para casos sensíveis).
- **DoD:** envio offline reconcilia ao reconectar; conflitos resolvidos.

---

## Fase 9 — Endurecimento, observabilidade, billing e deploy

**Objetivo:** prontidão para produção.
**Dependências:** F6 (mínimo) — idealmente F8.

### Etapa 9.1 — Observabilidade completa
- Métricas (Prometheus), tracing distribuído entre os 4 binários + IA, dashboards.
- **DoD:** rastrear uma mensagem do webhook à resposta com correlação por tenant.

### Etapa 9.2 — Billing/usage e quotas
- Medição de uso, aplicação de `plan`/`subscription`, bloqueio por inadimplência.
- **DoD:** quota excedida bloqueia ação; uso registrado por tenant.

### Etapa 9.3 — Retenção de mídia
- TTL/gatilho de expiração do binário no storage; resumo permanece para sempre.
- **DoD:** política aplicada; mídia expirada reentregue sob demanda quando possível.

### Etapa 9.4 — Segurança e carga
- Auditoria RLS rigorosa, testes de vazamento, rate limiting, testes de rajada.
- **DoD:** sem vazamento entre tenants sob carga; limites resistem a rajada.

### Etapa 9.5 — CI/CD + deploy Hostinger
- Pipelines por stack; deploy Hostinger KVM2; proxy reverso (Nginx/Caddy) com
  TLS e `proxy_buffering off` para WebSocket.
- **DoD:** deploy reproduzível; WebSocket estável atrás do proxy.

---

## Fase 10 — Port para Web

**Objetivo:** app Web com paridade de features, sem FFI.
**Dependências:** F7 (UI) e contrato estável de F6.

### Etapa 10.1 — `flutter_web` (RemoteOnly)
- App Flutter separado; reusa `core_ui`/`domain_models`/`api_client`; **não**
  depende de `local_engine_ffi`; `DataSource: RemoteOnly`.
- **DoD:** build `flutter build web`; sem dependência nativa.

### Etapa 10.2 — Paridade e mídia na Web
- Mídia servida pelo storage transitório (sem cache local).
- **DoD:** paridade funcional com o desktop nas operações essenciais.

---

## Apêndice A — Checklist transversal por PR

- [ ] `tenant_id` em toda query nova + policy RLS coberta.
- [ ] `domain_*` sem `infrastructure_*`.
- [ ] Eventos/DTOs novos em `contracts` com `TenantEnvelope` e versão.
- [ ] Comentários em pt-br; identificadores em inglês.
- [ ] Sem segredos no código (`.env`/cifragem).
- [ ] Testes da etapa + lint da stack passando.
- [ ] Idempotência preservada onde há `message_id`/`stanzaId`.

## Apêndice B — Rastreabilidade de regras v1 → componentes v2

| Regra v1 (referência) | Onde vive na v2 |
|---|---|
| `inicializar_atendimento_whatsapp` / reaproveitar ativo | `application::DecideTicketPolicy` |
| Status `FILA…ARQUIVADO` + histórico | `domain_ticket` (máquina de estados) |
| `bot_pode_atender` + `AppInstance.resposta_bot` | `application::CanBotRespond` / `BotRulesEngine` |
| `MovimentoFluxo` (SLA por etapa) | `domain_kanban` + `flow_movement` |
| `EtapaFluxo`/`FluxoAtendimento`/`Departamento` | `domain_kanban` (stage/flow/department) |
| `Mensagem` (mídia, reply, read receipts) | `domain_conversation` + `message` |
| `resumo_midia`/`analise_midia`/ponteiro | F5.5 + `infrastructure_storage` |
| `FeaturesCompose` (facade de IA pura) | `ia_engine` (núcleo reaproveitado; F5.2b) |
| `AttendanceOrchestrator` (orquestração) | `worker` + `application`/`domain_*` (Rust) |
| Celery: `process_contact_response_task` (fila) | `worker` consumindo Redis Streams (F4.3) |
| Celery: `verificar_feedback`/`purge_media` (agendamento) | scheduler do `worker` (F4.3b) |
| `message_buffer` (debounce Redis) | `application::DebounceByContact` (F4.2) |
| `Documento`/`QueryCompose` (pgvector 1536) | `training_document`/`intent_behavior` + `ia_engine` |
| `TenantConfig` (persona/prompts/providers) | `tenant_config` + `ia_engine` override |
| `Tenant`/`Plan`/`Subscription`/`TenantUser` | F2 Control Plane |

---

*Documento de fases criado como guia operacional. Sujeito a refinamento a cada
fase concluída (retroalimenta o planejamento).*
