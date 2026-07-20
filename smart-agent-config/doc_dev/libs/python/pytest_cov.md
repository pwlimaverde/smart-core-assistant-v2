# pytest-cov

- **Versão Recomendada:** 5.0+
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-20
- **Propósito no Projeto:** Medição de cobertura do `ia_engine` (pytest + coverage.py). Bússola, **não meta cega** (ver `testing-strategy.md`).
- **Documentação Oficial:** https://pytest-cov.readthedocs.io/
- **Origem:** setup em primeira mão no projeto (2026-07-20), ferramenta estável.

---

## Histórico de Atualizações
- **2026-07-20** — Doc inicial. Instrumentação de cobertura Python (fase de cobertura de testes).

## 1. Instalação
No grupo dev do `ia_engine/pyproject.toml`:
```toml
[dependency-groups]
dev = ["pytest>=8.3", "pytest-asyncio>=0.24", "pytest-cov>=5.0", ...]
```
```bash
uv sync --dev
```

## 2. Config (pyproject.toml)
```toml
[tool.coverage.run]
source = ["ia_engine"]
branch = true
omit = ["src/ia_engine/contracts/*", "*/__main__.py"]

[tool.coverage.report]
show_missing = true
exclude_lines = ["pragma: no cover", "if __name__ == .__main__.:",
                 "raise NotImplementedError", "if TYPE_CHECKING:"]
```

## 3. Uso
```bash
cd ia_engine
uv run pytest --cov=ia_engine --cov-report=term-missing   # tabela + linhas faltantes
uv run pytest --cov=ia_engine --cov-report=json:coverage.json  # p/ parsing/CI
uv run pytest --cov=ia_engine --cov-report=html            # htmlcov/
uv run pytest --cov=ia_engine --cov-fail-under=80          # threshold (ratchet no CI)
```

## 4. Notas
- `branch = true` mede cobertura de ramos (não só linhas) — mais rigoroso.
- `omit`/`exclude_lines` mantêm o número **significativo** (fora stubs/bootstrap).
- Excluir trechos pontuais com comentário `# pragma: no cover` (justificado no diff).
- `--cov-fail-under=N` para o gate ratchet (falha se cair abaixo do baseline).

## 5. Referências
- https://pytest-cov.readthedocs.io/
- `doc_dev/planejamento/24-cobertura-testes-100.md` (plano de cobertura)
