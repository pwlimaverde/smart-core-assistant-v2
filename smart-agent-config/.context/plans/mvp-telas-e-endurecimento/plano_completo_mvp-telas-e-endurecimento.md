# Plano Completo — MVP: Telas & Endurecimento

> **Slug:** `mvp-telas-e-endurecimento`
> **Status:** Plano de execução reestruturado e aterrado no código real + doc atual de libs (todas validadas na central local `doc_dev/libs/`).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Origem:** continuação do ciclo `finalizacao-mvp-operacional` (fechado como MVP parcial WS-0..WS-4 e mergeado na dev). Cobre o backlog restante: as **TELAS Flutter** (bloco principal) + **endurecimento de backend**.
> **Regra inegociável (herdada, DoD transversal):** tudo que cria/altera comportamento **passa pela observabilidade** — emite logs/spans estruturados, registra auditoria quando toca estado sensível, e nunca vaza segredo/PII.
> **Princípio transversal explícito:** **SOLID + Ports & Adapters** (Rust: casos de uso dependem de `Arc<dyn Trait>`, `domain_*` sem I/O; Flutter: `DataSource` abstrato RemoteOnly injetado por `get_it`).

---

## 0. Estado real consolidado (aterramento — base da reestruturação)

A investigação no código revelou que **boa parte do que o pedido inicial descreve como "a construir" já existe**. Isso recalibra o esforço: o WS-7 telas é majoritariamente endurecimento, e o backend de realtime do chat já está pronto.

| Área | Arquivo / Caminho | Estado real confirmado | Impacto no plano |
|---|---|---|---|
| **Rotas admin (18)** | `runtime_api/src/main.rs:229` (`registrar_rotas_admin`) | As 18 rotas (ListTenants…SetFeatureFlagOverride) **já registradas** via `handler_admin_forward` autenticado (superuser=true). | WS-7 telas **consome**, não cria rotas. |
| **Telas admin Flutter** | `clients/modulos/admin_module/lib/src/features/config/**` | **JÁ EXISTEM** páginas, controllers, usecases, datasources e models para tenants/billing/dashboard/feature_flags/audit/core_settings/evolution/tenant_config. | WS-7 telas vira **endurecimento + lacunas** (CRUD faltante, fluxos de detalhe/editar/ativar, convites), não construção do zero. |
| **Telas operacionais Flutter** | `clients/modulos/core_module/lib/**` | `core_module` só tem serviços de infra (auth/storage/session no-op). **NÃO há** fila/kanban/chat. | WS-6 é **construção nova** (maior bloco real). |
| **Realtime backend** | `runtime_api/src/realtime.rs` + `admin.proto:418` | `RealtimeManager` com fan-out Redis Pub/Sub (`tenant:{id}:events`) + `broadcast` por tenant **já implementado**; RPC `StreamAtendimentos returns (stream AtendimentoEvent)` **já no contrato**. | WS-6 chat **só consome**; nenhum trabalho de fan-out novo. |
| **Stub Dart do stream** | `api_client/.../generated/queries/admin.pbgrpc.dart` | **NÃO tem** `streamAtendimentos` gerado (só `exportTenantsCsv` como `ResponseStream`). | WS-6 exige **regerar o stub Dart** a partir do `.proto` (tarefa concreta). |
| **Envelope (contrato)** | `contracts/schemas/envelope.proto:18` + `generated/fbs/envelope.fbs:16` | Campos 11–13: `auth_user_id`, `auth_scopes`, `auth_is_superuser`. **Sem** `flow_permissions`. | WS-5a adiciona campo **14** (proto) + slot na tabela FB. |
| **RequestContext** | `infrastructure_postgres/src/security.rs:8` | **Já tem** `flow_permissions: Vec<i32>` + `has_flow_permission()` (com bypass `kanban:admin`/`tenant:admin`) — testado. | WS-5a só precisa **popular** o vetor (hoje chega vazio). |
| **contexto_do_envelope** | `data_postgres/src/main.rs:13` | Seta `flow_permissions: vec![]` fixo. | WS-5a faz ler do envelope. |
| **AuditLogPayload** | `observability/src/audit.rs:13` | Campos: `tenant_id, level, service, trace_id, event, message, context, user_id, ip_address`. **Falta `user_agent`.** | WS-5b adiciona `user_agent` (+ migration + INSERT + plumbing). |
| **Helpers de auditoria** | `observability/src/audit.rs:252-341` | `info/warn/error(tenant_id, event, message, context, user_id, ip_address, trace_id)` + `*_global`. Assinatura posicional larga (`#![allow(clippy::too_many_arguments)]`). | WS-5b: **não** adicionar 9º parâmetro posicional — introduzir `AuditContext` (ver §Correções). |
| **Padrão Flutter de referência** | `login_module/.../login_grpc_datasource.dart` | `Datasource<Session> implements Datasource<T>` → `_client.login(...)` → mapeia `GrpcError` via `mapGrpcError`; retorno `ReturnSuccessOrError`. DI por módulos (`installModules`/`get_it`); canal `GrpcWebClientChannel.xhr`; `go_router`; token em `flutter_secure_storage`. | WS-6/WS-7 **replicam** esse padrão para os novos datasources. |
| **TenantConfigCache** | `data_postgres/src/main.rs:39` (`config_cache: Arc<TenantConfigCache>`) | Cache plugado no AppState. **Sem subscriber de invalidação** Pub/Sub. | WS-7.2 adiciona o subscriber `core:settings:invalidate`. |

> **Conclusão do aterramento:** o trabalho pesado é **WS-6 (telas operacionais novas)**. WS-7 telas é endurecimento incremental. O backend de endurecimento (WS-5a/5b/7.2) é cirúrgico e pode correr **em paralelo** às telas, com a única dependência dura sendo **WS-5a antes do filtro de fluxo do Kanban**.

---

## 1. Contrato de Observabilidade (DoD de TODA tarefa que cria/altera comportamento)

Nenhuma etapa fecha sem cumprir os **três eixos**. A fundação já existe na crate `observability` (este plano a **aplica**).

### 1.1 Telemetria (logs + traces)
- Span por handler/caso de uso novo com `tenant_id` (e `trace_id` quando houver) via `observability::tenant_span!` ou `#[tracing::instrument(...)]`.
- Campos padrão (doc 05 §2): `service`, `env`, `tenant_id`, `trace_id`; `error_code` no caminho de erro (via `error_core::registrar`, padrão já presente em `runtime_api` `registrar_erro_borda:315`).
- **Propagação `traceparent` W3C** ponta a ponta (campo `Envelope.traceparent:23`), reusando `observability::{extrair_contexto, injetar_contexto_atual}`.
- No Flutter: o cliente propaga `traceparent` nas chamadas gRPC-Web; logs de erro de UI **sem PII**.

### 1.2 Auditoria (negócio + segurança)
- Produção: `AuditLogger::new_with_redis(conn, "<serviço>")` → publica em `security:stream` via `transport::bus::publicar_evento_seguranca` → consumido pelo `data_postgres` → tabela `audit_log` sob RLS. **Nunca** abrir Postgres direto dos serviços (mantém `infra` desacoplada de `observability`).
- **Convenção:** `<dominio>.<acao>` em snake (glossário §12).
- **Metadados mínimos (doc 08 §4.2):** timestamp UTC (data_postgres), `user_id`, `ip_address`, **`user_agent`** (habilitado pela WS-5b), `event_type`, `description` **sem segredo**.
- **Eventos críticos obrigatórios (doc 08 §4.2):** Tenant/`owner_id`, TenantInvite, TenantUser/permissões, Subscription/PaymentRecord, chaves de API.

### 1.3 Sanitização (doc 05 §6, doc 08 §4)
- **Proibido** logar: JWT/refresh token, `apikey` de instância, chaves de API, `ENCRYPTION_KEY`, payload bruto do WhatsApp, telefone completo (mascarar `+55 11 9****-1234`).
- Structs com credencial usam `secrecy::SecretString` (0.10.3).
- No Flutter: tokens/refresh só em `flutter_secure_storage`, nunca em log.

### 1.4 Checklist por PR
- [ ] Span com `tenant_id`/`trace_id` no caminho novo.
- [ ] `traceparent` propagado ao próximo salto.
- [ ] ≥ 1 evento de auditoria por ação sensível (ou declaração explícita "sem evento de auditoria").
- [ ] Eventos na convenção `<dominio>.<acao>`, documentados no §12.
- [ ] Nenhum segredo em log/auditoria; PII mascarada.

---

## 2. Workstreams e grafo de dependências

```
WS-5a RBAC fino (flow_permissions no Envelope)  ─────┐  (dependência dura)
                                                      ▼
                            WS-6.2 Kanban (filtro por fluxo) ──► restante WS-6 telas operacionais
                                                                          (fila, chat streaming, outbound)

WS-5b user_agent no AuditLogPayload   ───┐
WS-7.2 invalidação TenantConfigCache  ───┤  (endurecimento — paralelo às telas, sem bloquear WS-6)
WS-0.3 e2e de cadeia de trace         ───┘  (gate de fundação; alinhar diretriz de testes)

WS-7 telas admin (endurecimento)  ──────────  (independente; depende só das 18 rotas já expostas)
```

**Regras de sequenciamento:**
- **WS-5a precede** a etapa do Kanban que filtra por fluxo (WS-6.2). O resto de WS-6 (fila, chat, outbound) **não** depende de WS-5a e pode começar antes.
- **WS-5b, WS-7.2, WS-0.3** são endurecimento de backend e correm **em paralelo** ao bloco de telas.
- **WS-7 telas** é independente de tudo (as rotas já existem); pode iniciar a qualquer momento.

---

## 3. WS-5a — RBAC fino por fluxo (`flow_permissions` no Envelope)

**Estado real:** `RequestContext` já tem `flow_permissions: Vec<i32>` + `has_flow_permission()` (security.rs:17/32, testado). O elo quebrado é o transporte: o `Envelope` não carrega o vetor, e `contexto_do_envelope` (data_postgres/src/main.rs:18) seta `vec![]` fixo. O `exigir_auth` (runtime_api/src/main.rs:373) hoje popula apenas `auth_scopes`/`auth_user_id`/`auth_is_superuser`.

### 3.1 Tarefas (ordem)
1. **Contrato — campo no Envelope.** Adicionar `repeated int32 flow_permissions = 14;` em `contracts/schemas/envelope.proto` e o campo equivalente (`flow_permissions:[int];`) nas tabelas `Envelope` de `generated/fbs/envelope.fbs:16` **e** `generated/fbs/all_schemas.fbs:455`. Regenerar com `flatc 25.x` (flatc 25.12.19) + `tonic-build` no build do `contracts`. **Evolução aditiva** (novo field number → retrocompatível; serviços antigos ignoram o campo).
2. **Origem das permissões — decidir entre (A) claim no JWT vs (B) RPC ao data_postgres.**
   - **(A) Claim `flow_permissions` no JWT:** zero round-trip extra no caminho quente; porém o vetor fica **estático até o refresh** (mudança de permissão só vale no próximo token) e **infla o token**.
   - **(B) RPC novo `GetUserFlowPermissions { tenant_id, user_id }` ao data_postgres:** sempre fresco, sem inchar o JWT; custo de +1 RPC por requisição autenticada (mitigável com cache curto em memória no runtime_api, TTL ~30 s, invalidável).
   - **Decisão recomendada:** **(B) com cache de TTL curto**. Alinha com o restante da arquitetura (banco é a fonte de verdade via data_postgres), respeita a memória "banco só via infra/RPC", e evita revogação atrasada de acesso a fluxo — que é justamente um controle de segurança. O cache curto neutraliza o custo no caminho quente. **Confirmar com o dono** antes de codar (trade-off explícito).
3. **`exigir_auth` popula o envelope.** Após validar o JWT, carregar `flow_permissions` (via opção escolhida) e setá-las no `Envelope` antes do forward.
4. **`contexto_do_envelope` lê do envelope.** Trocar `flow_permissions: vec![]` por `flow_permissions: env.flow_permissions.clone()` (data_postgres/src/main.rs:18).
5. **Repos de Kanban filtram.** Nos handlers/repos de leitura de Kanban, aplicar `ctx.has_flow_permission(fluxo_id)`; barrar → `DbError::PermissionDenied` (mesmo caminho de `exigir_qualquer`).

### 3.2 SOLID / Ports & Adapters
- **Port novo (opção B):** `FlowPermissionsProvider { fn permissions(tenant_id, user_id) -> Result<Vec<i32>> }`. **Adapter:** `RpcFlowPermissionsProvider` (fala com data_postgres) + decorator `CachedFlowPermissionsProvider` (TTL curto). **DIP:** o interceptor depende de `Arc<dyn FlowPermissionsProvider>`. **ISP:** port pequeno e único, não acoplado ao resto do `AuthDeps`.

### 3.3 Observabilidade & Auditoria
- **(a) Logs/traces:** span no `exigir_auth` ao carregar permissões (`service=runtime_api`, `tenant_id`, `user_id`, `trace_id`); **não** logar o conjunto de fluxos em claro (apenas a contagem). Caminho de erro com `error_code`.
- **(b) Auditoria:** `autorizacao.negada` (**WARN**) quando o filtro de fluxo barra (contexto: `fluxo_id`, `user_id`, `ip_address`, `user_agent`; **sem** listar todas as permissões). É evento de segurança (doc 08 §4.2). Concessão normal **não** gera auditoria (declarado: *sem evento de auditoria* no caminho feliz, para não inundar a trilha).
- **(c) Sanitização:** vetor de permissões é metadado, não segredo, mas evitar despejá-lo em log; nada de token.

### 3.4 DoD
- Atendente sem o fluxo X **não** vê cards do fluxo X (barrado no data_postgres) e o bloqueio fica **auditado** com `user_agent`/`ip`. Atendente com o fluxo vê. `kanban:admin`/`tenant:admin` veem tudo. Contrato regenerado e **workspace inteiro** compila (`clippy -D warnings`) + `.\infra\test-local.ps1` verde.

---

## 4. WS-5b — `user_agent` no `AuditLogPayload`

**Estado real:** `AuditLogPayload` (audit.rs:13) não tem `user_agent`; os helpers `info/warn/error/*_global` já têm assinatura posicional larga (8 args). O consumer de auditoria no `data_postgres` faz o INSERT na `audit_log` (migration `0010_audit_log.sql`). Exigido por doc 08 §4.2.

### 4.1 Estratégia menos invasiva — `AuditContext` (em vez de 9º parâmetro posicional)
Adicionar um novo parâmetro posicional a `info/warn/error` (já com `#![allow(clippy::too_many_arguments)]`) multiplicaria a fragilidade e tocaria **todos** os call-sites de forma cega. A estratégia recomendada:

1. **Introduzir struct `AuditContext`** em `observability`:
   ```rust
   pub struct AuditContext {
       pub user_id: Option<i32>,
       pub ip_address: Option<String>,
       pub user_agent: Option<String>,
       pub trace_id: Option<String>,
   }
   ```
   Agrupa os quatro metadados de ator/rede/trace que hoje viajam soltos. `Default` derivável para call-sites de sistema (sem ator).
2. **Adicionar `user_agent: Option<String>` ao `AuditLogPayload`** (campo aditivo; `serde` retrocompatível com payloads antigos via `#[serde(default)]`).
3. **Novos métodos ergonômicos** `info_ctx/warn_ctx/error_ctx(tenant_id, event, message, context, &AuditContext)` que delegam aos `log_tenant_event` existentes preenchendo o novo campo. **Manter** os métodos antigos como _thin wrappers_ que constroem um `AuditContext` parcial (`user_agent: None`) — assim **nenhum call-site existente quebra**; só os que precisam de `user_agent` migram para a forma `_ctx`.
4. **Migration nova** `00XX_audit_log_user_agent.sql`: `ALTER TABLE audit_log ADD COLUMN user_agent TEXT NULL;` (aditiva, nullable — sem backfill).
5. **INSERT no consumer** (`data_postgres`): incluir `user_agent` em `NewAuditLogEntry` + `inserir_audit_log`/`inserir_audit_log_global`.
6. **Plumbing do `user_agent` na borda:** o `runtime_api` extrai o header `user-agent` da requisição gRPC-Web e o injeta no `AuditContext` nas chamadas de auditoria dos **eventos críticos** (WS-5a `autorizacao.negada`, e os eventos admin já auditados pelo forward).

### 4.2 Call-sites afetados (alto nível)
- `observability/src/audit.rs` (payload + métodos `_ctx` + wrappers).
- `data_postgres`: `NewAuditLogEntry`, `inserir_audit_log*`, consumer de `audit_log`.
- `runtime_api`: borda que captura `user-agent` e monta `AuditContext` (eventos de auth/RBAC/admin).
- `infrastructure_postgres`: migration nova + (se `inserir_audit_log` é tipado por struct) campo extra.
- Demais call-sites de `info/warn/error` em `worker`/`webhook_ingress`/etc. **não mudam** (continuam usando os wrappers antigos com `user_agent: None`).

### 4.3 SOLID
- `AuditContext` é um **value object** de borda (sem I/O) — coesão e ISP (um agregado de metadados em vez de quatro params soltos). Não introduz novo port; estende o contrato de auditoria de forma aditiva (OCP).

### 4.4 Observabilidade & Auditoria
- **(a) Logs/traces:** mudança estrutural; sem novo span. Garantir que falha de INSERT do novo campo cai no `tracing::error` já existente (audit.rs:114/153).
- **(b) Auditoria:** **habilita** os metadados mínimos do doc 08 §4.2 — não é evento próprio (*sem evento de auditoria intencional*; é plumbing). Os eventos que passam a carregar `user_agent` são os críticos de WS-5a/WS-7.
- **(c) Sanitização:** `user_agent` é metadado, não segredo; truncar tamanho defensivo (ex.: 512 chars) para evitar payload abusivo.

### 4.5 DoD
- Evento `autorizacao.negada` (e os eventos admin) gravam `user_agent` na `audit_log`; call-sites antigos seguem compilando sem alteração; migration aplicada via `.\infra\test-local.ps1`. `clippy -D warnings`.

---

## 5. WS-7.2 — Invalidação do `TenantConfigCache` (Redis Pub/Sub)

**Estado real:** `TenantConfigCache` plugado no AppState do `data_postgres` (main.rs:39). Não há subscriber de invalidação — alterar config exige restart para refletir. O `realtime.rs` já estabelece o padrão Pub/Sub 0.25 a reusar.

### 5.1 Tarefas
1. **Subscriber dedicado** no canal `core:settings:invalidate`, espelhando `realtime.rs:52`:
   ```rust
   let con = client.get_async_connection().await?;   // conexão DEDICADA (bloqueante)
   let mut pubsub = con.into_pubsub();
   pubsub.subscribe("core:settings:invalidate").await?;
   let mut stream = pubsub.on_message();             // impl Stream<redis::Msg>
   while let Some(msg) = stream.next().await {
       let payload: String = msg.get_payload()?;     // { tenant_id, key? }
       // cache.invalidate(tenant_id [, key])
   }
   ```
   Rodar em `tokio::spawn` no boot do `data_postgres`.
2. **Publisher** nos handlers que gravam config — `UpdateTenantConfig` e `UpsertCoreSetting` — usando **`MultiplexedConnection`** (`get_multiplexed_async_connection`), **NUNCA** a conexão do subscribe:
   ```rust
   let mut con = client.get_multiplexed_async_connection().await?;
   let _n: u32 = con.publish("core:settings:invalidate", payload).await?;
   ```
3. **Invalidação granular:** payload carrega `tenant_id` (e `key` opcional) → invalida só a entrada afetada, sem flush global.

> **API redis 0.25 (NÃO 1.0):** subscribe via `get_async_connection().into_pubsub()` + `on_message()` + `get_payload()`; publish via `get_multiplexed_async_connection().publish()`. Regra de ouro: subscribe e publish em **conexões separadas**.

### 5.2 SOLID / Ports & Adapters
- **Ports novos:** `ConfigInvalidationPublisher { publish(tenant_id, key?) }` e `ConfigInvalidationSubscriber { run(cache) }`. **Adapters:** `RedisConfigInvalidationPublisher` (multiplexed) e `RedisConfigInvalidationSubscriber` (dedicada). **ISP:** publisher e subscriber separados (vivem em pontos diferentes). **DIP:** os handlers de escrita dependem do trait publisher, não da conexão Redis concreta. **OCP:** trocar o backend de invalidação não toca nos handlers.

### 5.3 Observabilidade & Auditoria
- **(a) Logs/traces:** span `config.invalidada` na recepção do evento (`tenant_id`, `key`, `trace_id`); log estruturado da publicação.
- **(b) Auditoria:** `config.invalidada` (**INFO**) — já no glossário (herdado do §8 do plano base). O evento de **mutação** (`config.atualizada`/`api_key.update`) já é auditado pelos handlers admin; a invalidação é o efeito propagado.
- **(c) Sanitização:** payload do canal carrega só `tenant_id`/`key` — **nunca** o valor da config (que pode ser chave de API). Descrição sem segredo.

### 5.4 DoD
- `UpdateTenantConfig`/`UpsertCoreSetting` refletem nos consumidores **sem restart**; invalidação granular por tenant/chave; evento `config.invalidada` auditado. Subscribe e publish em conexões distintas (sem deadlock). `clippy -D warnings` + `.\infra\test-local.ps1`.

---

## 6. WS-6 — Telas operacionais Flutter (bloco principal — construção nova)

**Estado real:** `smart-core-admin` tem login pronto e DI por `installModules` (bootstrap.dart). `core_module` **não** tem telas operacionais. O `design_system_module` tem tokens + widgets base (`AppScaffold`, `AppCard`, `PrimaryButton`, `AppTextField`, `AppErrorView`). O backend de stream (`realtime.rs` + RPC `StreamAtendimentos`) está pronto, **mas o stub Dart do stream ainda não foi gerado**.

> **Decisão de módulo:** as telas operacionais são uma **nova feature** num módulo dedicado. Recomenda-se um `operacional_module` (ou feature `operacional/` dentro de um módulo de atendimento), seguindo a estrutura `data/domain/presentation` do `login_module`/`admin_module`, e registrado em `bootstrap.dart` via `installModules`. Componentes visuais reutilizáveis vão para `design_system_module`.

### 6.1 Tarefas (ordem)
1. **WS-6.0 — Regerar o stub gRPC-Web do stream.** O `.proto` já declara `StreamAtendimentos returns (stream AtendimentoEvent)`, mas `admin.pbgrpc.dart` **não** expõe `streamAtendimentos`. Regerar os stubs Dart (mesma toolchain que gerou `exportTenantsCsv` como `ResponseStream<...>`) para obter `ResponseStream<AtendimentoEvent> streamAtendimentos(StreamAtendimentosRequest, {metadata})`. **Pré-requisito de WS-6.3.**
2. **WS-6.1 — `AtendimentoDataSource` abstrato (RemoteOnly).** Port Dart abstrato (DIP/LSP) com as operações da tela: listar fila por departamento, mover card de etapa, abrir stream de eventos, enviar mensagem outbound. Implementação `AtendimentoRemoteDataSource` via gRPC-Web (`AdminServiceClient`), injetada por `get_it`. **Garante o port Web/F10 futuro** (trocar por `LocalEngineFFI` sem mexer nas telas). Datasources seguem o padrão `Datasource<T>` + `mapGrpcError` + `ReturnSuccessOrError` do `login_grpc_datasource.dart`.
3. **WS-6.2 — Fila por departamento + Kanban (drag-and-drop).**
   - **Decisão de drag-and-drop:** usar **`Draggable`/`DragTarget` nativos do Flutter** (sem dependência nova). Justificativa: o MVP precisa só de mover card entre colunas de etapa; o nativo cobre isso, evita uma dep externa não documentada na central, e mantém o `flutter analyze` limpo. **`appflowy_board` fica como alternativa rejeitada para o MVP** (se no futuro surgir necessidade de board complexo — reorder dentro da coluna, virtualização — reabrir a decisão e **criar `doc_dev/libs/flutter/appflowy_board.md` antes de codar**, conforme a memória "doc local primeiro").
   - Estado das colunas/cards com **`flutter_bloc` 9.1.1** (`Cubit`/`Bloc` + `BlocBuilder`); mover card despacha um evento → caso de uso → `AtendimentoDataSource.moveStage` → RPC. **O filtro de fluxo é server-side (WS-5a)**; a UI só renderiza o que vem.
   - Componentes (coluna, card, área de drop) no `design_system_module`.
4. **WS-6.3 — Chat lateral (streaming).** Consome o stub `streamAtendimentos` (WS-6.0): `ResponseStream<AtendimentoEvent>` sobre `GrpcWebClientChannel` (já criado em `GrpcApiClient`). **JWT no metadata** já é injetado pelo `AuthTokenInterceptor`. **Reconexão com backoff exponencial** ao encerrar o stream (o `ResponseStream` completa/erra → reabrir após backoff com jitter). Estado do chat com `flutter_bloc`. **Envio outbound** pela mesma `AtendimentoDataSource` (RPC unário ao backend de outbound já existente).
5. **WS-6.4 — Navegação e sessão.** Rotas das telas operacionais com **`go_router` 17.3.0** + guarda de sessão (redirect para login se sem token, padrão `auth_redirect.dart`); refresh/access token em **`flutter_secure_storage` 9.x** (reusar `token_local_datasource.dart`/`secure_local_storage_service.dart` do login). DI por `get_it` 9.2.1 via módulo registrado no `bootstrap.dart`.

### 6.2 SOLID / Ports & Adapters (Flutter)
- **Port (Dart):** `AtendimentoDataSource` (abstrato, RemoteOnly hoje; `LocalEngineFFI` no F8). **LSP:** trocar a fonte sem mudar a tela. **DIP:** telas/controllers dependem da abstração via `get_it`, nunca do stub gRPC direto. **SRP:** um datasource por fronteira (stream vs unário), controllers `flutter_bloc` só orquestram estado, sem I/O direto.

### 6.3 Observabilidade & Auditoria
- **(a) Logs/traces:** o cliente propaga `traceparent` nas chamadas; logs de erro de UI **sem PII**. Erros de stream → log estruturado de reconexão (tentativa/backoff), sem conteúdo de mensagem.
- **(b) Auditoria:** *sem evento de auditoria próprio do cliente* (intencional — auditoria é **server-side**). Mover card e enviar mensagem disparam eventos auditados no `runtime_api`/`worker` (`kanban.movido`, `mensagem.enviada`).
- **(c) Sanitização:** **nunca** logar conteúdo de mensagem nem telefone completo na UI; tokens só em `flutter_secure_storage`.

### 6.4 DoD
- Stub do stream gerado; fila por departamento carrega; mover card entre etapas persiste (e respeita `flow_permissions` server-side); chat lateral recebe eventos em tempo real **contra o `runtime_api` real** (não mock), reconecta com backoff ao cair; envio outbound funciona. `flutter analyze` limpo via `.\infra\test-flutter.ps1`.

---

## 7. WS-7 telas — Telas admin Flutter (endurecimento + lacunas)

**Estado real (recalibrado):** o `admin_module` **já tem** páginas, controllers, usecases, datasources e models para tenants, billing (planos/assinatura/pagamentos), dashboard, feature_flags, audit, core_settings, evolution e tenant_config — todos consumindo as 18 rotas admin já expostas. O escopo real é **fechar lacunas e endurecer**, não construir do zero.

### 7.1 Tarefas (lacunas a confirmar/fechar)
1. **WS-7.1 — Auditoria de cobertura das 18 rotas.** Mapear cada rota (`ListTenants/GetTenant/UpdateTenant/SetTenantActive/GenerateAccessCode/ListPlans/CreatePlan/UpdatePlan/ListSubscriptions/RegisterPayment/ListPayments/QueryAuditLog/GetServiceHealth/GetDashboardSummary/ExportTenantsCsv/ListFeatureFlags/SetFeatureFlag/SetFeatureFlagOverride`) → usecase/tela existente. Os usecases já presentes cobrem a maioria (`list_tenants`, `get_tenant`, `update_tenant`, `set_tenant_active`, `generate_access_code`, planos, pagamentos, feature flags, audit, dashboard, export). **Entregável:** lista das rotas **sem** tela/fluxo completo.
2. **WS-7.2 telas — Fluxos de detalhe tenant.** Garantir lista→detalhe→editar→ativar/desativar encadeados (lista + usecases existem; confirmar a **navegação `go_router`** entre eles e o detalhe).
3. **WS-7.3 telas — Convites.** Verificar se há tela de **convites** (geração/listagem) — não há `invite` óbvio no `admin_module` (há `generate_access_code`). Se o fluxo de convite de tenant_user for requisito, construir tela consumindo a rota correspondente; **caso a rota não exista**, sinalizar dependência de backend (fora do escopo das 18 rotas atuais).
4. **WS-7.4 telas — Endurecimento transversal:** estados de erro/empty/loading com `AppErrorView`; paginação onde as respostas são listas; CSV export com `ResponseStream` (já há `export_tenants_csv_usecase`). Tudo via `flutter_bloc`.

### 7.2 SOLID / Ports & Adapters (Flutter)
- Já segue o padrão: `AdminServiceClient` (stub) → `admin_grpc_datasource.dart` → `admin_service_impl.dart` (services de domínio) → usecases → controllers (`flutter_bloc`) → pages. **DIP:** controllers dependem do service de domínio, não do stub. Endurecer mantendo essa estratificação; nenhum novo port estrutural esperado (a menos que convites exijam novo datasource).

### 7.3 Observabilidade & Auditoria
- **(a) Logs/traces:** cliente propaga `traceparent`; logs de UI sem PII.
- **(b) Auditoria:** *sem evento próprio do cliente* — o `runtime_api` audita as mutações admin (`tenant.atualizado`, `plano.alterado`, `pagamento.lancado`, `api_key.update`, `config.atualizada`, `feature_flag.*`), agora com `user_agent` (WS-5b).
- **(c) Sanitização:** tokens/refresh só em `flutter_secure_storage`; chaves de API exibidas mascaradas, nunca em log.

### 7.4 DoD
- As 18 rotas com cobertura de tela mapeada e lacunas fechadas; fluxos lista→detalhe→editar→ativar operando **contra o `runtime_api` real**; estados de erro/empty tratados. `flutter analyze` limpo via `.\infra\test-flutter.ps1`.

---

## 8. WS-0.3 — Teste e2e de cadeia de trace

**Objetivo:** um teste que segue um `traceparent`/`trace_id` W3C do **webhook → bus → worker → RPC data_postgres → linha em `audit_log`**, validando que o mesmo `trace_id` percorre toda a cadeia (a semeadura no webhook e a propagação nos RPCs já existem da base WS-1/WS-2).

### 8.1 Tensão com a diretriz de testes (sinalizada)
A skill de `final-review` proíbe **criar** testes por iniciativa própria; aqui o teste e2e é **entregável explícito** deste plano. **Ação obrigatória:** **alinhar com o dono antes de codar** — confirmar que este teste é desejado como parte do MVP de endurecimento. Sem o aceite, WS-0.3 fica **bloqueado/parqueado** e os demais WS seguem.

### 8.2 Execução (se aprovado)
- Rodar via **`.\infra\test-local.ps1`** (sobe túnel SSH via `test_support` + `SQLX_OFFLINE`).
- Injetar um evento de webhook conhecido → afirmar que a linha gravada em `audit_log` carrega o **mesmo `trace_id`** semeado, e que nada sensível (telefone completo/payload bruto) vazou no caminho.

### 8.3 Observabilidade & Auditoria
- **(a) Logs/traces:** o próprio teste **valida** a continuidade do `trace_id`.
- **(b) Auditoria:** valida que a linha de `audit_log` é gravada com os metadados mínimos.
- **(c) Sanitização:** confirma que nada sensível vaza na cadeia.

### 8.4 DoD
- Aceite do dono obtido; teste verde via `.\infra\test-local.ps1` demonstrando `trace_id` contínuo do webhook ao `audit_log`.

---

## 9. Cronograma relativo (sprints relativos, sem datas fixas)

| Sprint | Workstreams | Marco |
|---|---|---|
| **R1** | **WS-5a** (RBAC fino) + início **WS-6.0/6.1** (stub stream + DataSource) | Contrato regenerado; base das telas operacionais pronta |
| **R2** | **WS-6.2/6.3/6.4** (fila + Kanban + chat streaming + nav) ‖ **WS-5b** (user_agent) ‖ **WS-7.2** (cache invalidation) | **Telas operacionais funcionais** ponta-a-ponta; backend endurecido |
| **R3** | **WS-7 telas** (endurecimento admin) ‖ **WS-0.3** (e2e trace, se aprovado) | Back office endurecido; cadeia de trace validada |
| **R4** | Consolidação, polish de UX, fechamento de DoD por WS | **MVP de telas + endurecimento** completo |

> **Caminho crítico:** WS-6 (telas operacionais novas) é o maior bloco. WS-5a o precede apenas no recorte do Kanban. O endurecimento (5b/7.2/0.3) corre em paralelo (‖) sem bloquear as telas.

---

## 10. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Regeneração do `Envelope` (WS-5a) quebra (de)serialização em algum serviço | Build do workspace inteiro falha | Campo **aditivo** (field 14 / `#[serde(default)]`); rodar `clippy -D warnings` + `.\infra\test-local.ps1` no **workspace todo** após `flatc`/`tonic-build`; confirmar `flatc 25.x` no ambiente local (já no CI) |
| Decisão A vs B do `flow_permissions` (JWT vs RPC) escolhida errada | Revogação atrasada de acesso (A) ou custo no caminho quente (B) | Recomendado **B + cache TTL curto invalidável**; **confirmar com o dono** antes de codar |
| `appflowy_board` adotado sem doc local | Dep externa não validada na central | **Decisão: usar `Draggable`/`DragTarget` nativos** no MVP; só reabrir com `doc_dev/libs/flutter/appflowy_board.md` criado antes |
| Stub Dart do stream não regenerado | Chat não compila | **WS-6.0 é pré-requisito** explícito de WS-6.3 |
| Reconexão do stream gRPC-Web instável | Chat "morre" silenciosamente | Backoff exponencial com jitter + indicador de estado de conexão na UI; `BroadcastStreamRecvError::Lagged` já tratado no server |
| Subscribe e publish na mesma conexão Redis (WS-7.2) | Deadlock/erro | Conexão **dedicada** (`into_pubsub`) para subscribe, **multiplexed** para publish — regra do `realtime.rs` |
| `user_agent` plumbing toca muitos call-sites (WS-5b) | Ripple amplo | `AuditContext` + wrappers retrocompatíveis: só os eventos críticos migram; o resto não muda |
| WS-0.3 colide com a diretriz "não criar testes" | Bloqueio de processo | **Alinhar com o dono**; parquear se não aprovado |
| WS-7 telas: convites podem não ter rota backend | Tela sem endpoint | WS-7.1 mapeia cobertura primeiro; sinalizar dependência de backend se faltar rota |
| Ambiente remoto/túnel instável | Trava integração | `test_support` (túnel SSH + `SQLX_OFFLINE`) + reset de schema; transport TCP em Windows (memória `transport-windows-tcp`) |

---

## 11. Estratégia de testes

- **Rust:** **sempre** via **`.\infra\test-local.ps1`** (nunca `cargo test` direto — sobe túnel via `test_support` + `SQLX_OFFLINE`). WS-5a: testes de isolamento de fluxo (atendente com/sem fluxo, bypass admin) já cobertos parcialmente em `security.rs` — estender para o caminho ponta-a-ponta. WS-5b: verificar `user_agent` persistido. WS-7.2: invalidação reflete sem restart (subscribe/publish em conexões distintas). `#[sqlx::test]` com transação+rollback onde couber.
- **Flutter:** via **`.\infra\test-flutter.ps1`** (nunca `flutter test` direto). Telas exercitam o fluxo real contra o `runtime_api` (não mock): WS-6 (fila/kanban/chat streaming/outbound), WS-7 (CRUD admin).
- **e2e de fundação:** WS-0.3 (cadeia de trace) — **mediante aceite do dono**.
- **DoD comum:** compila + `cargo clippy -D warnings` / `flutter analyze` limpo + testes verdes + observabilidade/auditoria cumpridas por etapa.

---

## 12. Glossário de eventos de auditoria (estende §8 do plano base)

> Convenção `<dominio>.<acao>` em snake. Descrição **sem segredo**. Reusa/estende o glossário do plano base arquivado.

| Evento | Nível | Quando | WS |
|---|---|---|---|
| `autorizacao.negada` | WARN | RBAC barrou por escopo **ou por fluxo** (`flow_permissions`); contexto: `fluxo_id`, `user_id`, `ip`, `user_agent` — sem listar permissões | WS-5a |
| `config.invalidada` | INFO | Entrada do `TenantConfigCache` invalidada via Pub/Sub (só `tenant_id`/`key`, sem valor) | WS-7.2 |
| `config.atualizada` / `api_key.update` | INFO | Mutação de TenantConfig (descrição sem o segredo) — **já existente**, agora propaga invalidação e carrega `user_agent` | WS-7.2 / WS-5b |
| `tenant.atualizado` / `tenant.criado` | INFO | Mutações admin de tenant (inclui `owner_id`) — **já existentes**, agora com `user_agent` | WS-7 telas / WS-5b |
| `plano.alterado` / `pagamento.lancado` | INFO | Subscription / PaymentRecord manual — **já existentes**, agora com `user_agent` | WS-7 telas / WS-5b |
| `tenant_user.role_change` | WARN | Mudança de cargo/permissões (TenantUser), com `user_agent` | WS-5b |

> **Sobre `user_agent` (WS-5b):** não cria evento novo — **enriquece** os eventos críticos existentes (doc 08 §4.2) com o metadado faltante. Telas Flutter (WS-6/WS-7) **não** emitem auditoria própria (server-side).

---

## 13. Correções aplicadas (pedido inicial → ajuste → fonte)

| Item do pedido | Correção aplicada | Fonte |
|---|---|---|
| WS-7 telas admin "a construir" (tenants/planos/convites/flags/dashboard) | **JÁ EXISTEM** em `admin_module` (pages/controllers/usecases/datasources/models). WS-7 vira **endurecimento + mapeamento de lacunas**, não construção do zero | `clients/modulos/admin_module/lib/src/features/config/**` |
| WS-6 chat "consumindo o server streaming `StreamAtendimentos`" como se exigisse backend | **Backend de stream já pronto** (`realtime.rs` fan-out Redis + RPC no `.proto`). WS-6 só **consome** | `runtime_api/src/realtime.rs`; `admin.proto:418` |
| WS-6 chat presumindo stub Dart pronto | **Stub Dart do stream NÃO existe** (`admin.pbgrpc.dart` só tem `exportTenantsCsv`). Adicionada **WS-6.0: regerar stub** como pré-requisito | `api_client/.../admin.pbgrpc.dart:213` |
| Kanban: `appflowy_board` vs nativo | **Decisão: `Draggable`/`DragTarget` nativos** (sem dep nova; cobre o MVP; central sem doc do pacote). `appflowy_board` rejeitado p/ MVP — criar doc local antes se reabrir | info_aux §"Decisão em aberto"; memória "doc local primeiro" |
| WS-5b `user_agent` via "novo parâmetro nas assinaturas" | **`AuditContext`** (struct de metadados) + métodos `_ctx` + wrappers retrocompatíveis — em vez de 9º param posicional; só eventos críticos migram | `observability/src/audit.rs:1-3,252` (já tem `too_many_arguments`) |
| WS-5a `flow_permissions` "claim no JWT OU RPC — avaliar" | Recomendado **RPC ao data_postgres + cache TTL curto** (revogação fresca, JWT enxuto, alinha "banco só via infra/RPC"); confirmar com dono | memória "banco-unica-porta"; doc 08 §5.2 |
| WS-5a campo no Envelope | Campo **14** no `envelope.proto` (após `auth_is_superuser=13`) + slot nas tabelas FB `envelope.fbs`/`all_schemas.fbs`; aditivo/retrocompatível | `contracts/schemas/envelope.proto:18-34` |
| `RequestContext` "estender com flow_permissions" | **Já tem** o campo + `has_flow_permission()` testado; só falta **popular** (vem `vec![]` de `contexto_do_envelope:18`) | `infrastructure_postgres/src/security.rs:17,32` |
| WS-7.2 cache "implementar" | `TenantConfigCache` **já plugado** no AppState; falta só o **subscriber de invalidação** | `data_postgres/src/main.rs:39` |
| WS-0.3 teste e2e | **Sinalizada a tensão** com a diretriz "não criar testes" — **alinhar com o dono** antes; parquear se não aprovado | skill final-review; pedido §WS-0.3 |
| Versões de libs | Respeitadas as reais (info_aux): flutter_bloc 9.1.1, get_it 9.2.1, go_router 17.3.0, flutter_secure_storage 9.x, grpc dart 5.1.0, redis 0.25, tonic-web 0.14.1, flatbuffers 25.x, opentelemetry 0.24, secrecy 0.10.3 | `info_aux_mvp-telas-e-endurecimento.md` |

---

## 14. Frontmatter PREVC (para canonização)

Cada WS abaixo é uma fase do workflow PREVC; o corpo técnico está nas seções 3–8.

| Fase (WS) | P (Planning) | R (Review) | E (Execution) | V (Validation) | C (Confirmation) |
|---|---|---|---|---|---|
| **WS-5a RBAC fino** | Decidir JWT vs RPC (recomendado RPC+cache) | Aprovar contrato aditivo do Envelope + port `FlowPermissionsProvider` | Regerar contrato; popular envelope; filtrar Kanban | `test-local.ps1`: isolamento de fluxo + `autorizacao.negada` auditado | Workspace verde; doc do evento |
| **WS-5b user_agent** | `AuditContext` + migration | Aprovar struct/migration aditivas | Payload+métodos+migration+INSERT+plumbing borda | `test-local.ps1`: `user_agent` persistido; call-sites antigos OK | clippy verde |
| **WS-7.2 cache invalidation** | Canal `core:settings:invalidate` | Aprovar ports pub/sub separados | Subscriber dedicado + publisher multiplexed | `test-local.ps1`: reflete sem restart | `config.invalidada` auditado |
| **WS-6 telas operacionais** | `operacional_module` + ports Dart | Aprovar `AtendimentoDataSource` + nativo p/ DnD | Stub stream; fila; kanban; chat; nav | `test-flutter.ps1` contra runtime real | `flutter analyze` limpo |
| **WS-7 telas admin** | Mapear cobertura das 18 rotas | Aprovar plano de lacunas | Fechar fluxos detalhe/editar/ativar/convites | `test-flutter.ps1` contra runtime real | estados de erro/empty OK |
| **WS-0.3 e2e trace** | **Alinhar diretriz com dono** | Aceite do dono | Teste de cadeia de trace | `test-local.ps1`: `trace_id` contínuo | parqueado se não aprovado |

---

*Plano reestruturado e aterrado no código real + doc atual de libs (todas validadas na central local `doc_dev/libs/`). Pronto para canonização via MCP dotcontext (`scaffoldPlan` + `workflow-init`) referenciando `info_aux_mvp-telas-e-endurecimento.md` e este documento.*
