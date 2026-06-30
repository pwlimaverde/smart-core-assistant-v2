# Plano Completo — Finalização MVP Operacional

> **Status:** Plano de execução reestruturado e validado contra o código real e a documentação atual de libs/serviços.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** fechar todas as frentes 🚧 e as lacunas da implementação inicial (com destaque para Grafana/observabilidade), levando o produto a um **MVP operacional ponta-a-ponta**.
> **Regra inegociável:** tudo que for implementado **passa pela observabilidade** — emite logs/spans estruturados **e** registra auditoria (ver §1 e a sub-seção "Observabilidade & Auditoria" obrigatória de cada WS).
> **Princípio transversal explícito:** **SOLID + Ports & Adapters** (ver §0 e o reforço por WS).
> **Origem:** `doc_dev/planejamento/15-plano-finalizacao-em-andamento.md` + `info_aux_finalizacao-mvp-operacional.md` + aterramento no código real (este documento).

---

## 0. Princípios SOLID aplicados (transversal — requisito explícito do usuário)

Todo o plano respeita o padrão **Ports & Adapters** já adotado nos `data_*` (plano 14). A regra é única: **casos de uso dependem de traits (ports), não de implementações concretas**, e cada fronteira externa é um adapter substituível.

| Princípio | Como o plano aplica |
|---|---|
| **SRP** (responsabilidade única) | `webhook_ingress` só **autentica + deduplica + publica**; o `worker` **orquestra**; o `data_*` **persiste/integra**. Nenhum binário acumula papéis. Casos de uso isolados (um por arquivo em `application`). |
| **OCP** (aberto/fechado) | Novos provedores de mensageria entram por **novas impls de trait** no `ProviderRegistry` (já existe em `infrastructure_messaging`), sem tocar nos casos de uso. Novo backend de realtime entra por nova impl do port `RealtimeFanout`. |
| **LSP** (substituição) | Adapters intercambiáveis atrás do mesmo port: `RealtimeFanout` via Redis Pub/Sub hoje, outro backend amanhã, sem alterar o handler de stream. O `data_whatsapp` já trata capacidade ausente como `MessagingProviderError::Unsupported` (sem no-op/panic) — manter esse contrato. |
| **ISP** (segregação de interface) | Ports pequenos e específicos. Ex.: separar `IdempotencyStore` (SET NX) de `RealtimeFanout` (pub/sub); não criar um "mega-repo". As capacidades de mensageria já vêm fatiadas (`MessageSender`, `InstanceManager`, `read_receipts()`, `reactions()`, `presence()`...). |
| **DIP** (inversão de dependência) | Casos de uso na crate `application` dependem de `Arc<dyn Trait>` injetado por construtor; `domain_*` **sem I/O**. Os apps de negócio **nunca** importam `infrastructure_*` — falam com os `data_*` por RPC tipado (`transport`). |

> **Ports & adapters por WS:** cada workstream abaixo declara, na sua sub-seção SOLID, **quais ports (traits) novos surgem** e **quais adapters os implementam**.

---

## 1. Contrato de Observabilidade (DoD de TODA tarefa)

Nenhuma tarefa fecha sem cumprir os **três eixos** (a fundação já existe na crate `observability` — este plano a **aplica**, não a reinventa).

### 1.1 Telemetria (logs + traces)
- Boot chama `observability::init_telemetry("<serviço>", "<env>")` (já é padrão em webhook_ingress/worker/runtime_api/data_whatsapp/control_plane — confirmado no código).
- Todo handler/caso de uso novo abre **span** com `tenant_id` (e `trace_id` quando houver) via `observability::tenant_span!` ou `#[tracing::instrument(...)]`.
  - Campos padrão (doc 05 §2/Obs4): `service`, `env`, `tenant_id`, `trace_id`, e `error_code` no caminho de erro (via `error_core::registrar`).
- **Propagação `traceparent` W3C** ponta a ponta: webhook → bus → worker → RPC `data_*`. Reusar `observability::{extrair_contexto, injetar_contexto_atual}` e o campo `traceparent` do `Envelope`/`EventoBruto`/`TenantEnvelope` (padrão já presente em `worker::processar_mensagem_recebida`, linha 91).
- Logs estruturados (`tracing::{info,warn,error}` com campos), nunca string interpolada solta.

### 1.2 Auditoria (negócio + segurança)
- Em produção: `observability::AuditLogger::new_with_redis(conn, "<serviço>")`. Em teste: `new(tenant_pool, admin_pool, "<serviço>")` sob a feature `postgres-audit`.
- API confirmada (`observability/src/audit.rs`): `info/warn/error(tenant_id, event, message, context, user_id, ip_address, trace_id)` (com tenant) e `info_global/warn_global/error_global(...)` (sistema). Publica em `security:stream` via `transport::bus::publicar_evento_seguranca` → consumido pelo `data_postgres` → tabela `audit_log` sob RLS. **Nunca** abrir Postgres direto a partir dos serviços (mantém `infra` desacoplada de `observability` — doc 05 §3).
- **Convenção de nome:** `<dominio>.<acao>` em snake. Registrar no glossário (§7).
- **Metadados mínimos do `audit_log` (doc 08 §4.2):** timestamp UTC (preenchido pelo `data_postgres`), `user_id` do `RequestContext`, `ip_address`, `user_agent`, `event_type`, `description` **sem segredo**. O payload `AuditLogPayload` já carrega `tenant_id`, `level`, `service`, `trace_id`, `event`, `message`, `context`, `user_id`, `ip_address` — **falta `user_agent`** no payload: incluir quando o WS tocar eventos críticos do doc 08 (ver WS-5/WS-7).

### 1.3 Sanitização (doc 05 §6, doc 08 §4)
- **Proibido** logar: token de instância (`apikey`), JWT, refresh token, chaves de API, `ENCRYPTION_KEY`, payload bruto do WhatsApp, telefone completo (mascarar `+55 11 9****-1234`).
- Structs com credencial usam `secrecy::SecretString` (já em `data_whatsapp`/`EvolutionProvider`).

### 1.4 Checklist por PR
- [ ] Span com `tenant_id`/`trace_id` no caminho novo.
- [ ] `traceparent` propagado ao próximo salto (bus/RPC).
- [ ] ≥ 1 evento de auditoria por ação relevante (ou declaração explícita "sem evento de auditoria").
- [ ] Eventos na convenção `<dominio>.<acao>` e documentados no §7.
- [ ] Nenhum segredo em log/auditoria.
- [ ] Caminho de erro também audita (`warn`/`error`).

---

## 2. Estado real consolidado (aterramento no código — base da reestruturação)

| Componente | Arquivo | Estado real confirmado |
|---|---|---|
| **webhook_ingress** | `server/apps/webhook_ingress/src/main.rs` | Normaliza (axum 0.8, rota `{param}`) e publica no bus via `bus::publicar_evento` (l.100). **NÃO valida origem/whitelist/token**; **sem `AuditLogger`**; sem idempotência. |
| **worker** | `server/apps/worker/src/main.rs` | `processar_mensagem_recebida` persiste em **`atendimento_id: 1` fixo** (l.78); **sem `AuditLogger`**; **reconecta cliente RPC por evento** (`transport::conectar_cliente("data_postgres")` dentro do handler, l.74) — `AppState` é vazio. Filtra `event_type == "message.received"` (l.40) — atenção: webhook publica `whatsapp.message.received`. |
| **data_whatsapp** | `server/apps/data_whatsapp/src/main.rs` | Outbound pronto: `SendWhatsappMessage` (l.609) e `SendWhatsappMedia` (l.700); `ProviderRegistry` + `EvolutionProvider` com `SecretString`; já audita instância via `publicar_evento_seguranca`. |
| **runtime_api** | `server/apps/runtime_api/src/{main.rs,audit.rs}` | Login/Refresh/Logout ✅; interceptor `exigir_auth` (l.281) valida JWT + blocklist + guard de superuser. `handler_stream_atendimentos` (l.581) é **forward único** de `ListAtendimentos` — **não é stream**. Faltam Register/Invite/Accept e RBAC fino (`module_permissions`/`flow_permissions`). |
| **control_plane** | `server/apps/control_plane/src/main.rs` | Só `RegisterTenant` (forward p/ `CreateTenant`), `TestEvolutionConnection`, `AdminBulkDisconnect` + CLI superuser. **Faltam CRUD admin** (config/plano/invite/tenant_user) e `TenantConfigCache` plugado. |
| **observability** | `server/crates/observability/src/{lib.rs,audit.rs,span_helpers.rs}` | `init_telemetry`, `AuditLogger::{new,new_with_redis,info,warn,error,*_global}`, macro `tenant_span!`, `extrair_contexto`/`injetar_contexto_atual`. OTel é **0.24** (lib.rs re-exporta `opentelemetry`). |
| **repos a reusar** | `infrastructure_postgres/src/integracoes/{whitelist.rs,whatsapp.rs}`, `clientes/`, `atendimentos/`, `tenants/` | `WhiteListRepository::esta_na_lista` (whitelist.rs l.31) e `WhatsappInstanceRepository::{buscar_por_id,buscar_por_instance_id}` (whatsapp.rs l.185/207, coluna `api_key`). **Não existe** `integracoes/evolution.rs** — o plano base citava errado; a verdade é `whatsapp.rs`. |
| **messaging** | `infrastructure_evolution/`, `infrastructure_messaging/` | `ProviderRegistry`, `MessagingProvider`, `MessageSender`, `InstanceManager` etc. — usados pelo `data_whatsapp`. |
| **bus** | `transport/src/bus.rs` | `STREAM_EVENTOS = "events:stream"`, `STREAM_SEGURANCA = "security:stream"`, `publicar_evento`, `publicar_evento_seguranca`, `Consumer`, `consumir`. |
| **messaging_gateway** | (arquitetura doc, §System Overview) | **Órfão** — papel migrou para `webhook_ingress`/`data_whatsapp`. **Descomissionar** (WS-0). |

---

## 3. Workstreams

```
WS-0 Observabilidade + Grafana LGTM (fundação transversal)
       ├──► WS-1 webhook_ingress: auth + whitelist + idempotência
       │            └──► WS-2 worker: orquestração de atendimento
       │                       └──► WS-3 outbound: worker → data_whatsapp
       │                                  └──► WS-4 realtime: stream real por tenant (tonic + Redis Pub/Sub)
       │                                             └──► WS-6 telas operacionais Flutter
       ├──► WS-5 runtime_api: Register/Invite/Accept + comandos + RBAC
       └──► WS-7 control_plane CRUD + TenantConfigCache + telas admin
```

---

### WS-0 — Observabilidade transversal + Grafana LGTM *(devops-4 / F9.1)*

**Estado atual real:** `init_telemetry` já roda em todos os binários. **Falta** a stack LGTM (`docker/compose/observability.yml`) e o `AuditLogger` plugado em `worker` (0 auditoria) e `webhook_ingress` (0 auditoria). O lado Rust de OTel já está implementado na crate `observability` em **0.24** (não há nada a reescrever no Rust aqui).

#### Tarefas
1. **WS-0.1 — Stack LGTM** (`docker/compose/observability.yml` + `docker/observability/`).
   - **Fase dev:** imagem all-in-one `grafana/otel-lgtm` (valida o pipeline em minutos). **Fase prod:** stack separada (OTel Collector + Loki + Tempo + Prometheus + Grafana).
   - `otel-collector-config.yaml` (recebe OTLP gRPC `:4317` / HTTP `:4318`; exporta traces→Tempo, logs→Loki OTLP nativo, métricas→Prometheus remote-write):
     ```yaml
     receivers:
       otlp:
         protocols:
           grpc: { endpoint: 0.0.0.0:4317 }
           http: { endpoint: 0.0.0.0:4318 }
     processors:
       memory_limiter: { check_interval: 1s, limit_mib: 512 }
       batch: { send_batch_size: 512, timeout: 5s }
     exporters:
       otlp/tempo:            { endpoint: tempo:4317, tls: { insecure: true } }
       otlphttp/loki:         { endpoint: http://loki:3100/otlp, tls: { insecure: true } }
       prometheusremotewrite: { endpoint: http://prometheus:9090/api/v1/write }
     service:
       pipelines:
         traces:  { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlp/tempo] }
         logs:    { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp/loki] }
         metrics: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [prometheusremotewrite] }
     ```
   - Datasources provisionados com **correlação trace↔logs** (Loki `derivedFields` regex `trace_id` → Tempo `tempo-uid`; Tempo `tracesToLogs` → `loki-uid`).
   - **Gotchas:** Loki 3.x exige `allow_structured_metadata: true` e recebe OTLP nativo em `/otlp` (dispensa Promtail; Promtail/Agent depreciados → Alloy se precisar). Prometheus com `--storage.tsdb.retention.time=30d --web.enable-lifecycle`. `GF_SECURITY_ADMIN_PASSWORD` em prod. `memory_limiter` é crítico (OOM na KVM2).
   - Expor `grafana.smartcoreassistant.com.br` via **Caddy** (`reverse_proxy localhost:3000`, `X-Forwarded-Proto/Host`).
   - Variáveis `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` nos `.env` de dev/prod.
   - **Re-confirmar no deploy** apenas as **tags de imagem** (o resto é fixo).
2. **WS-0.2 — Plugar `AuditLogger` onde falta.**
   - `worker/src/main.rs`: criar `ConnectionManager` do bus no boot e `AuditLogger::new_with_redis(bus, "worker")`; injetar no `AppState` (hoje vazio).
   - `webhook_ingress/src/main.rs`: idem (`AuditLogger::new_with_redis(state.redis.clone(), "webhook_ingress")` reusando o `ConnectionManager` já existente em `AppState`).
   - **Descomissionar `messaging_gateway`**: remover do workspace/compose/`target`; registrar a decisão (o papel está em `webhook_ingress` + `data_whatsapp`).
3. **WS-0.3 — Cadeia de trace de ponta a ponta.** Teste de integração que segue um `trace_id` do webhook → bus → worker → `audit_log`.
4. **WS-0.4 — Métricas de pool** (feature `pool-metrics` já existe): ligar em `data_postgres`/`data_redis` e expor ao Prometheus via Collector.

#### Observabilidade & Auditoria
- **Logs/traces:** habilitar o OTLP exporter contra o Collector; confirmar campos `service/env/tenant_id/trace_id` nos logs JSON de ≥ 2 serviços.
- **Auditoria:** WS-0 **não emite evento de negócio próprio** — ele **habilita** a auditoria dos demais WS. *Sem evento de auditoria intencional* (é fundação).
- **Sanitização:** nenhum segredo nos dashboards/labels; portas do Collector/Loki/Prometheus/Tempo **não expostas** (rede Docker interna).

#### SOLID
- **Ports novos:** nenhum no Rust (a infra de telemetria já está pronta). **Adapters:** o Collector é o adapter de saída neutro (OCP — trocar Tempo/Loki sem mexer no app).

#### DoD
- `docker compose -f docker/compose/observability.yml up -d` saudável.
- Webhook de teste gera **trace contínuo** (Tempo) + **logs** (Loki) + **linha em `audit_log`** correlacionados pelo mesmo `trace_id`.
- Dashboards com dados reais de ≥ 2 serviços. `messaging_gateway` removido. `cargo clippy -D warnings` + `.\infra\test-local.ps1` verdes.

---

### WS-1 — `webhook_ingress`: autenticação + whitelist + idempotência *(F3.4)*

**Estado atual real:** `handle_webhook` (main.rs l.79) parseia, normaliza e publica **sem validar a origem**. O token chega no payload Evolution Go como `apikey`/`instanceToken` (l.229 do normalizador). Não há dedupe.

#### Tarefas (ordem de implementação)
1. **WS-1.1 — Autenticação da origem.** Antes de publicar, validar o token de instância contra o banco via RPC ao `data_postgres`.
   - **Novo RPC no `data_postgres`:** `VerifyWhatsappInstanceToken { tenant_id, instance_id, token }` → usa `WhatsappInstanceRepository::buscar_por_id` (whatsapp.rs l.185) e **compara** o `api_key` armazenado com o token recebido (comparação em tempo constante). Retorna `{ valid: bool, phone_number? }`. (Não existe `buscar_por_token`; reusar `buscar_por_id` pelo `instance_id` do path é o caminho correto e usa o índice `(tenant_id, id)`.)
   - Carregar o token recebido em `secrecy::SecretString` no webhook (nunca logar).
2. **WS-1.2 — Whitelist (quando aplicável a MESSAGE inbound).** RPC `IsPhoneWhitelisted { tenant_id, phone_number }` → `WhiteListRepository::esta_na_lista` (whitelist.rs l.31). Se o tenant exige whitelist e o remetente não está, rejeitar.
3. **WS-1.3 — Idempotência.** Deduplicar por `message_id`/`stanzaId` (extraído de `data.key.id`) com **`SET tenant:<uuid>:webhook:dedup:<msg_id> 1 NX EX <ttl>`** no `data_redis` (RPC ou conexão de bus). Se a chave já existe → `webhook.duplicated` e **não** publica.
4. **WS-1.4 — Rejeição segura.** Token inválido → `401`; fora da whitelist → `403`; **sem** publicar no bus em nenhum dos casos.

> **Arquivos:** `webhook_ingress/src/main.rs` (handler), novo módulo `webhook_ingress/src/auth.rs` (validação) e `webhook_ingress/src/dedup.rs` (idempotência); novos handlers no `data_postgres` (`VerifyWhatsappInstanceToken`, `IsPhoneWhitelisted`) — repositórios já existem.

#### Observabilidade & Auditoria
- **Logs/traces:** o span `handle_webhook` já existe (`#[tracing::instrument]`, l.70) com `provider/tenant_id/instance_id/event_type`. **Semear `traceparent`** aqui via `injetar_contexto_atual` no `TenantEnvelope` publicado (hoje não há). Mascarar telefone; nunca logar `apikey`.
- **Auditoria:** `webhook.received` (INFO), `webhook.rejected` (WARN — motivo: `invalid_token`/`not_whitelisted`, **sem** o token no contexto), `webhook.duplicated` (INFO). Via `AuditLogger` plugado no WS-0.2.
- **Sanitização:** token em `SecretString`; contexto de auditoria carrega apenas `instance_id`, motivo e telefone mascarado.

#### SOLID
- **Ports novos:** `OriginAuthenticator` (valida token/whitelist) e `IdempotencyStore` (`already_seen(key) -> bool` via SET NX). **Adapters:** `RpcOriginAuthenticator` (fala com `data_postgres`), `RedisIdempotencyStore` (fala com `data_redis`). SRP: o webhook **só** autentica+deduplica+publica. ISP: dois ports pequenos, não um "mega-validador".

#### DoD
- Token válido + (whitelist ok) → evento no bus; inválido → `401` auditado; fora da whitelist → `403` auditado; duplicado → ignorado e auditado. Testes cobrindo os 4 casos. `clippy -D warnings` + `.\infra\test-local.ps1`.

---

### WS-2 — `worker`: orquestração de atendimento *(F3.2 / F4.1–4.3, 4.5)*

**Estado atual real:** `processar_mensagem_recebida` persiste em `atendimento_id: 1` fixo (l.78), reconecta o cliente RPC por evento (l.74), e o `AppState` é vazio. Filtra `event_type == "message.received"` (l.40) — **corrigir** para casar com o tópico real publicado pelo webhook (`whatsapp.message.received`).

#### Tarefas (ordem)
1. **WS-2.6 (primeiro — bootstrap) — Cliente RPC no estado.** Conectar `data_postgres`/`data_redis` **uma vez** no `main` e guardar em `AppState` (clones `Arc`), eliminando o `conectar_cliente` por evento. Plugar o `AuditLogger` (do WS-0.2).
2. **WS-2.1 — `domain_whatsapp` (normalização, sem I/O).** Crate `crates/domain_whatsapp`: mapeamento por chave JSON (`imageMessage`/`audioMessage`/… → `media_type`), reply/`stanzaId`, extração de `sender`/`pushName`. Regra pura (DIP: `domain_*` sem I/O).
3. **WS-2.2 — Resolução contato → atendimento.** Caso de uso em `application` que, via RPC `data_postgres`: localiza/cria contato (`clientes/`), resolve **atendimento aberto** do contato ou abre um (`atendimentos/`), substituindo o `atendimento_id` fixo. Novo RPC `ResolveAtendimentoParaContato { tenant_id, phone, push_name }` no `data_postgres` (reusa repositórios existentes em transação RLS).
4. **WS-2.3 — Debounce por contato.** Agrupar rajada com lock **`SET tenant:<uuid>:lock:debounce:<contato> 1 NX EX <ttl>`** no `data_redis` (assinatura confirmada redis 0.25). Janela curta antes de processar.
5. **WS-2.4 — Políticas de ticket + Kanban.** Casos de uso `DecideTicketPolicy` e `ApplyKanbanStage` (mover estágio conforme evento).
6. **WS-2.5 — Barreira de bot (sem LLM).** `BotRulesEngine::can_bot_respond` (flag `bot_pode_atender`, sem humano ativo) → resposta temporária. **Ponto de extensão futuro** para o `ia_engine` (F5) via novo adapter (OCP).

> **Arquivos:** `worker/src/main.rs` (AppState + dispatch), nova crate `crates/domain_whatsapp`, novos casos de uso em `crates/application` (`receive_message.rs`, `resolve_atendimento.rs`, `decide_ticket_policy.rs`, `apply_kanban_stage.rs`, `bot_rules.rs`), novos RPC no `data_postgres`.

#### Observabilidade & Auditoria
- **Logs/traces:** span por etapa (`resolver_atendimento`, `aplicar_debounce`, `decidir_ticket`, `aplicar_kanban`, `avaliar_bot`) com `tenant_id`/`trace_id` via `tenant_span!`. **Propagar `traceparent`** (já presente em l.91) em cada RPC.
- **Auditoria:** `atendimento.aberto` / `atendimento.reaberto`, `mensagem.persistida`, `ticket.transicionado`, `kanban.movido`, `bot.respondeu` / `bot.silenciado` (INFO). Caminho de erro: `mensagem.falha_persistencia` (ERROR).
- **Sanitização:** conteúdo da mensagem **não** vai para auditoria/log INFO; telefone mascarado.

#### SOLID
- **Ports novos:** `ContatoAtendimentoResolver`, `DebounceLock`, `TicketPolicy`, `KanbanStageMover`, `BotPolicy`. **Adapters:** impls RPC (`data_postgres`) e Redis (`data_redis`) injetadas no `AppState`. **OCP:** `BotPolicy` permite plugar o `ia_engine` depois sem alterar o orquestrador. **DIP:** orquestrador depende de `Arc<dyn Trait>`; `domain_whatsapp` sem I/O.

#### DoD
- 2 mensagens do mesmo contato em rajada → **1** atendimento, debounce aplicado, estágio de Kanban correto, tudo **auditado**. Cliente RPC reusado (sem reconexão por evento). Testes de integração contra `data_postgres`/`data_redis` reais (`test_support`). `clippy -D warnings` + `.\infra\test-local.ps1`.

---

### WS-3 — Envio outbound *(F4.4)*

**Estado atual real:** `data_whatsapp::SendWhatsappMessage`/`SendWhatsappMedia` prontos (main.rs l.609/700). O `worker` ainda **não** os chama.

#### Tarefas
1. **WS-3.1 — Caso de uso de envio** em `application` (`send_outbound_message.rs`): RPC `data_whatsapp::SendWhatsappMessage` com **retry + backoff** (resiliência a falha transitória do provedor). Resolve `instance_id` (db) do atendimento.
2. **WS-3.2 — Confirmações.** Consumir `whatsapp.message.status` (já publicado pelo webhook via `MESSAGE_UPDATE`) e refletir status de entrega/leitura no atendimento (RPC `data_postgres`).

> **Arquivos:** `crates/application/src/.../send_outbound_message.rs`, dispatch no `worker/src/main.rs`.

#### Observabilidade & Auditoria
- **Logs/traces:** span `enviar_mensagem` com `tenant_id`/`trace_id`; propagar `traceparent` ao `data_whatsapp`.
- **Auditoria:** `mensagem.enviada` (INFO), `mensagem.falha_envio` (WARN — tentativa/causa, sem corpo), `mensagem.confirmada` (INFO).
- **Sanitização:** sem corpo da mensagem em log INFO; telefone mascarado.

#### SOLID
- **Port novo:** `OutboundSender::send_text/send_media`. **Adapter:** `RpcOutboundSender` (fala com `data_whatsapp`, que por sua vez usa `ProviderRegistry`). **OCP:** trocar provedor é trocar a impl no registry, sem tocar no caso de uso.

#### DoD
- Resposta sai pelo gateway com retry resiliente; envio/falha/confirmação **auditados**; testes contra `data_whatsapp` stub. `clippy -D warnings` + `.\infra\test-local.ps1`.

---

### WS-4 — Realtime: stream real por tenant *(F6.2)*

**Estado atual real:** `handler_stream_atendimentos` (runtime_api/main.rs l.581) faz **um** `ListAtendimentos` e retorna — **não é stream**. Falta fan-out.

#### Tarefas
1. **WS-4.1 — Stream gRPC server-streaming (tonic 0.14.6).** RPC `StreamAtendimentos(Req) returns (stream AtendimentoEvent)` no contrato. `tonic-build` gera `type StreamAtendimentosStream: Stream<Item=Result<Msg,Status>>`. Padrão: canal `tokio::sync::mpsc` + `tokio_stream::wrappers::ReceiverStream`. **JWT validado na abertura** pelo mesmo interceptor das unárias (injeta contexto em `request.extensions_mut()`; `Status::unauthenticated`/`Status::permission_denied`).
2. **WS-4.2 — Fan-out por tenant via Redis Pub/Sub (redis 0.25).** Cada réplica mantém **um subscriber por canal de tenant** numa `tokio::spawn`; faz fan-out interno via `tokio::sync::broadcast` para os N streams gRPC abertos daquele tenant naquela réplica. **API 0.25 (NÃO 1.0):**
   ```rust
   // Subscriber — conexão DEDICADA (bloqueante, não multiplexável)
   let con = client.get_async_connection().await?;
   let mut pubsub = con.into_pubsub();
   pubsub.subscribe(format!("tenant:{tenant_id}:events")).await?;
   let mut stream = pubsub.on_message();            // impl Stream<Item = redis::Msg>
   while let Some(msg) = stream.next().await {       // futures::StreamExt
       let payload: String = msg.get_payload()?;
       // broadcast.send(evento) → streams gRPC abertos
   }

   // Publisher — MultiplexedConnection (clonável). NUNCA a mesma conexão do subscribe.
   let mut con = client.get_multiplexed_async_connection().await?;
   let _n: u32 = con.publish(format!("tenant:{tenant_id}:events"), payload).await?;
   ```
   - `broadcast` lagged (`BroadcastStreamRecvError::Lagged`) → encerrar stream com `Status::resource_exhausted`.
   - O **publisher** é o `worker` (ao persistir mensagem/typing/kanban) usando `MultiplexedConnection`.
3. **WS-4.3 — `tonic-web 0.14.1`** habilitado para o futuro port Web: `Server::builder().accept_http1(true).layer(GrpcWebLayer::new())` + `CorsLayer` expondo `grpc-status`/`grpc-message`. Server streaming **é** suportado em gRPC-Web.

> **Arquivos:** `runtime_api/src/main.rs` (handler real de stream), novo `runtime_api/src/realtime.rs` (subscriber + broadcast registry), contrato em `crates/contracts` (`.proto` do `AtendimentoEvent`), publisher no `worker`.

#### Observabilidade & Auditoria
- **Logs/traces:** span `stream_atendimentos` por conexão com `tenant_id`/`trace_id`.
- **Auditoria:** `stream.aberto` (INFO), `stream.fechado` (INFO), `stream.nao_autorizado` (WARN). Reusar `publicar_auditoria_borda` (audit.rs).
- **Sanitização:** eventos de realtime não carregam segredos; isolamento por canal `tenant:<uuid>:events`.

#### SOLID
- **Port novo:** `RealtimeFanout::{subscribe(tenant) -> Stream, publish(tenant, event)}`. **Adapter:** `RedisPubSubFanout` (hoje); **LSP** garante outro backend amanhã sem tocar no handler. **ISP:** separar `RealtimeSubscriber` de `RealtimePublisher` (publisher vive no worker; subscriber no runtime_api).

#### DoD
- 2 clientes do mesmo tenant recebem o mesmo evento em tempo real; cliente de outro tenant **não** recebe (isolamento). Auditado e testado (multi-réplica atrás de feature flag — ver Riscos). `clippy -D warnings` + `.\infra\test-local.ps1`.

---

### WS-5 — `runtime_api`: Register/Invite/Accept + comandos + RBAC *(F6.1 / F6.3)*

**Estado atual real:** Login/Refresh/Logout ✅ (main.rs l.398/477/520); interceptor `exigir_auth` (l.281) com JWT + blocklist + guard de superuser; `handler_admin_forward` (l.612) é o padrão de forward autenticado. **Faltam** Register/Invite/Accept e RBAC fino (`module_permissions`/`flow_permissions`).

#### Tarefas
1. **WS-5.1 — Register / Invite / Accept.**
   - `RegisterTenant` (forward p/ control_plane/`data_postgres`), `CreateInvite` (token via `OsRng`, ≥ 64 chars, `expires_at` 7 dias — doc 08 §5.1), `AcceptInvite` (transação que marca `used=true` e cria `TenantUser`; reuso → `410 Gone`).
2. **WS-5.2 — Comandos de leitura.** Tickets, kanban, histórico via `handler_admin_forward` autenticado ao `data_postgres`. Kanban filtra por `flow_permissions` do `RequestContext` (doc 08 §5.2).
3. **WS-5.3 — RBAC completo (defesa em 3 camadas).** (1) interceptor extrai escopos do JWT (já faz `auth_scopes`); (2) `RequestContext` no `data_postgres` valida `module_permissions`/`flow_permissions` (`ctx.has_permission("clientes:write")` — doc 08 §5.2, padrão já usado em whitelist.rs l.58); (3) RLS no banco. Estender `RequestContext` com `flow_permissions: Vec<i32>` carregado no middleware.

> **Arquivos:** `runtime_api/src/main.rs` (novas rotas), `crates/application/src/auth/{register.rs,invite.rs,accept.rs}`, novos RPC no `data_postgres`, `infrastructure_postgres/src/security.rs` (`RequestContext` + `flow_permissions`).

#### Observabilidade & Auditoria (eventos críticos do doc 08 §4.2 — OBRIGATÓRIOS)
- **Auditoria:** `tenant.registrado` (criação de Tenant/`owner_id`), `convite.enviado` / `convite.aceito` / `convite.expirado` (TenantInvite), `tenant_user.role_change` (mudança de permissões — TenantUser), `autorizacao.negada` (WARN, RBAC barrou). **Incluir `user_agent`** e `ip_address` no contexto (doc 08 §4.2 exige). Descrição **sem segredo** (nunca o token do convite).
- **Logs/traces:** span por handler; `traceparent` propagado.
- **Sanitização:** token de convite em `SecretString`/`OsRng`, nunca logado nem auditado em claro.

#### SOLID
- **Ports novos:** `InviteService`, `RbacGuard`. **Adapters:** impls RPC ao `data_postgres`. **SRP:** cada caso de uso (register/invite/accept) em arquivo próprio. **DIP:** handlers dependem de `AuthDeps`/traits, não de SQL.

#### DoD
- Cadastro/convite ponta a ponta; reuso de convite → `410`; chamada sem escopo → negada e **auditada** com `user_agent`/`ip`. `clippy -D warnings` + `.\infra\test-local.ps1`.

---

### WS-6 — Telas operacionais Flutter *(F4.6)* — consome WS-3/WS-4

**Estado atual real:** app `smart-core-admin` com login pronto; faltam telas operacionais.

#### Tarefas
1. **WS-6.1 — Fila por departamento + Kanban (drag-and-drop)** no `smart-core-admin`, componentes em `design_system_module`. (Avaliar `appflowy_board`; **sem doc local** — criar doc se adotado.)
2. **WS-6.2 — Chat lateral** consumindo **server streaming** (WS-4) via `api_client` (`grpc` dart, `ResponseStream`; `GrpcWebClientChannel` no Web futuro), com envio outbound (WS-3). Stores reativos com `flutter_bloc`.
3. **WS-6.3 — `DataSource` abstrato (RemoteOnly)** desde já (garante port Web/F10). DI via `get_it`; navegação/guarda de sessão com `go_router`; refresh token em `flutter_secure_storage`.

#### Observabilidade & Auditoria
- **Logs/traces:** o cliente propaga `traceparent` nas chamadas; logs de erro de UI sem PII.
- **Auditoria:** *sem evento de auditoria próprio do cliente* (intencional — auditoria é server-side). As ações disparam eventos auditados no `runtime_api`/`worker`.

#### SOLID
- **Port (Dart):** `AtendimentoDataSource` (RemoteOnly hoje, LocalEngineFFI no F8). **LSP:** trocar a fonte sem mudar a tela. **DIP:** telas dependem da abstração via `get_it`.

#### DoD
- Mover card e enviar/receber mensagem em tempo real **contra o `runtime_api` real** (não mock); `flutter analyze` limpo via `.\infra\test-flutter.ps1`.

---

### WS-7 — Control Plane CRUD + `TenantConfigCache` + telas admin *(F2.2b/2.3/2.5)*

**Estado atual real:** `control_plane` só `RegisterTenant`/`TestEvolutionConnection`/`AdminBulkDisconnect` + CLI superuser (main.rs). `TenantConfigCache` implementado/testado mas **não plugado**.

#### Tarefas
1. **WS-7.1 — CRUD admin** no `control_plane` (gRPC de administração que forward para `data_postgres`, que detém os repositórios): tenant, config, plano/assinatura (`Subscription`/`PaymentRecord`), `tenant_user`/`invite`.
2. **WS-7.2 — `TenantConfigCache` plugado.** Instanciar nos consumidores; rotas RPC de leitura/escrita de config; **assinante de invalidação via Redis Pub/Sub** (canal `core:settings:invalidate`) usando a **API 0.25** (`into_pubsub()` + `on_message()`), simétrico ao WS-4.
3. **WS-7.3 — Telas admin** (`admin_module`): tenants, planos/assinatura, convites (consome o `control_plane`).

> **Arquivos:** `control_plane/src/main.rs` (rotas CRUD), `control_plane/src/config_cache.rs` (subscriber de invalidação), novos RPC no `data_postgres`, telas em `admin_module`.

#### Observabilidade & Auditoria (eventos críticos do doc 08 §4.2 — OBRIGATÓRIOS)
- **Auditoria:** `tenant.criado` / `tenant.atualizado` (incluindo troca de `owner_id`), `plano.alterado` (Subscription), `pagamento.lancado` (PaymentRecord manual), `config.atualizada` / `api_key.update` (chaves de API do TenantConfig — **descrição sem o segredo**, ex.: "Chave Groq atualizada"), `config.invalidada`. **Operações administrativas SEMPRE auditadas**, com `user_id`/`ip_address`/`user_agent`.
- **Logs/traces:** span por handler com `tenant_id`/`trace_id`.
- **Sanitização:** chaves de API criptografadas (AES-256-GCM, doc 08 §2) **antes** do banco; `SecretString` em trânsito; nunca em log/auditoria.

#### SOLID
- **Ports novos:** `TenantAdminRepository` (CRUD via RPC), `ConfigInvalidationSubscriber`. **Adapters:** RPC `data_postgres` + Redis Pub/Sub. **OCP:** novo backend de cache/invalidação sem tocar nos consumidores. **DIP:** consumidores dependem do `TenantConfigCache` (trait), não da impl Redis.

#### DoD
- Alterar config via RPC reflete nos consumidores **sem restart** (invalidação funcionando) e fica **auditado**; telas admin operam contra o `control_plane` real. `clippy -D warnings` + `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1`.

---

## 4. Correções aplicadas (plano base → correção → fonte)

| Item do plano base | Correção aplicada | Fonte |
|---|---|---|
| `tonic-web = "0.12"` | **0.14.1** (versão real do workspace) | info_aux §tonic (Cargo.toml); WS-4.3 |
| Redis Pub/Sub API "moderna" (`get_async_pubsub()`/`split()`, redis ≥1.0) | **redis 0.25**: `get_async_connection().into_pubsub()` + `on_message()` + `get_payload()`; publish via `get_multiplexed_async_connection()` | info_aux §"API externa: Redis Pub/Sub 0.25"; WS-4.2 |
| OTel `0.22` + `new_pipeline()` sugerido pelo subagente LGTM | **OTel 0.24** já implementado na crate `observability` (lib.rs re-exporta `opentelemetry`); ignorar a 0.22 | info_aux §opentelemetry (⚠️); `observability/src/lib.rs` |
| Realtime "stream" | É **forward único** hoje (`handler_stream_atendimentos` faz um `ListAtendimentos` e retorna); WS-4 implementa server streaming real | `runtime_api/src/main.rs` l.581 |
| Worker reusa conexões | Hoje **reconecta cliente RPC por evento** (`conectar_cliente` dentro do handler, `AppState` vazio); corrigido em WS-2.6 (cliente no estado) | `worker/src/main.rs` l.74 |
| `messaging_gateway` instrumentar | **Órfão** — papel migrou para `webhook_ingress`/`data_whatsapp`; **descomissionar** (não instrumentar) | arquitetura doc §System Overview; WS-0.2 |
| WS-1 validar contra `integracoes/evolution.rs` | **Não existe** `evolution.rs`; a verdade é `integracoes/whatsapp.rs` (coluna `api_key`, `buscar_por_id`/`buscar_por_instance_id`) + `whitelist.rs` (`esta_na_lista`) | `infrastructure_postgres/src/integracoes/{whatsapp.rs,whitelist.rs}` |
| Worker filtra `event_type == "message.received"` | Tópico real publicado pelo webhook é `whatsapp.message.received`; alinhar o dispatch do worker | `webhook_ingress/src/main.rs` l.272; `worker/src/main.rs` l.40 |
| Auditoria "metadados mínimos" | `AuditLogPayload` **não tem `user_agent`** (exigido pelo doc 08 §4.2); incluir nos WS que tocam eventos críticos (WS-5/WS-7) | `observability/src/audit.rs`; doc 08 §4.2 |
| `idempotência/debounce` genéricos | Especificados com a sintaxe real **`SET ... NX EX`** namespaced por tenant (`tenant:<uuid>:...`) da redis 0.25 | info_aux §redis 0.25; WS-1.3/WS-2.3 |

---

## 5. Cronograma (mapeado em S0.5–S9, herdado do doc 02 / plano base)

| Sprint | Janela | Workstreams | Marco |
|---|---|---|---|
| **S0.5** | 30/jun – 11/jul | **WS-0** (obs + Grafana LGTM) | Tudo nasce instrumentado/auditado; Grafana no ar; `messaging_gateway` removido |
| **S1** | (sobrepõe) | **WS-1** (webhook auth + idempotência) | Ingestão confiável e auditada |
| **S2–S3** | 14/jul – 08/ago | **WS-2** (orquestração worker) | Contato→atendimento real (fim do `atendimento_id` fixo) |
| **S4** | 11/ago – 22/ago | **WS-3 + WS-4** (outbound + realtime) | Resposta sai + stream por tenant |
| **S5** | 25/ago – 05/set | **WS-6** (telas operacionais) | **MVP ponta-a-ponta** |
| **S6** | 08/set – 19/set | **WS-7** (control plane + admin) | Back office operacional |
| **S7** | 22/set – 03/out | **WS-5** (Register/Invite + comandos + RBAC) | API cliente completa + RBAC |
| **S8–S9** | 06/out – 31/out | Endurecimento + consolidação | Dashboards/alertas + F7 |

> **WS-0 abre e roda em paralelo ao WS-1.** Caminho crítico: **WS-2** (alimenta WS-3/WS-4/WS-6). Marco de MVP na **S5**.

---

## 6. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| WS-2 (contato→atendimento) escorrega | Empurra MVP (S5) e UI | Atacar 1º; fatiar em WS-2.6→2.2→2.3 entregáveis |
| Fan-out realtime multi-réplica (WS-4) | Complexidade de sincronização | Começar single-réplica; Pub/Sub atrás de feature flag; lagged → `resource_exhausted` |
| Auditoria assíncrona perde evento se Redis cai | Lacuna de trilha | Já há `tracing::error` no fallback (audit.rs l.102); monitorar profundidade do `security:stream` no Grafana |
| `messaging_gateway` órfão | Confusão de responsabilidade | Descomissionar em WS-0.2 e documentar |
| Comparação de token de instância | Timing attack | Comparação em tempo constante; token em `SecretString` |
| Ambiente remoto/túnel instável | Trava integração | `test_support` (sobe túnel SSH + `SQLX_OFFLINE`) + reset de schema; smoke após deploy dev |
| `redis 0.25`: subscribe e publish na mesma conexão | Deadlock/erro | Conexão **dedicada** para subscribe, **multiplexed** para publish (regra do info_aux) |

---

## 7. Estratégia de testes (por WS)

- **Rust:** sempre via **`.\infra\test-local.ps1`** (nunca `cargo test` direto — sobe túnel via `test_support` + `SQLX_OFFLINE`). Integração contra Postgres/Redis reais; `#[sqlx::test]` com transação+rollback onde couber. Cada WS adiciona testes de **isolamento multi-tenant** para tabelas/canais novos.
- **Flutter:** via **`.\infra\test-flutter.ps1`**; telas exercitam o fluxo real contra o `runtime_api` (não mock).
- **Observabilidade (gate da fundação):** teste ponta-a-ponta seguindo um `trace_id` do webhook ao `audit_log` (WS-0.3).
- **DoD comum a todo WS:** compila + `cargo clippy -D warnings` + testes verdes + observabilidade/auditoria cumpridas.

---

## 8. Glossário de eventos de auditoria (vivo — herdado e completado)

> Convenção `<dominio>.<acao>` em snake. Descrição **sem segredo**.

| Evento | Nível | Quando | WS |
|---|---|---|---|
| `webhook.received` | INFO | Webhook autenticado aceito | WS-1 |
| `webhook.rejected` | WARN | Token inválido ou fora da whitelist (motivo no contexto, sem token) | WS-1 |
| `webhook.duplicated` | INFO | `message_id`/`stanzaId` já visto (dedup SET NX) | WS-1 |
| `atendimento.aberto` / `.reaberto` | INFO | Atendimento resolvido/aberto para o contato | WS-2 |
| `mensagem.persistida` | INFO | Mensagem gravada no atendimento | WS-2 |
| `mensagem.falha_persistencia` | ERROR | Falha ao gravar | WS-2 |
| `ticket.transicionado` / `kanban.movido` | INFO | Mudança de estágio | WS-2 |
| `bot.respondeu` / `bot.silenciado` | INFO | Barreira de bot | WS-2 |
| `mensagem.enviada` / `.falha_envio` / `.confirmada` | INFO/WARN/INFO | Outbound (causa na falha, sem corpo) | WS-3 |
| `stream.aberto` / `.fechado` / `.nao_autorizado` | INFO/INFO/WARN | Realtime por tenant | WS-4 |
| `tenant.registrado` | INFO | Cadastro de tenant (`owner_id`) | WS-5 |
| `convite.enviado` / `.aceito` / `.expirado` | INFO | TenantInvite (sem token em claro) | WS-5 |
| `tenant_user.role_change` | WARN | Mudança de cargo/permissões (TenantUser) | WS-5/WS-7 |
| `autorizacao.negada` | WARN | RBAC barrou (escopo/flow insuficiente) | WS-5 |
| `tenant.criado` / `.atualizado` | INFO | Control plane (inclui troca de `owner_id`) | WS-7 |
| `plano.alterado` / `pagamento.lancado` | INFO | Subscription / PaymentRecord manual | WS-7 |
| `api_key.update` / `config.atualizada` / `config.invalidada` | INFO | Chaves do TenantConfig / config (descrição sem o segredo) | WS-7 |
| `login_success` / `login_rate_limited` / `logout` / `token_reuse_detected` | INFO/WARN/INFO/WARN | Borda de auth (já implementados) | — |

> **Eventos críticos obrigatórios do doc 08 §4.2** estão cobertos: Tenant/`owner_id` (WS-5/WS-7), TenantInvite (WS-5), TenantUser/permissões (WS-5/WS-7), Subscription/PaymentRecord (WS-7), chaves de API do TenantConfig (WS-7). Todos com `user_id`, `ip_address` e `user_agent` no contexto.

---

## 9. Próximo passo de canonização

Plano completo escrito. A canonização via MCP dotcontext (`scaffoldPlan` + `workflow-init`) referencia este arquivo e o `info_aux`, deixando o workflow PREVC pronto para a execução WS a WS.

---

*Plano reestruturado e validado contra o código real e a doc atual de libs/serviços. Retroalimentado conforme cada WS fecha; sincronizar status com o doc 02.*
