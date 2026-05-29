---
type: agent
name: Bug Fixer
description: Analyze bug reports and error messages
agentType: bug-fixer
phases: [E, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Isolar a causa raiz antes de propor solução.
- Verificar idempotência: checar se envolve `wa_message_id` duplicado ou reprocessamento.
- Verificar isolamento de tenant: checar vazamento de dados entre tenants (RLS).
- Verificar debounce: rajadas podem causar processamento duplicado ou fora de ordem.
- Corrigir sem introduzir regressões nas regras críticas (política de ticket, bot bloqueado).

## Investigation Flow

1. Identificar o binário afetado (`messaging_gateway`, `worker`, `runtime_api`, `control_plane`).
2. Verificar logs estruturados (crate `observability`) para rastrear o evento.
3. Checar se o problema é na camada `domain_*` (regra pura) ou `infrastructure_*` (I/O).
4. Para bugs de tenant isolation: revisar policies RLS e filtros `tenant_id`.
5. Para bugs de mídia: verificar retry/backoff do Evolution Go (403/500 transitório).

## Available Skills

| Skill | Description |
|-------|-------------|
| [bug-investigation](./../skills/bug-investigation/SKILL.md) | Investigar bugs sistematicamente e análise de causa raiz |
