---
type: plan
name: "MVP: Telas & Endurecimento"
planSlug: mvp-telas-e-endurecimento
description: "Backlog restante da finalização do MVP: telas Flutter operacionais (fila/Kanban/chat realtime) e admin (endurecimento) + endurecimento de backend (RBAC fino por fluxo, user_agent na auditoria, invalidação do TenantConfigCache, e2e de trace)."
summary: "Fechar o MVP operacional com as telas Flutter e o endurecimento de backend, herdando o DoD transversal de observabilidade/auditoria + SOLID/Ports & Adapters do ciclo anterior."
status: completed
generated: 2026-06-30
closed: 2026-07-05
closure_note: "Ciclo fechado completo via prevc-final-review. Entregues WS-5a (RBAC fino por fluxo, incl. correção do gap na borda gRPC-Web encontrado no gate final), WS-5b (user_agent na auditoria), WS-7.2 (invalidação do TenantConfigCache), WS-0.3 (e2e de cadeia de trace, aceite do dono), WS-6 (telas operacionais Flutter novas: fila/Kanban/chat) e WS-7 telas (endurecimento do admin_module). WS-7.3 (telas de convite) parqueado por decisão do dono — é fluxo de admin de tenant, não do painel de superusuário; ver memória convites-tenant-nao-e-painel-superuser. Falha de ambiente pré-existente e documentada (role smartcore_app é bootstrap superuser no Postgres remoto de dev) não bloqueou o fechamento. Ver .context/workflow/docs/final-review.md."
agents:
  - type: "frontend-specialist"
    role: "Telas operacionais (WS-6) e admin (WS-7) no smart-core-admin (Flutter): fila, Kanban DnD nativo, chat streaming gRPC-Web"
  - type: "backend-specialist"
    role: "Endurecimento Rust: RBAC fino por fluxo (WS-5a), user_agent na auditoria (WS-5b), invalidação do TenantConfigCache (WS-7.2)"
  - type: "architect-specialist"
    role: "Validar evolução aditiva do contrato Envelope e o design Ports & Adapters dos novos ports"
  - type: "security-auditor"
    role: "Revisar flow_permissions/RBAC, sanitização e os eventos de auditoria (doc 08 §4.2) com user_agent"
  - type: "test-writer"
    role: "Validação via .\\infra\\test-local.ps1 e .\\infra\\test-flutter.ps1; e2e de cadeia de trace (WS-0.3, mediante aceite)"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "frontend-specialist"
    status: "completed"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "backend-specialist"
    status: "completed"
---

# MVP: Telas & Endurecimento — Frontend operacional/admin + RBAC fino, user_agent, cache invalidation

> Continuação do ciclo `finalizacao-mvp-operacional` (fechado como MVP parcial WS-0..WS-4 e
> mergeado na dev). Cobre o backlog restante: as **telas Flutter** (bloco principal) + o
> **endurecimento de backend**. **DoD transversal inegociável (herdado):** observabilidade
> (logs/traces + auditoria `audit_log`, sem segredos/PII) e **SOLID/Ports & Adapters**.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_mvp-telas-e-endurecimento.md](./mvp-telas-e-endurecimento/plano_completo_mvp-telas-e-endurecimento.md)
- **Documentação auxiliar** (libs validadas na central local + notas de API): [info_aux_mvp-telas-e-endurecimento.md](./mvp-telas-e-endurecimento/info_aux_mvp-telas-e-endurecimento.md)
- **Origem:** conversa (continuação) · **Base arquivada:** `.context/plans/archive/finalizacao-mvp-operacional/`

## Escopo (workstreams)
| WS | Foco | Tipo | Estado base |
|---|---|---|---|
| **WS-5a** | RBAC fino por fluxo: `flow_permissions` no contrato `Envelope` + carga no `exigir_auth` + filtro Kanban no `data_postgres` | backend | `RequestContext.has_flow_permission` já existe; falta popular |
| **WS-5b** | `user_agent` no `AuditLogPayload` via `AuditContext` (retrocompatível) + migration + consumer | backend | payload sem `user_agent` |
| **WS-7.2** | Subscriber de invalidação do `TenantConfigCache` (Redis Pub/Sub `core:settings:invalidate`) | backend | cache plugado, sem invalidação |
| **WS-6** | Telas operacionais Flutter: fila por depto + Kanban DnD nativo + chat streaming + outbound | frontend | **construção nova** (`core_module` sem telas) |
| **WS-7 telas** | Telas admin Flutter (tenants/planos/convites/flags/dashboard) consumindo as 18 rotas já expostas | frontend | **já existem** → endurecimento + lacunas |
| **WS-0.3** | Teste e2e de cadeia de trace (webhook→bus→worker→data_postgres→audit_log) | qualidade | **alinhar diretriz de testes com o dono** |

> **Já concluído (base, não replanejar):** WS-0.1 (stack LGTM), WS-0.4 (pool-metrics), WS-1..WS-4,
> WS-2.4, WS-5 forward routes, WS-7 admin routes, RBAC por escopo ponta-a-ponta.

## Sequenciamento
**WS-5a precede** o filtro de fluxo do Kanban (WS-6.2); o resto de WS-6 (fila, chat, outbound)
e o endurecimento (WS-5b, WS-7.2, WS-0.3) e WS-7 telas correm **em paralelo**. Caminho crítico:
**WS-6** (telas operacionais novas). Detalhe técnico, grafo de dependências, cronograma, riscos,
glossário de auditoria e "Correções aplicadas" no [plano completo](./mvp-telas-e-endurecimento/plano_completo_mvp-telas-e-endurecimento.md).

## Fases (PREVC)
- **P — Planning (concluída):** reestruturação aterrada no código real; libs validadas na central local; decisões registradas (RPC+cache para `flow_permissions`, `AuditContext`, DnD nativo).
- **R — Review:** validar com `architect-specialist` a evolução aditiva do `Envelope` (campo 14) e os ports novos (`FlowPermissionsProvider`, `ConfigInvalidation*`, `AtendimentoDataSource`).
- **E — Execution:** WS-5a → (WS-6 ‖ WS-5b ‖ WS-7.2 ‖ WS-7 telas); WS-0.3 mediante aceite.
- **V — Validation:** `.\infra\test-local.ps1` (Rust) + `.\infra\test-flutter.ps1` (Flutter, contra runtime real); isolamento de fluxo; invalidação sem restart.
- **C — Confirmation:** gate `prevc-final-review`; commit gitflow por workstream.
