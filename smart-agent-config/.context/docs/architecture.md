---
type: doc
name: architecture
description: System architecture, layers, patterns, and design decisions
category: architecture
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Architecture Notes

Smart Core Assistant v2 é um **modular monolith** em Rust (Cargo workspace) com um serviço Python de IA e um cliente Flutter. Separação em crates por domínio garante isolamento lógico e facilita promoção a microserviços sem reescrever.

**Princípio central:** o webhook nunca executa regra pesada — apenas autentica, resolve `tenant_id`, persiste o evento bruto e publica no event bus. Todo o domínio roda assincronamente no Worker.

## System Architecture Overview

```
WhatsApp ──webhook──► Evolution Go (multi-instância)
                              │
                    ┌─────────▼──────────┐
                    │  messaging_gateway  │  ← valida, resolve tenant, persiste bruto, publica
                    └─────────┬──────────┘
                              │ Redis Streams (envelope com tenant_id)
                    ┌─────────▼──────────┐
                    │      worker         │  ← debounce, conversa, ticket, kanban, IA, outbound
                    └──────┬─────┬───────┘
                           │     │ gRPC (não FFI/PyO3 — ver §13.1 do planejamento)
                    ┌──────▼──┐  └──► ia_engine (Python / LangChain / RAG; núcleo = FeaturesCompose)
                    │PostgreSQL│
                    │+ pgvector│
                    └──────────┘
                           ▲
              gRPC/HTTP + WebSocket
                    ┌──────┴──────────┐
                    │  runtime_api    │  ← API + realtime para Flutter
                    └─────────────────┘
                           ▲
                    Flutter (Windows → Web)
                           │ FFI (flutter_rust_bridge)
                    local_engine (SQLite + cache de mídia)

  + control_plane: tenants, planos, credenciais, instâncias Evolution
```

## Architectural Layers

- **`apps/*`**: Executáveis (binários Rust) — cada um é um processo independente.
- **`crates/domain_*`**: Regras puras de negócio, sem I/O, sem dependência de infraestrutura.
- **`crates/application`**: Orquestra casos de uso (`ReceiveMessage`, `DecideTicketPolicy`, `CanBotRespond`).
- **`crates/contracts`**: DTOs, eventos, contratos gRPC, envelopes — todos carregam `tenant_id`.
- **`crates/infrastructure_*`**: Adaptadores de banco (sqlx), Redis, Evolution Go, storage.
- **`crates/local_engine`**: Crate dual-target: lib dos binários-servidor **e** `cdylib`/`staticlib` para FFI do Flutter Windows.
- **`ia_engine/`**: Serviço Python separado (LangChain) chamado via **gRPC** pelo worker. Núcleo é a facade `FeaturesCompose` reaproveitada da v1 (só muda o ponto de entrada: task Celery → handler gRPC). FFI/PyO3 foi descartado (§13.1 do planejamento).
- **`clients/flutter_windows` + `clients/flutter_web`**: Dois apps Flutter separados + pacotes em `clients/packages/`, com camada `DataSource` abstrata (`LocalEngineFFI` no Windows, `RemoteOnly` na Web).

## Detected Design Patterns

| Pattern | Confiança | Localização | Descrição |
|---------|-----------|-------------|-----------|
| Event-Driven | Alta | `messaging_gateway` → Redis Streams → `worker` | Webhook publica evento; worker consome assincronamente |
| Domain-Driven Design | Alta | `crates/domain_*` | Crates por bounded context; regras puras sem I/O |
| CQRS (leve) | Média | `runtime_api` | Comandos via gRPC/HTTP (Flutter↔servidor, em aberto); realtime via WebSocket |
| Repository | Alta | `crates/infrastructure_postgres` | Adaptadores isolados do domínio |
| Strategy | Alta | `clients/packages/api_client` DataSource | `LocalEngineFFI` vs `RemoteOnly` trocáveis sem mudar lógica |
| Dual-Target Crate | Alta | `crates/local_engine` | Compilável como lib-servidor e cdylib/FFI |

## Entry Points

- `apps/messaging_gateway/src/main.rs` — ingestão de webhooks
- `apps/worker/src/main.rs` — processamento de eventos de domínio
- `apps/runtime_api/src/main.rs` — API + WebSocket para o Flutter
- `apps/control_plane/src/main.rs` — back office / gestão de tenants
- `ia_engine/src/server.py` — serviço gRPC de IA (Python)
- `clients/flutter_windows/lib/main.dart` — app Flutter Windows

> **Nota:** projeto greenfield — estrutura planejada em `doc_dev/planejamento/00-planejamento-inicial.md`.

## Public API

| Símbolo | Tipo | Localização |
|---------|------|-------------|
| `contracts::events::MessageReceived` | Evento | `crates/contracts` |
| `contracts::envelopes::TenantEnvelope` | DTO | `crates/contracts` |
| `domain_ticket::TicketPolicy` | Trait | `crates/domain_ticket` |
| `domain_conversation::Conversation` | Entity | `crates/domain_conversation` |
| `application::use_cases::ReceiveMessage` | Use Case | `crates/application` |
| `local_engine::LocalEngine` | FFI + lib | `crates/local_engine` |

## Internal System Boundaries

- **Gateway ↔ Worker**: Redis Streams com `tenant_id` no envelope. Gateway nunca conhece regras de domínio.
- **Worker ↔ ia_engine**: **gRPC** (processos separados; FFI/PyO3 descartado — §13.1). Rust nunca depende de detalhes do LangChain; contrato `.proto`/`domain_ai`. O worker também substitui o Celery da v1 (fila via Redis Streams + agendamento de feedback/retenção).
- **Worker ↔ Runtime API**: PostgreSQL + Redis pub/sub para fan-out de eventos realtime por tenant.
- **Flutter ↔ local_engine**: FFI via `flutter_rust_bridge` (somente Windows). Web usa `RemoteOnly`.

## External Service Dependencies

- **Evolution Go**: gateway WhatsApp multi-instância. Auth: `apikey` por instância. MinIO/S3 integrado para mídia.
- **PostgreSQL + pgvector**: banco unificado com RLS. `tenant_id` obrigatório em todas as tabelas.
- **Redis Streams**: event bus com consumer groups. Namespace por tenant para cache/presença.
- **MinIO/S3**: storage transitório de mídia (TTL curto; cache permanente no cliente).
- **OpenAI / Groq / Ollama**: provedores de LLM abstraídos pelo LangChain no `ia_engine`.

## Key Decisions & Trade-offs

| Decisão | Escolha | Racional |
|---------|---------|----------|
| Granularidade | Modular monolith (Cargo workspace) | Isolamento lógico agora; promoção futura sem reescrever |
| Banco multi-tenant | Um PostgreSQL + RLS | Sem provisionamento por tenant; migrations únicas |
| IA (`ia_engine`) | Serviço Python separado via **gRPC** (não FFI/PyO3) | Ecossistema maduro; isola a parte imatura; isolamento de processo + escala por réplicas (vence o GIL) |
| Flutter ↔ Rust | Híbrido (gRPC/WS + FFI local) | Servidor é fonte da verdade; FFI dá performance/offline no Windows |
| Ordem de entrega | Windows primeiro | Foco; port Web limpo via abstração `DataSource` |

## Top Directories Snapshot

- `server/` — Cargo workspace Rust (4 binários + ~14 crates de domínio, aplicação e infra)
- `evolution/` — configuração e gestão do Evolution Go (gateway WhatsApp multi-instância)
- `clients/packages/` — pacotes Dart compartilhados (core_ui, domain_models, api_client, local_engine_ffi)
- `clients/flutter_windows/` — app Flutter Windows desktop (fase 1)
- `clients/flutter_web/` — app Flutter Web (fase 2, projeto Flutter separado, sem FFI)
- `ia_engine/` — motor de IA em Python (LangChain, RAG, transcrição)
- `docker/` — infra local de desenvolvimento
- `smart-agent-config/` — planejamento e orquestração de agentes (esta pasta)
- `old/` — v1 Django (referência de domínio, git-ignored)

> Estrutura detalhada com regras de acoplamento: `doc_dev/01-estrutura-do-projeto.md`

## Related Resources

- [Project Overview](project-overview.md)
- [Data Flow](data-flow.md)
- [Planejamento Inicial](../doc_dev/planejamento/00-planejamento-inicial.md)
