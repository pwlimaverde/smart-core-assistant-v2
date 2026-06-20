# Final Review — painel-admin-superusuario
Data: 2026-06-20 · Modelo: Opus · Diff: commit 073d4d2 (escopo do plano)

## Rótulo: CORRIGIDO  (informativo — não bloqueia o ciclo)

## Resumo das correções

A implementação do commit 073d4d2 está sólida e cobre as Fases F0→6, a guarda crítica
`exigir_superuser_do_metadata`, a cifragem/masking e o `TestEvolutionConnection` sem
vazar credencial. O principal problema encontrado foi de **auditoria**: o requisito
inviolável "toda mutação de estado sensível gera audit_log" estava **parcialmente**
atendido — várias mutações novas não emitiam evento. Todos os pontos foram corrigidos:

1. **Feature flags sem auditoria** (`handler_set_feature_flag`, `handler_set_feature_flag_override`) — adicionado `feature_flag_set`.
2. **Criação de tenant sem auditoria** (`handler_create_tenant`) — adicionado `tenant_created` (alteração cadastral exigida pela diretriz §4.2). Exigiu passar `redis_conn` ao handler/rota e ajustar o teste existente.
3. **Mudança de chave de API sem evento dedicado** — adicionado `tenant_api_key_changed` (WARN) com `chaves_alteradas` (só nomes) no `handler_update_tenant_config`.
4. **`TestEvolutionConnection` sem auditoria nem `#[tracing::instrument]`** — adicionado evento `connection_tested` na fachada gRPC-Web e `#[tracing::instrument(skip_all)]` nos handlers do `control_plane`.
5. **SuperuserGuard no Flutter só checava `isAuthenticated`** — passou a exigir `isSuperuser` (defesa em profundidade exigida no DoD B.1); teste do guard atualizado.

Registra-se também a **contradição de status**: o front-matter do plano marcava
R=in_progress e E/V/C=pending, mas a feature está implementada por inteiro no commit
073d4d2. O status foi alinhado pelo agente principal no fechamento do ciclo.

## 1. Plano vs. Implementado

| Item | Status | Observação |
|---|---|---|
| F0 — `admin_module`, shell, `admin.proto`, build.rs, CoreSettings ponta a ponta | ✅ | Módulo Flutter Clean Arch completo; proto registrado no build.rs |
| F0 — Guarda `exigir_superuser_do_metadata` (JWT + blocklist Redis + is_superuser) | ✅ | `grpc_web.rs` espelha fielmente o `exigir_auth`; auditoria de acesso negado OK |
| F1 — Config global (CoreSettings) + por tenant (TenantConfig) | ✅ | Masking `••••••••` server+client; update preserva valor cifrado |
| F2 — Tenants (List/Get/Create/Update/SetActive/GenerateAccessCode) | ✅ (após correção) | `tenant_created` faltava auditoria → corrigido |
| F2 — Billing (planos/assinaturas/pagamentos) | ⚠️ | Pagamento NÃO estende `current_period_end` da subscription (ver §5) |
| F3 — Evolution (`TestEvolutionConnection` + cliente reqwest/secrecy) | ✅ (após correção) | Não vazava credencial; faltava audit `connection_tested` e instrument → corrigido |
| F4 — Feature flags (migration + CRUD + override) | ✅ (após correção) | Migration/RLS OK; faltava auditoria das mutações → corrigido |
| F5 — Auditoria & Dashboards (QueryAuditLog, GetServiceHealth, GetDashboardSummary, ExportCsv server-stream) | ✅ | CSV via server-streaming, conforme limitação do browser |
| F6 — Operacional por tenant | ➖ | Fora do diff auditado; sem itens novos a verificar aqui |
| DoD — guarda superuser na fachada gRPC-Web | ✅ | Aplicada em todos os RPCs admin |
| DoD — SuperuserGuard no Flutter | ✅ (após correção) | Passou a exigir `isSuperuser` |
| DoD — campos cifrados nunca exibem valor; máscara preserva no update | ✅ | Verificado em `handler_update_tenant_config` e nas pages |
| DoD — toda mutação gera auditoria | ✅ (após correção) | 4 lacunas fechadas |
| DoD — `cargo clippy -D warnings` / `flutter analyze` limpos | ✅ | Ambos limpos (revalidado) |
| DoD — enums proto via `TryFrom<i32>` | ✅ | Sem `from_i32()` |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| `server/apps/data_postgres/src/main.rs` (handler_set_feature_flag ~2960) | Mutação de flag global sem audit | Emite `feature_flag_set` (escopo global, sem segredos) |
| `server/apps/data_postgres/src/main.rs` (handler_set_feature_flag_override ~3050) | Override por tenant sem audit | Emite `feature_flag_set` (escopo tenant) |
| `server/apps/data_postgres/src/main.rs` (handler_create_tenant ~697/283/3545) | Criação de tenant sem audit (exigido §4.2) | Passa `redis_conn`, emite `tenant_created`; rota e teste ajustados |
| `server/apps/data_postgres/src/main.rs` (handler_update_tenant_config ~1809/1960) | Sem evento dedicado para troca de api_key | Coleta `chaves_alteradas` (só nomes) e emite `tenant_api_key_changed` (WARN) |
| `server/apps/runtime_api/src/grpc_web.rs` (test_evolution_connection ~1894) | Teste de conexão sem audit | Emite `connection_tested` (tenant + state, nunca a key) |
| `server/apps/control_plane/src/main.rs` (handler_test_evolution_connection / handler_register_tenant) | Faltava `#[tracing::instrument]` | Adicionado `skip_all` + campos de correlação (sem credencial) |
| `clients/apps/smart-core-admin/lib/auth_redirect.dart` + `app.dart` | Guard só checava autenticação | Passou a exigir `isSuperuser`; não-superuser → `/login` |
| `clients/apps/smart-core-admin/test/auth_guard_test.dart` | Teste desatualizado (esperava `/home`) e sem novo param | Reescrito p/ `isSuperuser` e rota `/admin/core-settings` |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| Guarda gRPC-Web (acesso negado) | ✅ `skip_all` | ✅ `auth_access_denied` | ✅ context `{}` | Conforme ao plano |
| CoreSetting upsert/delete | ✅ instrument | ✅ `core_setting_upserted`/`_deleted` | ✅ só `key` | OK |
| UpdateTenantConfig | ✅ | ✅ `tenant_config_updated` + `tenant_api_key_changed` | ✅ só nomes de chaves | Corrigido |
| Tenant create/update/active/access_code | ✅ | ✅ (`tenant_created` corrigido; demais já presentes) | ✅ sem api_key | Nomes de evento divergem levemente do catálogo §12 (ver §5) |
| Plano create/update | ✅ | ✅ `billing_plan_created/updated` | ✅ | OK |
| RegisterPayment | ✅ | ✅ `payment_registered` | ✅ | Não estende período (§5) |
| Feature flag set/override | ✅ | ✅ `feature_flag_set` | ✅ | Corrigido |
| TestEvolutionConnection | ✅ (corrigido) | ✅ `connection_tested` (corrigido) | ✅ `SecretString`, sem `derive(Debug)`, key só no header | Corrigido |
| ExportTenantsCsv | ✅ | ⚠️ não emite `data_exported` | ✅ | Ver §5 (decisão de não bloquear) |

## 3. Decisões Autônomas (revisar depois)

- ⚠️ **`connection_tested` emitido na fachada (runtime_api), não no `control_plane`.** O `control_plane` não tem conexão Redis/bus (Cargo.toml sem redis/transport::bus); adicionar seria invasivo. A fachada já tem `self.bus` e segue o mesmo padrão dos audits de borda (login/logout). Decisão de menor risco.
- ⚠️ **`tenant_api_key_changed` mantém também o `tenant_config_updated` genérico.** Optou-se por emitir o evento dedicado *além* do genérico para não alterar consumidores existentes do `tenant_config_updated`.
- ⚠️ **RLS de `feature_flag_overrides` não foi alterado.** O `handler_set_feature_flag_override`/`list_feature_flags` operam com `&pool` sem `set_config('app.current_tenant')`. Como `list_feature_flags` lê todos os overrides cross-tenant com sucesso, a role do `data_postgres` faz bypass de RLS para uso administrativo — logo o write também funciona. Verificado como OK.

## 4. Revalidação

| Verificação | Resultado | Nota |
|---|---|---|
| `cargo clippy --all-targets --all-features -- -D warnings` | ✅ | via `infra\test-local.ps1 -Fast` |
| `cargo fmt -- --check` | ✅ | exit 0 |
| `cargo test --workspace --lib --bins` | ✅ | inclui `test_handler_create_tenant` (com novo audit) |
| `flutter analyze` | ✅ | "No issues found!" |
| `flutter test` (12 pacotes) | ✅ | 103 testes, incluindo `smart-core-admin +5` (guard atualizado) |

## 5. Pendências (escopo extra ou fora do plano)

- **DoD parcial — pagamento manual não estende `current_period_end`.** `handler_register_payment` só insere `PaymentRecord`; o DoD pede estender o período da `tenants_subscription`. Não corrigido por exigir decisão de modelagem (qual subscription, criação se inexistente, status). Recomenda-se tarefa de follow-up.
- **`data_exported` não emitido no `ExportTenantsCsv`.** Catálogo §12 prevê o evento; ausência é desvio menor (leitura/exportação, não mutação). Deixado como pendência por não ser mutação de estado.
- **Nomenclatura de eventos diverge do catálogo §12** em alguns casos. Os eventos existem e são sanitizados; alinhamento de nomes é cosmético.
- **`user_agent` não é persistido no audit_log** — `observability::AuditLogPayload` não tem o campo (limitação pré-existente da infra, fora do escopo deste plano).
