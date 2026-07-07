---
type: plan
name: "Fase N2 — ia_engine (serviço Python de IA via gRPC)"
planSlug: n2-ia-engine
description: "Camada de IA como serviço Python separado (gRPC, decisão travada — não FFI): skeleton uv/grpc.aio, contratos/stubs nos dois lados, reescrita da FeaturesCompose em LangChain 1.x/LCEL, análise (transcribe/interpret/analyse/embed 1536), resposta+RAG via RPC pgvector sob RLS, integração worker→IA com degradação graciosa e UI de chat."
summary: "Entregar a inteligência do produto: bot responde com RAG e persona do tenant, mídia vira resumo/análise, com resiliência (fallback para a resposta fixa atual) e trace contínuo cruzando o processo Python."
status: filled
generated: "2026-07-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "ai-specialist"
    role: "ia_engine Python: grpc.aio, reescrita da FeaturesCompose em LCEL 1.x, features de análise, RAG e OTel Python"
  - type: "backend-specialist"
    role: "Contratos proto, port IaEngineClient + decorator ResilientIaEngine no worker, RPC QueryCompose no data_postgres"
  - type: "architect-specialist"
    role: "Aprovar RPCs de IA, fronteira de segredos (api key por request) e estratégia de degradação"
  - type: "frontend-specialist"
    role: "UI do chat: resposta da IA e resumo de mídia (N2.6)"
  - type: "test-writer"
    role: "Isolamento do RAG (pgvector sob RLS), degradação graciosa, testes de característica da facade"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-2"
    name: "Execution"
    prevc: "E"
    agent: "ai-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Fase N2 — `ia_engine` (serviço Python de IA via gRPC)

> Segunda fase do backlog pós-MVP. **Decisões travadas:** worker ↔ ia_engine é **gRPC, não FFI**
> (memória `ia-engine-grpc-decision`); banco de **porta única** — RAG via RPC `QueryCompose`
> no `data_postgres`, o Python não abre Postgres (memória `banco-unica-porta-via-infra-rpc`).

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n2-ia-engine.md](./n2-ia-engine/plano_completo_n2-ia-engine.md)
- **Documentação auxiliar** (LangChain 1.x, OTel Python, grpcio): [info_aux_n2-ia-engine.md](./n2-ia-engine/info_aux_n2-ia-engine.md)
- **Origem:** `doc_dev/planejamento/17-fase-N2-ia-engine.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N2.1** | Skeleton (`uv`, `grpc.aio`, healthcheck, OTel, compose) | pasta `ia_engine/` ausente |
| **N2.2** | Contratos/stubs (Rust+Python) + **reescrita** da `FeaturesCompose` em LCEL 1.x | facade da v1 em `old/` (langchain 0.1.x — APIs legadas removidas no 1.x) |
| **N2.3** | Análise: transcribe / interpret / analyse / embed **1536** | schema pgvector `0007` pronto |
| **N2.4** | Resposta + RAG (RPC `QueryCompose` sob RLS) + sentimento | tabelas de treinamento prontas |
| **N2.5** | Integração worker → IA (timeout/retry/degradação) + mídia (resumo + `MediaPointer`) | barreira de bot com resposta fixa em `worker/src/main.rs` |
| **N2.6** | UI: resposta da IA e resumo de mídia no chat | `operacional_module` pronto |

## Sequenciamento
**N2.1 → N2.2 → (N2.3 ‖ N2.4) → N2.5 → N2.6.** Maior incógnita de esforço do backlog;
**não bloqueia N3/N4** (podem correr em paralelo). Correções da reestruturação (porte é
reescrita em LCEL 1.x; pydantic v2; `init_chat_model`; setup OTel confirmado) no
[plano completo](./n2-ia-engine/plano_completo_n2-ia-engine.md).

## Fases (PREVC)
- **P:** validar skeleton + contratos de IA; confirmar modelo de embeddings 1536.
- **R:** aprovar RPCs de IA, `IaEngineClient` + `ResilientIaEngine` e fronteira de segredos.
- **E:** skeleton → facade → features → RAG → integração → UI.
- **V:** `.\infra\test-local.ps1` (RAG isolado por tenant, degradação) + `.\infra\test-flutter.ps1` (chat).
- **C:** resposta de IA ponta-a-ponta no WhatsApp; trace contínuo no Tempo; gate `prevc-final-review`.
