# Final Review — mvp-telas-e-endurecimento
Data: 2026-07-05 · Modelo: Opus · Diff: dev...HEAD (escopo: server/apps, server/crates, clients/modulos, clients/apps, clients/packages)

## Rótulo: CORRIGIDO

## Resumo das correções
- **Bug real de RBAC na borda gRPC-Web (WS-5a):** os handlers operacionais da fachada gRPC-Web (`list_atendimentos`, `move_atendimento_etapa`) montavam o `Envelope` para o `data_postgres` **sem popular `flow_permissions`**. Como o painel Flutter operacional fala exatamente por essa fachada (não pelo `transport::Server`), qualquer atendente **não-admin** veria a fila vazia (o filtro em `listar_por_status` descartava todo card com fluxo) e **toda movimentação de card seria negada** (`exigir_fluxo` com vetor vazio). Adicionado o helper `resolver_flow_permissions_web` (mesma estratégia RPC+cache TTL curto do `main::resolver_flow_permissions`) e populado `flow_permissions` nesses dois env_reqs para não-superusuários. Sem essa correção, o WS-5a ficava correto no caminho IPC interno mas quebrado no caminho real do cliente.
- **Log não-estruturado no chat (WS-6):** o `ChatController` usava `print()` (com `// ignore: avoid_print`) para o log de reconexão. Trocado por `dart:developer log()` estruturado (`name`/`error`), eliminando a supressão de lint e mantendo o DoD de "log estruturado de reconexão sem PII".

## 1. Plano vs. Implementado
| Workstream | Status | Observação |
|---|---|---|
| WS-5a | ⚠️→✅ (corrigido) | Contrato (Envelope campo 14), `GetUserFlowPermissions`, `GetCache`/`SetCache`, `exigir_auth`, `contexto_do_envelope`, `exigir_fluxo` e filtro em `listar_por_status` todos presentes e corretos. **Desvio corrigido:** faltava popular `flow_permissions` na fachada gRPC-Web (caminho real do cliente). |
| WS-5b | ✅ | `user_agent` no Envelope (campo 15), `AuditContext` + métodos `_ctx`, wrappers antigos retrocompatíveis (call-sites não quebraram), migration `0013_audit_log_user_agent.sql` (aditiva/nullable), INSERT em `NewAuditLogEntry`/`inserir_audit_log(_global)`, plumbing `user_agent_do_metadata` com truncamento defensivo (512). |
| WS-7.2 | ✅ | Subscriber dedicado no canal `core:settings:invalidate` em **conexão separada** (`get_async_connection().into_pubsub()`), publishers via `ConnectionManager`/`AsyncCommands::publish` (separada do subscribe) em `UpsertCoreSetting`/`DeleteCoreSetting`/`atualizar_tenant_config`. Reconexão com backoff no boot. Invalidação granular por tenant + `invalidate_all` para CoreSettings globais. |
| WS-0.3 | ✅ | `e2e_trace.rs` é real: hops via Redis/Postgres reais (STREAM_EVENTOS → worker consume → STREAM_SEGURANCA → consumidor real `processar_eventos_auditoria_lote` → `audit_log`), usa o traceparent efetivamente consumido (não a variável semeada) e valida sanitização (telefone/payload bruto não vazam). |
| WS-6 | ✅ | `operacional_module` novo com `AtendimentoDataSource` (port abstrato) + `AtendimentoRemoteDataSource` gRPC-Web injetados por `get_it`; Kanban com **DnD nativo** (`Draggable`/`DragTarget`, sem `appflowy_board`); chat com stream realtime + **reconexão backoff exponencial com jitter**; stub Dart `admin.pbgrpc.dart` regenerado com `streamAtendimentos` e RPCs novas. Telas dependem só da abstração, nunca do stub direto. |
| WS-7 telas | ✅ | Endurecimento do `admin_module`: `AppErrorView` nos estados de erro, paginação (audit/billing com limit/offset), navegação lista→detalhe→editar. |
| WS-7.3 (convites) | parqueado (decisão do dono) | Não construído neste ciclo por decisão documentada (fluxo de admin de TENANT, não do painel de superusuário). As RPCs `CreateInvite`/`AcceptInvite` existem no backend, mas não há tela no `admin_module` — correto conforme escopo. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| server/apps/runtime_api/src/grpc_web.rs (`list_atendimentos`) | `env_req` sem `flow_permissions` → fila vazia p/ atendente não-admin no caminho gRPC-Web | Popula `flow_permissions` via novo `resolver_flow_permissions_web` (RPC+cache) para não-superusuário |
| server/apps/runtime_api/src/grpc_web.rs (`move_atendimento_etapa`) | `env_req` sem `flow_permissions` → `exigir_fluxo` negava toda movimentação de não-admin | Idem: popula `flow_permissions` antes do forward |
| server/apps/runtime_api/src/grpc_web.rs (novo `resolver_flow_permissions_web` + `extrair_permissoes_web`) | Faltava a resolução de permissões na borda do browser | Helper espelhando `main::resolver_flow_permissions` (cache-aside GetCache→GetUserFlowPermissions→SetCache TTL 30s) |
| clients/modulos/operacional_module/.../chat_controller.dart | `print()` com `// ignore: avoid_print` (log não-estruturado) | Trocado por `dart:developer log()` estruturado, sem PII, sem supressão de lint |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| RBAC fino negado (fluxo) | `tracing::warn` em `exigir_fluxo` com tenant_id/user_id/flow_id | `autorizacao.negada` (WARN) com user_id/ip/user_agent, sem listar permissões | Não loga o conjunto de fluxos | ✅ conforme doc 08 §4.2 |
| Mover card Kanban | span `MoveAtendimentoEtapa` + traceparent | `kanban.movido` (INFO) com user_agent + fan-out realtime | Sem conteúdo/PII | ✅ |
| Enviar mensagem outbound | span + traceparent | `mensagem.enviada` (INFO) com user_agent, **sem conteúdo** | Conteúdo (PII) nunca logado nem auditado | ✅ |
| Invalidação de config | `tracing::debug` com tenant_id | `config.atualizada`/`api_key.changed`/`core_setting_*` já auditados; invalidação é efeito | Canal carrega só `tenant_id`, nunca o valor da config | ✅ |
| Chat stream reconnect (Flutter) | `developer.log` estruturado (tentativa) | server-side (correto) | Nunca payload/PII no log de UI | ✅ (corrigido de `print`) |

## 3. Decisões Autônomas (revisar depois)
- `resolver_flow_permissions_web` foi adicionado como cópia próxima do `main::resolver_flow_permissions` (duplicação controlada) em vez de extrair para um módulo compartilhado — mantém a fachada gRPC-Web autocontida e evita mexer na visibilidade da função do `main`. Se preferir DRY, dá para promover a um helper `crate::flow_permissions` depois.
- `get_thread`/`send_outbound_message` na borda gRPC-Web **não** recebem `flow_permissions` — deliberado: os handlers correspondentes no `data_postgres` não aplicam filtro de fluxo (só escopo `atendimentos:*`), então seria plumbing morto.

## 4. Revalidação
- cargo fmt: ✅ (aplicado + `--check` limpo)
- cargo clippy (`--workspace --all-targets -D warnings`, SQLX_OFFLINE): ✅ sem warnings
- flutter analyze (operacional_module): ✅ "No issues found!"

## 5. Pendências (fora do escopo do plano)
- WS-7.3 telas de convite: parqueado por decisão do dono; quando reabrir, exige desenho de persona (admin de tenant vs superusuário) antes de codar.
- Teste pré-existente `infrastructure_postgres::auditoria::test_audit_log_rls_isolation_enforced` falha no ambiente remoto de dev (role `smartcore_app` é superuser/bypassa RLS) — problema de infra remota compartilhada, não deste ciclo; não corrigível no repo.
