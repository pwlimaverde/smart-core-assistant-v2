# Documentação Auxiliar — Reestruturação dev/prod

> Gerado em: 2026-11-21 (fase de levantamento, executada no próprio servidor `srv1321059`)
> Plano canônico: `.context/plans/servidor-reestruturacao-dev-prod.md`
> Plano completo: `.context/plans/servidor-reestruturacao-dev-prod/plano_completo_servidor-reestruturacao-dev-prod.md`

Este plano não mexe em bibliotecas de código (Grupo A vazio): o assunto é
pipeline, Compose e operação. A central `doc_dev/libs/` não foi consultada porque
nenhuma lib de Rust, Python ou Flutter muda. As fontes aqui são o estado real do
servidor e do GitHub, levantados por leitura, e o comportamento conhecido das
ferramentas de CI e de containers.

---

## 1. Estado real levantado (2026-11-21, somente leitura)

### 1.1 Máquina
| Item | Valor |
|---|---|
| CPU / RAM / swap | 2 vCPU · 7,8 GiB · 2 GiB de swap |
| Disco | 96 GB, 24 GB usados (25%) |
| Uso real de RAM da dev | ~1,6 GiB (`ia_engine_jev` 505 MiB, `mcp_server` 479 MiB de 512 MiB, `ia_engine` 336 MiB, o resto < 130 MiB cada) |
| Observabilidade | ~0,46 GiB |
| Soma dos `mem_limit` do compose prod | ~9,4 GiB (a dev tem outro tanto, ~9,9 GiB com MinIO) |
| Runner | `actions.runner.pwlimaverde-smart-core-assistant-v2.hostinger-kvm2` (systemd, usuário `gh-runner`, labels `[self-hosted, hostinger]`) |
| sudo do `gh-runner` | só `systemctl`/`journalctl` em `smartcore-*` (o comentário do workflow fala em `docker compose`: está desatualizado) |

**Alerta no `mcp_server` da dev:** 479 MiB de um teto de 512 MiB. Fora do
escopo deste plano, mas é o próximo OOM provável.

### 1.2 Projetos Compose no ar
| Projeto | Origem do compose | Quem implanta hoje |
|---|---|---|
| `smart-core-v2-dev` (20 serviços) | `docker/dev/compose.yml` | `deploy-dev.yml` |
| `smart-core-v2-evolution` | `docker/evolution/compose.yml` | `deploy-dev.yml` (pull + up a cada deploy) |
| `smart-core-v2-observability` | `docker/observability/compose.yml` | `deploy-dev.yml` **e** `deploy-prod.yml`, ambos com `--force-recreate` |
| `smart-core-v2-edge` | `docker/edge/compose.yml` | `deploy-dev.yml` (build da imagem `:latest`) e `deploy-prod.yml` (só sobe) |
| `releases-stack` (container `smart-core-v2-releases`) | `/opt/smartcore/releases-stack/compose.yml` — **fora do repositório** | à mão |
| `smart-core-site` (imagem `smartcore-site:local`) | `/opt/smartcore/site/` — fora do deploy | à mão |
| `smart-core-v2-prod` | `docker/prod/compose.yml` | **nunca subiu** |

Não há containers `smartcoreassistant_*` (v1) nem `paulo-ecoprint-*` no ar. O
domínio principal hoje cai no container do site (`:8085`), não no Django.
O `CLAUDE.md` global da máquina está desatualizado nesses dois pontos.

### 1.3 Diretórios em `/opt/smartcore`
| Caminho | Situação |
|---|---|
| `dev/env/dev.env` | Fonte atual do ambiente dev (gh-runner, 600, 6,6 KB) + 5 backups `.bak-*` |
| `dev/.env`, `dev/bin`, `dev/bin.bak` | Resto da era systemd (jun/2026) |
| `prod/env/` | **Não existe** (o `CLAUDE.md` diz "vazio") |
| `prod/.env` (34 linhas, jun/2026) | Resto da era systemd — não é o `prod.env` que o workflow espera |
| `prod/releases/v0.1.0` + `current` → v0.1.0 | Binários da era systemd. O padrão "diretório por versão + symlink `current`" é reaproveitado neste plano |
| `prod/backups/` | Dumps e exports de segurança |
| `observability/env/observability.env` | Fonte do env da observabilidade |
| `releases/`, `releases-data/`, `releases-stack/` | Servidor de releases (mock antigo + stack atual + dados) |
| `backups/` | Dumps avulsos (pré-docker, desativação da v1) |
| `Caddyfile.novo` | Resto de set/2026 |

### 1.4 Volumes
Volumes nomeados por projeto (`smart-core-v2-dev_postgres_data`,
`..._redis_data`, `..._minio_data`, etc.) e **volumes órfãos** de quando o
Evolution vivia no projeto da dev (`smart-core-v2-dev_evolution_data`,
`..._evolution_logs`, `..._postgres_evolution_data`) e três volumes anônimos.

### 1.5 GitHub
| Item | Estado |
|---|---|
| Tags `v*` | só `v0.1.0` |
| `main` × `dev` | `main` está **797 commits atrás** da `dev` |
| Proteção da `main` | **nenhuma** (`Branch not protected`) |
| Rulesets | nenhum |
| Environments | `dev` (sem regra) e `prod` (política de implantação só para tags `v*`) |
| `deploy-prod.yml` | usa `environment: production` — **ambiente que não existe**. O GitHub cria o ambiente sem proteção na primeira execução: a tag iria para produção sem revisor e sem a política `v*` do ambiente `prod` |
| Secrets de repositório | `RELEASES_UPLOAD_TOKEN`, `SIGNTOOL_CERT`, `SIGNTOOL_PASSWORD` |
| `pr-to-main.yml` | abre PR `dev → main` **depois** do deploy da tag (fluxo invertido) |

### 1.6 Bind mounts que leem da workspace do runner
O `deploy-*.yml` roda o compose de dentro de
`/home/gh-runner/actions-runner/_work/...` — **a mesma workspace para dev e
prod**. Arquivos montados por bind:

- `docker/dev|prod/compose.yml` → `../init-scripts` e `../backup` (script do
  `pg_backup` e a sonda dele);
- `docker/observability/*.yml` e `provisioning/`;
- `docker/evolution/init-scripts`.

Consequência: um deploy da dev faz checkout da `dev` na mesma pasta; o
`pg_backup` de **produção** passa a executar o `backup.sh` da `dev` no próximo
restart do container. É o motivo técnico do bundle de release por ambiente
(seção D-R4 do plano completo).

### 1.7 Dependências do "ambiente local"
| Artefato | Uso |
|---|---|
| `server/crates/test_support/src/lib.rs` (`ensure_tunnel`) | sobe túnel SSH para o Postgres/Redis da VPS quando a porta 5434/6380 não está aberta; na CI os service containers ocupam as portas e o túnel não abre |
| `infra/tunnel.ps1`, `infra/tunnel.sh` | túnel manual |
| `infra/test-local.ps1`, `infra/test-quick.ps1`, `infra/test-flutter.ps1`, `infra/clean-target.ps1` | testes e limpeza na máquina do desenvolvedor |
| `infra/create-superuser.ps1`, `infra/delete-superuser.ps1`, `infra/backup-envs.ps1` | administração pela máquina local, via túnel |
| `server/.env` (no clone do VPS) | `DATABASE_URL` aponta para o túnel |
| `docker/dev/compose.yml` | publica Postgres (5434), Redis (6380) e Redis-bus (6381) em `127.0.0.1` **só** para o túnel |
| Docs | `.context/docs/tooling.md`, `testing-strategy.md`, `architecture.md`, runbooks em `infra/` |

`infra/build-windows.ps1` **não** é local: o `deploy-dev.yml` e o
`release-windows.yml` o chamam. Fica.

---

## 2. Comportamento das ferramentas que o plano usa

### 2.1 GitHub Actions
- **Eventos criados com `GITHUB_TOKEN` não disparam novos workflows** (exceto
  `workflow_dispatch` e `repository_dispatch`). Uma tag criada por um job com
  `GITHUB_TOKEN` **não** dispara o `deploy-prod.yml`. Por isso a tag de release
  é criada por pessoa (`git push` ou `gh release create`, com o token do
  usuário), nunca por um job.
- **Environments**: revisores obrigatórios, tempo de espera, política de
  implantação por branch/tag e secrets por ambiente. Um secret de ambiente só
  é entregue ao job que declara `environment:` com aquele nome, depois de
  passar pelas regras. `environment:` com nome inexistente cria o ambiente sem
  regra nenhuma.
- **Secrets**: até 48 KB cada. Valores multilinha (chaves PEM) passam melhor em
  base64. O GitHub mascara o valor do secret no log, mas não mascara
  transformações dele (o conteúdo decodificado). Nunca imprimir o decodificado
  nem usar `set -x` no passo.
- **Rulesets**: protegem branch (`main`: exigir PR, checks obrigatórios,
  proibir force-push e exclusão) e tag (`v*`: só quem estiver na lista de
  bypass cria, atualiza ou apaga). Com um único desenvolvedor, exigir
  aprovação de PR trava o fluxo (o autor não aprova o próprio PR); exige-se PR
  + checks verdes, com 0 aprovações.
- **`concurrency`** com `cancel-in-progress: false` serializa deploys do
  mesmo grupo.
- **Runner self-hosted**: o job roda na própria VPS. Não precisa de SSH, chave
  de deploy nem porta aberta para o GitHub.

### 2.2 GHCR
- Login com `GITHUB_TOKEN` (`packages: write` no build, `packages: read` no
  deploy). Não há necessidade de `DOCKER_REGISTRY_TOKEN`.
- `docker/metadata-action` com `type=semver,pattern={{version}}` gera a tag
  **sem** o `v` (`1.4.0` para a tag git `v1.4.0`); `type=sha` gera
  `sha-<curto>`.
- Retagar sem rebuild: `docker buildx imagetools create -t <novo> <existente>`
  (cria um novo nome para o mesmo digest).
- Limpeza: `actions/delete-package-versions` (por padrão de tag, com
  `min-versions-to-keep`).

### 2.3 Docker Compose
- Vários `-f` são mesclados na ordem (base + override). Listas como `ports`
  são somadas, mapas como `environment` são sobrescritos por chave.
- `-p <projeto>` ou `name:` no arquivo fixam o projeto; `--env-file` define a
  interpolação. `COMPOSE_PROJECT_NAME` no `.env` sobrepõe — proibido nos env de
  ambiente (já documentado no `deploy-dev.yml`).
- `up -d` **não** recria container quando só muda o conteúdo de um arquivo
  montado por bind (já mordeu a observabilidade). Com bundle por versão o
  caminho do bind muda a cada release, e o Compose recria o serviço.
- `up -d` sem `down` recria só o que mudou; `down` derruba tudo (downtime) e
  não é necessário para trocar de versão.
- `mem_limit` e `restart: unless-stopped` estão em uso e funcionam fora do
  Swarm. O plano não depende de `deploy.restart_policy`; a doc atual do Compose
  consultada (Context7, `/websites/docker_compose`) não esclarece esse ponto
  fora do Swarm, e `on-failure` com `max_attempts` deixaria o serviço parado
  depois das tentativas — o oposto do que o `watchdog` do projeto pressupõe.

### 2.4 Caddy
- Um único processo ocupa 80/443; a config é uma só, e `reload` troca a config
  inteira. Não existe "borda por ambiente" na mesma máquina sem um segundo IP.
- `caddy validate --config <arquivo> --adapter caddyfile` valida sem servir;
  roda na CI com a imagem do Caddy.

---

## 3. Grupo C — Observabilidade e auditoria (levantamento)

| Etapa | Log/trace | `audit_log` | Vazamento |
|---|---|---|---|
| Governança Git (rulesets, environments) | histórico de deployments do GitHub | sem evento de `audit_log` (não é ação de aplicação) | nenhum segredo envolvido |
| Materialização do `.env` | linha `env materializado: <ambiente> (<n> chaves)` no job, sem valores | sem evento | decodificado nunca vai ao log; `umask 077`; `printf`, não `echo`; sem `set -x` |
| Deploy (dev/prod) | marcador `event=deploy env=<e> version=<v> sha=<s> status=<ok/falha>` em `/opt/smartcore/<env>/deploys.log` (lido pelo promtail) + anotação no Grafana | sem evento (a trilha é o histórico do environment no GitHub) | `docker logs --tail` no smoke test pode trazer PII de payload → limitar a 50 linhas, como hoje, e revisar M10 do go-live |
| Rollback | mesmo marcador, `event=rollback` | sem evento | idem |
| Serviços de aplicação | inalterados: `SMARTCORE_ENV` passa a vir do overlay, corrigindo o `env` fixo em `"production"` (M9 do go-live) | inalterado | inalterado |
