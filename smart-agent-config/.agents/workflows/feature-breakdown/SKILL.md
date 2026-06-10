---
name: feature-breakdown
description: Break down features into implementable tasks. Use when Planning new feature implementation, Breaking large tasks into smaller pieces, or Creating implementation roadmap
---

## Workflow

1. Entenda o requisito completo e confirme em qual fase do roadmap (`doc_dev/planejamento/02-fases-desenvolvimento.md`) a feature se encaixa
2. Decomponha seguindo as camadas do projeto: contrato (`.proto` em `contracts`) → handler no `data_*` (se toca dados) → caso de uso em `application` → app de negócio → tela Flutter que valida (decisão D8)
3. Cada tarefa deve ser independente e testável, com critério de aceite explícito
4. Mapeie dependências entre tarefas e o que pode andar em paralelo
5. Sinalize riscos e decisões em aberto cedo
6. Para features não triviais, finalize com a skill `plan-restructuring` (plano canônico em `.context/plans/` + PREVC)

## Examples

**Decomposição (padrão do projeto):**
```
## Feature: autenticação de usuários

### Tarefa 1: contrato
- auth.proto em crates/contracts (LoginRequest/Response, RefreshRequest/Response)
- Aceite: stubs gerados no build; round-trip de codec testado

### Tarefa 2: handlers de dados
- handler_verify_credentials no data_postgres (Argon2 via infrastructure_postgres)
- tokens de refresh no data_redis (rotação + blocklist)
- Aceite: testes de integração com banco real passando

### Tarefa 3: caso de uso + API
- AuthService em crates/application; endpoint no runtime_api com interceptor JWT
- Aceite: login/refresh/logout ponta-a-ponta via RPC

### Tarefa 4: tela que valida (D8)
- Telas de login/cadastro no flutter_windows (RemoteOnly, core_ui)
- Aceite: fluxo completo manual + widget tests

### Dependências: 2 e 3 dependem de 1; 4 depende de 3.
```

## Quality Bar

- Tarefa cabível em um dia de trabalho; critério de aceite verificável (teste ou DoD)
- Respeitar as fronteiras: app de negócio nunca importa `infrastructure_*`; banco só via handler no `data_postgres`
- Toda feature de backend inclui a tela que a valida no mesmo ciclo (D8)
- Riscos e decisões em aberto documentados no plano, não descobertos na execução

## Resource Strategy

- Add `scripts/` only when the task is fragile, repetitive, or benefits from deterministic execution.
- Add `references/` only when details are too large or too variant-specific to keep in `SKILL.md`.
- Add `assets/` only for files that will be consumed in the final output.
- Keep extra docs out of the skill folder; prefer `SKILL.md` plus only the resources that materially help.
