---
type: skill
name: Code Review
description: Review code quality, patterns, and best practices. Use when Reviewing code changes for quality, Checking adherence to coding standards, or Identifying potential bugs or issues
skillSlug: code-review
phases: [R, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
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

- `crates/domain_*` sem import de `crates/infrastructure_*`
- Toda query PostgreSQL com `tenant_id` explícito (além do RLS)
- Comentários no código em **português pt-br** com acentuação correta
- Sem `unwrap()` / `expect()` em código de produção Rust
- Sem segredos hardcoded; variáveis de ambiente via `.env`
- `cargo clippy -- -D warnings` e `cargo fmt --check` passando

## Quality Bar

- Focus on the most impactful issues first
- Explain why something is a problem
- Provide concrete suggestions for improvement
- Balance thoroughness with pragmatism
