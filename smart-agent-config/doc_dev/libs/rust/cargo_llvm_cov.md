# cargo-llvm-cov

- **Versão Recomendada:** 0.6+ (validado com 0.8.7)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-20
- **Propósito no Projeto:** Medição de cobertura da stack Rust (source-based, via LLVM). Bússola, **não meta cega** (ver `testing-strategy.md`). Ligado ao gate local `infra/test-local.ps1 -Coverage`.
- **Documentação Oficial:** https://github.com/taiki-e/cargo-llvm-cov
- **Origem:** setup em primeira mão no projeto (2026-07-20), ferramenta estável.

---

## Histórico de Atualizações
- **2026-07-20** — Doc inicial. Instrumentação de cobertura Rust (fase de cobertura de testes).

## 1. Instalação
```bash
rustup component add llvm-tools-preview
cargo install cargo-llvm-cov --locked
```

## 2. Uso no projeto

```bash
# a partir de server/ — cobertura UNITARIA (sem banco), igual ao -Fast do CI
$env:SQLX_OFFLINE = "true"; $env:RUST_TEST_THREADS = "1"
cargo llvm-cov --workspace --lib --bins --summary-only -- --test-threads=1

# gera lcov (consumivel por ferramentas/CI)
cargo llvm-cov --workspace --lib --bins --lcov --output-path coverage/rust-lcov.info -- --test-threads=1

# cobertura INTEGRADA (unit + tests/): exige o tunel SSH ativo (test_support) +
# DATABASE_URL/REDIS_URL apontando pro banco remoto. Roda a suite inteira.
cargo llvm-cov --workspace -- --test-threads=1
```

- `--summary-only`: só a tabela por arquivo + TOTAL (regions/functions/lines/branches).
- `--lcov --output-path`: lcov para CI/threshold.
- `--html`: relatório navegável em `target/llvm-cov/html`.
- `cargo llvm-cov report`: re-emite o relatório da última execução sem re-rodar.

## 3. Notas
- **Unit ≠ real:** `--lib --bins` cobre só unitários; a integração (Postgres/RLS/Redis
  via `tests/`) cobre muito mais de `infrastructure_postgres`/`transport` — a cobertura
  combinada exige rodar a suite completa com o túnel.
- Serializar (`--test-threads=1`) para os testes de banco não estourarem conexões.
- Excluir do numerador o que não faz sentido cobrir (entrypoints/stubs) via
  `--ignore-filename-regex` ou anotações `// coverage:ignore`.

## 4. Referências
- https://github.com/taiki-e/cargo-llvm-cov
- `doc_dev/planejamento/24-cobertura-testes-100.md` (plano de cobertura)
