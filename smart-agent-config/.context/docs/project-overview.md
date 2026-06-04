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
- **Estado**: em desenvolvimento — **fundação de persistência, barramento e segurança já implementada**; módulo de autenticação em andamento. Demais apps/crates ainda não criados. Snapshot real por etapa em `doc_dev/planejamento/02-fases-desenvolvimento.md`.
- **Estrutura de diretórios e diretrizes**: `doc_dev/planejamento/01-estrutura-do-projeto.md`
- **Planejamento arquitetural completo**: `doc_dev/planejamento/00-planejamento-inicial.md`

## Status de implementação (resumo)

> Fonte de verdade: `doc_dev/planejamento/02-fases-desenvolvimento.md` (§Estado atual).

- ✅ **`server/crates/infrastructure_postgres`** — PostgreSQL único multi-tenant com **RLS**, migrations **0001–0009**, crypto AES-256-GCM (`CipherManager`), auth (Argon2, `AuthUser`), `RequestContext` (RLS por transação), cache de config.
- ✅ **`server/crates/infrastructure_redis`** — event bus (Streams + consumer groups + `TenantEnvelope`), `auth_tokens` (refresh com rotação/reuse-detection + blocklist), cache.
- ✅ **Storage Cloudflare R2** configurado e validado; **infra local** (`docker/compose/data.yml`: PG+pgvector, Redis, MinIO) + scripts de deploy.
- 🚧 **Auth** (`user-auth-module`) — cria `contracts` (`auth.proto`), `application` (`AuthService`) e o app `runtime_api` (Tonic + interceptor JWT). PREVC: P concluído; R/E/V/C pendentes.
- ⬜ **Pendentes** — apps `messaging_gateway`/`worker`/`control_plane`, `ia_engine` (Python), `realtime`, `local_engine` (FFI), clients Flutter, `evolution/`, crates `observability`/`error_core`, CI/CD.

## Entry Points (planejados)

- `apps/messaging_gateway/src/main.rs` — ingestão de webhooks do Evolution Go
- `apps/worker/src/main.rs` — processamento de eventos de domínio
- `apps/runtime_api/src/main.rs` — API gRPC (unário + Server Streaming) para Flutter
- `apps/control_plane/src/main.rs` — gestão de tenants e planos
- `ia_engine/src/server.py` — serviço gRPC de IA (Python; núcleo `FeaturesCompose`)
- `clients/flutter_windows/lib/main.dart` — app Flutter Windows (Web: `flutter_web/`)

## Key Exports

**Já implementados (✅):**
- `crates/infrastructure_postgres` — pool sqlx, migrations 0001–0009, RLS, `RequestContext`, `CipherManager`, auth/Argon2
- `crates/infrastructure_redis` — event bus (Streams), `auth_tokens` (refresh/blocklist), cache, `TenantEnvelope`

**Planejados (⬜/🚧):**
- `crates/contracts` (🚧 via auth) — DTOs, eventos, envelopes com `tenant_id`, contratos gRPC
- `crates/application` (🚧 via auth) — casos de uso orquestrados
- `crates/domain_*` — regras puras de negócio (sem I/O)
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

> Estrutura detalhada com responsabilidades e regras de acoplamento: `doc_dev/planejamento/01-estrutura-do-projeto.md`

## Technology Stack Summary

**Backend**: Rust com tokio, **tonic** (gRPC unário + Server Streaming) + **tonic-web** (gRPC-Web para a Web), sqlx (PostgreSQL). Quatro binários independentes em Cargo workspace.

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
