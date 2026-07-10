---
type: plan
name: "Fase N1 — Fechamento do MVP + Scheduler do Worker"
planSlug: n1-fechamento-mvp-scheduler
description: "Primeira fase do backlog pós-MVP: merge e validação do MVP em dev, scheduler temporal do worker (F4.3b — timeout de feedback + disparo de purga de mídia), fechamento do elo outbox→outbound do atendente e dashboards/alertas Grafana provisionados como código."
summary: "Consolidar o MVP ponta-a-ponta em dev/produção e fechar a única lacuna estrutural da F4 (scheduler do worker), herdando o DoD transversal de observabilidade/auditoria + SOLID/Ports & Adapters."
status: filled
progress: 40
generated: "2026-07-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Scheduler temporal no worker (tokio::spawn + interval), RPCs de varredura no data_postgres, consumidor de envio outbound do atendente"
  - type: "devops-specialist"
    role: "Merge/deploy dev, dashboards e alertas Grafana provisionados como código (datasource UIDs fixos, alerting YAML)"
  - type: "architect-specialist"
    role: "Aprovar ports novos (SchedulerClock, RPCs de varredura) e o desenho de idempotência/lock"
  - type: "test-writer"
    role: "Validação via .\\infra\\test-local.ps1: timeout+purga idempotentes, outbound entregue"
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
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "devops-specialist"
    status: "pending"
lastUpdated: "2026-07-09T22:08:09.779Z"
---

# Fase N1 — Fechamento do MVP + Scheduler do Worker

> Primeira fase do backlog pós-MVP (N1–N5). **DoD transversal inegociável (herdado):**
> observabilidade (logs/traces + auditoria `audit_log`, sem segredos/PII) e SOLID/Ports & Adapters.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n1-fechamento-mvp-scheduler.md](./n1-fechamento-mvp-scheduler/plano_completo_n1-fechamento-mvp-scheduler.md)
- **Documentação auxiliar** (libs da central + Grafana provisioning): [info_aux_n1-fechamento-mvp-scheduler.md](./n1-fechamento-mvp-scheduler/info_aux_n1-fechamento-mvp-scheduler.md)
- **Origem:** `doc_dev/planejamento/16-fase-N1-fechamento-mvp-e-scheduler.md` (agora histórico)

## Escopo (tarefas)
| # | Foco | Tipo | Estado base |
|---|---|---|---|
| **N1.1** | Merge `feature/mvp-telas-e-endurecimento` → `dev` + smoke ponta-a-ponta | processo | branch já passou o gate `prevc-final-review` |
| **N1.2** | Scheduler temporal do worker: timeout de feedback + disparo de purga (F4.3b) | backend | worker só consome bus; consumidor de purga **já existe** no `data_storage` |
| **N1.3** | Elo outbox → outbound do atendente (`SendOutboundMessage` → relay → `data_whatsapp`) | backend | outbox+relay prontos; falta fechar o consumo do evento de envio |
| **N1.4** | Dashboards/alertas Grafana como código | devops | stack LGTM no ar, sem dashboards curados |

## Sequenciamento
**N1.1 → (N1.2 ‖ N1.3) → N1.4.** Detalhe técnico, correções aplicadas, contratos de
observabilidade por tarefa e riscos no [plano completo](./n1-fechamento-mvp-scheduler/plano_completo_n1-fechamento-mvp-scheduler.md).

## Fases (PREVC)
- **P:** aterrar scheduler + elo outbox (feito na reestruturação de 2026-07-06; revalidar diffs no início do ciclo).
- **R:** aprovar ports (`SchedulerClock`, RPCs `ListarAtendimentosFeedbackVencido`/`ListarMidiasExpiradas`) e estratégia de lock/idempotência.
- **E:** merge; scheduler; outbound do atendente; dashboards.
- **V:** `.\infra\test-local.ps1` — timeout+purga idempotentes (2 ticks sem duplicar), outbound entregue com `status_envio` correto.
- **C:** gate `prevc-final-review`; dashboards com dados reais; commit gitflow por tarefa.

## Execution History

> Last updated: 2026-07-09T22:08:09.779Z | Progress: 40%

### phase-p [DONE]
- Started: 2026-07-07T09:58:31.822Z
- Completed: 2026-07-07T09:58:31.822Z

### phase-r [DONE]
- Started: 2026-07-07T10:45:04.464Z
- Completed: 2026-07-07T10:45:04.464Z
