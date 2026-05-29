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

- Implementar a UI do app Flutter para Windows (desktop) e depois Web.
- Implementar camada `DataSource` abstrata: `LocalEngineFFI` (Windows) e `RemoteOnly` (Web).
- Integrar com `runtime_api` via gRPC/HTTP (comandos) e WebSocket (realtime).
- Garantir que toda lógica de dados passa pela interface `DataSource`.
- Implementar stores reativos (Riverpod/Bloc) que respondem a eventos WebSocket.

## Platform Notes

- **Windows**: `DataSource` usa `LocalEngineFFI` via `flutter_rust_bridge`.
- **Web**: `DataSource` usa `RemoteOnly`. Mesma UI, só troca a implementação de dados.
- Arquivos gerados (`*.g.dart`, `*.freezed.dart`) git-ignored; regenerar com `flutter pub run build_runner build`.

## Quality Checks

- Nenhuma referência direta a FFI fora de `LocalEngineFFI`.
- `flutter test` passando.
- Telas funcionando no modo `RemoteOnly` antes de integrar FFI.
