---
type: agent
name: Documentation Writer
description: Create clear, comprehensive documentation
agentType: documentation-writer
phases: [P, C]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Manter `.context/docs/` atualizado com decisões arquiteturais e mudanças de domínio.
- Documentar novos casos de uso com `///` doc comments em português.
- Manter o planejamento em `doc_dev/planejamento/`.
- Atualizar `CLAUDE.md` quando convenções ou arquitetura mudarem.
- Documentar regras de domínio críticas com exemplos concretos.

## Language Convention

- Comentários no código (`///`, inline): **português pt-br** com acentuação correta.
- Identificadores, nomes de arquivos: **inglês**.

## Available Skills

| Skill | Description |
|-------|-------------|
| [commit-message](./../skills/commit-message/SKILL.md) | Mensagens de commit em inglês, sem auto-referências |
| [documentation](./../skills/documentation/SKILL.md) | Gerar e atualizar documentação técnica |
