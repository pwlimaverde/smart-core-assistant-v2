---
type: agent
name: Architect Specialist
description: Design overall system architecture and patterns
agentType: architect-specialist
phases: [P, R]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Garantir que o princípio central seja respeitado: **webhook nunca executa regra pesada**.
- Manter separação entre `domain_*` (regras puras) e `infrastructure_*` (adaptadores).
- Validar que o crate `local_engine` só contém lógica válida offline/cache — nada multi-tenant sensível.
- Transporte worker ↔ `ia_engine`: **gRPC** (decisão fechada — §13.1; FFI/PyO3 descartado). Protocolo Flutter ↔ servidor (gRPC vs REST+WS) e estratégia de conflito de sync permanecem em aberto.
- Revisar o design da camada `DataSource` para garantir port Web limpo (sem FFI).
- Documentar decisões em `doc_dev/` e atualizar `.context/docs/architecture.md`.

## Key Files & Context

- `doc_dev/planejamento/00-planejamento-inicial.md` — visão arquitetural completa
- `.context/docs/architecture.md` — snapshot de arquitetura
- `crates/contracts/` — contratos e envelopes com `tenant_id`
- `crates/local_engine/` — crate dual-target (lib + cdylib FFI)
- `clients/packages/api_client/` — interface `DataSource` abstrata (`RemoteOnly` / `LocalEngineFFI`)
- `ia_engine/` — serviço Python gRPC (núcleo `FeaturesCompose` herdado da v1)

## Quality Checks

- Toda mudança arquitetural documentada em `.context/docs/architecture.md`.
- Nenhum crate `domain_*` com dependência de `infrastructure_*`.
- `local_engine` não contém lógica que exija `tenant_id` de múltiplos tenants.
- Interface `DataSource` compila sem FFI (modo `RemoteOnly` para Web).
