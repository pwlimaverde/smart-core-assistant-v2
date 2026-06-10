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
- Guardar a **arquitetura modular por contrato**: apps de negócio nunca importam `infrastructure_*`; dados só via RPC aos serviços `data_*` (`Envelope` + `transport`).
- Manter separação entre `application`/`domain_*` (regras) e `infrastructure_*` (adaptadores, exclusivos dos `data_*`).
- Validar que o crate `local_engine` só contém lógica válida offline/cache — nada multi-tenant sensível.
- Transporte worker ↔ `ia_engine`: **gRPC** (decisão fechada — §13.1; FFI/PyO3 descartado). Flutter ↔ servidor: **contrato unificado D7** (FlatBuffers padrão; gRPC fallback; Server Streaming) — fechado. Estratégia de conflito de sync offline permanece em aberto.
- Revisar o design da camada `DataSource` para garantir port Web limpo (sem FFI).
- Documentar decisões em `doc_dev/` e atualizar `.context/docs/architecture.md`.

## Key Files & Context

- `doc_dev/planejamento/00-planejamento-inicial.md` — visão arquitetural completa
- `.context/docs/architecture.md` — snapshot de arquitetura
- `server/crates/contracts/` — schemas `.proto`/`.fbs`, `Envelope` e `TenantEnvelope<T>`
- `server/crates/transport/` — codecs, canais UDS/TCP/WS e `transport::bus`
- `server/apps/data_*` — únicos donos das libs `infrastructure_*`
- `clients/packages/api_client/` — interface `DataSource` abstrata (`RemoteOnly` / `LocalEngineFFI`) *(planejado)*
- `ia_engine/` — serviço Python gRPC (núcleo `FeaturesCompose` herdado da v1) *(planejado)*

## Quality Checks

- Toda mudança arquitetural documentada em `.context/docs/architecture.md`.
- Nenhum app de negócio importa `infrastructure_*`; nenhum `domain_*` depende de infra.
- `local_engine` não contém lógica que exija `tenant_id` de múltiplos tenants.
- Interface `DataSource` compila sem FFI (modo `RemoteOnly` para Web).
