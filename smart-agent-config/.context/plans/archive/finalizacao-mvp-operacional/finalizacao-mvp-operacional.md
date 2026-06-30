---
status: completed
generated: 2026-06-27
closed: 2026-06-30
closure_note: "Ciclo fechado como MVP PARCIAL via prevc-final-review. Entregues WS-0 (parcial), WS-1, WS-2 (exceto 2.4), WS-3, WS-4. Pendentes (backlog): WS-2.4 (ticket/kanban), WS-5 (Register/Invite/Accept + RBAC), WS-6 (telas Flutter), WS-7 (control_plane CRUD + admin), WS-0.1/0.3/0.4 (stack LGTM, e2e de trace, métricas de pool). Ver final-review-finalizacao-mvp-operacional.md."
agents:
  - type: "architect-specialist"
    role: "Validar Ports & Adapters/SOLID e o contrato de observabilidade transversal entre os workstreams"
  - type: "backend-specialist"
    role: "Implementar WS-0..WS-5/WS-7 (Rust): observabilidade/Grafana, webhook auth, orquestração do worker, outbound, realtime, control_plane CRUD"
  - type: "devops-specialist"
    role: "Subir a stack Grafana LGTM (Collector/Loki/Tempo/Prometheus) e expor via Caddy (WS-0)"
  - type: "frontend-specialist"
    role: "Implementar as telas operacionais (WS-6) e admin (WS-7) no smart-core-admin (Flutter)"
  - type: "security-auditor"
    role: "Revisar sanitização (secrecy), RLS e os eventos de auditoria obrigatórios (doc 08 §4.2)"
  - type: "test-writer"
    role: "Testes via .\\infra\\test-local.ps1 e .\\infra\\test-flutter.ps1, incluindo o teste de cadeia de trace ponta-a-ponta"
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
    agent: "backend-specialist"
    status: "completed-partial"
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

# Finalização do MVP Operacional — Frentes em Andamento + Observabilidade

> Fechar todas as frentes 🚧 do projeto e as lacunas da implementação inicial
> (com destaque para o **Grafana/observabilidade**), levando o produto a um **MVP
> operacional ponta-a-ponta**. **Regra inegociável:** tudo que for implementado
> passa pela observabilidade (logs/traces estruturados **+** auditoria `audit_log`)
> e segue **SOLID/Ports & Adapters**.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_finalizacao-mvp-operacional.md](./finalizacao-mvp-operacional/plano_completo_finalizacao-mvp-operacional.md)
- **Documentação auxiliar** (libs + serviços + APIs): [info_aux_finalizacao-mvp-operacional.md](./finalizacao-mvp-operacional/info_aux_finalizacao-mvp-operacional.md)
- **Origem:** `doc_dev/planejamento/15-plano-finalizacao-em-andamento.md` (+ conversa)
- **Bases:** `doc_dev/planejamento/{02-fases,05-observabilidade,10-plano-cicd-devops,11-painel-admin}.md`, `14-refator-solid-ports-adapters.md`, `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` (§4/§4.2)

## Escopo (workstreams)
| WS | Foco | Fase | Estado base |
|---|---|---|---|
| **WS-0** | Observabilidade transversal + stack Grafana LGTM; plugar `AuditLogger` no `worker`/`webhook_ingress` | devops-4/F9.1 | parcial |
| **WS-1** | `webhook_ingress`: auth do token de instância + whitelist + idempotência | F3.4 | sem validação |
| **WS-2** | `worker`: `domain_whatsapp` + resolução contato→atendimento + debounce + ticket/kanban/bot | F3.2/F4 | `atendimento_id` fixo |
| **WS-3** | Outbound: `worker` → `data_whatsapp::SendWhatsappMessage` (retry/backoff) | F4.4 | não chamado |
| **WS-4** | Realtime: server streaming real + fan-out por tenant via Redis Pub/Sub (0.25) | F6.2 | forward único |
| **WS-5** | `runtime_api`: Register/Invite/Accept + comandos de leitura + RBAC | F6.1/6.3 | só Login/Refresh/Logout |
| **WS-6** | Telas operacionais Flutter (fila + Kanban + chat realtime) | F4.6 | só login |
| **WS-7** | `control_plane` CRUD + `TenantConfigCache` plugado + telas admin | F2.2b/2.3/2.5 | só CLI superuser |

> **Fora do escopo (backlog):** F5 `ia_engine`, F8 `local_engine` (FFI), F10 port Web,
> F9.2 billing. O `worker`/telas já nascem com ponto de extensão para a IA.

## Requisito transversal (DoD de toda etapa)
- **Observabilidade:** span com `tenant_id`/`trace_id` (`observability::tenant_span!`),
  `traceparent` propagado bus→RPC, ≥ 1 evento `AuditLogger` por ação na convenção
  `<dominio>.<acao>` (publicado no bus → `data_postgres` → `audit_log` sob RLS), sem
  segredos/PII em log (`secrecy::SecretString`). Eventos críticos do doc 08 §4.2 sempre auditados.
- **SOLID/Ports & Adapters:** casos de uso na `application` dependem de **traits (ports)**,
  não de implementações (DIP); um adapter por fronteira (OCP via `ProviderRegistry`);
  ports pequenos (ISP); `domain_*` sem I/O.

## Fases (PREVC)

### P — Planning (concluída)
Plano base (doc 15) + reestruturação aterrada no código real; libs validadas contra a
central local + coleta (Grafana LGTM, Redis Pub/Sub 0.25). Correções aplicadas
registradas no `plano_completo`.

### R — Review (próxima)
Validar com `architect-specialist`: contrato de observabilidade, design Ports & Adapters
por WS, e o sequenciamento (WS-2 é caminho crítico). Confirmar a decisão de
descomissionar `messaging_gateway` e o novo RPC `VerifyWhatsappInstanceToken` (WS-1).

### E — Execution
Implementar na ordem WS-0 → WS-1 → WS-2 → WS-3 → WS-4 → WS-6 → (WS-5 ‖ WS-7).
Detalhe técnico máximo no [plano_completo](./finalizacao-mvp-operacional/plano_completo_finalizacao-mvp-operacional.md).

### V — Validation
`.\infra\test-local.ps1` (Rust) + `.\infra\test-flutter.ps1` (Flutter); teste de **cadeia
de trace ponta-a-ponta** (webhook → bus → worker → RPC → `audit_log`, mesmo `trace_id`);
isolamento multi-tenant do fan-out realtime.

### C — Confirmation
Gate `prevc-final-review`; descomissionar `messaging_gateway`; sincronizar status com o
doc 02; commit gitflow por workstream.

## Cronograma (S0.5–S9 — herdado do doc 02)
WS-0 (S0.5, paralelo a WS-1) → WS-1 (S1) → WS-2 (S2–S3, **crítico**) → WS-3+WS-4 (S4) →
**WS-6 (S5 = marco MVP ponta-a-ponta)** → WS-7 (S6) → WS-5 (S7) → endurecimento (S8–S9).
