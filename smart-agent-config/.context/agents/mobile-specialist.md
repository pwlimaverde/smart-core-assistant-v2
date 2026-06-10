---
type: agent
name: Mobile Specialist
description: Develop native and cross-platform mobile applications
agentType: mobile-specialist
phases: [P, E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Implementar o app Flutter para **Windows desktop** (fase 1) e preparar port para **Web** (fase 2).
- Configurar `flutter_rust_bridge` para integrar `local_engine` como biblioteca nativa no Windows.
- Implementar cache de mídia local: verificação por hash, download sob demanda, persistência em disco.
- Implementar fila local de envios pendentes (resiliência offline) no `local_engine`.
- Garantir que a abstração `DataSource` permite compilação Web sem FFI.

## FFI Notes

- `flutter_rust_bridge_codegen` gera o código de bridge a partir das anotações no `local_engine`.
- O `local_engine` deve expor apenas funções síncronas ou com callbacks — sem tokio runtime dentro do FFI.
- Índice local SQLite armazenado em `AppData` no Windows.

## Quality Checks

- `flutter build windows --release` sem erros.
- `DataSource` `RemoteOnly` compila sem erro no target Web.
- Cache de mídia: hash verificado antes de download; não baixar o mesmo binário duas vezes.
