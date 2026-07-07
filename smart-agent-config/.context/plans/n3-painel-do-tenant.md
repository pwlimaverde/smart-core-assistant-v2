---
type: plan
name: "Fase N3 — Painel do Tenant (convites, usuários e permissões)"
planSlug: n3-painel-do-tenant
description: "Autonomia do admin de tenant: telas de convite/aceite/register (CreateInvite/AcceptInvite já expostos), gestão de usuários com UI de flow_permissions (RBAC fino validado ponta-a-ponta pela UI), configuração do tenant, e decisão de empacotamento (módulo no smart-core-admin com RBAC de UI — recomendada — vs app dedicado)."
summary: "Dar autonomia ao admin de tenant (persona distinta do superusuário) construindo a UI sobre o backend de convites e RBAC fino já prontos; majoritariamente Flutter + RPC de escrita UpdateTenantUser."
status: filled
generated: "2026-07-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "frontend-specialist"
    role: "Telas de convite/aceite, gestão de usuários com multi-seleção de flow_permissions, config do tenant; RBAC de UI (guardas go_router)"
  - type: "backend-specialist"
    role: "RPC UpdateTenantUser (role/scopes/flow_permissions) + forwards de convite faltantes + invalidação do cache de flow_permissions"
  - type: "security-auditor"
    role: "Escopo de autorização (tenant:admin do próprio tenant), eventos críticos de TenantInvite/TenantUser com user_agent, defesa em profundidade UI+backend"
  - type: "test-writer"
    role: "Validação do RBAC fino pela UI contra o runtime real (.\\infra\\test-flutter.ps1)"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-2"
    name: "Execution"
    prevc: "E"
    agent: "frontend-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "security-auditor"
    status: "pending"
---

# Fase N3 — Painel do Tenant (convites, usuários e permissões)

> Terceira fase do backlog pós-MVP. **Decisão travada (memória
> `convites-tenant-nao-e-painel-superuser`):** convites e gestão de usuários são fluxo do
> **admin de tenant** — não entram no `admin_module`/`AdminFacade` do superusuário.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n3-painel-do-tenant.md](./n3-painel-do-tenant/plano_completo_n3-painel-do-tenant.md)
- **Documentação auxiliar** (libs Flutter da central + rotas backend): [info_aux_n3-painel-do-tenant.md](./n3-painel-do-tenant/info_aux_n3-painel-do-tenant.md)
- **Origem:** `doc_dev/planejamento/18-fase-N3-painel-do-tenant.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N3.1** | Telas de convite (gerar/listar/revogar) + aceite + register | `CreateInvite`/`AcceptInvite` **já expostos** (`runtime_api/src/main.rs:161`); mapear `ListInvites`/`RevokeInvite` na fase P |
| **N3.2** | Gestão de usuários + UI de `flow_permissions` (RBAC fino) | backend fim-a-fim pronto; falta RPC de escrita `UpdateTenantUser` |
| **N3.3** | Configuração do tenant (persona/prompts/providers, keys mascaradas) | `TenantConfig` + invalidação Pub/Sub prontos |
| **N3.4** | Empacotamento: módulo no `smart-core-admin` com RBAC de UI (recomendado) vs app dedicado | **decisão do dono na fase P** |

## Sequenciamento
**N3.4 (decisão) → N3.1 → N3.2 → N3.3.** Pode correr **em paralelo à N2**. Correções da
reestruturação (invalidação explícita do cache de `flow_permissions` promovida a recomendada;
guardas `redirect` do go_router) no [plano completo](./n3-painel-do-tenant/plano_completo_n3-painel-do-tenant.md).

## Fases (PREVC)
- **P:** mapear cobertura de rotas de convite na borda + **decidir empacotamento (A/B) com o dono**.
- **R:** aprovar `TenantAdminDataSource` + RBAC de UI + `UpdateTenantUser`.
- **E:** convites; gestão de usuários/fluxos; config do tenant.
- **V:** `.\infra\test-flutter.ps1` contra runtime real; **RBAC fino validado pela UI** (conceder/revogar fluxo muda a fila/Kanban do atendente).
- **C:** eventos críticos auditados com `user_agent`; sem PII/segredo; gate `prevc-final-review`.
