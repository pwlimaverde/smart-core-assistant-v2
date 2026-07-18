---
type: plan
name: "Fase N7 — Endurecimento residual + operação validada (pré-cutover)"
planSlug: n7-endurecimento-residual
description: "Segunda fase do port final (N6–N8): quita as pendências técnicas de N1/N4/N5 — quotas de storage/departamentos (guard log-only, padrão N4.2), idempotência do sync offline por action_id (aditivo) + dead-letter de outbound, contadores de rate-limit unificados no RPC RegisterRateLimitAttempt do data_redis (já existente), sync offline robusto no desktop (trigger de reconexão via connectivity_plus + atomicidade single-statement no SQLite + Lagged no stream FFI) — e valida a operação com tráfego real (rajada/dashboards/E2E manual)."
summary: "Pré-condição dura do cutover: fechar as arestas residuais e provar operação com tráfego real. Reuso de padrões já entregues (QuotaGuard N4, fila offline N5); nenhum enforce de produção ligado aqui (isso é N8.3)."
status: filled
progress: 0
generated: "2026-07-18"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Quotas (data_storage/data_postgres), dedupe server-side + dead-letter, rate-limit via data_redis, evolução aditiva dos protos"
  - type: "mobile-specialist"
    role: "local_engine (atomicidade SQLite, Lagged no stream FFI), trigger de reconexão no operacional_module"
  - type: "architect-specialist"
    role: "Aprovar formato do action_id/dedupe, migrations e a fronteira do local_engine"
  - type: "devops-specialist"
    role: "Validação operacional manual: rajada via túnel, dashboards/alertas no Grafana, roteiro E2E"
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
    agent: "documentation-writer"
    status: "pending"
lastUpdated: "2026-07-18"
---

# Fase N7 — Endurecimento residual + operação validada (pré-cutover)

> Segunda fase do cronograma de **port final** (N6–N8). Quita as pendências
> técnicas registradas nos ciclos N1/N4/N5 e valida a operação com tráfego real —
> **pré-condição dura do cutover (N8)**. Sem isto, o enforce de produção seria
> ligado às cegas. **Invariante:** todo enforcement novo nasce **log-only atrás de
> flag** (padrão N4), com auditoria só no ponto de enforce real.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n7-endurecimento-residual.md](./n7-endurecimento-residual/plano_completo_n7-endurecimento-residual.md)
- **Documentação auxiliar** (aterramento no código + libs): [info_aux_n7-endurecimento-residual.md](./n7-endurecimento-residual/info_aux_n7-endurecimento-residual.md)
- **Origem:** `doc_dev/planejamento/22-fase-N7-endurecimento-residual.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N7.1** | Quotas restantes: migration `max_storage_bytes` + guard no `data_storage`; caller de `departamentos` no CRUD | recurso `"departamentos"` já reconhecido pelo store; falta caller + recurso `"storage"` |
| **N7.2** | Idempotência do sync: `action_id` (aditivo) nos RPCs Move/Send + dedupe server-side; dead-letter de outbound sem destino | `action_id` (uuid v7) já viaja client-side; falta campo no proto + dedupe |
| **N7.3** | Rate-limit do webhook unificado via RPC `RegisterRateLimitAttempt` do `data_redis` | **RPC já existe** e é usado pelo runtime_api; webhook migra do redis-bus |
| **N7.4** | Sync offline robusto: trigger de reconexão (`connectivity_plus`) + timer; atomicidade single-statement no SQLite; `Lagged` no stream FFI | `next_version` não-atômico; stream encerra silencioso em `Lagged` |
| **N7.5** | Validação operacional manual (relatório): rajada, dashboards/alertas, E2E do tenant | provisionado (N1.4) mas nunca validado com tráfego real |

## Sequenciamento
**N7.1 ‖ N7.3 → N7.2 → N7.4 → N7.5.** Correções da reestruturação (RPC de rate-limit
já pronto; `"departamentos"` já é recurso; atomicidade é single-statement no SQLite;
`Lagged` via resubscribe) no [plano completo](./n7-endurecimento-residual/plano_completo_n7-endurecimento-residual.md).

## Fases (PREVC)
- **P:** confirmar formato do `action_id`/dead-letter e limite de storage por plano.
- **R:** aprovar migrations + evolução aditiva dos protos + estratégia de dedupe.
- **E:** N7.1→N7.4 código; N7.5 roteiro manual — cada etapa com Observabilidade & Auditoria do plano completo.
- **V:** `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1` + relatório da validação manual.
- **C:** changelog, gate `prevc-final-review`, arquivamento.

## Execution History

> Last updated: 2026-07-18 | Progress: 0%
