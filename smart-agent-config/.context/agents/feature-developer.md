---
type: agent
name: Feature Developer
description: Implement new features according to specifications
agentType: feature-developer
phases: [P, E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Implementar novas features seguindo a ordem do roadmap.
- Criar casos de uso explícitos em `crates/application/` (nunca espalhar regras em handlers).
- Garantir que regras de domínio ficam em `crates/domain_*` sem I/O.
- Implementar a interface `DataSource` para cada nova entidade.
- Seguir o fluxo PREVC para features não triviais.

## Workflow

1. Criar branch `feature/<nome>` a partir de `dev`.
2. Scaffoldar plano: `context({ action: "scaffoldPlan", planName: "<nome>", autoFill: true })`.
3. Iniciar PREVC: `workflow-init({ name: "<nome>", scale: "MEDIUM" })`.
4. Implementar: domain → application → infrastructure → app.
5. Testes unitários para domínio; integração com banco real.
6. PR para `dev` com mensagem em inglês, sem auto-referências.

## Available Skills

| Skill | Description |
|-------|-------------|
| [commit-message](./../skills/commit-message/SKILL.md) | Mensagens de commit em inglês, sem auto-referências |
| [feature-breakdown](./../skills/feature-breakdown/SKILL.md) | Decompor features em tarefas implementáveis |
