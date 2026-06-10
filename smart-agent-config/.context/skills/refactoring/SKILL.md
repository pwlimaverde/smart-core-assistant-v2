---
type: skill
name: Refactoring
description: Refactor code safely with a step-by-step approach. Use when Improving code structure without changing behavior, Reducing code duplication, or Simplifying complex logic
skillSlug: refactoring
phases: [E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---
## Workflow

1. Garanta cobertura de testes antes (no Rust, rode `cargo test --workspace`; sem rede de proteção, escreva os testes primeiro)
2. Identifique o alvo específico: regra em handler → caso de uso; duplicação entre crates → `contracts`/helper; lógica multi-tenant vazada p/ `local_engine` → de volta ao servidor
3. Um tipo de mudança por vez; commits pequenos e frequentes
4. Rode os testes (e `clippy`/`ruff`/`flutter analyze`) após cada passo
5. Verifique que nenhum comportamento mudou — teste quebrado = comportamento alterado

## Examples

**Extrair regra de handler para caso de uso (alvo clássico do projeto):**
```rust
// Antes: regra de negócio dentro do handler do data_postgres
async fn handler_receive_message(env: Envelope) -> Result<Envelope, AppError> {
    // ... 40 linhas decidindo política de ticket inline
}

// Depois: handler orquestra; regra vive em crates/application
async fn handler_receive_message(env: Envelope) -> Result<Envelope, AppError> {
    let decisao = application::decidir_politica_ticket(&ctx)?;
    repo.aplicar_decisao(&decisao).await
}
```

## Quality Bar

- Nunca refatorar sem testes; passos pequenos com commit a cada um
- Comportamento idêntico: mesma resposta, mesmos eventos publicados, mesma auditoria
- Refatoração não mistura com feature/fix no mesmo commit
- Fronteiras preservadas: nada de mover regra para `infrastructure_*` ou criar import de infra em app de negócio
- Rust: sem `unwrap()` novo; tratamento de erro continua via `?`/`AppError`

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
