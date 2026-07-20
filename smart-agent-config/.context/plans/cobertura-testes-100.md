---
type: plan
name: "Cobertura de Testes — rumo aos 100%"
planSlug: cobertura-testes-100
description: "Iniciativa de qualidade: com a medição instrumentada e o baseline medido (Python 73%, Flutter 76,4%, Rust unit 48% — real ≫ com integração), fechar as lacunas de cobertura significativa até o norte de 100% (exclusões justificadas de entrypoints/stubs/FFI), instrumentar o gate de cobertura no CI (ratchet) e cobrir a lacuna do ia_engine sem job no CI. Política: bússola, não meta cega."
summary: "Medir → priorizar por valor → fechar lacunas por stack (factories/repositories Python, initial_loading/get_it/design_system Flutter, usecases application/domain Rust) → ratchet no CI. Nenhum serviço externo novo; foco em testes e no gate de cobertura."
status: filled
progress: 100
generated: "2026-07-20"
scaffoldVersion: "2.0.0"
agents:
  - type: "test-writer"
    role: "Escrever unit/integração/widget/bloc tests fechando as lacunas por stack"
  - type: "devops-specialist"
    role: "Gate de cobertura no CI (llvm-cov/pytest-cov/flutter --coverage), job do ia_engine, ratchet"
  - type: "backend-specialist"
    role: "Cobertura Rust: usecases de application/domain, ramos de erro dos data_*, integração"
  - type: "mobile-specialist"
    role: "Cobertura Flutter: BLoCs (bloc_test), widgets/golden do design system, DI"
  - type: "ai-specialist"
    role: "Cobertura Python: llm factories, repositories RSOE, media parsing, servicer"
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
    agent: "test-writer"
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
    agent: "documentation-writer"
    status: "pending"
lastUpdated: "2026-07-20T17:56:19.288Z"
---

# Cobertura de Testes — rumo aos 100%

> Iniciativa de qualidade **paralela** ao port (N6–N8). A **instrumentação** e o
> **baseline** já estão prontos; falta fechar as lacunas de cobertura **significativa**
> e travar regressão no CI. **Política herdada** (`testing-strategy.md`): cobertura é
> *"bússola, não meta cega"* — 100% é o **norte**, com exclusões justificadas
> (entrypoints, stubs gerados, glue de FFI, DI puro).

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_cobertura-testes-100.md](./cobertura-testes-100/plano_completo_cobertura-testes-100.md)
- **Documentação auxiliar** (ferramentas + baseline medido + padrões): [info_aux_cobertura-testes-100.md](./cobertura-testes-100/info_aux_cobertura-testes-100.md)
- **Origem:** `doc_dev/planejamento/24-cobertura-testes-100.md` (agora histórico)

## Baseline medido (2026-07-20)
| Stack | Cobertura | Fracos |
|---|---|---|
| Python (`ia_engine`) | **73%** | `llm/*factory` 19–24%, `repositories/*` 45–56%, `shared/media` 19% |
| Flutter (`clients`) | **76,4%** | `initial_loading` 38%, `get_it` 57%, `design_system` 61% |
| Rust (server, **unit**) | **48%** linhas | `storage` 30%, `observability` 26%; integração cobre muito mais (real ≫) |

## Escopo (etapas)
| # | Foco |
|---|---|
| **C1** | Gate de cobertura no CI (llvm-cov combinado no job rust; **novo job do ia_engine**; flutter --coverage) + ratchet |
| **C2** | Python 73%→ alvo: llm factories, repositories RSOE, media parsing, ramos de erro do servicer |
| **C3** | Flutter 76,4%→ alvo: `initial_loading`/`get_it`/`design_system` (bloc_test/widget/golden), erros dos BLoCs |
| **C4** | Rust (unit 48%, real ≫)→ alvo: usecases de `application`+`domain`, ramos dos `data_*`, integração; medir combinado com túnel |
| **C5** | P2 + revisão de exclusões + `testing-strategy.md` atualizado + ratchet ativo |

## Sequenciamento
**C1 → (C2 ‖ C3 ‖ C4) → C5.** Detalhes, exemplos e a sub-seção
"Observabilidade & Auditoria" por etapa no [plano completo](./cobertura-testes-100/plano_completo_cobertura-testes-100.md).

## Fases (PREVC)
- **P:** confirmar exclusões (o que não conta pro 100%), alvo por camada e escala do ratchet.
- **R:** aprovar o gate ratchet (começa informativo) e a ordem por stack.
- **E:** C1→C5, cada etapa com Observabilidade & Auditoria (na maioria "sem evento de auditoria"; cobrir o código de audit/sanitização é alvo).
- **V:** `-Coverage` local (Rust com túnel para o real) + `uv run pytest --cov` + CI publicando os 3 %s + ratchet verde.
- **C:** changelog, `testing-strategy.md` atualizado, gate `prevc-final-review`, arquivamento.

## Execution History

> Last updated: 2026-07-20T17:56:19.288Z | Progress: 100%

### phase-2 [DONE]
- Started: 2026-07-20T14:56:55.681Z
- Completed: 2026-07-20T17:56:19.288Z

- [x] Step 1: Step 1 *(2026-07-20T15:16:04.967Z)*
  - Output: .github/workflows/ci.yml, clients/pubspec.yaml
  - Notes: C1: cargo llvm-cov combinado (informativo) + job novo ia_engine (pytest --cov) + flutter test --coverage agregado. CI 100% verde (4/4 jobs) na branch feature/cobertura-testes-100-c1-gate-ci, merge --no-ff em dev (072665f).
- [x] Step 2: Step 2 *(2026-07-20T16:35:06.254Z)*
  - Output: ia_engine/tests/ (130 testes)
  - Notes: C2: ia_engine 73% -> 99% (nao-bootstrap). 86 testes novos (44->130). ruff/mypy limpos. Merge --no-ff em dev (048daa5), CI 4/4 verde.
- [x] Step 3: Step 3 *(2026-07-20T17:10:57.282Z)*
  - Output: clients/*/test/ (201 testes)
  - Notes: C3: Flutter agregado 76,4% -> 93,5% (613/802 -> 848/907). 5 modulos fracos elevados (initial_loading 100%, get_it 97,6%, design_system 96,9%, domain_models 91,1%, operacional 90,6%). analyze limpo. Merge --no-ff em dev (c16251c), CI 4/4 verde.
- [x] Step 4: Step 4 *(2026-07-20T17:31:45.086Z)*
  - Output: server/crates/{application,domain_whatsapp,local_engine}, server/apps/{data_postgres,data_redis}
  - Notes: C4: application isolado 0->80,87%; domain_whatsapp 54,15%->99,30%; local_engine 73,45%->97,17% (isolado); workspace unitario 48%->54,31% (excluindo worker, problema ambiental de porta Redis local). Achado fora de escopo documentado: race condition em OfflineQueue::next_version (SELECT MAX+1 sem atomicidade) - teste que comprova a corrida foi escrito, fix arquitetural fica para follow-up. fmt/clippy limpos. Merge --no-ff em dev (e289771), CI 4/4 verde (incluindo llvm-cov combinado do CI da C1 rodando os novos testes).
- [x] Step 5: Step 5 *(2026-07-20T17:56:19.288Z)*
  - Output: .github/workflows/ci.yml, testing-strategy.md
  - Notes: C5: ratchet ativo (Python --cov-fail-under=90, Flutter piso 85% no lcov agregado); Rust mantido informativo (poucas rodadas da suite combinada em CI ainda). Exclusoes revisadas por stack, incluindo correcao da hipotese de excluir main.rs (C4 provou logica real la). testing-strategy.md atualizado com numeros finais C1-C4. Merge --no-ff em dev (0838a42), CI 4/4 verde.

### phase-p [DONE]
- Started: 2026-07-20T14:56:51.991Z
- Completed: 2026-07-20T14:56:51.991Z

### phase-r [DONE]
- Started: 2026-07-20T14:56:52.682Z
- Completed: 2026-07-20T14:56:52.682Z
