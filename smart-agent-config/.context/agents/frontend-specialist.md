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
- Integrar com `runtime_api` via **contrato unificado D7**: FlatBuffers padrão (desktop: TCP/TLS; Web: WebSocket binário), gRPC como fallback comutável, Server Streaming para realtime. Sempre pela interface `DataSource`/factory do `api_client` (seleção por `kIsWeb`).
- Garantir que toda lógica de dados passa pela interface `DataSource` — a UI nunca fala com transporte/infraestrutura diretamente.
- Implementar stores reativos (Riverpod/Bloc) que respondem aos eventos do **stream realtime**.

## Platform Notes

- **Windows**: `DataSource` usa `LocalEngineFFI` via `flutter_rust_bridge`; canal primário TCP/TLS com FlatBuffers.
- **Web**: `DataSource` usa `RemoteOnly`; canal primário WebSocket binário (fallback gRPC-Web). Mesma UI, só troca a implementação de dados.
- Código gerado (`*.g.dart`, `*.freezed.dart`) não é versionado; regenerar com `dart run build_runner build`.

## Quality Checks

- Nenhuma referência direta a FFI fora de `LocalEngineFFI`.
- `flutter analyze` e `flutter test` passando.
- Telas funcionando no modo `RemoteOnly` antes de integrar FFI.
