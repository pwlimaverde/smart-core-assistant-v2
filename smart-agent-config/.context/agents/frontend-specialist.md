---
type: agent
name: Frontend Specialist
description: Design and implement user interfaces
agentType: frontend-specialist
phases: [P, E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Implementar a UI do app Flutter para Windows (desktop) e depois Web, de forma **incremental** — a tela nasce colada à feature que valida (ex.: auth → login/cadastro). Decisão D8.
- Manter o **design system `core_ui`** (tema dark padrão; tokens slate/emerald) e reusar seus componentes (card de Kanban, painel de chat, inputs).
- Implementar camada `DataSource` abstrata: `LocalEngineFFI` (Windows) e `RemoteOnly` (Web).
- Integrar com `runtime_api` via **gRPC único**: unário (comandos/consultas) + Server Streaming (realtime). Desktop usa gRPC nativo HTTP/2; Web usa gRPC-Web. Sempre pela interface `DataSource` em `clients/packages/api_client/`.
- Garantir que toda lógica de dados passa pela interface `DataSource`.
- Implementar stores reativos (Riverpod/Bloc) que respondem aos eventos do **stream gRPC**.

## Platform Notes

- **Windows**: `DataSource` usa `LocalEngineFFI` via `flutter_rust_bridge`.
- **Web**: `DataSource` usa `RemoteOnly`. Mesma UI, só troca a implementação de dados.
- Arquivos gerados (`*.g.dart`, `*.freezed.dart`) git-ignored; regenerar com `flutter pub run build_runner build`.

## Quality Checks

- Nenhuma referência direta a FFI fora de `LocalEngineFFI`.
- `flutter test` passando.
- Telas funcionando no modo `RemoteOnly` antes de integrar FFI.
