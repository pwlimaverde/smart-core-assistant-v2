---
name: pr-review
description: Review pull requests against team standards and best practices. Use when Reviewing a pull request before merge, Providing feedback on proposed changes, or Validating PR meets project standards
---

## Workflow

1. Leia a descrição do PR e o plano/feature relacionado (`.context/plans/` ou `doc_dev/`)
2. Confirme o gitflow: base correta (`dev` para feature/bugfix; `main` só p/ hotfix/release) e branch com prefixo certo
3. Verifique que os gates da stack passaram: Rust (`clippy --all-targets -- -D warnings`, `fmt --check`, testes), Python (`ruff`, `pyright`, pytest), Flutter (`analyze`, `test`)
4. Revise arquivo por arquivo com foco nas fronteiras: app de negócio importando `infrastructure_*` é bloqueio; query sem `tenant_id` é bloqueio
5. Cheque commits: inglês, conventional commits, sem `Co-Authored-By`/rodapés de IA
6. Verifique testes novos para regra nova e doc atualizada no mesmo PR
7. Aprove, peça mudanças ou comente — distinguindo obrigatório de sugestão

## Examples

**Pedido de mudanças:**
```
Bom progresso, mas há bloqueios:

1. apps/worker importa infrastructure_postgres direto — dados só via
   RPC ao data_postgres (handler novo, não dependência direta).
2. Query em handler_list_tickets sem filtro tenant_id (RLS é a segunda
   barreira, não a única).
3. Falta teste para a variante de erro de `decidir_politica_ticket`.

Sugestão (não bloqueia): extrair a montagem do Envelope repetida
nos 3 handlers para um helper em tests/common/.
```

## Quality Bar

- Fronteiras arquiteturais e isolamento de tenant são bloqueios, não sugestões
- Feedback específico com caminho do arquivo e alternativa concreta
- Sem `unwrap()`/`expect()` novos em produção Rust
- Comentários do código em pt-br; commits em inglês sem auto-referência de IA
- Aprovar somente com CI verde e confiança real na mudança

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
