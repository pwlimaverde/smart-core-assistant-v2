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

- **Raiz do monorepo (Monolito)**: [smart-core-assistant-v2](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2)
- **Pasta de Configurações e Agentes**: [smart-agent-config](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config) — Localização da pasta de contexto `.context/`
- **Sistema Legado v1 (Django)**: [old](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/old) — Usado exclusivamente como referência de regras de negócio e domínio.
- **Linguagens**: Rust (backend), Dart/Flutter (frontend), Python (IA)
- **Estado**: em desenvolvimento — **fundação modular implementada** (crates de base, serviços `data_*`, infra Postgres/Redis/R2); próxima fase: CI/CD, depois auth. Snapshot real por etapa em [02-fases-desenvolvimento.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/02-fases-desenvolvimento.md).
- **Estrutura de diretórios e diretrizes**: [01-estrutura-do-projeto.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/01-estrutura-do-projeto.md)
- **Planejamento arquitetural completo**: [00-planejamento-inicial.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/00-planejamento-inicial.md)

## Status de implementação (resumo)

> Fonte de verdade: `doc_dev/planejamento/02-fases-desenvolvimento.md` (§Estado atual).

- ✅ **Crates de base** — `contracts` (schemas `.proto`/`.fbs`, `Envelope`, `TenantEnvelope<T>`), `transport` (codecs FlatBuffers/gRPC, canais UDS/TCP/WS, `transport::bus`), `error_core`, `observability` (tracing OTLP + auditoria via bus).
- ✅ **`infrastructure_postgres`** — PostgreSQL único multi-tenant com **RLS**, migrations, crypto AES-256-GCM (`CipherManager`), auth (Argon2, `AuthUser`), `RequestContext` (RLS por transação), outbox.
- ✅ **`infrastructure_redis`** — event bus (Streams + consumer groups), `auth_tokens` (refresh com rotação/reuse-detection + blocklist), cache, locks.
- ✅ **`infrastructure_storage`** — cliente **Cloudflare R2** real (`aws-sdk-s3`, presign real, layout `media/{tenant}/...`); sem MinIO — R2 em dev e produção.
- ✅ **Serviços de dados** — `data_postgres`, `data_redis`, `data_storage` (servidores RPC; únicos donos das libs `infrastructure_*`).
- 🚧 **CI/CD + DevOps** (próxima fase — F-devops), **auth** (`user-auth-module`: `AuthService` + JWT no `runtime_api`), painel admin do superusuário; apps `messaging_gateway`/`worker`/`control_plane` bootstrapados.
- ⬜ **Pendentes** — `ia_engine` (Python), realtime (Server Streaming), `local_engine` (FFI), clients Flutter, `evolution/`.

## Entry Points

- `apps/data_postgres` / `apps/data_redis` / `apps/data_storage` — servidores RPC de dados (✅)
- `apps/messaging_gateway/src/main.rs` — ingestão de webhooks do Evolution Go (🚧 bootstrapado)
- `apps/worker/src/main.rs` — processamento de eventos de domínio (🚧 bootstrapado)
- `apps/runtime_api/src/main.rs` — API para Flutter: FlatBuffers/TCP padrão, gRPC fallback, Server Streaming realtime — decisão D7 (🚧)
- `apps/control_plane/src/main.rs` — gestão de tenants e planos; CLIs `create-superuser`/`delete-superuser` (🚧)
- `ia_engine/src/server.py` — serviço gRPC de IA (Python; núcleo `FeaturesCompose`) (⬜)
- `clients/flutter_windows/lib/main.dart` — app Flutter Windows (Web: `flutter_web/`) (⬜)

## Key Exports

**Já implementados (✅):**
- `crates/contracts` — `Envelope` (RPC), `TenantEnvelope<T>` (bus), schemas `.proto`/`.fbs` e stubs gerados
- `crates/transport` — codecs, canais UDS/TCP/WS, `transport::bus` (Redis Streams)
- `crates/error_core` / `crates/observability` — `AppError`/`ErrorEnvelope`, tracing OTLP
- `crates/infrastructure_postgres` — pool sqlx, migrations, RLS, `RequestContext`, `CipherManager`, auth/Argon2, outbox
- `crates/infrastructure_redis` — event bus (Streams), `auth_tokens` (refresh/blocklist), cache, locks
- `crates/infrastructure_storage` — cliente R2 (`aws-sdk-s3`), presign, layout de chaves por tenant

**Planejados (⬜/🚧):**
- `crates/application` (🚧 via auth) — casos de uso orquestrados
- `crates/domain_*` — regras puras de negócio (sem I/O); extraídos da `application` só quando justificar
- `crates/local_engine` — cache local + FFI para Flutter Windows

## File Structure & Code Organization

- [server/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server) — backend Rust (Cargo workspace: 7 apps + 9 crates)
- [evolution/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/evolution) — configuração do Evolution Go (gateway WhatsApp multi-instância)
- [clients/packages/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/packages) — pacotes Dart compartilhados entre os apps Flutter
- [clients/flutter_windows/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/flutter_windows) — app Flutter Windows desktop (fase 1)
- [clients/flutter_web/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/flutter_web) — app Flutter Web (fase 2, separado do Windows)
- [ia_engine/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/ia_engine) — motor de IA em Python (LangChain, RAG, transcrição)
- [docker/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/docker) — infra local de desenvolvimento (PostgreSQL+pgvector, Redis)
- [smart-agent-config/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config) — planejamento, agentes, CLAUDE.md e `.context/`
- [old/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/old) — v1 Django (referência de domínio apenas, git-ignored)

> Estrutura detalhada com responsabilidades e regras de acoplamento: [01-estrutura-do-projeto.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/01-estrutura-do-projeto.md)

## Technology Stack Summary

**Backend**: Rust com tokio, FlatBuffers/UDS-TCP como transporte padrão (gRPC via **tonic** como fallback; **tonic-web** para a Web — decisão D7), sqlx (PostgreSQL). Cargo workspace com 7 apps (4 de negócio + 3 serviços `data_*`) e 9 crates.

**Frontend**: Flutter/Dart, Windows desktop primeiro. FFI via `flutter_rust_bridge` com `local_engine`. Port Web usa `RemoteOnly` sem FFI.

**IA**: serviço Python `ia_engine` separado, consumido pelo worker via **gRPC** (não FFI/PyO3). LangChain, pgvector para RAG, provedores OpenAI/Groq/Ollama. Reaproveita a facade `FeaturesCompose` da v1.

**Infra**: PostgreSQL + pgvector (RLS), Redis Streams (event bus), Evolution Go (WhatsApp), Cloudflare R2 (mídia transitória, S3-compatible).

## Getting Started Checklist

1. Leia `doc_dev/planejamento/00-planejamento-inicial.md` — visão arquitetural completa.
2. Instale Rust (`rustup`), Flutter SDK, Python 3.13+ (com `uv`), `protoc` e `flatc`.
3. Configure `.env` a partir de `.env.example` na raiz do monorepo.
4. Suba infra local: `docker compose -f docker/compose/data.yml up -d`.
5. Build do workspace: `cargo build` em `server/`.

## Related Resources

- [Architecture](architecture.md)
- [Development Workflow](development-workflow.md)
- [Tooling](tooling.md)
- [00-planejamento-inicial.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/00-planejamento-inicial.md)
