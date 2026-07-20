# Plano Completo — Cobertura de Testes (rumo aos 100%)

> Gerado em: 2026-07-20 · Reestruturado contra o baseline **medido** e os padrões
> de teste do projeto (ver [info_aux](./info_aux_cobertura-testes-100.md)).
> Origem: `doc_dev/planejamento/24-cobertura-testes-100.md` (histórico).
> **Idioma:** Português (comunicação/documentação); código e identificadores em inglês.
> **Objetivo:** com a medição já instrumentada e o baseline conhecido, fechar as
> lacunas de cobertura **significativa** até o norte de 100%, com exclusões
> justificadas. Política: *"bússola, não meta cega"*.

## Correções aplicadas (vs. plano base — doc 24)

| # | Correção | Motivo / Fonte |
|---|---|---|
| 1 | Baseline deixou de ser estimativa: **medido de fato** — Python 73%, Flutter 76,4%, Rust unit 48% (por módulo). | execução de `pytest-cov`/`flutter --coverage`/`cargo llvm-cov` (2026-07-20) |
| 2 | Ferramentas de cobertura **curadas na central**: `cargo_llvm_cov.md` (rust) e `pytest_cov.md` (python). | central `doc_dev/libs/` |
| 3 | **Rust `application` não aparece no sumário unitário** — usecases exercitados via integração/mocks; virou P1 medir isolado + unit dos usecases. | sumário `cargo llvm-cov` |
| 4 | **Cobertura combinada Rust** (unit + integração) exige `cargo llvm-cov --workspace` com **túnel ativo** — o número unitário subestima o real. | `cargo_llvm_cov.md` §3 |
| 5 | **`ia_engine` sem job no CI** virou etapa explícita (os 44 testes Python nunca rodam no pipeline). | leitura do `ci.yml` |
| 6 | Regra de mocking (só fronteiras externas; banco/domínio reais) reafirmada por etapa. | `testing-strategy.md` |

---

## C1 — Gate de cobertura no CI (instrumentação → pipeline)

**Objetivo:** tornar a cobertura **visível e não-regressiva** no CI (a medição local
já existe via `-Coverage`). Começa **informativa**, evolui para **ratchet**.

**Passos:**
1. **Rust:** no job `rust` do `ci.yml` (que já sobe Postgres/Redis efêmeros), adicionar
   um passo `cargo llvm-cov` reaproveitando os service containers → cobertura
   **combinada** (unit + integração) real. Publicar `lcov` como artefato + resumo.
2. **Python:** **criar job de CI do `ia_engine`** (hoje inexistente): `uv sync` +
   `uv run pytest --cov=ia_engine --cov-report=xml` + resumo. Fecha a lacuna do
   Python não ter gate.
3. **Flutter:** no job `flutter`, `flutter test --coverage` por pacote (melos) + agregar
   lcov + resumo.
4. **Ratchet:** começar informativo (só reporta o %); depois `--cov-fail-under`/threshold
   por stack no baseline atual (falha só se **cair**), evitando exigir 100% de cara.

**DoD:** os três %s aparecem no CI; regressão de cobertura reprovada pelo ratchet.

**Observabilidade & Auditoria:**
- (a) É config de CI — sem span de runtime; o "log" é o resumo do job.
- (b) Sem evento de auditoria (intencional — não toca estado de produto).
- (c) Sem segredo/PII (fixtures de teste não carregam valores reais).

---

## C2 — Python `ia_engine` 73% → alvo (~95% do não-bootstrap)

**Áreas:** `llm/*`, `features/*/repositories`, `shared/media.py`, `servicer.py`.

**Passos:**
1. **`llm/provider_factory.py` (19%)** e **`embeddings_factory.py` (24%)**: testar
   resolução de slug `groq:`/`google_genai:`/`openai:` (via `init_chat_model`) e o
   **`output_dimensionality=1536` obrigatório** dos embeddings Google; cobrir o
   fallback e o erro de provider desconhecido.
2. **`features/*/repositories/*.py` (45–56%)**: cada repository RSOE tem o ramo de
   **erro fechado** não exercido — testar sucesso e erro com o datasource mockado
   (mock só na fronteira externa).
3. **`shared/media.py` (19%)**: parsing/normalização de payload de mídia com fixtures
   (image/audio/video) — inclui o caminho de payload inválido.
4. **`servicer.py` (77%)**: ramos de erro/degradação graciosa de cada RPC (falha da IA
   não trava o fluxo — asserção do comportamento gracioso).
5. Excluir bootstrap (`server.py`/`settings.py`/`telemetry.py`) via `omit` (justificado).

**DoD:** `uv run pytest --cov=ia_engine` mostra ≥ alvo no não-bootstrap; ruff/mypy limpos.

**Observabilidade & Auditoria:**
- (a) Sem span novo (é teste). Testes de `servicer` **asseguram** que os spans de
  degradação graciosa existem (assert de comportamento, não de log).
- (b) Sem evento de auditoria (o ia_engine não escreve audit_log; é serviço de IA).
- (c) Fixtures nunca carregam api_key/PII real; testar que a transcrição/áudio **não**
  aparece em log é um caso válido.

---

## C3 — Flutter `clients` 76,4% → alvo (~90% nos modulos de feature)

**Áreas:** `initial_loading_module`, `get_it_module`, `design_system_module`,
`domain_models`, `operacional_module`.

**Passos:**
1. **`initial_loading_module` (38%)**: fluxo de carregamento inicial + estados
   (loading/erro/pronto) via `bloc_test`.
2. **`get_it_module` (57%)**: casos de resolução/registro de dependências.
3. **`design_system_module` (61%)**: widget/golden tests dos componentes e tokens.
4. **`domain_models` (71%)**: serialização/desserialização e edge cases dos modelos.
5. **`operacional_module` (78%)**: estados de **erro** dos BLoCs de atendimento/kanban
   (mock do `AtendimentoDataSource` — a fronteira).

**DoD:** `.\infra\test-flutter.ps1 -Coverage` mostra ≥ alvo nos modulos; analyze verde.

**Observabilidade & Auditoria:**
- (a) N/A (UI/cliente; sem tracing de servidor).
- (b) Sem evento de auditoria.
- (c) Fixtures/mocks sem token/telefone real.

---

## C4 — Rust server (unit 48%, real ≫) → alvo (~90% nos crates de lógica)

**Áreas:** `crates/application`, `crates/domain_*`, `crates/local_engine`, ramos de
erro dos `apps/data_*`; completar integração em `infrastructure_*`.

**Passos:**
1. **Medir `application` isolado** (`cargo llvm-cov -p application`) — não apareceu no
   sumário do workspace; priorizar **unit dos usecases** (auth, TicketPolicy,
   BotRulesEngine, debounce — ver Testing Priorities).
2. **`domain_*`**: lógica pura — alvo 100% (conversões, branches de erro).
3. **`local_engine` (80%)**: ampliar unit da fila offline/LWW/índice SQLite.
4. **`apps/data_*`**: ramos de erro dos handlers (unit inline `#[cfg(test)]`).
5. **Integração**: completar `tests/` reais de `infrastructure_postgres` (ramos RLS/erro)
   e `transport` (bus: publicar→consumir→confirmar, replay).
6. **Medir combinado** com o túnel (`cargo llvm-cov --workspace` via `test-local.ps1`)
   para o número real, não o unitário.
7. Excluir `main.rs`/stubs (`--ignore-filename-regex`), justificado.

**DoD:** `.\infra\test-local.ps1 -Coverage` (e a suíte completa) verde; cobertura
combinada ≥ alvo nos crates de lógica; `application` medido.

**Observabilidade & Auditoria:**
- (a) Testes de integração já rodam sob `run_in_tenant_transaction`; **cobrir** que os
  spans/`error_code` são emitidos onde o plano exige.
- (b) **Cobrir a auditoria**: testar que mutações sensíveis (ex.: `api_key.update`,
  convites, mudança de cargo) **geram** o `audit_log` esperado, com metadados e **sem**
  o segredo — é a cobertura da própria trilha de auditoria.
- (c) Testar **sanitização**: asserção de que log/erro não vaza segredo/PII (telefone
  mascarado, `SecretString` redigido).

---

## C5 — P2 + revisão de exclusões + consolidação

**Passos:**
1. P2 dos três stacks (itens de menor peso: `servicer` restante, `domain_models`,
   widgets secundários, ramos de erro remanescentes dos `data_*`).
2. **Revisar exclusões** (§ do doc 24): confirmar que cada `omit`/`ignore`/`no cover`
   é intencional e justificado no diff — o número final reflete cobertura significativa.
3. Atualizar `testing-strategy.md` com os alvos por camada e o baseline/atual.
4. Ligar o **ratchet** no CI (threshold = cobertura consolidada) para travar regressão.

**DoD:** cobertura significativa no norte de 100% por camada de lógica; ratchet ativo;
`testing-strategy.md` atualizado.

**Observabilidade & Auditoria:** (a) N/A · (b) sem evento · (c) sem segredo/PII.

---

## Sequenciamento
**C1 (gate/CI) → (C2 ‖ C3 ‖ C4 em paralelo por stack) → C5 (consolidação/ratchet).**
C1 dá visibilidade cedo; C2/C3/C4 são independentes (stacks distintos, agentes
distintos); C5 fecha com o ratchet e a revisão de exclusões.

## Validação (fase V)
- `.\infra\test-local.ps1 -Coverage` + suíte completa (Rust, com túnel para o real).
- `cd ia_engine; uv run pytest --cov=ia_engine` (Python).
- `.\infra\test-flutter.ps1 -Coverage` (Flutter).
- CI: os três %s publicados + ratchet verde.

## DoD do plano
Cobertura **medida e visível no CI** nos 3 stacks; lacunas de valor fechadas
(factories/repositories Python, `initial_loading`/`get_it`/`design_system` Flutter,
usecases de `application`/domain Rust); exclusões justificadas; ratchet travando
regressão; `ia_engine` com job de CI. 100% tratado como norte com exclusões explícitas.
