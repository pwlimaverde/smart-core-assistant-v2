---
type: doc
name: development-workflow
description: Day-to-day engineering processes, branching, and contribution guidelines
category: workflow
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Development Workflow

O projeto usa **gitflow** como padrão de branches. Funcionalidades não triviais seguem o fluxo PREVC (Plan → Review → Execute → Verify → Complete) via dotcontext.

## Branching Strategy

| Branch | Propósito |
|--------|-----------|
| `main` | Releases de produção |
| `dev` | Branch de desenvolvimento ("next release") |
| `feature/<nome>` | Novas funcionalidades (base: `dev`) |
| `bugfix/<nome>` | Correções em desenvolvimento (base: `dev`) |
| `release/<versão>` | Preparação de release (base: `dev`) |
| `hotfix/<nome>` | Correções urgentes em produção (base: `main`) |
| `support/<nome>` | Branches de suporte |

Use `git flow feature start/finish` quando aplicável.

## Commit Convention

- Mensagem em **inglês**
- Sem `Co-Authored-By` nem rodapés de ferramenta de IA
- Formato: `<tipo>: <descrição curta>` (ex.: `feat: add webhook signature validation`)
- Tipos: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`

## Language Convention

- **Código e identificadores**: inglês
- **Comentários no código** (inline, `///`, docstrings): português pt-br com acentuação correta
- **Documentação e comunicação**: português pt-br

## Planning Workflow (PREVC)

Para funcionalidades não triviais:

1. `context({ action: "scaffoldPlan", planName: "<nome>", autoFill: true })`
2. `workflow-init({ name: "<nome>", scale: "MEDIUM" })`
3. Avance: **Plan → Review → Execute → Verify → Complete**
4. Use `workflow-advance` para transitar entre fases

Escalas: `QUICK` (bugfix simples), `SMALL` (feature isolada), `MEDIUM` (feature com decisões de design), `LARGE` (sistema completo).

## Roadmap de Construção

1. **Fundação**: Cargo workspace + `contracts` + schema PostgreSQL com RLS + observabilidade
2. **Messaging Gateway** + Evolution multi-instância
3. **Runtime API** (gRPC unário + Server Streaming) + shell Flutter Windows (`RemoteOnly`) + telas de login/cadastro junto do auth (UI incremental — decisão D8)
4. **Worker** (substitui o Celery da v1) + `ia_engine` Python via gRPC
5. **Regras de domínio** explícitas nos crates `domain_*`
6. **Local Engine** (FFI) + cache de mídia + SQLite + sync
7. Endurecimento + observabilidade + billing/usage
8. **Port para Web** (troca `DataSource` para `RemoteOnly`)

## Related Resources

- [Tooling](tooling.md)
- [Architecture](architecture.md)
