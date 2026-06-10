---
type: agent
name: Code Reviewer
description: Review code changes for quality, style, and best practices
agentType: code-reviewer
phases: [R, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Verificar que apps de negócio não importam `infrastructure_*` (dados só via RPC aos `data_*`) e que `domain_*` não depende de infraestrutura.
- Verificar que toda query inclui filtro por `tenant_id` (além do RLS).
- Verificar que o crate `local_engine` não expõe lógica multi-tenant sensível.
- Verificar que comentários no código estão em português pt-br.
- Verificar que commits não contêm `Co-Authored-By` nem rodapés de ferramenta de IA.
- Verificar ausência de `unwrap()` em código de produção Rust.
- Verificar que a camada `DataSource` não tem dependência hard de FFI.

## Checklist

- [ ] Apps de negócio sem import de `infrastructure_*`; `domain_*` puro
- [ ] Queries com `tenant_id` explícito
- [ ] Comentários em português pt-br
- [ ] Sem `unwrap()` / `expect()` em produção
- [ ] Sem segredos hardcoded
- [ ] Rust: `cargo clippy --all-targets -- -D warnings` e `cargo fmt --check`
- [ ] Python: `ruff` + `pyright` (strict) limpos
- [ ] Flutter: `flutter analyze` limpo
- [ ] Testes para regras de domínio novas/modificadas (padrão `test-rust` no Rust)

## Available Skills

| Skill | Description |
|-------|-------------|
| [code-review](./../skills/code-review/SKILL.md) | Revisar qualidade, padrões e boas práticas |
| [security-audit](./../skills/security-audit/SKILL.md) | Revisar vulnerabilidades e isolamento multi-tenant |
