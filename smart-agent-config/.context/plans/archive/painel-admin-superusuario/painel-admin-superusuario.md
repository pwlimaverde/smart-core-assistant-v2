---
status: completed
generated: 2026-06-19
agents:
  - type: "backend-specialist"
    role: "Implementar AdminService gRPC-Web, handlers RPC, repos Rust e guarda is_superuser"
  - type: "frontend-specialist"
    role: "Implementar admin_module Flutter com Clean Arch, stubs Dart e telas por fase"
  - type: "security-auditor"
    role: "Revisar guarda exigir_superuser_do_metadata, política de cifragem e sanitização de auditoria"
  - type: "architect-specialist"
    role: "Validar integração gRPC-Web, molde repetível e fronteiras de serviço"
  - type: "test-writer"
    role: "Escrever testes de mapeamento proto↔JSON (Rust) e datasource/usecase/controller (Flutter)"
  - type: "code-reviewer"
    role: "Revisar PRs garantindo checklist transversal (guarda, cifragem, auditoria, paginação)"
docs:
  - "architecture.md"
  - "security.md"
  - "data-flow.md"
  - "testing-strategy.md"
phases:
  - id: "phase-p"
    name: "Planning — Planejamento e reestruturação"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — Validação de arquitetura e abordagem"
    prevc: "R"
    agent: "security-auditor"
    status: "completed"
  - id: "phase-e"
    name: "Execution — Implementação das Fases 0→6"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — Testes e verificação ponta a ponta"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — Entrega, documentação e arquivamento"
    prevc: "C"
    agent: "code-reviewer"
    status: "completed"
---

# Painel Gerencial do Superusuário (Admin Total)

> Construir o painel de controle total para o superusuário: `AdminService` gRPC-Web tipado
> (proto) exposto na fachada `runtime_api`, cobrindo config global/por-tenant, tenants/billing,
> integrações (Evolution), feature flags, auditoria e dashboards — com guarda `is_superuser`
> e observabilidade em toda mutação.

## Artefatos detalhados

- **Plano completo:** [painel-admin-superusuario/plano_completo_painel-admin-superusuario.md](./painel-admin-superusuario/plano_completo_painel-admin-superusuario.md)
- **Documentação auxiliar (libs + serviços):** [painel-admin-superusuario/info_aux_painel-admin-superusuario.md](./painel-admin-superusuario/info_aux_painel-admin-superusuario.md)
- **Origem do plano:** `doc_dev/planejamento/11-painel-admin-superusuario.md` (permanece como histórico)

## Resumo do escopo

O `smart-core-admin` (Flutter Web/WASM) é o painel **superadmin/configuração**. O Flutter
fala exclusivamente com a fachada gRPC-Web do `runtime_api`, que valida JWT (`is_superuser`)
e repassa ao `data_postgres` (CRUD) e ao `control_plane` (lógica de negócio).

**Gargalo crítico:** a fachada gRPC-Web hoje só expõe `AuthService`. Todo endpoint admin
precisa ser exposto, precedido pela implementação de `exigir_superuser_do_metadata`.

## Roadmap de fases de implementação

| Fase | Escopo | Status backend | Status Flutter |
|------|--------|---------------|----------------|
| **Fundação (F0)** | admin_module, shell, guarda is_superuser, admin.proto, CoreSettings ponta a ponta | 🔴 | 🔴 |
| **Fase 1 — Config global & IA** | CoreSettings + TenantConfig (handlers ✅, fachada + tela faltam) | 🟡 | 🔴 |
| **Fase 2 — Tenants & Billing** | ListTenants/GetTenant/Update, planos, assinaturas, pagamentos, TenantUser/Invite | 🔴 | 🔴 |
| **Fase 3 — Integrações** | Evolution (TestEvolutionConnection + cliente HTTP Rust), painel de saúde | 🔴 | 🔴 |
| **Fase 4 — Feature flags + histórico** | Migration feature_flags, CRUD, viewer de histórico | 🔴 | 🔴 |
| **Fase 5 — Auditoria & Dashboards** | QueryAuditLog, GetDashboardSummary, ExportCsv (streaming) | 🔴 | 🔴 |
| **Fase 6 — Operacional por tenant** | Atendentes, Departamentos, AppInstances, RAG | 🟡 | 🔴 |

## Pré-requisitos técnicos críticos

1. **`exigir_superuser_do_metadata`** (Fase 0, antes de tudo): JWT + blocklist Redis + `is_superuser`
2. **`protoc_plugin` ≥ 16.0.0** (breaking change gRPC Dart 5.x): necessário para gerar stubs Dart do `AdminService`
3. **`AdminService` proto** em `contracts/schemas/queries/admin.proto` + pipeline Dart

## Decisões arquiteturais registradas

- **CRUD simples** → `data_postgres` via `deps.pg.call`
- **Ações complexas** (provisionar tenant, gerar código, testar Evolution, agregações) → `control_plane`
- **Superusuário** tem `tenant_id = Uuid::nil()`; **tenant alvo** vai no payload (`resolver_tenant_alvo`)
- **Auditoria** assíncrona via bus Redis (`STREAM_SEGURANCA`) → consumidor `data_postgres` → `audit_log`
- **Exportação CSV** via server-streaming gRPC (único streaming suportado no browser gRPC-Web)
- **tonic-web 0.14.1 + prost 0.14.3**: sem breaking changes vs versões anteriores

## Phase P — Planning (concluída)

**Entregáveis:**
- [x] Plano base reconciliado com código real (`doc_dev/planejamento/11-painel-admin-superusuario.md`)
- [x] Triagem de libs: tonic-web e prost atualizados na central; grpc Dart 5.x documentado
- [x] Evolution API documentada (endpoints, auth, TestEvolutionConnection)
- [x] `info_aux` consolidado com todos os grupos A/B/C
- [x] Plano completo reestruturado pelo subagente `opus`

## Phase R — Review (em andamento)

**Objetivo:** Validar a arquitetura, a guarda de segurança e o molde repetível antes de implementar.

| # | Tarefa | Agente | Status | Entregável |
|---|--------|--------|--------|------------|
| R.1 | Revisar `exigir_superuser_do_metadata` (alinhamento com `exigir_auth` existente) | `security-auditor` | pending | Aprovação ou correções de segurança |
| R.2 | Validar contratos `admin.proto` (RPCs, campos, streaming CSV) | `architect-specialist` | pending | proto revisado ou aprovado |
| R.3 | Revisar molde repetível (passos 1→6) contra padrões existentes do projeto | `code-reviewer` | pending | Checklist aprovado |

## Phase E — Execution (pendente)

**Objetivo:** Implementar as fases 0→6 aplicando o molde repetível.

| # | Sub-etapa | Agente | Status |
|---|-----------|--------|--------|
| E.0 | Fundação: admin_module + shell + guarda + proto + CoreSettings ponta a ponta | `backend-specialist` + `frontend-specialist` | pending |
| E.1 | Fase 1: Config global & IA (fachada gRPC-Web + telas) | `backend-specialist` + `frontend-specialist` | pending |
| E.2 | Fase 2: Tenants & Billing (repos + handlers + telas) | `backend-specialist` + `frontend-specialist` | pending |
| E.3 | Fase 3: Integrações (cliente HTTP Evolution + TestEvolutionConnection + telas) | `backend-specialist` + `frontend-specialist` | pending |
| E.4 | Fase 4: Feature flags + histórico de config | `backend-specialist` + `frontend-specialist` | pending |
| E.5 | Fase 5: Auditoria & Dashboards + exportação CSV streaming | `backend-specialist` + `frontend-specialist` | pending |
| E.6 | Fase 6: Operacional por tenant | `backend-specialist` + `frontend-specialist` | pending |

## Phase V — Validation (pendente)

**Objetivo:** Verificar que o painel funciona ponta a ponta contra `runtime_api` real.

| # | Tarefa | Agente | Status |
|---|--------|--------|--------|
| V.1 | Testes Rust: mapeamento proto↔JSON em todos os handlers admin | `test-writer` | pending |
| V.2 | Testes Flutter: datasource/usecase/controller por fase | `test-writer` | pending |
| V.3 | Verificar que campos cifrados nunca exibem valor real na UI | `security-auditor` | pending |
| V.4 | Verificar `SuperuserGuard` bloqueia usuário comum no Flutter | `security-auditor` | pending |
| V.5 | `cargo clippy -- -D warnings` limpo | `code-reviewer` | pending |
| V.6 | `flutter analyze` limpo | `code-reviewer` | pending |
| V.7 | Verificar eventos de auditoria gerados por todas as mutações | `security-auditor` | pending |

## Phase C — Confirmation (pendente)

**Objetivo:** Entregar, documentar e arquivar o plano.

| # | Tarefa | Agente | Status |
|---|--------|--------|--------|
| C.1 | Atualizar `doc_dev/planejamento/11-painel-admin-superusuario.md` com status final | `documentation-writer` | pending |
| C.2 | Final-review (auditoria pós-implementação) | `code-reviewer` | pending |
| C.3 | Arquivar plano (mover para `.context/plans/archive/painel-admin-superusuario/`) | `architect-specialist` | pending |

## Critérios de aceite globais (DoD)

- [ ] Login JWT do superusuário; refresh automático
- [ ] `exigir_superuser_do_metadata` na fachada gRPC-Web (não apenas no IPC interno)
- [ ] CRUD completo de tenants (criar, editar, ativar/suspender)
- [ ] Config global (CoreSettings) e por tenant (TenantConfig) editáveis ponta a ponta
- [ ] Campos cifrados nunca exibem valor real; máscara `••••••••` preserva valor no update
- [ ] CRUD de planos/assinaturas; pagamento manual estende `current_period_end`
- [ ] Feature flags dinâmicas (global + por tenant) resolvidas em runtime
- [ ] `TestEvolutionConnection` funcional (sem vazar credencial)
- [ ] Toda mutação gera evento de auditoria (`actor=superuser_id`, `tenant_alvo`, `trace_id`, diff `before/after`, sem segredo/PII)
- [ ] Audit viewer com filtros; deep-link `trace_id` ao Grafana/Tempo
- [ ] Dashboard KPIs; `GetServiceHealth` funcional
- [ ] `cargo clippy -- -D warnings` limpo; `flutter analyze` limpo
- [ ] Testes: mapeamento proto↔JSON (Rust) + datasource/usecase/controller (Flutter)
