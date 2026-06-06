---
type: skill
name: Commit Message
description: Generate commit messages that follow conventional commits and repository scope conventions. Use when Creating git commits after code changes, Writing commit messages for staged changes, or Following conventional commit format for the project
skillSlug: commit-message
phases: [E, C]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---
## Workflow

1. Review the staged changes using `git diff --staged`
2. Identify the type of change (feat, fix, docs, style, refactor, test, chore)
3. Determine the scope (component, module, or area affected)
4. Write a concise subject line (50 chars max, imperative mood)
5. Add body if needed to explain "why" not "what"
6. Reference issue numbers if applicable

## Examples

**Feature commit:**
```
feat(worker): add ticket policy for contact reuse

Implement TicketPolicy use case that reuses active tickets
(FILA/EM_ATENDIMENTO/PENDENCIA) instead of creating new ones.
```

**Bug fix commit:**
```
fix(gateway): validate evolution webhook signature before processing

Previously accepted any webhook payload without signature check.
```

## Quality Bar

- Use imperative mood: "add" not "added" or "adds"
- Keep subject line under 50 characters
- Use body to explain why, not what
- One logical change per commit

## Project-Specific Rules

- Mensagem sempre em **inglês**
- **Nunca** incluir `Co-Authored-By: Claude` nem `🤖 Generated with Claude Code`
- Branch de origem segue gitflow: `feature/`, `bugfix/`, `hotfix/`, etc.
