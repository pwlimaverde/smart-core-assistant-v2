# Changelog - Smart Core Assistant v2

Histórico de alterações do projeto com base no ciclo PREVC.

## [2026-07-09] - Fase N1: Fechamento do MVP + Scheduler do Worker

> Ciclo PREVC `n1-fechamento-mvp-scheduler` fechado e arquivado via `prevc-final-review`.
> Final-review: qualidade **CONFORME** (nenhuma correção necessária). Fecha a única lacuna
> estrutural remanescente da F4 (scheduler temporal do worker) e o elo outbox→outbound do
> atendente; provisiona observabilidade (dashboards + alertas Grafana) como código.

### Adicionado

- **Scheduler temporal do `worker` (F4.3b):** `worker/src/scheduler.rs` novo — loop
  `tokio::spawn` + `tokio::time::interval` (default 60s, configurável via
  `SMARTCORE_SCHEDULER_TICK_SECS`) paralelo ao consumidor do bus. Port `Clock`
  (`SystemClock`) para tempo injetável. Duas tarefas, cada uma sob lock Redis
  cross-tenant `SET NX PX` (`scheduler:lock:feedback_timeout` / `:media_purge`):
  timeout de feedback vencido (transiciona e audita `atendimento.feedback_expirado`)
  e disparo de purga de mídia expirada (publica `media.purge` no bus, já consumido
  pelo `data_storage`).
- **Migração `0014_scheduler_idempotencia.sql`:** colunas `feedback_expirado_em`
  (`oraculo_atendimento`) e `midia_purgada_em` (`oraculo_mensagem`) + índices
  parciais, garantindo que 2 ticks seguidos não dupliquem efeito.
- **RPCs de varredura no `data_postgres`:** `ListarAtendimentosFeedbackVencido`,
  `MarcarFeedbackExpirado`, `ListarMidiasExpiradas`, `MarcarMidiaPurgada` — as duas
  varreduras são cross-tenant via `admin_pool` (BYPASSRLS), mesmo padrão de
  `AdminListAllConnectedInstances`.
- **Elo outbox → outbound do atendente (WS-6.3 / N1.3):** worker consome
  `message.persisted` (já drenado pelo `OutboxRelay`) e, quando `sender_id ==
  "atendente"`, resolve destino (`ResolverDestinoEnvioOutbound`, novo RPC) e envia
  via `data_whatsapp::SendWhatsappMessage` com retry/backoff (1/2/4s) e
  idempotência por `status_envio` (reentrega do consumer group vira no-op).
  Sucesso grava o `stanzaId` (`MarcarMensagemEnviada`); falha definitiva audita
  `mensagem.envio_falhou` (WARN, sem conteúdo) via `MarcarMensagemFalhaEnvio`.
- **Dashboards e alertas Grafana como código (N1.4):**
  `docker/observability/provisioning/dashboards/json/{servicos_saude,latencia_grpc,
  outbox_backlog,trace_chain}.json` (novo) e `provisioning/alerting/{rules,
  contact-points,notification-policies}.yml` (novo); `allowUiUpdates: false` e
  `editable: false` nos providers/datasources para dashboards-como-código de fato.

### Corrigido

- **Bug pré-existente no envio do bot:** `worker` montava o payload de
  `SendWhatsappMessage` com as chaves `instance_id`/`to`, mas o handler em
  `data_whatsapp` sempre esperou `id`/`to_number` — corrigido no mesmo call site
  tocado pelo elo outbox→outbound.
- **Duplicidade de prefixo de métrica no `otel-collector`:** `namespace:
  "smartcore"` do exporter Prometheus duplicava o prefixo já presente nos nomes de
  métrica da aplicação (`smartcore_rpc_duration_ms` → `smartcore_smartcore_...`).
  Removido; adicionado `resource_to_telemetry_conversion.enabled: true` para expor
  `service_name` como label por métrica (pré-requisito dos dashboards por serviço).

### Pendências remanescentes (trabalho futuro)
- TTL de feedback via env var global (`SMARTCORE_SCHEDULER_FEEDBACK_TTL_HORAS`), não
  per-tenant — override por tenant fica para N4 (retenção por política de plano).
- Sem chave de idempotência client-side para o envio outbound (depende de dedupe do
  provedor por `stanzaId`); considerar dead-letter para falha de resolução de
  destino sem `whatsapp_contact` ativo.
- Validação de dashboards/alertas com tráfego real e Grafana rodando fica para
  verificação manual em dev (ambiente de execução deste ciclo não tinha Docker).

## [2026-06-30] - Finalização do MVP Operacional (parcial WS-0..WS-4)

> Ciclo PREVC `finalizacao-mvp-operacional` fechado como **MVP PARCIAL** e arquivado via
> `prevc-final-review`. Final-review: `final-review-finalizacao-mvp-operacional.md` — qualidade
> **CORRIGIDO** (8 desvios corrigidos, 1 crítico de segurança). Entregues WS-0 (parcial), WS-1,
> WS-2 (exceto 2.4), WS-3, WS-4. **Backlog:** WS-2.4 (ticket/kanban), WS-5 (Register/Invite/Accept
> + RBAC), WS-6 (telas Flutter), WS-7 (control_plane CRUD + admin), WS-0.1/0.3/0.4 (stack LGTM,
> e2e de trace, métricas de pool).

### Adicionado

- **WS-1 `webhook_ingress` — autenticação + whitelist + idempotência:** RPCs
  `VerifyWhatsappInstanceToken` (comparação **constante-time** via `subtle`) e `IsPhoneWhitelisted`
  no `data_postgres`; dedupe `SET NX EX` por tenant; rejeição segura 401/403 sem publicar no bus.
  Token de instância em `secrecy::SecretString`; `traceparent` W3C semeado no envelope; telefone
  mascarado na auditoria.
- **WS-2 `worker` — orquestração de atendimento:** crate `domain_whatsapp` (normalização pura, sem
  I/O); RPC `ResolveAtendimentoParaContato` (contato→atendimento em transação RLS, fim do
  `atendimento_id` fixo); cliente RPC reusado no `AppState` (sem reconexão por evento); debounce
  por contato; barreira de bot com eventos `bot.respondeu`/`bot.silenciado`.
- **WS-3 outbound:** envio `worker` → `data_whatsapp` com retry/backoff exponencial (5xx/429);
  confirmações de status (`mensagem.enviada`/`falha_envio`/`confirmada`).
- **WS-4 realtime:** server streaming gRPC real (`StreamAtendimentos`, tonic) com JWT na abertura;
  fan-out por tenant via Redis Pub/Sub 0.25 (subscriber em conexão **dedicada** `into_pubsub()`,
  publisher em `MultiplexedConnection`); auditoria `stream.aberto/fechado/nao_autorizado`.

### Removido

- **`messaging_gateway` descomissionado (WS-0.2):** diretório `server/apps/messaging_gateway/` e
  referências em `.env.example` removidos; papel migrou para `webhook_ingress` + `data_whatsapp`.

## [2026-06-25] - Camada de Mensageria WhatsApp (Evolution Go)

> Ciclo PREVC `camada-mensageria-whatsapp-evolution-go` concluído e arquivado. Final-review:
> `final-review-camada-mensageria-whatsapp-evolution-go.md` — qualidade **CORRIGIDO**.

### Adicionado

- **`infrastructure_messaging` — contrato segregado (ISP):** o trait único de 12 métodos virou
  traits de capacidade — núcleo `InstanceManager`+`MessageSender` e opcionais `PresenceControl`,
  `ReadReceipts`, `Reactions`, `MediaDownloader`, `ProfileQuery`, `AdvancedSettingsControl`. Fachada
  `MessagingProvider` com descoberta `Option<&dyn Cap>` (default `None`), preservando object-safety
  de `Arc<dyn MessagingProvider>`.
- **`ProviderRegistry` + `ProviderRegistryBuilder` (DIP) (`registry.rs`):** resolve `dyn
  MessagingProvider` pela coluna `provider` da instância (chave = `provider_name()`); plugar um novo
  provedor passa a ser nova crate + 1 linha no registry, sem tocar consumidores.
- **`MessagingProviderError::Unsupported(&'static str)` (LSP):** capacidade ausente retorna erro
  canônico em vez de no-op/panic; os handlers de `data_whatsapp` derivam a mensagem desse variante.
- **`webhook_ingress` — `WebhookNormalizer` registry (OCP):** o `match provider` hardcoded virou
  `HashMap<&str, Arc<dyn WebhookNormalizer>>`; canonização dos eventos Go (UPPERCASE/PascalCase +
  aliases) para `MESSAGE`/`CONNECTION`/`PRESENCE`/`QRCODE`/`CONTACTS`/`MESSAGE_UPDATE`; provedor
  desconhecido responde 202 + warn.
- **Novos RPCs em `data_whatsapp`:** markread, react, presence, avatar (foto de perfil), download de
  mídia e reconnect — cada um resolve o `dyn` por instância e respeita LSP.

### Alterado

- **Realinhamento Evolution API v2 (Baileys) → Evolution Go (whatsmeow):** `infrastructure_evolution`
  passa a falar o contrato Go (fonte da verdade: `evolution_go_adapter.py`) — `/instance/connect`
  com token da instância + `subscribe` UPPERCASE + `immediate`; status via `GET /instance/status`;
  envio via `/send/text` e `/send/media` (`type`/`url`/`caption`/`filename`); logout
  `DELETE /instance/logout`; `map_state` ampliado; webhook embutido no `connect`. Mocks wiremock
  migrados de v2 para Go. Nenhum endpoint v2 remanescente.
- **`data_whatsapp`:** `AppState` deixa de segurar o `EvolutionProvider` concreto e passa a usar
  `ProviderRegistry` (concreto só na composition root); `AdminBulkDisconnect` →
  `AdminBulkDisconnectInstances`.

### Observabilidade & Auditoria

- `SecretString` sempre em `skip(...)`; body de erro do provedor truncado a 200 chars; body do
  webhook nunca logado (PII). Auditoria `whatsapp.instance.create/delete` e
  `whatsapp.admin.bulk_disconnect` via `security:stream` → `audit_log` (context sem token).

### Sem mudança de schema

- DB, migração `0008_whatsapp_sync.sql` e ports/adapters já eram genéricos — validados sem alteração.

### Correções do final-review (CORRIGIDO)

- 5 handlers de capacidade opcional em `data_whatsapp` retornavam `AppError::Internal` com strings
  ad-hoc; passaram a derivar de `MessagingProviderError::Unsupported(...)` (conformidade LSP). Teste
  `test_lsp_unsupported_error` ajustado. Revalidado verde via `test-local.ps1 -Fast`.

### Pendências remanescentes (trabalho futuro)

- Confirmar empiricamente o campo `base64` do `/message/downloadmedia` contra o Evolution Go real.
- Auditar o `.proto` dos novos RPCs (markread/presence/etc.) com o time de contratos.
- `translate_go_payload` (ingress, payload whatsmeow → shape canônico) foi além do plano; documentar.

## [2026-06-20] - Painel Gerencial do Superusuário (Admin Total)

> Ciclo PREVC `painel-admin-superusuario` concluído e arquivado. Final-review:
> `final-review-painel-admin-superusuario.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Contratos:** `admin.proto`/`admin.fbs` com o `AdminService` (CoreSettings, TenantConfig, Tenants, Billing, Evolution, Feature Flags, Auditoria/Saúde e export CSV em stream); `build.rs` passa a gerar o `admin.proto`.
- **runtime_api:** fachada gRPC-Web `AdminFacade` com guarda `exigir_superuser_do_metadata` (JWT + blocklist Redis + `is_superuser`) delegando ao `data_postgres`/`control_plane`.
- **data_postgres:** handlers de tenants, planos, assinaturas, pagamentos, feature flags (+ overrides), auditoria, saúde, resumo do dashboard e export CSV; migration `0012_feature_flags` (com RLS por tenant).
- **control_plane:** handler `TestEvolutionConnection` + módulo `evolution` (verificação HTTP via reqwest/secrecy).
- **Flutter:** módulo `admin_module` (domain/data/presentation) consumindo o `AdminService` via gRPC-Web; `api_client` expõe `AdminServiceClient`; `smart-core-admin` registra o módulo e redireciona o superusuário para `/admin/core-settings`.

### Corrigido (follow-up do final-review)
- **Auditoria de mutações sensíveis:** adicionados eventos `feature_flag_set` (flag global e override), `tenant_created` (passa `redis_conn` ao handler/rota), `tenant_api_key_changed` (WARN, só nomes de chaves) e `connection_tested` no `TestEvolutionConnection`.
- **Observabilidade:** `#[tracing::instrument(skip_all)]` nos handlers `test_evolution_connection`/`register_tenant` do `control_plane`.
- **SuperuserGuard (Flutter):** passou a exigir `isSuperuser` (não só autenticação); não-superusuário é redirecionado para `/login`. Teste do guard atualizado.

### Pendências remanescentes (trabalho futuro)
- **Pagamento manual não estende `current_period_end`** da subscription (DoD parcial; exige decisão de modelagem).
- **`data_exported`** não emitido em `ExportTenantsCsv` (leitura, não mutação).
- **`user_agent`** não persistido no `audit_log` (limitação pré-existente de `AuditLogPayload`).

## [2026-06-15] - Deploy do Admin Flutter Web no CI/CD sob `/v2/admin`

> Ciclo PREVC `deploy-admin-web` concluído. Final-review:
> `final-review-deploy-admin-web.md` — qualidade **CORRIGIDO**.

### Adicionado
- **App Flutter (E1):** `usePathUrlStrategy()` em `bootstrap.dart` para URLs limpas sob `/v2/admin/` (path strategy). Dependência `flutter_web_plugins: sdk: flutter` declarada no `pubspec.yaml`.
- **Caddyfile reescrito (E2):** 2 site blocks (apex prod + dev) com matcher por path `@grpcapi path /smartcore.contracts.*` (captura POST e preflight OPTIONS), `handle_path /v2/admin/*` com SPA fallback (`try_files`), CSP (`wasm-unsafe-eval`) + HSTS + headers de segurança. `reverse_proxy` sem h2c (gRPC-Web é HTTP/1.1). Access logs por site com rotação.
- **Provisionamento (E3):** Flutter SDK para o `gh-runner` (clone stable + `precache --web`), web roots `/srv/smart-core-admin/{prod,dev}` (755, owned by `gh-runner`), Caddyfile copiado via `install` (fonte da verdade versionada), DNS apex+dev no resumo.
- **Ambiente (E4):** `RUNTIME_API_GRPC_WEB_ADDR` documentado em `.env.deploy.example` (prod 50051 / dev 50061, bind localhost).
- **CI (E5):** `detect` corrigido para `clients/pubspec.yaml` (pub workspace). Job Flutter via melos (`analyze`/`test`) + smoke build web `--wasm`.
- **Deploy DEV (E6):** Build web + publicação atômica em `/srv/smart-core-admin/dev/web` com backup `web.bak` e rollback integrado.
- **Deploy PROD (E7):** Build web + publicação versionada em `releases/$TAG/web` com symlink estável e rollback por `PREV_WEB`.
- **Debug local (E9):** `.vscode/launch.json` (compound F5 → Chrome debug contra dev remoto). `run-admin.ps1` documentado com endpoint dev remoto.
- **Documentação (E8):** Seção 9.5 em `10-plano-cicd-devops.md` (estratégia de build/deploy web). Seção 7 em `09-comunicacao-e-autenticacao.md` (same-origin, roteamento por path, debug local CORS).

### Corrigido (follow-up do final-review)
- **`server-setup.sh`:** Guard de idempotência (`grep -qF`) na inserção do Flutter PATH no `.bashrc` do `gh-runner` — evita linhas duplicadas em re-execuções. Trocado `--add` por `--replace-all` no `git config safe.directory`.

### Pendências remanescentes (trabalho futuro)
- **Fase V (validação):** Itens V0–V7 (debug local, CI verde, dev/prod acessíveis, same-origin, rollback, segurança, TLS) dependem de infraestrutura no servidor (DNS apontado, Caddy rodando, Flutter SDK instalado).
- **Job `flutter-windows`** em `deploy-prod.yml` referencia `clients/flutter_windows` (possível path obsoleto) — fora do escopo deste plano.
- **Idempotência do cargo PATH** no `.bashrc` (linha 145 de `server-setup.sh`) — pré-existente, merece correção em ciclo futuro.

## [2026-06-11] - Otimização de Pools, Concorrência e Observabilidade de Gargalos

> Ciclo PREVC `otimizacao-pools-observabilidade` concluído. Final-review (Opus):
> `final-review-otimizacao-pools-observabilidade.md` — qualidade **CORRIGIDO**.

### Adicionado
- **F1 Correções críticas:** Argon2 via `spawn_blocking` (`hash_password_async`/`verify_password_async`); `transport::bus::Consumer` com **conexão dedicada** (`get_async_connection`) para o `XREADGROUP BLOCK`; `REDIS_BUS_URL` separada da `REDIS_URL` (cache 6379-local/6380-remoto allkeys-lru × bus 6380-local/6381-remoto noeviction); **ACK condicional** (XACK só em `Ok`, PEL como retry) + DLQ `security:dlq` via `xpending_count.times_delivered` + `xclaim`.
- **F2 Controle de pools:** `PoolConfig::from_env` (`SMARTCORE_PG_POOL_MAX/MIN`, `ACQUIRE_TIMEOUT_MS`, `IDLE_TIMEOUT_S`, `MAX_LIFETIME_S`) com fail-fast e pool quente; admission control no `transport::Server` (semáforo `SMARTCORE_<SVC>_MAX_INFLIGHT`); timeouts Redis via `new_with_backoff_and_timeouts`.
- **F3 Monitoramento:** API de métricas OTel 0.24/OTLP 0.17 (`init_metrics` via `new_pipeline().metrics`); gauges de pool (`observability::pool_metrics`, feature **`pool-metrics`** só-sqlx); RED por método + slowlog com `traceparent` no `transport::runtime`; medição de espera de acquire; gauges de lag (`smartcore_bus_pending`, `smartcore_outbox_backlog`).
- **F4 Eficiência:** `revogar_familia` com DEL variádico; outbox relay marcando publicados em lote (`id = ANY($1)`); consolidação de auditoria em lote por tenant.
- **Ambiente local de testes pré-push (`infra/test-local.ps1`):** esteira completa (fmt → clippy → `cargo test --workspace` com integração via túnel SSH → `sqlx prepare --check`), modos `-Fast`/`-ResetTunnel`; `tunnel.ps1` mapeando as 3 portas (Postgres 5434, cache 6379→6380, bus 6380→6381); servidor Hostinger com `smartcore-v2-redis-bus` provisionado (host 6381, noeviction) e `REDIS_BUS_URL` nos `.env` dev/prod.

### Corrigido (follow-up do final-review)
- **Invariante de arquitetura:** métricas de pool estavam gated por `postgres-audit` (reintroduzia a aresta de produção `observability → infrastructure_postgres`); isoladas na feature `pool-metrics` (apenas `dep:sqlx`), verificado com `cargo tree -e no-dev`.
- `cargo fmt` aplicado no workspace (12 arquivos pendentes do ciclo).

### Validação
- Suíte completa (unit + integração) verde contra o Postgres/Redis reais da Hostinger via túnel (~140 testes, 0 falhas), na topologia cache×bus nova.

### Pendências remanescentes (trabalho futuro)
- **M5:** dashboard Grafana "Saúde de Dados" + 5 alertas (provisioning de infra).
- DoDs de carga formais (20 logins concorrentes, rajada de 200 req, saturação pool max=2) — instrumentação pronta, falta o exercício de carga.
- `worker`/`data_storage` ainda sem timeouts Redis (P4 restrito ao `data_postgres` por plano).
- Restart dos services dev/prod para ativarem `REDIS_BUS_URL` (entra no próximo deploy).

## [2026-06-07] - DevOps Completo: CI/CD, Ambientes e Provisionamento do Servidor

> Ciclo PREVC `cicd-devops` concluído. Final-review (Opus):
> `final-review-cicd-devops.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Workflows GitHub Actions (`.github/workflows/`):** `ci.yml` (lint, testes, `cargo sqlx prepare --check` offline, detecção Flutter), `deploy-dev.yml` (build + deploy automático em push `dev` no self-hosted runner), `deploy-prod.yml` (build + deploy com approval manual, rollback via symlink/`PREV_RELEASE`, backup de banco, GitHub Release, job Flutter Windows) e `pr-to-main.yml` (PR automático `dev→main` após tag).
- **Provisionamento do servidor (`infra/server-setup.sh`):** setup completo do Hostinger KVM2 (Ubuntu 22.04) — usuários `smartcore`/`gh-runner`, Caddy com TLS automático e h2c para gRPC, journald, ufw (só 22/80/443), sudoers restrito, `protoc`/`flatc`, postgresql-client.
- **Systemd (`infra/systemd/`):** 14 service units (7 por ambiente dev/prod) + 2 targets, com `User=smartcore`, `NoNewPrivileges`, `PrivateTmp`, `EnvironmentFile` por ambiente e ordem de dependências (`runtime_api` depende dos demais).
- **Observabilidade (`docker/`):** stack LGTM (Grafana, Loki, Tempo, Prometheus, OTEL Collector, Promtail) com `mem_limit` por container, rede externa `smartcore_v2_network` e datasources do Grafana pré-provisionados (correlação log↔trace e service map por UID).
- **Backup cifrado dos `.env` (`infra/backup-envs.ps1`):** AES-256-CBC / PBKDF2 / 100k iterações, com manuseio de senha via `SecureString` e variável de ambiente (sem expor segredo na lista de processos).
- **Documentação de deploy:** `README.md` (raiz) com instruções de CI/CD e `.env.example` com todas as variáveis de deploy (incluindo Grafana).

### Corrigido (follow-up do final-review)
- **Datasources do Grafana (`docker/observability/provisioning/datasources/ds.yml`):** `datasourceUid` referenciava o nome em vez do UID — adicionados `uid:` explícitos e corrigidas as correlações derivedField/serviceMap.
- **Smoke tests (`deploy-dev.yml`/`deploy-prod.yml`):** ampliados de 4 para os 7 serviços, alinhando com o critério V.1 ("todos os serviços active").
- **`backup-envs.ps1`:** removido código morto (`$PasswordBytes`) e endurecido o manuseio de senha.

### Pendências remanescentes (trabalho futuro)
- Separar `REDIS_BUS_URL` antes de F3 (registrado no plano).
- `docker/compose/observability.yml`: trocar o default fraco `GRAFANA_ADMIN_PASSWORD:-admin_secret_pass` por variável obrigatória em produção.
- `infra/.env.deploy.example` está coberto pelo `.gitignore` (`.env.*`) — versionar o template na feature de deploy-data/tunnel.

## [2026-06-05] - Refator de Arquitetura Modular por Contrato (RF0–RF6)

> Ciclo PREVC `refator-arquitetura-modular` concluído. Final-review (Opus):
> `final-review-refator-arquitetura-modular.md` — qualidade **CORRIGIDO**.

### Adicionado
- **Crate `contracts` (`server/crates/contracts`):** Fonte de schema canônica em **`.proto`** (`schemas/*.proto`) gerando gRPC/Protobuf via `tonic_prost_build` e FlatBuffers via `flatc --proto`→`.fbs`→`flatc --rust` (`build.rs`). `protoc`/`flatc` vendorizados em `server/bin/`. Decisão de manchete: o `flatc` **não** transpila `.fbs`→`.proto`, então o IDL autorado virou `.proto` — FlatBuffers permanece o codec de fio padrão (`payload:[ubyte]` preservado).
- **Crate `transport` (`server/crates/transport`):** Runtime de transporte sobre UDS — `framing.rs` (len/flags/corr_id), `runtime.rs` (`MuxClient` corr_id→oneshot, timeout, backpressure), `codec.rs` (codec FB/gRPC comutável por env) e `bus.rs` (Redis Streams `STREAM_EVENTOS`/`STREAM_SEGURANCA`, consumer group, XACK, reprocessamento PEL) absorvendo o antigo `event_bus.rs` do `infrastructure_redis`.
- **`ErrorEnvelope` no `error_core` (`envelope_bridge.rs`):** Ponte serializável entre `AppError` e o envelope de contrato; 6 categorias novas em `code.rs` (apêndice, disciplina de não-remover preservada).
- **Rewire de auditoria p/ Streams (`observability/src/audit.rs`):** Auditoria publica em `STREAM_SEGURANCA` via `transport::bus`; consumidor de consolidação no app `data_postgres`.
- **Apps por contrato (`server/apps/*`):** `data_postgres` (RPC 3 protocolos + consumer de auditoria + `OutboxRelay` via PgListener), `data_redis`, `data_storage`, `runtime_api`, `messaging_gateway`, `worker`, `control_plane` (topologia ponta-a-ponta; realtime/WS e `control_plane` como stubs declarados).
- **Crate `application` (`auth/login.rs`):** Caso de uso de login falando por RPC (`transport::conectar_cliente`), sem acesso direto a repositório.
- **Migration `0011_outbox.sql`:** Tabela `outbox` + trigger `pg_notify('outbox_new')` para o relay outbox→bus.
- **Docker:** serviço `redis-bus` com `--maxmemory-policy noeviction` (separado do `allkeys-lru` que evicta Streams).

### Corrigido (follow-up das pendências do final-review)
- **Runtime de transporte resiliente (`transport/src/runtime.rs`):** `MuxClient` reescrito com keepalive (PING→PONG nas flags do `framing`), detecção de conexão morta e reconexão automática com **backoff exponencial + jitter** (teto de tentativas). O `Server` responde PING com PONG sem passar pelos handlers.
- **Ciclo `observability→infrastructure_postgres` removido em produção:** feature `postgres-audit` saiu do `default` (`default = []`); o build padrão publica auditoria só via Redis Streams. Dev-dependency auto-referente reativa a feature nos testes (retrocompatibilidade com banco).
- **`traceparent` W3C ponta-a-ponta no barramento:** `TenantEnvelope`/`EventoBruto` ganham o campo `traceparent` (serde `default`, retrocompatível); publicado e lido no Redis Streams. Propagado em `messaging_gateway` (RPC→bus), `worker` (bus→RPC) e auditoria (`audit.rs`, `data_postgres`).
- **`traceparent` no relay do outbox:** `0011_outbox` ganha a coluna `traceparent`; o `handler_persist_message` persiste o trace da requisição na mesma transação ACID e o `OutboxRelay` o repropaga no barramento (persistência → relay → bus).
- **Stubs eliminados (handlers reais por contrato):**
  - `data_postgres`: `GetThread` carrega a thread de mensagens (RLS); novos RPCs `ListAtendimentos` (snapshot por status, RLS) e `CreateTenant` (escrita admin).
  - `runtime_api`: `StreamAtendimentos` deixa de ser mock e delega ao `data_postgres` (`ListAtendimentos`) via RPC.
  - `control_plane`: `RegisterTenant` deixa de gerar UUID fake e delega ao `data_postgres` (`CreateTenant`) via RPC.

### Pendências remanescentes (trabalho futuro)
- **Streaming multi-frame de verdade** (`runtime_api::StreamAtendimentos`): hoje é snapshot req/reply. Server-streaming real exige um primitivo de Handler com múltiplos frames no `transport` (as flags `STREAM_ITEM`/`STREAM_END` já existem no framing).
- **Validação em banco real:** os handlers novos (`GetThread`/`ListAtendimentos`/`CreateTenant`) passam `fmt`/`clippy`/build offline; a semântica RLS/admin precisa ser exercitada com o túnel SSH + DB (`cargo test`).

## [2026-06-04] - Tratamento de Erros (`error_core`)

### Adicionado
- **Crate `error_core` (`server/crates/error_core`):** Fundação transversal de tratamento de erros rastreável do workspace. Reexporta `ErrorCode`, `ErrorCategory`, `AppError`, `Severity`, `ErrorReport`, `ErrorContext` e `registrar()`.
- **Taxonomia estável `ErrorCode` (`code.rs`):** 17 códigos cobrindo auth/storage/db/cache/validação/conflito/internal, serializáveis em `SCREAMING_SNAKE_CASE` (serde) com `Display` manual (sem `serde_json` no hot path de log) e `category()` para agrupamento em métricas.
- **Agregador `AppError` (`error.rs`):** Enum com payload `String` (erros de infra ainda não existem no workspace) expondo `code()`, `severity()` (composta por variante + conteúdo), `retryable()` e `public_message()` — esta nunca vaza PII, stack trace ou detalhe interno.
- **Registro rastreável (`report.rs`):** `ErrorReport` + `registrar()` emitindo log estruturado via `tracing` (`error!`/`warn!` por severidade) com correlação `trace_id`/`tenant_id`, integrado à crate `observability`.
- **Mapeamento gRPC (`transport.rs`, feature `grpc`):** `to_status()` converte `AppError` em `tonic::Status`; `AuthInsufficientScope → PermissionDenied`, demais auth → `Unauthenticated`, alinhado ao doc 09. `tonic` carregado apenas sob a feature opcional.
- **`tonic = "0.14.6"` no workspace:** Adicionada a `[workspace.dependencies]` e `error_core` registrada em `[workspace.members]` de `server/Cargo.toml`.
- **Testes de integração:** 13 testes (`tests/integration_tests.rs` + submódulos `code`/`error`/`report`/`transport`/`observability`) cobrindo mapeamento de códigos, severidade, retryable, mensagens públicas, transporte gRPC (feature-gated) e integração real com `tracing_subscriber` (correlação e não-vazamento de PII).

## [2026-06-04] - Observabilidade e Auditoria

### Adicionado
- **Migration `0010_audit_log.sql`:** Nova migração no PostgreSQL com tabela `audit_log`, índices focados em desempenho para buscas de tenant/globais, e suporte à isolamento de dados com Row-Level Security (RLS).
- **Módulo `auditoria` no `infrastructure_postgres`:** Repositório Rust (`audit_log.rs`) contendo inserção e busca estruturada de logs. Mapeamentos do SQLx implementados usando formato dinâmico (sem macros `!`) para compatibilidade com compilações locais/CI offline.
- **Crate `observability`:** Nova crate Rust transversal para inicializar o OpenTelemetry gRPC e o Tracing JSON no stdout.
- **`AuditLogger` assíncrono:** Logger fire-and-forget com dual pool (Conventional tenant pool + Admin pool com BYPASSRLS) para gravação concorrente de logs de inquilinos e de superusuários do sistema.
- **Helpers de Propagação:** Helpers utilitários no Rust para injetar e extrair o TraceContext W3C a partir de HashMaps genéricos, preparados para Redis Streams e payloads JSON.
- **Stack LGTM Docker Compose:** Configurações centralizadas em `docker/compose/observability.yml` e arquivos em `docker/observability/` (OTel Collector, Loki, Tempo, Prometheus, Grafana, Promtail) com limites rígidos de memória.
- **Provisionamento de Dashboards:** Configuração as-code para provisionamento automático de datasources no Grafana e criação do dashboard "Smart Core v2 - Auditoria e Segurança" (`audit_log.json`).
