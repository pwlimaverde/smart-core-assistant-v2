# Skills — biblioteca única

Procedimentos sob demanda para os agentes. **Esta pasta é a fonte única das skills do
projeto: não existem cópias.** `.claude/skills/`, `.agents/skills/` e
`.agents/workflows/` foram removidas de propósito (2026-10-01) — se reaparecerem, foi
um `sync exportContext` sem `skipSkills: true`; apague-as.

> Project: smart-agent-config

## Quem lê daqui

- **MCP dotcontext** — caminho fixo no código (`SKILLS_DIR = '.context/skills'`):
  `skill list`, `skill getContent`, `getForPhase` e as fases PREVC.
- **Seletor de skill** (`.claude/hooks/roteador.py`) — a cada mensagem o Jev escolhe a
  skill e o gancho injeta só o **caminho** dela; o Claude (ou o subagente) lê o arquivo.
  O Claude Code não carrega mais a lista de skills na sessão.
- **Comandos `/slug`** — `.claude/commands/<slug>.md` são stubs gerados por
  `.claude/hooks/gerar_stubs_skills.py` (com `disable-model-invocation: true`) que só
  mandam ler o arquivo daqui. Nunca editar os stubs: editar a skill e rodar o gerador.
- **Antigravity** — lê pelo caminho, a partir deste catálogo (referenciado no `AGENTS.md`).

Detalhes do roteador: `.context/docs/tooling.md` (seção "Roteador de modelo e seletor de skill").

## Catálogo

| Skill | Descrição | Como é acionada |
|-------|-----------|-----------------|
| [`api-design`](./api-design/SKILL.md) | Design contract-first APIs (.proto canônico → FlatBuffers/gRPC) for services and the Flutter client. Use when Designing new RPC methods or services, Defining… | seletor (Jev) ou `$api-design` |
| [`bug-investigation`](./bug-investigation/SKILL.md) | Investigate bugs systematically and perform root cause analysis. Use when Investigating reported bugs, Diagnosing unexpected behavior, or Finding the root ca… | seletor (Jev) ou `$bug-investigation` |
| [`code-review`](./code-review/SKILL.md) | Review code quality, patterns, and best practices. Use when Reviewing code changes for quality, Checking adherence to coding standards, or Identifying potent… | seletor (Jev) ou `$code-review` |
| [`commit-message`](./commit-message/SKILL.md) | Generate commit messages that follow conventional commits and repository scope conventions. Use when Creating git commits after code changes, Writing commit… | seletor (Jev) ou `$commit-message`; `/commit-message` |
| [`documentation`](./documentation/SKILL.md) | Generate and update technical documentation. Use when Documenting new features or APIs, Updating docs for code changes, or Creating README or getting started… | seletor (Jev) ou `$documentation` |
| [`dotcontext-tooling`](./dotcontext-tooling/SKILL.md) | When to use harness actions (init, guide, advance, manage, sensors) across any adapter | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow`](./dotcontext-workflow/SKILL.md) | Operate PREVC workflow through any adapter (MCP, CLI, hooks, Pi) | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow-c`](./dotcontext-workflow-c/SKILL.md) | PREVC phase C (Confirmation) checklist for harness-backed work | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow-e`](./dotcontext-workflow-e/SKILL.md) | PREVC phase E (Execution) checklist for harness-backed work | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow-p`](./dotcontext-workflow-p/SKILL.md) | PREVC phase P (Planning) checklist for harness-backed work | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow-r`](./dotcontext-workflow-r/SKILL.md) | PREVC phase R (Review) checklist for harness-backed work | MCP dotcontext (workflow/harness) ou `$slug` |
| [`dotcontext-workflow-v`](./dotcontext-workflow-v/SKILL.md) | PREVC phase V (Validation) checklist for harness-backed work | MCP dotcontext (workflow/harness) ou `$slug` |
| [`feature-breakdown`](./feature-breakdown/SKILL.md) | Break down features into implementable tasks. Use when Planning new feature implementation, Breaking large tasks into smaller pieces, or Creating implementat… | seletor (Jev) ou `$feature-breakdown`; `/feature-breakdown` |
| [`plan-restructuring`](./plan-restructuring/SKILL.md) | Etapa final de qualquer planejamento. Normaliza a origem do plano (conversa, doc_dev ou .context/plans) em um diretório próprio dentro de .context/plans/{fea… | seletor (Jev) ou `$plan-restructuring`; `/plan-restructuring` |
| [`pr-review`](./pr-review/SKILL.md) | Review pull requests against team standards and best practices. Use when Reviewing a pull request before merge, Providing feedback on proposed changes, or Va… | seletor (Jev) ou `$pr-review`; `/pr-review` |
| [`prevc-confirmation`](./prevc-confirmation/SKILL.md) | Fase C (Confirmation) do workflow PREVC - Entregar e documentar. Ativar após conclusão da fase V (Validation), com testes passando e PR mergeado. Inclui gate… | fase PREVC ativa (gancho) ou MCP; `/prevc-confirmation` |
| [`prevc-execution`](./prevc-execution/SKILL.md) | Fase E (Execution) do workflow PREVC - Construir o que foi planejado. Ativar após conclusão da fase R (Review), quando design e arquitetura estão aprovados. | fase PREVC ativa (gancho) ou MCP; `/prevc-execution` |
| [`prevc-final-review`](./prevc-final-review/SKILL.md) | Auditoria final pós-implementação (subagente Opus) que compara o que foi implementado contra o plano aprovado, corrige automaticamente os desvios (sem bloque… | fase PREVC ativa (gancho) ou MCP; `/prevc-final-review` |
| [`prevc-planning`](./prevc-planning/SKILL.md) | Fase P (Planning) do workflow PREVC - Definir o que construir. Ativar quando uma nova feature é solicitada, um bug complexo precisa ser investigado, ou uma r… | fase PREVC ativa (gancho) ou MCP; `/prevc-planning` |
| [`prevc-review`](./prevc-review/SKILL.md) | Fase R (Review) do workflow PREVC - Validar approach e arquitetura. Ativar após conclusão da fase P (Planning), quando PRD e spec técnica estão prontos. | fase PREVC ativa (gancho) ou MCP; `/prevc-review` |
| [`prevc-validation`](./prevc-validation/SKILL.md) | Fase V (Validation) do workflow PREVC - Verificar que funciona. Ativar após conclusão da fase E (Execution), quando o código está implementado e pronto para… | fase PREVC ativa (gancho) ou MCP; `/prevc-validation` |
| [`refactoring`](./refactoring/SKILL.md) | Refactor code safely with a step-by-step approach. Use when Improving code structure without changing behavior, Reducing code duplication, or Simplifying com… | seletor (Jev) ou `$refactoring` |
| [`security-audit`](./security-audit/SKILL.md) | Review code and infrastructure for security weaknesses. Use when Reviewing code for security vulnerabilities, Assessing authentication/authorization, or Chec… | seletor (Jev) ou `$security-audit` |
| [`test-generation`](./test-generation/SKILL.md) | Generate comprehensive test cases for code. Use when Writing tests for new functionality, Adding tests for bug fixes (regression tests), or Improving test co… | seletor (Jev) ou `$test-generation` |
| [`test-rust`](./test-rust/SKILL.md) | Guia profissional para escrever testes em Rust (unitários, integração, doctests, parametrizados, property-based, snapshot e assíncronos com Tokio) seguindo a… | seletor (Jev) ou `$test-rust` |

`$slug` no início da mensagem força a skill; `/slug` existe para as skills de uso manual.
As `prevc-*` e `dotcontext-*` não passam pelo Jev; as `prevc-*` o gancho escolhe pela fase PREVC
ativa em `.context/workflow/status.yaml`.

## Creating Custom Skills

Create a new skill by adding a directory with a `SKILL.md` file (frontmatter `name` and a one-line `description`; the selector sends the description to Jev). If it is a manual skill, add the slug to `skills_manuais` in `.claude/roteador.config.json` and run `py -3 .claude/hooks/gerar_stubs_skills.py`:

```
.context/skills/
└── my-skill/
    ├── SKILL.md          # Required: source skill definition
    ├── scripts/          # Optional: deterministic helpers
    ├── references/       # Optional: load-on-demand details
    └── assets/           # Optional: output resources
```

### Skill Anatomy

```md
The source file under `.context/skills/` keeps internal scaffold metadata so dotcontext can track fill status.
Skills are no longer exported to AI-tool directories; the selector and the MCP need at least:

---
name: my-skill
description: Describe what the skill does and the concrete triggers for when to use it
---

## Workflow
1. Step one
2. Step two

## Examples
```
[Short example]
```

## Quality Bar
- List the checks and constraints that keep the skill reliable

## Resource Strategy
- Explain when to add `scripts/`, `references/`, or `assets/`
```

Keep activation language in the description frontmatter, keep the body concise, and avoid extra docs such as `README.md` or `CHANGELOG.md` inside the skill folder.

## PREVC Phase Mapping

| Phase | Name | Skills |
|-------|------|--------|
| P | Planning | feature-breakdown, documentation, api-design |
| R | Review | pr-review, code-review, api-design, security-audit |
| E | Execution | commit-message, test-generation, refactoring, bug-investigation |
| V | Validation | pr-review, code-review, test-generation, security-audit |
| C | Confirmation | commit-message, documentation |
