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

## Ambientes na VPS (dev e prod) — regra compartilhada

Desde 2026-11-22 a VPS Hostinger (`srv1321059`) roda **dois ambientes v2**, ambos
implantados por bundle (`/opt/smartcore/<env>/releases/current`), nunca da
workspace do runner. Detalhes: `doc_dev/runbooks/RUNBOOK_DEPLOY.md`.

| | dev | prod |
|---|---|---|
| Gatilho | push/merge na `dev` → `deploy-dev.yml` | tag `vX.Y.Z` (só o dono) → `deploy-prod.yml` + **aprovação** no environment `prod` |
| Versão | `vX.Y.Z-beta.N` automática (base no arquivo `VERSION`) | `vX.Y.Z` = mesmo digest da beta testada |
| Compose | `docker/stack/docker-compose.base.yml` + `dev.override.yml` + `dev.vars` | idem com `prod.override.yml` + `prod.vars` |
| Env | secret `ENV_FILE_B64` (env `dev`) → `/opt/smartcore/dev/env/dev.env` | secret `ENV_FILE_B64` (env `prod`) → `/opt/smartcore/prod/env/prod.env` |
| Rollback | automático se o smoke falhar | idem + `gh workflow run rollback-prod.yml --ref main -f versao=vX.Y.Z` (aprovação) |
| Domínio | `dev.smartcoreassistant.com.br` | `smartcoreassistant.com.br` |

- **Fonte do ambiente é o secret do GitHub Environment**; o arquivo no servidor é
  cópia materializada pelo deploy (dono `gh-runner`, modo 600). **Nunca** editar
  `<env>.env` nem `docker/*/.env` à mão — rotação: `RUNBOOK_DEPLOY.md` §9.
- O deploy falha se faltar chave de `infra/deploy/required-keys.<env>`.
- RC (`vX.Y.Z-rc.N` → `release-candidate.yml`): build e bundle de prod **sem
  deploy**; obrigatório para release com migração.
- Hotfix: `hotfix/*` a partir da `main` → PR → tag `vX.Y.Z` → o deploy abre PR
  `main → dev` (backport, merge commit).
- Infra compartilhada (borda, observabilidade, Evolution) só muda por
  `deploy-infra.yml` (push na `main` ou dispatch), com aprovação de prod.
- Memória (decisão D1): tetos por ambiente nos `.vars`; `oom_score_adj` dev 900,
  observabilidade 300, prod 0 — sob pressão o kernel mata a dev primeiro.
- Webhook do WhatsApp: dev usa `http://provider_edge:8088/dev` (cutover de
  2026-11-25, `dev.vars`); prod ainda usa `http://172.17.0.1:9211` até o cutover
  dela (a `evolution_net` é compartilhada). ADR
  `doc_dev/arquitetura/adr-intermediario-webhooks-provedores.md`.
- O checkout `/opt/smartcore/ops/smart-core-assistant-v2` é espelho da `dev`
  (`git pull --ff-only origin dev`). Não subir compose de lá.
- Marcadores de deploy: `/opt/smartcore/{dev,prod,infra}/deploys.log` → painel
  **Deploys** no Grafana.
- Mesmo arquivo de regras para a sessão local e a sessão do VPS: mudanças de ambiente entram aqui.
