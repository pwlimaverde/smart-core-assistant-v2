# Smart Core Assistant v2 — Fases de Desenvolvimento

> **Status:** Guia operacional de construção — **atualizado em 2026-07-06** após o
> fechamento de dois ciclos PREVC: `finalizacao-mvp-operacional` (WS-0..WS-4) e
> `mvp-telas-e-endurecimento` (RBAC fino, user_agent, cache invalidation, telas
> operacionais/admin, e2e de trace). **O MVP operacional ponta-a-ponta está
> fechado.** Inclui **próximos passos divididos em fases** ao final do snapshot.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** Deriva de [00-planejamento-inicial.md](./00-planejamento-inicial.md)
> (visão/arquitetura) e [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md)
> (organização de pastas). Define **o quê construir, em que ordem e como saber
> que está pronto** — com **status por etapa** auditado contra o código real.

---

## Como usar este guia

- O desenvolvimento é dividido em **Fases** (marcos de valor) → **Etapas**
  (entregáveis coesos) → **Componentes/tarefas**.
- A numeração de fases (**F0–F10**) é um **mapa de dependência lógica**, não
  cronológico. As referências F1/F4.3b/F5.5/F6/F8/F9.3 usadas em outros planos
  continuam válidas.
- Cada etapa tem **status**, **entregáveis** e **critérios de aceite (DoD)**.
- Convenção de branch (gitflow): `feature/<fase>-<slug>` a partir de `dev`. Sem
  `Co-Authored-By` nem rodapés de IA.
- **Definition of Done global por etapa:** compila + lint limpo
  (`cargo clippy -- -D warnings` / `ruff` / `flutter analyze`) + testes da etapa
  passando + comentários em pt-br + sem segredos no código.
- **Testes sempre pelos scripts canônicos:** `.\infra\test-local.ps1` (Rust) e
  `.\infra\test-flutter.ps1` (Flutter) — nunca `cargo test`/`flutter test` direto.

### Legenda de status

- ✅ **Concluído** — implementado e validado.
- 🚧 **Em andamento** — começado.
- ⬜ **Pendente** — ainda não iniciado.

---

## Estado atual do desenvolvimento (snapshot 2026-07-06)

### O que já está pronto (✅)

- **Crates de Base/Fundação** — `contracts` (schemas proto/fbs, `Envelope` com
  `auth_*`, `flow_permissions` e `user_agent`, stubs gerados), `transport` (codec
  FlatBuffers/gRPC, canais UDS/TCP/WS, barramento `transport::bus`), `error_core`
  (erros serializáveis `ErrorEnvelope` com códigos estáveis) e `observability`
  (tracing OTLP, `traceparent` W3C, auditoria via Streams com `AuditContext` +
  `user_agent`).
- **Serviços de Dados (data_*)** — `data_postgres`, `data_redis`, `data_storage`
  (Cloudflare R2) e `data_whatsapp` (12 rotas Evolution Go), todos em **Ports &
  Adapters**. `data_postgres` com outbox relay, métricas de backlog e
  **`TenantConfigCache` plugado com invalidação via Redis Pub/Sub**
  (`core:settings:invalidate`) — configuração reflete **sem restart**.
- **Ingestão endurecida (F3)** — `webhook_ingress` **valida `apikey`/token de
  instância e aplica whitelist** de remetentes antes de publicar no bus;
  idempotência preservada; Evolution Go em projeto compose próprio.
- **Orquestração do `worker` (F4)** — resolução **contato → atendimento aberto**
  (`ResolveAtendimentoParaContato` — fim do `atendimento_id` fixo), **debounce por
  contato** (lock Redis), **política de ticket/Kanban** (posicionamento na etapa +
  auditoria `ticket.transicionado`/`kanban.movido`), **barreira de bot** (resposta
  temporária sem LLM) e **envio outbound** via `data_whatsapp::SendWhatsappMessage`.
- **Realtime (F6.2)** — `RealtimeManager` com **fan-out por tenant via Redis
  Pub/Sub** (`tenant:{id}:events`) + RPC `StreamAtendimentos` (gRPC Server
  Streaming) servindo o chat em tempo real; eventos de Kanban também publicados.
- **Autenticação/autorização (F6.1/6.3)** — `Login`/`Refresh`/`Logout` com JWT
  HS256, rotação de refresh por família + reuse-detection, rate limiting e
  blocklist; **RBAC por escopo ponta-a-ponta** (interceptor → escopos →
  `RequestContext` → RLS) e **RBAC fino por fluxo** (`flow_permissions` no
  `Envelope`, resolvido por RPC ao `data_postgres` + cache TTL 30s no `data_redis`,
  filtro na fila e barreira no mover-etapa, evento `autorizacao.negada` com
  `user_agent`/`ip`). Convites e comandos de leitura expostos na borda autenticada.
- **Painel admin do superusuário (F2 — redesenhado)** — decisão de arquitetura:
  o painel fala **somente com o `runtime_api`** (fachada `AdminFacade` gRPC-Web
  com **18 rotas admin**: tenants, planos, assinaturas, pagamentos, auditoria,
  saúde, dashboard, CSV export, feature flags, core settings, evolution, tenant
  config), **não** com o `control_plane` — que permanece como CLI de bootstrap
  (`create-superuser`/`delete-superuser`). Telas do `admin_module` **endurecidas**
  (estados de erro com retry, paginação, encadeamento lista→detalhe→pagamentos→
  auditoria via `go_router`).
- **Telas operacionais Flutter (WS-6)** — `operacional_module` novo
  (data/domain/presentation): **fila por departamento**, **Kanban drag-and-drop
  nativo** (`Draggable`/`DragTarget`, sem dep externa), **chat lateral streaming**
  (reconexão com backoff exponencial + jitter, badge de conexão, zero PII em log)
  e **envio outbound**. Registrado no `smart-core-admin` via `installModules`.
- **Deploy web do admin** — `smart-core-admin` (Flutter Web) buildado no runner
  self-hosted e servido sob **`/v2/admin`** em dev e prod (**same-origin** com o
  gRPC-Web, roteado pelo Caddy), com rollback. Ver plano `deploy-admin-web`.
- **CI/CD + servidor (F-devops — completa)** — `ci.yml`, `deploy-dev.yml`,
  `deploy-prod.yml`, `pr-to-main.yml`; runner self-hosted no Hostinger; deploy
  automático de `dev`, tags `v*` em prod; **stack Grafana LGTM**
  (`docker/observability/compose.yml`: OTel Collector, Loki, Tempo, Prometheus,
  Grafana, Promtail) — devops-4 entregue. Docker reestruturado em
  `docker/{dev,prod,edge,evolution,observability,server,web}` (migração
  full-docker).
- **Qualidade/observabilidade transversal** — **teste e2e de cadeia de trace**
  (webhook → bus → worker → RPC → `audit_log` com o mesmo `trace_id` W3C, sem
  vazamento de PII); métricas de pool/outbox (`smartcore_outbox_backlog` etc.);
  `user_agent` persistido nos eventos críticos de auditoria (doc 08 §4.2).

### O que está pendente (⬜) — visão executiva

- **`ia_engine` (F5)** — serviço Python (gRPC/FlatBuffers) — pasta ainda ausente.
  **Maior bloco restante.** Decisão registrada: worker ↔ ia_engine via **gRPC**
  (não FFI); `FeaturesCompose` da v1 é reaproveitada.
- **Scheduler do `worker` (F4.3b)** — timeout de feedback + purga de mídias
  (substitui o Celery beat da v1). Única etapa da F4 não entregue.
- **Painel do tenant (novo)** — convites (`CreateInvite`/`AcceptInvite` **já
  expostos na borda**; telas parqueadas por decisão do dono — são fluxo de **admin
  de tenant**, não do painel superusuário), gestão de usuários e de
  `flow_permissions` pelo admin do tenant.
- **Endurecimento de produção (F9)** — enforcement de billing/quotas, retenção de
  mídia (lifecycle R2/purga), segurança/carga (incl. **role Postgres dedicada
  não-superuser** no ambiente — hoje `smartcore_app` é bootstrap superuser e o RLS
  não é exercitado de verdade em dev), dashboards/alertas Grafana com dados reais.
- **Local engine `local_engine` (FFI)** — F8 — e **paridade Web completa** — F10
  (o admin já roda na web; falta o app do tenant/operacional standalone, se mantido).

### Inventário de crates/apps × status

| Componente | Tipo | Status | Plano/Nota |
|---|---|---|---|
| `infrastructure_postgres` | crate infra | ✅ | repositórios SQLx, criptografia, migrations 0001–0013 (`user_agent` na 0013), RLS |
| `infrastructure_redis` | crate infra | ✅ | conexões Redis, cache, tokens, locks |
| `infrastructure_storage` | crate infra | ✅ | cliente R2 real (`aws-sdk-s3`), presign real, layout `media/{tenant}/...` |
| `infrastructure_evolution` | crate infra | ✅ | cliente HTTP Evolution Go + `EvolutionProvider` |
| `infrastructure_messaging` | crate infra | ✅ | abstração de provedor de mensageria + `ProviderRegistry` (plano 13) |
| `contracts` | crate base | ✅ | schemas proto/fbs, `Envelope` (campos 1–15) e tipos gerados |
| `transport` | crate base | ✅ | canais UDS/TCP/WS, codecs e barramento |
| `observability` | crate base | ✅ | tracing OTLP + auditoria via bus + `AuditContext`/`user_agent` |
| `error_core` | crate base | ✅ | taxonomia e erros com `ErrorEnvelope` serializável (códigos estáveis na borda) |
| `test_support` | crate base | ✅ | suporte a testes (túnel SSH, fixtures) |
| `application` | crate aplicação | ✅ | casos de uso de auth + montagem de envelopes; regras de domínio residuais no `worker` |
| `local_engine` | crate (FFI) | ⬜ | F8; motor local embarcado |
| `data_postgres` | app | ✅ | RPC Postgres + outbox relay + `TenantConfigCache` com invalidação Pub/Sub; Ports & Adapters |
| `data_redis` | app | ✅ | RPC Redis (tokens, cache, locks, rate limiter); Ports & Adapters |
| `data_storage` | app | ✅ | RPC (PutFile/GetFile/PresignFile) + consumer de purga; backend R2 real |
| `data_whatsapp` | app | ✅ | RPC de instâncias/mensagens WhatsApp via `infrastructure_evolution` (12 rotas) |
| `webhook_ingress` | app | ✅ | webhook autenticado (`apikey`/token) + whitelist + normalização + publish no bus |
| `control_plane` | app | ✅ (escopo revisado) | CLI de bootstrap de superusuário; **CRUD admin migrou para o `runtime_api`** (decisão de arquitetura) |
| `worker` | app | ✅ (exceto scheduler) | orquestração completa: resolução, debounce, ticket/Kanban, bot, outbound; **falta F4.3b** |
| `runtime_api` | app | ✅ | auth + realtime + 18 rotas admin + rotas operacionais (fila/thread/mover etapa/outbound) + RBAC fino |
| `clients/apps/smart-core-admin` | app Flutter | ✅ | login + painel admin + telas operacionais; **deployado na web sob `/v2/admin`** |
| `clients/modulos/login_module` | módulo Flutter | ✅ | login/logout/refresh via gRPC + guarda de sessão |
| `clients/modulos/admin_module` | módulo Flutter | ✅ | 18 rotas cobertas; estados de erro/paginação/encadeamento endurecidos |
| `clients/modulos/operacional_module` | módulo Flutter | ✅ | fila + Kanban DnD nativo + chat streaming + outbound |
| `clients/modulos/design_system_module` | módulo Flutter | ✅ | design system (tema dark) + componentes de Kanban |
| `clients/packages/api_client` | pacote Flutter | ✅ | cliente gRPC-Web único; stubs regerados (incl. `streamAtendimentos`) |
| `clients/packages/domain_models` | pacote Flutter | ✅ | DTOs do `.proto` |
| `evolution/` | stack Go | ✅ | Evolution Go 0.7.1 pinado, compose próprio no deploy |
| `ia_engine` | stack Python | ⬜ | F5; gRPC/FlatBuffers IA engine (pasta ausente) |

> **Removido do inventário:** `messaging_gateway` — o papel foi **absorvido** por
> `webhook_ingress` (ingestão) e `data_whatsapp` (envio); o app não existe mais.

> **Nota de arquitetura (camadas — esclarecimento importante):**
> `infrastructure_postgres` **não é** a camada de domínio. É a **ponte de
> persistência**: padroniza a comunicação com o banco (migrations, organização
> das tabelas e funções de **CRUD**), **sem regras de negócio**. Os seus módulos
> por domínio (`tenants/`, `clientes/`, `atendimentos/`, `operacional/`,
> `treinamento/`, `integracoes/`) são apenas **repositórios** (CRUD por tabela).
>
> As **regras de negócio** moram na camada **`application`** (casos de uso) e nos
> handlers orquestradores (`worker`), que chamam o CRUD via RPC aos serviços
> `data_*` (memória: **banco tem uma única porta — `data_postgres` via RPC**).
>
> Os crates **`domain_*` puros** (regras de domínio sem I/O) são **opcionais** e
> podem ser **extraídos** quando a complexidade justificar; até lá, a regra vive
> na `application`/orquestrador. A regra **"`domain_*` sem I/O"** vale para
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
   reescrita (já exercido: admin roda na web sem fork de código).
6. **Uma crate por sistema externo** — `infrastructure_postgres` (SQLx),
   `infrastructure_redis` (Redis), `infrastructure_storage` (S3/R2) são as
   **únicas** que falam com cada cliente.
7. **Transporte Flutter ↔ servidor é gRPC único** — unário (comandos/consultas) +
   **Server Streaming** (realtime). Sem WebSocket. Web via gRPC-Web (`tonic-web`).
   Toda tela fala só com o `api_client`.
8. **UI incremental, colada à feature** — cada feature de backend entrega, no
   mesmo ciclo, a tela que a valida.
9. **Observabilidade como DoD transversal** — tudo que cria/altera comportamento
   emite logs/spans estruturados com `tenant_id`/`traceparent`, registra auditoria
   (`<dominio>.<acao>`) quando toca estado sensível e **nunca** vaza segredo/PII
   (telefone mascarado, tokens só em storage seguro).

### Mapa de dependências entre fases (estado 2026-07-06)

```
F0 Fundação ──► F1 Banco+RLS+Storage ──► Bootstrap CLI superuser
   (✅)             (✅)                    (✅)
                       │
                       ▼
               F-devops ✅ COMPLETA (incl. Grafana LGTM — devops-4)
                       │
                       ▼
               F6.1/6.3 Auth + JWT + rotação + RBAC (escopo e fluxo) ✅
                       │
                       ▼
               F2 Painel admin superusuário ✅ (via runtime_api, 18 rotas + telas)
                       │
                       ├──► F3 Ingestão WhatsApp/Evolution ✅ (auth+whitelist)
                       │            │
                       │            ▼
                       └──► F4 Worker + Domínio ✅ (falta só F4.3b scheduler)
                                  │
                                  ▼
                          F6 Runtime API + Realtime ✅ ──► UI operacional ✅
                          (fila/Kanban/chat streaming)     (MVP PONTA-A-PONTA ✅)
                                  │
                                  ▼
                    ┌─────────────┴──────────────┐
                    ▼                            ▼
          F5 ia_engine (gRPC Python) ⬜   Painel do tenant ⬜
          (próximo grande bloco)          (convites, usuários, flow_permissions)
                    │                            │
                    └─────────────┬──────────────┘
                                  ▼
                          F9 Endurecimento produção ⬜
                          (billing/quotas, retenção mídia, RLS real, carga)
                                  │
                                  ▼
                          F7 consolidação desktop ⬜ ── F8 Local Engine (FFI) ⬜
                                  │
                                  ▼
                          F10 paridade Web completa 🚧 (admin já no ar)
```

> **Marco alcançado — MVP funcional ponta-a-ponta (2026-07):** uma mensagem de
> WhatsApp entra pelo `webhook_ingress` (autenticada + whitelist), vira
> atendimento no `worker` (resolução/debounce/ticket/Kanban/bot), aparece na fila
> e no Kanban do painel, o chat recebe em tempo real via `StreamAtendimentos` e a
> resposta sai pelo `data_whatsapp` — tudo auditado e rastreável por um único
> `trace_id` (validado pelo teste e2e WS-0.3).

---

## Próximos passos (a partir de 2026-07-06) — divididos em fases

> Backlog pós-MVP, dividido em **fases N1–N5** por dependência e valor. Cada fase
> é um ciclo PREVC próprio (planejar via `/plan-restructuring` → canonizar em
> `.context/plans/`). O DoD transversal de observabilidade/auditoria e
> SOLID/Ports & Adapters (princípios 1–9) vale para todas.

### Fase N1 — Fechamento do ciclo + scheduler do worker (curto prazo)

**Objetivo:** consolidar o MVP em `dev`/produção e fechar a única lacuna da F4.

| # | Entregável | Ref. | Notas |
|---|---|---|---|
| N1.1 | Merge de `feature/mvp-telas-e-endurecimento` → `dev` e validação no ambiente dev (deploy automático) | — | Branch já passou pelo gate `prevc-final-review` |
| N1.2 | **Scheduler do `worker`** (F4.3b): timeout de feedback + purga de mídias via `data_storage::remover_objeto`; tarefas temporais resilientes no Redis | F4.3b | Substitui o Celery beat da v1; última etapa pendente da F4 |
| N1.3 | Consumer do outbox → disparo real do outbound do atendente (hoje `SendOutboundMessage` persiste; confirmar/fechar o elo outbox → `data_whatsapp`) | F4.4 | Verificar cobertura do `OutboxRelay` para mensagens de atendente |
| N1.4 | Dashboards Grafana com dados reais (uptime, latência gRPC, erros, backlog outbox) + alertas básicos | F9.1 | Stack LGTM já no ar; falta curadoria de dashboards |

**DoD:** MVP rodando em dev com scheduler ativo; mensagem de atendente sai de
ponta a ponta; dashboards refletindo tráfego real.

### Fase N2 — `ia_engine` (F5 — maior bloco)

**Objetivo:** camada de IA como serviço Python separado, consumido pelo `worker`
via **gRPC** (decisão registrada; `FeaturesCompose` da v1 reaproveitada).

| # | Entregável | Ref. |
|---|---|---|
| N2.1 | Skeleton (`uv`, `server.py` gRPC, `features/`, `llm/`, `contracts/`) + stubs gerados dos `.proto` nos dois lados | F5.1–5.2 |
| N2.2 | Porte da facade `FeaturesCompose` da v1 (núcleo de IA quase intacto) | F5.2b |
| N2.3 | Features de análise: transcribe / interpret / analyse / embeddings 1536 | F5.3 |
| N2.4 | Resposta + RAG (pgvector via `data_postgres` RPC, `query_compose`) + sentimento | F5.4 |
| N2.5 | Integração `worker` → IA: timeout + retry/backoff + **degradação graciosa** (bot barrier já cobre a ausência); resumo/análise + `MediaPointer` via RPC; binário no `data_storage` (R2) | F5.5 |
| N2.6 | UI: exibição da resposta da IA e do resumo de mídia no chat (trilha de UI) | F5/UI |

**DoD:** mensagem com mídia gera transcrição/resumo; resposta automática do bot
passa a ser gerada pela IA com RAG; falha da IA degrada para a resposta
temporária atual sem travar o fluxo. Observabilidade: `traceparent` cruza o
processo Python; nenhum conteúdo de mensagem em log.

### Fase N3 — Painel do tenant (convites, usuários e permissões)

**Objetivo:** dar autonomia ao **admin de tenant** (persona distinta do
superusuário — ver memória `convites-tenant-nao-e-painel-superuser`).

| # | Entregável | Ref. |
|---|---|---|
| N3.1 | Telas de **convite** (gerar/listar/revogar) e **aceite de convite** + Register — as rotas `CreateInvite`/`AcceptInvite` já existem na borda autenticada | F6.1 (borda ✅) |
| N3.2 | Gestão de usuários do tenant: papéis, escopos e **`flow_permissions`** (UI que alimenta o RBAC fino já implementado) | WS-5a (backend ✅) |
| N3.3 | Tela de configurações do tenant (persona/prompts/providers) para o admin do tenant — reusa `TenantConfig` + invalidação de cache já prontos | F9/F2 |
| N3.4 | Decidir empacotamento: módulo novo no `smart-core-admin` com RBAC de UI, ou app dedicado do tenant | arquitetura |

**DoD:** admin de tenant convida atendente, define fluxos permitidos, e o
atendente logado vê apenas os fluxos concedidos (validando o RBAC fino de ponta
a ponta pela UI). Eventos `tenant_user.role_change` auditados com `user_agent`.

### Fase N4 — Endurecimento de produção (F9)

**Objetivo:** prontidão para operação comercial.

| # | Entregável | Ref. |
|---|---|---|
| N4.1 | **Role Postgres dedicada não-superuser** nos ambientes (hoje `smartcore_app` é bootstrap superuser e o RLS não é exercitado em dev — pendência de ambiente documentada); revalidar suíte de isolamento | F9.4 |
| N4.2 | Billing/usage: medição de uso, enforcement de `plan`/`subscription`, bloqueio por inadimplência, quotas de instância/storage por tenant (repos e telas admin já existem; falta o enforcement no caminho quente) | F9.2 |
| N4.3 | Retenção de mídia: TTL/lifecycle no R2 (≤ 30 dias) ou purga via scheduler (N1.2); o resumo permanece | F9.3 |
| N4.4 | Segurança e carga: auditoria RLS, testes de vazamento, rate limiting amplo (além do login), testes de rajada no webhook/bus | F9.4 |

**DoD:** tenant inadimplente bloqueado; mídia expira; testes de vazamento/carga
verdes com a role não-superuser; rastreio webhook→resposta correlacionado por
tenant no Grafana.

### Fase N5 — Consolidação de clientes + offline (F7/F8/F10)

**Objetivo:** pós-estabilização — só entra após N1–N4 estáveis em produção.

| # | Entregável | Ref. |
|---|---|---|
| N5.1 | Consolidação do app (F7): navegação/estados/acessibilidade revisados, empacotamento Windows (`flutter build windows --release`) | F7 |
| N5.2 | `local_engine` FFI (F8): dual-target, índice SQLite, cache de mídia por hash com URL pré-assinada, `DataSource: LocalEngineFFI`, fila offline + sync | F8 |
| N5.3 | Paridade Web completa (F10): o admin já roda em `/v2/admin`; avaliar app operacional web standalone do tenant + CORS de mídia no bucket | F10 |

**DoD:** app desktop empacotado; modo offline funcional; paridade web validada.

### Sequenciamento e riscos

- **Ordem recomendada:** N1 → N2 ‖ N3 (paralelizáveis; N2 é backend/Python, N3 é
  Flutter/borda já pronta) → N4 → N5.
- **N2 (`ia_engine`) é a maior incógnita de esforço** (serviço Python novo);
  pode exigir ciclo extra. Não bloqueia N3/N4.
- **N4.1 (role não-superuser)** deve entrar cedo se possível — sem ela, os testes
  de isolamento RLS em dev não provam nada (falha conhecida de ambiente).
- **Túnel SSH / ambiente remoto** — testes de integração dependem do
  `test_support`; manter o ambiente dev estável é pré-condição de todas as fases.

---

## Trilha de UI incremental (transversal — decisão D8)

A UI **não** é uma fase única e tardia: cada feature de backend entrega a tela
que a valida, consumindo o `api_client`. **Estado atual: a trilha funcionou** —
login (F6.5), painel admin (F2) e fila/Kanban/chat (F4/F6.2) nasceram coladas às
features e já estão entregues.

| Feature de backend | Fase | Tela | Status |
|---|---|---|---|
| **Bootstrap + auth** | F6 | Shell + design system + **login** + guarda de sessão | ✅ |
| Painel admin (superusuário) | F2 | Tenants, planos/assinatura, pagamentos, auditoria, flags, dashboard, configs | ✅ (endurecido) |
| Worker + Kanban (sem IA) | F4 | Fila por departamento + **Kanban DnD** + **chat lateral** (Server Streaming) + outbound | ✅ |
| `ia_engine` | F5/N2 | Exibição da resposta da IA e resumo de mídia no chat | ⬜ |
| Painel do tenant | N3 | Convites, usuários, `flow_permissions`, config do tenant | ⬜ |
| Local Engine (FFI) | F8/N5 | Estados offline/cache (`DataSource: LocalEngineFFI`) | ⬜ |
| Endurecimento/billing | F9/N4 | Uso/billing do tenant | ⬜ |

**Regras da trilha (inalteradas):**
- A UI sempre fala com o `api_client` (gRPC) — nunca com infraestrutura nem FFI
  direto fora do `local_engine_ffi`.
- Componentes visuais reutilizáveis vão para o `design_system_module`; telas
  específicas ficam no módulo da feature.
- `DataSource` abstrato desde a primeira tela (modo `RemoteOnly`).
- **DoD de cada tela:** `flutter analyze` limpo (via `.\infra\test-flutter.ps1`)
  + a tela exercita o fluxo real contra o `runtime_api` (não mock) + comentários
  em pt-br.

---

## Fase 0 — Fundação do monorepo e infra local — ✅

**Objetivo:** esqueleto compilável de todas as stacks + ambiente local de dados.

- **0.1 Esqueleto de diretórios** — ✅ (`server/`, `docker/`, `infra/`, `clients/`,
  `evolution/`, `smart-agent-config/`; falta só `ia_engine/`, criado na N2).
- **0.2 Cargo workspace** — ✅.
- **0.3 Infra local de dados** — ✅ (reestruturada: composes por contexto em
  `docker/{dev,prod,edge,evolution,observability,server,web}`).
- **0.4 crate `observability`** — ✅ (tracing OTLP + auditoria via Streams +
  `AuditContext`).
- **0.5 crate `error_core`** — ✅ (códigos estáveis usados pela borda, ex.
  `AUTH_INSUFFICIENT_SCOPE`).
- **0.6 crate `contracts`** — ✅ (Envelope campos 1–15; proto → fbs no build).
- **0.7 crate `transport`** — ✅ (UDS/TCP/WS + bus; em Windows usar TCP —
  memória `transport-windows-tcp`).

---

## Fase 1 — Banco unificado multi-tenant + RLS — ✅

**Entregue na crate `infrastructure_postgres`** — ver
[03-infraestrutura-postgres.md](./03-infraestrutura-postgres.md).

- **1.1 Fundação** (pool, migrations, `run_in_tenant_transaction`) — ✅.
- **1.2 Tenant context + RLS** (`RequestContext` + policies fail-closed) — ✅,
  agora com `has_flow_permission`/`exigir_fluxo` (RBAC fino).
- **1.3 Migrations do schema** — ✅ (0002–0013; `audit_log` 0010 + `user_agent`
  0013; outbox 0011).
- **1.4 Testes de isolamento** — ✅ (*revalidar a cada nova tabela*; atenção: em
  dev a role é bootstrap superuser → N4.1).
- **1.5 `infrastructure_storage` (R2)** — ✅.
- **1.6 Microsserviços de dados (`data_*`)** — ✅.

---

## Fase devops — CI/CD, Ambientes e Servidor — ✅ (completa)

- **devops-1 Provisionamento Hostinger** — ✅.
- **devops-2 Systemd e Caddy** — ✅ (Caddy também serve o admin web em `/v2/admin`).
- **devops-3 GitHub Actions + self-hosted runner** — ✅ (CI + deploy dev/prod +
  pr-to-main; runner com Flutter SDK para o build web).
- **devops-4 Observabilidade (Grafana LGTM)** — ✅ (`docker/observability/compose.yml`;
  falta **curadoria de dashboards/alertas** → N1.4).

**Plano detalhado:** [10-plano-cicd-devops.md](./10-plano-cicd-devops.md).

---

## Fase 2 — Painel Admin do Superusuário — ✅ (redesenhada)

**Decisão de arquitetura (substitui o desenho original):** o painel do
superusuário fala **somente com o `runtime_api`** (fachada `AdminFacade`
gRPC-Web) — o `control_plane` **não** ganhou API gRPC de administração e
permanece como CLI de bootstrap. Ver
[11-painel-admin-superusuario.md](./11-painel-admin-superusuario.md).

- **2.1 Regras de tenant/plano/quota** — ✅ persistência/CRUD; **enforcement de
  quota/billing no caminho quente → N4.2**.
- **2.2 Cifragem de credenciais** — ✅ (`CipherManager`, AES-256-GCM).
- **2.2b Resolução de configuração em runtime** — ✅ (`TenantConfigCache` plugado
  no `data_postgres` + **invalidação via Redis Pub/Sub** `core:settings:invalidate`;
  granular por tenant, global para CoreSettings; reflete **sem restart**).
- **2.3 CRUD administrativo** — ✅ via `runtime_api` (18 rotas: ListTenants,
  GetTenant, UpdateTenant, SetTenantActive, GenerateAccessCode, ListPlans,
  CreatePlan, UpdatePlan, ListSubscriptions, RegisterPayment, ListPayments,
  QueryAuditLog, GetServiceHealth, GetDashboardSummary, ExportTenantsCsv,
  ListFeatureFlags, SetFeatureFlag, SetFeatureFlagOverride).
- **2.4 `infrastructure_evolution` (provisionamento)** — ✅.
- **2.5 UI: telas de administração** — ✅ (`admin_module` endurecido: estados de
  erro com retry, paginação, encadeamento lista→detalhe→editar→ativar,
  pagamentos e auditoria por tenant).
- **Fora do escopo desta fase:** convites/gestão de usuários do **tenant** —
  persona de admin de tenant → **N3**.

---

## Fase 3 — Ingestão WhatsApp + Evolution multi-instância — ✅

- **3.1 `evolution/` (infra do gateway)** — ✅ (Evolution Go 0.7.1, compose
  próprio, deploy fundacional no CI).
- **3.2 Normalização** — ✅ (mapeamento de tipos de mídia, `messages.upsert` →
  evento interno, reply/`stanzaId`, em `domain_whatsapp`/`infrastructure_messaging`).
- **3.3 Barramento de eventos (`transport::bus`)** — ✅.
- **3.4 `webhook_ingress`** — ✅ **endurecido**: valida `apikey`/token de
  instância, aplica **whitelist** de remetentes (rejeição auditada
  `not_whitelisted`), persiste bruto via RPC e publica no bus. Sem regra pesada.

---

## Fase 4 — Worker + domínio (sem IA) — ✅ (exceto 4.3b)

- **4.1 Regras de domínio** — ✅ (ciclo de vida do atendimento via
  `ResolveAtendimentoParaContato` + política de ticket no `data_postgres`).
- **4.2 Casos de uso** — ✅ (resolução, debounce, política de ticket, barreira de
  bot implementados no orquestrador; extração para `application`/`domain_*`
  opcional futura).
- **4.3 Binário `worker`** — ✅ (consome o bus, resolve contato→atendimento,
  debounce por lock Redis, aplica ticket/Kanban com auditoria, cliente RPC
  reaproveitado no estado).
- **4.3b Scheduler do `worker`** — ⬜ → **N1.2** (timeout de feedback + purga de
  mídias via `data_storage`).
- **4.4 Envio outbound** — ✅ (`worker` → `data_whatsapp::SendWhatsappMessage`;
  mensagem de atendente persiste via outbox — confirmar elo do relay em N1.3).
- **4.5 `BotRulesEngine` (sem LLM)** — ✅ (barreira: `bot_pode_atender` + ausência
  de atendente humano → resposta temporária; será substituída pela IA na N2).
- **4.6 UI: fila + Kanban + chat lateral** — ✅ (`operacional_module`: fila por
  departamento, Kanban **DnD nativo** — decisão registrada, sem `appflowy_board` —,
  chat streaming com reconexão backoff+jitter, envio outbound).

---

## Fase 5 — `ia_engine` (Python, serviço RPC) — ⬜ → **Fase N2**

**Objetivo:** mídia→texto, intents/entidades, RAG, resposta e sentimento, como
serviço Python exposto por **gRPC** (decisão registrada — não FFI) e consumido
pelo `worker` com timeout/retry e degradação graciosa.

- **5.1** skeleton (`uv`, `server.py` RPC, `features/`, `llm/`, `contracts/`).
- **5.2** contratos e stubs gerados dos schemas `.proto` (nos dois lados).
- **5.2b** portar a facade `FeaturesCompose` da v1 (núcleo de IA quase intacto).
- **5.3** features de análise (transcribe/interpret/analyse/embeddings 1536).
- **5.4** resposta + RAG (pgvector + `query_compose` via `data_postgres` RPC) + sentimento.
- **5.5** integração worker→IA + mídia: grava `resumo`/`analise` + **ponteiro**
  (`MediaPointer`) via `data_postgres` RPC; binário no `data_storage` (R2).

Detalhamento operacional na **Fase N2** (próximos passos).

---

## Fase 6 — Runtime API + Realtime — ✅ (núcleo do MVP entregue)

- **6.1 Binário `runtime_api`** — ✅: auth (Login/Refresh/Logout), convites e
  comandos de leitura na borda autenticada, rotas operacionais
  (ListAtendimentos/GetThread/MoveAtendimentoEtapa/SendOutboundMessage) e 18
  rotas admin. *Telas de Register/aceite de convite → N3.*
- **6.2 Realtime (gRPC Server Streaming)** — ✅: `RealtimeManager` com fan-out
  por tenant via **Redis Pub/Sub** (`tenant:{id}:events`), `StreamAtendimentos`
  autenticado, `Lagged` tratado; consumido pelo chat com reconexão.
- **6.3 Autenticação/autorização** — ✅: JWT HS256 + rotação por família +
  reuse-detection + blocklist + rate limiting; **defesa em 3 camadas**
  (interceptor → escopos → RLS) ponta-a-ponta; **RBAC fino por fluxo**
  (`flow_permissions` no Envelope, RPC + cache TTL 30s, `exigir_fluxo`,
  `autorizacao.negada` auditado com `user_agent`/`ip`).
- **6.4 Contrato cliente estável** — ✅: `tonic-web` habilitado; stubs Dart
  regerados (incl. `streamAtendimentos`); evolução **aditiva** do Envelope
  comprovada (campos 14/15 sem quebra).
- **6.5 UI: bootstrap + telas de auth** — ✅ (login_module completo + guarda de
  sessão + secure storage).

---

## Fase 7 — Consolidação do app (RemoteOnly) — 🚧 → **Fase N5.1**

As telas nasceram coladas às features (F6.5, F2, F4.6); a F7 é **consolidação**:
navegação, estados de carga/erro/vazio, acessibilidade, consistência visual e
**empacotamento** (`flutter build windows --release`). O deploy **web** do app já
está resolvido (Caddy `/v2/admin`, same-origin). Pendências concentradas em N5.1.

---

## Fase 8 — Local Engine (FFI) + mídia local — ⬜ → **Fase N5.2**

- **8.1** `local_engine` dual-target (lib + `cdylib`/`staticlib`).
- **8.2** índice SQLite + cache de dados.
- **8.3** cache de mídia em disco (hash + URL pré-assinada do R2).
- **8.4** `local_engine_ffi` + `DataSource: LocalEngineFFI`.
- **8.5** fila offline + sincronização (last-write-wins + versionamento).

---

## Fase 9 — Endurecimento, billing e produção — 🚧 → **Fase N4** (+ N1.4)

- **9.1 Observabilidade completa** — 🚧: stack LGTM no ar e cadeia de trace
  **validada por teste e2e** (webhook → `audit_log` com o mesmo `trace_id`);
  faltam dashboards/alertas curados (N1.4).
- **9.2 Billing/usage e quotas** — ⬜ → N4.2 (enforcement no caminho quente).
- **9.3 Retenção de mídia** — ⬜ → N4.3 (lifecycle R2 ou purga via scheduler N1.2).
- **9.4 Segurança e carga** — ⬜ → N4.1/N4.4 (**role não-superuser** nos
  ambientes, testes de vazamento/rajada, rate limiting amplo).
- **9.5 CI/CD + deploy** — ✅ (entregue na fase devops; rollback operante).

---

## Fase 10 — Port para Web — 🚧 (parcial) → **Fase N5.3**

- **10.1** `flutter_web` RemoteOnly — 🚧: o **admin já roda na web** em
  `/v2/admin` (dev+prod, same-origin, gRPC-Web), incluindo os módulos
  operacionais. Falta decidir/entregar o app web standalone do **tenant**.
- **10.2** paridade e mídia na Web (URL pré-assinada do R2; **CORS** no bucket —
  ver [08 §7.5](./08-infraestrutura-storage.md)) — ⬜.

---

## Apêndice A — Checklist transversal por PR

- [ ] `tenant_id` em toda query nova + policy RLS coberta
      (`run_in_tenant_transaction`).
- [ ] `domain_*` (quando existir) sem `infrastructure_*`.
- [ ] Eventos/DTOs novos em `contracts` com `TenantEnvelope` e versão
      (**evolução aditiva** — nunca renumerar campos).
- [ ] Chaves de storage no layout `media/{tenant}/{instance}/{type}/{hash}`.
- [ ] Span com `tenant_id`/`traceparent` no caminho novo; `traceparent` propagado
      ao próximo salto.
- [ ] ≥ 1 evento de auditoria por ação sensível (convenção `<dominio>.<acao>`)
      com `user_id`/`ip`/`user_agent` — ou declaração explícita "sem evento".
- [ ] Nenhum segredo/PII em log ou auditoria (telefone mascarado; tokens só em
      secure storage).
- [ ] Comentários em pt-br; identificadores em inglês.
- [ ] Sem segredos no código (`.env`/cifragem; `.env.deploy` git-ignored).
- [ ] Testes via `.\infra\test-local.ps1` / `.\infra\test-flutter.ps1` + lint
      da stack passando.
- [ ] Idempotência preservada onde há `message_id`/`stanzaId`/`hash`.

## Apêndice B — Rastreabilidade v1 → componentes v2 (estado real)

| Regra v1 (referência) | Onde vive na v2 | Status |
|---|---|---|
| Schema multi-tenant + RLS | `infrastructure_postgres` (migrations 0001–0013) | ✅ |
| Cifragem de credenciais (Fernet) | `crypto.rs` (`CipherManager`, AES-256-GCM) | ✅ |
| `TenantConfig` (persona/prompts/providers) | `tenants/config.rs` + `TenantConfigCache` com invalidação Pub/Sub | ✅ |
| `Tenant`/`Plan`/`Subscription`/`TenantUser` | `tenants/`, `plans`, `users` + 18 rotas admin + telas | ✅ |
| `Documento`/`QueryCompose` (pgvector 1536) | `treinamento/` + migration 0007 | ✅ (persist.; RAG → N2) |
| `AppInstance`/Evolution | `operacional/app_instances.rs` + `integracoes/evolution.rs` | ✅ |
| Atendimento/Mensagem/Movimento | `atendimentos/` + fila/Kanban/chat na UI | ✅ |
| Refresh/blocklist/cache de permissões | `infrastructure_redis` (auth_tokens, cache, flow_permissions TTL 30s) | ✅ |
| Event bus (substitui fila Celery) | `transport::bus` (Redis Streams) | ✅ |
| Mídia (binário transitório) | `infrastructure_storage` (Cloudflare R2) | ✅ (retenção → N4.3) |
| Auth/JWT/sessão + `runtime_api` | `application` + `apps/runtime_api` | ✅ |
| RBAC (`role`+`module_permissions`+`flow_permissions`) | escopos + `flow_permissions` fim-a-fim (WS-5a) | ✅ (UI de gestão → N3) |
| `AttendanceOrchestrator` (orquestração) | `worker` (resolução/debounce/ticket/Kanban/bot) | ✅ |
| Celery: `process_contact_response_task` | `worker` consumindo Streams | ✅ |
| Celery: feedback/purga de mídia | scheduler do `worker` (F4.3b) | ⬜ → N1.2 |
| `message_buffer` (debounce) | lock de debounce no Redis (worker) | ✅ |
| `FeaturesCompose` (IA pura) | `ia_engine` (gRPC) | ⬜ → N2 |

## Apêndice C — Planos relacionados

- [03-infraestrutura-postgres.md](./03-infraestrutura-postgres.md) — Postgres + RLS (✅).
- [04-infraestrutura-redis.md](./04-infraestrutura-redis.md) — Redis (✅).
- [05-observabilidade.md](./05-observabilidade.md) — logs/métricas/traces + LGTM.
- [06-tratamento-de-erros.md](./06-tratamento-de-erros.md) — crate `error_core`.
- [07-crate-contracts.md](./07-crate-contracts.md) — contratos/eventos/envelope.
- [08-infraestrutura-storage.md](./08-infraestrutura-storage.md) — storage Cloudflare R2.
- [09-comunicacao-e-autenticacao.md](./09-comunicacao-e-autenticacao.md) — transporte + auth.
- [10-plano-cicd-devops.md](./10-plano-cicd-devops.md) — plano-mãe CI/CD + DevOps.
- [11-painel-admin-superusuario.md](./11-painel-admin-superusuario.md) — painel admin
  (**nota:** implementado via `runtime_api`, não `control_plane`).
- [15-plano-finalizacao-em-andamento.md](./15-plano-finalizacao-em-andamento.md)
  — plano de execução do fechamento do MVP (**concluído**; ciclos arquivados em
  `.context/plans/archive/finalizacao-mvp-operacional/` e
  `.context/plans/archive/mvp-telas-e-endurecimento/`).

### Planos das próximas fases (backlog pós-MVP N1–N5)

- [16-fase-N1-fechamento-mvp-e-scheduler.md](./16-fase-N1-fechamento-mvp-e-scheduler.md)
  — **N1:** merge/validação do MVP + scheduler do worker (F4.3b) + elo outbound + dashboards.
- [17-fase-N2-ia-engine.md](./17-fase-N2-ia-engine.md)
  — **N2:** `ia_engine` Python via gRPC (F5) — análise, RAG pgvector, resposta, integração resiliente.
- [18-fase-N3-painel-do-tenant.md](./18-fase-N3-painel-do-tenant.md)
  — **N3:** painel do admin de tenant — convites, usuários e `flow_permissions` (UI do RBAC fino).
- [19-fase-N4-endurecimento-producao.md](./19-fase-N4-endurecimento-producao.md)
  — **N4:** role Postgres não-superuser, billing/quotas, retenção de mídia, segurança/carga (F9).
- [20-fase-N5-consolidacao-clientes-offline.md](./20-fase-N5-consolidacao-clientes-offline.md)
  — **N5:** consolidação desktop (F7), local engine FFI/offline (F8), paridade Web (F10).

---

*Documento de fases auditado contra o código real e os ciclos PREVC arquivados
(julho/2026). Retroalimentado a cada fase concluída.*
