---
status: filled
generated: 2026-06-04
agents:
  - type: "database-specialist"
    role: "Migration audit_log + repositório no infrastructure_postgres"
  - type: "backend-specialist"
    role: "Crate observability (telemetry + AuditLogger + span helpers)"
  - type: "devops-specialist"
    role: "Stack LGTM Docker Compose + configurações de serviço"
  - type: "security-auditor"
    role: "Validação de RLS, sanitização de PII, segurança da telemetria"
docs:
  - "architecture.md"
  - "security.md"
  - "data-flow.md"
phases:
  - id: "fase-1-infra-auditoria"
    name: "Infraestrutura PostgreSQL para Auditoria"
    prevc: "P"
    agent: "database-specialist"
    status: "pending"
  - id: "fase-2-crate-observability"
    name: "Crate observability (logs + OTel + AuditLogger)"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "fase-3-stack-lgtm"
    name: "Stack LGTM Self-Hosted (Docker Compose)"
    prevc: "E"
    agent: "devops-specialist"
    status: "pending"
  - id: "fase-4-metricas-spans"
    name: "Métricas e Spans Avançados"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "fase-5-health-alertas"
    name: "Health Checks, Alertas e Dashboards"
    prevc: "V"
    agent: "devops-specialist"
    status: "pending"
---

# Observabilidade e Auditoria — Logs Estruturados, Traces, Métricas e Auditoria no PostgreSQL

> Implementar o sistema completo de observabilidade (logs JSON, métricas OTel, traces distribuídos via LGTM stack) e logs de auditoria de negócio/segurança persistidos no PostgreSQL com RLS.

## Artefatos Detalhados

- **Plano completo:** [plano_completo_observabilidade-e-auditoria.md](./observabilidade-e-auditoria/plano_completo_observabilidade-e-auditoria.md)
- **Documentação auxiliar:** [info_aux_observabilidade-e-auditoria.md](./observabilidade-e-auditoria/info_aux_observabilidade-e-auditoria.md)

## Task Snapshot
- **Primary goal:** Sistema de observabilidade completo (logs, traces, métricas) + logs de auditoria no PostgreSQL com isolamento multi-tenant via RLS.
- **Success signal:** Binário emite JSON estruturado, traces visíveis no Tempo, audit_log persiste eventos de negócio com RLS, dashboards do Grafana provisionados.
- **Key references:**
  - [05-observabilidade.md](../../doc_dev/planejamento/05-observabilidade.md) (origem)
  - [03-infraestrutura-postgres.md](../../doc_dev/planejamento/03-infraestrutura-postgres.md) (fundação)
  - [06-tratamento-de-erros.md](../../doc_dev/planejamento/06-tratamento-de-erros.md) (integração)

## Divisão Essencial

| Tipo | Destino | Método | Volume |
|------|---------|--------|--------|
| **Logs de Aplicação** (técnicos) | stdout → Docker → Loki | JSON via `tracing` | Alto |
| **Logs de Auditoria** (negócio/segurança) | Tabela `audit_log` no PostgreSQL | INSERT via `AuditLogger` | Baixo |

## Working Phases

### Fase 1 — Infraestrutura PostgreSQL para Auditoria (F0.4)
> **Agente:** `database-specialist` | **PREVC:** P

- Migration `0010_audit_log.sql` com tabela, índices e RLS
- Módulo `auditoria/audit_log.rs` na crate `infrastructure_postgres`
- Registrar no `lib.rs`

### Fase 2 — Crate `observability` (F0.4)
> **Agente:** `backend-specialist` | **PREVC:** E

- Nova crate `server/crates/observability`
- `telemetry.rs`: init JSON + OTel OTLP/gRPC
- `audit.rs`: `AuditLogger` fire-and-forget
- `span_helpers.rs`: macro `tenant_span!`
- Taxonomia de eventos de auditoria

### Fase 3 — Stack LGTM Self-Hosted (F9.1)
> **Agente:** `devops-specialist` | **PREVC:** E

- `docker/compose/observability.yml` (Collector, Loki, Tempo, Prometheus, Grafana, Promtail)
- `docker/observability/` (configurações de cada serviço)
- Datasources e dashboards provisionados as-code

### Fase 4 — Métricas e Spans Avançados (F4–F6)
> **Agente:** `backend-specialist` | **PREVC:** E

- Contadores e histogramas OTel nos binários
- Spans com `tenant_id` via macro
- Propagação W3C TraceContext (gRPC)

### Fase 5 — Health Checks, Alertas e Dashboards (F9.1)
> **Agente:** `devops-specialist` | **PREVC:** V

- Endpoints `/health` e `/metrics` nos binários
- Alertas (Alertmanager/Grafana)
- Dashboards provisionados (overview, audit, performance, infra)

## Rollback Plan

- **Fase 1:** `DROP TABLE audit_log;` ou reverter migration via sqlx
- **Fase 2:** Remover crate `observability` do workspace
- **Fase 3:** `docker compose -f docker/compose/observability.yml down -v`
