# Final Review — cicd-devops
Data: 2026-06-07 · Modelo: Opus · Diff: main...HEAD (escopo cicd-devops)

## Veredito: CORRIGIDO

> **Nota de completude:** as fases E (provisionamento do servidor) e V (deploy
> end-to-end, smoke tests, rollback) são majoritariamente operações no servidor
> real (Hostinger `76.13.229.210`) e **não são verificáveis por git**. Esta
> auditoria validou e corrigiu os **artefatos** que suportam essas fases
> (workflows, server-setup, systemd, observabilidade, scripts e documentação). O
> dono do projeto confirmou a execução e autorizou o arquivamento.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---|---|---|
| R.1 `ci.yml`: `SQLX_OFFLINE=true` nos steps necessários | ✅ | Presente em clippy, test e sqlx prepare --check |
| R.1 `ci.yml`: `cargo sqlx prepare --workspace --check` | ✅ | Step dedicado, com comentário explicativo |
| R.1 `deploy-dev.yml`: lista de 7 binários | ✅ | `data_postgres data_redis data_storage runtime_api control_plane messaging_gateway worker` |
| R.1 `deploy-prod.yml`: rollback via `PREV_RELEASE`/readlink | ✅ | `readlink current` → `GITHUB_ENV`; rollback usa `${{ env.PREV_RELEASE }}` + `rm -rf` da release falha |
| R.1 `deploy-prod.yml`: Flutter `if: needs.build-and-deploy.result == 'success'` | ✅ | Conforme |
| R.1 `pr-to-main.yml`: `pull-requests: write` | ✅ | `permissions: pull-requests: write` + `contents: read` |
| R.2 server-setup: instala docker/postgresql-client | ⚠️ | Instala `postgresql-client`, mas NÃO instala `docker.io` (assume Docker já presente da stack de dados). Ver Pendências |
| R.2 server-setup: journald (SystemMaxUse/MaxRetentionSec) | ✅ | `SystemMaxUse=500M`, `MaxRetentionSec=7day` |
| R.2 server-setup: Caddyfile h2c gRPC | ✅ | `reverse_proxy h2c://localhost:8080/8090`, `versions h2c` |
| R.2 server-setup: sudoers gh-runner (inclui journalctl) | ✅ | restart/start/stop/is-active/journalctl restritos a `smartcore-*` |
| R.2 server-setup: gh-runner no grupo docker | ✅ | `usermod -aG docker gh-runner` |
| R.3 14 services + 2 targets | ✅ | 7 por ambiente (dev/prod) + 2 targets, todos presentes |
| R.3 runtime_api depende de todos | ✅ | `After=` lista os 6 demais; `Requires=` postgres+redis |
| R.3 EnvironmentFile por ambiente | ✅ | dev→`/opt/smartcore/dev/.env`, prod→`/opt/smartcore/prod/.env` |
| R.3 User/NoNewPrivileges/PrivateTmp | ✅ | `User=smartcore`, `NoNewPrivileges=yes`, `PrivateTmp=yes` em todas |
| R.4 `mem_limit` em todos os containers | ✅ | 6 containers com `deploy.resources.limits.memory` |
| R.4 rede `smartcore_v2_network` externa | ✅ | `external: true` |
| R.4 pipelines OTEL (traces→Tempo, logs→Loki, metrics→Prometheus) | ✅ | Conforme em otel-collector-config.yml |
| R.4 datasources Grafana pré-configurados | ⚠️→✅ | Correlação derivedField/serviceMap apontava para nomes em vez de UIDs — corrigido |
| R.5 só `.env.example` commitado | ✅ | Apenas `.env.example` e `server/.env.example` rastreados |
| R.5 `.gitignore` cobre `*.env`/`.env.*` | ✅ | `.env`, `.env.*`, `*.env`, exceto `.example`/`.sample` |
| R.5 firewall bloqueia portas internas | ✅ | ufw libera só 22/80/443; comentário lista internas bloqueadas |
| C `.env.example` reflete vars de deploy | ⚠️→✅ | Faltavam vars do Grafana — adicionadas |
| C README com instruções de deploy | ⚠️→✅ | Descrição do trigger do CI estava incorreta — corrigida |
| C backup cifrado dos `.env` | ✅ | `infra/backup-envs.ps1` (AES-256-CBC/PBKDF2/100k iter) — endurecido nesta auditoria |
| E.* (server-setup, DNS, runner, push/tag) | N/A | Operações no servidor real; artefatos que os suportam validados acima |
| V.* (deploy/rollback/smoke end-to-end) | N/A | Execução no servidor; smoke test ampliado para cobrir os 7 serviços |
| ➕ flatc + protobuf-compiler no server-setup | ➕ | Além do plano; necessário p/ FlatBuffers/Tonic |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| docker/observability/provisioning/datasources/ds.yml:5-34 | `derivedFields.datasourceUid: Tempo` e `serviceMap.datasourceUid: Prometheus` referenciavam o NOME da datasource, não o UID — correlação log↔trace e service map não resolveriam | Adicionado `uid: prometheus/loki/tempo` explícito a cada datasource e ajustadas as referências para os UIDs |
| .github/workflows/deploy-dev.yml:70 | Smoke test cobria só 4 serviços; plano V.1 pede "todos active" | Incluídos `control_plane messaging_gateway worker` na verificação |
| .github/workflows/deploy-prod.yml:106 | Idem (prod) | Incluídos os 3 serviços faltantes |
| infra/backup-envs.ps1:39-49 | Senha lida em texto puro (`Read-Host` sem `-AsSecureString`) | Trocado para `-AsSecureString` + conversão controlada |
| infra/backup-envs.ps1:64-65 | `$PasswordBytes` morto + senha passada via `pass:$Password` (visível na lista de processos) | Removido código morto; senha passada via `pass:env:BACKUP_ENC_PASS` e var de ambiente limpa após o uso |
| README.md:44 | "Disparado em qualquer Pull Request" — ci.yml também dispara em `push` de qualquer branch | Texto ajustado para refletir push (todas as branches) + PR para main/dev |
| .env.example:77-80 | Faltavam `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` consumidos por observability.yml | Bloco Grafana adicionado |

## 3. Decisões Autônomas (revisar depois)
- Ampliei os smoke tests (dev+prod) de 4 para 7 serviços. O plano registra explicitamente health check raso (`is-active`) como risco aceito; a ampliação é low-risk e alinha com V.1 ("todos os serviços active"). Se algum dos 3 serviços extras ficar `inactive` legitimamente em algum cenário, o deploy passará a falhar/rollback — comportamento desejado.
- `backup-envs.ps1`: mantive a leitura interativa, apenas endurecendo o manuseio da senha. Não alterei o algoritmo (AES-256-CBC/PBKDF2/100k iter) nem o fluxo de decriptação documentado.

## 4. Revalidação
- YAML (workflows/observ.): ✅ (parsing válido nos arquivos editados)
- shell (`bash -n server-setup.sh`): ✅ (sintaxe OK)
- powershell (`backup-envs.ps1`): ✅ (parser sem erros após edição)
- lint/type-check/clippy: N/A (sem código Python/Rust no escopo)

## 5. Pendências (escopo extra ou fora do plano)
- **`infra/.env.deploy.example` está GITIGNORADO** (`.gitignore` `.env.*` o captura). É um template `*.example` sem segredos que deveria ser versionado, mas pertence ao fluxo de deploy-data/tunnel (outra feature) e não aos workflows/systemd do cicd-devops — fora do escopo. Recomendo `!infra/*.env.deploy.example` ou renomear na feature correspondente. O `backup-envs.ps1` referencia `./.env.deploy` real, que continua corretamente ignorado.
- **`docker/compose/observability.yml`**: fallback `GRAFANA_ADMIN_PASSWORD:-admin_secret_pass` é uma senha-padrão fraca embutida (apenas default de `docker compose up` local, não segredo de produção). Considerar trocar por `${GRAFANA_ADMIN_PASSWORD:?defina no .env}`.
- **server-setup.sh não instala `docker.io`**: diverge do texto do plano (correção #9), mas é coerente com o servidor real (Docker já provisionado pela stack de dados). Documentar como pré-requisito.
- Arquivos `infra/create-superuser.ps1`, `delete-superuser.ps1`, `deploy-data.*`, `manage.ps1`, `tunnel.*`, `test-r2.py` aparecem no diff mas são de outras features — não auditados/tocados.
