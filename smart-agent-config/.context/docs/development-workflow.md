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

Dois ambientes, ambos na VPS `srv1321059` — **não há ambiente local**
(plano `servidor-reestruturacao-dev-prod`). A máquina do desenvolvedor edita,
faz push e lê logs no Grafana; build, testes e deploy são da CI.

| Branch / tag | Propósito | O que dispara |
|---|---|---|
| `feature/<nome>`, `bugfix/<nome>` | Trabalho do dia a dia (base: `dev`) | CI (`ci.yml`) |
| `dev` | Integração contínua — o que está na dev | `deploy-dev.yml` → `vX.Y.Z-beta.N` em `/opt/smartcore/dev` |
| `vX.Y.Z-beta.N` (tag) | Criada pelo deploy da dev **depois** do smoke test: "rodou e passou na dev" | nada (só marca o commit) |
| `vX.Y.Z` (tag) | Release — criada **por pessoa** (só o dono, ruleset) num commit com beta | `deploy-prod.yml` (aprovação no environment `prod`) |
| `main` | **Ponteiro da última release**: avança sozinha por fast-forward depois do deploy de prod | `deploy-infra.yml` se a release mudou borda/observabilidade/Evolution |
| `hotfix/<nome>` | Correção urgente (base: `main`) → PR para `main` → tag `vX.Y.(Z+1)` | PR `main → dev` (backport) aberto pelo `deploy-prod` |

Regras (rulesets do GitHub):
- `main`: sem push direto (só PR, merge commit) e sem force-push/exclusão; quem avança
  por fast-forward é a deploy key do runner.
- `dev`: sem force-push nem exclusão. Correção em produção de bug da dev = `git revert`.
- Tags `vX.Y.Z`: só o dono cria; nenhuma tag `v*` é movida ou apagada (versão publicada é
  imutável — correção é nova versão PATCH).
- `release/*` não existe mais: a beta na dev cumpre o papel de candidata.

O arquivo `VERSION` (raiz) define o `X.Y.Z` das betas. Depois de lançar `vX.Y.Z`,
suba o `VERSION` (MINOR/MAJOR é decisão humana; sem isso as betas seguem no próximo PATCH).

Passo a passo de release, hotfix e rollback: `doc_dev/runbooks/RUNBOOK_DEPLOY.md`.

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

1. **Fundação** ✅: Cargo workspace + crates de base (`contracts`/`transport`/`error_core`/`observability`) + serviços `data_*` (Postgres com RLS, Redis, storage R2)
2. **CI/CD + DevOps** (próxima — F-devops) → depois **auth** (`user-auth-module`) e painel admin
3. **Messaging Gateway** + Evolution multi-instância
4. **Runtime API** (contrato unificado D7) + shell Flutter Windows (`RemoteOnly`) + telas de login/cadastro junto do auth (UI incremental — decisão D8)
5. **Worker** (substitui o Celery da v1) + `ia_engine` Python via gRPC
6. **Regras de domínio** explícitas nos crates `domain_*` (extraídas da `application` quando justificar)
7. **Local Engine** (FFI) + cache de mídia + SQLite + sync
8. Endurecimento + observabilidade + billing/usage
9. **Port para Web** (troca `DataSource` para `RemoteOnly`)

## Ambientes na VPS — regra compartilhada

- **Fonte dos segredos**: secret `ENV_FILE_B64` do GitHub Environment (`dev` / `prod`).
  O arquivo `/opt/smartcore/<env>/env/<env>.env` é **cópia materializada** pelo deploy
  (dono `gh-runner`, 600) e é sobrescrito a cada deploy — **nunca** editar à mão.
  Rotação: `base64 -w0 <arquivo> | gh secret set ENV_FILE_B64 --env <env>` e redeploy
  (ver RUNBOOK_DEPLOY). Chaves obrigatórias: `infra/deploy/required-keys.<env>`.
- **O que roda**: `/opt/smartcore/<env>/releases/current` → bundle da versão
  (`docker/stack/*` + `backup/` + `init-scripts/` + `images.env`). Nada roda da
  workspace do runner nem deste checkout.
- **Infra compartilhada** (borda, observabilidade, Evolution) muda só por
  `deploy-infra.yml`, com aprovação do environment `prod`. O deploy da dev não a toca.
- O checkout `/opt/smartcore/ops/smart-core-assistant-v2` é espelho do `dev`, só para
  leitura (`git pull --ff-only origin dev`). **Nunca** subir compose a partir dele.
- Não compilar Rust nem Flutter na VPS (2 vCPU / 7,8 GB): build é da CI, que publica no GHCR.
- Mexer à mão num serviço da dev só em incidente, e sempre com o compose do bundle:
  `cd /opt/smartcore/dev/releases/current` e os mesmos `-f`/`--env-file` do `infra/deploy/lib.sh`.
- Mesmo arquivo de regras para todas as sessões: mudanças de ambiente entram aqui.

## Related Resources

- [Tooling](tooling.md)
- [Architecture](architecture.md)
- [RUNBOOK_DEPLOY](../../doc_dev/runbooks/RUNBOOK_DEPLOY.md)
