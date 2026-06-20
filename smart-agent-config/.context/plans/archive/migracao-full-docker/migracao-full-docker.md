---
status: completed
generated: 2026-06-20
title: Migração Full-Docker (dev + prod)
artifacts:
  plano_completo: ".context/plans/migracao-full-docker/plano_completo_migracao-full-docker.md"
  info_aux: ".context/plans/migracao-full-docker/info_aux_migracao-full-docker.md"
phases:
  - id: "phase-p"
    name: "Planning — inventário, decisões, mapa de portas, bloqueador transport"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — approach: transport DNS, isolamento, redes, Dockerfile, edge, CI"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — transport, Dockerfile, compose, observability, edge, env, workflows, remoções"
    prevc: "E"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — subida ordenada + smoke-test (healthy, gRPC-Web, admin, traces, audit_log)"
    prevc: "V"
    agent: "devops-specialist"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review, limpeza Hostinger, arquivamento"
    prevc: "C"
    agent: "devops-specialist"
    status: "completed"
---

# Migração Full-Docker (dev + prod) — Plano Canônico

> Migrar a infra híbrida (binários Rust via systemd no host Hostinger + dados/observabilidade
> em Docker + Caddy no host) para **full-Docker**, do zero, com 2 ambientes isolados (dev/prod),
> imagens no **GHCR**, observabilidade **LGTM compartilhada** e remoção do provisioning de host.

## Artefatos detalhados
- **Plano completo (verdade técnica):** [plano_completo_migracao-full-docker.md](./migracao-full-docker/plano_completo_migracao-full-docker.md)
- **Documentação auxiliar (libs/serviços externos):** [info_aux_migracao-full-docker.md](./migracao-full-docker/info_aux_migracao-full-docker.md)

## Decisões fechadas
- **Registry:** GHCR — CI builda + push; servidor só `pull && up`.
- **Isolamento:** dados isolados por ambiente (postgres/redis/redis-bus/minio); observabilidade
  LGTM compartilhada (separação por `OTEL_SERVICE_NAMESPACE`).
- **Imagem Rust única** `smartcore-server` (7 binários, `command:` por serviço).
- **Imagem edge por-ambiente** `smartcore-edge` (Caddy + bundle Flutter embutido).
- **MinIO só em dev** (profile); prod usa Cloudflare R2.
- **Comunicação inter-serviços por TCP via DNS do Compose** → exige alteração na `transport`
  (`Endpoint::parse` hoje só aceita IP numérico — ver plano completo).

## Fases PREVC
| Fase | Foco | Status |
|------|------|--------|
| **P** | Inventário, decisões, mapa de portas TCP, identificação do bloqueador da transport | ✅ concluída |
| **R** | Revisão da abordagem (transport DNS, isolamento por project name, redes, Dockerfile cargo-chef, edge, CI GHCR) | pendente |
| **E** | E.1 transport · E.2 Dockerfile server · E.3 compose.yml · E.4 compose.observability.yml · E.5 edge · E.6 env-files · E.7 workflows · E.8 remoções | pendente |
| **V** | Subida ordenada + smoke-test (containers healthy, gRPC-Web, admin em /v2/admin/, traces por namespace, audit_log) | pendente |
| **C** | Final-review, limpeza do servidor Hostinger (legado), arquivamento | pendente |

## Observabilidade & Auditoria (transversal)
- OTLP preservado para `otel-collector:4317`; `OTEL_SERVICE_NAMESPACE=smartcore-{dev,prod}`.
- Sem novos eventos de auditoria de domínio (só muda transporte/empacotamento); smoke-test
  exige que a trilha `transport::bus → data_postgres → audit_log` continue funcionando.
- Segredos em `.env` fora do git; nunca logados; structs com credencial usam `secrecy`.
