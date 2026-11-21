---
type: plan
name: "Reestruturação dev/prod — dois ambientes, deploy por merge e por tag"
planSlug: servidor-reestruturacao-dev-prod
description: "Elimina o ambiente local e fixa dois ambientes na VPS: dev (merge na branch dev → deploy-dev.yml) e prod (tag vX.Y.Z criada por pessoa num commit da main → deploy-prod.yml com aprovação). Compose base único + overlay por ambiente, bundle de release por ambiente em /opt/smartcore/<env>/releases/<id> (tira dev e prod da workspace compartilhada do runner), segredos como secret de GitHub Environment, imagens por versão exata e rollback por troca de bundle. Infra compartilhada (borda, observabilidade, Evolution, releases) só muda pelo fluxo de prod."
summary: "Corrige sete defeitos de processo levantados no servidor em 2026-11-21 — o mais grave: deploy-prod.yml usa environment 'production', que não existe, então a primeira tag iria para produção sem revisor. Fatia de pipeline e topologia do producao-go-live, que continua dono do isolamento de rede (C1–C3), backup externo e das decisões D1/D3/D7/D10."
status: filled
progress: 0
generated: "2026-11-21"
scaffoldVersion: "2.0.0"
agents:
  - type: "devops-specialist"
    role: "Workflows, compose base + overlay, bundle e deploy.sh, rollback, deploy-infra"
  - type: "architect-specialist"
    role: "Fronteira com o producao-go-live, topologia de ambientes, critérios de corte"
  - type: "security-auditor"
    role: "Rulesets, environments, materialização de segredos sem vazamento"
  - type: "backend-specialist"
    role: "Remoção do túnel do test_support; política expand/contract de migrações"
  - type: "documentation-writer"
    role: "RUNBOOK_DEPLOY, development-workflow, architecture, CLAUDE.md"
phases:
  - id: "phase-p"
    name: "Planning — levantamento e plano"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — decisões R-D1..R-D6 e fronteira com o go-live"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution — R1 governança, R2 compose, R3 bundle/segredos, R4 fim do local, R5 workflows"
    prevc: "E"
    agent: "devops-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation — R6 RC, primeira tag, ensaio de rollback e hotfix"
    prevc: "V"
    agent: "devops-specialist"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation — R7 documentação e limpeza do legado"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
lastUpdated: "2026-11-21T13:42:12.174Z"
---

# Reestruturação dev/prod — dois ambientes, deploy por merge e por tag

> Levantamento feito no próprio servidor, somente leitura. Nada foi alterado
> no servidor, no GitHub ou nos workflows.
> **Ação imediata recomendada (uma linha):** `deploy-prod.yml` →
> `environment: prod`. Hoje está `production`, que não existe; a primeira tag
> criaria o ambiente sem revisor.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_servidor-reestruturacao-dev-prod.md](./servidor-reestruturacao-dev-prod/plano_completo_servidor-reestruturacao-dev-prod.md)
- **Documentação auxiliar e estado real**: [info_aux_servidor-reestruturacao-dev-prod.md](./servidor-reestruturacao-dev-prod/info_aux_servidor-reestruturacao-dev-prod.md)
- Relacionados: [producao-go-live.md](./producao-go-live.md) (depende deste para a Fase 9), [n12-cutover-producao.md](./n12-cutover-producao.md)

## Defeitos que o plano corrige
| # | Defeito |
|---|---|
| 1 | `environment: production` inexistente no deploy de prod (sem revisor) |
| 2 | Tag sai da `dev`; PR `dev → main` aberto depois do deploy; `main` 797 commits atrás |
| 3 | `main` sem proteção; tags `v*` sem ruleset |
| 4 | Prod em `:latest` — sem rollback por versão |
| 5 | Dev e prod executam compose e binds da mesma workspace do runner |
| 6 | Deploy da dev troca borda, Evolution e observabilidade |
| 7 | Dois composes de ~600 linhas, ~90% iguais |

## Fases
| # | Fase | Esforço |
|---|---|---|
| R0 | Levantamento (feito) | — |
| R1 | Governança Git: rulesets, `environment: prod`, gate de origem, fim do `pr-to-main.yml` | 0,5 d |
| R2 | Compose base `docker/stack/` + overlays dev/prod, prova de equivalência | 2 d |
| R3 | Bundle por ambiente, `infra/deploy/deploy.sh`, `ENV_FILE_B64` por environment | 2 d |
| R4 | Fim do ambiente local (túnel, `.ps1`, portas de banco, docs) | 1 d |
| R5 | `deploy-dev`, `deploy-prod`, `deploy-infra`, `rollback-prod` | 2 d |
| R6 | RC, primeira tag, ensaio de rollback e hotfix (depende de go-live C1–C3, F5) | 1 d + 48 h |
| R7 | Runbook e docs | 0,5 d |

## Decisões do dono
R-D1 infra compartilhada só pelo fluxo de prod · R-D2 secret de environment
como fonte do `.env` · R-D3 merge commit entre `dev` e `main` · R-D4 RC
obrigatório com migração · R-D5 arquivar scripts locais · R-D6 migrações
expand/contract. Bloqueante externo: **D1 do go-live (memória da VPS)**.

## Definition of Done
- [ ] Nenhum túnel, script ou porta de ambiente local; docs atualizadas.
- [ ] Push na `dev` implanta só a stack dev; borda/observabilidade/Evolution intocadas.
- [ ] Tag fora da `main` recusada; tag na `main` pede aprovação e implanta `X.Y.Z` exato.
- [ ] Dev e prod rodam de `/opt/smartcore/<env>/releases/current`, não da workspace.
- [ ] `.env` dos dois ambientes vindo de secret de environment, validado por chave.
- [ ] Rollback de prod por `rollback-prod.yml` medido (< 5 min) e hotfix ensaiado com backport.
- [ ] Marcadores de deploy dos dois ambientes visíveis no Grafana.
- [ ] `RUNBOOK_DEPLOY.md` publicado; `CLAUDE.md` e docs sem regra antiga.

## Estado do workflow PREVC
`workflow-init` **não** foi executado: o `prevc.json` está ligado ao plano
`windows-releases-v01-beta` (fase C em andamento) e seria sobrescrito. Rodar
`workflow-init({ name: "servidor-reestruturacao-dev-prod", scale: "MEDIUM" })` +
`plan({ action: "link" })` depois de fechar ou arquivar aquele workflow.

## Execution History

> Last updated: 2026-11-21T13:42:12.174Z | Progress: 0%
