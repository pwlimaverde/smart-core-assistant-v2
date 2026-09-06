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
  `antigravity`; sem preset ele espalha para .cursor/.windsurf/.cline/…) e, logo
  depois, `git checkout -- .context/agents/`.
- **Conferir**: `.context/agents/backend-specialist.md` tem ~34 linhas de
  conteúdo real; se aparecer `AUTO-GENERATED`, a fonte foi corrompida.

`init` tem o mesmo risco: ele recria docs e agents como templates vazios, mesmo
com `skipContentGeneration: true`.

## Repository Snapshot
- `doc_dev/` — planejamento canônico do projeto (arquitetura, modelagem de dados, padrões por linguagem, fases)
- `.context/` — docs, agentes, skills e workflow coordenados pelo dotcontext (esta pasta)
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
