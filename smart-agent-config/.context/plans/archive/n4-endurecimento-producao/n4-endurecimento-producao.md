---
type: plan
name: "Fase N4 — Endurecimento de Produção (billing, quotas, retenção, segurança)"
planSlug: n4-endurecimento-producao
description: "Prontidão comercial: role Postgres não-superuser (destrava os testes de RLS), medição de uso e enforcement de plan/subscription com QuotaGuard (log-only → enforce), bloqueio por inadimplência, retenção de mídia por política (+ R2 lifecycle como defesa em profundidade), rate limiting amplo e testes de carga/vazamento."
summary: "Fechar os buracos que separam o MVP de uma operação comercial: RLS provado de verdade, limites de plano aplicados no caminho quente e retenção de mídia governada por política."
status: filled
progress: 60
generated: "2026-07-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "database-specialist"
    role: "Role não-superuser com grants mínimos, fronteira pool × admin_pool, revalidação da suíte de isolamento RLS"
  - type: "backend-specialist"
    role: "QuotaGuard (port + decorator), medição de uso, bloqueio por inadimplência, retenção por política, rate limiting amplo"
  - type: "security-auditor"
    role: "Auditoria das policies RLS, testes de vazamento cross-tenant, varredura de segredos/PII em logs"
  - type: "devops-specialist"
    role: "Provisionamento da role por ambiente, R2 lifecycle versionado, testes de rajada/carga"
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
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "devops-specialist"
    status: "pending"
lastUpdated: "2026-07-16T23:57:57.551Z"
---

# Fase N4 — Endurecimento de Produção (billing, quotas, retenção, segurança)

> Quarta fase do backlog pós-MVP (F9). **N4.1 é pré-condição de credibilidade** dos testes de
> RLS (memória `db-remoto-role-bootstrap-superuser`) — **candidata a antecipação para logo
> após N1** (decisão do dono na fase P).

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n4-endurecimento-producao.md](./n4-endurecimento-producao/plano_completo_n4-endurecimento-producao.md)
- **Documentação auxiliar** (SQL da role, R2 lifecycle confirmado, libs): [info_aux_n4-endurecimento-producao.md](./n4-endurecimento-producao/info_aux_n4-endurecimento-producao.md)
- **Origem:** `doc_dev/planejamento/19-fase-N4-endurecimento-producao.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N4.1** | Role Postgres **não-superuser** + revalidação da suíte de isolamento | `smartcore_app` é bootstrap superuser → RLS cego em dev |
| **N4.2** | Billing/usage: medição, enforcement `plan`/`subscription` (**log-only → enforce**), bloqueio por inadimplência, quotas | CRUD pronto, sem enforcement; padrão de subquery de limite em `atendentes.rs:148` |
| **N4.3** | Retenção de mídia por política (+ R2 lifecycle versionado como defesa em profundidade) | consumidor de purga pronto; disparo vem do scheduler (N1.2) |
| **N4.4** | Segurança e carga: auditoria RLS, rate limiting amplo, testes de rajada, varredura de segredos | rate_limiter só de login no `data_redis` |

## Sequenciamento
**N4.1 → (N4.2 ‖ N4.3) → N4.4.** Depende da N1 (scheduler para retenção). Correções da
reestruturação (lifecycle do R2 confirmado via API S3; SQL de referência da role; log-only
promovido a passo) no [plano completo](./n4-endurecimento-producao/plano_completo_n4-endurecimento-producao.md).

## Fases (PREVC)
- **P:** decidir antecipação da N4.1; modelo de quota por recurso.
- **R:** aprovar grants mínimos + `QuotaGuard` + política de retenção.
- **E:** role; enforcement; retenção; rate limiting/carga.
- **V:** `.\infra\test-local.ps1` — isolamento **verde com a role real** + quota/bloqueio + carga.
- **C:** métricas de uso; eventos auditados; varredura de logs limpa; gate `prevc-final-review`.

## Execution History

> Last updated: 2026-07-16T23:57:57.551Z | Progress: 60%

### phase-2 [DONE]
- Started: 2026-07-16T23:57:51.776Z
- Completed: 2026-07-16T23:57:51.776Z

### phase-c [DONE]
- Started: 2026-07-16T23:57:57.551Z
- Completed: 2026-07-16T23:57:57.551Z

### phase-v [DONE]
- Started: 2026-07-16T23:57:54.790Z
- Completed: 2026-07-16T23:57:54.790Z
