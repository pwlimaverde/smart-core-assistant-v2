# Smart Core Assistant v2 — Fases de Desenvolvimento

> **Status:** Guia operacional de construção — **atualizado em 2026-08-08** após
> auditoria de código do legado (`old/`) contra a v2. Fecharam-se os oito ciclos
> **N1–N8** (arquivados em `.context/plans/archive/`), a fase **C1** (clients na
> `return_success_or_error` 3.0.1), o **cadastro self-service com vouchers**, a
> **configuração guiada** e as **oito etapas do plano de paridade**
> (`infra/PLANO_PARIDADE_V1.md`, 31/07 a 06/08).
>
> **Correção de rumo em relação à versão anterior deste documento:** a afirmação
> "o produto v2 está funcionalmente completo" **não se sustenta contra o código**.
> A auditoria de 2026-08-08 (duas passadas — superfícies e depois regras internas)
> encontrou **47 lacunas verificadas** de paridade com a v1: concentradas no
> **eixo da conversa** (mídia, leitura, busca, presença), na **IA não cabeada**
> (`Analyse` nunca chamado) e em **operação** (keepalive, roteamento por conexão).
> Nove têm código pronto no servidor **sem nenhum chamador**, e **cinco não são
> lacunas e sim defeitos** em caminho que já roda — mensagem de grupo virando
> atendimento, bot respondendo ao fragmento inicial da rajada, pesquisa de
> satisfação que expira sem ter sido pedida, `msg_fallback` sem efeito e evento
> de conexão sem consumidor.
> Inventário completo: [26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md).
> Cronograma derivado: **N8.5–N12** ao final do snapshot.
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

## Estado atual do desenvolvimento (snapshot 2026-08-08)

### O que já está pronto (✅)

> Acrescentado ao snapshot anterior (que ia até N5) — entregas de 2026-07-18 a
> 2026-08-06, auditadas no código:
>
> - **N6 — IA no fluxo vivo:** `Transcribe`/`InterpretMedia`/`Sentimento` ligados
>   ao pipeline real (URL de mídia no `NormalizedMessage`, análise persistida via
>   `AnexarAnaliseMidia`); `gerado_por_ia`/`resumo_midia` no proto e no chat;
>   fluxos de transferência resolvidos por tenant; sentimento persistido
>   (migration 0020).
> - **N7 — Endurecimento residual:** quota de storage (0021) e de departamentos;
>   idempotência do sync (`action_id` + `applied_actions`) e dead-letter de
>   outbound (0022); rate-limit centralizado via `RegisterRateLimitAttempt`;
>   sync offline com gatilho por conectividade e timer.
> - **N8 — Migração e cutover (código):** ETL `infra/migracao-v1/` idempotente
>   com dry-run/delta e conciliação (75 testes); Caddy de produção com
>   `/v2/admin` e `/v2/tenant`; `api_key` de instância cifrada (0023); runbooks
>   de cutover e de rollout do enforce. **A execução real continua pendente.**
> - **Config de IA pelo Rust:** cascata `TenantConfig > CoreSettings` publicada no
>   Redis (`tenant:config:<id>`) e consumida pelo `ia_engine`; chave de API e
>   prompt saíram do payload gRPC. Corrigiu dois defeitos silenciosos — persona
>   do bot e mensagem de transferência do tenant não valiam nada.
> - **Fase C1:** clients Flutter reconstruídos sobre `return_success_or_error`
>   3.0.1 (padrão RSOE em todos os módulos).
> - **Cadastro self-service + vouchers:** `OnboardingService` (5 RPCs públicos),
>   `tenants_voucher`/`tenants_voucher_redemption` (0027), pagamento como porta
>   plugável, e **configuração guiada** retomável (conta criada → operando).
> - **Robustez do cliente:** `DialogoComCampos` no design system (posse e descarte
>   dos controllers), erro dentro da janela em vez de SnackBar atrás do barrier,
>   vazamentos de controller fechados.
> - **Robustez da stack:** `watchdog` (reinicia serviço travado e publica
>   `smartcore_service_up` de fora) + binário `healthcheck` para os oito serviços.
> - **Paridade v1 — etapas 1 a 8** (`infra/PLANO_PARIDADE_V1.md`): conexões de
>   WhatsApp, equipe (departamentos e atendentes), painel do tenant, contatos,
>   fluxos e etapas com CRUD, Kanban próprio com as regras de transição
>   conferidas contra a v1 (incluindo saudação ao assumir), treinamento com
>   intents e teste de pergunta, e ficha do atendimento (etiquetas e notas).
>
> Números do inventário atual: **84 RPCs** no `AdminService`, **27 migrations**,
> **12 módulos Flutter**, **10 apps Rust** + **14 crates**, **6 RPCs** no
> `ia_engine`.

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

### O que está pendente (⬜) — visão executiva (snapshot 2026-08-08)

> As pendências abaixo saem da **auditoria de código** de 2026-08-08 (v1 `old/`
> × v2), não de changelog. Detalhe item a item, com evidência:
> [26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md).
> Consolidadas no cronograma **N9–N12** (seção "Próximos passos").
>
> 🔌 marca **capacidade instalada sem chamador** — o servidor já sabe fazer, e
> nenhuma rota ou tela alcança. São as pendências mais baratas de fechar.

- **⚠️ Defeitos em caminho que já roda (não são lacunas de tela).** A segunda
  passada da auditoria entrou nas regras internas do pipeline e achou cinco
  divergências de comportamento: **(1)** mensagem de **grupo vira atendimento
  individual** — `is_group` é preenchido no `NormalizedMessage` e nenhum
  consumidor o lê, enquanto a v1 descartava com fallback por JID `@g.us`;
  **(2)** o bot **responde ao fragmento inicial** — a v1 acumulava as mensagens
  do contato num buffer (`TIME_CACHE`, 5 s, configurável) e respondia ao texto
  compilado, a v2 usa `SET NX EX 2` onde a primeira mensagem ganha e as demais só
  são persistidas; **(3)** a **pesquisa de satisfação não existe** — `avaliacao`
  e `feedback` só aparecem em SELECT e o scheduler expira um feedback que nunca
  foi solicitado; **(4)** `msg_fallback`/`msg_sem_info` do tenant **não têm
  efeito** (o worker usa `BOT_TEXT_FALLBACK`, constante no código — mesma classe
  dos bugs de persona e mensagem de transferência corrigidos em 28/07);
  **(5)** o **estado da conexão só muda quando alguém consulta** — o evento
  `CONNECTION` é normalizado e publicado no barramento, e o worker consome apenas
  `message.received` e `whatsapp.message.status`. `PRESENCE` e `CONTACTS` também
  ficam sem consumidor.
- **Quatro colunas mortas em `oraculo_atendimento`** — lidas, nunca escritas:
  `prioridade` (sempre `normal`), `tags` (sempre `[]`), `contexto_conversa`
  (sempre `{}`) e `data_primeira_resposta` — **sem esta última não há métrica de
  tempo de primeira resposta**.
- **Fila e quadro sem busca.** A v1 filtra por nome, nome de perfil, telefone e
  assunto, e por atendente; `ListAtendimentosRequest` tem apenas `status`,
  `departamento_id` e `limit` — sem busca e sem `offset`.

- **A conversa é só texto (maior lacuna).** O atendente **não envia mídia**
  (🔌 `SendWhatsappMedia`) e **não vê a mídia recebida** — o chat mostra apenas o
  resumo textual que a IA gerou, embora o binário esteja no R2 e o caminho em
  `oraculo_mensagem.arquivo_midia`. Também faltam: marcar como lida e contador de
  não lidas (🔌 `MarkWhatsappMessageRead` + coluna `lido`), presença "digitando"
  (🔌 `SetWhatsappPresence`), citação de mensagem (colunas `mensagem_citada_id`/
  `quoted_preview` fora do `.proto`) e reação (🔌 `SendWhatsappReaction`).
- **IA analítica desligada do fluxo.** `IaEngineService.Analyse` está
  implementado e testado dos dois lados e **nunca é chamado pelo worker**:
  `intent_detectado` e `entidades_extraidas` estão sempre vazias desde a 0006.
  Com isso caem quatro comportamentos da v1 — assunto automático do atendimento,
  etiquetagem por intenção, enriquecimento do cadastro do contato por entidades,
  e o relatório de intenções.
- **Campos personalizados só existem para a IA.** `atu_campo_personalizado`/
  `atu_valor_campo` e o repositório existem; `ResolverCamposAtendimento` alimenta
  o `Responder`. Falta o catálogo (definir os campos do fluxo), o preenchimento
  manual na ficha e a extração assíncrona que a v1 fazia.
- **Operação da conexão de WhatsApp incompleta.** Sem ligar/desligar o bot por
  conexão, sem ver o QR fora do onboarding, sem renomear nem editar o webhook, e
  **sem keepalive** — a v1 reconectava a sessão a cada 60 s porque o whatsmeow
  derruba conexão ociosa. Pior: o roteamento ignora `AppInstance` e usa **o
  primeiro fluxo ativo do tenant**, então duas conexões (Vendas/Suporte) caem no
  mesmo departamento.
- **Nenhum e-mail sai do sistema.** Não há cliente SMTP no `server/`. Isso
  bloqueia de uma vez: entrega do convite (hoje o link relativo é exibido na tela
  para copiar), ativação e **recuperação de senha** — que simplesmente não existe.
- **Quadro e ficha incompletos.** Faltam atribuir a outro atendente, transferir
  de fluxo manualmente (🔌 `TransferirAtendimentoParaFluxo` só pela IA), exportar
  o quadro, ler a timeline de movimentos (gravados e sem RPC), excluir nota e
  editar/desativar etiqueta do catálogo.
- **Cadastros residuais.** Editar contato e ver seu histórico; **cliente PJ**
  (🔌 `ClienteRepository` completo, sem RPC nem tela); gestão da whitelist
  (🔌 hoje só leitura no `webhook_ingress`); sincronização de perfil/foto do
  WhatsApp (🔌 `GetWhatsappProfilePicture`).
- **Treinamento sem arquivo.** A v1 aceitava `.pdf/.doc/.docx/.txt/.xls/.xlsx/.csv`
  (loaders LangChain); a v2 só aceita texto colado. E o feedback do teste de
  resposta (`treinamento_query_test_feedback`) não tem RPC.
- **Configuração sem backup.** A v1 tinha quatro comandos de gestão de
  `CoreSettings` (export, import, bootstrap por env, load); a v2 só edita pela
  UI — não há como exportar a configuração global nem semear um ambiente novo.
- **Fim do port não executado.** O domínio de produção ainda serve o **painel
  Django** no fallback do Caddy. O ETL está pronto e testado, **não rodado contra
  produção**; `SMARTCORE_QUOTA_ENFORCE` segue `false`; as quatro validações
  manuais da N7.5 (rajada, dashboards com tráfego real, E2E, dedupe/dead-letter)
  continuam pendentes; `ReprocessarDeadLetter` e `LocalEngineFfiDataSource` não
  têm chamador/registro em produção.

### Inventário de crates/apps × status

| Componente | Tipo | Status | Plano/Nota |
|---|---|---|---|
| `infrastructure_postgres` | crate infra | ✅ | repositórios SQLx, criptografia, **migrations 0001–0027**, RLS. Repos prontos **sem consumidor**: `campos.rs`, `clientes.rs`, `whitelist.rs` |
| `infrastructure_redis` | crate infra | ✅ | conexões Redis, cache, tokens, locks |
| `infrastructure_storage` | crate infra | ✅ | cliente R2 real (`aws-sdk-s3`), presign real, layout `media/{tenant}/...` |
| `infrastructure_evolution` | crate infra | ✅ | cliente HTTP Evolution Go: texto, mídia, presença, reação, foto de perfil, QR, estado |
| `infrastructure_messaging` | crate infra | ✅ | abstração de provedor de mensageria + `ProviderRegistry` (plano 13) |
| `domain_whatsapp` | crate domínio | ✅ | tipos de mídia/mensagem sem I/O (primeiro `domain_*` extraído) |
| `ia_client` | crate cliente | ✅ | cliente resiliente do `ia_engine` (timeout/retry/degradação) + feature `mock`; usado por `worker` e `runtime_api` |
| `contracts` | crate base | ✅ | schemas proto/fbs, `Envelope` (campos 1–15) e tipos gerados |
| `transport` | crate base | ✅ | canais UDS/TCP/WS, codecs e barramento |
| `observability` | crate base | ✅ | tracing OTLP + auditoria via bus + `AuditContext`/`user_agent` |
| `error_core` | crate base | ✅ | taxonomia e erros com `ErrorEnvelope` serializável (códigos estáveis na borda) |
| `test_support` | crate base | ✅ | suporte a testes (túnel SSH, fixtures) |
| `application` | crate aplicação | ✅ | casos de uso de auth + montagem de envelopes; regras de domínio residuais no `worker` |
| `local_engine` | crate (FFI) | ✅ | N5.2: índice SQLite, cache de mídia por hash, fila offline LWW; exposto via `local_engine_ffi` (flutter_rust_bridge) |
| `data_postgres` | app | ✅ | RPC Postgres + outbox relay + `TenantConfigCache` com invalidação Pub/Sub; Ports & Adapters |
| `data_redis` | app | ✅ | RPC Redis (tokens, cache, locks, rate limiter); Ports & Adapters |
| `data_storage` | app | ✅ | RPC (PutFile/GetFile/PresignFile) + consumer de purga; backend R2 real |
| `data_whatsapp` | app | ⚠️ | 12 rotas. **4 sem chamador**: `SendWhatsappMedia`, `MarkWhatsappMessageRead`, `SetWhatsappPresence`, `SendWhatsappReaction`; `GetWhatsappProfilePicture` idem |
| `webhook_ingress` | app | ✅ | webhook autenticado (`apikey`/token) + whitelist + normalização + publish no bus + rate-limit via RPC |
| `control_plane` | app | ✅ (escopo revisado) | CLI de bootstrap de superusuário; **CRUD admin migrou para o `runtime_api`** (decisão de arquitetura) |
| `worker` | app | ⚠️ | orquestração + scheduler com 4 jobs (feedback, purga de mídia, vetorização, intents). **Não chama `Analyse`**; **sem keepalive de instância** |
| `runtime_api` | app | ✅ | auth + realtime + **84 RPCs** no `AdminService` (admin, tenant, operacional, onboarding, treinamento) + RBAC fino |
| `healthcheck` | app | ✅ | sonda `rpc`/`batimento` para os serviços Rust (usada no `healthcheck:` do compose) |
| `watchdog` | app | ✅ | reinicia container travado e publica `smartcore_service_up` de fora dos serviços |
| `clients/apps/smart-core-admin` | app Flutter | ✅ | exclusivo do **superusuário**; deployado na web sob `/v2/admin` |
| `clients/apps/smart-core-tenant` | app Flutter | ✅ | workspace + painel do tenant + onboarding; Windows empacotado; web sob `/v2/tenant` |
| `clients/packages/local_engine_ffi` | pacote Flutter | ⚠️ | binding flutter_rust_bridge do `local_engine`; `LocalEngineFfiDataSource` **não registrada no DI de produção** |
| `clients/modulos/login_module` | módulo Flutter | ✅ | login/logout/refresh via gRPC + guarda de sessão |
| `clients/modulos/admin_module` | módulo Flutter | ✅ | tenants, planos/billing, vouchers, pagamentos, auditoria, saúde, dashboard, flags, core settings, evolution, tenant config |
| `clients/modulos/tenant_module` | módulo Flutter | ✅ | painel, conexões, equipe, fluxos/etapas, contatos, convites, usuários, config do tenant |
| `clients/modulos/onboarding_module` | módulo Flutter | ✅ | cadastro (dados/plano/pagamento/pronto) + configuração guiada (assistente, WhatsApp, departamento) |
| `clients/modulos/treinamento_module` | módulo Flutter | ⚠️ | material, intenções e teste de pergunta; **sem upload de arquivo e sem feedback** |
| `clients/modulos/operacional_module` | módulo Flutter | ⚠️ | Kanban DnD por fluxo + chat streaming + ficha (etiquetas/notas). **Sem mídia, leitura, presença, timeline** |
| `clients/modulos/design_system_module` | módulo Flutter | ✅ | tema, componentes de Kanban e `DialogoComCampos` |
| `clients/modulos/core_module`, `navigation_module`, `dependencies_module`, `initial_loading_module`, `presentation_module` | módulos Flutter | ✅ | infraestrutura de app (RSOE 3.0.1, rotas, DI, bootstrap) |
| `clients/packages/api_client` | pacote Flutter | ✅ | cliente gRPC-Web/nativo único; stubs regerados |
| `clients/packages/domain_models`, `app_config`, `get_it_module` | pacotes Flutter | ✅ | DTOs do `.proto`, config por ambiente, DI |
| `evolution/` | stack Go | ✅ | Evolution Go 0.7.1 pinado, compose próprio no deploy |
| `ia_engine` | stack Python | ⚠️ | `grpc.aio`, 6 RPCs, config via Redis, RAG pgvector, degradação graciosa. **`Analyse` sem chamador**; sem loader de arquivos (v1 tinha 7 formatos) |
| `infra/migracao-v1/` | pacote Python | ⚠️ | ETL v1→v2 idempotente com dry-run/delta e conciliação (75 testes). **Nunca executado contra produção** |

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

### Mapa de dependências entre fases (estado 2026-08-08)

```
F0..F10 estruturais ─── todas ✅ ─── N1..N8 (backlog + port) ─── todas ✅
                                              │
                                              ▼
                              C1 clients RSOE 3.0.1 ✅
                              Cadastro + vouchers ✅
                              Configuração guiada ✅
                              Paridade v1 etapas 1–8 ✅
                                              │
                                              ▼
                    AUDITORIA v1 × v2 (2026-08-08): 47 lacunas,
                       5 delas defeitos em caminho que já roda
                                              │
                                              ▼
                          N8.5 Defeitos do pipeline ⬜
                          (grupo, buffer, satisfação,
                           msg_fallback, evento CONNECTION)
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
        N9 Conversa completa ⬜      N10 IA analítica ⬜      N11 Operação e
        (mídia, leitura, presença,   (Analyse no fluxo,        cadastros ⬜
         busca, timeline, campos     assunto/etiquetas,        (conexões, keepalive,
         personalizados)             contato enriquecido,      AppInstance, e-mail,
                    │                arquivo, feedback)        whitelist, PJ)
                    │                         │                         │
                    └─────────────────────────┼─────────────────────────┘
                                              ▼
                              N12 Cutover real de produção ⬜
                              (ETL rodado, enforce ligado,
                               DNS virado, Django desligado)
```

> **N8.5 vem antes de tudo**: são defeitos, não features — afetam mensagem real
> hoje, e o custo é baixo (tudo em servidor). **N9 é o caminho crítico** do que
> o usuário final sente. N10 e N11 são paralelizáveis entre si (N10 é
> worker/`ia_engine`; N11 é infra/cadastros). N12 exige as anteriores fechadas —
> não se desliga o legado enquanto a v2 faz menos que ele.

> **Marco alcançado — MVP funcional ponta-a-ponta (2026-07):** uma mensagem de
> WhatsApp entra pelo `webhook_ingress` (autenticada + whitelist), vira
> atendimento no `worker` (resolução/debounce/ticket/Kanban/bot), aparece na fila
> e no Kanban do painel, o chat recebe em tempo real via `StreamAtendimentos` e a
> resposta sai pelo `data_whatsapp` — tudo auditado e rastreável por um único
> `trace_id` (validado pelo teste e2e WS-0.3).
>
> **Onde esse marco ainda não chega (2026-08):** se a mensagem for **áudio,
> imagem ou documento**, o atendente lê apenas o resumo que a IA gerou — não
> ouve, não vê, não baixa, e não tem como responder com um arquivo. É o limite
> que a **N9** remove.

---

## Próximos passos (a partir de 2026-08-08) — Paridade real e cutover (fases N9–N12)

> Origem: a **auditoria de código v1 × v2** de 2026-08-08
> ([26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md)),
> que sucede o `infra/PLANO_PARIDADE_V1.md` (etapas 1–8, concluídas). As fases
> N1–N8 estão fechadas; o que separa o projeto de **desligar o legado** são
> quatro frentes: completar a conversa, ligar a IA analítica, fechar operação e
> cadastros, e executar o cutover.
>
> Cada fase é um ciclo PREVC próprio (planejar via `/plan-restructuring` →
> canonizar em `.context/plans/`). O DoD transversal de observabilidade/auditoria
> e SOLID/Ports & Adapters (princípios 1–9) vale para todas. A ordem de execução
> dentro de cada etapa é a que evitou retrabalho nas rodadas de paridade:
> **contrato → servidor (repo/port/adapter/handler) → fachada `grpc_web.rs` →
> stubs Dart → módulo cliente RSOE → testes**.

### Fase N8.5 — Defeitos de comportamento do pipeline (entra na frente de tudo)

**Objetivo:** corrigir o que a v2 já faz **diferente** da v1 num caminho que roda
em produção. Não são telas: são cinco divergências que afetam mensagem real, e
por isso vêm antes das features da N9. Ciclo curto, todo em servidor.

| # | Entregável | Evidência |
|---|---|---|
| N8.5.1 | **Descartar mensagem de grupo** na ingestão (ler `is_group` + fallback por JID `@g.us`), com contador e log — hoje cada participante de grupo vira um atendimento com o nome errado | v1 `_is_group_message`; `is_group` sem leitor no v2 |
| N8.5.2 | **Buffer de agregação** por contato substituindo o lock "primeiro ganha": acumular a rajada, dedupe por `message_id`, janela configurável (`TIME_CACHE`), responder ao texto compilado | v1 `message_buffer` + `_compile_message_content`; v2 `SET NX EX 2` fixo |
| N8.5.3 | **Pesquisa de satisfação**: enviar a solicitação ao encerrar, interpretar a resposta do contato e gravar `avaliacao`/`feedback` — fechando o ciclo que hoje só tem o expirador | v1 `_enviar_solicitacao_feedback` + `_check_and_process_feedback` |
| N8.5.4 | Aplicar `msg_fallback` e `msg_sem_info` do tenant (hoje `BOT_TEXT_FALLBACK` é constante no worker) | mesma classe dos bugs corrigidos em 28/07 |
| N8.5.5 | **Consumir `CONNECTION`** no worker → atualizar `connection_state` no ato da queda (hoje só por consulta); avaliar `CONTACTS` (nome/foto) e `PRESENCE` | eventos publicados sem consumidor |

**DoD:** um grupo não gera atendimento; três mensagens seguidas geram uma
resposta ao conjunto; o cliente recebe o pedido de avaliação e a nota fica no
atendimento; derrubar a conexão reflete no painel sem ninguém abrir a tela.

### Fase N9 — A conversa completa (caminho crítico)

**Objetivo:** a v2 tratar a mensagem como a v1 tratava — mídia, leitura,
presença e contexto. É o que o atendente sente todo dia, e o que hoje o legado
faz melhor. **Nove das lacunas têm servidor pronto e nenhum chamador.**

> **Ficha de cada tela** (rota, persona, dados, ações, RPC por item, estado):
> [27-mapa-telas-rotas-v2.md](./27-mapa-telas-rotas-v2.md), Parte D. A fase
> divide-se em quatro entregas — **N9a** mídia, **N9b** leitura/presença/citação,
> **N9c** busca/filtros/prioridade/atribuir/exportar, **N9d** ficha completa
> (campos personalizados, galeria, timeline) + catálogo de campos e etiquetas.

| # | Entregável | Evidência da lacuna |
|---|---|---|
| N9.1 | **Enviar mídia pelo chat**: RPC de upload (`data_storage` → R2) + envio via 🔌 `SendWhatsappMedia`; UI de anexo com pré-visualização e progresso | v1 `conversation_upload`; RPC existe sem chamador |
| N9.2 | **Ver e baixar a mídia recebida**: expor `arquivo_midia` no `.proto` com URL pré-assinada de curta duração; player de áudio, visualizador de imagem e download de documento no chat | v1 `mensagem_media`/`conversation_medias`; hoje só o resumo textual |
| N9.3 | **Leitura**: `MarcarAtendimentoLido` (repo `marcar_como_lida` já existe) + espelho no WhatsApp via 🔌 `MarkWhatsappMessageRead` + contador de não lidas na fila e no cartão | v1 `mark-read` + `notifications_unread_count` |
| N9.4 | **Presença e citação**: "digitando" via 🔌 `SetWhatsappPresence` durante a redação; `mensagem_citada_id`/`quoted_preview` no proto e na bolha do chat | v1 `conversation_presence`; colunas existem desde a 0006 |
| N9.5 | **Timeline do atendimento**: RPC de leitura de `oraculo_movimento_fluxo` + aba na ficha (quem moveu, quando, por quê, automático × manual) | v1 `conversation_timeline`; movimentos gravados e ilegíveis |
| N9.6 | **Campos personalizados**: CRUD do catálogo por fluxo/escopo, preenchimento manual na ficha (`atu_valor_campo`) e exibição no cartão | v1 `CampoPersonalizadoAdmin` + `custom_field_patch`; hoje só leitura para o `Responder` |
| N9.7 | **Quadro**: atribuir a outro atendente, transferir de fluxo manualmente (🔌 `TransferirAtendimentoParaFluxo`), exportar CSV, excluir nota, editar/desativar etiqueta do catálogo | v1 `board_assign`, `board_transfer_fluxo`, `export`, `nota_delete` |
| N9.8 | **Busca e filtros na fila e no quadro**: `q` server-side (nome, nome de perfil, telefone, assunto), filtro por atendente e `offset` para paginação | v1 `list_conversations`/`board_snapshot_by_fluxo`; hoje só status+departamento+limit |
| N9.9 | **Colunas mortas**: caminho de escrita para `prioridade` (com UI no cartão), `tags`, `contexto_conversa` e `data_primeira_resposta` — esta última é a base da métrica de SLA de primeira resposta | 4 colunas só em SELECT |

**DoD:** um atendente recebe um áudio, ouve, responde com uma imagem, acha a
conversa buscando pelo telefone, a conversa some do contador de não lidas, o
contato vê "digitando" e o histórico registra quem moveu o cartão — tudo sem
sair da v2.

### Fase N10 — IA analítica no fluxo

**Objetivo:** ligar o `Analyse` — hoje implementado, testado e **nunca chamado** —
e recuperar os comportamentos que dependiam dele na v1.

| # | Entregável | Evidência da lacuna |
|---|---|---|
| N10.1 | `worker` chama `Analyse` no pipeline: `intent_detectado`/`entidades_extraidas` persistidos por mensagem, com degradação graciosa (falha não trava o fluxo) | colunas vazias desde a migration 0006 |
| N10.2 | **Assunto automático** do atendimento a partir da análise | v1 `_auto_fill_subject` |
| N10.3 | **Etiquetagem por intenção** (sincroniza etiquetas do atendimento com os intents detectados) | v1 `_sync_intent_tags` |
| N10.4 | **Enriquecimento do contato** por entidades (nome, e-mail, documento) com validação e sem sobrescrever dado do cadastro | v1 `process_contact_entities` |
| N10.5 | **Treinamento por arquivo**: upload de `.pdf/.doc/.docx/.txt/.xls/.xlsx/.csv` → extração no `ia_engine` → chunks → `Embed` | v1 `load_document_file` (loaders LangChain); v2 só texto colado |
| N10.6 | **Feedback do teste de resposta** (`treinamento_query_test_feedback`): RPC + UI de "boa/ruim" com comentário, alimentando a curadoria | tabela existe na 0007, sem RPC |
| N10.7 | **Extração assíncrona de campos personalizados** pela IA (depende de N9.6) | v1 `extract_custom_fields_async` |

**DoD:** uma conversa nova ganha assunto e etiqueta sem intervenção; o contato é
completado a partir do que ele mesmo disse; um PDF de política de troca vira
material treinado e responde na aba de teste.

### Fase N11 — Operação da conexão, roteamento e cadastros

**Objetivo:** o tenant operar sozinho o que hoje exige o legado ou o banco.

| # | Entregável | Evidência da lacuna |
|---|---|---|
| N11.1 | **Keepalive das sessões Evolution** (job no scheduler do worker, no padrão dos quatro existentes) | v1 rodava a cada 60 s; whatsmeow derruba sessão ociosa |
| N11.2 | **Roteamento por conexão → departamento** (`AppInstance`): a instância que recebeu decide o fluxo/departamento, em vez de `buscar_primeiro_ativo` | v1 `Departamento.validar_api_key` + `_configure_department_from_app_instance` |
| N11.3 | **Gestão da conexão**: QR fora do onboarding, ligar/desligar bot por conexão, renomear, editar webhook, logout | v1 `instance_qrcode`, `toggle_bot`, `instance_update`, `instance_webhook`, `instance_logout` |
| N11.4 | **E-mail transacional** (porta plugável, como o pagamento): entrega do convite com URL absoluta, ativação e **recuperação de senha** (`AuthService` + telas) | nenhum cliente SMTP no `server/`; a v1 tinha os três |
| N11.5 | **Whitelist**: CRUD, busca por contato e alternar ativo (🔌 repo pronto, hoje só leitura no `webhook_ingress`) | v1 `settings_manager` (5 rotas) |
| N11.6 | **Contatos e clientes**: editar contato, histórico de atendimentos do contato (depende de N9.5), **cliente PJ** com vínculo N:N (🔌 `ClienteRepository` completo) | v1 `TenantContatoAdmin`/`TenantClienteAdmin` |
| N11.7 | **Perfil do WhatsApp**: sincronizar nome e foto via 🔌 `GetWhatsappProfilePicture` | v1 `EvolutionContact` |
| N11.8 | Residuais de operação: expor `ReprocessarDeadLetter` na borda, registrar `LocalEngineFfiDataSource` no DI de produção, job de expiração/aviso de assinatura, capacidade do atendente (`max_conversas`) aplicada na elegibilidade | pendências N7/N5 + v1 `check_subscription_expirations`, `is_available` |
| N11.9 | **Backup da configuração**: export/import de `CoreSettings` (CLI no `control_plane`) para semear ambiente novo e restaurar após incidente | v1 tinha 4 comandos de gestão |
| N11.10 | Normalizar **enquete, lista e botões** (hoje caem em `MediaType::Other`) | v1 mapeava 12 tipos |

**DoD:** um tenant com duas conexões manda Vendas para um departamento e Suporte
para outro; um convite chega por e-mail; uma senha esquecida se recupera sem
suporte; a sessão do WhatsApp não cai sozinha.

### Fase N12 — Cutover real de produção (fim do port)

**Objetivo:** executar o que a N8 deixou pronto e desligar o legado. **Só entra
com N9–N11 fechadas** — cutover com a v2 fazendo menos que a v1 é regressão para
o usuário, não migração.

| # | Entregável | Estado |
|---|---|---|
| N12.1 | Executar o ETL contra produção: dry-run → carga antecipada → delta → conciliação por entidade (criar o superusuário **depois** do ETL, conforme o runbook) | código pronto, 75 testes; nunca rodado |
| N12.2 | Fechar as 4 validações manuais da N7.5: rajada/carga, dashboards e alertas com tráfego real, E2E das UIs do tenant, dedupe/dead-letter observados | pendentes desde 2026-07-23 |
| N12.3 | Rollout do enforce: encerrar a janela log-only, derivar limites reais por plano e ligar `SMARTCORE_QUOTA_ENFORCE=true` | tooling pronto em `infra/migracao-v1/analise-enforce/` |
| N12.4 | Virada: DNS/rotas para a v2 na raiz do domínio, rollback válido até o freeze, **desligamento do painel Django** e remoção do fallback do Caddy | Django ainda no `handle` de fallback |

**DoD:** o domínio de produção serve a v2 na raiz; o legado está desligado; a
conciliação fecha por entidade; nenhum alerta aberto após 72 h de tráfego real.

### Sequenciamento e riscos (N8.5–N12)

- **Ordem recomendada:** N8.5 → N9 → (N10 ‖ N11) → N12. A N8.5 entra na frente
  por ser correção de comportamento em código que já roda — e é a fase mais
  barata (sem contrato novo, sem tela). N10 e N11 não se tocam (worker/`ia_engine`
  × infra e cadastros) e podem correr em paralelo.
- **N8.5.2 (buffer) altera o coração do pipeline** — é a mudança de maior risco
  de regressão junto com N11.2. Exige teste com rajada real e preservação da
  idempotência por `message_id` que o lock hoje garante de graça.
- **As 9 lacunas 🔌 são o trabalho mais barato do backlog** — contrato + fachada +
  tela sobre servidor já testado. Vale abrir cada fase por elas: entregam valor
  antes do trabalho de fundação.
- **N9.1/N9.2 (mídia) mexem em quota de storage** — o guard de
  `max_storage_bytes` já existe em log-only e passa a morder de verdade quando o
  atendente puder enviar arquivo. Validar antes de N12.3.
- **N11.2 (`AppInstance`) muda o roteamento de mensagem** — é a alteração de maior
  risco de regressão do backlog. Exige teste e2e com duas instâncias e um plano
  de reversão por feature flag.
- **N12 tem decisões humanas pendentes**: janela de migração, path definitivo na
  raiz do domínio e estratégia de convivência com o Django durante a virada.

---

## Port final N6–N8 — ✅ CONCLUÍDO (histórico)

> As três fases do port final foram executadas e arquivadas
> (`.context/plans/archive/n6-ia-fluxo-vivo`, `n7-endurecimento-residual`,
> `n8-migracao-e-cutover`), com auditoria adicional em 2026-07-24 (3 defeitos de
> bloqueio de cutover + 3 desvios de plano corrigidos).

| Fase | Entregue | Ressalva |
|---|---|---|
| **N6** (2026-07-22) | mídia no pipeline vivo, `gerado_por_ia`/`resumo_midia` no chat, fluxos de transferência por tenant, transcrição real, sentimento persistido | `Analyse` ficou implementado e **não cabeado** → **N10.1** |
| **N7** (2026-07-23) | quotas de storage/departamentos, idempotência `action_id` + dead-letter, rate-limit unificado, sync offline com conectividade/timer | 4 validações manuais → **N12.2**; `ReprocessarDeadLetter` sem chamador → **N11.8** |
| **N8** (2026-07-23) | ETL completo com dry-run/delta/conciliação, Caddy de produção, cifra da `api_key`, runbooks de cutover e enforce | **execução real não feita** → **N12** |

---

## Backlog pós-MVP N1–N5 — ✅ CONCLUÍDO (histórico)

> As cinco fases abaixo foram **executadas e arquivadas** (ciclos PREVC completos
> com final-review; ver changelog e `.context/plans/archive/`). Mantidas aqui como
> registro histórico do planejado × entregue.

### Fase N1 — Fechamento do ciclo + scheduler do worker — ✅ (2026-07-09)

**Objetivo:** consolidar o MVP em `dev`/produção e fechar a única lacuna da F4.

| # | Entregável | Ref. | Notas |
|---|---|---|---|
| N1.1 | Merge de `feature/mvp-telas-e-endurecimento` → `dev` e validação no ambiente dev (deploy automático) | — | Branch já passou pelo gate `prevc-final-review` |
| N1.2 | **Scheduler do `worker`** (F4.3b): timeout de feedback + purga de mídias via `data_storage::remover_objeto`; tarefas temporais resilientes no Redis | F4.3b | Substitui o Celery beat da v1; última etapa pendente da F4 |
| N1.3 | Consumer do outbox → disparo real do outbound do atendente (hoje `SendOutboundMessage` persiste; confirmar/fechar o elo outbox → `data_whatsapp`) | F4.4 | Verificar cobertura do `OutboxRelay` para mensagens de atendente |
| N1.4 | Dashboards Grafana com dados reais (uptime, latência gRPC, erros, backlog outbox) + alertas básicos | F9.1 | Stack LGTM já no ar; falta curadoria de dashboards |

**DoD:** MVP rodando em dev com scheduler ativo; mensagem de atendente sai de
ponta a ponta; dashboards refletindo tráfego real.

### Fase N2 — `ia_engine` (F5 — maior bloco) — ✅ (2026-07-10; mídia ao vivo → N6)

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

### Fase N3 — Painel do tenant (convites, usuários e permissões) — ✅ (2026-07-15; app dedicado `smart-core-tenant`)

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

### Fase N4 — Endurecimento de produção (F9) — ✅ (2026-07-16; quotas residuais → N7)

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

### Fase N5 — Consolidação de clientes + offline (F7/F8/F10) — ✅ (2026-07-17; prod web → N8)

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
| Painel admin (superusuário) | F2 | Tenants, planos/assinatura, pagamentos, auditoria, flags, dashboard, configs | ✅ |
| Worker + Kanban (sem IA) | F4 | Fila por departamento + **Kanban DnD** + **chat lateral** (Server Streaming) + outbound | ✅ |
| `ia_engine` | F5/N2/N6 | Selo "gerado por IA" e resumo de mídia no chat | ✅ |
| Painel do tenant | N3 | Convites, usuários, `flow_permissions`, config do tenant | ✅ |
| Endurecimento/billing | F9/N4 | Vouchers, pagamentos e quotas no admin | ✅ |
| Cadastro + configuração guiada | — | 4 passos de cadastro + 4 de configuração, retomáveis | ✅ |
| Paridade v1 (etapas 1–8) | — | Conexões, equipe, painel, contatos, fluxos/etapas, quadro por fluxo, treinamento (3 abas), ficha | ✅ |
| Local Engine (FFI) | F8/N5 | Estados offline/cache (`DataSource: LocalEngineFFI`) | ⚠️ pronto, não registrado no DI |
| **Conversa completa** | **N9** | Anexo/visualização de mídia, não lidas, busca na fila, presença, citação, timeline, campos personalizados, prioridade no cartão | ⬜ |
| **IA analítica** | **N10** | Assunto e etiquetas automáticos, upload de arquivo no treinamento, feedback do teste | ⬜ |
| **Operação e cadastros** | **N11** | Conexão (QR/bot/webhook), whitelist, contato editável, cliente PJ, recuperação de senha | ⬜ |

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
  instância, aplica a **whitelist** de remetentes a IGNORAR (números internos —
  diretoria/supervisão/testes; descarte auditado `webhook.ignored`, motivo
  `remetente_ignorado`), persiste bruto via RPC e publica no bus. Sem regra
  pesada. **Atenção:** a whitelist NÃO é lista de permissão — ver
  `modelagem_dados/06_modulo_integracoes.md` §WhiteList.

---

## Fase 4 — Worker + domínio (sem IA) — ✅ (keepalive de instância → **N11.1**)

- **4.1 Regras de domínio** — ✅ (ciclo de vida do atendimento via
  `ResolveAtendimentoParaContato` + política de ticket no `data_postgres`).
- **4.2 Casos de uso** — ✅ (resolução, debounce, política de ticket, barreira de
  bot implementados no orquestrador; extração para `application`/`domain_*`
  opcional futura).
- **4.3 Binário `worker`** — ✅ (consome o bus, resolve contato→atendimento,
  debounce por lock Redis, aplica ticket/Kanban com auditoria, cliente RPC
  reaproveitado no estado).
- **4.3b Scheduler do `worker`** — ✅ (entregue na N1.2; hoje com 4 jobs: feedback
  vencido, purga de mídia, vetorização de treinamento e intents sem embedding).
  **Falta o keepalive de instância** → **N11.1**.
- **4.4 Envio outbound** — ✅ (`worker` → `data_whatsapp::SendWhatsappMessage`;
  mensagem de atendente persiste via outbox — confirmar elo do relay em N1.3).
- **4.5 `BotRulesEngine` (sem LLM)** — ✅ (barreira: `bot_pode_atender` + ausência
  de atendente humano → resposta temporária; será substituída pela IA na N2).
- **4.6 UI: fila + Kanban + chat lateral** — ✅ (`operacional_module`: fila por
  departamento, Kanban **DnD nativo** — decisão registrada, sem `appflowy_board` —,
  chat streaming com reconexão backoff+jitter, envio outbound).

---

## Fase 5 — `ia_engine` (Python, serviço RPC) — ✅ (N2 + N6; `Analyse` sem chamador → **N10.1**)

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

- **6.1 Binário `runtime_api`** — ✅: auth (Login/Refresh/Logout), onboarding
  público, convites, rotas operacionais e de gestão do tenant — **84 RPCs** hoje.
  *Falta `Recuperar senha` no `AuthService` → **N11.4**.*
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

## Fase 7 — Consolidação do app (RemoteOnly) — ✅ (entregue na **Fase N5.1**)

As telas nasceram coladas às features (F6.5, F2, F4.6); a F7 é **consolidação**:
navegação, estados de carga/erro/vazio, acessibilidade, consistência visual e
**empacotamento** (`flutter build windows --release`). O deploy **web** do app já
está resolvido (Caddy `/v2/admin`, same-origin). Pendências concentradas em N5.1.

---

## Fase 8 — Local Engine (FFI) + mídia local — ✅ (N5.2 + N7.4; registro no DI → **N11.8**)

- **8.1** `local_engine` dual-target (lib + `cdylib`/`staticlib`) — ✅.
- **8.2** índice SQLite + cache de dados — ✅.
- **8.3** cache de mídia em disco (hash + URL pré-assinada do R2) — ✅.
- **8.4** `local_engine_ffi` + `DataSource: LocalEngineFFI` — ⚠️ classe pronta,
  **não registrada no DI de produção**.
- **8.5** fila offline + sincronização (LWW + versionamento) + gatilho por
  conectividade e timer — ✅ (N7.4).

---

## Fase 9 — Endurecimento, billing e produção — ✅ (N1.4/N4/N7; enforce e validações → **N12**)

- **9.1 Observabilidade completa** — ✅: stack LGTM, cadeia de trace validada por
  e2e, dashboards curados, `watchdog` publicando `smartcore_service_up`.
  **Validação com tráfego real de produção** → N12.2.
- **9.2 Billing/usage e quotas** — ✅ implementado (instâncias, departamentos,
  fluxos, storage). **`SMARTCORE_QUOTA_ENFORCE` ainda `false`** → N12.3.
- **9.3 Retenção de mídia** — ✅ (purga por retenção do plano no scheduler,
  migration 0017).
- **9.4 Segurança e carga** — ✅ role `smartcore_app_rt` não-superuser com RLS
  provado, rate limiting unificado. **Testes de rajada com tráfego real** → N12.2.
- **9.5 CI/CD + deploy** — ✅ (fase devops; rollback operante).

---

## Fase 10 — Port para Web — ✅ (dev e prod roteados; virada da raiz → **N12.4**)

- **10.1** `flutter_web` RemoteOnly — ✅: **admin e tenant** rodam na web em
  `/v2/admin` e `/v2/tenant` (dev e prod, same-origin, gRPC-Web pelo Caddy).
- **10.2** mídia na Web (URL pré-assinada do R2 + **CORS** no bucket —
  ver [08 §7.5](./08-infraestrutura-storage.md)) — ⚠️ CORS configurado; a
  **exibição de mídia no chat** ainda não existe → **N9.2**.
- **10.3** raiz do domínio ainda serve o **Django legado** no fallback → **N12.4**.

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

> Auditado contra o código em 2026-08-08. Detalhe por rota/model:
> [26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md).
> 🔌 = servidor pronto **sem chamador**.

### Fundação e plataforma — fechada

| Regra v1 (referência) | Onde vive na v2 | Status |
|---|---|---|
| Schema multi-tenant + RLS | `infrastructure_postgres` (migrations 0001–0027) | ✅ |
| Cifragem de credenciais (Fernet) | `crypto.rs` (`CipherManager`, AES-256-GCM), inclusive `api_key` de instância (0023) | ✅ |
| `TenantConfig` (persona/prompts/providers) | `tenants/config.rs` + cascata publicada no Redis e consumida pelo `ia_engine` | ✅ |
| `Tenant`/`Plan`/`Subscription`/`TenantUser` | `tenants/`, `plans`, `users` + 84 RPCs + telas admin/tenant | ✅ |
| Refresh/blocklist/cache de permissões | `infrastructure_redis` (auth_tokens, cache, `flow_permissions` TTL 30 s) | ✅ |
| Event bus (substitui fila Celery) | `transport::bus` (Redis Streams) + outbox relay | ✅ |
| Mídia (binário transitório) | `infrastructure_storage` (R2) + purga por retenção do plano | ✅ |
| Auth/JWT/sessão + `runtime_api` | `application` + `apps/runtime_api` | ✅ |
| RBAC (`role`+`module_permissions`+`flow_permissions`) | escopos + `flow_permissions` fim a fim + UI de gestão | ✅ |
| `AttendanceOrchestrator` | `worker` (resolução/debounce/ticket/Kanban/bot/outbound) | ✅ |
| `process_contact_response_task` | `worker` consumindo Streams | ✅ |
| feedback/purga de mídia (beat) | scheduler do `worker` | ✅ |
| `message_buffer` (debounce) | lock de debounce no Redis | ✅ |
| `board_service._aplicar_regras_tipo_etapa` | `atendimentos.rs` (5 colunas, nome decide desfecho, assumir desliga bot, `historico_status`) | ✅ |
| `FluxoAtendimento`/`EtapaFluxo` | 8 RPCs + telas (a v1 só tinha admin genérico) | ✅ superior |
| `Departamento`/`Atendente` | 8 RPCs + tela de equipe | ✅ |
| `Treinamento`/`QueryCompose` (pgvector 1536) | `treinamento/` + job de vetorização + 3 abas | ✅ |
| `FeaturesCompose` (IA pura) | `ia_engine` (6 RPCs, config via Redis) | ✅ |

### Lacunas abertas — endereçadas por N9–N12

| Regra v1 (referência) | Onde deveria viver na v2 | Status |
|---|---|---|
| `_is_group_message` (descarta grupo) | `is_group` no `NormalizedMessage`, sem leitor | ⚠️ **defeito → N8.5.1** |
| `message_buffer` + `_compile_message_content` | lock `SET NX EX 2` (primeira ganha) | ⚠️ **defeito → N8.5.2** |
| `_enviar_solicitacao_feedback` / `_check_and_process_feedback` | `avaliacao`/`feedback` só em SELECT | ⚠️ **defeito → N8.5.3** |
| `msg_fallback` / `msg_sem_info` | publicados no `RuntimeConfig`, nunca aplicados | ⚠️ **defeito → N8.5.4** |
| webhook `CONNECTION`/`CONTACTS`/`PRESENCE` | normalizados e publicados, sem consumidor | ⚠️ **defeito → N8.5.5** |
| `conversation_upload` / `mensagem_media` | 🔌 `SendWhatsappMedia` + `arquivo_midia` no proto | ⬜ **N9.1/N9.2** |
| `list_conversations(q, atendente_id)` (busca e filtros) | `ListAtendimentos` sem busca nem `offset` | ⬜ **N9.8** |
| `prioridade` / `tags` / `contexto_conversa` / `data_primeira_resposta` | colunas lidas e nunca escritas | ⬜ **N9.9** |
| `mark-read` / `unread-count` | 🔌 `MarkWhatsappMessageRead` + coluna `lido` | ⬜ **N9.3** |
| `conversation_presence` / citação | 🔌 `SetWhatsappPresence` + `mensagem_citada_id` | ⬜ **N9.4** |
| `conversation_timeline` | `oraculo_movimento_fluxo` (gravado, sem RPC) | ⬜ **N9.5** |
| `CampoPersonalizado`/`ValorCampoAtendimento` | 🔌 `campos.rs` (só leitura para o `Responder`) | ⬜ **N9.6** |
| `board_assign` / `board_transfer_fluxo` / `export` | 🔌 `TransferirAtendimentoParaFluxo` | ⬜ **N9.7** |
| `analise_previa_mensagem` | `IaEngineService.Analyse` 🔌 **nunca chamado** | ⬜ **N10.1** |
| `_auto_fill_subject` / `_sync_intent_tags` / `process_contact_entities` | `worker` (pós-`Analyse`) | ⬜ **N10.2–4** |
| `load_document_file` (7 formatos) | `ia_engine` + `CreateMyTreinamento` | ⬜ **N10.5** |
| `QueryTestFeedback` | `treinamento_query_test_feedback` (sem RPC) | ⬜ **N10.6** |
| `keepalive_evolution_instances` | scheduler do `worker` | ⬜ **N11.1** |
| `AppInstance` (api_key → departamento) | `resolver_atendimento_para_contato` (hoje: primeiro fluxo ativo) | ⬜ **N11.2** |
| `instance_qrcode`/`toggle_bot`/`instance_update`/`instance_webhook` | fachada + `/tenant/conexoes` | ⬜ **N11.3** |
| e-mail de convite/ativação + `password_reset` | porta de e-mail + `AuthService` | ⬜ **N11.4** |
| `WhiteList` (5 rotas) | 🔌 `integracoes/whitelist.rs` | ⬜ **N11.5** |
| `Contato` (editar) / `Cliente` (PJ) | 🔌 `contatos.rs` / `clientes.rs` | ⬜ **N11.6** |
| `EvolutionContact` (nome/foto) | 🔌 `GetWhatsappProfilePicture` | ⬜ **N11.7** |
| `check_subscription_expirations` / `is_available` | scheduler + elegibilidade do atendente | ⬜ **N11.8** |
| `export/import/bootstrap_core_settings` (4 comandos) | CLI do `control_plane` | ⬜ **N11.9** |
| 12 tipos de mensagem mapeados | enquete/lista/botões caem em `Other` | ⬜ **N11.10** |
| **Dados de produção da v1** | ETL `infra/migracao-v1/` (pronto, não executado) | ⬜ **N12.1** |
| **Painel Django no ar** | fallback do Caddy em produção | ⬜ **N12.4** |

### Descartado por decisão — não será portado

| Regra v1 | Motivo |
|---|---|
| `trello_sync` inteiro (5 modelos, 18 tasks, webhooks) | 🚫 quadro próprio: o cartão nasce do atendimento, não de um espelho externo |
| ClickUp e Notion (`unifield_data_services`) | 🚫 mesma decisão |
| `config_database`, `run_migrations`, `test_connection` | 🚫 base única com RLS substitui o DB-per-tenant |
| `tenant-admin` genérico do Django (21 modelos) | 🚫 tela por caso de uso, não por tabela |
| landing page e `config_debug` | 🚫 fora do produto |

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

### Planos do port final (N6–N8 — concluídos)

- [21-fase-N6-ia-fluxo-vivo.md](./21-fase-N6-ia-fluxo-vivo.md)
  — **N6 ✅:** IA no fluxo vivo — mídia no pipeline, campos de IA no chat, fluxos de transferência, transcrição real.
- [22-fase-N7-endurecimento-residual.md](./22-fase-N7-endurecimento-residual.md)
  — **N7 ✅:** quotas restantes, idempotência do sync, rate-limit centralizado, triggers offline, validação operacional.
- [23-fase-N8-migracao-e-cutover.md](./23-fase-N8-migracao-e-cutover.md)
  — **N8 ✅ (código):** ETL v1→v2, produção web, rollout do enforce, runbook de cutover. Execução real → **N12**.
- [24-cobertura-testes-100.md](./24-cobertura-testes-100.md) — trilha de cobertura e ratchet no CI.
- [25-fase-C1-clients-rsoe-v3.md](./25-fase-C1-clients-rsoe-v3.md)
  — **C1 ✅:** clients Flutter sobre a `return_success_or_error` 3.0.1.

### Base do cronograma atual (N9–N12)

- [26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md)
  — **auditoria de código v1 × v2** (2026-08-08): inventário por domínio, 47
  lacunas verificadas com evidência, cinco defeitos de comportamento, itens
  descartados por decisão e o que a v2 tem além da v1. **É a fonte das fases
  N8.5–N12.**
- [27-mapa-telas-rotas-v2.md](./27-mapa-telas-rotas-v2.md)
  — **mapa de telas, rotas e funcionalidades** (2026-08-09): inventário das 40
  páginas da v1 com as ações de cada uma, árvore de navegação proposta para a v2,
  **ficha por tela** (rota, persona, dados, ações, RPC, estado) e os **43 RPCs
  novos + 6 extensões aditivas** consolidados. **É o contrato de execução das
  fases N9–N11.**
- `infra/PLANO_PARIDADE_V1.md` — plano das etapas 1–8 de paridade (executadas
  entre 31/07 e 06/08/2026); **sucedido** pelo documento 26.
- `infra/PLANO_ROBUSTEZ_CLIENTE.md` — varredura de robustez do cliente Flutter
  (concluída); a nota final sobre query compose e teste de resposta foi resolvida
  na etapa 7 da paridade.
- `infra/migracao-v1/RUNBOOK_CUTOVER_N8.md` e
  `infra/RUNBOOK_ENFORCE_ROLLOUT_N8.md` — procedimentos operacionais da **N12**.

### Planos canônicos das fases N8.5–N12 (`.context/plans/`)

Criados em 2026-08-09 via `/plan-restructuring`. Cada um tem pasta própria com
plano completo (verdade técnica), `info_aux` (libs e serviços, com a
documentação verificada) e referências brutas:

| Fase | Plano canônico | Estado |
|---|---|---|
| N8.5 | `.context/plans/n85-defeitos-pipeline.md` | 🚧 workflow PREVC ativo (fase R) |
| N9 | `.context/plans/n9-conversa-completa.md` | pronto, na fila |
| N10 | `.context/plans/n10-ia-analitica.md` | pronto, na fila |
| N11 | `.context/plans/n11-operacao-cadastros.md` | pronto, na fila |
| N12 | `.context/plans/n12-cutover-producao.md` | pronto, na fila |

**Achados da coleta de documentação que alteram o plano:**
- 🚨 `video_player` **não suporta Windows** → spike de `media_kit` na N9a.
- ⚠️ O contrato da **evolution-go** não é o da Evolution API v2 — a fonte da
  verdade é `infrastructure_evolution/src/provider.rs` (registrado nos `info_aux`).
- A premissa do keepalive da v1 foi corrigida: o whatsmeow tem keep-alive nativo;
  o certo é **sondar estado**, não forçar reconexão (N11.1).
- E-mail: porta plugável com **Brevo** como default; **SPF/DKIM levam 24–48 h** —
  iniciar o DNS no dia 1 da N11.

---

*Documento de fases auditado contra o código real (`dev` @ `cf30905`) em
2026-08-08. Retroalimentado a cada fase concluída.*
