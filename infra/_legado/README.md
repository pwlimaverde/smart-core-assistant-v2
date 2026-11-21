# infra/_legado — scripts da era do ambiente local

Arquivados em 2026-11-21 pela Fase R4 do plano `servidor-reestruturacao-dev-prod`
(decisão R-D5: arquivar por um ciclo de release, depois apagar).

**Não há mais ambiente local.** Dev e prod rodam só na VPS (`srv1321059`):

| Antes (aqui) | Agora |
|---|---|
| `tunnel.ps1` / `tunnel.sh` (túnel SSH para Postgres/Redis) | Não existe: o banco da dev não publica porta no host. Testes de integração rodam na CI |
| `test-local.ps1`, `test-quick.ps1`, `test-flutter.ps1` | CI (`.github/workflows/ci.yml`); portão dos agentes: `node infra/ci-verde.mjs` |
| `clean-target.ps1` | Não se compila na VPS; na máquina do dev, `cargo clean` |
| `create-superuser.ps1`, `delete-superuser.ps1` | Pendente: `workflow_dispatch` que roda o binário de admin dentro do container (ver `doc_dev/runbooks/RUNBOOK_DEPLOY.md`) |
| `backup-envs.ps1` | Segredos vivem no secret `ENV_FILE_B64` de cada GitHub Environment (+ cofre do dono) |

Os scripts continuam aqui só como referência; eles apontam para portas e
túneis que não existem mais e **não funcionam**.
