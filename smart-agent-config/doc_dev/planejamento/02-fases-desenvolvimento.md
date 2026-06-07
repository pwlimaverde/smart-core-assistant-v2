# Smart Core Assistant v2 — Fases de Desenvolvimento

> **Status:** Guia operacional de construção — **revisado em junho/2026** para
> refletir o estado real do desenvolvimento.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** Deriva de [00-planejamento-inicial.md](./00-planejamento-inicial.md)
> (visão/arquitetura) e [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md)
> (organização de pastas). Define **o quê construir, em que ordem e como saber
> que está pronto** — agora com **status por etapa** e os novos crates de base.

---

## Como usar este guia

- O desenvolvimento é dividido em **Fases** (marcos de valor) → **Etapas**
  (entregáveis coesos) → **Componentes/tarefas**.
- A numeração de fases (**F0–F10**) é um **mapa de dependência lógica**, não
  cronológico. Vários itens de persistência das F1–F5 foram **adiantados** para
  a crate `infrastructure_postgres` (ver §"Estado atual"). As referências
  F1/F4.3b/F5.5/F6/F8/F9.3 usadas em outros planos continuam válidas.
- Cada etapa tem **status**, **entregáveis** e **critérios de aceite (DoD)**.
- Convenção de branch (gitflow): `feature/<fase>-<slug>` a partir de `dev`. Sem
  `Co-Authored-By` nem rodapés de IA.
- **Definition of Done global por etapa:** compila + lint limpo
  (`cargo clippy -- -D warnings` / `ruff` / `flutter analyze`) + testes da etapa
  passando + comentários em pt-br + sem segredos no código.

### Legenda de status
- ✅ **Concluído** — implementado e validado.
- 🚧 **Em andamento** — começado.
- ⬜ **Pendente** — ainda não iniciado.

---

## Estado atual do desenvolvimento (snapshot)

### O que já está pronto (✅)
- **Crates de Base/Fundação** — `contracts` (schemas proto/fbs, Envelope e stubs gerados), `transport` (codec FlatBuffers/gRPC, canais UDS/TCP/WS, barramento `transport::bus`), `error_core` (erros serializáveis `ErrorEnvelope`) e `observability` (tracing, `traceparent`, auditoria rewired para Streams).
- **Serviços de Dados (data_*)** — `data_postgres` (encapsulando RLS pool, migrations e CRUD Postgres de `infrastructure_postgres`), `data_redis` (encapsulando cache, tokens, locks de `infrastructure_redis`) e `data_storage` (encapsulando Cloudflare R2 de `infrastructure_storage`).
- **Infraestrutura de dados + deploy** — `docker/compose/data.yml` (PG+pgvector, Redis, MinIO) e scripts `infra/` de automação e túnel SSH.
- **Bootstrap de superusuário** — CLI `create-superuser` e `delete-superuser` no `control_plane` (thin RPC client → `data_postgres`), com auditoria e trail.

### O que está em andamento (🚧)
- **Módulo de autenticação** (`user-auth-module`) — Casos de uso de autenticação e RBAC em `application`, expostos via RPC no `runtime_api`. **Pré-requisito para o painel admin.**
- **Painel Admin do Superusuário** — Equivalente ao Django admin da v1: gestão de tenants, planos, assinaturas e pagamentos via Flutter + `runtime_api`. Veja [11-painel-admin-superusuario.md](./11-painel-admin-superusuario.md).
- **Orquestração e Gateway de Mensagens** — O bootstrap estrutural de `messaging_gateway`, `worker` e `control_plane` já foi criado na reestruturação e aguarda a lógica detalhada de suas respectivas fases.

### O que está pendente (⬜)
- **`ia_engine`** (serviço Python separado via gRPC/FlatBuffers).
- **realtime** (fan-out do stream gRPC via Redis pub/sub no `runtime_api`).
- **Clients Flutter** e o motor local **`local_engine`** (FFI).
- **CI/CD + DevOps** completo (plano 10).

### Inventário de crates/apps × status

| Componente | Tipo | Status | Plano/Nota |
|---|---|---|---|
| `infrastructure_postgres` | crate infra | ✅ | repositórios SQLx, criptografia e migrations |
| `infrastructure_redis` | crate infra | ✅ | conexões Redis, cache, tokens, locks |
| `infrastructure_storage` | crate infra | ✅ | cliente R2 real (`aws-sdk-s3`), presign real, layout `media/{tenant}/...` |
| `infrastructure_evolution` | crate infra | ⬜ | cliente HTTP REST para o Evolution Go |
| `contracts` | crate base | ✅ | schemas proto/fbs, Envelope e tipos gerados |
| `transport` | crate base | ✅ | canais UDS/TCP/WS, codecs e barramento |
| `observability` | crate base | ✅ | tracing OTLP central + auditoria via bus |
| `error_core` | crate base | ✅ | taxonomia e erros com `ErrorEnvelope` serializável |
| `application` | crate aplicação| 🚧 | casos de uso de negócio; em andamento com o auth |
| `local_engine` | crate (FFI) | ⬜ | F8; motor local embarcado |
| `data_postgres` | app | ✅ | servidor RPC Postgres síncrono/assíncrono + outbox |
| `data_redis` | app | ✅ | servidor RPC Redis síncrono (tokens, cache, locks) |
| `data_storage` | app | 🚧 | servidor RPC (PutFile/GetFile/PresignFile) + consumer de purga **funcionando sobre o stub filesystem**; backend R2/MinIO pendente |
| `control_plane` | app | 🚧 | bootstrapado; aguarda endpoints admin (F2) |
| `messaging_gateway` | app | 🚧 | bootstrapado; aguarda lógica webhook WhatsApp (F3) |
| `worker` | app | 🚧 | bootstrapado; aguarda orquestrador do domínio (F4) |
| `runtime_api` | app | 🚧 | em andamento; gRPC mínimo (auth) (F6) |
| `clients/packages/core_ui` | pacote Flutter | ⬜ | bootstrap na F6.5 (design system) |
| `clients/packages/api_client` | pacote Flutter | ⬜ | bootstrap na F6.5 (gRPC único / FlatBuffers) |
| `clients/flutter_windows` | stack Flutter | ⬜ | incremental (F6.5 bootstrap+auth → F2/F4/F5 telas → F7 consolida) |
| `clients/flutter_web` | stack Flutter | ⬜ | F10 (RemoteOnly; reusa packages) |
| `evolution/` | stack Go | ⬜ | F3; gateway Evolution Go |
| `ia_engine` | stack Python | ⬜ | F5; gRPC/FlatBuffers IA engine |

> **Nota de arquitetura (camadas — esclarecimento importante):**
> `infrastructure_postgres` **não é** a camada de domínio. É a **ponte de
> persistência**: padroniza a comunicação com o banco (migrations, organização
> das tabelas e funções de **CRUD**), **sem regras de negócio**. Os seus módulos
> por domínio (`tenants/`, `clientes/`, `atendimentos/`, `operacional/`,
> `treinamento/`, `integracoes/`) são apenas **repositórios** (CRUD por tabela).
>
> As **regras de negócio** moram na camada **`application`** (casos de uso), que
> **orquestra** chamando o CRUD do `infrastructure_postgres`. Exemplo:
> *processar a mensagem recebida* (regra → `application`) e, ao final, *salvar a
> mensagem* (chama a função de criação do `infrastructure_postgres`).
>
> Os crates **`domain_*` puros** (regras de domínio sem I/O) são **opcionais** e
> podem ser **extraídos da `application`** quando a complexidade justificar; até
> lá, a regra vive na `application`. A regra **"`domain_*` sem I/O"** vale para
> quando forem criados.

---

### Princípios invioláveis (revalidar a cada PR)
1. **O webhook nunca executa regra pesada** — só autentica, resolve tenant,
   persiste bruto e publica no bus.
2. **`tenant_id` em toda query** + **RLS** como segunda barreira (toda query de
   tenant roda em `run_in_tenant_transaction` com `RequestContext`).
3. **`domain_*` sem I/O** — quando criados, nenhuma dependência de
   `infrastructure_*`.
4. **`local_engine` sem lógica multi-tenant sensível nem de webhook.**
5. **`DataSource` abstrato desde o dia 1** no Flutter — garante o port Web sem
   reescrita.
6. **Uma crate por sistema externo** — `infrastructure_postgres` (SQLx),
   `infrastructure_redis` (Redis), `infrastructure_storage` (S3/R2) são as
   **únicas** que falam com cada cliente.
7. **Transporte Flutter ↔ servidor é gRPC único** — unário (comandos/consultas) +
   **Server Streaming** (realtime). Sem WebSocket. Web via gRPC-Web (`tonic-web`).
   Toda tela fala só com o `api_client`.
8. **UI incremental, colada à feature** — cada feature de backend entrega, no
   mesmo ciclo, a tela que a valida (a partir da F6/auth). A UI nasce no
   `flutter_windows` em modo `RemoteOnly`. Ver "Trilha de UI" abaixo.

### Mapa de dependências entre fases

```
F0 Fundação ──► F1 Banco+RLS+Storage ──► Bootstrap CLI superuser
   (✅ infra      (✅ feito)              (✅ create/delete-superuser)
    local)             │
                       │
                       ▼
               F6.1 runtime_api + AuthService (Login/Logout/Refresh)
                       │
                       ▼
               F6.2 AuthInterceptor (is_superuser role guard)
                       │
                       ▼
               F2-admin Control Plane CRUD ──► AdminService no runtime_api
                       │                               │
                       │                               ▼
                       │                    Flutter Admin (Painel Superusuário)
                       │                    (Tenants, Planos, Assinaturas, Pagamentos)
                       │                    ← ver 11-painel-admin-superusuario.md
                       │
                       ├──► F3 Messaging Gateway + Evolution
                       │            │
                       │            ▼
                       └──► F4 Worker + Domínio ──► F5 ia_engine (gRPC)
                                  │                     │
                                  ▼                     │
                          F6 Runtime API completo ◄─────┘
                          (Auth regular, Register, Invite)
                          └─► UI: login/cadastro tenant
                          └─► F4.6 Kanban/chat Flutter
                                  │
                                  ▼
                          F7 Flutter Windows — consolidação (RemoteOnly)
                                  │
                                  ▼
                          F8 Local Engine (FFI) + mídia local
                                  │
                                  ▼
                          F9 Endurecimento + billing + observ. + CI/CD + deploy
                                  │
                                  ▼
                          F10 Port Web (RemoteOnly)
```

> **Ordem prática de desenvolvimento:** fundação ✅ → auth superusuário (F6.1–6.2) →
> **painel admin** (F2-admin + Flutter admin) → auth regular de tenants (F6 completo) →
> features operacionais (F3/F4/F5). O painel admin é a primeira feature de negócio
> porque valida toda a stack (JWT, gRPC, Flutter, controle de acesso) em um ambiente
> controlado (apenas o superusuário usa).
>
> **MVP funcional ponta-a-ponta** = F0→F6. A persistência das F1–F5 já está
> pronta; falta a orquestração (worker, gateway, IA) e a API/realtime.

---

## Trilha de UI incremental (transversal — decisão D8)

A UI **não** é uma fase única e tardia. A partir da F6 (quando o `runtime_api`
ganha o primeiro endpoint gRPC real), **cada feature de backend entrega a tela
que a valida**, no `flutter_windows` em modo `RemoteOnly` (sem FFI), consumindo o
`api_client`. O objetivo é conferir o uso ponta-a-ponta a cada feature — começando
pelas telas de login e cadastro junto do auth.

> **Pré-requisito único:** existir o endpoint gRPC da feature no `runtime_api`. A
> primeira leva de UI nasce com o auth (F6), que também faz o bootstrap do app e
> do design system `core_ui`.

| Feature de backend | Fase | Tela entregue junto (flutter_windows · RemoteOnly) |
|---|---|---|
| **Bootstrap + auth** | **F6** | Shell do app + `core_ui` (tema dark) + **login** + **cadastro** (Register) + aceite de convite |
| Control Plane (admin) | F2 | Telas internas de gestão: tenants, planos/assinatura, convites (uso administrativo) |
| Worker + Kanban (sem IA) | F4 | Fila por departamento + **painel Kanban** (drag-and-drop) + **chat lateral** consumindo o **Server Streaming** |
| `ia_engine` | F5 | Exibição da resposta da IA e do resumo de mídia dentro do chat |
| Local Engine (FFI) | F8 | Estados offline/cache na UI (troca para `DataSource: LocalEngineFFI`) |
| Endurecimento/billing | F9 | Tela de configurações do tenant + uso/billing |

**Regras da trilha:**
- A UI sempre fala com o `api_client` (gRPC) — nunca com infraestrutura nem FFI
  direto fora do `local_engine_ffi`.
- Componentes visuais reutilizáveis vão para `core_ui` (design system); telas
  específicas ficam no app.
- `DataSource` abstrato desde a primeira tela (modo `RemoteOnly`), garantindo o
  port Web (F10) sem reescrita.
- **DoD de cada tela:** `flutter analyze` limpo + a tela exercita o fluxo real da
  feature contra o `runtime_api` (não mock) + comentários em pt-br.

> **F7 deixa de ser "construir todas as telas".** Como as telas nascem coladas às
> features, a F7 passa a ser **consolidação** do app Windows (navegação, estados de
> erro/carga, acessibilidade, empacotamento) — ver Fase 7.

---

## Fase 0 — Fundação do monorepo e infra local

**Objetivo:** esqueleto compilável de todas as stacks + ambiente local de dados.

### Etapa 0.1 — Esqueleto de diretórios — 🚧
- ✅ `server/`, `docker/`, `infra/`, `smart-agent-config/` criados.
- ⬜ `evolution/`, `clients/`, `ia_engine/` (criados quando as fases chegarem).
- ✅ `.env.example` + `.gitignore` cobrindo `.env`, `target/`, `infra/.env.deploy`.

### Etapa 0.2 — Cargo workspace — ✅
- ✅ `server/Cargo.toml` (workspace) + `Cargo.lock` configurados com todos os membros de `apps/` e `crates/`.
- **DoD:** `cargo build` verde no workspace; `cargo fmt --check` limpo.

### Etapa 0.3 — Infra local de dados — ✅
- `docker/compose/data.yml`: PostgreSQL 16 + pgvector, Redis 7, MinIO.
- `docker/init-scripts/01-extensions.sql` (`vector`, `uuid-ossp`).
- **DoD:** `docker compose -f docker/compose/data.yml up -d` sobe saudável.

### Etapa 0.4 — crate `observability` — ✅
- logs estruturados (JSON) com `tracing`; spans com `tenant_id` e contexto OTLP. Auditoria direcionada para Streams (bus) sem conexão direta ao Postgres.
- **DoD:** binário emite log JSON com nível configurável; trace exportável.

### Etapa 0.5 — crate `error_core` — ✅
- Taxonomia (`ErrorCode`, `ErrorCategory`), agregador `AppError` e mapeamento para `ErrorEnvelope` serializável que cruza a fronteira IPC/RPC de rede.
- **DoD:** erros estruturados e rastreáveis na observabilidade.

### Etapa 0.6 — crate `contracts` — ✅
- Schemas `.proto` canônicos em `schemas/`, transpilação automática para `.fbs` no build, e stubs de tipos gerados automaticamente via `build.rs` (FlatBuffers + Tonic). Exposição do `Envelope` unificado.
- **DoD:** stubs gerados; compatibilidade de tipos compilando no workspace.

### Etapa 0.7 — crate `transport` — ✅
- Implementação de codecs (FlatBuffers, gRPC), canais UDS/TCP/WS, protocolo de framing RPC (len, flags, corr_id) e barramento assíncrono Redis Streams (`transport::bus`).
- **DoD:** transmissão local via UDS e barramento Streams operando.

---

## Fase 1 — Banco unificado multi-tenant + RLS — ✅ (concluída)

**Objetivo:** persistência única com isolamento por tenant garantido pelo banco.
**Entregue na crate `infrastructure_postgres`** — ver [03-infraestrutura-postgres.md](./03-infraestrutura-postgres.md).

### Etapa 1.1 — `infrastructure_postgres` (fundação) — ✅
- Pool `sqlx`, runner de migrations, healthcheck (`criar_pool`,
  `inicializar_banco_dados`), `run_in_tenant_transaction`.

### Etapa 1.2 — Tenant context + policies RLS — ✅
- `security.rs` (`RequestContext`) + função RLS (`0001_create_rls_function.sql`)
  com `SET LOCAL app.current_tenant`; policies fail-closed por tabela.

### Etapa 1.3 — Migrations do schema de domínio — ✅
- Migrations **0002–0011** cobrem Control Plane, domínio operacional,
  atendimentos, treinamento RAG (pgvector 1536), evolution_sync, settings,
  **audit_log (0010)** e **outbox (0011)**.

### Etapa 1.4 — Testes de isolamento multi-tenant — ✅
- Suíte de integração contra Postgres real (vazamento entre tenants + ausência
  de contexto). *Revalidar a cada nova tabela.*

### Etapa 1.5 — `infrastructure_storage` (R2/MinIO) — 🚧 (stub)
- **Estado atual:** `StorageClient` é um **stub baseado em filesystem** (grava em
  diretório local; `presign` devolve URL mockada) já integrado como dependência de
  `data_storage` e exercido pelos handlers RPC. A API atual é `put/get/presign/delete`
  por `tenant_id`+`file_name`.
- **Pendente:** substituir o stub pela ponte S3-compatible (`aws-sdk-s3`) com layout
  `media/{tenant}/{instance}/{type}/{hash}`, presign real e R2 em produção / MinIO em
  dev — ver [08-infraestrutura-storage.md](./08-infraestrutura-storage.md).
- **DoD:** CRUD de objetos e links pré-assinados **reais** contra MinIO/R2.

### Etapa 1.6 — Microsserviços de dados (`data_*`) — ✅
- Embrulho das bibliotecas de infraestrutura em apps de execução independentes (`data_postgres`, `data_redis`, `data_storage`) expondo servidores RPC IPC/UDS para leitura/escrita e escuta do bus.
- **DoD:** comunicação UDS direta no Cargo workspace operando; persistência preservada sob RLS.

---

## Fase 2 — Control Plane

**Objetivo:** back office — gestão de tenants, planos, RBAC, credenciais e
registro de instâncias Evolution. **Persistência já pronta; falta o app.**

### Etapa 2.1 — Regras de tenant/plano/quota — ⬜
- Dados e repositórios já existem em `infrastructure_postgres/tenants/` +
  `plans`/`settings`. Extrair regras puras para `domain_tenant` **se/quando**
  justificar (ver nota de arquitetura).

### Etapa 2.2 — Cifragem de credenciais — ✅
- `crypto.rs` (`CipherManager`, AES-256-GCM) cifra api keys de provedores e
  tokens de instância; chave-mestra via env.

### Etapa 2.3 — Binário `control_plane` — ⬜
- CRUD (tenant, config, plano/assinatura, tenant_user/invite) sobre os
  repositórios existentes; API gRPC de administração.

### Etapa 2.4 — `infrastructure_evolution` (provisionamento) — ⬜
- Cliente **HTTP** do Evolution Go (`/instance/create|connect|qr|pair|status`),
  global key × token de instância, guard de quota. *A persistência das instâncias
  já existe em `integracoes/evolution.rs` + migration 0008.*

### Etapa 2.5 — UI: telas de administração (trilha de UI) — ⬜
- No `flutter_windows`: telas internas de gestão de **tenants**, **planos/
  assinatura** e **convites**, consumindo a API do `control_plane` via `api_client`.
  Componentes reutilizáveis em `core_ui`. **DoD:** fluxos reais contra o servidor;
  `flutter analyze` limpo.

---

## Fase 3 — Messaging Gateway + Evolution multi-instância

**Objetivo:** ingestão confiável de webhooks → evento interno no bus.

### Etapa 3.1 — `evolution/` (infra do gateway WhatsApp) — ⬜
- `docker/` (Evolution Go + 2 PG; sem Redis; `DATABASE_SAVE_MESSAGES=false`),
  `config/` e `scripts/` de provisionamento.

### Etapa 3.2 — `domain_whatsapp` (normalização) — ⬜
- Mapeamento por chave JSON (`imageMessage`/`audioMessage`/… → `media_type`),
  normalização de `messages.upsert` → evento interno, reply/`stanzaId`.

### Etapa 3.3 — barramento de eventos (`transport::bus`) — ✅
- Redis Streams + consumer groups integrados em `transport::bus`; envelopes serializáveis e publish/consume operacionais.
- **DoD:** eventos no bus fluem com sucesso no workspace.

### Etapa 3.4 — Binário `messaging_gateway` — 🚧
- Ingestão de webhooks → resolve `tenant_id` → persiste bruto via RPC em `data_postgres` → publica evento no bus. Sem regras de negócio.
- **DoD:** webhook cadastrado e eventos enfileirados no bus com sucesso.

---

## Fase 4 — Worker + domínio (sem IA)

**Objetivo:** orquestrar conversa/ticket/kanban e enviar resposta — ainda sem LLM.
*Persistência de atendimentos/clientes/operacional já pronta no Postgres.*

### Etapa 4.1 — Regras de domínio — ⬜
- Ciclo de vida do atendimento, reaproveitamento de ativo, reabertura/feedback,
  transferência. Em `application`/`domain_*` (reusando os repositórios prontos).

### Etapa 4.2 — `application` (casos de uso) — 🚧 (base via auth)
- `ReceiveMessage`, `DebounceByContact`, `ResolveConversation`,
  `DecideTicketPolicy`, `ApplyKanbanStage`, `CanBotRespond`, `TransferFlow`. A
  crate já nasce com o auth; estes casos de uso entram aqui.

### Etapa 4.3 — Binário `worker` — 🚧
- Consome o bus, executa o debounce por contato, resolve a conversa, aplica políticas de ticket e atualiza o Kanban via chamadas RPC a `data_postgres` e `data_redis`.
- **DoD:** processamento assíncrono consumindo eventos do bus integrado com sucesso.

### Etapa 4.3b — Scheduler do `worker` (substitui o Celery da v1) — ⬜
- Timeout de feedback + purga de mídias. A purga de mídia dispara requisição RPC para o serviço `data_storage::remover_objeto`.
- **DoD:** tarefas temporais agendadas no Redis executadas de forma resiliente.

### Etapa 4.4 — Envio outbound — ⬜
- Dispara requisição HTTP REST para o Evolution Go (`/message/sendText|sendMedia`) com retry e backoff; escuta confirmações.
- **DoD:** envio outbound operando via gateway.

### Etapa 4.5 — `BotRulesEngine` (sem LLM) — ⬜
- Lógica de barreira de bot (resposta automática ativa, sem interação humana, flag `bot_pode_atender`). Resposta temporária.
- **DoD:** bot respondendo mensagens simuladas via RPC.

### Etapa 4.6 — UI: fila + Kanban + chat lateral (trilha de UI) — ⬜
- No `flutter_windows`: **fila por departamento**, **painel Kanban** com
  drag-and-drop (`appflowy_board` ou equivalente) e **chat lateral** consumindo o
  **gRPC Server Streaming** (`StreamAtendimentos`) via stores reativos. Envio de
  mensagem outbound pela tela. Componentes em `core_ui` (card de Kanban, painel de
  chat, input). **DoD:** mover card e enviar/receber mensagem em tempo real contra
  o `runtime_api`; `flutter analyze` limpo.

---

## Fase 5 — `ia_engine` (Python, serviço RPC) — ⬜

**Objetivo:** mídia→texto, intents/entidades, RAG, resposta e sentimento, como serviço Python exposto por RPC e consumido pelo `worker`.

- **5.1** skeleton (`uv`, `server.py` RPC, `features/`, `llm/`, `contracts/`).
- **5.2** contratos e stubs gerados com base em schemas `.proto` (stubs nos dois lados).
- **5.2b** portar a facade `FeaturesCompose` da v1 (núcleo de IA quase intacto).
- **5.3** features de análise (transcribe/interpret/analyse/embeddings 1536).
- **5.4** resposta + RAG (pgvector + `query_compose` via `data_postgres` RPC) + sentimento.
- **5.5** integração worker→IA + mídia: grava `resumo`/`analise` + **ponteiro** (`MediaPointer`) via `data_postgres` RPC; binário vai para `data_storage` RPC (R2). Timeout + retry/backoff; degradação graciosa.

---

## Fase 6 — Runtime API + Realtime  ⟶ MVP ponta-a-ponta — 🚧

**Objetivo:** servir o cliente (comandos/consultas + tempo real).
**Em andamento via `user-auth-module`.**

### Etapa 6.1 — Binário `runtime_api` — 🚧
- gRPC (Tonic). Auth: `AuthService` (Register/Login/Refresh/Logout/Invite/
  Accept) já planejado/iniciado. Demais comandos/consultas (tickets, kanban,
  histórico) ⬜.

### Etapa 6.2 — crate `realtime` (gRPC Server Streaming) — 🚧
- RPC de stream autenticado (ex.: `StreamAtendimentos`) — o cliente abre um
  stream gRPC e o servidor empurra eventos. Fan-out por tenant (mensagem, typing,
  presença, kanban) completo ⬜ — usa **Redis pub/sub** para multi-réplica.
  **Sem WebSocket** (decisão D7). O JWT é validado na abertura do stream pelo
  mesmo interceptor das chamadas unárias.

### Etapa 6.3 — Autenticação/autorização — 🚧
- JWT HS256 (access 15min) + refresh opaco 7d (rotação por família, reuse-
  detection), blocklist, RBAC (`role`+`module_permissions`+`flow_permissions`),
  rate limiting de login. **Defesa em 3 camadas** (interceptor → escopos → RLS).
  Detalhe no plano canônico `user-auth-module` e no doc
  [09-comunicacao-e-autenticacao.md](./09-comunicacao-e-autenticacao.md).

### Etapa 6.4 — Contrato cliente estável — ⬜
- Congelar proto/DTOs em `contracts` para o Flutter (codegen Dart); habilitar
  `tonic-web` para o app Web; changelog.

### Etapa 6.5 — UI: bootstrap do `flutter_windows` + telas de auth — ⬜ — **NOVO (trilha de UI)**
- Bootstrap do app `flutter_windows` + packages `core_ui` (design system, tema
  dark), `domain_models` (DTOs do `.proto`) e `api_client` (factory gRPC `kIsWeb`,
  modo `RemoteOnly`).
- **Telas de login e cadastro** (e aceite de convite) consumindo `AuthService`
  via gRPC, validando o fluxo ponta-a-ponta (decisão D8). Guarda de sessão
  (armazenamento seguro do refresh token + auto-refresh do access token).
- **DoD:** `flutter analyze` limpo; login/cadastro reais contra o `runtime_api`
  emitem e renovam tokens; navegação autenticada protegida.

---

## Fase 7 — Flutter Windows: consolidação do app (RemoteOnly) — ⬜

**Objetivo:** consolidar em um app coeso as telas que **já nasceram coladas às
features** (login/cadastro na F6.5; admin na F2; Kanban/fila/chat na F4; IA no
chat na F5). Aqui não se "constrói tudo do zero" — refina-se o conjunto.

- **7.1** packages estáveis (`domain_models`, `api_client`, `core_ui`) — já
  existentes da trilha de UI; aqui são revisados e versionados.
- **7.2** `DataSource: RemoteOnly` consolidado (sem FFI), interface estável para
  o port Web e para a futura troca por `LocalEngineFFI` (F8).
- **7.3** navegação, estados de carga/erro/vazio, acessibilidade e consistência
  visual entre as telas; settings do tenant.
- **7.4** realtime no cliente consolidado (stores reagindo aos eventos do
  **stream gRPC**), reconexão e backpressure.
- **7.5** empacotamento e build de release (`flutter build windows --release`).

---

## Fase 8 — Local Engine (FFI) + mídia local — ⬜

**Objetivo:** cache/offline de alto desempenho no Windows.
**Risco-chave:** dual-target FFI.

- **8.1** `local_engine` dual-target (lib + `cdylib`/`staticlib`).
- **8.2** índice SQLite + cache de dados.
- **8.3** cache de mídia em disco (verificação por **hash**; download único via
  **URL pré-assinada** do `infrastructure_storage`/R2; persistência local).
- **8.4** `local_engine_ffi` + `DataSource: LocalEngineFFI`.
- **8.5** fila offline + sincronização (last-write-wins + versionamento).

---

## Fase 9 — Endurecimento, observabilidade, billing, CI/CD e deploy — ⬜

**Objetivo:** prontidão para produção.

### Etapa 9.1 — Observabilidade completa — ⬜
- Métricas (Prometheus), tracing distribuído entre binários + IA, dashboards
  (stack LGTM self-hosted). **Plano [05](./05-observabilidade.md).**
- **DoD:** rastrear uma mensagem do webhook à resposta, correlacionada por tenant.

### Etapa 9.2 — Billing/usage e quotas — ⬜
- Medição de uso, aplicação de `plan`/`subscription` (repos já existem), bloqueio
  por inadimplência; quota de instâncias e de storage por tenant.

### Etapa 9.3 — Retenção de mídia — ⬜
- TTL/lifecycle do binário (R2 lifecycle ≤ 30 dias **ou** purga via worker); o
  resumo permanece. Ver [08-infraestrutura-storage.md §8](./08-infraestrutura-storage.md).

### Etapa 9.4 — Segurança e carga — ⬜
- Auditoria RLS, testes de vazamento, rate limiting, testes de rajada.

### Etapa 9.5 — CI/CD + deploy Hostinger — ⬜
- Pipelines por stack (CI) + entrega via **SSH + GHCR** (CD); deploy KVM2; proxy
  reverso (Caddy/Nginx) com TLS e `proxy_buffering off`. Hoje o deploy é
  **manual** (`infra/`). **Plano [10](./10-plano-cicd-devops.md) → docs 11 (CI/CD) e 12 (DevOps).**

---

## Fase 10 — Port para Web — ⬜

**Objetivo:** app Web com paridade de features, sem FFI.

- **10.1** `flutter_web` (RemoteOnly; sem `local_engine_ffi`).
- **10.2** paridade e mídia na Web (servida por URL pré-assinada do R2; **CORS**
  no bucket — ver [08 §7.5](./08-infraestrutura-storage.md)).

---

## Apêndice A — Checklist transversal por PR

- [ ] `tenant_id` em toda query nova + policy RLS coberta
      (`run_in_tenant_transaction`).
- [ ] `domain_*` (quando existir) sem `infrastructure_*`.
- [ ] Eventos/DTOs novos em `contracts` com `TenantEnvelope` e versão.
- [ ] Chaves de storage no layout `media/{tenant}/{instance}/{type}/{hash}`.
- [ ] Comentários em pt-br; identificadores em inglês.
- [ ] Sem segredos no código (`.env`/cifragem; `.env.deploy` git-ignored).
- [ ] Testes da etapa + lint da stack passando.
- [ ] Idempotência preservada onde há `message_id`/`stanzaId`/`hash`.

## Apêndice B — Rastreabilidade v1 → componentes v2 (estado real)

| Regra v1 (referência) | Onde vive na v2 | Status |
|---|---|---|
| Schema multi-tenant + RLS | `infrastructure_postgres` (migrations 0001–0009) | ✅ |
| Cifragem de credenciais (Fernet) | `crypto.rs` (`CipherManager`, AES-256-GCM) | ✅ |
| `TenantConfig` (persona/prompts/providers) | `tenants/config.rs` + `tenant_config` | ✅ (persist.) |
| `Tenant`/`Plan`/`Subscription`/`TenantUser` | `tenants/`, `plans`, `users` + migr. 0002/0003 | ✅ (persist.) |
| `Documento`/`QueryCompose` (pgvector 1536) | `treinamento/` + migration 0007 | ✅ (persist.) |
| `AppInstance`/Evolution | `operacional/app_instances.rs` + `integracoes/evolution.rs` + migr. 0005/0008 | ✅ (persist.) |
| Atendimento/Mensagem/Movimento | `atendimentos/` + migration 0006 | ✅ (persist.) |
| Refresh/blocklist/cache de permissões | `infrastructure_redis` (auth_tokens, cache) | ✅ |
| Event bus (substitui fila Celery) | `infrastructure_redis::event_bus` | ✅ |
| Mídia (binário transitório) | `infrastructure_storage` (R2/MinIO) | 🚧 (stub filesystem; S3/R2 pendente) |
| Auth/JWT/sessão + `runtime_api` | `application` + `apps/runtime_api` | 🚧 |
| `AttendanceOrchestrator` (orquestração) | `worker` + `application` | ⬜ |
| Celery: `process_contact_response_task` | `worker` consumindo Streams | ⬜ |
| Celery: feedback/purga de mídia | scheduler do `worker` (4.3b) | ⬜ |
| `message_buffer` (debounce) | `application::DebounceByContact` | ⬜ |
| `FeaturesCompose` (IA pura) | `ia_engine` (gRPC) | ⬜ |

## Apêndice C — Planos relacionados

- [03-infraestrutura-postgres.md](./03-infraestrutura-postgres.md) — Postgres + RLS (✅).
- [04-infraestrutura-redis.md](./04-infraestrutura-redis.md) — Redis (✅).
- [05-observabilidade.md](./05-observabilidade.md) — logs/métricas/traces + LGTM.
- [06-tratamento-de-erros.md](./06-tratamento-de-erros.md) — crate `error_core`.
- [07-crate-contracts.md](./07-crate-contracts.md) — contratos/eventos/envelope.
- [08-infraestrutura-storage.md](./08-infraestrutura-storage.md) — storage R2/MinIO.
- [09-comunicacao-e-autenticacao.md](./09-comunicacao-e-autenticacao.md) — transporte + auth.
- [10-plano-cicd-devops.md](./10-plano-cicd-devops.md)
  — plano-mãe CI/CD + DevOps (docs 11/12 a detalhar).
- `.context/plans/user-auth-module.md` — plano canônico do auth (🚧).

---

*Documento de fases revisado para refletir o estado real (junho/2026).
Retroalimentado a cada fase concluída.*
