---
name: code-review
description: Review code quality, patterns, and best practices. Use when Reviewing code changes for quality, Checking adherence to coding standards, or Identifying potential bugs or issues
---

## Workflow

1. Understand the context and purpose of the code
2. Check for correctness and logic errors
3. Evaluate code structure and organization
4. Look for potential performance issues
5. Check for security vulnerabilities
6. Verify error handling is appropriate
7. Assess readability and maintainability

## Project-Specific Checks

- Apps de negócio sem import de `infrastructure_*` (dados só via RPC aos `data_*`); `domain_*`/`application` sem dependência de infra
- Toda query PostgreSQL com `tenant_id` explícito (além do RLS)
- Comentários no código em **português pt-br** com acentuação correta
- Erros via `error_core::AppError`/`ErrorEnvelope`; sem `unwrap()` / `expect()` em produção Rust
- Sem segredos hardcoded; variáveis de ambiente via `.env`
- Rust: `cargo clippy --all-targets -- -D warnings` e `cargo fmt --check` passando
- Python (`ia_engine`): `ruff` e `pyright` (strict) limpos; tipagem explícita
- Flutter: `flutter analyze` limpo; UI fala só com a interface `DataSource`

## Quality Bar

- Focus on the most impactful issues first
- Explain why something is a problem
- Provide concrete suggestions for improvement
- Balance thoroughness with pragmatism
