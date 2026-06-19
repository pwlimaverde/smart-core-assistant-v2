# 11 — Painel Gerencial do Superusuário (Plano de Controle Total)

> **Status:** ⬜ Planejado — primeira feature de negócio pós-fundação (login já funciona).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Referência v1:** `old/smart-core-assistant-painel/` — Django admin (global + por-tenant)
> e o "Service Hub" como especificação funcional.
> **Consolidação 2026-06-18:** este documento foi reconciliado com o código real
> (`server/` + `clients/`). Premissas antigas que estavam erradas foram corrigidas na §3.

---

## 1. Objetivo

Construir o **plano de controle total** da aplicação para o **superusuário**: o ponto
único onde toda a plataforma é parametrizada — system prompts, API keys das LLMs,
configuração por tenant, integrações, planos/billing, feature flags, auditoria e
dashboards — sem acesso direto ao banco.

**Escopo (decisão):** este app (`smart-core-admin`) é **superadmin/configuração**. A
operação diária do tenant (chat/kanban/CRM) será outro app cliente. O superusuário pode,
porém, editar a configuração de qualquer tenant alvo (contexto por `tenant_id` no payload).

**Princípio arquitetural:** o Flutter admin fala **exclusivamente com `runtime_api`** via
**gRPC-Web** (app Web/WASM). O `runtime_api` valida o JWT (superusuário) e repassa ao
`data_postgres` (CRUD) e ao `control_plane` (lógica de negócio) por RPC interno. Nenhuma
tela acessa a infraestrutura diretamente.

---

## 2. Decisões desta consolidação

- **Transporte admin:** um `AdminService` gRPC **tipado** (proto) exposto na fachada
  gRPC-Web, espelhando o padrão do `AuthService`.
- **Entrega:** roadmap faseado completo, com um **molde repetível** (§5) aplicado por
  fatias verticais.
- **Auditoria & observabilidade (§12):** toda ação registra o que foi feito e por quem;
  exposição de logs/erros no painel reaproveitando a infra existente.
- **Melhorias de mercado incorporadas (§13):** teste de conexão/health, versionamento de
  config, feature flags dinâmicas, dashboards & cost tracking.
- **State Flutter:** padrão existente — Clean Arch + `return_success_or_error` + get_it
  (`AppModule`/`GetItModule`) + `BaseController`/`ViewStateBuilder` + `design_system_module`.

---

## 3. Realidade do código atual (correções factuais)

Mapeamento do que **já existe** vs **o que falta**, após auditoria de `server/` e `clients/`.

### 3.1 O que JÁ existe (não recriar)

- **Banco modelado quase por completo (migrations 0001–0011, ~35 tabelas com RLS):**
  tenants/config, **billing (`tenants_plan`/`tenants_subscription`/`tenants_paymentrecord`
  na 0003)**, clientes/contatos, operacional (departamentos, fluxos, etapas, atendentes,
  app_instances), atendimentos (tickets, mensagens, campos dinâmicos, etiquetas, notas),
  treinamento/RAG, evolution_sync (0008), audit_log (0010), outbox (0011).
- **Handlers RPC no `data_postgres`** (JSON sobre `Envelope`): `ListCoreSettings`,
  `UpsertCoreSetting`, `DeleteCoreSetting`, `GetTenantConfig`, `UpdateTenantConfig`
  (com cifragem AES-GCM e masking `••••••••` prontos), `CreateTenant`, `CreateSuperuser`/
  `ListSuperusers`/`DeleteSuperuser`, `GetUserIdentity`, `ListAtendimentos`, `GetThread`,
  `PersistMessage`, `UpsertContact`, `VerifyCredentials`.
- **Rotas admin no `transport::Server` do `runtime_api`** (IPC interno) com
  `exigir_auth(..., superuser=true)`: CoreSettings CRUD, TenantConfig get/update,
  GetUserIdentity, StreamAtendimentos.
- **`control_plane` é serviço RPC** (não só CLI): rota `RegisterTenant` (delega a
  `data_postgres::CreateTenant`) + subcomando `create-superuser`. Pronto para ganhar as
  ações complexas (§9).
- **Cifragem:** `infrastructure_postgres::crypto::CipherManager` (AES-256-GCM) +
  `TenantConfigCache` (invalidação via Redis pub/sub).
- **Flutter:** `login_module` (Clean Arch completo), `api_client` (gRPC-Web + protobuf
  gerado `auth.pb.dart`), `design_system_module` (tema gold/stone), `presentation_module`
  (`BaseController`), `navigation_module`, DI via `get_it_module`.

### 3.2 O GARGALO (peça crítica que falta)

O Flutter é **Web/WASM** e só alcança a **fachada gRPC-Web**
([server/apps/runtime_api/src/grpc_web.rs](../../server/apps/runtime_api/src/grpc_web.rs)),
que **hoje só expõe `AuthService`** (Login/Refresh/Logout). **Nenhum endpoint admin chega
ao browser.** As rotas admin existem só no `transport::Server` (IPC interno), inacessível
ao navegador. → Todo endpoint admin precisa ser **exposto na fachada gRPC-Web**.

**[Segurança — crítico]** A fachada gRPC-Web **não tem guarda de superuser** (só `logout`
valida token via metadata). É preciso um helper `exigir_superuser_do_metadata` (JWT +
blocklist Redis + `claims.is_superuser`) replicando o interceptor `exigir_auth`
([runtime_api/src/main.rs](../../server/apps/runtime_api/src/main.rs)). Sem isso, expor
admin via gRPC-Web abriria acesso indevido.

### 3.3 O que NÃO existe (a criar)

- **Handlers RPC** de listagem/edição da maioria dos domínios: `ListTenants`/`GetTenant`/
  `UpdateTenant`/`SetTenantActive`; planos/assinaturas/pagamentos CRUD; tenant users/
  invites; operacional; query de `audit_log`; agregações de dashboard.
- **Repos faltantes:** `TenantRepository::listar`/`atualizar`/`set_active` (hoje só
  `criar`/`buscar_por_id`); repos de plan/subscription/payment.
- **`AdminService` proto** + fachadas gRPC-Web + Dart gerado + `admin_module` Flutter.
- **Feature flags:** não há tabela (migration nova).
- **Cliente HTTP Evolution em Rust** (para "testar conexão"): `messaging_gateway` só
  bootstrapado; não há cliente Evolution real ainda.
- **Cost tracking de LLM:** depende do `ia_engine` (Python/gRPC) que ainda não existe.

### 3.4 Conceitos do old que NÃO se aplicam (não portar)

- **`TenantDatabase` (DB-per-tenant):** obsoleto — a v2 é single-DB + RLS (decisão D4).
- **Flags hardcoded em `settings.py`:** viram feature flags dinâmicas no banco (§13).
- **`TenantEvolution`/`TenantTrello` como tabelas próprias:** consolidados em
  `tenants_tenantconfig` + `evolution_sync_instance` (0008).

---

## 4. Pré-requisitos (dependências de fase)

| Pré-requisito | Status | Nota |
|---|---|---|
| `runtime_api` + fachada gRPC-Web | ✅ parcial | só `AuthService`; estender com `AdminService` |
| `AuthService` (Login/Refresh/Logout) | ✅ | login do superusuário funciona |
| Guarda `is_superuser` na fachada gRPC-Web | 🔴 | **criar `exigir_superuser_do_metadata`** (§3.2) |
| `control_plane` serviço RPC | ✅ | só `RegisterTenant`; estender com ações complexas |
| `data_postgres` repos/handlers | 🟡 | CoreSettings/TenantConfig ok; resto a criar |
| Pipeline de geração Dart de proto | ✅ | precedente `auth.pb.dart` |
| `admin_module` Flutter | 🔴 | criar do zero, espelhando `login_module` |

**Ordem macro:** Fundação (§6) → Fases 1→6 (§7), cada uma aplicando o molde (§5).

---

## 5. Molde repetível ("fábrica" de um recurso admin)

Como são ~14 domínios, padroniza-se **um pipeline** e aplica-se a cada recurso:

1. **Repo Rust** (`infrastructure_postgres/src/...`): `listar`/`buscar`/`criar`/
   `atualizar`/`remover` (muitos já existem; alguns faltam).
2. **Handler RPC** no `data_postgres`: JSON sobre `Envelope`, com `resolver_tenant_alvo`,
   `ok_reply`/`erro`, `publicar_auditoria` (toda mutação auditada com `actor = superuser_id`).
3. **Proto** no `AdminService` (`contracts/schemas/queries/admin.proto`) + registro no
   [build.rs](../../server/crates/contracts/build.rs).
4. **Fachada gRPC-Web** (`runtime_api`): `exigir_superuser_do_metadata` → delega ao
   `data_postgres`/`control_plane` via `deps.pg.call`/`deps.cp.call` (padrão
   `handler_admin_forward`) → converte JSON↔proto → registra `add_service` no `serve()`.
5. **Dart gerado** no `api_client` (pipeline do `auth.pb.dart`) + expor stub no
   [grpc_api_client.dart](../../clients/packages/api_client/lib/src/grpc_api_client.dart).
6. **Feature Flutter** no `admin_module` (Clean Arch): datasource gRPC → usecase
   (`UsecaseBaseCallData`) → controller (`BaseController`) + page (`ViewStateBuilder`).

> Roteamento (regra): CRUD simples → `data_postgres`; ações complexas (provisionar tenant,
> gerar código de acesso + e-mail, testar conexão Evolution, agregações) → `control_plane`.

---

## 6. Fundação (Fase 0)

- **`admin_module`** novo (`clients/modulos/admin_module/`), pubspec workspace,
  espelhando `login_module`.
- **Shell admin:** substituir o placeholder `/home` em
  [app.dart](../../clients/apps/smart-core-admin/lib/app.dart) por `AppScaffold` com
  navegação lateral (seções do roadmap); `/admin` como destino pós-login em
  [auth_redirect.dart](../../clients/apps/smart-core-admin/lib/auth_redirect.dart).
- **Guarda de segurança:** `exigir_superuser_do_metadata` na fachada gRPC-Web (§3.2).
- **`AdminService` proto** inicial + pipeline Dart validado.
- **Fatia vertical de validação:** **CoreSettings** ponta a ponta (handler já existe),
  provando proto→fachada→dart→tela antes de escalar.

---

## 7. Roadmap de domínios (P1–P4 mapeadas em fases)

> Legenda backend: ✅ handler existe · 🟡 tabela/repo existe, falta handler · 🔴 não existe.

### Fase 1 — Configuração global & IA  *(P2 do mapeamento)*
- **CoreSettings** ✅ — globais: API keys, modelos padrão, prompts de sistema, thresholds,
  embeddings, mensagens. Tela: tabela (key/description/encrypted/updated_at) + CRUD;
  `encrypted=true` exibe `••••••••`.
- **TenantConfig** ✅ (Get/Update prontos, cifragem + masking) — por tenant alvo:
  - **LLM:** `llm_class` (groq/openai/anthropic/local), `model`, `llm_temperature` (slider
    0.0–2.0), `transcription_provider`/`transcription_model`, `vision_provider`/`vision_model`.
  - **Bot/Prompts:** `dados_empresa` (textarea), `persona_bot` (textarea), `bot_agent_name`.
  - **Mensagens automáticas:** `msg_fallback`, `msg_sem_info`, `msg_transferencia`.
  - **Entidades:** `entity_types` (editor JSON).
  - **API Keys:** groq/openai/google — mascaradas `••••••••`; diálogo `obscureText`;
    enviar máscara preserva o valor (comportamento já garantido no handler).
  - **Branding/RAG:** `brand_name`, `primary_color`/`secondary_color` (color picker),
    `timezone`, `language_code`, `embeddings_*`, `chunk_*`, thresholds.

### Fase 2 — Tenants & Billing  *(P1 do mapeamento)*
- **Dashboard de Tenants** 🟡: lista (name, slug, owner, `subscription_status` colorido,
  `days_until_expiration` com cores <7 vermelho / <30 amarelo, created_at). Filtros
  (status, criação, expiração), busca (name/slug/owner). Bulk: estender assinatura
  (30d/6m/12m), ativar/suspender, gerar código de acesso (`[A-Z0-9]{3}-[A-Z0-9]{3}`).
  Backend: `CreateTenant` ✅; faltam `ListTenants`/`GetTenant`/`UpdateTenant`/
  `SetTenantActive` + `TenantRepository::listar`/`atualizar`/`set_active`.
- **Detalhe do Tenant** 🟡: abas Identificação (name/slug/owner/active/email/phone),
  Credenciais (id, api_key mascarada — read-only), Config IA (Fase 1), Assinatura,
  Pagamentos.
- **Planos** 🟡 / **Assinaturas** 🟡 / **Pagamentos** 🟡 (tabelas 0003 existem; faltam
  repos/handlers). Registro manual de pagamento → cria `PaymentRecord` + estende
  `current_period_end`. Proteção: não excluir plano com assinatura ativa.
- **TenantUser / TenantInvite** 🟡 (tabelas 0002): gestão de usuários do tenant + convites
  com RBAC por módulo (token, expiração).

### Fase 3 — Integrações + teste de conexão/health  *(P2/P3 + melhoria)*
- **Evolution** (`evolution_sync_instance`/`_contact`/`_whitelist`) 🟡: server_url,
  api_key (cifrada), instance_name, connection_state, subscribed_events, whitelist.
  Botão **"Testar Conexão"** → `control_plane::TestEvolutionConnection` (decripta, faz
  HTTP, atualiza `connection_state`/`last_state_check`). **Requer cliente HTTP Evolution
  em Rust (🔴 a criar).**
- **Trello/Notion/ClickUp** 🔴 (eram o `UnifiedDataService` do old; nada no Rust ainda) —
  fase posterior.
- **Painel de saúde:** status dos serviços/instâncias + validação de keys LLM.

### Fase 4 — Feature flags dinâmicas + versionamento de config  *(melhorias)*
- **Feature flags** 🔴: migration nova `00NN_feature_flags.sql` (flag global + override
  por tenant) + CRUD + resolução em runtime. Substitui flags de `settings.py` do old
  (`ATENDIMENTO_UNIFICADO_ENABLED`, etc.).
- **Versionamento de config:** o `audit_log` ✅ já registra mutações
  (`core_setting_upserted`, `tenant_config_updated`, …). Construir **viewer de histórico**
  (quem/quando/o quê). **Rollback** = etapa avançada (tabela de snapshots de config).

### Fase 5 — Auditoria & Dashboards  *(P4 + melhoria)*
- **Audit viewer** 🟡 (tabela `audit_log` existe; falta handler de query com filtros:
  nível, serviço, evento, trace_id, período, tenant, user).
- **Dashboard principal** 🔴: cards (tenants ativos/suspensos/em atraso, receita mensal,
  expirando em 7 dias) + gráficos (tenants/mês, receita/mês, atendimentos/dia). Agregação
  no backend (`control_plane::GetDashboardSummary`).
- **Exportações CSV** (stream gRPC): tenants, pagamentos (por intervalo), clientes.
- **LLM cost tracking** 🔴: depende do `ia_engine`; modelar tabela de uso por
  tenant/modelo (tokens) → insumo de billing por uso.

### Fase 6 — Operacional por tenant (superadmin no contexto de um tenant)  *(P3, por último)*
- Atendentes (visão global; bulk disponível/indisponível), Departamentos (CRUD + fluxos
  inline), AppInstances (instâncias WhatsApp), campos dinâmicos, etiquetas, treinamento/RAG.
  Tabelas/repos 🟡 existem; faltam handlers. São mais operacionais → entram por último.

---

## 8. Modelo de dados — tabelas envolvidas

Todas já existem (0001–0011). **Nenhuma migration nova para P1–P3**, exceto **feature
flags** (Fase 4) e, futuramente, **snapshots de config** (rollback) e **uso de LLM** (cost).

> Nomes reais preservam o prefixo do Django legado (`tenants_*`, `oraculo_*`,
> `evolution_sync_*`, `settings_manager_*`). Use os nomes exatos.

| Tabela (nome real) | Entidade | Migration |
|---|---|---|
| `tenants_tenant` | Tenant | 0002 |
| `tenants_tenantconfig` | TenantConfig (IA, keys, branding) | 0002 |
| `tenants_tenantuser` | TenantUser (RBAC) | 0002 |
| `tenants_tenantinvite` | TenantInvite | 0002 |
| `tenants_plan` | Plan | 0003 |
| `tenants_subscription` | Subscription | 0003 |
| `tenants_paymentrecord` | PaymentRecord | 0003 |
| `oraculo_app_instance` | AppInstance | 0005 |
| `evolution_sync_instance` | EvolutionInstance | 0008 |
| `settings_manager_coresettings` | CoreSettings (global) | 0009 |
| `audit_log` | AuditLog | 0010 |
| `auth_user` | AuthUser (global) | 0001 |
| *(nova)* `feature_flags` | FeatureFlag (global + por tenant) | Fase 4 |

> Credenciais cifradas via `CipherManager` (AES-256-GCM) em `infrastructure_postgres::crypto`.

---

## 9. Arquitetura de implementação

```
[Flutter Admin Web/WASM]
    │  gRPC-Web (HTTP/1.1, metadata: authorization: Bearer <JWT superuser>)
    ▼
[runtime_api] ── fachada gRPC-Web ── exigir_superuser_do_metadata (JWT + blocklist + is_superuser)
    │  RPC (UDS/TCP)                         │  RPC (UDS/TCP)
    ▼                                        ▼
[data_postgres]                          [control_plane]
 (CRUD direto sob RLS)                    (lógica de negócio: provisionar tenant,
                                          gerar código de acesso + e-mail,
                                          testar conexão Evolution, agregações dashboard)
```

**Roteamento no `runtime_api`:** todo `AdminService` exige `is_superuser=true`; CRUD →
`data_postgres`; ações complexas → `control_plane`. Superusuário tem `tenant_id=Uuid::nil()`;
o **tenant alvo** das operações por-tenant vai no payload (`resolver_tenant_alvo`).

---

## 10. Contratos gRPC — `AdminService` (tipado)

Novo `contracts/schemas/queries/admin.proto`, exposto na fachada gRPC-Web.

### Tenants
```protobuf
rpc ListTenants(ListTenantsRequest) returns (ListTenantsResponse);
rpc GetTenant(GetTenantRequest) returns (TenantDetail);
rpc CreateTenant(CreateTenantRequest) returns (TenantDetail);
rpc UpdateTenant(UpdateTenantRequest) returns (TenantDetail);
rpc SetTenantActive(SetTenantActiveRequest) returns (Empty);
rpc BulkExtendSubscription(BulkExtendRequest) returns (BulkResult);
rpc BulkSetTenantActive(BulkSetActiveRequest) returns (BulkResult);
rpc GenerateAccessCode(GenerateAccessCodeRequest) returns (AccessCodeResult);
```

### Planos, assinaturas e pagamentos
```protobuf
rpc ListPlans(Empty) returns (ListPlansResponse);
rpc CreatePlan(CreatePlanRequest) returns (Plan);
rpc UpdatePlan(UpdatePlanRequest) returns (Plan);
rpc SetPlanActive(SetPlanActiveRequest) returns (Empty);
rpc ListSubscriptions(ListSubscriptionsRequest) returns (ListSubscriptionsResponse);
rpc RegisterPayment(RegisterPaymentRequest) returns (PaymentRecord);
rpc ListPayments(ListPaymentsRequest) returns (ListPaymentsResponse);
```

### Configuração global e por tenant
```protobuf
rpc ListCoreSettings(Empty) returns (ListCoreSettingsResponse);
rpc UpsertCoreSetting(UpsertCoreSettingRequest) returns (CoreSetting);
rpc DeleteCoreSetting(DeleteCoreSettingRequest) returns (Empty);
rpc GetTenantConfig(GetTenantRequest) returns (TenantConfig);
rpc UpdateTenantConfig(UpdateTenantConfigRequest) returns (TenantConfig);
rpc TestEvolutionConnection(TestConnectionRequest) returns (ConnectionResult);
rpc TestLlmKey(TestLlmKeyRequest) returns (ConnectionResult);
```

### Usuários do tenant
```protobuf
rpc ListTenantUsers(ListTenantUsersRequest) returns (ListTenantUsersResponse);
rpc InviteTenantUser(InviteTenantUserRequest) returns (TenantInvite);
rpc UpdateTenantUser(UpdateTenantUserRequest) returns (TenantUser);
rpc RevokeTenantUser(RevokeTenantUserRequest) returns (Empty);
```

### Feature flags (melhoria)
```protobuf
rpc ListFeatureFlags(ListFeatureFlagsRequest) returns (ListFeatureFlagsResponse);
rpc SetFeatureFlag(SetFeatureFlagRequest) returns (FeatureFlag); // global ou por tenant
```

### Auditoria, dashboard e exportação (melhoria + P4)
```protobuf
rpc QueryAuditLog(QueryAuditLogRequest) returns (QueryAuditLogResponse);
rpc GetConfigHistory(GetConfigHistoryRequest) returns (ConfigHistoryResponse);
rpc GetServiceHealth(Empty) returns (ServiceHealthResponse);
rpc GetDashboardSummary(Empty) returns (DashboardSummary);
rpc ExportTenantsCsv(ExportRequest) returns (stream CsvChunk);
rpc ExportPaymentsCsv(ExportPaymentsRequest) returns (stream CsvChunk);
```

---

## 11. Campos encriptados — política de segurança

Nunca trafegam em claro pelo gRPC nem são exibidos literalmente:

| Campo | Tabela | Tratamento |
|---|---|---|
| `api_keys` (JSON: groq/openai/google) | `tenants_tenantconfig` | mascarado por chave (`••••••••`) |
| `value` (quando `encrypted`) | `settings_manager_coresettings` | mascarado na leitura |
| `api_key` da instância | `evolution_sync_instance` | mascarado; edição substitui |

**Fluxo (já implementado para TenantConfig; replicar):**
1. UI envia novo valor via gRPC (TLS) → `runtime_api` → `data_postgres`/`control_plane`.
2. `CipherManager::encrypt(value)` antes de persistir (formato `ciphertext:nonce:tag`).
3. Na leitura, devolve `"••••••••"` — nunca decripta para o admin.
4. Enviar a máscara `••••••••` no update **preserva** o valor existente (não sobrescreve).
5. Para testar conexão, o `control_plane` decripta internamente e testa sem expor o valor.

---

## 12. Auditoria e observabilidade do painel

> **Princípio inviolável (herdado do [05-observabilidade.md](./05-observabilidade.md)):**
> **toda ação do painel registra o que foi feito e por quem.** Nenhuma mutação ocorre sem
> um evento de auditoria correlacionado por `actor` (superuser), `tenant_id` alvo e
> `trace_id`. Nada de erro silencioso: todo erro é logado com `error_code`/`severity`
> (via `error_core`) e rastreável fim a fim.

### 12.1 Infra existente reutilizada (NÃO reimplementar)
- **Crate `observability`:** `init_telemetry`, `AuditLogger`/`AuditLogPayload`, propagação
  W3C `traceparent` no `Envelope`, métricas OTel, `monitorar_pool`.
- **Pipeline de auditoria assíncrono (já em uso):** handler → `AuditLogger`/
  `publicar_auditoria` publica no **bus Redis Streams** (`transport::bus`,
  `STREAM_SEGURANCA`) → **consumidor no `data_postgres`** consolida em `audit_log` (em
  lote, com PEL/reprocessamento). **Auditoria nunca é gravada de forma síncrona** (não
  bloqueia o handler).
- **Tabela `audit_log` (0010)** com RLS + índices para os filtros do painel: por tenant,
  por evento, por user, por nível (`WARN`/`ERROR`), global (tenant_id NULL), GIN no
  `context`. **Leitura já implementada:** `buscar_audit_logs_admin(event_filter, limit,
  offset)`, `buscar_audit_logs_globais(...)`, `buscar_audit_logs(tenant, ...)` em
  `infrastructure_postgres::auditoria`.
- **Stack LGTM (docker/observability):** Grafana/Prometheus/Loki/Tempo/OTel Collector já
  provisionados, incluindo dashboard `audit_log.json`. Logs técnicos e traces vivem aqui;
  o painel **integra (deep-link)**, não duplica.

### 12.2 Pontos de registro — toda ação do `AdminService` emite evento

Cada handler admin (mutação **e** acessos sensíveis) publica um evento. Convenção de
nome: `snake_case` `dominio_acao`; `level` INFO (sucesso), WARN (negado/risco), ERROR
(falha técnica). O **`context` (JSONB)** carrega `actor_user_id`, `tenant_alvo` (quando
aplica), `target_id`, e **diff `before`/`after`** nas edições (para versionamento §13).

| Ação (RPC) | Evento | Level | `context` (além de actor/trace) |
|---|---|---|---|
| Login/Refresh/Logout | `login_success` / `login_rate_limited` / `logout` | INFO/WARN | já implementado na borda |
| Acesso admin negado (não-superuser) | `auth_access_denied` | WARN | `method` (já implementado) |
| CreateTenant / UpdateTenant | `tenant_created` / `tenant_updated` | INFO | `tenant_id`, `before`/`after` |
| SetTenantActive / Bulk | `tenant_activated` / `tenant_suspended` | INFO | lista de `tenant_ids` |
| GenerateAccessCode | `access_code_generated` | INFO | `tenant_id` (NUNCA o código) |
| UpsertCoreSetting / Delete | `core_setting_upserted` / `core_setting_deleted` | INFO | `key`, `encrypted`; valor cifrado **nunca** no context |
| UpdateTenantConfig | `tenant_config_updated` | INFO | `tenant_id`, diff dos campos; **API keys mascaradas** |
| API key alterada | `tenant_api_key_changed` | WARN | `tenant_id`, `provider` (sem valor) |
| Plan/Subscription/Payment | `plan_created`/`subscription_updated`/`payment_registered` | INFO | `tenant_id`, `amount`, `period` |
| InviteTenantUser / Revoke | `tenant_user_invited` / `tenant_user_revoked` | INFO | `tenant_id`, `email`, `role` |
| SetFeatureFlag | `feature_flag_set` | INFO | `flag`, `scope` (global/tenant), `before`/`after` |
| TestEvolutionConnection / TestLlmKey | `connection_tested` | INFO/WARN | `target`, `result` (ok/falha), **sem credencial** |
| Export*Csv | `data_exported` | WARN | `tipo`, `intervalo`, `linhas` |
| Impersonation (se adotado) | `impersonation_started`/`_ended` | WARN | `tenant_id` |

**Regra de ouro (cruza com [05 §6](./05-observabilidade.md) e segurança §11):** o `context`
**nunca** contém segredo, valor de chave, senha, token nem PII bruta. Em campos cifrados,
registra-se apenas o fato da mudança (`provider`/`key`), nunca o conteúdo.

### 12.3 Exposição no painel (logs e erros)

1. **Audit viewer** (`QueryAuditLog`): tabela cross-tenant para o superusuário (pool
   admin), com filtros **nível, serviço, evento, período, `tenant`, `user`, `trace_id`** e
   busca no `context` (GIN). Reaproveita `buscar_audit_logs_admin`/`_globais`, **expandindo
   a query** para os filtros acima. Cada linha: timestamp, level (badge), service, event,
   message, actor (`user_id`), `tenant`, e **ação "ver trace"**.
2. **Histórico de configuração** (`GetConfigHistory`): derivado dos eventos `*_updated`/
   `*_upserted` com diff `before`/`after` — alimenta o versionamento de config (§13) e o
   rollback futuro.
3. **Painel de erros**: recorte do audit viewer por `level IN (WARN, ERROR)` (índice
   dedicado já existe), agrupável por `error_code`/`event`/`service`. Distinção explícita:
   - **Erros de negócio/segurança auditados** → persistidos em `audit_log` (histórico
     longo, fonte do painel).
   - **Erros técnicos / traces / logs de stack** → vivem em **Loki/Tempo** (retenção
     curta 7–14d). O painel oferece **deep-link ao Grafana/Tempo por `trace_id`** (não
     reimplementa busca de traces). Atenção: `trace_id` pode expirar no Tempo antes do
     registro de auditoria — por isso o `audit_log` é a fonte durável.
4. **Saúde dos serviços** (`GetServiceHealth`): consome `/health` e `/metrics` de cada
   binário (doc 05 §5) — status up/down, taxa de erro por `error_code`, lag do bus,
   backlog de outbox, métricas de pool (já emitidas como `smartcore_bus_pending`,
   `smartcore_outbox_backlog`, pool metrics). Complementa a melhoria de health/teste de
   conexão (§13).

### 12.4 Fluxo técnico de um registro
```
[handler admin no data_postgres/control_plane]
   └─ publicar_auditoria(bus, event, level, context{actor, tenant_alvo, diff})
        └─ STREAM_SEGURANCA (Redis)  ── assíncrono, best-effort, não bloqueia ──┐
                                                                                ▼
                                       [consumidor data_postgres] → INSERT audit_log (lote + PEL)
                                                                                │
[painel] ── QueryAuditLog/GetConfigHistory/GetServiceHealth (superuser) ────────┘
```

### 12.5 Retenção e segurança
- `audit_log` é **persistente** (negócio/segurança); logs/traces no LGTM têm **retenção
  curta**. Histórico longo do painel depende de `audit_log`.
- Leitura cross-tenant **só** para superusuário (pool admin); tenant comum vê só o seu (RLS).
- Sanitização obrigatória do `context` (sem segredos/PII) antes de publicar no bus.

---

## 13. Melhorias de mercado incorporadas

1. **Teste de conexão / health (Fase 3/5):** botão por integração (Evolution/Trello/LLM)
   + painel de saúde de serviços/instâncias. `TestEvolutionConnection`/`TestLlmKey`.
   *Dependência:* cliente HTTP Evolution em Rust (a criar).
2. **Versionamento de config (Fase 4):** histórico de quem/quando/o quê sobre `audit_log`
   (`GetConfigHistory`); rollback como etapa avançada com tabela de snapshots.
3. **Feature flags dinâmicas (Fase 4):** tabela `feature_flags` (global + por tenant),
   resolução em runtime; substitui flags hardcoded.
4. **Dashboards & cost tracking (Fase 5):** `GetDashboardSummary` (KPIs/gráficos) + tabela
   de uso de tokens por tenant/modelo (depende do `ia_engine`) para billing por uso.

---

## 14. Análise crítica — falhas de lógica e oportunidades

**Falhas/riscos (corrigir no caminho):**
1. **[Crítico] Fachada gRPC-Web sem guarda de superuser** (§3.2) — tratar na Fase 0
   antes de expor qualquer endpoint admin.
2. **Drift contrato proto ↔ JSON:** o `data_postgres` fala JSON ad hoc; a borda é tipada.
   A tradução manual é ponto de divergência — mitigar com testes de mapeamento (espelhar
   `login_module`).
3. **Concorrência entre superadmins:** last-write-wins silencioso em edição simultânea →
   adotar optimistic locking (`updated_at`/versão) em config/tenant.
4. **Auditoria obrigatória:** toda mutação deve gerar `audit_log` com `actor=superuser_id`
   (padrão `publicar_auditoria` já existe — aplicar em todos os novos handlers).
5. **Não portar conceitos obsoletos** (§3.4): `TenantDatabase` DB-per-tenant; flags de
   `settings.py`.

**Oportunidades:**
- **Impersonation / "ver como tenant"** para suporte (auditado).
- **Paginação/filtros uniformes** em todas as listas (contrato comum).
- **Resolução consistente de tenant alvo** (`resolver_tenant_alvo`) em todos os endpoints.
- **Observability nativa no painel** (o backend já emite tracing/auditoria).

---

## 15. Etapas de implementação

### Etapa 0 — Fundação (§6)
Branch `feature/admin-foundation`. `admin_module` + shell + `exigir_superuser_do_metadata`
+ `admin.proto` inicial + pipeline Dart + fatia CoreSettings ponta a ponta.

### Etapa A — Backend por fase (molde §5)
Branch `feature/admin-backend-<fase>`.
- **A.1 Repos faltantes:** `TenantRepository::listar`/`atualizar`/`set_active`;
  `PlanRepository`, `SubscriptionRepository`, `PaymentRecordRepository`; (Fase 4)
  `feature_flags`.
- **A.2 Handlers `data_postgres`:** CRUD + auditoria em cada mutação.
- **A.3 `control_plane`:** `BulkExtendSubscription`, `GenerateAccessCode` (código 6-char,
  Redis TTL 24h, e-mail SMTP), `TestEvolutionConnection`, `TestLlmKey`,
  `GetDashboardSummary`.
- **A.4 `admin.proto`** + `build.rs`.
- **A.5 Fachada gRPC-Web** (`AdminServiceServer`) com guard de superuser; streaming p/ CSV.
- **DoD A:** `grpcurl` chama todos os RPCs com JWT de superusuário; sem JWT ou com JWT
  comum → `PERMISSION_DENIED`/`AUTH_INSUFFICIENT_SCOPE` **na fachada gRPC-Web**.

### Etapa B — Frontend por fase (molde §5)
Branch `feature/admin-flutter-<fase>`.
- **B.0** `api_client`: stubs gerados + expostos no `GrpcApiClient`.
- **B.1** Shell + navegação + `SuperuserGuard` (valida `is_superuser` no JWT; senão encerra).
- **B.2→B.n** Telas por fase (Config/IA → Tenants/Billing → Integrações → Flags/Histórico
  → Auditoria/Dashboard → Operacional), cada uma `BaseController` + `ViewStateBuilder` +
  widgets do design system; campos cifrados mascarados.
- **DoD B:** telas da fase operacionais contra `runtime_api` real; `flutter analyze` limpo;
  cifrados nunca exibem valor real; `SuperuserGuard` bloqueia usuários comuns.

---

## 16. Critérios de aceite globais (DoD)

- [ ] Login do superusuário via JWT; refresh automático.
- [ ] Guarda `is_superuser` **na fachada gRPC-Web** (não só no IPC interno).
- [ ] CRUD completo de tenants (criar, editar, ativar/suspender, histórico).
- [ ] Config global (CoreSettings) e por tenant (TenantConfig) editáveis ponta a ponta.
- [ ] CRUD de planos com proteção; pagamento manual estende `current_period_end`.
- [ ] Bulk actions para múltiplos tenants.
- [ ] Campos cifrados nunca exibem valor real; máscara preserva o valor no update.
- [ ] Feature flags dinâmicas (global + por tenant) resolvidas em runtime.
- [ ] **Toda ação do painel gera evento de auditoria** (`actor=superuser_id`, `tenant_alvo`,
  `trace_id`, diff `before`/`after`), sem segredo/PII no `context` (§12).
- [ ] Audit viewer (filtros nível/serviço/evento/período/tenant/user/trace_id), histórico
  de config e painel de erros (WARN/ERROR) com deep-link de `trace_id` ao Grafana/Tempo.
- [ ] `GetServiceHealth` reporta status/erros/lag por serviço.
- [ ] Dashboard com KPIs; teste de conexão das integrações.
- [ ] `flutter analyze` limpo; `cargo clippy -- -D warnings` limpo.
- [ ] Testes: mapeamento proto↔JSON (Rust) + datasource/usecase/controller (Flutter).

---

## 17. Checklist transversal por PR

- [ ] JWT de superusuário validado na fachada gRPC-Web antes de qualquer handler.
- [ ] Campos cifrados via `CipherManager`; nunca logados.
- [ ] Mutações **e acessos sensíveis** geram evento de auditoria (`audit_log`) com
  `actor=superuser_id`, publicado **assíncrono no bus** (nunca síncrono).
- [ ] `context` de auditoria sanitizado: sem segredo, valor de chave, token ou PII bruta.
- [ ] `tenant_id` no Envelope mesmo em operações globais (`Uuid::nil()`); tenant alvo no payload.
- [ ] Paginação consistente em todas as listas.
- [ ] CSV escapa vírgulas/aspas.
- [ ] Comentários em pt-br; identificadores em inglês.

---

*Documento criado em 2026-06-07. Consolidado com o código real em 2026-06-18
(correções factuais §3, molde repetível §5, auditoria & observabilidade §12, melhorias §13,
análise crítica §14). Retroalimentar conforme a implementação avança.*
