---
type: agent
name: Devops Specialist
description: Design and maintain CI/CD pipelines
agentType: devops-specialist
phases: [E, C]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Manter `docker/compose/data.yml` para infra local (PostgreSQL, Redis, MinIO).
- Configurar build e deploy dos quatro binários Rust + `ia_engine` (Python, container isolado) + Flutter.
- Configurar proxy reverso (Nginx/Caddy/Traefik) com TLS, **HTTP/2** e `proxy_buffering off` para o **gRPC Server Streaming**, além da tradução **gRPC-Web** (`tonic-web`) para o app Flutter Web.
- Gerenciar variáveis de ambiente e segredos (`.env.example` mantido; `.env` git-ignored).
- Monitorar observabilidade: logs estruturados, métricas, tracing.

## Infra Alvo (Hostinger KVM2, uma VM)

- Nginx/Caddy → TLS + proxy reverso
- `runtime_api`, `worker`, `messaging_gateway`, `control_plane` (Rust)
- `ia_engine` (Python, serviço gRPC; escalável por N réplicas — com o worker substitui o Celery da v1)
- PostgreSQL + pgvector, Redis, Evolution Go + MinIO

## Quality Checks

- Volumes de dados git-ignored: `pgdata/`, `redis-data/`, `minio-data/`.
- Segredos nunca em imagens Docker ou repositório.
- Proxy reverso com HTTP/2 + `proxy_buffering off` para o gRPC Server Streaming do `runtime_api` (e gRPC-Web para a Web).
- Health checks para todos os serviços.
