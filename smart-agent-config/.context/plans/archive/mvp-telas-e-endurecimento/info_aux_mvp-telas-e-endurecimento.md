# Documentação Auxiliar — MVP: Telas & Endurecimento

> Gerado em: 2026-06-30
> Plano canônico: `.context/plans/mvp-telas-e-endurecimento.md`
> Plano completo: `.context/plans/mvp-telas-e-endurecimento/plano_completo_mvp-telas-e-endurecimento.md`
> Origem: conversa (continuação do ciclo `finalizacao-mvp-operacional`, fechado como parcial WS-0..WS-4).

## Triagem da central local (etapa 2a)

**Todas as libs deste plano estão `✅ ATUALIZADA` na central `doc_dev/libs/` — USAR LOCAL.**
Nenhuma chamada a Context7/WebSearch foi necessária. Referências abaixo apontam para a
central com a respectiva data de `Última Verificação`.

| Lib | Stack | Versão | Verificação | Doc local |
|---|---|---|---|---|
| flutter_bloc | flutter | 9.1.1 (bloc 9.2.1) | 2026-06-14 | `doc_dev/libs/flutter/flutter_bloc.md` |
| get_it | flutter | 9.2.1 | 2026-06-14 | `doc_dev/libs/flutter/get_it.md` |
| go_router | flutter | 17.3.0 | 2026-06-14 | `doc_dev/libs/flutter/go_router.md` |
| flutter_secure_storage | flutter | 9.2.3+ | 2026-06-14 | `doc_dev/libs/flutter/flutter_secure_storage.md` |
| grpc (dart) | flutter | 5.1.0 | 2026-06-18 | `doc_dev/libs/flutter/grpc.md` |
| return_success_or_error | flutter | 2.0.0 | 2026-06-14 | `doc_dev/libs/flutter/return_success_or_error.md` |
| redis | rust | 0.25.0 | 2026-06-10 | `doc_dev/libs/rust/redis.md` |
| tonic-web | rust | 0.14.1 | 2026-06-18 | `doc_dev/libs/rust/tonic-web.md` |
| flatbuffers | rust | 25.x (flatc 25.12.19) | recente | `doc_dev/libs/rust/flatbuffers.md` |
| secrecy | rust | 0.10.3 | 2026-06-01 | `doc_dev/libs/rust/secrecy.md` |
| sqlx | rust | 0.9.0 | 2026-06-10 | `doc_dev/libs/rust/sqlx.md` |
| opentelemetry | rust | 0.24 (projeto) | 2026-06-10 | `doc_dev/libs/rust/opentelemetry.md` |

> **Decisão em aberto (Kanban drag-and-drop):** `appflowy_board` **não tem doc local**.
> Adoção indecisa. Alternativas: `appflowy_board` (criar doc se adotado), ou
> `Draggable`/`DragTarget` nativos do Flutter (sem dependência nova — preferível para o MVP).
> Resolver na fase de design da WS-6; se adotar pacote externo, criar
> `doc_dev/libs/flutter/<pacote>.md` antes de codar.

---

## Notas de API por frente (extraídas da central + código atual)

### Front-end (WS-6 / WS-7 telas)

**Monorepo Flutter** (`clients/`): app `smart-core-admin` + módulos `admin_module`,
`core_module`, `design_system_module`, `navigation_module`, `presentation_module`,
`login_module` + package `api_client`. Padrão já estabelecido pelo `login_module`
(Frente B do ciclo login): gRPC-Web via `api_client`, DI com `get_it`, navegação
`go_router`, sessão em `flutter_secure_storage`, estado com `flutter_bloc`, fronteiras
retornando `ReturnSuccessOrError`.

- **gRPC-Web streaming (chat realtime — consome `StreamAtendimentos` da WS-4):**
  cliente dart usa `ResponseStream` sobre `GrpcWebClientChannel` (browser). O server
  streaming É suportado em gRPC-Web. Token JWT no metadata na abertura; reconectar com
  backoff ao encerrar. Ver `doc_dev/libs/flutter/grpc.md` (5.1.0).
- **Admin (WS-7 telas):** consome as **18 rotas admin superusuário já expostas no
  runtime_api** (commit `6b28255`) via `handler_admin_forward` — todas unárias gRPC-Web.
- **DataSource RemoteOnly** desde já (garante o port Web/F10 futuro): telas dependem da
  abstração injetada por `get_it`; LSP para trocar por LocalEngineFFI depois.

### Back-end / endurecimento

- **WS-5 RBAC fino (`flow_permissions`):** hoje `contexto_do_envelope`
  (`data_postgres/src/main.rs:13`) seta `flow_permissions: vec![]`. O `RequestContext`
  (`infrastructure_postgres/src/security.rs`) **já tem** o campo + `has_flow_permission()`.
  Falta: (1) adicionar `flow_permissions: [int]` ao `Envelope` no contrato
  (`crates/contracts/schemas` + regenerar FlatBuffers com `flatc 25.x`/`tonic-build`);
  (2) `exigir_auth` (`runtime_api/src/main.rs:282`) carregar `TenantUser.flow_permissions`
  (RPC novo ao `data_postgres` ou claims do JWT) e popular o envelope; (3)
  `contexto_do_envelope` ler do envelope em vez de `vec![]`.
- **WS-5 `user_agent` no `AuditLogPayload`** (`observability/src/audit.rs`): exigido pelo
  doc 08 §4.2. Mudança cross-cutting: novo campo no payload + parâmetro nas assinaturas de
  `AuditLogger::{info,warn,error,*_global}` (muitos call-sites) + coluna `user_agent` em
  migration nova da `audit_log` (atual: `migrations/0010_audit_log.sql`) + INSERT no
  consumer de auditoria do `data_postgres`. Estratégia para reduzir ripple: considerar um
  struct de contexto opcional (`AuditContext { user_id, ip, user_agent, trace_id }`) em vez
  de mais parâmetros posicionais.
- **WS-7.2 invalidação do `TenantConfigCache`** (`infrastructure_postgres`): subscriber
  Redis Pub/Sub no canal `core:settings:invalidate`. **API redis 0.25** (idêntica ao
  fan-out da WS-4): conexão **dedicada** `client.get_async_connection().await?.into_pubsub()`
  + `subscribe()` + `on_message()` (Stream); publisher em `MultiplexedConnection`
  (`get_multiplexed_async_connection`). Publicado pelos handlers `UpdateTenantConfig` /
  `UpsertCoreSetting` do `data_postgres` ao gravar config. NUNCA subscribe e publish na
  mesma conexão. Ver `doc_dev/libs/rust/redis.md` (0.25).
- **WS-0.3 teste e2e de trace:** seguir um `trace_id`/`traceparent` W3C do webhook → bus →
  worker → RPC `data_postgres` → linha em `audit_log`. `traceparent` já é semeado no webhook
  (WS-1) e propagado nos RPCs do worker (WS-2/2.4). Rodar via `.\infra\test-local.ps1`
  (sobe túnel SSH + `SQLX_OFFLINE`). **Observar a diretriz do projeto sobre testes** (a skill
  de final-review proíbe criar testes; aqui o teste é entregável explícito do plano — alinhar
  com o dono antes de codar).

---

## Grupo C — Observabilidade & Auditoria (transversal, por frente)

| Frente | Logs/trace | Auditoria (`audit_log`) | Sanitização |
|---|---|---|---|
| WS-6 telas operacionais | cliente propaga `traceparent`; logs de erro de UI sem PII | *sem evento próprio* (auditoria é server-side; ações disparam eventos no runtime_api/worker) | nunca logar conteúdo de mensagem/telefone completo na UI |
| WS-7 telas admin | idem cliente | *sem evento próprio* (o runtime_api audita as mutações admin) | tokens/refresh em `flutter_secure_storage`, nunca em log |
| WS-5 flow_permissions | span no `exigir_auth` ao carregar permissões; `autorizacao.negada` (WARN) quando barra por fluxo | acesso negado a fluxo é evento de segurança | não logar o conjunto de permissões em claro desnecessariamente |
| WS-5 user_agent | — | **habilita** os metadados mínimos exigidos (08 §4.2) nos eventos críticos (Tenant/owner_id, TenantInvite, TenantUser, Subscription/PaymentRecord, api_key) | `user_agent` é metadado, não segredo; descrição sem segredo |
| WS-7.2 cache invalidation | span `config.invalidada`; log estruturado da recepção do evento | `config.invalidada` (INFO) já no glossário (§8 do plano base) | canal/payload sem segredos (só chave/tenant) |
| WS-0.3 e2e trace | o próprio teste valida a cadeia de `trace_id` | valida que a linha de `audit_log` é gravada | confirma que nada sensível vaza no caminho |

---

## Notas Gerais

- **DoD transversal (herdado, inegociável):** observabilidade (span `tenant_id`/`trace_id`,
  `traceparent` propagado, ≥1 evento de auditoria por ação relevante, sem segredos/PII em log)
  + SOLID/Ports & Adapters (casos de uso dependem de traits; um adapter por fronteira).
- **Base já pronta (NÃO replanejar):** WS-0.1 (stack LGTM em `docker/observability/`), WS-0.4
  (`pool-metrics` habilitada), WS-1..WS-4, WS-2.4, WS-5 forward routes, WS-7 admin routes,
  RBAC por escopo ponta-a-ponta. Plano de origem arquivado em
  `.context/plans/archive/finalizacao-mvp-operacional/`.
- **Validação:** Rust via `.\infra\test-local.ps1` / `.\infra\test-quick.ps1`; Flutter via
  `.\infra\test-flutter.ps1`. Telas exercitam o fluxo real contra o `runtime_api` (não mock).
- **Regeneração de contrato (WS-5):** alterar `Envelope` exige `protoc`/`flatc` no ambiente
  (já instalados no CI; localmente confirmar) e afeta todos os serviços que (de)serializam o
  envelope — testar o workspace inteiro após a mudança.
