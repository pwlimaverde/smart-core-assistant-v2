# Project Rules and Guidelines

> Auto-generated from .context/docs on 2026-09-06T13:21:01.086Z

## README

# Documentation Index

Welcome to the repository knowledge base. Start with the project overview, then dive into specific guides as needed.

## Core Guides
- [Project Overview](./project-overview.md)
- [Architecture Notes](./architecture.md)
- [Development Workflow](./development-workflow.md)
- [Testing Strategy](./testing-strategy.md)
- [Glossary & Domain Concepts](./glossary.md)
- [Data Flow & Integrations](./data-flow.md)
- [Security & Compliance Notes](./security.md)
- [Tooling & Productivity Guide](./tooling.md)

## ⚠️ dotcontext 1.1.1 — não exportar contexto sem reverter os agents depois

`sync exportContext` (e `exportAgents`) **destrói a fonte** `.context/agents/*.md`:
copia o conteúdo para `.claude/agents/` corretamente e, em seguida, sobrescreve o
próprio arquivo de origem com um stub `AUTO-GENERATED REFERENCE FILE` que aponta
para si mesmo. O derivado fica bom; o canônico se perde.

Vale para **`agentMode: "markdown"` também** — não só para `"symlink"`, como era
até a 1.0.x. Confirmado em 2026-09-06: 22 arquivos, 1170 linhas, restaurados via
git.

- **Se só for executar planos**, não há motivo para exportar — o MCP lê o
  `.context/` direto.
- **Se precisar exportar**, sempre com `preset` explícito (`claude`,
  `antigravity`; sem preset ele espalha para .cursor/.windsurf/.cline/…),
  **`skipSkills: true`** (as skills têm fonte única em `.context/skills/` e não são
  mais exportadas — sem isso o export recria `.claude/skills/` e desfaz o seletor) e,
  logo depois, `git checkout -- .context/agents/`.
- **Conferir**: `.context/agents/backend-specialist.md` tem ~34 linhas de
  conteúdo real; se aparecer `AUTO-GENERATED`, a fonte foi corrompida.

`init` tem o mesmo risco: ele recria docs e agents como templates vazios, mesmo
com `skipContentGeneration: true`.

## Repository Snapshot
- `doc_dev/` — planejamento canônico do projeto (arquitetura, modelagem de dados, padrões por linguagem, fases)
- `.context/` — docs, agentes, skills e workflow coordenados pelo dotcontext (esta pasta)
- Skills: **biblioteca única** em `.context/skills/` (catálogo no `README.md` de lá); um gancho com o Jev escolhe a skill de cada mensagem e, no modo `on`, o modelo/especialista — ver `tooling.md` ("Roteador de modelo e seletor de skill")
- Stacks: **Rust** (backend), **Python** (`ia_engine`), **Flutter/Dart** (clients)

## Document Map
| Guide | File | Primary Inputs |
| --- | --- | --- |
| Project Overview | `project-overview.md` | Roadmap, README, stakeholder notes |
| Architecture Notes | `architecture.md` | ADRs, service boundaries, dependency graphs |
| Development Workflow | `development-workflow.md` | Branching rules, CI config, contributing guide |
| Testing Strategy | `testing-strategy.md` | Test configs, CI gates, known flaky suites |
| Glossary & Domain Concepts | `glossary.md` | Business terminology, user personas, domain rules |
| Data Flow & Integrations | `data-flow.md` | System diagrams, integration specs, queue topics |
| Security & Compliance Notes | `security.md` | Auth model, secrets management, compliance requirements |
| Tooling & Productivity Guide | `tooling.md` | CLI scripts, IDE configs, automation workflows |

## Ambiente da dev (VPS) — regra compartilhada

- Fonte do ambiente: `/opt/smartcore/dev/env/dev.env` (dono `gh-runner`, modo 600). **Nunca** editar `docker/*/.env` à mão.
- O deploy da dev copia esse arquivo para `docker/dev/.env` no workspace do runner e **falha** se faltar uma chave obrigatória (`POSTGRES_*`, `REDIS_PASSWORD`, `MINIO_ROOT_PASSWORD`, `EVOLUTION_GLOBAL_API_KEY`).
- O checkout `/opt/smartcore/ops/smart-core-assistant-v2` é espelho do `dev`: manter com `git pull --ff-only origin dev`. Não subir o compose de lá com um `.env` que não veio do `dev.env`.
- Recriar serviços da dev à mão só depois de conferir `REDIS_PASSWORD` no `.env` usado (sem exibir o valor). Se a dúvida for de configuração, o caminho é o deploy.
- Mesmo arquivo de regras para a sessão local e a sessão do VPS: mudanças de ambiente entram aqui.

