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

Smart Core Assistant v2 é um **modular monolith** com o projeto inteiro localizado na raiz [smart-core-assistant-v2](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2). As configurações globais de IA e do contexto do agente (`.context/`) ficam centralizadas na subpasta [smart-agent-config](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config).

O monorepo abriga o backend em Rust (Cargo workspace), o serviço Python de IA e os clientes Flutter. A separação em crates por domínio garante isolamento lógico e facilita a promoção a microserviços sem reescrever. O sistema antigo em Django, localizado em [old](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/old), serve estritamente como especificação viva do domínio legado.

**Princípio central:** o webhook nunca executa regra pesada — apenas autentica, resolve `tenant_id`, persiste o evento bruto e publica no event bus. Todo o domínio roda assincronamente no Worker.

## System Architecture Overview

```
WhatsApp ──webhook──► Evolution Go (multi-instância)
                              │
                    ┌─────────▼──────────┐
                    │  messaging_gateway  │  ← valida, resolve tenant, persiste bruto, publica
                    └─────────┬──────────┘
                              │ transport::bus (Redis Streams; TenantEnvelope<T> com tenant_id)
                    ┌─────────▼──────────┐
                    │      worker         │  ← debounce, conversa, ticket, kanban, IA, outbound
                    └──────┬─────┬───────┘
                           │     │ gRPC (não FFI/PyO3 — ver §13.1 do planejamento)
                           │     └──► ia_engine (Python / LangChain / RAG; núcleo = FeaturesCompose)
                           │
       RPC tipado (UDS + FlatBuffers; gRPC/TCP fallback) — Envelope protobuf
        ┌──────────────────┼───────────────────┐
        ▼                  ▼                   ▼
 ┌────────────┐    ┌──────────────┐    ┌──────────────┐
 │data_postgres│   │  data_redis  │    │ data_storage │   ← únicos donos das infra_* libs
 │ PG+pgvector │   │ cache/tokens │    │ Cloudflare R2│
 │ +RLS+outbox │   │ locks/bus    │    │ (aws-sdk-s3) │
 └────────────┘    └──────────────┘    └──────────────┘
        ▲
       Contrato unificado D7: FlatBuffers/TCP padrão + gRPC fallback + Server Streaming (realtime)
                    ┌──────┴──────────┐
                    │  runtime_api    │  ← API + realtime p/ Flutter (desktop TCP/HTTP2; web WS binário/gRPC-Web)
                    └─────────────────┘
                           ▲
                    Flutter (Windows → Web)
                           │ FFI (flutter_rust_bridge)
                    local_engine (SQLite + cache de mídia)

  + control_plane: tenants, planos, credenciais, instâncias Evolution
  Apps de negócio (runtime_api/worker/gateway/control_plane) acessam dados só via RPC aos data_*.
```

## Arquitetura modular por contrato (decisão central)

O refator modular dividiu o backend em **processos independentes que se comunicam por
contrato**, nunca por import cruzado de código. O eixo é a separação **acesso a dados em
serviços `data_*`** acessados via **RPC sobre Unix Domain Sockets com FlatBuffers**
(gRPC/TCP como fallback):

- **Serviços de dados (`apps/data_*`)** — únicos donos das libs de infraestrutura:
  - `data_postgres` encapsula `infrastructure_postgres` (RLS, migrations, CRUD, outbox relay);
  - `data_redis` encapsula `infrastructure_redis` (cache, tokens, locks);
  - `data_storage` encapsula `infrastructure_storage` (Cloudflare R2 real via `aws-sdk-s3`; presign + purga via bus).
  - Expõem servidor RPC (FlatBuffers/UDS, gRPC fallback) e consomem o bus para tarefas assíncronas.
- **Apps de negócio (`apps/runtime_api`, `worker`, `messaging_gateway`, `control_plane`)** —
  **não** importam `infrastructure_*`; falam com os `data_*` via cliente RPC tipado de `transport`.
- **Crates de base (transversais)**: `contracts` (schemas `.proto` → FlatBuffers + gRPC,
  `Envelope` e `TenantEnvelope<T>`), `transport` (codecs, canais UDS/TCP/WS, framing RPC e
  `transport::bus` Redis Streams), `error_core` (`AppError`/`ErrorEnvelope`), `observability`
  (tracing OTLP, `traceparent`, auditoria via bus).

## Architectural Layers

- **`apps/*`**: Executáveis (binários Rust) — cada um é um processo independente.
- **`crates/application`**: Orquestra casos de uso de negócio (auth hoje; depois `ReceiveMessage`,
  `DecideTicketPolicy`, `CanBotRespond`), dependendo só de `contracts`/`transport` (RPC), não de infra.
- **`crates/contracts`**: schemas `.proto` canônicos, FlatBuffers e stubs gRPC gerados no build;
  expõe o `Envelope` (RPC) e o `TenantEnvelope<T>` (eventos do bus) — ambos carregam `tenant_id`.
- **`crates/transport`**: codecs FlatBuffers/gRPC, canais UDS/TCP/WS, framing RPC e o barramento `transport::bus`.
- **`crates/error_core` / `crates/observability`**: convenções transversais compiladas em todos os serviços.
- **`crates/infrastructure_*`**: adaptadores de banco (sqlx), Redis e storage — **consumidos
  exclusivamente** pelos respectivos `apps/data_*`, nunca pelos apps de negócio.
- **`crates/domain_*`** *(ainda não criados)*: regras puras sem I/O. **Opcionais** — extraídos da
  `application` só quando a complexidade justificar; até lá a regra vive em `application`.
- **`crates/local_engine`** *(F8, não criado)*: crate dual-target (lib-servidor **e**
  `cdylib`/`staticlib` para FFI do Flutter Windows).
- **`ia_engine/`** *(F5, não criado)*: serviço Python separado (LangChain) chamado via **gRPC** pelo
  worker. Núcleo é a facade `FeaturesCompose` da v1 (só muda o ponto de entrada: task Celery → handler
  gRPC). FFI/PyO3 foi descartado (§13.1 do planejamento).
- **`clients/flutter_windows` + `clients/flutter_web`** *(F6.5+, não criados)*: dois apps Flutter
  separados + pacotes em `clients/packages/`, com camada `DataSource` abstrata (`LocalEngineFFI` no
  Windows, `RemoteOnly` na Web).

## Detected Design Patterns

| Pattern | Confiança | Localização | Descrição |
|---------|-----------|-------------|-----------|
| Event-Driven | Alta | `messaging_gateway` → Redis Streams → `worker` | Webhook publica evento; worker consome assincronamente |
| RPC por contrato | Alta | `apps/data_*` + `crates/transport`/`contracts` | Acesso a dados isolado em serviços via UDS/FlatBuffers (gRPC fallback) |
| CQRS (leve) | Média | `runtime_api` | Comandos/consultas req/reply (FlatBuffers padrão, gRPC fallback); realtime via Server Streaming (contrato unificado — decisão D7) |
| Repository | Alta | `crates/infrastructure_postgres` | Adaptadores isolados do domínio (consumidos só por `data_postgres`) |
| Outbox + relay | Alta | `data_postgres` (migration 0011) | Escrita transacional + `LISTEN/NOTIFY` → publica no bus |
| Domain-Driven Design | Planejado | `crates/domain_*` (não criados) | Bounded contexts; regras puras sem I/O — extraídas da `application` quando justificar |
| Strategy | Planejado | `clients/packages/api_client` DataSource | `LocalEngineFFI` vs `RemoteOnly` trocáveis sem mudar lógica |
| Dual-Target Crate | Planejado | `crates/local_engine` (F8) | Compilável como lib-servidor e cdylib/FFI |

## Entry Points

- `apps/messaging_gateway/src/main.rs` — ingestão de webhooks
- `apps/worker/src/main.rs` — processamento de eventos de domínio
- `apps/runtime_api/src/main.rs` — API para o Flutter (contrato unificado D7: FlatBuffers padrão, gRPC fallback, Server Streaming)
- `apps/control_plane/src/main.rs` — back office / gestão de tenants
- `ia_engine/src/server.py` — serviço gRPC de IA (Python)
- `clients/flutter_windows/lib/main.dart` — app Flutter Windows

> **Nota:** em desenvolvimento. A **fundação modular já está implementada** — crates de base
> (`contracts`, `transport`, `error_core`, `observability`), os serviços `data_*` (RPC sobre
> UDS/FlatBuffers + consumo do bus) e as libs `infrastructure_postgres` (RLS, migrations
> 0001–0011, crypto, auth, `RequestContext`, outbox) e `infrastructure_redis` (bus, auth_tokens,
> cache, locks) e `infrastructure_storage` (**Cloudflare R2 real** via `aws-sdk-s3`). O **auth**
> (`application`/`runtime_api`) e os apps de negócio (`worker`, `messaging_gateway`,
> `control_plane`) estão **bootstrapados/em andamento**; `ia_engine`, `local_engine` e os
> clients Flutter **não foram criados**. Status real por etapa: `doc_dev/planejamento/02-fases-desenvolvimento.md`.

## Public API

| Símbolo | Tipo | Localização |
|---------|------|-------------|
| `contracts::Envelope` | DTO RPC (protobuf) | `crates/contracts` |
| `contracts::TenantEnvelope<T>` | DTO de evento do bus | `crates/contracts` (`src/envelope.rs`) |
| `contracts::ErrorEnvelope` | DTO de erro | `crates/contracts` |
| `transport::bus::{Consumer, publicar_evento}` | Barramento Redis Streams | `crates/transport` |
| `transport::Server` | Servidor RPC (rotas por `method`) | `crates/transport` |
| `error_core::AppError` / `to_error_envelope` | Erro agregado + ponte | `crates/error_core` |
| `observability::init_telemetry` | Bootstrap de tracing | `crates/observability` |
| `infrastructure_postgres::run_in_tenant_transaction` | RLS scope | `crates/infrastructure_postgres` |

## Internal System Boundaries

- **Apps de negócio ↔ dados**: acesso a Postgres/Redis/storage **só** via RPC tipado aos
  `apps/data_*` (UDS + FlatBuffers, gRPC/TCP fallback), embrulhado no `Envelope` protobuf.
  Nenhum app de negócio importa `infrastructure_*`.
- **Gateway ↔ Worker**: `transport::bus` (Redis Streams) com `TenantEnvelope<T>` (tenant_id no envelope). Gateway nunca conhece regras de domínio.
- **Worker ↔ ia_engine**: **gRPC** (processos separados; FFI/PyO3 descartado — §13.1). Rust nunca depende de detalhes do LangChain; contrato `.proto`/`domain_ai`. O worker também substitui o Celery da v1 (fila via Redis Streams + agendamento de feedback/retenção).
- **Worker ↔ Runtime API**: PostgreSQL + Redis pub/sub para fan-out de eventos realtime por tenant; o `runtime_api` empurra cada evento pelo **stream gRPC** aberto pelo cliente.
- **Flutter ↔ Runtime API**: **contrato unificado com transporte flexível (decisão D7)** — FlatBuffers padrão (desktop: TCP/TLS; Web: WebSocket binário) com gRPC como fallback comutável (`SMARTCORE_API_CODEC`; Web via gRPC-Web/`tonic-web`); realtime por Server Streaming.
- **Flutter ↔ local_engine**: FFI via `flutter_rust_bridge` (somente Windows). Web usa `RemoteOnly`.

## External Service Dependencies

- **Evolution Go**: gateway WhatsApp multi-instância. Auth: `apikey` por instância; expõe `mediaUrl` no payload via storage S3 próprio.
- **PostgreSQL + pgvector**: banco unificado com RLS. `tenant_id` obrigatório em todas as tabelas.
- **Redis Streams**: event bus com consumer groups. Namespace por tenant para cache/presença.
- **Cloudflare R2 (S3-compatible)**: storage transitório de mídia (TTL curto; cache permanente no cliente). Acesso HTTPS direto, sem MinIO/túnel.
- **OpenAI / Groq / Ollama**: provedores de LLM abstraídos pelo LangChain no `ia_engine`.

## Key Decisions & Trade-offs

| Decisão | Escolha | Racional |
|---------|---------|----------|
| Granularidade | Modular monolith (Cargo workspace) | Isolamento lógico agora; promoção futura sem reescrever |
| Banco multi-tenant | Um PostgreSQL + RLS | Sem provisionamento por tenant; migrations únicas |
| IA (`ia_engine`) | Serviço Python separado via **gRPC** (não FFI/PyO3) | Ecossistema maduro; isola a parte imatura; isolamento de processo + escala por réplicas (vence o GIL) |
| Flutter ↔ Rust | Contrato unificado D7 (FlatBuffers padrão + gRPC fallback + Server Streaming) + FFI local | Servidor é fonte da verdade; transporte comutável por configuração; FFI dá performance/offline no Windows |
| Ordem de entrega | Windows primeiro | Foco; port Web limpo via abstração `DataSource` |
| Construção da UI | Incremental, colada a cada feature (decisão D8) | A tela nasce junto da feature que valida (ex.: auth → login/cadastro); 2 apps Flutter + design system `core_ui` (tema dark) |

## Top Directories Snapshot

- [server/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server) — Cargo workspace Rust: **7 apps** (`data_postgres`, `data_redis`, `data_storage`, `runtime_api`, `worker`, `messaging_gateway`, `control_plane`) + **9 crates** (`contracts`, `transport`, `error_core`, `observability`, `application`, `infrastructure_postgres/redis/storage`, `test_support`)
- [evolution/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/evolution) — configuração e gestão do Evolution Go (gateway WhatsApp multi-instância)
- [clients/packages/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/packages) — pacotes Dart compartilhados (core_ui, domain_models, api_client, local_engine_ffi)
- [clients/flutter_windows/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/flutter_windows) — app Flutter Windows desktop (fase 1)
- [clients/flutter_web/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/clients/flutter_web) — app Flutter Web (fase 2, projeto Flutter separado, sem FFI)
- [ia_engine/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/ia_engine) — motor de IA em Python (LangChain, RAG, transcrição)
- [docker/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/docker) — infra local de desenvolvimento
- [smart-agent-config/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config) — planejamento e orquestração de agentes (esta pasta)
- [old/](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/old) — v1 Django (referência de domínio, git-ignored)

> Estrutura detalhada com regras de acoplamento: [01-estrutura-do-projeto.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/01-estrutura-do-projeto.md)

## Related Resources

- [Project Overview](project-overview.md)
- [Data Flow](data-flow.md)
- [00-planejamento-inicial.md](file:///C:/PROJETOS/FULL-STACK/smart-core-assistant-v2/smart-agent-config/doc_dev/planejamento/00-planejamento-inicial.md)
