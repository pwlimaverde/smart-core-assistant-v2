# Plano de Cobertura de Testes — rumo aos 100%

> **Status:** Plano de execução — criado em **2026-07-20**.
> **Idioma:** Português (comunicação/documentação); código e identificadores em inglês.
> **Objetivo:** instrumentar a medição de cobertura nos três stacks, estabelecer o
> baseline real e traçar o caminho priorizado até 100% de cobertura **significativa**.
> **Política herdada** (`testing-strategy.md`): cobertura é *"bússola, não meta cega"*.
> 100% é o **norte**, com exclusões **justificadas e explícitas** (entrypoints,
> stubs gerados, glue de FFI) — nunca teste trivial só para inflar o número.

---

## 0. Instrumentação (feita)

A medição passou a ser reprodutível localmente e por stack:

| Stack | Ferramenta | Como rodar | Saída |
|---|---|---|---|
| **Rust** | `cargo llvm-cov` | `.\infra\test-local.ps1 -Coverage` (unit) | `coverage/rust-lcov.info` + summary |
| **Python** | `pytest-cov` | `cd ia_engine; uv run pytest --cov=ia_engine --cov-report=term-missing` | term + `coverage.json` |
| **Flutter** | `flutter test --coverage` | `.\infra\test-flutter.ps1 -Coverage` | `coverage/flutter-lcov.info` (agregado) |

- `ia_engine/pyproject.toml`: `pytest-cov` no grupo dev + `[tool.coverage.run]`
  (branch coverage, `omit` dos stubs `contracts/` e `__main__`).
- `infra/test-local.ps1 -Coverage`: `cargo llvm-cov --workspace --lib --bins`.
- `infra/test-flutter.ps1 -Coverage`: `flutter test --coverage` por pacote + agrega lcov.
- Artefatos de cobertura no `.gitignore`.

> **Nota:** a cobertura **Rust** aqui é **unitária** (`--lib --bins`, sem banco). A
> suíte de integração (Postgres/RLS, Redis) roda via túnel e cobre muito do
> `infrastructure_postgres`/`transport` que os unitários não alcançam — a cobertura
> "real" do Rust é **maior** que o baseline unitário abaixo. Medir a cobertura
> integrada exige `cargo llvm-cov` com o túnel ativo (ver §5, item CI).

---

## 1. Baseline medido (2026-07-20)

### Python — `ia_engine`: **73%** (961 stmts, 220 sem cobertura; 44 testes)

| Área | Cobertura | Lacuna principal |
|---|---|---|
| `features/*/domain/*` (usecases, models, parameters, errors) | 92–100% | quase completo |
| `features/*/datasources/*` | 70–100% | ramos de erro de `responder`/`transcribe` |
| `features/*/repositories/*` | **45–56%** | caminho de erro/retorno RSOE não exercido |
| `llm/provider_factory.py` | **19%** | resolução de provider (groq/google/openai) |
| `llm/embeddings_factory.py` | **24%** | fábrica de embeddings (dim 1536) |
| `shared/media.py` | **19%** | parsing/normalização de mídia |
| `servicer.py` | 77% | ramos de erro dos RPCs |
| `server.py` / `settings.py` / `telemetry.py` | **0%** | bootstrap/config (ver exclusões §3) |

### Flutter — clients: **76.4%** (613/802 linhas)

| Pacote | Cobertura | | Pacote | Cobertura |
|---|---|---|---|---|
| app_config | 100% | | login_module | 88% |
| api_client | 100% | | operacional_module | 78% |
| navigation_module | 100% | | domain_models | 71% |
| core_module | 100% | | design_system_module | **61%** |
| smart-core-admin | 100% | | get_it_module | **57%** |
| smart-core-tenant | 100% | | initial_loading_module | **38%** |
| tenant_module | 91% | | dependencies_module | 0/0 (só DI) |
| presentation_module | 92% | | | |

### Rust — server (unitário `--lib --bins`): **48% de linhas** (16.623 linhas)

> ⚠️ **Só unitário.** A suíte de integração (`tests/` contra Postgres/RLS + Redis
> via túnel) cobre grande parte do `infrastructure_postgres`/`transport`/`data_*`
> que **não** aparece aqui — a cobertura real é **materialmente maior**. Medir a
> cobertura combinada exige `cargo llvm-cov` com o túnel ativo (ver §5).

| Crate | Cobertura (unit) | | Crate | Cobertura (unit) |
|---|---|---|---|---|
| error_core | 99% | | domain_whatsapp | 54% |
| local_engine | 80% | | infrastructure_postgres | 49% (real ≫) |
| infrastructure_messaging | 80% | | infrastructure_redis | 49% (real ≫) |
| transport | 65% (real ≫) | | infrastructure_evolution | 47% |
| | | | infrastructure_storage | **30%** |
| | | | observability | **26%** |
| | | | test_support | 0% (helper de teste) |

- **`crates/application`** não apareceu no sumário unitário (usecases exercitados
  majoritariamente por integração/mocks nas `tests/`) — **medir isolado** e priorizar
  unit dos usecases é a P1 do Rust.
- Crates de `infrastructure_*` baixos no unit são, em boa parte, cobertos por
  integração real; o gap unitário concentra-se em `infrastructure_storage`,
  `observability` e ramos de erro dos `apps/data_*`.

---

## 2. Onde 100% agrega valor (prioridades)

Alinhado às **Testing Priorities** do `testing-strategy.md`:

1. **Regras de negócio / usecases** — `application` e `domain_*` (Rust), `features/*/domain`
   (Python): **alvo 100%**. É onde bug = comportamento errado ao cliente.
2. **Repositórios / datasources** — caminhos de erro (RSOE / `Result`) hoje descobertos.
   **Alvo ~100%** dos ramos de erro (mock só das fronteiras externas).
3. **Fábricas de provider/embeddings** (Python `llm/*`): resolução por slug + dim 1536.
4. **UI/BLoC** (Flutter modulos): estados de erro/loading dos BLoCs e widgets críticos.
5. **Integração** (Rust `infrastructure_postgres`/`transport`): já coberta por
   `tests/` reais — manter e completar ramos de RLS/erro.

---

## 3. Exclusões justificadas (não contam para o "100%")

Documentadas para o número refletir cobertura **significativa**:

- **Entrypoints/bootstrap:** `main.rs` dos apps, `server.py`, `settings.py`,
  `telemetry.py` — wiring de processo, testados de fato pelo boot/e2e, não por unit.
- **Código gerado:** stubs gRPC/FlatBuffers (`contracts`, `*.pb.dart`,
  `ia_engine/contracts`), bindings frb (`local_engine_ffi/lib/src/rust/**`), `cargokit/**`.
- **Glue de FFI:** `local_engine_ffi/rust/src/api` na borda Dart↔Rust (coberto pelo
  crate `local_engine` do lado Rust).
- **DI puro:** `dependencies_module`/`get_it` (registro sem lógica).

Marcar com `#[cfg(...)]`/`pragma: no cover`/`// coverage:ignore` quando aplicável,
ou via `omit`/`exclude` das configs — sempre com justificativa no diff.

---

## 4. Plano priorizado por stack

### Python (`ia_engine`) 73% → alvo
- **P1** `repositories/*` (45–56%): testar retorno de erro RSOE de cada repository
  (mock do datasource) — ~5 arquivos. **+~10 pts**.
- **P1** `llm/provider_factory.py` (19%) e `embeddings_factory.py` (24%): testar
  resolução `groq:`/`google_genai:`/`openai:` + `output_dimensionality=1536` e o
  fallback. **+~7 pts**.
- **P2** `shared/media.py` (19%): parsing de payload de mídia (fixtures de
  image/audio/video). **+~3 pts**.
- **P2** `servicer.py` (77%): ramos de erro/degradação graciosa de cada RPC.
- Excluir bootstrap (§3). **Alvo prático: ~95%+ do código não-bootstrap.**

### Flutter (clients) 76.4% → alvo
- **P1** `initial_loading_module` (38%): fluxo de carregamento inicial + estados.
- **P1** `get_it_module` (57%) e `design_system_module` (61%): widgets/tokens do
  design system com golden/widget tests; DI com casos de resolução.
- **P2** `domain_models` (71%): serialização/edge cases dos modelos.
- **P2** `operacional_module` (78%): estados de erro dos BLoCs de atendimento/kanban.
- Manter os 100% existentes. **Alvo prático: ~90%+ nos modulos de feature.**

### Rust (server) baseline → alvo
- **P1** `crates/application` (usecases/regras): completar ramos de erro — alvo 100%.
- **P1** `crates/domain_*`: lógica pura — alvo 100%.
- **P2** `crates/local_engine`: fila offline/LWW/índice — ampliar unit (já tem base).
- **P2** ramos de erro dos handlers dos `apps/data_*` (unit inline).
- Integração (`infrastructure_postgres`/`transport`): completar via `tests/` reais.
- Excluir `main.rs`/stubs (§3). **Alvo prático: ~90%+ nos crates de lógica.**

---

## 5. Gate de CI (recomendado — não incluído ainda)

1. **Job de cobertura não-bloqueante** por stack, publicando o % como resumo/artefato
   (lcov). Começa **informativo** (bússola).
2. Depois, **threshold progressivo** (ratchet): falha só se a cobertura **cair** abaixo
   do baseline atual (evita regressão sem exigir 100% de cara).
3. Rust integrado: rodar `cargo llvm-cov` no job que já sobe Postgres/Redis efêmeros
   (o `rust` do `ci.yml`), reaproveitando os service containers.
4. Python: adicionar **job de CI do `ia_engine`** (hoje inexistente) com `pytest --cov`
   — fecha a lacuna de o `ia_engine` não ter gate no CI.

---

## 6. Sequenciamento sugerido

**Instrumentação (feita) → baseline (feito) → P1 dos 3 stacks → gate ratchet no CI
→ P2 → revisão de exclusões.** Cada incremento roda o gate local (`-Coverage`) antes
do push. 100% tratado como norte com as exclusões da §3 assumidas explicitamente.
