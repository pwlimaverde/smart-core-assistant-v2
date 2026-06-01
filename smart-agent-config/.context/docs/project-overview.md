---
type: doc
name: project-overview
description: High-level overview of the project, its purpose, and key components
category: overview
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Project Overview

Smart Core Assistant v2 é uma plataforma SaaS multi-tenant de atendimento inteligente ao cliente via WhatsApp. Substitui a v1 (Django) com backend em Rust, frontend Flutter (Windows → Web), banco PostgreSQL unificado com RLS e um cluster Evolution Go multi-instância — eliminando a complexidade operacional de um banco e uma instância Evolution por tenant.

## Quick Facts

- **Raiz do monorepo**: `smart-core-assistant-v2/`
- **Esta pasta**: `smart-agent-config/` — planejamento e orquestração de agentes
- **Linguagens**: Rust (backend), Dart/Flutter (frontend), Python (IA)
- **Estado**: greenfield — somente planejamento; código de produção ainda não existe
- **Estrutura de diretórios e diretrizes**: `doc_dev/01-estrutura-do-projeto.md`
- **Planejamento arquitetural completo**: `doc_dev/planejamento/00-planejamento-inicial.md`

## Entry Points (planejados)

- `apps/messaging_gateway/src/main.rs` — ingestão de webhooks do Evolution Go
- `apps/worker/src/main.rs` — processamento de eventos de domínio
- `apps/runtime_api/src/main.rs` — API + WebSocket para Flutter
- `apps/control_plane/src/main.rs` — gestão de tenants e planos
- `ia_engine/src/server.py` — serviço gRPC de IA (Python; núcleo `FeaturesCompose`)
- `clients/flutter_windows/lib/main.dart` — app Flutter Windows (Web: `flutter_web/`)

## Key Exports (planejados)

- `crates/contracts` — DTOs, eventos, envelopes com `tenant_id`, contratos gRPC
- `crates/domain_*` — regras puras de negócio (sem I/O)
- `crates/application` — casos de uso orquestrados
- `crates/local_engine` — cache local + FFI para Flutter Windows

## File Structure & Code Organization

- `server/` — backend Rust (Cargo workspace: 4 binários + ~14 crates)
- `evolution/` — configuração do Evolution Go (gateway WhatsApp multi-instância)
- `clients/packages/` — pacotes Dart compartilhados entre os apps Flutter
- `clients/flutter_windows/` — app Flutter Windows desktop (fase 1)
- `clients/flutter_web/` — app Flutter Web (fase 2, separado do Windows)
- `ia_engine/` — motor de IA em Python (LangChain, RAG, transcrição)
- `docker/` — infra local de desenvolvimento (PostgreSQL, Redis, MinIO)
- `smart-agent-config/` — planejamento, agentes, CLAUDE.md e `.context/`
- `old/` — v1 Django (referência de domínio apenas, git-ignored)

> Estrutura detalhada com responsabilidades e regras de acoplamento: `doc_dev/01-estrutura-do-projeto.md`

## Technology Stack Summary

**Backend**: Rust com tokio, axum (HTTP), tonic (gRPC), sqlx (PostgreSQL). Quatro binários independentes em Cargo workspace.

**Frontend**: Flutter/Dart, Windows desktop primeiro. FFI via `flutter_rust_bridge` com `local_engine`. Port Web usa `RemoteOnly` sem FFI.

**IA**: serviço Python `ia_engine` separado, consumido pelo worker via **gRPC** (não FFI/PyO3). LangChain, pgvector para RAG, provedores OpenAI/Groq/Ollama. Reaproveita a facade `FeaturesCompose` da v1.

**Infra**: PostgreSQL + pgvector (RLS), Redis Streams (event bus), Evolution Go (WhatsApp), MinIO/S3 (mídia transitória).

## Getting Started Checklist

1. Leia `doc_dev/planejamento/00-planejamento-inicial.md` — visão arquitetural completa.
2. Instale Rust (`rustup`), Flutter SDK, Python 3.11+.
3. Configure `.env` a partir de `.env.example` na raiz do monorepo.
4. Suba infra local: `docker compose -f docker/compose/data.yml up -d`.
5. Build do workspace: `cargo build` na raiz do monorepo.

## Related Resources

- [Architecture](architecture.md)
- [Development Workflow](development-workflow.md)
- [Tooling](tooling.md)
- [Planejamento Inicial](../doc_dev/planejamento/00-planejamento-inicial.md)
