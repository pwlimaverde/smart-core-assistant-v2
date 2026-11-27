# Plano completo — Reestruturação dev/prod (dois ambientes, deploy por merge e por tag)

> Slug: `servidor-reestruturacao-dev-prod` · Gerado em 2026-11-21 · Fase: levantamento concluído (P)
> Documentação auxiliar e estado real do servidor: [info_aux_servidor-reestruturacao-dev-prod.md](./info_aux_servidor-reestruturacao-dev-prod.md)
> Plano irmão (go-live): [../producao-go-live.md](../producao-go-live.md)

---

## 0. Resumo executivo

O pedido é chegar a **dois ambientes, dev e prod**, sem ambiente local, com
deploy automático por merge na `dev` e por tag `vX.Y.Z` criada a partir da
`main`. A maior parte da infraestrutura já existe: workflows de deploy por
branch e por tag, runner self-hosted na VPS, compose de prod pronto (nunca
subiu), smoke tests com sonda real e backup prévio do banco.

O que falta não é construir uma plataforma nova. São **sete defeitos de
processo**, alguns graves:

| # | Defeito | Efeito |
|---|---|---|
| 1 | `deploy-prod.yml` declara `environment: production`, ambiente que não existe (o protegido se chama `prod`) | A primeira tag cria um ambiente **sem revisor nem política de tag** e vai direto para produção |
| 2 | A tag sai da `dev`; o PR `dev → main` é aberto **depois** do deploy (`pr-to-main.yml`) | `main` não é o que roda em produção; está 797 commits atrás |
| 3 | `main` sem proteção; tags `v*` sem ruleset | Qualquer push ou tag vira release |
| 4 | Produção em `:latest` | Rollback por versão impossível; o "reempurrar a tag" reconstrói e move o `latest` |
| 5 | Dev e prod executam compose e binds **da mesma workspace do runner** | Um deploy da dev troca o `backup.sh` que o `pg_backup` de **produção** executa |
| 6 | O deploy da **dev** reconstrói e troca a borda, e recria Evolution e observabilidade | Push na `dev` pode derrubar produção, site e feed de atualização |
| 7 | `docker/dev` e `docker/prod` são dois arquivos de ~600 linhas, ~90% iguais | Deriva entre ambientes (as lacunas L1–L3 e L7 do go-live nasceram daí) |

A proposta corrige esses sete pontos e remove o ambiente local. Ela **não**
reduz o número de serviços: a divisão em `data_*`, `worker`, `runtime_api` etc.
é regra de arquitetura (apps de negócio não importam `infrastructure_*`; dados
só via RPC aos `data_*`). "Simplificar containers" aqui quer dizer um compose
base único, um overlay curto por ambiente e menos projetos compartilhados mal
atribuídos.

---

## 1. Relação com o plano `producao-go-live`

O `producao-go-live` cobre o go-live inteiro (segurança, isolamento de rede,
Evolution, releases do app Windows, site). Este plano é a **fatia de
pipeline e topologia de ambientes** e assume os itens abaixo do go-live, que
deixam de ser tratados lá:

| Item do go-live | Passa a ser entregue aqui por |
|---|---|
| L1 (validar chaves do `prod.env`) | Fase R3 (`infra/deploy/deploy.sh`, validação comum aos dois ambientes) |
| L4 / A5 (prod em `:latest`, rollback) | Fases R2, R3, R5 |
| L5 (tag de qualquer branch, PR pós-deploy) | Fase R1 |
| L8 / A4 (borda trocada por push na dev) | Fase R5 |
| L9 (prod recria observabilidade inteira) | Fase R5 |
| Fase 2, item 5 (versão exata, rollback por `workflow_dispatch`) | Fase R5 |

Continuam no go-live (este plano **depende** deles para a prod subir): C1
(redes de telemetria por ambiente), C2 (URL do webhook por ambiente), C3
(portas próprias de prod), C4 (backup externo), decisões D1 (VPS), D3
(runner), D7 (canal de alerta) e D10 (política de versão). A Fase 9 do go-live
("primeiro deploy por tag") passa a exigir as Fases R1–R5 deste plano.

---

## 2. Correções aplicadas ao pedido original

O pedido trouxe um desenho de partida. Pontos mantidos, ajustados ou
recusados, com o motivo:

| # | No pedido | Decisão | Por quê |
|---|---|---|---|
| 1 | Dev com 3–4 stacks (backend, banco, redis, edge) | **Ajustado**: 1 projeto de aplicação por ambiente (com todos os serviços, banco e Redis dentro) + 4 projetos de infraestrutura compartilhada | Unir `data_*`, `worker`, `runtime_api` num "backend" viola a arquitetura modular por contrato. A simplificação real é o compose base + overlay |
| 2 | Edge por ambiente | **Recusado**: borda única, implantada só pelo fluxo de prod | 80/443 só cabem num processo por IP. A borda roteia os dois ambientes, o site e o feed de releases; quem a troca tem de ser o fluxo com aprovação |
| 3 | Observabilidade separada por ambiente | **Ajustado**: uma stack LGTM compartilhada, separada por rótulo `env` e por rede de telemetria de cada ambiente (C1 do go-live) | Duas LGTM custam ~0,5 GiB a mais de RAM numa máquina de 7,8 GiB que já não comporta a soma dos tetos. O requisito "observabilidade em dev e prod" continua atendido |
| 4 | Build da Evolution no deploy da dev | **Recusado** | A Evolution é imagem fixada (`evolution-go-wa:0.7.3-wa2`, antes `0.7.3-wa1` e `0.7.2-wa1`) com workflow próprio. Reconstruir a cada push troca a sessão de WhatsApp sem motivo. Ela passa a ser implantada só pelo fluxo de prod |
| 5 | SSH do GitHub para a VPS (`SSH_DEPLOY_KEY`) | **Recusado** | O runner é self-hosted **na própria VPS**: não há SSH a fazer. Uma chave de deploy seria só mais um segredo |
| 6 | `DOCKER_REGISTRY_TOKEN` | **Recusado** | O `GITHUB_TOKEN` com `packages: write/read` já autentica no GHCR |
| 7 | `DEV_ENV`/`PROD_ENV` em base64 como secrets | **Aceito, com forma diferente**: secret de **ambiente** `ENV_FILE_B64` (mesmo nome em `dev` e `prod`), não de repositório | Secret de ambiente só chega ao job que passou pela regra do ambiente. Secret de repositório estaria disponível para qualquer workflow, inclusive de branch de feature |
| 8 | `echo $DEV_ENV \| base64 -d > ...` | **Corrigido** para `printf '%s' "$ENV_FILE_B64" \| base64 -d` com `umask 077` e escrita atômica | `echo` sem aspas quebra em espaços/glob; escrever direto no destino deixa arquivo parcial se o decode falhar |
| 9 | `override.yml` da dev "sem healthchecks estritos" | **Recusado** | Os smoke tests dependem das sondas. Sonda frouxa na dev esconde exatamente a falha que depois cai na prod. As sondas são idênticas; muda só tempo de retenção, memória, nível de log e storage |
| 10 | Prod com `cpus: '2'`, `memory: 4G` por serviço e `restart_policy: on-failure, max_attempts: 3` | **Recusado** | 2 CPUs numa máquina de 2 vCPU não limita nada; 4 GiB por serviço não cabe. `on-failure` com 3 tentativas deixa o serviço **parado** após a terceira — o `watchdog` do projeto pressupõe `restart: unless-stopped`. Mantém-se `mem_limit` por serviço, calibrado pelo uso medido |
| 11 | `/opt/smartcore/<env>/volumes/{postgres,redis,media}` (bind) | **Recusado** | Migrar os volumes nomeados com dados vivos (Postgres da dev, sessão do WhatsApp) para bind é risco sem ganho. Ficam os volumes nomeados, escopados pelo projeto (`smart-core-v2-prod_postgres_data`) |
| 12 | `/opt/smartcore/<env>/compose/` | **Aceito e ampliado**: bundle de release por versão, `/opt/smartcore/<env>/releases/<id>/` + symlink `current` | Resolve o defeito 5 (workspace compartilhada) e dá rollback trivial: o bundle anterior tem o compose e os scripts daquela versão |
| 13 | Hotfix `vX.Y.(Z+1)-hotfix.1` | **Corrigido** para `vX.Y.(Z+1)` | Em SemVer, `-hotfix.1` é pré-release e vale **menos** que `X.Y.(Z+1)`. Além disso o gatilho do deploy (`v[0-9]+.[0-9]+.[0-9]+`) não casa com sufixo — o hotfix não subiria |
| 14 | `vX.Y.Z-rc.N` | **Ajustado**: RC gera imagens e bundles de prod (ensaio de build), **sem deploy** | Não há staging. RC serve para provar que a release compila com os endereços de prod antes da tag final |
| 15 | Rollback `pull && down && up` | **Corrigido** | `pull` traz a mesma versão (não volta nada), `down` derruba tudo sem necessidade. Rollback = apontar `current` para o bundle anterior e `up -d` (seção 9) |
| 16 | Tag criada no fluxo de release por automação | **Ajustado**: a tag é criada por pessoa (`gh release create` ou `git push origin vX.Y.Z`) | Tag criada com `GITHUB_TOKEN` não dispara workflow nenhum; o deploy de prod nunca rodaria |
| 17 | `docs/DEPLOY_PLAYBOOK.md`, `infra/deploy-script-dev.sh` e `-prod.sh` | **Ajustado**: `doc_dev/runbooks/RUNBOOK_DEPLOY.md` e **um** script `infra/deploy/deploy.sh <env> <id>` | O repo não tem `docs/`; runbooks vivem em `doc_dev/runbooks/`. Dois scripts quase iguais repetem o problema dos dois composes |
| 18 | Notificação Slack/Teams | **Adiado para a decisão D7 do go-live** | Não há canal configurado. Até lá: resumo do job (`GITHUB_STEP_SUMMARY`), e-mail de falha do GitHub e marcador de deploy no Grafana |

---

## 3. Arquitetura de ambientes

### 3.1 Diagrama

```
                         GitHub (pwlimaverde/smart-core-assistant-v2)
   feature/* ──PR──▶ dev ──────────────PR (merge commit)──────────────▶ main
                      │                                                  │
                      │ push                                    tag vX.Y.Z (pessoa)
                      ▼                                                  ▼
              deploy-dev.yml                                    deploy-prod.yml
              env "dev" (sem revisor)                 env "prod" (revisor + só tags v*)
              build só do que mudou                    gate: tag ∈ main + CI verde
              imagens :sha-<curto>                     build completo → imagens :X.Y.Z
                      │                                                  │
                      └──────────────┐                 ┌─────────────────┘
                                     ▼                 ▼
 ┌──────────────────────── VPS srv1321059 (runner self-hosted, sem SSH) ───────────────────────┐
 │                                                                                             │
 │  smart-core-v2-dev  (app, 20 serviços)          smart-core-v2-prod  (app + site)            │
 │  /opt/smartcore/dev/releases/current            /opt/smartcore/prod/releases/current        │
 │  MinIO · portas 50051/8081/8083                 R2 · portas 50052/8082/8084 (+C3 go-live)   │
 │  rede telemetria_dev                            rede telemetria_prod                        │
 │         │                                                 │                                 │
 │         └──────────────┬──────────────────────────────────┘                                 │
 │                        ▼  infraestrutura compartilhada (implantada SÓ pelo fluxo de prod)   │
 │  smart-core-v2-edge (Caddy 80/443)  ·  smart-core-v2-observability (LGTM, rótulo env)       │
 │  smart-core-v2-evolution (WhatsApp) ·  smart-core-v2-releases (feed do app Windows)         │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Projetos Compose (de 8 para 6)

| Projeto | Conteúdo | Implantado por | Muda em relação a hoje |
|---|---|---|---|
| `smart-core-v2-dev` | Aplicação dev + Postgres, Redis, Redis-bus, MinIO, backup | `deploy-dev.yml` | Compose base + overlay; sem portas de banco no host |
| `smart-core-v2-prod` | Aplicação prod + Postgres, Redis, Redis-bus, backup, **site** | `deploy-prod.yml` | Sobe pela primeira vez; site entra (decisão do go-live) |
| `smart-core-v2-edge` | Caddy | `deploy-prod.yml` / `deploy-infra.yml` | Sai do fluxo da dev; imagem versionada |
| `smart-core-v2-observability` | LGTM | `deploy-prod.yml` / `deploy-infra.yml` | Recria só quando o hash da config muda |
| `smart-core-v2-evolution` | Evolution + banco dele | `deploy-prod.yml` / `deploy-infra.yml` | Sai do fluxo da dev; a dev só confere a rede |
| `smart-core-v2-releases` | `releases_server` | `deploy-prod.yml` / `deploy-infra.yml` | Sai de `/opt/smartcore/releases-stack` (fora do repo) e do nome `releases-stack` |

Some: `smart-core-site` avulso (vai para dentro da prod) e `releases-stack`.

### 3.3 Diferenças permitidas entre dev e prod

Só estas. Qualquer outra diferença entre os ambientes é defeito.

| Aspecto | dev | prod |
|---|---|---|
| Imagens | `sha-<curto>` por imagem | `X.Y.Z` em todas |
| Storage de mídia | MinIO local | Cloudflare R2 |
| Portas no host | 50051 / 8081 / 8083 / (MCP dev) | 50052 / 8082 / 8084 / (MCP prod, C3) |
| Endereços Flutter (`--dart-define`) | `dev.smartcoreassistant.com.br` | `smartcoreassistant.com.br` |
| Backup | 24 h, 14 dias | 12 h (6 h após go-live), 30 dias + cópia externa (C4) |
| `mem_limit` | menor (dev ociosa) | pelo uso medido + folga |
| `SMARTCORE_ENV` / `OTEL_SERVICE_NAMESPACE` | `dev` / `smart-core-v2-dev` | `prod` / `smart-core-v2-prod` |
| `RUST_LOG` | `info` (pode subir para `debug` por variável) | `info` |
| Site | não sobe | sobe |

Sondas, `restart`, rotação de log, redes internas e lista de serviços: **iguais**.

---

## 4. Fluxos CI/CD

### 4.1 Feature → dev (deploy automático)

```
1. git switch -c feature/xxx dev ; commits ; git push
2. CI (ci.yml) roda na branch: Rust (fmt, clippy, testes com Postgres/Redis de serviço),
   Python, Flutter analyze/test, caddy validate se docker/edge mudou,
   compose config se docker/ mudou.
3. PR feature/xxx → dev. Checks obrigatórios verdes. Merge (squash permitido aqui).
4. push em dev dispara deploy-dev.yml:
   a. changes      → paths-filter decide o que construir
   b. build-*      → só imagens afetadas, tag sha-<curto> (+ :dev móvel)
   c. deploy (runner VPS, env "dev"):
        - materializa /opt/smartcore/dev/env/dev.env a partir de ENV_FILE_B64
        - monta bundle /opt/smartcore/dev/releases/<sha>/ (compose, overlay, scripts,
          images.env com a tag de CADA imagem; imagens não reconstruídas herdam a tag
          do bundle current)
        - infra/deploy/deploy.sh dev <sha>
            valida chaves → compose config → pull → up -d --remove-orphans
            → troca current → smoke tests → marcador de deploy
        - NÃO toca borda, Evolution, observabilidade nem releases
   d. Windows dev (artefato) segue como hoje.
5. Falha no smoke → job vermelho, current NÃO é trocado (aponta para o bundle anterior);
   correção = git revert na dev (nunca force-push).
```

### 4.2 dev → main → tag → prod

```
1. Abrir PR dev → main (pessoa, ou workflow "abrir-release" por workflow_dispatch).
   Corpo do PR: changelog desde a última tag, lista de migrações novas
   (server/crates/infrastructure_postgres/migrations/), aviso se houver migração
   não compatível com a versão anterior.
2. Checks obrigatórios na main: CI completo verde no commit de merge.
3. Merge com MERGE COMMIT (não squash): dev e main mantêm história comum;
   com squash, o próximo PR dev → main reapresenta todos os commits.
4. Release candidate (opcional, recomendado em release com migração):
     gh release create v1.4.0-rc.1 --target main --prerelease --generate-notes
   → deploy-prod.yml roda até o build (imagens 1.4.0-rc.1, Flutter com endereços de prod),
     NÃO implanta.
5. Release:
     gh release create v1.4.0 --target main --generate-notes
   (ou git tag -a v1.4.0 -m "Release v1.4.0" origin/main && git push origin v1.4.0)
6. deploy-prod.yml:
   a. gate-origem  → o commit da tag é ancestral de origin/main; senão aborta
   b. gate-ci      → workflow CI concluiu success nesse SHA (já existe)
   c. build-*      → todas as imagens com tag 1.4.0 (sem latest)
   d. deploy (runner VPS, env "prod" → espera aprovação do dono):
        - pg_dump validado (já existe; usuário/banco lidos do prod.env — L6)
        - materializa prod.env; monta bundle /opt/smartcore/prod/releases/v1.4.0/
        - infra/deploy/deploy.sh prod v1.4.0
        - infra (borda, observabilidade, Evolution, releases): só se o hash da
          config ou a versão da imagem mudou em relação ao que está no ar
        - smoke da borda, smoke dos serviços (incluindo mcp_server, web, site — L7)
   e. pós-deploy: abre PR main → dev se main tiver commit que dev não tem
      (substitui o pr-to-main.yml invertido; só acontece após hotfix).
```

### 4.3 Hotfix

```
1. git switch -c hotfix/descricao origin/main
2. Correção + teste. PR hotfix/descricao → main. CI verde. Merge.
3. gh release create v1.4.1 --target main      (não -hotfix.1: ver correção 13)
4. deploy-prod.yml igual ao normal (com aprovação).
5. O job pós-deploy abre PR main → dev. Merge com merge commit (backport).
   Se a dev tiver mudado o mesmo trecho, resolver conflito no PR, nunca na main.
```

### 4.4 Infra compartilhada fora de release

`deploy-infra.yml` com `workflow_dispatch` (entrada: `componente` = edge |
observability | evolution | releases), `environment: prod` (mesma aprovação),
roda a partir da `main`. Serve para trocar config da borda ou da observabilidade
sem cortar uma versão nova da aplicação. Não há disparo automático por push na
`main` (decisão do pedido: "main → nada automático").

---

## 5. Estrutura de diretórios

### 5.1 No servidor

```
/opt/smartcore/
├── dev/
│   ├── env/dev.env                 # materializado pelo deploy (600, gh-runner); NÃO editar à mão
│   ├── releases/
│   │   ├── <sha>/                   # bundle: compose.yml, compose.override.yml, backup/, init-scripts/,
│   │   │                            #         images.env, RELEASE (sha, data, run id)
│   │   └── current -> <sha>
│   ├── deploys.log                  # marcadores de deploy/rollback (promtail lê)
│   └── backups/                     # dumps do pg_backup (bind) — hoje em volume, migra na Fase R2
├── prod/
│   ├── env/prod.env
│   ├── releases/{v1.4.0,v1.3.2,…,current}
│   ├── deploys.log
│   └── backups/                     # pg_dump pré-deploy + pg_backup periódico (+ cópia externa, C4)
├── infra/
│   ├── edge/releases/<versão>/
│   ├── observability/{env/observability.env, releases/<hash>/}
│   ├── evolution/releases/<versão>/
│   └── releases/{env/releases.env, data/}   # dados do feed (hoje /opt/smartcore/releases-data)
├── ops/smart-core-assistant-v2/     # clone de leitura (espelho da dev) — nunca sobe compose daqui
└── _legado/                         # tudo da era systemd e restos, até ser apagado com aprovação
```

Retenção de bundles: 5 em dev, 10 em prod (texto pequeno; o que pesa são as
imagens, que ficam no GHCR).

### 5.2 Limpeza do legado (com aprovação, Fase R6)

Mover para `_legado/` (não apagar de início): `dev/.env*`, `dev/bin*`,
`prod/.env*`, `prod/releases/v0.1.0` (binários systemd — o novo
`prod/releases/` passa a guardar bundles), `prod/db-backup-v0.1.0-*.dump`,
`releases/` (mock Python), `Caddyfile.novo`, `site/`, `releases-stack/`.
Volumes órfãos `smart-core-v2-dev_evolution_*` e
`smart-core-v2-dev_postgres_evolution_data`: conferir que o Evolution atual usa
`smart-core-v2-evolution_*`, fazer dump e só então remover, com pedido explícito.

### 5.3 No repositório

```
docker/
├── stack/compose.yml            # BASE única da aplicação (hoje dev/compose.yml + prod/compose.yml)
├── dev/compose.override.yml     # diferenças da seção 3.3
├── dev/.env.example
├── prod/compose.override.yml
├── prod/.env.example            # completo (L2, L3 do go-live) + lista REQUIRED_KEYS
├── edge/ observability/ evolution/ releases/ site/   # inalterados na forma
├── backup/ init-scripts/        # copiados para o bundle, nunca montados da workspace
infra/deploy/
├── deploy.sh                    # deploy.sh <dev|prod> <id>  (usado por deploy-*, rollback)
├── bundle.sh                    # monta o bundle a partir do checkout
├── smoke.sh                     # smoke dos serviços e da borda (hoje duplicado nos YAML)
└── required-keys.{dev,prod}     # chaves obrigatórias por ambiente
.github/workflows/
├── ci.yml                       # + caddy validate + compose config + shellcheck
├── deploy-dev.yml               # reescrito (4.1)
├── deploy-prod.yml              # reescrito (4.2)
├── deploy-infra.yml             # novo (4.4)
├── rollback-prod.yml            # novo (9.2)
├── abrir-release.yml            # novo, opcional (PR dev → main com changelog)
└── pr-to-main.yml               # REMOVIDO
doc_dev/runbooks/RUNBOOK_DEPLOY.md
```

---

## 6. Compose base + overlay (trechos)

### 6.1 `docker/stack/compose.yml` (base, recortes)

```yaml
# Base da aplicação. NÃO tem `name:` — o projeto vem de -p no deploy.sh
# (smart-core-v2-dev | smart-core-v2-prod). Bind mounts são relativos ao
# BUNDLE, nunca à workspace do runner.
x-server-image: &server-image ghcr.io/pwlimaverde/smart-core-assistant-v2/smartcore-server:${SERVER_TAG:?SERVER_TAG ausente}

x-logging: &logging
  driver: json-file
  options: { max-size: "${LOG_MAX_SIZE:-20m}", max-file: "${LOG_MAX_FILES:-5}" }

x-rpc-health: &rpc-health
  interval: 20s
  timeout: 5s
  retries: 3
  start_period: 30s

services:
  postgres:
    image: pgvector/pgvector:pg16
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro    # ./ = bundle
    networks: [internal]
    restart: unless-stopped
    logging: *logging
    mem_limit: ${MEM_POSTGRES:?}

  data_postgres:
    image: *server-image
    environment:
      SMARTCORE_ENV: ${SMARTCORE_ENV:?}
      OTEL_SERVICE_NAMESPACE: ${OTEL_SERVICE_NAMESPACE:?}
      # ...
    networks: [internal, telemetria]
    healthcheck:
      <<: *rpc-health
      # mantém a sonda dupla atual do data_postgres (copiada sem alteração)
      test: ["CMD", "healthcheck", "rpc", "DATA_POSTGRES"]
    restart: unless-stopped
    logging: *logging
    mem_limit: ${MEM_DATA_POSTGRES:?}

  ia_engine:
    image: ghcr.io/pwlimaverde/smart-core-assistant-v2/smartcore-ia-engine:${IA_ENGINE_TAG:?}
  # ... demais serviços idênticos aos atuais, com tag por variável

networks:
  internal: {}
  telemetria:            # C1 do go-live: rede de telemetria POR AMBIENTE
    name: ${TELEMETRIA_NET:?}
    external: true
  evolution_net:
    name: smart_core_v2_evolution_net
    external: true

volumes:
  postgres_data: {}
  redis_data: {}
  redis_bus_data: {}
  pg_backups: {}
```

Regra: `:?` em toda variável que muda por ambiente. Um `.env` incompleto
falha no `compose config`, antes de qualquer container ser tocado — em vez do
default silencioso que hoje faz a prod cair em `:latest`.

### 6.2 `docker/dev/compose.override.yml`

```yaml
services:
  minio:
    image: quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z
    pull_policy: missing
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:?}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:?}
    volumes: [minio_data:/data]
    networks: [internal]
    restart: unless-stopped
    mem_limit: 512m
  minio-setup:
    # ... (igual ao atual)
  data_storage:
    depends_on:
      minio-setup: { condition: service_completed_successfully }
  runtime_api:
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:50051:50051"]
  web:
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:8081:80"]
  web-tenant:
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:8083:80"]
  # SEM portas de Postgres/Redis no host: o túnel do ambiente local deixa de existir.

volumes:
  minio_data: {}
```

### 6.3 `docker/prod/compose.override.yml`

```yaml
services:
  runtime_api:
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:50052:50051"]
  web:
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:8082:80"]
  # web-tenant: sem porta enquanto a web do tenant estiver fechada (A12 do go-live)
  site:
    image: ghcr.io/pwlimaverde/smart-core-assistant-v2/smartcore-site:${SITE_TAG:?}
    ports: ["${HOST_BRIDGE_IP:-172.17.0.1}:8085:80"]
    networks: [internal]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1/"]
      interval: 30s
      timeout: 5s
      retries: 3
    mem_limit: 64m
  pg_backup:
    environment:
      BACKUP_INTERVALO_SEGUNDOS: ${BACKUP_INTERVALO_SEGUNDOS:-43200}
      BACKUP_RETENCAO_DIAS: ${BACKUP_RETENCAO_DIAS:-30}
```

### 6.4 Comando efetivo (dentro do `deploy.sh`)

```bash
docker compose -p "smart-core-v2-${ENV}" \
  --project-directory "$BUNDLE" \
  -f "$BUNDLE/compose.yml" -f "$BUNDLE/compose.override.yml" \
  --env-file "/opt/smartcore/${ENV}/env/${ENV}.env" \
  --env-file "$BUNDLE/images.env" \
  up -d --remove-orphans
```

Ao trocar o projeto da dev para a base nova, o nome de projeto
(`smart-core-v2-dev`) e os nomes de volume (`postgres_data`, …) **não mudam**:
os volumes com dados são reaproveitados. Conferir com `compose config` antes do
primeiro `up` (Fase R2).

---

## 7. Versionamento

| Item | Regra |
|---|---|
| Esquema | SemVer `MAJOR.MINOR.PATCH` na tag git `vX.Y.Z`; imagens sem o `v` (`X.Y.Z`) |
| MAJOR | Quebra de contrato com o app Windows instalado ou migração que exige ação manual |
| MINOR | Funcionalidade nova compatível |
| PATCH | Correção, inclusive hotfix |
| RC | `vX.Y.Z-rc.N`, sempre em commit da `main`; build sem deploy |
| Origem | Tag só em commit alcançável por `origin/main` — verificado no workflow e protegido por ruleset |
| Quem cria | Pessoa na lista de bypass do ruleset de tag (o dono) |
| Imutabilidade | Tag publicada não se move nem se apaga; correção = nova versão PATCH |
| App Windows | Ciclo independente (`win-vX.Y.Z`), já tratado no go-live; o servidor sobe antes do app que depende dele |
| Imagens dev | `sha-<curto>` (imutável) + `dev` (móvel, só referência humana; o compose nunca usa) |
| Retenção GHCR | Tags `X.Y.Z`: todas. `sha-*`: 30 dias, mínimo 20 versões. `-rc.*`: 60 dias |

---

## 8. Segredos e variáveis

### 8.1 Onde vive cada coisa

| Segredo | Local canônico | Chega ao servidor por |
|---|---|---|
| Arquivo de ambiente da dev | Secret de ambiente `ENV_FILE_B64` no environment **`dev`** | `deploy-dev.yml` → `/opt/smartcore/dev/env/dev.env` |
| Arquivo de ambiente da prod | Secret de ambiente `ENV_FILE_B64` no environment **`prod`** | `deploy-prod.yml` → `/opt/smartcore/prod/env/prod.env` |
| Observabilidade | Secret `OBS_ENV_FILE_B64` no environment `prod` | `deploy-prod.yml`/`deploy-infra.yml` |
| Evolution | chaves dentro do `prod.env` (já é assim no `dev.env`) | idem |
| Releases | Secret `RELEASES_ENV_FILE_B64` no environment `prod` | idem |
| GHCR | `GITHUB_TOKEN` | — |
| Upload de release / assinatura | Já existentes; migram para environment conforme C6/A13 do go-live | — |

Cópia de recuperação: o dono guarda o `.env` de prod também fora do GitHub
(cofre de senhas), por causa da `ENCRYPTION_KEY` (sem ela os dados cifrados
no banco se perdem).

### 8.2 Materialização (dentro do `deploy.sh`)

```bash
# ENV_FILE_B64 entra pelo `env:` do passo, nunca interpolado no script.
umask 077
destino="/opt/smartcore/${ENV}/env/${ENV}.env"
tmp="$(mktemp "${destino}.XXXXXX")"
if ! printf '%s' "${ENV_FILE_B64:?}" | base64 -d > "$tmp"; then
  rm -f "$tmp"; echo "::error::ENV_FILE_B64 inválido"; exit 1
fi
# Chaves obrigatórias (nomes apenas; valores nunca vão ao log)
faltando=$(grep -vxF -f <(cut -d= -f1 "$tmp") "infra/deploy/required-keys.${ENV}" || true)
if [ -n "$faltando" ]; then
  rm -f "$tmp"; echo "::error::chaves ausentes: $(echo $faltando)"; exit 1
fi
# Proibidas (lista do go-live §4.4): COMPOSE_PROJECT_NAME, MINIO_* na prod, portas de banco
if grep -qE '^COMPOSE_PROJECT_NAME=' "$tmp"; then rm -f "$tmp"; echo "::error::COMPOSE_PROJECT_NAME proibido"; exit 1; fi
mv -f "$tmp" "$destino"
echo "env materializado: ${ENV} ($(grep -c '=' "$destino") chaves)"
```

### 8.3 Rotação

1. Editar o arquivo no cofre do dono.
2. `base64 -w0 prod.env | gh secret set ENV_FILE_B64 --env prod`.
3. Rodar `deploy-infra.yml` ou um redeploy da versão atual (`rollback-prod.yml`
   com a versão corrente faz exatamente isso: reaplica env e `up -d`).

A regra "fonte do ambiente é `/opt/smartcore/dev/env/dev.env`" do `CLAUDE.md`
do projeto passa a ser "fonte é o secret do environment; o arquivo no servidor
é cópia materializada" — atualizar o `CLAUDE.md` e o `development-workflow.md`
na Fase R3.

---

## 9. Rollback e recuperação

### 9.1 Dev
- Deploy com smoke vermelho não troca o `current`; os containers podem ter
  sido recriados. Recuperação automática: o `deploy.sh` reaplica o bundle
  `current` (anterior) quando o smoke falha.
- Correção definitiva: `git revert` na `dev` → novo deploy. Nunca force-push.

### 9.2 Prod — `rollback-prod.yml`

`workflow_dispatch` com entrada `versao` (ex.: `1.3.2`), `environment: prod`
(aprovação). Passos:

1. Confere que `/opt/smartcore/prod/releases/v1.3.2/` existe e que as imagens
   `:1.3.2` existem no GHCR (`docker manifest inspect`).
2. **Portão de migração**: compara a lista de migrações do bundle alvo com a
   do `current`. Se a versão atual aplicou migração que a alvo não conhece,
   o job **para** e exige a entrada `aceito_migracao=sim` + leitura do runbook
   (as 53 migrações são só para frente).
3. `pg_dump` validado (mesmo passo do deploy).
4. `deploy.sh prod v1.3.2` (reaplica env, `up -d`, smoke, troca `current`).
5. Marcador `event=rollback` no `deploys.log` e anotação no Grafana.

Tempo esperado: 2–4 min (imagens já em disco ou no GHCR, sem build).

### 9.3 Política de migração (pré-requisito do rollback barato)

- Migração **expand/contract**: a versão N adiciona (coluna/tabela nova,
  nullable); a N+1 passa a usar; a N+2 remove o velho. Assim N−1 roda contra
  o schema de N.
- PR que traz migração destrutiva (DROP, RENAME, NOT NULL sem default) leva o
  rótulo `migracao-destrutiva`; o PR `dev → main` lista essas migrações; para
  essas releases, rollback = **restauração de dump** (perda do que entrou
  depois do backup) ou correção para frente.

### 9.4 Desastre (VPS perdida)
Fora do escopo principal (go-live C4/D1), mas este plano deixa o caminho
pronto: com os `.env` no GitHub/cofre, as imagens no GHCR e os bundles
reproduzíveis do git, uma VPS nova precisa de Docker, runner, restauração do
dump externo e um `rollback-prod.yml` para a versão atual.

---

## 10. Fases de execução

Cada fase entra por branch `feature/` → PR → `dev`; nada é testado na máquina
do desenvolvedor nem compilado na VPS. "Dono" = ação manual sua.

### Fase R0 — Levantamento (concluída nesta sessão)
- **Entregue:** inventário do servidor, GitHub e repositório (`info_aux` §1).
- **Observabilidade & Auditoria:** (a) sem log novo; (b) sem evento de
  auditoria; (c) nenhuma chave ou valor de `.env` lido ou exibido — só nomes,
  tamanhos e permissões.

### Fase R1 — Governança Git (pré-requisito de tudo; ~0,5 dia)
- **Dono:**
  1. Ruleset da `main`: exigir PR, checks obrigatórios (`CI / Rust`, `CI / Python`,
     `CI / Flutter`, `CI / Infra`), bloquear force-push e exclusão, 0 aprovações.
  2. Ruleset da `dev`: bloquear force-push e exclusão; exigir CI verde no PR.
  3. Ruleset de tag `v*`: criação/alteração/exclusão só pelo dono (bypass).
  4. Environment `prod`: revisor obrigatório = dono; política de implantação
     já restrita a tags `v*` (mantém); adicionar o secret `ENV_FILE_B64`
     (Fase R3).
  5. Primeiro merge `dev → main` (797 commits) por PR com **merge commit**.
- **IA:**
  1. `deploy-prod.yml`: `environment: production` → `environment: prod`
     (**corrige o defeito 1; fazer antes de qualquer tag**).
  2. Job `gate-origem`: `git merge-base --is-ancestor "$GITHUB_SHA" origin/main`.
  3. Remover `pr-to-main.yml`; criar o job pós-deploy que abre PR `main → dev`
     quando houver divergência.
  4. Atualizar `development-workflow.md` (fluxo novo; `release/*` some —
     a `main` cumpre esse papel).
- **Conclusão:** uma tag `v0.0.0-rc.1` de teste em commit fora da `main` é
  recusada pelo `gate-origem`; push direto na `main` é recusado.
- **Observabilidade & Auditoria:** (a) trilha = histórico de deployments do
  environment no GitHub; (b) sem evento de `audit_log`; (c) sem segredo.

### Fase R2 — Compose base + overlay (~2 dias)
- **IA:**
  1. `docker/stack/compose.yml` a partir do `dev/compose.yml` (o mais completo),
     com tags por variável e `:?` nas variáveis de ambiente.
  2. Overlays dev e prod (§6). `.env.example` de cada ambiente completos (L2/L3)
     e `infra/deploy/required-keys.{dev,prod}`.
  3. CI: `docker compose -f stack -f dev/override config -q` e o mesmo para prod,
     com um `.env` de exemplo; falha se aparecer `:latest` em imagem de aplicação.
  4. Prova de equivalência: `compose config` da base+overlay dev **igual** ao
     `compose config` do `docker/dev/compose.yml` atual, exceto as diferenças
     intencionais (portas de banco, tags). O diff vai no PR.
  5. Apagar `docker/dev/compose.yml` e `docker/prod/compose.yml` só depois
     de a dev rodar estável na base nova por 48 h.
- **Risco:** médio (mexe na dev em uso). Mitigação: item 4; volumes com o mesmo
  nome; dump da dev antes do primeiro `up`.
- **Observabilidade & Auditoria:** (a) `SMARTCORE_ENV`/`OTEL_SERVICE_NAMESPACE`
  passam a vir do overlay — conferir no Loki que os logs da dev chegam com
  `env=dev` (corrige M9 do go-live); (b) sem evento de auditoria; (c) `.env.example`
  só com placeholders.

### Fase R3 — Bundle, script único e segredos (~2 dias)
- **IA:**
  1. `infra/deploy/bundle.sh`: copia compose, override, `backup/`,
     `init-scripts/` para `/opt/smartcore/<env>/releases/<id>/`; grava
     `images.env` e `RELEASE`.
  2. `infra/deploy/deploy.sh <env> <id>`: materializa env (§8.2) → `compose config`
     → `pull` → `up -d --remove-orphans` → `smoke.sh` → troca `current` (ou
     reaplica o anterior se o smoke falhar) → marcador → poda de bundles.
  3. `infra/deploy/smoke.sh`: unifica os dois smoke tests de hoje e inclui
     `mcp_server`, `web`, `site` (L7). Smoke de Redis da config mantido.
  4. `shellcheck` na CI para `infra/deploy/*.sh`.
- **Dono:** gerar `ENV_FILE_B64` dos environments `dev` e `prod` a partir do
  `dev.env` atual e do `prod.env` novo (go-live F5).
- **Conclusão:** um deploy da dev cria o bundle e o `pg_backup` passa a montar
  `backup.sh` do bundle (`docker inspect` mostra o caminho em
  `/opt/smartcore/dev/releases/...`, não em `_work`).
- **Observabilidade & Auditoria:** (a) linha `event=deploy` com `env`,
  `version`, `sha`, `run_id`, `status`, `duracao_s` em `deploys.log`; promtail
  com job `deploys` → consulta e anotação no Grafana; (b) sem evento de
  `audit_log` (não é ação de usuário da aplicação); (c) `ENV_FILE_B64` só via
  `env:`; decodificado nunca impresso; sem `set -x`; `umask 077`.

### Fase R4 — Fim do ambiente local (~1 dia)
- **IA:**
  1. `test_support`: remover `ensure_tunnel`/`iniciar_tunnel`; sem banco na
     porta, o teste de integração falha com mensagem clara ("rode na CI").
  2. Mover para `infra/_legado/` (ou apagar): `tunnel.ps1`, `tunnel.sh`,
     `test-local.ps1`, `test-quick.ps1`, `test-flutter.ps1`, `clean-target.ps1`,
     `create-superuser.ps1`, `delete-superuser.ps1`, `backup-envs.ps1`.
     Superusuário passa a ser criado por `workflow_dispatch` no environment do
     ambiente (job que roda o binário de admin dentro do container).
  3. Overlay da dev sem portas 5434/6380/6381 no host (§6.2).
  4. Docs: `tooling.md`, `testing-strategy.md`, `architecture.md`,
     `development-workflow.md`, `CLAUDE.md` do projeto: "não há ambiente local;
     a máquina do desenvolvedor edita, faz push e lê logs no Grafana".
  5. Apagar `server/.env` do clone do VPS (aponta para túnel inexistente) — com
     aprovação, pois é arquivo fora do git.
- **Conclusão:** `grep -ri tunnel server/ infra/ .context/docs` sem ocorrência
  ativa; CI verde.
- **Observabilidade & Auditoria:** (a) sem mudança; (b) sem evento; (c) remove
  uma rota de acesso direto ao banco (melhora a postura).

### Fase R5 — Workflows reescritos (~2 dias)
- **IA:**
  1. `deploy-dev.yml` conforme 4.1: sem borda, sem Evolution, sem
     observabilidade; tag `sha-*`; `images.env` herdando tags não
     reconstruídas.
  2. `deploy-prod.yml` conforme 4.2: gates, build completo `X.Y.Z` (sem
     `latest`), RC sem deploy, infra condicional por hash, PR `main → dev`
     pós-deploy.
  3. `deploy-infra.yml` (4.4) e `rollback-prod.yml` (9.2).
  4. Borda: imagem `smartcore-edge:X.Y.Z` construída só no fluxo de prod;
     `caddy validate` na CI de todo PR que toca `docker/edge`.
  5. Retenção GHCR (`actions/delete-package-versions`) agendada semanalmente.
  6. `concurrency` único `deploy-vps` para dev, prod, infra e rollback (o host
     é um só: dois `compose pull` simultâneos disputam disco e memória).
- **Conclusão:** push na `dev` não recria `smart-core-v2-edge`,
  `-observability` nem `-evolution` (conferir `docker ps` → `Up` inalterado).
- **Observabilidade & Auditoria:** (a) `GITHUB_STEP_SUMMARY` com versão,
  imagens e resultado do smoke; marcador no `deploys.log`; (b) sem evento de
  `audit_log`; (c) `docker logs --tail 50` no smoke — mesmo limite de hoje.

### Fase R6 — Ensaio e corte (~1 dia + 48 h de observação)
Depende do go-live C1, C2, C3 e F5 (prod.env) prontos.
- **IA + Dono:**
  1. `v1.0.0-rc.1` na `main` → build sem deploy, conferir imagens e bundles.
  2. Primeira tag `v1.0.0` → aprovação → prod no ar (é a Fase 9 do go-live).
  3. Ensaio de rollback: `v1.0.1` trivial → `rollback-prod.yml` para `1.0.0`
     → medir tempo; repetir para `1.0.1`.
  4. Ensaio de hotfix completo (4.3) com PR `main → dev` automático.
  5. Limpeza do legado (§5.2) com aprovação explícita item a item.
- **Conclusão:** checklist da seção 13 todo marcado.
- **Observabilidade & Auditoria:** (a) painel "Deploys" no Grafana com os
  marcadores dos dois ambientes; (b) sem evento de `audit_log`; (c) conferir
  no Loki que nenhuma linha do job de deploy contém valor de `.env`
  (busca pelos 4 primeiros caracteres de cada segredo, feita pelo dono).

### Fase R7 — Documentação (~0,5 dia)
- `doc_dev/runbooks/RUNBOOK_DEPLOY.md`: deploy dev, release, RC, hotfix,
  rollback, rotação de segredo, infra, recuperação de desastre.
- `.context/docs/architecture.md` (topologia de ambientes),
  `development-workflow.md`, `security.md` (segredos por environment),
  `tooling.md`; `CLAUDE.md` do projeto e o global da VPS (remover menções à v1
  no ar e a `/opt/smartcore/prod/env/` "vazio").
- `infra/RUNBOOK_CUTOVER_PROD.md` marcado como histórico.

---

## 11. Checklist de implementação (arquivos)

| Arquivo | Ação | Fase |
|---|---|---|
| `.github/workflows/deploy-prod.yml` | `environment: prod`; gate de origem; reescrita | R1, R5 |
| `.github/workflows/pr-to-main.yml` | remover | R1 |
| `.github/workflows/deploy-dev.yml` | reescrever | R5 |
| `.github/workflows/deploy-infra.yml` | criar | R5 |
| `.github/workflows/rollback-prod.yml` | criar | R5 |
| `.github/workflows/abrir-release.yml` | criar (opcional) | R5 |
| `.github/workflows/ci.yml` | + `compose config`, `caddy validate`, `shellcheck`, proibição de `:latest` | R2, R3, R5 |
| `docker/stack/compose.yml` | criar (base) | R2 |
| `docker/dev/compose.override.yml`, `docker/prod/compose.override.yml` | criar | R2 |
| `docker/dev/.env.example`, `docker/prod/.env.example` | completar | R2 |
| `docker/dev/compose.yml`, `docker/prod/compose.yml` | remover após 48 h estável | R2 |
| `docker/releases/compose.yml`, `docker/site/compose.yml` | `name:` padronizado, imagem por versão | R5 (com go-live F3/F8) |
| `infra/deploy/{deploy,bundle,smoke}.sh`, `required-keys.*` | criar | R3 |
| `server/crates/test_support/src/lib.rs` | remover túnel | R4 |
| `infra/*.ps1` locais, `infra/tunnel.sh` | mover para `_legado/` | R4 |
| `doc_dev/runbooks/RUNBOOK_DEPLOY.md` | criar | R7 |
| `.context/docs/*.md`, `CLAUDE.md` | atualizar | R1, R4, R7 |

---

## 12. Riscos e mitigações

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| **Memória**: soma dos tetos dev+prod ≈ 19 GiB numa VPS de 7,8 GiB; uso real hoje ~2,1 GiB só com dev | Alta | Alto (OOM derruba prod) | Medir na R6 com a prod no ar; tetos da dev menores (ia_engine 1g, jev 768m); `concurrency` único de deploy; alerta de memória do host (go-live A8); decisão D1 (VPS maior ou dev fora) antes do go-live |
| Primeiro merge `dev → main` com 797 commits | Certa | Médio | Merge commit, sem squash; nenhuma alteração direta na `main` antes dele |
| Troca de compose quebra a dev (nome de volume/projeto) | Média | Médio | Prova de equivalência por `compose config`; dump antes; volumes com o mesmo nome |
| Secret de ambiente desatualizado sobrescreve correção feita à mão no servidor | Média | Médio | Regra: nunca editar `.env` no servidor; rotação só pelo secret (§8.3) |
| Rollback com migração não compatível | Média | Alto | Expand/contract; portão de migração no `rollback-prod.yml`; dump pré-deploy |
| Runner único, `gh-runner` no grupo `docker` (= root) para dev e prod | Certa | Alto | Revisor no env `prod`; tags protegidas; runner separado para prod é D3 do go-live |
| Infra compartilhada só muda com aprovação de prod → atrito para ajustar a observabilidade da dev | Alta | Baixo | `deploy-infra.yml` sem precisar de release |
| Tag criada por automação não dispara deploy | Média | Baixo | Tag sempre por pessoa (`gh release create`) |
| Bundle ocupa disco | Baixa | Baixo | Texto puro; poda 5/10 |
| Deploy da dev e da prod simultâneos | Baixa | Médio | `concurrency: deploy-vps` |
| Divergência com o plano `producao-go-live` | Média | Médio | Seção 1 (fronteira explícita); atualizar o canônico do go-live com o ponteiro para este plano |

---

## 13. Validação do plano

| Ponto pedido | Atendido por |
|---|---|
| Nenhum "local" na arquitetura | Fase R4 (túnel, scripts, portas e docs removidos) |
| CI/CD 100% automático (merge na dev, tag na prod) | 4.1 e 4.2; a única ação humana na prod é criar a tag e aprovar o environment |
| Separação dev/prod (env, volumes, recursos) | Projetos e volumes por ambiente; env por environment; overlay com tetos próprios; redes de telemetria por ambiente (go-live C1) |
| Rollback e recuperação documentados | Seção 9 + `rollback-prod.yml` + RUNBOOK_DEPLOY |
| Tags vX.Y.Z só a partir da main | `gate-origem` no workflow + ruleset de tag + política do environment |
| Segredos via GitHub, nunca no repo | Secrets de environment `ENV_FILE_B64`; `.env.example` só com placeholders |
| Observabilidade em dev e prod | Stack compartilhada com rótulo `env` e marcador de deploy por ambiente |
| Backups automáticos (prod) | `pg_backup` periódico + `pg_dump` pré-deploy validado; cópia externa é C4 do go-live |

---

## 14. Cronograma

| Fase | Esforço | Depende de | Pode rodar em paralelo com |
|---|---|---|---|
| R0 Levantamento | feito | — | — |
| R1 Governança Git | 0,5 dia | — | — |
| R2 Compose base + overlay | 2 dias | R1 | R4 |
| R3 Bundle, script, segredos | 2 dias | R2 | R4 |
| R4 Fim do local | 1 dia | R1 | R2, R3 |
| R5 Workflows | 2 dias | R3 | — |
| R6 Ensaio e corte | 1 dia + 48 h | R5 + go-live C1–C3, F5 | — |
| R7 Documentação | 0,5 dia | R6 | — |
| **Total** | **~9 dias úteis de trabalho** + 48 h de observação | | |

**Fazer já, independente do resto:** R1 item IA-1 (`environment: prod`). É
uma linha e fecha o caminho de uma tag acidental ir para produção sem
aprovação.

---

## 15. Decisões do dono

| ID | Decisão | Recomendação |
|---|---|---|
| R-D1 | Aceitar que a borda, a observabilidade, o Evolution e o releases só mudem pelo fluxo de prod (ou `deploy-infra.yml` com aprovação) | Sim |
| R-D2 | Secret de environment como fonte do `.env` (em vez do arquivo no servidor) | Sim, com cópia no cofre |
| R-D3 | Merge commit em `dev → main` e `main → dev` | Sim |
| R-D4 | RC obrigatório para release com migração | Sim |
| R-D5 | Apagar (em vez de arquivar) os scripts locais `.ps1` | Arquivar em `infra/_legado/` por um ciclo, depois apagar |
| R-D6 | Política expand/contract para migrações | Sim — é o que torna o rollback barato |
