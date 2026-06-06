---
status: completed
generated: 2026-06-05
slug: refator-arquitetura-modular
scale: LARGE
artifacts:
  plano_completo: "./refator-arquitetura-modular/plano_completo_refator-arquitetura-modular.md"
  info_aux: "./refator-arquitetura-modular/info_aux_refator-arquitetura-modular.md"
phases:
  - id: "phase-p"
    name: "Planning — fundação de contrato, decisão .proto-canônica e congelamento do schema"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — contrato (envelope/errors), framing, mTLS e segurança do auth"
    prevc: "R"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — RF0..RF6 (contracts/transport → data_* → application → runtime_api → domínio)"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — interop FB↔gRPC, round-trip bytes↔[ubyte], trace distribuído, RLS multi-tenant"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — final-review, atualização dos docs 00–10 e arquivamento"
    prevc: "C"
    agent: "backend-specialist"
    status: "completed"
---

# Refator de Arquitetura Modular por Contrato (FlatBuffers/UDS + gRPC fallback)

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/refator-arquitetura-modular/05-refator-estado-atual.md` (+ docs 01–04).

## Artefatos

- **Plano completo (verdade técnica):**
  [`./refator-arquitetura-modular/plano_completo_refator-arquitetura-modular.md`](./refator-arquitetura-modular/plano_completo_refator-arquitetura-modular.md)
- **Documentação auxiliar (libs + toolchain + achado crítico):**
  [`./refator-arquitetura-modular/info_aux_refator-arquitetura-modular.md`](./refator-arquitetura-modular/info_aux_refator-arquitetura-modular.md)

## Objetivo

Migrar o `server/` de **crates in-process** para **serviços por contrato**: criar a camada
`contracts`/`transport` (FlatBuffers-first sobre UDS, gRPC plugável como fallback), aplicar os
**dois planos de acesso a dados** (RPC direto síncrono + bus Redis Streams assíncrono), manter
`error_core`/`observability` como **convenções** (ganhando `ErrorEnvelope` serializável e
`traceparent` no envelope), e nascer os apps `data_postgres`/`data_redis`/`data_storage`/
`runtime_api`/domínio. É **mais rewire que rewrite**: a base atual já antecipa boa parte do alvo
(`event_bus`, `TenantEnvelope`, `inserir_audit_log`, RLS/outbox, OTLP/W3C).

**Decisão de manchete (correção da reestruturação):** o `flatc` **não** transpila `.fbs`→`.proto`
(direção nativa é a inversa). A **fonte canônica de schema vira `.proto`** — `tonic-build`/`prost`
geram gRPC direto e `flatc --proto`→`.fbs`→`flatc --rust` geram FlatBuffers. **FlatBuffers
permanece o codec de fio padrão** (decisão do dono preservada); só muda o IDL autorado.

**Escopo (faseado RF0–RF6, dentro da fase E):** RF0 contracts/transport (runtime UDS, framing,
mux/keepalive/reconexão, codec FB/gRPC, bus); RF1 transversais (ErrorEnvelope, traceparent, rewire
de auditoria p/ Streams que remove o ciclo `observability→postgres`); RF2 `data_postgres` (server
3 protocolos + consumer + processadores RLS + relay outbox); RF3 `data_redis`/`data_storage`;
RF4 `application`/auth via contrato; RF5 `runtime_api` (FlatBuffers desktop+web, gRPC fallback);
RF6 `messaging_gateway`/`worker`/`control_plane`/`ia_engine`.

**Fora do escopo:** read-model/CQRS completo; cache-aside generalizado (só onde medir gargalo);
recuperação de senha/MFA/OAuth.

**Sinal de sucesso:** `transport`+`contracts` com envelope (tenant+traceparent+erro) e codec
comutável; trace distribuído provado em 2 processos; `data_*` operando por RPC direto + bus com
RLS/outbox preservados; `application` sem chamada direta a repositório; promoção de um serviço a
`tcp://` validada só por config; lint/test por stack verdes; comentários pt-br; sem segredos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — fundação de contrato, decisão `.proto`-canônica, congelamento do schema | Backend Specialist | ✅ completed |
| **R** | Review — contrato (envelope/errors), framing, mTLS e segurança do auth | Backend Specialist (+ Security Auditor) | ✅ completed |
| **E** | Execution — RF0..RF6 (E0..E6 como milestones) | Backend / Database / Devops / Test (por RF) | ✅ completed |
| **V** | Validation — interop FB↔gRPC, round-trip `bytes`↔`[ubyte]`, trace, RLS | Test Writer (+ Backend Specialist) | ✅ completed |
| **C** | Confirmation — final-review, atualização docs 00–10, arquivamento | Backend Specialist | ✅ completed |

> **Ciclo PREVC concluído em 2026-06-05.** Final-review (Opus) em
> [`../workflow/docs/final-review-refator-arquitetura-modular.md`](../workflow/docs/final-review-refator-arquitetura-modular.md):
> veredito de qualidade **CORRIGIDO** (clippy `-D warnings` + `cargo build -p contracts` verdes).
> Pendências conhecidas (stubs por design + keepalive/reconexão do transporte, feature
> `postgres-audit` ainda `default`, `traceparent` no evento do bus) registradas no relatório
> como trabalho futuro — fora do escopo deste ciclo.

### Milestones de Execução (fase E)

| Milestone | RF | Lead | Co-agentes | Docker/migrations |
|---|---|---|---|---|
| E0 | RF0 contracts/transport | backend-specialist | devops-specialist | volume UDS; `flatc` no CI |
| E1 | RF1 transversais/rewire | backend-specialist | database-specialist | Redis bus `noeviction` |
| E2 | RF2 data_postgres | database-specialist | backend-specialist | migration `0011_outbox`; UDS compose |
| E3 | RF3 data_redis/storage | backend-specialist | devops-specialist | MinIO/storage; sockets |
| E4 | RF4 application/auth | backend-specialist | test-writer | — |
| E5 | RF5 runtime_api | backend-specialist | test-writer | TCP/TLS, WS |
| E6 | RF6 domínio/ia_engine | backend-specialist | devops-specialist | VM GPU (TCP/TLS) |

## Decisões-chave (resumo — detalhes no plano completo)

1. **`.proto` como fonte canônica** (correção do `.fbs`→`.proto` inviável). `tonic-build`/`prost`
   geram gRPC; `flatc --proto`→`.fbs`→`flatc --rust` geram FlatBuffers. FlatBuffers **continua o
   codec de fio padrão**. Trade-off: conversão best-effort (cuidar `bytes`↔`[ubyte]`).
2. **FlatBuffers-first sobre UDS** + **runtime de transporte própria** (framing len/flags/corr_id,
   mux, keepalive, reconexão com backoff, backpressure, timeout). **gRPC fallback plugável** por
   config (`SMARTCORE_<SVC>_CODEC=grpc`) desde o RF0.
3. **Dois planos de acesso a dados:** RPC direto (síncrono) p/ leitura e escrita-com-ack; **bus
   Redis Streams** (assíncrono) p/ ingestão/eventos/auditoria. Leitura **nunca** passa por fila.
4. **Convenções permanecem libs:** `error_core` ganha `ErrorEnvelope` + categorias/campos novos;
   `observability` liga `traceparent` ao envelope. **Auditoria rewired** p/ Streams remove o ciclo
   `observability→infrastructure_postgres`.
5. **Toolchain:** instalar só `flatc v25.12.19` (o `protoc` vem **embutido** no tonic-build 0.14.6).
   `flatc --grpc` **não cobre Rust** → fallback gRPC usa prost/tonic (não FB-over-gRPC).
6. **Infra (projeto inicial, docker livre):** Redis do bus com `noeviction` (separar do
   `allkeys-lru` que evicta Streams); migration `0011_outbox` (tabela + trigger `pg_notify`);
   volume de sockets UDS compartilhado quando os `apps/` containerizarem.

## Correções aplicadas vs. plano base (docs 02/05)

Inversão `.fbs`→`.proto` (manchete: transpile inexistente no `flatc`); `protoc` embutido no
tonic-build (instalar só `flatc`); `flatc --grpc` não cobre Rust (fallback prost/tonic);
`ErrorCategory`/`Severity` via `TryFrom<i32>` (não `from_i32`); rewire de auditoria removendo o
ciclo `observability→postgres`; Redis bus `noeviction`; migration `0011_outbox`; `TenantEnvelope`
migra p/ `contracts` e `event_bus` vira `transport::bus`. Tabela completa na seção "Correções
aplicadas" do plano completo.

## Verificação

`flatc --version` (v25.x fixado no CI; **não** instalar protoc) → `cargo build -p contracts`
(gera prost+flatbuffers; asserção `bytes`↔`[ubyte]`) → ping req/reply por UDS + evento round-trip
pelo bus → interop FB↔gRPC do mesmo `method` → trace distribuído em 2 processos → `data_postgres`
ler/escrever agregado nos 3 protocolos (RLS) + outbox→relay→bus → `cargo clippy --all-targets
-D warnings` + `cargo fmt --check`. Gitflow a partir de `dev`; commits sem auto-referência ao
modelo; comentários em pt-br.
