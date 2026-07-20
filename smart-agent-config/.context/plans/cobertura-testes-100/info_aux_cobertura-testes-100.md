# Documentação Auxiliar — Plano de Cobertura de Testes (rumo aos 100%)

> Gerado em: 2026-07-20
> Plano canônico: `.context/plans/cobertura-testes-100.md`
> Plano completo: `.context/plans/cobertura-testes-100/plano_completo_cobertura-testes-100.md`
> Origem: `doc_dev/planejamento/24-cobertura-testes-100.md` (agora histórico)

Este plano é uma **iniciativa de qualidade** (escrever testes), não uma integração
com serviço externo novo. Portanto: **Grupo B vazio** (nenhum serviço de terceiros),
e as "libs" do Grupo A são as **ferramentas de teste/cobertura**. O material de
verdade aqui é (a) o **baseline medido** e (b) os **padrões de teste** do projeto.

---

## Grupo A — Ferramentas de teste/cobertura (por stack)

### Rust
| Lib | Central | Estado | Uso |
|-----|---------|--------|-----|
| `cargo-llvm-cov` (0.8.x) | `doc_dev/libs/rust/cargo_llvm_cov.md` | CRIADO 2026-07-20 | medição de cobertura (unit e integrada) |
| `mockall` | `doc_dev/libs/rust/mockall.md` | USAR LOCAL | mock de traits nas **fronteiras externas** (nunca banco/domínio) |
| `sqlx` (`#[sqlx::test]`) | `doc_dev/libs/rust/sqlx.md` | USAR LOCAL | testes de banco com transação+rollback / fixtures |
| `tokio` (`#[tokio::test]`) | `doc_dev/libs/rust/tokio.md` | USAR LOCAL | testes async (com timeout em I/O) |

### Python (`ia_engine`)
| Lib | Central | Estado | Uso |
|-----|---------|--------|-----|
| `pytest-cov` (5.x) | `doc_dev/libs/python/pytest_cov.md` | CRIADO 2026-07-20 | cobertura (branch) do ia_engine |
| `pytest` (8.3+) / `pytest-asyncio` (0.24+) | — | padrão | runner + async (`asyncio_mode=auto`) |

### Flutter (`clients`)
| Lib | Central | Estado | Uso |
|-----|---------|--------|-----|
| `flutter test --coverage` | (nativo do SDK) | — | gera `coverage/lcov.info` por pacote |
| `mocktail` | `doc_dev/libs/flutter/mocktail.md` | USAR LOCAL | mock de dependências (DataSource/repos) |
| `flutter_bloc` (bloc_test) | `doc_dev/libs/flutter/flutter_bloc.md` | USAR LOCAL | testar transições de estado dos BLoCs |

> Regra de mocking do projeto (`testing-strategy.md`): **mock só nas fronteiras
> externas** (rede/serviços). Banco, cache e lógica de domínio própria são testados
> de verdade — mock de banco testa o mock, não o SQL.

---

## Baseline medido (2026-07-20) — a verdade técnica do plano

### Python — `ia_engine`: **73%** (961 stmts, 220 sem cobertura; 44 testes)
Lacunas por área (do `coverage.json`):
- `llm/provider_factory.py` **19%**, `llm/embeddings_factory.py` **24%** — resolução de provider + dim 1536.
- `shared/media.py` **19%** — parsing de payload de mídia.
- `features/*/repositories/*.py` **45–56%** — ramos de erro/retorno RSOE.
- `servicer.py` 77% — ramos de erro dos RPCs.
- `server.py`/`settings.py`/`telemetry.py` **0%** — bootstrap (excluir).
- `features/*/domain/*` 92–100% — já ótimo.

### Flutter — `clients`: **76,4%** (613/802 linhas)
- **38%** `initial_loading_module` · **57%** `get_it_module` · **61%** `design_system_module` · 71% `domain_models`.
- 78% `operacional_module` · 88% `login_module` · 91% `tenant_module` · 92% `presentation_module`.
- 100%: `app_config`, `api_client`, `navigation_module`, `core_module`, `smart-core-admin`, `smart-core-tenant`.

### Rust — server (**unit** `--lib --bins`): **48% de linhas** (16.623)
- `error_core` 99% · `local_engine` 80% · `infrastructure_messaging` 80% · `transport` 65% (real ≫).
- `domain_whatsapp` 54% · `infrastructure_postgres` 49% (real ≫) · `infrastructure_redis` 49% · `infrastructure_evolution` 47%.
- `infrastructure_storage` **30%** · `observability` **26%** · `test_support` 0% (helper).
- **`crates/application` não apareceu no sumário unitário** → medir isolado e priorizar unit dos usecases.
- ⚠️ **Unit ≠ real:** a integração (`tests/` contra Postgres/RLS + Redis via túnel) cobre
  muito do `infrastructure_postgres`/`transport`/`data_*`. A cobertura combinada real
  é materialmente maior — medir com `cargo llvm-cov --workspace` + túnel ativo.

---

## Instrumentação já entregue (reprodutível)
- Rust: `.\infra\test-local.ps1 -Coverage` → `coverage/rust-lcov.info` + summary.
- Python: `cd ia_engine; uv run pytest --cov=ia_engine --cov-report=term-missing`.
- Flutter: `.\infra\test-flutter.ps1 -Coverage` → `coverage/flutter-lcov.info` (agregado).
- `.gitignore`: artefatos de cobertura ignorados.

## Padrões de teste do projeto (referência canônica)
- **Rust:** skill `test-rust` + `testing-strategy.md` — unit inline `#[cfg(test)]`;
  integração em `tests/` com agregador `integration_tests.rs` + submódulos por domínio;
  AAA; `-> anyhow::Result<()>` com `?`; validar **variante** do erro (`matches!`);
  banco real com transação+rollback / `#[sqlx::test]`; RLS testado pela **negação**.
- **Python:** pytest + pytest-asyncio (`asyncio_mode=auto`); padrão RSOE
  (`return_success_or_error`) — testar o ramo de erro fechado por feature.
- **Flutter:** unit + widget + `bloc_test` para estados; `mocktail` nas fronteiras.

---

## Grupo C — Observabilidade e Auditoria (deste plano)
Plano de **testes**: o código de teste **não** emite trilha de auditoria nem logs
de produção. Portanto, na maioria das etapas: **"sem evento de auditoria"** (intencional).
Dois pontos válidos, porém:
1. **Cobrir o código de observabilidade/auditoria** é alvo — os testes devem exercitar
   que mutações sensíveis **geram** o `audit_log` esperado e que os logs **não vazam**
   segredo/PII (asserção de sanitização). Ex.: teste que confirma `api_key.update`
   auditado **sem** o segredo; teste que confirma telefone mascarado no log.
2. **Testes não podem logar/persistir segredo ou PII real** — usar fixtures/valores
   fake; nunca tokens/telefones reais nas fixtures versionadas.

## Notas gerais
- 100% é **norte**, com **exclusões justificadas** (entrypoints, stubs gerados, glue
  de FFI, DI puro) — para o número refletir cobertura **significativa** (política
  "bússola, não meta cega").
- Lacuna estrutural: **`ia_engine` não tem job no CI** (os 44 testes Python nunca
  rodam lá) — fechar isso é parte do gate de cobertura.
