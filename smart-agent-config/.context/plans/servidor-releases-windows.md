---
type: plan
name: Servidor de Releases Windows — Auto-Update Robusto (Velopack)
description: Servidor Rust (Axum + Tokio) hospedando releases Windows com Velopack (sucessor do Squirrel), CI/CD GitHub Actions, cliente Flutter com auto-update silencioso, página principal com download.
planSlug: servidor-releases-windows
summary: "Servidor Rust (Axum + Tokio) hospedando releases Windows com Velopack, CI/CD pipeline GitHub Actions, cliente Flutter com auto-update silencioso, página principal com botão de download, observabilidade integrada."
prevc_scale: LARGE

phases:
  - id: "phase-p"
    name: "Planning — Design & Architecture"
    prevc: "P"
    summary: "Define arquitetura com Axum + Velopack, CI/CD, cliente Flutter, frontend e observabilidade. Validar integração Velopack + Flutter na spike P.3."
    required_sensors: []
    required_artifacts:
      - "arquitetura-releases-velopack.md"
      - "ci-cd-pipeline-design.md"
      - "velopack-flutter-integration-spike.md"
      - "frontend-mockup.md"
      - "security-checklist.md"
    deliverables:
      - "Documento de arquitetura (Axum + Velopack + Flutter) aprovado"
      - "Diagrama servidor → cliente Velopack"
      - "Especificação de API (/api/releases, /download/, /upload)"
      - "Spike P.3: validação Velopack Flutter integration"
      - "DNS registrado: releases.smartcoreassistant.com.br"

  - id: "phase-r"
    name: "Review — Security & Compliance"
    prevc: "R"
    summary: "Revisão de segurança (token sanitization, rate limiting), compliance, performance com especialistas."
    required_sensors:
      - "security_review"
      - "approval"
    required_artifacts:
      - "security-review-token-sanitization.md"
      - "performance-estimate-2vcpu.md"
      - "rate-limiting-tower-governor-version.md"
      - "approval-sign-off.md"
    deliverables:
      - "Security audit aprovado (Bearer token, SHA-256 handling)"
      - "Performance validada para 2 vCPU"
      - "Aprovação para implementação"

  - id: "phase-e"
    name: "Execution — Implementation"
    prevc: "E"
    summary: "Implementar servidor Rust (Axum 0.8), CI/CD, integração Velopack, frontend e observabilidade."
    required_sensors:
      - "tests"
      - "code_changes"
      - "build_status"
    required_artifacts:
      - "implementation-log.md"
      - "test-results.md"
      - "docker-compose-releases-validated.md"
    deliverables:
      - "Servidor Rust em container (smart-core-releases)"
      - "CI/CD completo (tag win-vX.Y.Z → build + upload)"
      - "Cliente Flutter integrado com Velopack"
      - "Página principal com botão de download"
      - "Observabilidade: métricas smartcore_releases_*"

  - id: "phase-v"
    name: "Validation — Testing & Verification"
    prevc: "V"
    summary: "Testes end-to-end (upload → download → client update), rollback, documentação operacional."
    required_sensors:
      - "integration_tests"
      - "performance_tests"
      - "security_audit"
    required_artifacts:
      - "test-report-e2e.md"
      - "validation-evidence-client-update.md"
      - "rollback-verification.md"
    deliverables:
      - "E2E: upload versão → cliente recebe atualização em <1h"
      - "Performance validada (2 vCPU, throughput)"
      - "Rollback testado (revert releases.win.json)"
      - "Runbook operacional"

  - id: "phase-c"
    name: "Complete — Handoff & Monitoring"
    prevc: "C"
    summary: "Stack em produção, alertas ativos, monitoramento contínuo."
    required_artifacts:
      - "handoff-summary-go-live.md"
      - "monitoring-dashboard-grafana.md"
      - "runbook-operacao.md"
      - "alert-rules-prometheus.md"
    deliverables:
      - "Servidor live na Hostinger com alertas"
      - "Dashboard Grafana com métricas de releases"
      - "Runbook de operação (publicar versão, reverter, debug)"
      - "Alertas para: upload falhou, taxa erro >5%, disco <10%"

generated: 2026-10-03
status: ready-para-detalhamento
scaffoldVersion: "2.0.0"
---

# Servidor de Releases Windows — Auto-Update Robusto (Velopack)

> **Versão revisada** (2026-10-03): Usa **Velopack** (sucessor do Squirrel.Windows), cliente **Flutter** (não .NET), servidor **Axum 0.8** + **Tokio** (não Actix). Tudo documentado em detalhe em `.context/plans/servidor-releases-windows/plano_completo_servidor-releases-windows.md`.

## Visão Geral — Arquitetura Velopack

```
┌─────────────────────────────────────────────────────────────────┐
│ CLIENTE WINDOWS (Flutter App: smart-core-tenant.exe)            │
├─────────────────────────────────────────────────────────────────┤
│ Integração Velopack (via velopack_flutter ou FFI próprio)       │
│ ├─ VelopackApp.Build().Run() na inicialização (hook de install) │
│ ├─ Checa a cada 1h: GET releases.smartcoreassistant.com.br/... │
│ └─ Se nova versão: baixa silenciosamente, aplica no próximo    │
│    restart (zero downtime)                                      │
└──────────────────────────────────────────────────────┬───────────┘
                                                        │
                                                        ↓
                        ┌───────────────────────────────────────────┐
                        │ SERVIDOR RUST (Axum 0.8 + Tokio)          │
                        │ Container: smart-core-releases (novo)     │
                        │ Host: releases.smartcoreassistant.com.br  │
                        │ Porta: 8086 (Hostinger interno)           │
                        ├───────────────────────────────────────────┤
                        │ GET /releases.win.json (feed)             │
                        │ GET /releases.win.json.gz/.br (cached)    │
                        │ GET /download/{version}/{filename}        │
                        │ POST /upload (CI/CD, Bearer token)        │
                        │ GET /health (healthcheck)                 │
                        └───────────────────────────────────────────┘
                                    ↑
                                    │ CI/CD
                        ┌───────────┴──────────────┐
                        │  GITHUB ACTIONS          │
                        ├──────────────────────────┤
                        │ On: push tag win-vX.Y.Z  │
                        │ 1. Build Windows app     │
                        │ 2. vpk pack              │
                        │ 3. POST /upload          │
                        └──────────────────────────┘
```

---

## Principais Decisões Técnicas

### Por que Velopack (não Squirrel)?
- **Squirrel.Windows** é maintenance-mode (comunidade Clowd.Squirrel)
- **Velopack** é o sucessor oficial, com SDKs Rust + Flutter support
- **Cliente real** é Flutter, não .NET — Velopack integra via `velopack_flutter` (pub.dev)

### Por que Axum (não Actix)?
- Workspace já usa **Axum 0.8** (`webhook_ingress`, `control_plane`)
- **Tower-HTTP 0.6** para middleware (CORS, compressão, file serving)
- Sem novo runtime de middleware

### Porta e DNS
- **Porta:** `8086` (Hostinger interno, roteiado via Caddy)
- **DNS:** `releases.smartcoreassistant.com.br` (pendente registro)
- **Tag de release:** `win-vX.Y.Z` (não `v*` — evita disparar deploy-prod)

### Observabilidade
- **Logs:** Estruturados com `tracing`, nunca imprimir token completo
- **Métricas:** `smartcore_releases_*` (downloads, upload latency, errors)
- **Auditoria:** Sem evento de `audit_log` (servidor não modifica state de tenant)

---

## Planos Detalhados

📖 **Leia o plano completo:** `.context/plans/servidor-releases-windows/plano_completo_servidor-releases-windows.md`

📋 **Documentação auxiliar (libs):** `.context/plans/servidor-releases-windows/info_aux_servidor-releases-windows.md`

---

## Checklist de Execução

Fases PREVC (Plan → Review → Execute → Validate → Complete):

- **P** (Planning): Spike P.3 validar Velopack + Flutter, registrar DNS
- **R** (Review): Security audit (token, rate limiting), aprovação
- **E** (Execution): Implementar servidor Rust, CI/CD, container
- **V** (Validation): E2E tests (upload → client update), rollback
- **C** (Complete): Go live, monitoring, runbook

---

## Referências Rápidas

- 🔗 **Velopack:** https://docs.velopack.io
- 🔗 **Axum 0.8:** https://docs.rs/axum/0.8
- 🔗 **Tower-HTTP 0.6:** https://docs.rs/tower-http/0.6
- 📁 **Libs Rust:** `doc_dev/libs/rust/{axum,tower-http,tokio,serde,tracing}.md`
- 🏗️ **Arquitetura:** `.context/docs/architecture.md`
