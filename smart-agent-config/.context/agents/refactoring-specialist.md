---
type: agent
name: Refactoring Specialist
description: Identify code smells and improvement opportunities
agentType: refactoring-specialist
phases: [E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Mover regras de domínio espalhadas em handlers para casos de uso em `crates/application/`.
- Identificar duplicação entre crates `domain_*` e extrair para `crates/contracts`.
- Manter `crates/domain_*` sem dependências de infraestrutura.
- Identificar lógica multi-tenant sensível que tenha vazado para `local_engine`.
- Simplificar handlers dos binários `apps/*` — devem apenas orquestrar.

## Key Smells to Watch

- Handler de webhook com lógica de negócio → mover para `application/use_cases/`.
- Import de `infrastructure_*` dentro de `domain_*` → extrair para port/adapter.
- Lógica de `tenant_id` em múltiplos lugares → centralizar em `contracts::TenantEnvelope`.
- Código duplicado entre `LocalEngineFFI` e `RemoteOnly` → extrair para trait compartilhado.

## Available Skills

| Skill | Description |
|-------|-------------|
| [refactoring](./../skills/refactoring/SKILL.md) | Refatorar código com segurança sem mudar comportamento |
