# Plano de Finalização — Frentes em Andamento + Lacunas Iniciais

> **Status:** Plano de execução — criado em **2026-06-27**.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** **fechar todas as frentes 🚧** do projeto e **as lacunas da
> implementação inicial** (com destaque para o **Grafana/observabilidade**), de
> modo que o produto chegue a um **MVP operacional ponta-a-ponta**.
> **Regra inegociável deste plano:** **tudo que for implementado passa pela
> observabilidade** — emite logs/spans estruturados **e** registra auditoria. Ver
> §1 (Contrato de Observabilidade).
> **Deriva de:** [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md)
> (cronograma S1–S9), [05-observabilidade.md](./05-observabilidade.md),
> [10-plano-cicd-devops.md](./10-plano-cicd-devops.md) (devops-4),
> [11-painel-admin-superusuario.md](./11-painel-admin-superusuario.md),
> [13](./13-camada-de-abstração-de-mensageria.md)/[14](./14-refator-solid-ports-adapters.md).

---

## 0. Escopo

### 0.1 Dentro do escopo (o que este plano finaliza)

| Frente | Estado hoje | Fase |
|---|---|---|
| **Observabilidade transversal + Grafana LGTM** | parcial (sem stack Grafana; `worker`/`webhook_ingress` sem auditoria) | devops-4 / F9.1 |
| **Auth/whitelist no `webhook_ingress`** | 🚧 origem não validada | F3.4 |
| **Orquestração do `worker`** | 🚧 persiste em `atendimento_id` fixo | F3.2 / F4.1–4.3, 4.5 |
| **Envio outbound** | ⬜ worker não chama `data_whatsapp` | F4.4 |
| **Realtime (stream real)** | 🚧 `StreamAtendimentos` é forward único | F6.2 |
| **`runtime_api` — comandos faltantes + RBAC** | 🚧 só auth básico | F6.1 / F6.3 |
| **Control Plane CRUD + `TenantConfigCache`** | 🚧 só CLI superuser | F2.2b / F2.3 |
| **Telas Flutter (admin + operacional)** | 🚧 só login pronto | F2.5 / F4.6 |

### 0.2 Fora do escopo (backlog posterior — não bloqueia o MVP)

- **F5 `ia_engine`** (serviço Python de IA) — é uma frente **nova**, não "em
  andamento". As telas/worker já são preparados para plugá-la depois.
- **F8 `local_engine` (FFI)** e **F10 port Web** (`flutter_web`).
- **F9.2 billing/quotas** e **F9.3 retenção de mídia** (além do mínimo já existente).

> Se a intenção for **incluir o `ia_engine`** nesta leva, ele entra como WS-7
> (após o WS-4 realtime); o restante do plano não muda.

---

## 1. Contrato de Observabilidade (requisito transversal — DoD de TODA tarefa)

Nenhuma tarefa deste plano é considerada concluída sem cumprir **os dois eixos**
abaixo. A fundação já existe na crate `observability` — este plano **a aplica em
todo handler/caso de uso novo**, sem reinventá-la.

### 1.1 Eixo Telemetria (logs + traces)

- Todo binário chama `observability::init_telemetry(<serviço>, <env>)` no boot
  (já é padrão; manter).
- Todo handler/caso de uso novo abre um **span** com `tenant_id` (e `trace_id`
  quando houver) via a macro `observability::tenant_span!` ou `#[tracing::instrument]`.
- **Propagar `traceparent` W3C** ponta-a-ponta: webhook → bus → worker → RPC
  `data_*` → resposta. Reusar `observability::{extrair_contexto, injetar_contexto_atual}`
  e o campo `traceparent` do `Envelope`/`EventoBruto` (padrão já presente no
  `worker::processar_mensagem_recebida`).
- Logs estruturados (`tracing::{info,warn,error}`) com campos, **nunca** string
  interpolada solta. **Sem segredos** em log (token de instância, JWT, api keys).

### 1.2 Eixo Auditoria (negócio + segurança)

- Instanciar **`observability::AuditLogger`** via `new_with_redis(conn, <serviço>)`
  em produção (em teste, `new(...)` com a feature `postgres-audit`).
- Toda **ação relevante** registra um evento via `AuditLogger`:
  - **Com tenant:** `info/warn/error(tenant_id, event, message, context, user_id, ip, trace_id)`.
  - **Sem tenant (sistema):** `*_global(...)`.
- O `AuditLogger` publica no **Redis Streams de segurança**
  (`publicar_evento_seguranca`) → consumido pelo `data_postgres` → tabela
  `audit_log` sob RLS. **Não** abrir conexão direta ao Postgres a partir dos
  serviços (mantém `infra` desacoplada de `observability`).
- **Convenção de nomes de evento:** `<dominio>.<acao>` em snake (ex.:
  `webhook.rejected`, `atendimento.aberto`, `mensagem.enviada`, `bot.respondeu`,
  `stream.aberto`, `tenant.criado`). Registrar no glossário (§7).

### 1.3 Checklist de observabilidade por PR (cola no template)

- [ ] Span com `tenant_id`/`trace_id` no caminho novo.
- [ ] `traceparent` propagado para o próximo salto (bus/RPC).
- [ ] Pelo menos 1 evento de auditoria por ação de negócio/segurança relevante.
- [ ] Nomes de evento na convenção `<dominio>.<acao>` e documentados no §7.
- [ ] Nenhum segredo em log/auditoria.
- [ ] Caminho de erro também audita (`warn`/`error`), não só o feliz.

---

## 2. Estrutura do plano (workstreams)

O trabalho está organizado em **workstreams (WS)** com dependências explícitas.
O WS-0 é **fundacional** e habilita o "passar pela observabilidade" de todos os
demais; por isso vem primeiro.

```
WS-0 Observabilidade + Grafana (fundação transversal)
       │  (toda tarefa abaixo já nasce auditada/instrumentada)
       ├──► WS-1 webhook_ingress: auth + whitelist + idempotência (F3.4)
       │            │
       │            ▼
       ├──► WS-2 worker: orquestração de atendimento (F3.2/F4.1–4.3, 4.5)
       │            │
       │            ▼
       ├──► WS-3 outbound: worker → data_whatsapp (F4.4)
       │            │
       │            ▼
       ├──► WS-4 realtime: stream real por tenant (F6.2)
       │            │
       │            ▼
       ├──► WS-6 telas operacionais Flutter (F4.6)  ◄── consome WS-4
       │
       ├──► WS-5 runtime_api: Register/Invite + comandos + RBAC (F6.1/6.3)
       │
       └──► WS-7 control_plane CRUD + TenantConfigCache + telas admin (F2.2b/2.3/2.5)
```

---

## 3. Workstreams detalhados

### WS-0 — Observabilidade transversal + Grafana LGTM  *(devops-4 / F9.1)*

**Por que primeiro:** estabelece a fundação que todas as outras tarefas usam para
cumprir o Contrato de Observabilidade (§1) e dá visibilidade do que está sendo
construído já durante a implementação.

#### Tarefas

1. **WS-0.1 — Stack Grafana LGTM (`docker/compose/observability.yml`)**
   - Serviços: **OTel Collector** (recebe OTLP gRPC dos binários), **Loki**
     (logs), **Tempo** (traces), **Prometheus** (métricas) e **Grafana** (UI).
   - Datasources provisionados + dashboards básicos: uptime por serviço, latência
     de RPC, taxa de erro, profundidade do stream do bus, latência webhook→bus.
   - Expor `grafana.smartcoreassistant.com.br` via **Caddy** (porta 3000 interna).
   - Variáveis OTLP nos `.env` de dev/prod (`OTEL_EXPORTER_OTLP_ENDPOINT`).
2. **WS-0.2 — Plugar `AuditLogger` onde falta**
   - **`worker`** (hoje **0** auditoria) e **`webhook_ingress`** (hoje **0**)
     recebem `AuditLogger::new_with_redis` no boot. Sem isso, WS-1/WS-2 não passam
     no DoD de auditoria.
   - Conferir `messaging_gateway`: como o papel migra para `webhook_ingress`/
     `data_whatsapp`, **decidir descomissionar** (remover do `target`/compose) em
     vez de instrumentar — registrar a decisão.
3. **WS-0.3 — Consolidar a cadeia de trace**
   - Garantir `traceparent` íntegro de ponta a ponta no fluxo de mensagem; teste
     de integração que segue um `trace_id` do webhook ao `audit_log`.
4. **WS-0.4 — Métricas de pool** (feature `pool-metrics` já existe) ligadas no
   `data_postgres`/`data_redis` e expostas ao Prometheus.

#### DoD
- `docker compose -f docker/compose/observability.yml up -d` sobe saudável.
- Em dev: um webhook de teste gera **trace contínuo** (Tempo) + **logs** (Loki) +
  **linha em `audit_log`**, correlacionados pelo mesmo `trace_id`.
- Dashboards mostram dados reais de ≥ 2 serviços.
- Plano [05](./05-observabilidade.md) e [10 §devops-4](./10-plano-cicd-devops.md)
  marcados como atendidos.

---

### WS-1 — `webhook_ingress`: autenticação + whitelist + idempotência  *(F3.4)*

**Estado:** recebe `/webhook/{provider}/{tenant}/{instance}`, normaliza e publica
no bus — **sem validar a origem**.

#### Tarefas
1. **WS-1.1 — Autenticação da origem:** validar o `apikey`/token de instância do
   payload contra `integracoes/evolution.rs` (token da instância) e a
   **whitelist** (`integracoes/whitelist.rs`) — repositórios já existem; falta
   plugar via RPC ao `data_postgres`.
2. **WS-1.2 — Idempotência:** deduplicar por `message_id`/`stanzaId` antes de
   publicar (chave no `data_redis`), evitando reprocessamento.
3. **WS-1.3 — Rejeição segura:** requisição inválida → `401/403`, **sem** publicar
   no bus.

#### Observabilidade (obrigatória)
- Span `webhook_ingest` com `tenant_id`/`instance_id`/`trace_id`.
- Auditoria: `webhook.received` (INFO), `webhook.rejected` (WARN, com motivo:
  token inválido / fora da whitelist), `webhook.duplicated` (INFO).
- `traceparent` semeado aqui e propagado no envelope publicado no bus.

#### DoD
- Webhook com token válido + instância na whitelist → evento no bus; inválido →
  rejeitado e **auditado**; duplicado → ignorado e auditado. Testes cobrindo os 3.

---

### WS-2 — `worker`: orquestração de atendimento  *(F3.2 / F4.1–4.3, 4.5)*

**Estado:** `processar_mensagem_recebida` persiste em `atendimento_id` fixo `1`.
É o **coração do MVP** e o **caminho crítico** do cronograma.

#### Tarefas
1. **WS-2.1 — `domain_whatsapp` (normalização):** mapeamento por chave JSON
   (`imageMessage`/`audioMessage`/… → `media_type`), reply/`stanzaId`. Crate de
   domínio **sem I/O** (regra dos `domain_*`).
2. **WS-2.2 — Resolução contato → atendimento:** localizar/criar contato, resolver
   **atendimento aberto** do contato (ou abrir um), substituindo o `atendimento_id`
   fixo. Reusa repositórios `clientes/` e `atendimentos/` via RPC `data_postgres`.
3. **WS-2.3 — Debounce por contato (`DebounceByContact`):** agrupar mensagens em
   rajada (janela curta no `data_redis`) antes de processar.
4. **WS-2.4 — Políticas de ticket + Kanban:** `DecideTicketPolicy`,
   `ApplyKanbanStage` (mover estágio conforme evento).
5. **WS-2.5 — Barreira de bot (`BotRulesEngine`, sem LLM):** `CanBotRespond`
   (flag `bot_pode_atender`, sem humano ativo) → resposta temporária.
   *Ponto de extensão futuro para o `ia_engine` (F5).*
6. **WS-2.6 — Cliente RPC no estado:** reusar conexões (`AppState`) em vez de
   `conectar_cliente` por evento (correção do bootstrap atual).

#### Observabilidade (obrigatória)
- Span por etapa (`resolver_atendimento`, `aplicar_debounce`, `decidir_ticket`,
  `aplicar_kanban`, `avaliar_bot`) com `tenant_id`/`trace_id`.
- Auditoria: `atendimento.aberto`, `atendimento.reaberto`, `mensagem.persistida`,
  `ticket.transicionado`, `kanban.movido`, `bot.respondeu` / `bot.silenciado`.
- `traceparent` propagado em cada RPC `data_*`.

#### DoD
- 2 mensagens do mesmo contato em rajada → **1** atendimento, debounce aplicado,
  estágio de Kanban correto, tudo **auditado**. Testes de integração contra
  `data_postgres`/`data_redis` reais (via `test_support`).

---

### WS-3 — Envio outbound  *(F4.4)*

**Estado:** infra pronta (`data_whatsapp::SendWhatsappMessage`/`SendWhatsappMedia`);
o `worker` ainda não a chama.

#### Tarefas
1. **WS-3.1 — Caso de uso de envio** no `worker`/`application`: dispara RPC
   `data_whatsapp::SendWhatsappMessage` com **retry + backoff**.
2. **WS-3.2 — Confirmações:** consumir status de entrega/leitura e refletir no
   atendimento.

#### Observabilidade
- Span `enviar_mensagem`; auditoria `mensagem.enviada`, `mensagem.falha_envio`
  (com tentativa/causa), `mensagem.confirmada`.

#### DoD
- Resposta sai pelo gateway com retry resiliente e **auditoria** de envio/falha.

---

### WS-4 — Realtime: stream real por tenant  *(F6.2)*

**Estado:** `handler_stream_atendimentos` faz **um** `ListAtendimentos` e retorna —
**não** é stream. Falta o fan-out.

#### Tarefas
1. **WS-4.1 — Stream gRPC real (`StreamAtendimentos`)** com **Server Streaming**
   (Tonic), validando o **JWT na abertura** (mesmo interceptor das unárias).
2. **WS-4.2 — Fan-out por tenant via Redis pub/sub:** publicar eventos
   (mensagem/typing/presença/kanban) e empurrar aos streams abertos do tenant;
   suporta **multi-réplica**. **Sem WebSocket** (decisão D7).
3. **WS-4.3 — `tonic-web`** habilitado para o futuro port Web.

#### Observabilidade
- Span `stream_atendimentos` por conexão; auditoria `stream.aberto`,
  `stream.fechado`, `stream.nao_autorizado` (WARN).

#### DoD
- 2 clientes do mesmo tenant recebem o mesmo evento em tempo real; cliente de
  outro tenant **não** recebe (isolamento) — auditado e testado.

---

### WS-5 — `runtime_api`: comandos faltantes + RBAC  *(F6.1 / F6.3)*

**Estado:** Login/Refresh/Logout ✅; faltam Register/Invite/Accept, comandos de
leitura e o RBAC completo.

#### Tarefas
1. **WS-5.1 — Register / Invite / Accept** (cadastro de tenant + convites).
2. **WS-5.2 — Comandos de leitura:** tickets, kanban, histórico (forward
   autenticado ao `data_postgres`, padrão `handler_admin_forward`).
3. **WS-5.3 — RBAC completo + defesa em 3 camadas:** interceptor (escopos a partir
   do JWT) → checagem de `module_permissions`/`flow_permissions` → RLS.

#### Observabilidade
- Auditoria: `tenant.registrado`, `convite.enviado`, `convite.aceito`,
  `autorizacao.negada` (WARN). Reusar o `audit.rs` da borda já existente.

#### DoD
- Cadastro/convite ponta-a-ponta; chamada sem escopo → negada e **auditada**.

---

### WS-6 — Telas operacionais Flutter  *(F4.6)* — consome WS-4

**Estado:** app `smart-core-admin` com login pronto; faltam as telas operacionais.

#### Tarefas
1. **WS-6.1 — Fila por departamento + Kanban** (drag-and-drop) no `smart-core-admin`,
   componentes em `design_system_module`.
2. **WS-6.2 — Chat lateral** consumindo o **Server Streaming** (WS-4) via
   `api_client`, com envio outbound (WS-3).
3. **WS-6.3 — `DataSource` abstrato (RemoteOnly)** desde já (garante port Web/F10).

#### DoD
- Mover card e enviar/receber mensagem em tempo real **contra o `runtime_api`
  real** (não mock); `flutter analyze` limpo.

---

### WS-7 — Control Plane CRUD + `TenantConfigCache` + telas admin  *(F2.2b/2.3/2.5)*

**Estado:** só CLI superuser; `admin_module` Flutter aguardando back-end;
`TenantConfigCache` implementado e testado mas **não plugado**.

#### Tarefas
1. **WS-7.1 — CRUD admin no `control_plane`:** tenant, config, plano/assinatura,
   tenant_user/invite (gRPC de administração sobre repositórios existentes).
2. **WS-7.2 — `TenantConfigCache` plugado:** instanciar nos consumidores; expor
   rotas RPC de leitura/escrita de configuração; **assinante de invalidação via
   Redis Pub/Sub** (canal `core:settings:invalidate`).
3. **WS-7.3 — Telas admin** (`admin_module`): tenants, planos/assinatura, convites.

#### Observabilidade
- Auditoria: `tenant.criado/atualizado`, `plano.alterado`, `config.atualizada`,
  `config.invalidada`. (Operações administrativas **sempre** auditadas.)

#### DoD
- Alterar configuração via RPC reflete nos consumidores **sem restart** (invalidação
  funcionando) e fica **auditado**; telas admin operam contra o `control_plane` real.

---

## 4. Cronograma (mapeado no S1–S9 do doc 02)

| Sprint | Janela | Workstreams | Marco |
|---|---|---|---|
| **S0.5** | 30/jun – 11/jul | **WS-0** (obs + Grafana) | Tudo passa a nascer instrumentado/auditado; Grafana no ar |
| **S1** | (sobrepõe) | **WS-1** (webhook auth) | Ingestão confiável e auditada |
| **S2–S3** | 14/jul – 08/ago | **WS-2** (orquestração worker) | Contato→atendimento real |
| **S4** | 11/ago – 22/ago | **WS-3 + WS-4** (outbound + realtime) | Resposta sai + stream por tenant |
| **S5** | 25/ago – 05/set | **WS-6** (telas operacionais) | **MVP ponta-a-ponta** |
| **S6** | 08/set – 19/set | **WS-7** (control plane + admin) | Back office operacional |
| **S7** | 22/set – 03/out | **WS-5** (comandos + RBAC) | API cliente completa + RBAC |
| **S8–S9** | 06/out – 31/out | Endurecimento + consolidação | Dashboards/alertas + F7 |

> **WS-0 abre o trabalho** e roda em paralelo ao WS-1 — é barato e destrava o DoD
> de observabilidade dos demais. O **caminho crítico** é WS-2 (orquestração), que
> alimenta WS-4 (realtime) e WS-6 (UI). O **marco de MVP** continua na **S5**.

---

## 5. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| WS-2 (contato→atendimento) escorrega | Empurra MVP (S5) e UI | Atacar em 1º; fatiar em WS-2.1/2.2 entregáveis |
| Fan-out realtime multi-réplica (WS-4) | Complexidade de sincronização | Começar single-réplica; pub/sub depois, atrás de feature flag |
| Auditoria assíncrona pode perder evento se Redis cai | Lacuna de trilha | Já há `tracing::error` no fallback; monitorar profundidade do stream no Grafana |
| `messaging_gateway` órfão | Confusão de responsabilidade | Decidir descomissionar em WS-0.2 e documentar |
| Ambiente remoto/túnel instável | Trava testes de integração | Manter `test_support` e reset de schema; smoke após cada deploy dev |

---

## 6. Estratégia de testes (por WS)

- **Rust:** sempre via `.\infra\test-local.ps1` (nunca `cargo test` direto).
  Integração contra Postgres/Redis reais (túnel via `test_support`), `#[sqlx::test]`
  com transação+rollback onde couber. Cada WS adiciona testes de isolamento
  multi-tenant para tabelas novas.
- **Flutter:** via `.\infra\test-flutter.ps1`; telas exercitam o fluxo real contra
  o `runtime_api` (não mock).
- **Observabilidade:** teste de ponta-a-ponta que segue um `trace_id` do webhook
  ao `audit_log` (WS-0.3) — gate da fundação.

---

## 7. Glossário de eventos de auditoria (vivo)

> Toda nova ação registra aqui o par `evento → quando emitir`. Mantido em ordem
> de domínio.

| Evento | Nível | Quando |
|---|---|---|
| `webhook.received` | INFO | Webhook autenticado aceito |
| `webhook.rejected` | WARN | Token inválido ou fora da whitelist |
| `webhook.duplicated` | INFO | `message_id`/`stanzaId` já visto |
| `atendimento.aberto` / `.reaberto` | INFO | Novo atendimento resolvido para o contato |
| `mensagem.persistida` | INFO | Mensagem gravada no atendimento |
| `mensagem.enviada` / `.falha_envio` / `.confirmada` | INFO/WARN | Outbound |
| `ticket.transicionado` / `kanban.movido` | INFO | Mudança de estágio |
| `bot.respondeu` / `bot.silenciado` | INFO | Barreira de bot |
| `stream.aberto` / `.fechado` / `.nao_autorizado` | INFO/WARN | Realtime |
| `tenant.registrado` / `convite.enviado` / `convite.aceito` | INFO | Auth/onboarding |
| `autorizacao.negada` | WARN | RBAC barrou |
| `tenant.criado/atualizado` / `plano.alterado` / `config.atualizada/invalidada` | INFO | Control plane |

---

## 8. Próximo passo de canonização

Ao aprovar este plano, a **etapa final** é rodar **`/plan-restructuring`** para
normalizá-lo em `.context/plans/{feature}/`, levantar libs/serviços, coletar a doc
auxiliar e gerar o plano canônico via MCP dotcontext — deixando o workflow PREVC
pronto para a execução WS a WS.

---

*Plano de finalização — criado em 2026-06-27. Retroalimentado conforme cada
workstream fecha; sincronizar status com o doc 02 a cada WS concluído.*
