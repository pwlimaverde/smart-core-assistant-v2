---
status: completed
generated: 2026-06-07
completed: 2026-06-07
slug: cicd-devops
scale: LARGE
artifacts:
  plano_completo: "./plano_completo_cicd-devops.md"
  info_aux: "./info_aux_cicd-devops.md"
  final_review: "../../../workflow/docs/final-review-cicd-devops.md"
phases:
  - id: "phase-p"
    name: "Planning — reestruturação do plano e validação de artefatos"
    prevc: "P"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — revisão de workflows, systemd, scripts e segurança"
    prevc: "R"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — provisionamento do servidor e deploy completo"
    prevc: "E"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — primeiro deploy end-to-end e smoke tests"
    prevc: "V"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — alertas Grafana, backup .env, documentação final"
    prevc: "C"
    agent: "devops-specialist"
    status: "completed"
---

# DevOps Completo: CI/CD, Ambientes e Provisionamento do Servidor

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/10-plano-cicd-devops.md`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./plano_completo_cicd-devops.md`](./plano_completo_cicd-devops.md)
- **Documentação auxiliar (ferramentas + serviços):**
  [`./info_aux_cicd-devops.md`](./info_aux_cicd-devops.md)

## Objetivo

Estabelecer **toda a infraestrutura de CI/CD e DevOps** do Smart Core Assistant v2 antes de
qualquer feature de negócio. Ao final, o pipeline estará funcional e o código será entregue
automaticamente nos dois ambientes (dev/prod) a cada push/tag.

**Servidor:** Hostinger KVM2 (2 vCPU / 8 GB RAM / Ubuntu 22.04 LTS)

O plano cobre:
- **GitHub Actions** — 4 workflows (CI, deploy-dev, deploy-prod, PR automático)
- **Self-hosted runner** no servidor para builds Rust nativos
- **systemd** — 14 service units + 2 targets (dev/prod)
- **Caddy** — reverse proxy com TLS automático para gRPC/h2c
- **Stack LGTM** — Grafana, Loki, Tempo, Prometheus, OTEL Collector, Promtail
- **Rollback** — de binários (symlink) e de banco (pg_dump)
- **Manutenção** — crons de limpeza, retenção de logs e releases

**Escopo especial:** todos os artefatos de infraestrutura (workflows, scripts, systemd units,
compose files, configs de observabilidade) **já existem e estão versionados** no repositório.
O foco da implementação é o **provisionamento do servidor** e a **validação end-to-end**.

**Fora do escopo:** features de negócio (auth, webhooks, IA), separação de `REDIS_BUS_URL`
(pendência registrada para antes de F3).

**Sinal de sucesso:** push em `dev` aciona CI + deploy automático; tag `v0.1.0` aciona deploy
prod com approval + GitHub Release + PR automático `dev→main`; Grafana acessível com
datasources funcionais; rollback testado (dev e prod).

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — reestruturação do plano e validação de artefatos | DevOps Specialist | ✅ completed |
| **R** | Review — revisão de workflows, systemd, scripts e segurança | DevOps Specialist (+ Security Auditor) | ✅ completed |
| **E** | Execution — provisionamento do servidor e deploy completo | DevOps Specialist | ✅ completed |
| **V** | Validation — primeiro deploy end-to-end e smoke tests | DevOps Specialist | ✅ completed |
| **C** | Confirmation — alertas Grafana, backup .env, documentação final | DevOps Specialist | ✅ completed |

## Decisões-chave (resumo — detalhes no plano completo)

1. **Self-hosted runner** no próprio Hostinger (builds rápidos com cache de ~/.cargo).
2. **Dois ambientes isolados** (dev/prod) no mesmo servidor, com portas/sockets/DBs separados.
3. **Rollback de binários** via symlink + backup automático (dev) / releases versionadas (prod).
4. **Migrations embutidas** nos binários (`sqlx::migrate!`); cópia manual para emergências.
5. **Observabilidade completa** (LGTM stack) com limites de memória por container.
6. **Caddy como reverse proxy** — TLS automático, h2c para gRPC Tonic.

## Correções aplicadas vs. plano base (doc_dev)

Plano alinhado com artefatos reais (10 divergências corrigidas — ver seção 6 do plano
completo). Destaques: Promtail adicionado, mem_limits presentes, `rustup update stable`
nos deploys, tracking de `PREV_RELEASE` via readlink, journald configurado no server-setup.

## Verificação

Sequência de validação: `server-setup.sh` → bancos de dados → `.env` → systemd units →
DNS → Caddy → self-hosted runner → GitHub environments → observabilidade → primeiro push
dev → tag `v0.1.0` → verificar rollback. Detalhes nas fases V.1–V.6 do plano completo.
Branch `feature/cicd-devops` a partir de `dev`.
