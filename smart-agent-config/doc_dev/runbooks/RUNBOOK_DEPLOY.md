# RUNBOOK — Deploy, release, hotfix e rollback (dev e prod)

> Plano: `.context/plans/servidor-reestruturacao-dev-prod.md`. Vale para a VPS
> `srv1321059` (76.13.229.210), que hospeda os **dois** ambientes. Não há ambiente
> local: a máquina do desenvolvedor só edita, faz push e lê o Grafana.

## 1. Visão geral

```
feature/* ──PR──▶ dev ──push──▶ deploy-dev.yml ──▶ vX.Y.Z-beta.N  (/opt/smartcore/dev)
                                                    │ tag beta criada após o smoke
                  dono: git tag vX.Y.Z <commit com beta> && git push origin vX.Y.Z
                                                    ▼
                                deploy-prod.yml ──(aprovação `prod`)──▶ vX.Y.Z (/opt/smartcore/prod)
                                                    │ main avança (fast-forward) até a release
                                                    ▼
                                deploy-infra.yml (se a release mudou borda/observabilidade/Evolution;
                                                  também pede aprovação)
```

| Workflow | Gatilho | Environment | O que faz |
|---|---|---|---|
| `ci.yml` | todo push/PR | — | Rust (fmt, clippy, testes com Postgres/Redis), Python, Flutter, **Infra** (compose config, shellcheck, actionlint, caddy validate) |
| `deploy-dev.yml` | push na `dev` | `dev` (sem revisor) | builda só o que mudou (`sha-<curto>`), promove as 6 imagens a `X.Y.Z-beta.N`, bundle, `deploy.sh dev`, tag beta |
| `deploy-prod.yml` | tag `vX.Y.Z` | `prod` (revisor: dono) | gate de origem, CI verde, web com endereços de prod, backend **promovido** da beta (mesmo digest), `deploy.sh prod`, avança a `main` |
| `rollback-prod.yml` | manual (da `main`) | `prod` | `rollback.sh prod vX.Y.Z` com portão de migração |
| `deploy-infra.yml` | push na `main` em `docker/{edge,observability,evolution}` ou manual | `prod` | `deploy-infra.sh <componente>` (bundle, validação, smoke, retorno automático) |

Cada tipo de run tem o seu grupo de `concurrency`: `deploy-vps-dev`,
`deploy-vps-prod-<tag>`, `deploy-vps-rollback-prod` e `deploy-vps-infra`. O GitHub
guarda só um run pendente por grupo e cancela o anterior; com grupos separados,
um deploy de um tipo não cancela nem trava o de outro. Um deploy por vez na VPS
continua garantido pelo runner self-hosted `hostinger`, que é único e roda um job
por vez.

## 2. Layout no servidor

```
/opt/smartcore/
├── dev/  e  prod/
│   ├── env/<env>.env          ← materializado do secret ENV_FILE_B64 (600, gh-runner). NÃO editar.
│   ├── releases/<id>/         ← bundle: docker-compose.base.yml, <env>.override.yml, <env>.vars,
│   │                            backup/, init-scripts/, images.env, MIGRATIONS, RELEASE, .env -> ../../env/<env>.env
│   ├── releases/current       ← o que está no ar
│   ├── releases/previous      ← o anterior (alvo do retorno automático)
│   ├── backups-deploy/        ← pg_dump validado antes de CADA deploy (10 últimos)
│   └── deploys.log            ← ts= event= env= version= sha= run= status= duracao_s=
├── infra/{edge,observability,evolution}/releases/<id>/ + current
├── infra/evolution/env/evolution.env, observability/env/observability.env
├── infra/deploys.log
├── prod/backups/              ← dumps históricos (root, 700) — não usado pelo deploy
└── _legado/                   ← restos da era systemd (movidos, nada apagado)
```

Projetos compose: `smart-core-v2-dev`, `smart-core-v2-prod`, `smart-core-v2-edge`,
`smart-core-v2-observability`, `smart-core-v2-evolution` (+ `releases-stack` e
`smart-core-site`, ainda fora do pipeline — go-live F3/F8).

Diferenças permitidas entre dev e prod: só as de `docker/stack/{dev,prod}.override.yml`
e `{dev,prod}.vars` (portas, redes de telemetria, retenção de backup, MinIO só na dev).

| | dev | prod |
|---|---|---|
| runtime_api / web / web-tenant | 50051 / 8081 / 8083 | 50052 / 8082 / 8084 |
| auth (control_plane) / mcp | 8095 / 8099 | 8096 / 8100 |
| webhook_ingress (loopback) | 9210 | 9211 |
| rede de telemetria | `smart_core_v2_observability` | `smart_core_v2_telemetria_prod` |
| storage | MinIO local | Cloudflare R2 |
| backup periódico | 24 h, 14 dias | 12 h, 30 dias |

## 3. Deploy da dev (automático)

1. PR `feature/x → dev`, CI verde, merge.
2. O push na `dev` dispara `deploy-dev.yml`. Nada a fazer.
3. Conferir: resumo do job (versão e tag de cada imagem), `tail /opt/smartcore/dev/deploys.log`,
   `docker compose ls`.

Se o smoke reprovar, o `deploy.sh` volta sozinho para o `previous` e o job fica
vermelho; a tag beta **não** é criada. Correção: `git revert` na `dev` (nunca force-push).

Mudança só de compose/scripts (`docker/stack`, `docker/backup`, `docker/init-scripts`,
`infra/deploy`, `VERSION`) gera nova beta **sem rebuild**: as imagens são promovidas
da beta anterior.

## 4. Release de produção

Pré-requisitos (uma vez — ver §9): secret `ENV_FILE_B64` no environment `prod`.

1. Escolher o commit: a beta que está boa na dev (`git tag -l 'v*-beta.*' --sort=-v:refname | head`).
2. Criar e enviar a tag **no mesmo commit da beta** (só o dono consegue — ruleset):
   ```bash
   git fetch --tags
   git tag -a v0.2.0 v0.2.0-beta.3^{} -m "Release v0.2.0"
   git push origin v0.2.0
   ```
3. `deploy-prod.yml` roda: gate de origem → CI verde → build da web de prod →
   **para em "Waiting for review"**. Aprovar em *Actions → run → Review deployments*.
4. Depois da aprovação: promoção das imagens, bundle, `pg_dump`, `up`, smoke; com
   sucesso, a `main` avança até `v0.2.0`. Se a release mudou borda/observabilidade/
   Evolution, o push na `main` dispara `deploy-infra.yml` (nova aprovação).
5. Subir o arquivo `VERSION` na `dev` (ex.: `0.3.0`) para as próximas betas.

Release com migração de banco: ver §7 antes de taguear, e **RC obrigatório** (§4.1).

### 4.1 Release candidate (RC) — ensaio sem deploy

Não há staging nem RAM para um terceiro ambiente (decisão D1, §12). O RC prova
tudo o que dá para provar sem subir nada: origem e CI, build da web com os
endereços de prod, promoção das imagens (`X.Y.Z-rc.N`, mesmo digest da beta) e
montagem + `compose config` do bundle de prod. Também lista as migrações novas.

```bash
git tag -a v0.3.0-rc.1 v0.3.0-beta.4^{} -m "RC v0.3.0"
git push origin v0.3.0-rc.1        # -> release-candidate.yml (sem aprovação, sem VPS)
# RC verde: tag final no MESMO commit
git tag -a v0.3.0 v0.3.0-rc.1^{} -m "Release v0.3.0" && git push origin v0.3.0
```
Obrigatório para release com migração (R-D4); opcional nas demais.

## 5. Hotfix

1. `git switch -c hotfix/descricao origin/main`; correção + teste.
2. PR `hotfix/descricao → main` (merge commit), CI verde, merge.
3. `git tag -a v0.2.1 origin/main -m "Hotfix v0.2.1" && git push origin v0.2.1`
   (`vX.Y.Z-hotfix.N` **não** — é pré-release em SemVer e não casa com o gatilho).
4. Sem beta, o `deploy-prod` constrói o backend na hora; resto igual ao §4.
5. O job abre **PR `main → dev`** (backport). Mergear com merge commit; conflito se
   resolve no PR, nunca na `main`.
6. Ensaio do fluxo completo (hotfix → tag → deploy → backport): `v0.2.3`,
   2026-11-23, junto do ensaio de rollback `v0.2.2 → v0.2.1` (R6).

## 6. Rollback de produção

*Actions → Rollback → PROD → Run workflow* (branch `main`), `versao: v0.2.0`.

- Confere que o bundle e as imagens existem, aplica o **portão de migração**, faz
  `pg_dump`, reimplanta e roda o smoke. Tempo esperado: 1–3 min (sem build).
- Se a versão em uso aplicou migração que a alvo não conhece, o job para. Só rode com
  `aceito_migracao: sim` se a migração for aditiva (expand/contract, §7). Senão o
  caminho é **restaurar o dump** (§8) ou corrigir para frente.
- O mesmo workflow com a versão **atual** serve para reaplicar o secret depois de uma rotação.

Rollback manual de emergência (runner fora do ar), como `gh-runner` na VPS:
```bash
cd /opt/smartcore/ops/smart-core-assistant-v2   # scripts só leem o checkout
sudo -u gh-runner infra/deploy/rollback.sh prod v0.2.0
```
As imagens da versão alvo normalmente já estão em disco (`up --pull missing`). Se não
estiverem, o pull exige login no GHCR (pacotes privados): `docker login ghcr.io` como
`gh-runner` com um token `read:packages`.

## 7. Migrações (expand/contract)

As migrações só andam para frente. Para o rollback continuar barato:
- versão N **adiciona** (coluna/tabela nova, nullable); N+1 passa a usar; N+2 remove o velho;
- PR com `DROP`, `RENAME` ou `NOT NULL` sem default leva o rótulo `migracao-destrutiva`
  e a release correspondente passa antes por uma beta com dados reais na dev.

## 8. Restaurar banco a partir do dump pré-deploy

```bash
ls -t /opt/smartcore/prod/backups-deploy/ | head
cd /opt/smartcore/prod/releases/current
docker compose -p smart-core-v2-prod --project-directory . -f docker-compose.base.yml -f prod.override.yml \
  --env-file .env --env-file prod.vars --env-file images.env stop data_postgres worker runtime_api control_plane
docker compose ... exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists' \
  < /opt/smartcore/prod/backups-deploy/<arquivo>.dump
docker compose ... up -d
```
(Script `infra/restore-postgres.sh` cobre o caso geral.)

## 9. Segredos

| Secret | Onde | Uso |
|---|---|---|
| `ENV_FILE_B64` | environment `dev` | `dev.env` inteiro, base64 |
| `ENV_FILE_B64` | environment `prod` | `prod.env` inteiro, base64 (criado em 2026-11-22) |
| `OBS_ENV_FILE_B64` | environment `prod` (opcional) | env da observabilidade; sem ele vale o arquivo do servidor |
| `EVOLUTION_ENV_FILE_B64` | environment `prod` (opcional) | env da Evolution; idem |
| deploy key `deploy-prod: avança main` | repositório (escrita) + `/home/gh-runner/.ssh/smartcore_main_ff` | único caminho de push direto na `main` |

Criar/rotacionar (nunca imprimir o arquivo):
```bash
base64 -w0 prod.env | gh secret set ENV_FILE_B64 --env prod -R pwlimaverde/smart-core-assistant-v2
```
Depois, redeploy (dev: qualquer push; prod: `rollback-prod` com a versão atual).
Guardar uma cópia do `prod.env` no cofre do dono: sem a `ENCRYPTION_KEY`, os dados
cifrados no banco se perdem.

O `deploy.sh` recusa env sem as chaves de `infra/deploy/required-keys.<env>` e env com
`COMPOSE_PROJECT_NAME` (ou `MINIO_*` na prod).

## 10. Infra compartilhada

*Actions → Deploy → INFRA compartilhada → Run workflow* (branch `main`),
`componente: edge | observability | evolution | todos`.
- **edge**: imagem `smartcore-edge:sha-<curto>`; `caddy validate` antes de publicar e
  de novo na VPS antes de trocar; smoke HTTPS em `smartcoreassistant.com.br` e `dev.`.
- **observability**: cria as redes de telemetria da prod se faltarem; o bundle novo
  troca o caminho dos binds e o compose recria só o que mudou.
- **evolution**: recria a Evolution (a sessão do WhatsApp fica no volume; reconexão de segundos).

## 11. Checklist de verificação rápida

```bash
docker compose ls
readlink /opt/smartcore/{dev,prod}/releases/current
tail -n 5 /opt/smartcore/{dev,prod}/deploys.log /opt/smartcore/infra/deploys.log
git ls-remote --tags origin 'v*' | tail
gh run list -L 5
```

Grafana → pasta *SmartCore v2* → painel **Deploys** (uid `smartcore-deploys`):
os marcadores dos três `deploys.log` (job `deploy_markers` do promtail), com
contagem de deploys/rollbacks/falhas. Os painéis *Serviços — saúde* e
*Latência gRPC* mostram os deploys de dev e prod como anotações. O Loki guarda
14 dias; o histórico completo é o próprio arquivo.

## 12. Memória (decisão D1, 2026-11-22)

VPS de 7,8 GiB + 2 GiB de swap para dev, prod, observabilidade, Evolution e borda.

| Camada | Soma dos tetos | `oom_score_adj` | Onde |
|---|---|---|---|
| prod | ~7,6 GiB | 0 | `docker/stack/prod.vars` (`MEM_*`) |
| dev | ~5,3 GiB | 900 | `docker/stack/dev.vars` |
| observabilidade | ~2,8 GiB | 300 | `docker/observability/compose.yml` |

- Teto não é reserva: o uso real medido (cgroup `memory.peak`) era ~3 GiB com
  tudo no ar. A soma dos tetos da **prod** cabe na RAM sozinha.
- Se o host inteiro ficar sem memória, o kernel mata **a dev primeiro**, depois
  a observabilidade, e só por último a prod.
- Recalibrar: `cat /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.peak`
  por container; ajustar `MEM_*` no `.vars` e seguir o fluxo normal (dev: push;
  prod: release).

## 13. Webhook do WhatsApp por ambiente

A `evolution_net` é compartilhada e nela `webhook_ingress` resolve para os dois
ambientes (incidente de 2026-11-22: webhooks da dev entregues na prod).

- **dev**: `WEBHOOK_INGRESS_URL=http://provider_edge:8088/dev` (`dev.vars`,
  cutover de 2026-11-25). O `provider_edge` repassa ao `webhook_ingress:9200`
  da dev (`PROVIDER_EDGE_DESTINOS`). Reverter: comentar a linha no `dev.vars`
  (volta ao padrão `http://webhook_ingress:9200`), deployar e regravar a URL.
- **Regravar a URL de uma instância já conectada**: a reconciliação do worker
  NÃO regrava (instância `connected` só tem o estado carimbado). Quem regrava é
  o botão Reconectar do painel (`ReconnectWhatsappInstance`), que chama
  `POST /instance/connect` com o token da instância e `webhookUrl`; com o
  cliente no ar, o Evolution só atualiza a configuração, sem novo QR. Sem
  acesso ao painel, a mesma chamada pode ser feita no host (token da instância
  em `GET /instance/all` com a chave global) e conferida em `/instance/all`.
- **prod**: `http://172.17.0.1:9211` — a porta da prod (`prod.vars`) publicada na
  ponte do Docker, que só o ingress da prod responde (`prod.override.yml`).
- Conferir: `docker exec smartcore-evolution wget -qO- http://172.17.0.1:9211/health`.
- Instância criada antes da v0.2.2 na prod (não havia nenhuma) teria a URL
  antiga gravada no Evolution: reconectar pelo painel regrava o webhook.

### 13.1 Envia mas não recebe (incidente de 2026-11-26)

Sintoma: instância `connected`, envio funciona, nenhuma mensagem recebida; o
`provider_edge` e o `webhook_ingress` só registram `Connected`/`Disconnected`.
Não é o webhook: a Evolution nem chega a despachar `Event: Message`.

- Assinatura no log da Evolution: a cada ~50 min
  `<stream:error><ack class="status" id="<mesmo id>" type="media"/>`, seguido de
  reconexão e `OfflineSyncPreview` com `Messages:` crescendo; nunca aparece
  `OfflineSyncCompleted`. Mensagens só chegam em rajada logo após reconectar.
- Causa: o whatsmeow da imagem `0.7.2-wa1` não trata a stanza `<status>`
  (stories dos contatos); sem ack, a fila offline do WhatsApp trava atrás dela.
- Correção: imagem `0.7.3-wa1` (whatsmeow com handler de `<status>`), publicada
  pelo workflow `evolution-wa-version` e implantada pelo `deploy-infra.yml`
  (`componente: evolution`, aprovação de prod). A sessão fica no volume.
- Conferir:
  ```bash
  docker logs -t --since 30m smartcore-evolution 2>&1 | grep -E "OfflineSyncCompleted|Event: Message|stream error"
  docker logs --since 30m smart-core-v2-dev-webhook_ingress-1 2>&1 | grep -c '"event_type":"Message"'
  ```
- Rollback: voltar o padrão do `docker/evolution/compose.yml` para `0.7.2-wa1`
  e rodar o `deploy-infra` (o schema v16 do store é compatível com a 0.7.2).
