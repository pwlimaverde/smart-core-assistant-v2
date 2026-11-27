# Plano — Conversão do Smart Core Assistant v2 para produção (go-live)

> Revisão 3, de 24/11/2026, sobre a branch `dev` (commit `0af1fd23`), com o
> inventário real do servidor de 23–24/11/2026. A revisão 2 (14/11/2026,
> commit `239e6239`) foi escrita **sem acesso ao servidor** e antes do plano
> `servidor-reestruturacao-dev-prod`; a seção R3 abaixo diz o que dela ficou
> superado. As seções 2.1 a 2.4 descrevem o desenho de 14/11 e ficam como
> histórico; o estado vigente é o da seção R3.
> Plano canônico: `.context/plans/producao-go-live.md`.
> Documentação auxiliar: `.context/plans/producao-go-live/info_aux_producao-go-live.md`.
> Fonte: leitura do repositório (compose, workflows, scripts, runbooks, código),
> inventário do servidor e documentação pública do Velopack e da Microsoft.

## R3. Estado real em 24/11/2026 e o que mudou desde a revisão 2

### R3.1 Servidor

| Item | Estado |
|---|---|
| Produção | `smart-core-v2-prod` **no ar** desde 22/11/2026 (`v0.2.1`), hoje `v0.2.2`, implantada por tag `vX.Y.Z` na `main` com aprovação no environment `prod` |
| Dev | `smart-core-v2-dev`, `0.2.4-beta.N`, implantada a cada push na `dev` |
| Composes | `docker/dev` e `docker/prod` **removidos**; as duas stacks saem de `docker/stack/` (`docker-compose.base.yml` + `dev.override.yml`/`prod.override.yml` + `dev.vars`/`prod.vars`), por bundle em `/opt/smartcore/<env>/releases/current` |
| Env | Secret `ENV_FILE_B64` do environment → `/opt/smartcore/<env>/env/<env>.env`; chaves obrigatórias em `infra/deploy/required-keys.<env>` |
| Infra compartilhada | Borda, observabilidade e Evolution só mudam por `deploy-infra.yml` (push na `main` ou dispatch, com aprovação de prod) |
| Servidor de releases | Projeto compose `releases-stack` (`/opt/smartcore/releases-stack`), subido à mão, imagem `:latest`; **fora** do `deploy-infra.yml` |
| Site | Imagem `smartcore-site:local` construída à mão, container **sem projeto compose** |
| Containers | 49 no total |
| Memória | VM de 7,8 GiB; uso real ≈ 1,5 GiB; **soma dos tetos ≈ 13 GiB** (prod ≈ 7,6 GiB, observabilidade ≈ 2,8 GiB, mais a dev). Proteção vigente: `oom_score_adj` dev 900, observabilidade 300, prod 0 (D1) |
| `web-tenant` | De pé na prod (o `docker-compose.base.yml` não tem perfil para ele), contrariando a web fechada |
| MinIO | Só na dev (`dev.override.yml`); a prod usa R2 |
| Socket do Docker | Montado em 3 pontos: `watchdog` da dev, `watchdog` da prod (`docker-compose.base.yml:609`) e `docker-socket-proxy` da observabilidade |
| Backup | Só local (`pg_backup` no mesmo disco); sem cópia externa |
| Restos | **Limpos em 24/11 (D24)**: 5 volumes sem uso, redes `smartcore_v2_network` e `smart-core-site_default`, cron de `caddy reload`, `cargo clean` em caminho inexistente, `renew-ssl.sh` da v1 e o prune diário de 24 h (fica o semanal de 168 h). Backup e lista em `/root/backups/2026-11-24-limpeza-d24/`. A rede `compose_agritech-backends` é de outro sistema e foi mantida |
| Acesso remoto | `claude-rc` (systemd) como root, `--permission-mode bypassPermissions`, `IS_SANDBOX=1`, checkout `/opt/smartcore/ops/smart-core-assistant-v2` espelho da `dev` |

### R3.2 Afirmações da revisão 2 que não valem mais

| Afirmação da revisão 2 | Realidade em 24/11 | Ação nesta revisão |
|---|---|---|
| A produção "nunca subiu" (0.2, 2.4) | No ar desde 22/11 (`v0.2.1` → `v0.2.2`) | Corrigido; F9 marcada como feita |
| "Não subir `docker/prod` como está" (8.2 item 1) | `docker/prod` não existe; prod sai de `docker/stack/` | Item reescrito |
| O servidor não foi acessado; Fase 0 a fazer | Inventário feito em 23–24/11 | F0 marcada como feita |
| C1, C2, C3 abertos | Resolvidos (`OBS_NET` por ambiente; `WEBHOOK_INGRESS_URL` com prod em `172.17.0.1:9211` fora da `evolution_net`; portas dev 8095/8099/9210 e prod 8096/8100/9211) | Marcados como resolvidos; a prova com instância `prod-` fica na F7 |
| A borda de produção muda por push na `dev` (L8, A4, item 18 de 8.2) | Borda só por `deploy-infra.yml`; `caddy validate` na CI e no deploy de infra | L8/A4 resolvidos; item 18 reescrito |
| Produção em `:latest`; rollback reconstrói tudo (L4, A5) | Prod promove o digest da beta testada; `rollback-prod.yml` por versão | Resolvidos para a stack de aplicação; releases e site seguem em imagem local/`latest` |
| Tag sai de qualquer branch (L5) | `gate-origem` e ruleset de tags `vX.Y.Z` | Resolvido (para o servidor; o app Windows segue em C6) |
| Deploy de prod sem validar chaves; `pg_dump` fixo (L1, L6) | `required-keys.prod`; `deploy.sh` lê usuário e banco do env | Resolvidos |
| `mcp_server`, `web`, `web-tenant` fora do smoke (L7) | `infra/deploy/smoke.sh` cobre | Resolvido |
| Deploy de prod recria a observabilidade (L9) | Não recria; infra só pelo `deploy-infra.yml` | Resolvido |
| `restore-postgres.sh` assume usuário e banco inexistentes (L11) | Apontava para `docker/<env>/compose.yml`, removido | **Resolvido em 24/11**: usa o bundle `current` e o env do ambiente pela `infra/deploy/lib.sh`; listagem e ensaio conferidos na dev |
| Soma dos tetos de prod ≈ 9,5 GB; D1 recomenda 16 GB | VM de 7,8 GiB, tetos somam ≈ 13 GiB, uso real ≈ 1,5 GiB; D1 decidida (mesma VPS, tetos + `oom_score_adj`) | 5.3, 7 e 8.1 atualizados; enxugar os tetos entra na F2B |
| Topologia proposta com `smart-core-v2-releases` implantado pelo `deploy-prod.yml` e borda pelo `deploy-prod.yml` (5.2) | Projeto real chama `releases-stack`; borda pertence ao `deploy-infra.yml` | 5.2 reescrita: releases entra no `deploy-infra.yml` |
| Observabilidade sem `mem_limit` (M7) | Teto e `oom_score_adj` 300 **no repositório** (`d2bb8e8e`, já na `main`), mas **não aplicados no servidor** em 24/11: os containers seguem com `oom_score_adj` 0 e sem teto, porque o `deploy-infra.yml` que os aplica (run `45091567804`) espera a aprovação do environment `prod` desde 23/11. Evolution ainda sem `mem_limit` | M7 reduzido ao Evolution e ao releases; aprovar o run pendente (ou novo dispatch da `main`) |
| RUSTSEC-2026-0459 pendente (M4) | Corrigido (`e76adaf2`, `libsqlite3-sys` 0.40) | M4 reduzido à auditoria bloqueante |
| D8 recomenda sessão root só na dev | O dono decidiu sessão root com permissão total no VPS que hospeda a prod | D8 registrada como decidida, com o risco |
| Webhook da prod "saindo da rede da prod" não existia no plano | `prod.override.yml` tira o `webhook_ingress` da prod da `evolution_net` (incidente do primeiro deploy, 250 eventos da dev entregues na prod) | Registrado em C2 |

### R3.3 O que continua aberto (resumo)

C4 (backup externo), C5 (segredos em `settings.local.json`), C6 (portões do
canal estável), A2/A3 (chave e prefixo do Evolution), A6/A7 (SSH e
`DOCKER-USER`, a conferir no inventário), A8 (métricas de host), A9 (destino
de alerta), A11 (certificado), A12 (web roteada na borda), A13 (token por
canal), L10–L14, M1, M8–M18 e o enxugamento do servidor (Fase 2B).

## 0. Resumo executivo

1. **O produto que vai a público é o aplicativo Windows.** A versão web
   (admin e tenant) **não será publicada agora**: fica fechada na borda até
   decisão do dono. Isso muda a borda de produção, que hoje já tem as rotas
   `/v2/admin` e `/v2/tenant` abertas (`docker/edge/Caddyfile:36-60`).
2. **A stack de servidor de produção está no ar** desde 22/11/2026
   (`smart-core-v2-prod`, hoje `v0.2.2`), por tag e aprovação, a partir de
   `docker/stack/` (seção R3). O go-live deste plano é a abertura ao público.
3. **Havia seis bloqueadores críticos; três seguem abertos.** Os três de
   isolamento entre dev e produção (nomes de serviço repetidos em redes
   compartilhadas, portas iguais no host, URL de webhook fixa no código) foram
   resolvidos pelo plano `servidor-reestruturacao-dev-prod`. Abertos: backup só no disco do banco; segredos
   expostos em arquivo local (confirmados nesta revisão); e **o canal estável do
   app Windows sem nenhum portão**: uma tag `win-vX.Y.Z` de qualquer branch
   publica no feed e todo aplicativo instalado se atualiza sozinho, sem pergunta.
4. **O instalador é marcado como suspeito pelo Windows porque o certificado é
   auto-assinado** (`infra/windows/README.md`). Resolver exige certificado de
   autoridade pública, e isso muda o passo de assinatura do pipeline: desde
   junho de 2023 a chave não pode mais ser exportada em PFX.
5. **O servidor de releases e o site público estão fora de qualquer deploy.**
   Um sobe à mão com imagem `:latest`; o outro é construído à mão no servidor
   (`smartcore-site:local`). Os dois entram no deploy de produção, por versão.
6. **A divisão em serviços está adequada.** O que falta é robustez de operação:
   isolamento dev×produção, backup fora do servidor, métricas de host, alerta
   com destino real, imagem por versão e rollback ensaiado (servidor e app).
7. Este plano **não substitui o N12** (ETL da v1 e enforce de quotas) nem os
   planos de releases Windows; ele os amarra ao go-live (seção 9).

## 1. Escopo

| Dentro | Fora (adiado, com condição) |
|---|---|
| Stack de servidor de produção na VPS, ao lado da dev | Abertura da web admin/tenant ao público (Fase A, só com aprovação do dono) |
| Evolution Go compartilhado, sem troca além da `0.7.3-wa2` | Botões "Entrar" e "Criar conta" do site |
| App Windows: canal estável, assinatura, auto-update | App para macOS/Linux/mobile |
| Servidor de releases em produção, por versão | Segunda VPS, réplica de banco, orquestrador |
| Site público por versão, no deploy de produção | Loja da Microsoft (alternativa registrada em D15) |

---

## 2. Inventário (revisão 2, 14/11/2026)

> **Histórico.** As seções 2.1 a 2.4 descrevem `docker/dev/compose.yml`,
> `docker/prod/compose.yml` e o `deploy-dev.yml` antigo, que não existem mais
> nessa forma. Para o estado vigente, ver R3.1 e
> `doc_dev/runbooks/RUNBOOK_DEPLOY.md`. As seções 2.5 a 2.8 continuam válidas,
> exceto onde a tabela R3.2 diz o contrário.

### 2.1 Como a dev sobe

O `deploy-dev.yml` dispara em todo push na `dev` (`:3-5`), sem esperar a CI, no
runner self-hosted (`:382`):

| # | Passo | Referência |
|---|---|---|
| 1 | Copia `/opt/smartcore/dev/env/dev.env` para `docker/dev/.env` e `docker/evolution/.env`; falha se faltar `POSTGRES_USER/PASSWORD/DB`, `REDIS_PASSWORD`, `MINIO_ROOT_PASSWORD`, `EVOLUTION_GLOBAL_API_KEY` | `:402-417` |
| 2 | Observabilidade com `--force-recreate` | `:424-429` |
| 3 | Evolution (`-p smart-core-v2-evolution`), que cria `smart_core_v2_evolution_net` | `:437-441` |
| 4 | `compose pull` + `up -d --remove-orphans` da dev | `:448-452` |
| 5 | Borda (`smartcore-edge:latest`) | `:456-460` |
| 6 | Testes de fumaça: config no Redis, borda (curl no domínio de **produção**), 12 serviços | `:467-586` |
| — | Em paralelo, gera o zip do app Windows de dev como artefato (não é o instalador) | `:198-240` |

### 2.2 Stack `smart-core-v2-dev` (`docker/dev/compose.yml`)

Todos com `restart: unless-stopped`, rotação de log (`:20-24`) e `mem_limit`.

| Serviço | Imagem | Porta no host | Redes | Volume | Depende de | Sonda |
|---|---|---|---|---|---|---|
| `postgres` | `pgvector/pgvector:pg16` | 127.0.0.1:5434 | internal | `postgres_data` | — | `pg_isready` |
| `redis` (cache) | `redis:7-alpine` | 127.0.0.1:6380 | internal | `redis_data` | — | `ping` |
| `redis-bus` | `redis:7-alpine` | 127.0.0.1:6381 | internal | `redis_bus_data` | — | `ping` |
| `pg_backup` | `pgvector/pgvector:pg16` | — | internal | `pg_backups` | postgres | idade do último dump |
| `minio` / `minio-setup` | `quay.io/minio/…` (`pull_policy: missing`, `:202-207`) | — | internal | `minio_data` | — | sem sonda |
| `data_postgres` | `smartcore-server:dev` | — | internal, observability | — | postgres | PING + batimento |
| `data_redis` | idem | — | internal, observability | — | redis, redis-bus | PING |
| `data_storage` | idem | — | internal, observability | — | — | PING + batimento |
| `control_plane` | idem | 172.17.0.1:8095 | internal, observability, mcp_net | — | data_postgres | PING |
| `ia_engine` / `ia_engine_jev` | imagens próprias `:dev` | — | internal, observability | — | — | `grpc.health.v1` |
| `mcp_server` | `smartcore-mcp-server:dev` | 172.17.0.1:8099 | mcp_net, mcp_telemetria | — | runtime_api, control_plane | espera 401 |
| `worker` | `smartcore-server:dev` | — | internal, observability | — | data_postgres, data_redis, ia_engine(s) | batimento |
| `runtime_api` | idem | 172.17.0.1:50051 | internal, observability, mcp_net | — | control_plane | PING |
| `web` / `web-tenant` | `smartcore-web(-tenant):dev` | 172.17.0.1:8081 / 8083 | internal | — | — | `wget` / sem sonda |
| `data_whatsapp` | `smartcore-server:dev` | — | internal, observability, evolution_net | — | redis | PING |
| `webhook_ingress` | idem | 127.0.0.1:9200 (no servidor: 9210) | internal, observability, evolution_net | — | — | `GET /health` |
| `watchdog` | idem, `user: root`, `docker.sock` (`:609`, `:622`) | — | internal, observability | — | — | sem sonda |

### 2.3 Stacks compartilhadas

| Projeto | Serviços | Observações |
|---|---|---|
| `smart-core-v2-evolution` | `smartcore-evolution` (`ghcr.io/pwlimaverde/evolution-go-wa:0.7.3-wa2` fixada por digest, `docker/evolution/compose.yml`), `smartcore-evolution-postgres` | Porta só em 127.0.0.1. **Sem `mem_limit`, sem rotação de log, sem backup, sem sonda no `evolution`** |
| `smart-core-v2-observability` | docker-proxy, otel-collector, loki, tempo, prometheus, grafana, promtail | Imagens fixadas. Loki e Tempo 14 dias, Prometheus 15 dias. **Sem `mem_limit`, sem rotação de log, sem sonda** |
| `smart-core-v2-edge` | `caddy` (`smartcore-edge:latest`) | Única coisa em 0.0.0.0 (80, 443, 443/udp). Um Caddyfile para dev **e** produção |

### 2.4 O que existe para produção (servidor)

| Item | Situação | Referência |
|---|---|---|
| `docker/prod/compose.yml` | 18 serviços; sem MinIO (mídia no R2); sem porta de banco/Redis no host; backup a cada 12 h, 30 dias | `:1-13`, `:143-154` |
| `deploy-prod.yml` | Tag `vX.Y.Z` → CI verde do commit → 6 imagens (`semver` + `latest`) → `environment: production` → `pg_dump` prévio → observabilidade, produção, borda → testes de fumaça | `:3-5`, `:24-49`, `:280-284`, `:305-453` |
| `/opt/smartcore/prod/env/prod.env` | Exigido pelo deploy (`:340`); não existia em 28/07/2026 (`infra/RUNBOOK_CUTOVER_PROD.md:13`). A confirmar |
| Rotas de produção na borda | Já escritas e **abertas**: `/v2/admin`, `/v2/tenant`, gRPC-Web, gRPC nativo, site, `auth.`, `mcp.`, `releases.`, `grafana.` | `docker/edge/Caddyfile:32-99`, `:177-206`, `:255-299` |

### 2.5 Aplicativo Windows (Smart Core Tenant)

| Aspecto | Como está | Referência |
|---|---|---|
| Alvo | Só o app **tenant** tem alvo Windows; o **admin é só web** (não há `clients/apps/smart-core-admin/windows/`) | árvore de `clients/apps` |
| Pipeline | `release-windows.yml`: tag `win-v*`, `workflow_dispatch` (cria a tag) ou branch `ci/release-windows-*` (ensaio sem publicar) | `:28-38` |
| Versão, canal e ambiente | `X.Y.Z-beta.N` → canal `beta`, build **dev** (`main_dev`, endereços `dev.`); `X.Y.Z` → canal `stable`, build **prod** (`main_prod`) | `:79-87` |
| Feed de atualização | `https://releases.smartcoreassistant.com.br/feed/<canal>`, gravado no build por `--dart-define`; padrão `stable` em `main_prod.dart:16-19`, `beta` em `main_dev.dart:20`. **Um só servidor para os dois canais**; a separação dev×produção é só o canal | `release-windows.yml:47`, `:137` |
| Conferência do binário | O job lê o snapshot AOT e falha se algum endereço não entrou | `:141-149` |
| Empacotamento | `vpk` 1.2.161, `packId` `SmartCoreTenant` (o mesmo para beta e estável), `--noPortable`, instalação por usuário em `%LOCALAPPDATA%\SmartCoreTenant` | `:45-46`, `:212-236` |
| Assinatura | `signtool` via `--signParams` com PFX dos secrets `SIGNTOOL_CERT`/`SIGNTOOL_PASSWORD`, SHA-256 e carimbo de tempo; sem os secrets, gera certificado efêmero. **Hoje o certificado é auto-assinado de desenvolvimento** (validade até 2036) | `:166-199`, `:214`; `infra/windows/README.md` |
| Verificação | Exige assinatura `Valid`, thumbprint esperado e carimbo no `Setup.exe` e nos binários do `.nupkg` | `:246-267` |
| Prova de auto-update | Instala `0.0.1-e2e.1`, serve feed local com `0.0.1-e2e.2` e espera o app se atualizar sozinho | `:277-332` |
| Publicação | Artefato (30 dias) + GitHub Release (pré-release no beta) + `POST /upload` no servidor de releases. Se o token faltar ou o servidor não responder, **só avisa e segue** | `:352-402` |
| Atualização no cliente | Na subida do app: `initializeVelopack(url)`, `isUpdateAvailable()`, `updateAndRestart()`. Baixa, aplica e reinicia **sem perguntar**. Não rebaixa versão (o parâmetro de downgrade do plugin não é usado) | `clients/apps/smart-core-tenant/lib/platform/auto_update_native.dart:36-43` |
| Pacote completo ou delta | **Só completo.** O job empacota em pasta vazia e não baixa a versão anterior (`vpk download`), então o Velopack não gera delta | `release-windows.yml:222-236` |
| Portões | Nenhum: sem exigência de CI verde, sem `environment`, sem restrição de branch. Vale para o canal estável | `:28-38` |
| Releases existentes | Só beta (`win-v0.2.0-beta.9` é a mais recente); nenhuma estável | `git tag` |

### 2.6 Servidor de releases (`releases_server`)

| Aspecto | Como está | Referência |
|---|---|---|
| O que é | Serviço Rust (Axum) que guarda o instalador e o feed do Velopack | `server/apps/releases_server/src/lib.rs` |
| Rotas | `GET /health`; `GET /api/installers/{canal}` (60/min/IP); `GET /feed/{canal}/{arquivo}` público (120/min/IP); `GET /download/{versao}/{arquivo}?t=` com ticket HMAC (30/min/IP); `POST /upload` com `Bearer RELEASES_UPLOAD_TOKEN` (5/min/IP) | `docker/releases/README.md` |
| Canais | `beta` e `stable` aceitos no servidor (`lib.rs:52`); **o `control_plane` só emite link para `beta`** e recusa `stable` | `server/apps/control_plane/src/releases.rs:43-51` |
| Download do instalador | Ticket de 5 minutos, emitido só para superusuário pela tela "Instalador Windows" do admin web, com auditoria (`security.audit`) | `control_plane/src/releases.rs:175`, `:203-224`; `crates/release_ticket/src/lib.rs:86-87` |
| Feed | Público, sem autenticação: o `.nupkg` completo do app pode ser baixado por qualquer um que conheça o nome | `lib.rs:365-380` |
| Publicação | Um único token para os dois canais; republicar a mesma versão substitui; o índice do canal é trocado a cada envio; `.nupkg` antigos nunca são apagados | `lib.rs:566-606` |
| Armazenamento | Disco local: `/opt/smartcore/releases-data` montado em `/data/releases`. **Sem backup** | `docker/releases/compose.yml:24` |
| Implantação | "Sobe à mão no VPS" (`:1`), imagem `…-releases:latest` (`:7`), porta 172.17.0.1:8086, `mem_limit` 128m, sem rotação de log, fora da rede de observabilidade | `docker/releases/compose.yml` |
| Imagem | Construída a **cada tag `win-v*`**, com tags `latest` e SHA do commit; não há tag de versão | `release-windows.yml:404-428` |
| Borda | `releases.smartcoreassistant.com.br` → 172.17.0.1:8086 | `docker/edge/Caddyfile:285-299` |
| Runbook | `doc_dev/runbooks/RUNBOOK_RELEASES.md` descreve recursos que **não existem no código**: rollback por `git show` do feed, troca de segredo com `RELEASES_DOWNLOAD_SECRET_OLD` e caminhos `/opt/smartcore/releases` | comparação com `lib.rs` e `main.rs` |

### 2.7 Site público

| Aspecto | Como está | Referência |
|---|---|---|
| Código | `docker/site/publico/` (um `index.html` de 24 KB + `static/css`, `static/img`; 196 KB), capturado da página renderizada da v1 | `docker/site/Dockerfile:8-9` |
| Imagem | `smartcore-site:local`, construída **à mão no servidor** (`docker compose -p smart-core-site up -d --build`); não está em nenhum workflow nem no GHCR | `docker/site/compose.yml:12-21` |
| Rota | Tudo em `smartcoreassistant.com.br` que não for `/v2/admin`, `/v2/tenant` ou gRPC cai no site (172.17.0.1:8085) | `docker/edge/Caddyfile:90-92` |
| Cabeçalhos | HSTS, `nosniff`, `X-Frame-Options: SAMEORIGIN`; **sem CSP** no bloco do site | `docker/edge/Caddyfile:94-98` |
| Dependência externa | Google Fonts (`fonts.googleapis.com`, `fonts.gstatic.com`) | `publico/index.html:22-24` |
| "Entrar" / "Criar conta" | Desligados por CSS (`[data-acesso-desativado]`, `pointer-events: none`), com `href="#"` | `publico/index.html:18`, `:60`, `:64`, `:110`, `:114`, `:238`, `:370` |
| Robustez | `mem_limit` 64m, rotação de log; sem sonda | `docker/site/compose.yml:27-32` |

### 2.8 Lacunas do deploy de produção

| # | Lacuna | Referência |
|---|---|---|
| L1 | **[Resolvido: `required-keys.prod`]** `deploy-prod.yml` não valida chaves obrigatórias do `prod.env` (a dev valida) | `deploy-prod.yml:339-340` × `deploy-dev.yml:405-410` |
| L2 | `docker/prod/.env.example` desatualizado: faltam `MCP_OAUTH_*`, `MCP_SERVICE_SECRET`, `MCP_*_TTL_S`, `MCP_HOST_PORT`, `MCP_OAUTH_HOST_PORT`, `EMAIL_*` (6), `APP_PUBLIC_URL`, `ATENDIMENTO_ATIVO_MAX_DIA`, `RELEASES_*` (3), `MEM_MCP_SERVER`. O compose exige as `MCP_*` (`docker/prod/compose.yml:356-361`) | diff dos dois exemplos |
| L3 | Em nenhum dos exemplos: `S3_CORS_ALLOWED_ORIGINS`, `IA_ENGINE_JEV_IMAGE`, `MCP_SERVER_IMAGE`, `MEM_IA_ENGINE_JEV`, `SMARTCORE_IA_ENGINE_JEV_ENDPOINT` | só em `.env.example:49` (raiz) |
| L4 | **[Resolvido na stack de aplicação: digest da beta + `rollback-prod.yml`]** Produção em `:latest`; o "rollback" documentado (reempurrar a tag) reconstrói tudo e move `latest` | `docker/prod/compose.yml:16`; `deploy-prod.yml:451` |
| L5 | **[Resolvido: `gate-origem` + ruleset]** A tag sai de qualquer branch; o PR `dev → main` só é aberto depois do deploy | `pr-to-main.yml:19-27` |
| L6 | **[Resolvido: `deploy.sh` lê do env]** `pg_dump` prévio com usuário e banco fixos no YAML | `deploy-prod.yml:317` |
| L7 | **[Resolvido: `smoke.sh`]** `web`/`web-tenant` de produção sem sonda; `mcp_server`, `web`, `web-tenant` fora do teste de fumaça | `docker/prod/compose.yml:444-465`; `deploy-prod.yml:415` |
| L8 | **[Resolvido: `deploy-infra.yml`]** A imagem da borda só é construída no deploy da **dev**: mudança no Caddyfile chega à produção por push na `dev`, sem CI nem aprovação | `deploy-dev.yml:242-263` |
| L9 | **[Resolvido]** O deploy de produção recria a observabilidade inteira e não confere o Evolution | `deploy-prod.yml:349-351` |
| L10 | Migrações no boot do `data_postgres`, só para frente (53 arquivos, nenhum `down`); sem ensaio antes de trocar a versão | `server/crates/infrastructure_postgres/migrations/` |
| L11 | **[Resolvido em 24/11: bundle `current` + env do ambiente via `lib.sh`; serviços ficam parados com instrução se a restauração falhar]** `infra/restore-postgres.sh` assumia usuário `postgres` e banco `smartcore` e apontava para `docker/<env>/compose.yml` | `infra/restore-postgres.sh` |
| L12 | Site e servidor de releases fora de qualquer deploy, sem imagem versionada (2.6, 2.7) | — |
| L13 | Canal estável do app Windows sem portão e com falha de upload tratada como aviso (2.5) | `release-windows.yml:28-38`, `:383-391` |
| L14 | O `control_plane` recusa o canal `stable`: em produção não há como emitir link do instalador | `control_plane/src/releases.rs:43-51` |

---

## 3. Segurança

### 3.1 Crítico (bloqueia o go-live)

| ID | Achado | Evidência | Correção |
|---|---|---|---|
| C1 | **[Resolvido em 22/11: `OBS_NET` por ambiente]** **Nomes de serviço repetidos em rede comum a dev e produção.** Os dois composes ligam `data_postgres`, `data_redis`, `data_storage`, `control_plane`, `runtime_api`, `worker`, `ia_engine`, `ia_engine_jev`, `data_whatsapp`, `webhook_ingress` à rede externa `smart_core_v2_observability`. O nome do serviço vira apelido de DNS em cada rede; um container em duas redes resolve o nome nas duas. Com as duas stacks no ar, `tcp://data_postgres:9101` chamado pela produção pode cair na dev. O transporte interno não autentica (`crates/transport/src/codec.rs:92-94`) | `docker/prod/compose.yml:184,217,237,271,292,402,429,473,488` e o equivalente na dev | Rede de telemetria **por ambiente** (`smart_core_v2_telemetria_prod` / `_dev`), com o coletor nas duas. Validar com `getent hosts data_postgres` |
| C2 | **[Resolvido em 22/11: `WEBHOOK_INGRESS_URL`; prod em `172.17.0.1:9211`, fora da `evolution_net`]** **Webhook do Evolution fixo no código**: `http://webhook_ingress:9200/webhook/...`. Com Evolution compartilhado e os dois `webhook_ingress` na mesma rede, a entrega alterna entre ambientes e o token da instância é recusado no ambiente errado | `server/apps/data_whatsapp/src/main.rs:362-365`, `:673`, `:1028`, `:1111` | Variável `WEBHOOK_INGRESS_URL_INTERNA` + apelido de rede por ambiente; regravar o webhook das instâncias existentes |
| C3 | **[Resolvido em 22/11: dev 8095/8099/9210, prod 8096/8100/9211]** **Portas iguais no host**: 8095, 8099 e 9200 têm o mesmo padrão nos dois composes; a borda aponta `auth.`/`mcp.` de dev e produção para a mesma porta | `docker/prod/compose.yml:273,373,490`; `docker/edge/Caddyfile:204,232,245,264`, aviso em `:208-211` | Portas próprias de produção (8096, 8098, 9201) e blocos separados no Caddyfile |
| C4 | **Backup só no disco do banco.** Vale também para o banco do Evolution e para os artefatos de release | `infra/RUNBOOK_ROBUSTEZ.md:131-135` | Cópia externa (bucket R2 próprio, credencial só de escrita) e restauração ensaiada |
| C5 | **Segredos em texto puro em `smart-agent-config/.claude/settings.local.json`** (confirmado por busca de padrão, sem exibir valores): URLs de banco com senha embutida nas linhas 66, 72, 105 e 106; um token do GitHub (`GH_TOKEN`) na linha 155; um cabeçalho `Authorization: Bearer` na linha 156. Não há chave chamada "password"/"senha": a senha está dentro das URLs. O arquivo é ignorado só pelo gitignore **global da máquina** (`~/.config/git/ignore:3`), não pelo do repositório. A `TYPESAFE_API_KEY` **não** aparece nesse arquivo; a exposição dela foi em saída de comando | busca por padrão no arquivo | Dono: revogar o token do GitHub e trocar as senhas de banco e a chave TypeSafe. IA: remover as regras e incluir `**/.claude/settings.local.json` no `.gitignore` do repositório |
| C6 | **Canal estável do app Windows sem portão.** Qualquer tag `win-vX.Y.Z`, de qualquer branch, sem CI verde e sem aprovação, publica no feed estável; todo aplicativo instalado baixa, aplica e reinicia sozinho na próxima abertura. Um build ruim ou malicioso chega a todos os clientes | `release-windows.yml:28-38`; `auto_update_native.dart:36-43` | Ambiente `production-windows` com revisor obrigatório, exigência de CI verde, tag só a partir de `main`, token de upload do estável só nesse ambiente, falha de upload reprova o job |

### 3.2 Alto

| ID | Achado | Evidência | Correção |
|---|---|---|---|
| A1 | **[Parcial: revisor no environment `prod`, ruleset de tags e bundle por ambiente fora da workspace; runner segue único e no grupo `docker`]** Runner self-hosted único, `gh-runner` no grupo `docker` (equivale a root), mesma workspace para dev e produção; `prod.env` legível pelo mesmo usuário | `infra/server-setup.sh:59`, `:74` | Revisor obrigatório no ambiente `production`, tags protegidas, conferir se o repositório é privado; depois, runner próprio (D3) |
| A2 | Chave global do Evolution compartilhada: a dev consegue apagar ou usar instâncias de produção | `docker/evolution/compose.yml:55` | Chave nova no go-live, prefixo por ambiente, alerta de instância removida |
| A3 | Nome de instância vem do usuário e o Evolution é um só: colisão entre ambientes | `runtime_api/src/grpc_web.rs:3916` | Prefixo `prod-`/`dev-` aplicado no `data_whatsapp` |
| A4 | **[Resolvido: `caddy validate` na CI e borda só por `deploy-infra.yml`]** Borda única e sem gate (L8); um Caddyfile inválido já derrubou tudo em 28/07/2026 (`deploy-dev.yml:497-501`) | — | `caddy validate` na CI; borda de produção só troca por tag |
| A5 | **[Parcial: servidor por versão; releases e site ainda não]** Imagens de produção em `:latest` (servidor, releases, borda) e bases por tag móvel | `docker/server/Dockerfile:5,34`; composes | Versão exata em produção; bases por digest |
| A6 | SSH como `root`, com campo de senha previsto; sem `fail2ban` nem atualização automática | `infra/.env.deploy.example:11-13`; `infra/server-setup.sh` | Só chave, `PermitRootLogin prohibit-password`, `fail2ban`, `unattended-upgrades` |
| A7 | O Docker publica portas por cima do UFW; cadeia `DOCKER-USER` vazia em 11/09/2026 | `docker/dev/compose.yml:54-57` | Regras na `DOCKER-USER` e inventário de portas |
| A8 | Sem métricas de host (CPU, memória, disco) | `infra/RUNBOOK_ROBUSTEZ.md:208-210` | `node_exporter` + `cAdvisor` + alertas |
| A9 | Alertas sem destino real | `docker/observability/compose.yml:126-127` | Canal definido pelo dono; alerta de teste |
| A10 | Sessão do Claude Code como root no VPS (`claude-rc`), com `bypassPermissions` e `IS_SANDBOX=1`, no mesmo servidor da prod e com acesso ao `prod.env` | `/etc/systemd/system/claude-rc.service` | **Aceito pelo dono (D8).** Mitigação mínima: nenhum segredo em conversa, backup em `/root/backups/` antes de editar config, nada de `compose` fora do deploy |
| A11 | **Instalador assinado com certificado auto-assinado.** O SmartScreen mostra "editor desconhecido" e o Defender pode classificar o `Setup.exe` como ameaça; o usuário relatou exatamente isso. Pedir ao cliente que importe o certificado de desenvolvimento como raiz confiável **não é saída**: daria a esse certificado poder de validar qualquer coisa na máquina dele | `infra/windows/README.md`; `release-windows.yml:10-14` | Certificado de autoridade pública em HSM de nuvem + mudança do passo de assinatura (seção 5.4, Fase 10) |
| A12 | **[Aberto; além da rota, o `web-tenant` da prod está de pé]** **Web de produção já roteada ao público** (`/v2/admin`, `/v2/tenant`, gRPC-Web). Contraria a decisão de não publicar a web agora | `docker/edge/Caddyfile:36-67` | `/v2/tenant` não roteado; `/v2/admin` e gRPC-Web só por lista de IP ou VPN (Fase 4) |
| A13 | Um só token de upload para beta e estável; o pipeline de beta (build de dev) tem credencial para publicar no feed de produção | `releases_server/src/lib.rs:121-126` | Token por canal; o do estável só no ambiente protegido |

### 3.3 Médio

| ID | Achado | Evidência | Correção |
|---|---|---|---|
| M1 | CORS do gRPC-Web espelha qualquer origem | `runtime_api/src/grpc_web.rs:11655-11657` | Lista fechada por ambiente |
| M2 | `watchdog` como root com o socket do Docker (dev e prod; com o proxy da observabilidade são 3 montagens do socket no servidor) | `docker/stack/docker-compose.base.yml:609` | Via `docker-socket-proxy` |
| M3 | Redis guarda chaves de LLM decifradas (decisão consciente) | `security.md:40-43` | Sem porta no host; RDB/AOF tratados como credencial |
| M4 | **[0459 corrigido em `e76adaf2`; resta a auditoria bloqueante]** RUSTSEC-2026-0459 pendente; auditoria com `continue-on-error`. O 0459 atinge justamente o **app Windows** (`local_engine` → `sqlx` → sqlite) | `server/.cargo/audit.toml:13-41`; `ci.yml:244` | Auditoria bloqueante com exceção datada; corrigir quando o `sqlx` publicar |
| M5 | Avisos 0386 (tokio), 0486 (rustix), `chacha20`, `spin` | `audit.toml:87-118` | `cargo update` no pós-go-live |
| M6 | Sem varredura de imagem nem de dependência Python/Dart; ações do GitHub por tag móvel | workflows | `trivy`, `pip-audit`, ações por SHA |
| M7 | **[Observabilidade resolvida (teto + `oom_score_adj` 300); restam Evolution e releases]** Evolution, observabilidade e releases sem limite de memória e/ou rotação de log | composes | `mem_limit` e `logging` |
| M8 | Banco do Evolution sem backup | `docker/evolution/compose.yml:78-81` | `pg_dump` periódico + cópia do volume |
| M9 | Serviços Rust iniciam a telemetria com ambiente fixo `"production"` também na dev | `data_whatsapp/src/main.rs:27` | Ler `SMARTCORE_ENV` |
| M10 | Dados pessoais em log: busca simples não achou telefone/CPF/CNPJ em macros de uma linha, mas não cobre macros de várias linhas | — | Revisão dirigida + teste |
| M11 | Site sem versionamento e sem CSP | `docker/site/compose.yml:21`; `Caddyfile:94-98` | Fase 3 |
| M12 | `S3_BUCKET` com o mesmo nome padrão em dev e produção | exemplos de `.env` | Bucket e credencial próprios |
| M13 | Feed do Velopack público: o pacote completo do app é baixável sem ticket; o ticket protege só o `Setup.exe` | `releases_server/src/lib.rs:365-380` | Aceitar (o app exige login) ou exigir token no feed (D14) |
| M14 | `packId` igual para beta e estável: instalar um por cima do outro troca o canal da máquina; quem testa beta não consegue manter os dois | `release-windows.yml:46` | `packId` próprio para o beta (D13) |
| M15 | Senha do PFX passada na linha de comando do `signtool` (mascarada no log) | `release-windows.yml:214` | Desaparece com a assinatura em HSM de nuvem |
| M16 | Artefatos de release sem backup e sem limpeza: `.nupkg` antigos acumulam em disco | `releases_server/src/lib.rs:584-591` | Retenção das N últimas + cópia externa |
| M17 | Runbook de releases descreve procedimentos que o código não implementa | `doc_dev/runbooks/RUNBOOK_RELEASES.md` | Reescrever na Fase 8 |
| M18 | O link de convite por e-mail aponta para a web do tenant (`APP_PUBLIC_URL`), que ficará fechada | `runtime_api/src/grpc_web.rs:378` | Verificar se convite e redefinição de senha concluem dentro do app Windows; decidir em D12 |

### 3.4 Baixo

| ID | Achado | Correção |
|---|---|---|
| B1 | `sqlx-prepare.yml` com `apt-get` sem nova tentativa (`:62-63`) | 3 tentativas |
| B2 | Flutter fixado em 3.47.9 em quatro workflows | Subida planejada, com ensaio do instalador |
| B3 | `infra/caddy/*.caddy` e `infra/cleanup-hostinger.sh` são legado | Arquivar |
| B4 | `infra/RUNBOOK_CUTOVER_PROD.md` descreve o servidor de 28/07/2026 | Reescrever após o go-live |
| B5 | `infra/server-setup.sh` executa `ufw --force reset` (`:91`) | Não rodar em servidor vivo |
| B6 | `.env.example` da raiz descreve UDS/systemd e traz o identificador da conta Cloudflare | Atualizar |
| B7 | `smart-agent-config/.claude/settings.json` (versionado) contém o IP público da VPS em regra de permissão (linha 66) | Trocar pelo apelido SSH |
| B8 | Site carrega fontes do Google (terceiro) | Hospedar as fontes junto, ou liberar só esses dois domínios na CSP |

### 3.5 O que já está bem resolvido (manter)

- Banco e Redis de produção sem porta no host; papel de runtime `smartcore_app_rt` sem superusuário, com RLS provado.
- `mcp_server` isolado por topologia, sem credencial de banco.
- Containers de aplicação sem root (exceto o `watchdog`); `releases_server` com usuário próprio (uid 10001).
- Promtail via proxy só de leitura; cabeçalhos de segurança e HSTS na borda; `/internal/*` bloqueado em `auth.`.
- Webhook autenticado por token de instância, com limite de requisições.
- Portão de CI verde e `pg_dump` validado no deploy de servidor.
- No app Windows: endereços conferidos dentro do binário, assinatura verificada em todos os binários, ciclo de auto-update provado antes de publicar, ensaio em branch `ci/` sem publicar.
- No servidor de releases: nomes por lista de permitidos (sem `ServeDir`), limite por IP, gravação atômica, ticket com validade de 5 minutos e auditoria da emissão.

---

## 4. Parâmetros de produção

Fonte única: `/opt/smartcore/prod/env/prod.env` (dono `gh-runner`, modo 600). Para o servidor de releases: `/opt/smartcore/releases/env/releases.env`, mesma regra. "Distinto" = não pode repetir o valor da dev.

### 4.1 Segredos do servidor

| Variável | Serviço | Obrigatória | Observação |
|---|---|---|---|
| `POSTGRES_PASSWORD`, `APP_RT_PASSWORD` | postgres, papel de runtime | sim | Distintos |
| `DATABASE_URL` / `DATABASE_ADMIN_URL` | serviços Rust | sim | Derivadas das senhas |
| `REDIS_PASSWORD`, `REDIS_URL`, `REDIS_BUS_URL` | redis, redis-bus | sim | Distinto |
| `JWT_SECRET` | control_plane, runtime_api | sim | Distinto: igual ao da dev, token da dev vale em produção |
| `ENCRYPTION_KEY` | data_postgres | sim | Distinto, **com cópia fora do servidor** |
| `MCP_OAUTH_PRIVATE_KEY_PEM` / `_PUBLIC_KEY_PEM`, `MCP_SERVICE_SECRET` | control_plane, mcp_server | sim se o MCP subir (D16) | Par próprio de produção |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | data_storage | sim | Token R2 restrito ao bucket de produção |
| `EVOLUTION_GLOBAL_API_KEY` | data_whatsapp | sim | Igual à da dev por decisão; trocar uma vez antes do go-live |
| `EMAIL_HOST_USER` / `EMAIL_HOST_PASSWORD` | control_plane | sim | Chave SMTP própria |
| `GF_SECURITY_ADMIN_PASSWORD`, `SMARTCORE_ALERTA_WEBHOOK_URL` | grafana (`observability.env`) | sim | Trocar no go-live |
| `TYPESAFE_API_KEY`, chaves de LLM | CoreSettings no banco | conforme o uso | Chaves próprias, com teto de gasto |

### 4.2 Releases e app Windows

| Parâmetro | Onde vive | Obrigatório | Observação |
|---|---|---|---|
| `RELEASES_UPLOAD_TOKEN` (hoje único) → proposto `RELEASES_UPLOAD_TOKEN_BETA` e `RELEASES_UPLOAD_TOKEN_STABLE` | `releases.env` e secrets do GitHub | sim | O do estável como secret **do ambiente** `production-windows`, não do repositório |
| `RELEASES_DOWNLOAD_SECRET` | `releases.env` **e** `prod.env` (control_plane) | sim para emitir link | O mesmo valor nos dois lados; hoje a dev também o usa, pois o servidor é um só |
| `RELEASES_PUBLIC_URL` | `prod.env` | sim | `https://releases.smartcoreassistant.com.br` |
| `RELEASES_INTERNAL_URL` | `prod.env` | recomendado | Endereço interno do serviço, para o control_plane não depender da borda |
| `RELEASES_DIR`, `RELEASES_BIND`, `RELEASES_MAX_UPLOAD_MB` | `releases.env` | não | Padrões `/data/releases`, `0.0.0.0:8086`, 500 |
| `RELEASES_IMAGE` | `releases.env` | sim | Versão exata, nunca `:latest` |
| `RELEASES_HOST_PORT` | `releases.env` e Caddyfile | não | 8086 |
| `SMARTCORE_UPDATE_FEED_URL` | `--dart-define` no build | sim | `…/feed/stable` (prod) e `…/feed/beta` (dev); conferido no binário |
| `SMARTCORE_API_ENDPOINT`, `SMARTCORE_MCP_ENDPOINT`, `SMARTCORE_APP_PUBLIC_URL`, `SMARTCORE_APP_VERSAO`, `SMARTCORE_APP_BUILD` | `--dart-define` no build | sim | Endereços de produção só no canal estável |
| `VPK_VERSION`, `PACK_ID`, `RELEASES_URL` | `release-windows.yml:45-47` | sim | `PACK_ID` do beta passa a ser próprio se D13 for aprovada |
| Assinatura: hoje `SIGNTOOL_CERT` + `SIGNTOOL_PASSWORD` (PFX) | secrets do GitHub | sim | Com certificado de autoridade pública em HSM de nuvem deixam de existir; entram as credenciais do serviço de assinatura (nomes dependem do fornecedor, D11), também como secrets do ambiente protegido |
| Carimbo de tempo | `release-windows.yml:214` | sim | Hoje `timestamp.digicert.com`; passa a ser o da autoridade escolhida |
| Nome do editor no certificado | certificado | sim | Deve ser a razão social da empresa; é o que o Windows mostra |

### 4.3 Site

| Parâmetro | Valor de produção | Observação |
|---|---|---|
| `SITE_IMAGE` (novo) | `ghcr.io/…/smartcore-site:<versão>` | Substitui `smartcore-site:local` |
| `SITE_HOST_PORT` | 8085 | Já usado pela borda |
| CSP do site (novo, na borda) | `default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data:; script-src 'self'; frame-ancestors 'self'` | Ajustar ao conteúdo real; some com as fontes hospedadas junto |
| Estado dos botões | `data-acesso-desativado` presente | Conferido por teste na CI: o build falha se o atributo sumir sem a Fase A aprovada |

### 4.4 Parâmetros não secretos do servidor

| Variável | Valor de produção | Valor de dev proibido? |
|---|---|---|
| `SERVER_IMAGE`, `WEB_IMAGE`, `IA_ENGINE_IMAGE`, `IA_ENGINE_JEV_IMAGE`, `MCP_SERVER_IMAGE` | Versão exata | sim |
| `WEB_TENANT_IMAGE` | Não usado enquanto a web do tenant estiver fechada | — |
| `SMARTCORE_ENV`, `OTEL_SERVICE_NAMESPACE` | `prod`, `smart-core-v2-prod` | sim |
| `RUNTIME_WEB_PORT`, `WEB_HOST_PORT` | 50052, 8082 | sim |
| `MCP_OAUTH_HOST_PORT` / `MCP_HOST_PORT`, `WEBHOOK_INGRESS_PORT` | 8096 / 8098, 9201 (proposta) | sim |
| `MCP_OAUTH_ISSUER` / `MCP_OAUTH_RESOURCE` | `https://auth.` / `https://mcp.smartcoreassistant.com.br` | sim |
| `APP_PUBLIC_URL` | Depende de D12 (hoje `https://smartcoreassistant.com.br/v2/tenant`, que ficará fechado) | sim |
| `S3_ENDPOINT`, `S3_REGION`, `S3_FORCE_PATH_STYLE`, `S3_BUCKET` | R2, `auto`, `true`, bucket próprio | sim |
| `S3_CORS_ALLOWED_ORIGINS` | Vazio enquanto a web estiver fechada (o app Windows não usa CORS) | sim |
| `ADMIN_IPS_PERMITIDOS` (novo, na borda) | IP fixo do dono ou faixa da VPN | — |
| `GRPC_WEB_ORIGENS_PERMITIDAS` (novo, M1) | `https://smartcoreassistant.com.br` | sim |
| `SMARTCORE_*_ENDPOINT` | Nomes de serviço da stack de produção | não, com C1 corrigido |
| `WEBHOOK_INGRESS_URL_INTERNA` (novo, C2) | `http://webhook-ingress-prod:9200` | sim |
| `EVOLUTION_API_URL` | `http://smartcore-evolution:8080` | não |
| `TRANSCRIPTION_ENABLED`, `SMARTCORE_QUOTA_ENFORCE` | `false` no início | não |
| `WEBHOOK_RATE_LIMIT_*`, `RUNTIME_API_RATE_LIMIT_*`, `ATENDIMENTO_ATIVO_MAX_DIA` | Padrões; calibrar | não |
| `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_FROM`, `EMAIL_FROM_NAME` | Brevo, domínio verificado | não |
| `BACKUP_*`, `WATCHDOG_*`, `LOG_MAX_*`, `MEM_*` (incluir `MEM_IA_ENGINE_JEV`, `MEM_MCP_SERVER`) | Conforme a memória medida na Fase 0 | não |
| `JEV_REQ_POR_MINUTO` | 1000, dividindo o teto da conta com a dev | rever |
| `AUTH_ACCESS_TTL_S`, `AUTH_REFRESH_TTL_S`, `LOGIN_RATE_*`, `SIGNUP_RATE_LIMIT_MAX` | Lidas pelo código, fora dos exemplos; documentar | não |

Proibido no `prod.env`: `COMPOSE_PROJECT_NAME`, `TYPESAFE_API_KEY`, `MINIO_*`, portas de banco/Redis no host.

---

## 5. Arquitetura

### 5.1 Veredito

**A divisão em serviços está correta e deve ser mantida.** Uma única porta para o banco, motor de IA sem acesso ao banco, `mcp_server` isolado por rede, webhook separado do processamento, cache separado do barramento. O `releases_server` como serviço à parte também está certo: ele precisa continuar no ar mesmo se a stack de aplicação cair, porque é por ele que uma correção chega ao cliente.

O ponto fraco é de operação: tudo em uma máquina, dev e produção lado a lado, stacks compartilhadas, e três componentes (site, releases, borda) fora de um deploy controlado.

### 5.2 Topologia proposta na VPS

| Projeto compose | Conteúdo | Quem implanta |
|---|---|---|
Revisada em 24/11/2026 para o fluxo que já existe (`docker/stack/` + bundle +
`deploy-infra.yml`, decisão R-D1 do plano `servidor-reestruturacao-dev-prod`:
infra compartilhada só pelo fluxo de prod).

| Projeto compose | Conteúdo | Quem implanta | Estado |
|---|---|---|---|
| `smart-core-v2-prod` | Serviços de aplicação + **`site`** (decisão do dono: junto com o admin) + `web` (admin, restrito); **sem `web-tenant`** enquanto a web estiver fechada | `deploy-prod.yml`, tag `vX.Y.Z` | No ar sem o site e com `web-tenant` |
| `releases-stack` (nome real; a revisão 2 o chamava `smart-core-v2-releases`) | `releases_server`, dados em `/opt/smartcore/releases-data` | `deploy-infra.yml`, componente novo `releases` (serve beta e estável: é infra compartilhada) | Subido à mão, `:latest` |
| `smart-core-v2-edge` | Caddy | `deploy-infra.yml` | Feito |
| `smart-core-v2-evolution` | Evolution + banco dele | `deploy-infra.yml`; o deploy de prod só confere | Feito |
| `smart-core-v2-observability` | LGTM + métricas de host | `deploy-infra.yml` | Feito (sem métricas de host) |
| `smart-core-v2-dev` | Dev | `deploy-dev.yml` | Feito |

Sobre o site dentro da stack de produção: atende ao pedido e ganha versão, sonda e teste de fumaça de graça. O custo é o site cair se alguém derrubar a stack inteira (`compose down`). Mitigação: `up -d` só recria o que mudou, a imagem do site tem tag por conteúdo (não muda a cada release) e a regra "nunca `down` em produção" entra na seção 8.

### 5.3 Pontos únicos de falha

| Ponto | Efeito | Hoje | Proposta |
|---|---|---|---|
| A VPS | Tudo fora do ar; banco, backups e releases perdidos juntos | Sem cópia externa | Backup externo + restauração ensaiada; snapshot do provedor |
| `postgres` | Sem atendimento | Perda de até 12 h | Dump a cada 6 h com cópia externa; depois, recuperação por instante |
| `redis-bus` (150 MB, `noeviction`) | Cheio, para toda mensagem | Alerta de fila existe | Medir, subir o teto, alerta de memória |
| `data_postgres` | Todos dependem; roda migração no boot | Sonda dupla + watchdog | Ensaio de migração antes do deploy |
| Borda | Derruba dev, produção, site, Grafana e **o feed de atualização** | Trocada por push na dev | Gate de validação; troca só por tag |
| Evolution compartilhado | WhatsApp parado nos dois ambientes | Sem limite, sem backup | Limites, backup, prefixo por ambiente |
| Servidor de releases | App instalado segue funcionando, mas **nenhuma correção chega ao cliente**; instalador indisponível | Sem backup, sem alerta | Backup externo, sonda externa em `/health`, GitHub Release como segunda cópia dos artefatos |
| Certificado de assinatura | Sem ele não sai versão; se a chave vazar, alguém assina como a empresa | PFX em secret do GitHub | Chave em HSM de nuvem; revogação documentada |
| Feed estável | Uma versão ruim chega a todos, sem volta automática (o Velopack não rebaixa versão) | Sem portão | C6 + beta antes do estável + procedimento de correção para frente |
| Memória da VPS | VM de 7,8 GiB; soma dos tetos ≈ 13 GiB (prod ≈ 7,6, observabilidade ≈ 2,8, mais a dev); uso real ≈ 1,5 GiB. Tetos não reservam memória: um pico conjunto ainda leva o kernel ao OOM | D1 decidida: mesma VPS, `oom_score_adj` dev 900 / obs 300 / prod 0 (a dev morre primeiro) | Fase 2B: enxugar os tetos da dev para a soma caber na RAM, alerta de memória do host (A8) |

### 5.4 O aviso de vírus no instalador: causa e caminho

**Causa.** O Windows decide com base em quem assinou e na reputação acumulada daquele editor e daquele arquivo. Hoje a assinatura é de um certificado que nenhuma máquina de terceiro reconhece, e cada versão é um arquivo novo sem histórico. O resultado é o aviso do SmartScreen e, em alguns casos, a quarentena pelo Defender.

**O que resolve, em ordem:**

1. **Certificado de autoridade pública em nome da empresa.** Desde 1º de junho de 2023 a chave privada precisa ficar em HSM de nuvem ou token físico; não existe mais PFX exportável. Consequência prática: o passo atual (`--signParams` com PFX em secret) **deixa de servir**. O `vpk` aceita `--signTemplate` (comando externo do serviço de assinatura) e `--azureTrustedSignFile` (serviço da Microsoft).
2. **Qual tipo.** O serviço da Microsoft (Artifact Signing, antes Trusted Signing) dá reputação imediata, mas a página da Microsoft lista organizações apenas dos EUA, Canadá, União Europeia e Reino Unido. Para empresa brasileira, o caminho provável é certificado **OV** de uma autoridade com assinatura em nuvem. O **EV** deixou de dar reputação imediata em 2024, então não compensa o preço maior. A elegibilidade e o fornecedor são a decisão D11.
3. **Reputação se constrói.** Com OV, os primeiros downloads ainda podem mostrar aviso; ele diminui com o uso. Manter **o mesmo certificado e o mesmo nome de editor** em todas as versões, e não trocar o nome do arquivo sem necessidade.
4. **Enviar o instalador para análise da Microsoft** a cada versão em que houver detecção indevida (portal de envio de arquivos da Microsoft Security Intelligence).
5. **Publicar o SHA-256** junto do link (o pipeline já calcula).
6. **Enquanto o certificado não chega:** orientar o piloto a usar "Mais informações → Executar assim mesmo", e só para clientes acompanhados. Não pedir instalação de certificado raiz.

### 5.5 Compatibilidade entre versões do app e do servidor

O servidor (`vX.Y.Z`) e o app (`win-vX.Y.Z`) têm ciclos independentes, e o app só se atualiza quando é aberto. Regras:

- O servidor sobe **antes** do app que depende de recurso novo.
- Mudança de contrato (proto) mantém compatibilidade com a versão anterior do app por pelo menos um ciclo.
- Toda versão estável passa antes pelo canal beta (build de dev) por um período definido em D10.
- Rollback do app é **para frente**: publica-se uma versão de número maior com o código anterior. Restaurar o índice antigo do feed só impede que quem ainda não atualizou atualize.

### 5.6 Ajustes por prioridade

| Prio | Ajuste | Justificativa |
|---|---|---|
| P0 | Isolar dev×produção (redes, portas, webhook) | C1–C3 |
| P0 | Portão no canal estável do app + token por canal | C6, A13 |
| P0 | Backup externo e restauração ensaiada (banco, Evolution, releases) | C4, M8, M16 |
| P0 | Versão exata em produção + rollback por troca de versão | L4, A5 |
| P0 | Fechar a web de produção na borda | A12 |
| P0 | Completar o exemplo de `prod.env` e validar chaves no deploy | L1–L3 |
| P1 | Site e servidor de releases no deploy, por versão | L12, M11 |
| P1 | Certificado de autoridade pública e novo passo de assinatura | A11 |
| P1 | `control_plane` aceitar o canal estável | L14 |
| P1 | Gate da borda; métricas de host; alertas com destino; sonda externa | A4, A8, A9 |
| P1 | Limites de memória e log em Evolution, observabilidade e releases | M7 |
| P1 | Ensaio de migração antes do deploy | L10 |
| P2 | Delta no pacote do app (`vpk download` antes do `pack`) | Atualização menor para o cliente |
| P2 | `watchdog` via proxy; CORS fechado; ambiente do trace por variável | M1, M2, M9 |
| P2 | Deploy da dev atrás da CI; auditoria bloqueante; varredura de imagem | M4, M6 |
| P3 | Artefatos de release no R2; recuperação por instante; segunda VPS | Evolução |

Fora de proposta: Kubernetes/Swarm, réplica de banco e várias réplicas de serviço.

---

## 6. Plano de execução

**Dono** = ação manual sua. **IA** = executável por agente, por branch `feature/` → `dev` → CI, sem testes na máquina local. Cada fase traz os três eixos de observabilidade exigidos pelo projeto.

### Fase 0 — Levantamento (somente leitura)

- **Entregáveis:** `docker ps` de todos os projetos; redes e quem está em cada uma; `ss -tlnp`; `free -h`, `nproc`, `df -h`; `ufw status` e `iptables -S DOCKER-USER`; `sshd -T`; atualizações pendentes; existência e permissão de `/opt/smartcore/*/env/`; resto da v1; versão do Evolution; **estado do container de releases, tamanho de `/opt/smartcore/releases-data` e versões no feed**; **container do site em uso**; ambientes e tags protegidas no GitHub; visibilidade do repositório e das GitHub Releases (se públicas, o instalador beta já está baixável sem ticket); quais secrets de assinatura existem (só nomes).
- **Dono sugerido:** IA (leitura, com autorização para a sessão SSH) + Dono (GitHub e Hostinger).
- **Risco:** baixo.
- **Conclusão:** relatório entregue; D1 decidida com os números de memória e disco.
- **Estado (24/11/2026): feita.** Inventário de 23–24/11 resumido em R3.1; D1 decidida. Se o inventário não trouxe `sshd -T`, `iptables -S DOCKER-USER` e a lista de environments/secrets do GitHub, esses três entram no início da Fase 1.
- **Observabilidade & Auditoria:** sem evento de auditoria (só leitura). O relatório lista nomes de chave, nunca valores.

### Fase 1 — Saneamento de segurança

- **Entregáveis:**
  - Dono: revogar o token do GitHub e trocar as senhas de banco que estão em `settings.local.json`; trocar a `TYPESAFE_API_KEY`; revisor obrigatório no ambiente `production-windows` (o `prod` já tem); tags `win-v*` protegidas (as `vX.Y.Z` já têm ruleset); snapshot da VPS.
  - IA: remover as regras com segredo; `.gitignore` do repositório cobrindo `settings.local.json`; trocar o IP por apelido em `settings.json`; SSH só por chave, `fail2ban`, `unattended-upgrades`, regras `DOCKER-USER` (script novo, sem `ufw reset`).
- **Estado (24/11/2026): parcial.** Feito pelo plano irmão: `environment: prod` com revisor, rulesets de `main`, `dev` e tags `vX.Y.Z`. D8 decidida pelo dono no sentido oposto à recomendação (sessão root com permissão total; ver seção 7). Abertos: C5 (o `settings.local.json` local ainda tem 4 URLs de banco com senha, token do GitHub e um `Bearer`; o arquivo segue fora do `.gitignore` do repositório), `production-windows`, endurecimento de SSH e `DOCKER-USER`.
- **Risco:** médio (trancar o acesso). Mitigação: sessão aberta, segunda conexão testada, console da Hostinger.
- **Conclusão:** login por senha recusado; só 22/80/443 respondem de fora; credenciais antigas invalidadas e comprovadamente sem efeito.
- **Observabilidade & Auditoria:** log do `sshd` e do `fail2ban` recolhido pelo promtail; alerta de tentativa de login em excesso. Sem evento em `audit_log` (não é ação de aplicação). Nenhum valor de segredo em comando ou saída.

### Fase 2 — Isolamento dev×produção e correções do servidor

- **Entregáveis (IA):**
  1. Redes de telemetria por ambiente (C1).
  2. URL interna do webhook por variável, apelido por ambiente e prefixo no nome da instância (C2, A3), com testes; comando para regravar o webhook das instâncias da dev.
  3. Portas próprias de produção e blocos separados no Caddyfile (C3); `caddy validate` na CI; borda de produção só por tag (A4).
  4. Exemplo de `prod.env` completo (L2, L3); validação de chaves no deploy (L1); `pg_dump` lendo usuário e banco do `prod.env` (L6).
  5. Imagens por versão exata; rollback por `workflow_dispatch` com a versão como entrada (L4); sondas e teste de fumaça para `mcp_server` e `web` (L7).
  6. `restore-postgres.sh` lendo o `.env` do ambiente (L11); cópia externa do backup (C4); backup do Evolution (M8).
  7. Limites e rotação de log em Evolution e observabilidade (M7); `node_exporter`, `cAdvisor`, alertas de host (A8); recriação condicional da observabilidade.
  8. CORS fechado (M1), ambiente do trace por variável (M9), revisão de dados pessoais em log (M10).
- **Risco:** médio (mexe na dev em uso). Mitigação: validar em branch `ci/` antes da `dev`, um item por vez.
- **Conclusão:** CI verde; dev no ar após cada item; de um container da dev só resolvem nomes da dev; WhatsApp da dev funcionando após a regravação.
- **Estado (24/11/2026): quase toda feita** pelo plano `servidor-reestruturacao-dev-prod`. Feitos: itens 1 (C1), 3 (C3, A4), 4 (L1, L6; conferir L2/L3 contra `required-keys.prod`), 5 (L4, L7) e a parte de observabilidade do item 7. A parte do item 2 que é C2 foi feita de outro jeito: a prod registra `http://172.17.0.1:9211` e o `webhook_ingress` dela saiu da `evolution_net`. Abertos: prefixo de instância (A3), item 6 menos o L11 (resolvido em 24/11; seguem C4 e M8), limites do Evolution (M7), métricas de host (A8, ver Fase 2B), item 8 (M1, M9 — os 9 serviços Rust ainda chamam `init_telemetry(..., "production")` —, M10).
- **Observabilidade & Auditoria:** (a) evento `whatsapp.webhook.regravado` em nível `info` com `tenant_id`, `instance_id`, `env`; erro com `error_code`. (b) `audit_log`: `whatsapp.instance.webhook_update` por instância regravada, sem o token. (c) Token da instância e chave global seguem em `SecretString`; nenhum telefone completo em log.

### Fase 2B — Simplificação do servidor (cenário B)

Origem: inventário de 23–24/11/2026. Hoje são 49 containers, tetos que somam
≈ 13 GiB numa VM de 7,8 GiB, três montagens do socket do Docker e restos da v1.
O cenário B leva a ≈ 46 containers sem perder função. **Nenhum item desta fase
foi decidido pelo dono**: cada um depende da decisão indicada (seção 7). A
exceção é o item 2, que só aplica a decisão já tomada de manter a web fechada.

- **Entregáveis (IA, após a decisão de cada item):**
  1. **MinIO fora da dev (D21).** A prod já usa R2; a dev passa a usar um bucket R2 próprio de dev, com token restrito a ele. Remove `minio` e `minio-setup` do `dev.override.yml`, `MINIO_ROOT_PASSWORD` do `required-keys.dev` e o volume `minio_data` depois de copiar o que for preciso.
  2. **`web-tenant` fora da prod** (aplica a web fechada, A12/Fase 4): perfil `web-publica` no `docker-compose.base.yml`, ligado só na dev; a borda deixa de rotear `/v2/tenant` na prod.
  3. **Alloy no lugar do promtail (D22).** O Promtail está em fim de vida desde 02/03/2026, sem correções nem atualizações, e a Grafana indica o Alloy como substituto, com conversor da configuração (`info_aux`, seção "Revisão 3"). O Alloy também traz exportadores de host e de containers embutidos, o que cobre A8 sem subir `node_exporter` e `cAdvisor` à parte.
  4. **Socket do Docker em um só ponto (D23).** Um único `docker-socket-proxy`, com permissões mínimas por cliente; os dois `watchdog` e o coletor de logs passam a falar com ele. Fecha M2.
  5. **Tetos coerentes com a RAM.** Recalcular os `MEM_*` da dev para que prod + observabilidade + dev caibam em ≈ 7 GiB, mantendo os `oom_score_adj` de D1; alerta de memória do host acima de 85 %.
  6. **Limpeza dos restos (D24) — feita em 24/11:** volumes anônimos e redes órfãs, cron de `caddy reload`, `renew-ssl.sh` da v1 (a borda já renova o certificado sozinha) e o prune diário. Backup e lista em `/root/backups/2026-11-24-limpeza-d24/`.
  7. **Site e releases com projeto compose e deploy** (antecipa parte das Fases 3 e 8): sem container solto fora de projeto.
- **Risco:** médio para a dev (troca de storage e de coletor de logs). Mitigação: um item por vez, validado em branch `ci/` antes da `dev`; prod só por `deploy-infra.yml` ou tag.
- **Conclusão:** ≈ 46 containers; soma dos tetos ≤ RAM da VM; uma montagem do socket; nenhum container fora de projeto compose; nenhum resto da v1 no `crontab`.
- **Observabilidade & Auditoria:** (a) após a troca do coletor, conferir no Loki que todos os serviços de dev e prod seguem com `service` e `env`; métricas de host no Prometheus com alerta de memória e disco. (b) Sem evento de auditoria (mudança de infraestrutura, não de aplicação). (c) O proxy do socket fica só leitura para o coletor; credenciais do bucket R2 da dev só no secret `ENV_FILE_B64` do environment `dev`.

### Fase 3 — Site público por versão, no deploy de produção

- **Entregáveis (IA):**
  1. Job de build do site na CI: imagem `ghcr.io/…/smartcore-site`, com tag de versão e tag pelo hash do conteúdo de `docker/site/`; a origem continua sendo `docker/site/publico/`.
  2. Serviço `site` no `prod.override.yml` (porta 172.17.0.1:8085, `mem_limit`, `oom_score_adj` da prod, rotação de log, sonda `wget` na página inicial); a tag da imagem vai no `images.env` do bundle, como as demais (`SITE_TAG`), e não no `prod.env`. *(Revisão 3: `docker/prod/compose.yml` não existe mais.)*
  3. Inclusão do `site` no teste de fumaça do deploy; conferência do conteúdo (título da página) pelo domínio.
  4. CSP do site no bloco da borda; cabeçalhos mantidos; fontes hospedadas junto ou liberadas na CSP (B8).
  5. Teste na CI que **falha** se algum botão de acesso perder `data-acesso-desativado`.
  6. Troca do container atual do site (imagem `smartcore-site:local`, construído à mão e hoje sem projeto compose) pelo serviço novo, na mesma porta, com o antigo removido só depois do teste de fumaça.
- **Dono:** aprovar qualquer mudança de texto do site; a página não muda de conteúdo nesta fase.
- **Risco:** baixo; a troca na porta 8085 tem alguns segundos sem site. Fazer fora do horário comercial.
- **Conclusão:** site servido por imagem versionada do GHCR, implantado pelo `deploy-prod.yml`; botões "Entrar" e "Criar conta" inativos; `smartcore-site:local` removida do servidor.
- **Observabilidade & Auditoria:** (a) log de acesso do Caddy em JSON para o Loki, sem corpo de requisição; sonda externa de disponibilidade no domínio. (b) Sem evento de auditoria (conteúdo estático, sem estado). (c) O site não coleta dado pessoal; o único vínculo externo é o link de WhatsApp comercial já existente.

### Fase 4 — Web de produção fechada

- **Entregáveis (IA):**
  1. Borda de produção: `/v2/tenant/*` responde 404; `/v2/admin/*` e o gRPC-Web (`Content-Type: application/grpc-web*`) só para `ADMIN_IPS_PERMITIDOS` (IP fixo do dono ou faixa de VPN); gRPC nativo (`application/grpc`) segue aberto, pois é o caminho do app Windows.
  2. `web-tenant` de produção fora do `up` (perfil do compose `web-publica`); o build da imagem continua para a Fase A.
  3. Teste de fumaça **negativo** no deploy: de fora da lista, `/v2/admin/` e `/v2/tenant/` não podem responder 200.
  4. Verificação dos fluxos que hoje apontam para a web: convite por e-mail e redefinição de senha (M18). Resultado alimenta D12.
- **Dono:** informar o IP fixo ou optar por VPN (D17).
- **Risco:** médio — fechar demais deixa o dono sem painel; fechar de menos publica a web. Mitigação: testar o acesso do dono antes de remover a rota aberta; manter o acesso por túnel SSH documentado como reserva.
- **Conclusão:** de uma rede qualquer, `/v2/admin/` e `/v2/tenant/` não abrem; da rede do dono, o admin abre e opera; o app Windows conecta normalmente.
- **Observabilidade & Auditoria:** (a) log da borda com contagem de recusas por rota; alerta se `/v2/admin` responder 200 para IP fora da lista (consulta no Loki). (b) Login no admin já é auditado pela aplicação; sem evento novo. (c) Log da borda sem cabeçalho `Authorization`.

### Fase 5 — Provisionamento do ambiente de produção

- **Entregáveis:**
  - Dono: DNS de `auth.`, `mcp.` (se D16 = ligar), `releases.`, `grafana.`; bucket R2 de produção e token restrito; bucket de backup e token só de escrita; chave SMTP; chaves de LLM com teto; canal de alerta; `ENCRYPTION_KEY` e `JWT_SECRET` guardadas fora do servidor.
  - IA: `prod.env` e `releases.env` montados com os valores recebidos por canal seguro; par RS256 do MCP gerado no servidor; `observability.env` com senha nova e destino de alerta; conferência por nome de chave.
- **Risco:** médio (segredo errado só aparece no boot). Mitigação: validação de chaves no deploy.
- **Conclusão:** `diff` de nomes de chave vazio; nenhum valor "distinto" igual ao da dev (comparação por hash); alerta de teste recebido.
- **Observabilidade & Auditoria:** (a) sem log de aplicação nesta fase. (b) Sem evento de auditoria. (c) Valores nunca passam por conversa, argumento de comando ou log; conferência só por nome ou hash.

### Fase 6 — Banco de produção

- **Entregáveis (IA):** primeira subida de `postgres`, `redis`, `redis-bus` e `data_postgres` (53 migrações em banco vazio); `provision-db-role.sh`; `DATABASE_URL` no papel restrito; prova de RLS; primeiro dump copiado para fora; **restauração ensaiada** em banco descartável.
- **Dono:** D4 (banco limpo ou ETL da v1). Com ETL entram E1 e E4 do N12, e o superusuário é criado depois.
- **Risco:** alto com ETL, baixo com banco limpo.
- **Conclusão:** migrações aplicadas; papel restrito em uso; dump externo restaurado com contagem conferida; tempo de restauração anotado.
- **Observabilidade & Auditoria:** (a) eventos `backup.concluido`/`backup.falhou` já emitidos pelo `pg_backup`; acrescentar `backup.copia_externa.concluida`/`.falhou` e alerta de cópia atrasada. (b) Com ETL: `migracao.iniciada`/`.concluida` (já existem). (c) Credenciais decifradas do ETL não entram em log nem no relatório de conciliação.

### Fase 7 — Evolution compartilhado

- **Entregáveis (IA):** confirmar a versão `0.7.3-wa2` (alinhar se houver outra instância, e parar aí); produção na `smart_core_v2_evolution_net` com o apelido próprio; chave global trocada uma vez (Dono fornece); backup do banco e do volume; limites.
- **Regra:** o deploy de produção não sobe nem recria o Evolution; só confere rede e saúde.
- **Risco:** alto para a dev durante a troca de chave e a regravação (janela curta). Sessões pareadas se mantêm enquanto os volumes não forem tocados.
- **Conclusão:** instância `prod-…` criada; mensagem chega só no `webhook_ingress` de produção; dev segue funcionando.
- **Observabilidade & Auditoria:** (a) contador de webhooks recusados por token inválido, por ambiente; alerta se passar de zero após a regravação. (b) `whatsapp.instance.create` com o nome prefixado. (c) Chave global e token de instância fora do log.

### Fase 8 — Servidor de releases em produção

- **Entregáveis (IA):**
  1. Imagem `…-releases:<versão>` construída quando `server/apps/releases_server/**` ou `docker/releases/**` mudam, e não a cada tag do app.
  2. Projeto compose `releases-stack` (nome atual no servidor), implantado pelo `deploy-infra.yml` como componente `releases` (é infra compartilhada: serve o beta e o estável; regra R-D1): `pull` por versão, `up -d`, sonda, teste de fumaça em `/health` e em `/api/installers/stable`; `releases.env` em `/opt/smartcore/releases/env/`; rotação de log.
  3. Token de upload por canal (A13); `control_plane` aceitando `stable` (L14); `RELEASES_INTERNAL_URL` apontando para o serviço.
  4. Armazenamento: disco local mantido, com cópia para bucket R2 após cada publicação e retenção das N últimas versões por canal (M16). GitHub Release segue como segunda cópia.
  5. Reescrita de `RUNBOOK_RELEASES.md` com o que o código faz (M17): publicar, correção para frente, troca de segredo (recriar os dois lados juntos, sem chave antiga), restauração do diretório.
  6. Sonda externa em `releases.smartcoreassistant.com.br/health`.
- **Dono:** fornecer os dois tokens de upload e o segredo de download; D14.
- **Risco:** médio — o servidor já atende o canal beta em uso; a troca de imagem e de token interrompe publicações por minutos. Clientes instalados não são afetados (só consultam o feed).
- **Conclusão:** servidor em versão exata, implantado pelo deploy; envio com token do beta no canal estável é recusado; link de download do estável emitido e auditado; cópia externa conferida; restauração do diretório ensaiada.
- **Observabilidade & Auditoria:** (a) eventos `release.publicada` (canal, versão, tamanho, sha256), `release.upload.recusado` (motivo), `release.download` (canal, versão, `jti`), em JSON; alerta de upload recusado em sequência e de `/health` fora do ar. (b) `audit_log`: `release.download_link.emitido` (já existe em `security.audit`), mais `release.publicada` com a origem (execução do workflow). (c) O ticket inteiro, o token de upload e o segredo nunca vão para o log; só `jti` e usuário.

### Fase 9 — Primeiro deploy do servidor por tag

- **Entregáveis:** tag `v1.0.0` em commit de `main` com CI verde; aprovação no ambiente `prod`; stack no ar com site, admin restrito e releases; superusuário criado; configurações gerais e chaves de LLM gravadas pelo painel.
- **Estado (24/11/2026): mecanismo feito, versão do go-live pendente.** A prod subiu por tag com aprovação em 22/11 (`v0.2.1`, 64 s) e está em `v0.2.2` (86 s); marcadores de deploy no Grafana já existem. Faltam: hotfix `v0.2.3` ainda sem tag, ensaio de rollback `v0.2.2 → v0.2.1` (plano irmão, R6) e, para o go-live público, o site, o admin restrito e o releases por versão. O número da versão do go-live (`v1.0.0` ou seguir em `0.x`) fica em D10.
- **Dono:** aprovar; criar o superusuário; parear o primeiro número.
- **Risco:** médio. Falha no teste de fumaça interrompe o deploy; a dev não depende da produção.
- **Conclusão:** todos os serviços com sonda saudáveis; site no domínio; `/v2/admin` só para o dono; `/v2/tenant` fechado; `releases.` respondendo; nenhum alerta aberto.
- **Observabilidade & Auditoria:** (a) painel de saúde dos serviços com o namespace de produção; anotação de deploy no Grafana com a versão. (b) `cutover.iniciado`/`.concluido` e criação do superusuário auditados. (c) Chaves de LLM gravadas pelo painel, cifradas; nunca por SQL.

### Fase 10 — App Windows: assinatura, canal estável e primeira versão

- **Entregáveis:**
  - Dono: contratar o certificado (D11), com validação da empresa; fornecer as credenciais do serviço de assinatura como secrets do ambiente `production-windows`.
  - IA:
    1. Passo de assinatura trocado para `--signTemplate` ou `--azureTrustedSignFile`, conforme D11; verificação de assinatura mantida, agora exigindo o editor esperado.
    2. Portões do canal estável (C6): tag a partir de `main`, CI verde do commit, ambiente com revisor, falha de upload reprova.
    3. `packId` próprio do beta, se D13 for aprovada.
    4. `vpk download` antes do `pack`, para gerar delta (P2).
    5. Ensaio completo em `ci/release-windows-*`, depois `win-v1.0.0-beta.N` no canal beta, depois `win-v1.0.0`.
    6. Envio do `Setup.exe` para análise da Microsoft se houver detecção.
    7. Página de instruções do instalador (SHA-256, o que esperar do SmartScreen nas primeiras semanas).
- **Risco:** alto — prazo e custo do certificado estão fora do nosso controle; a primeira versão estável define a reputação. Mitigação: começar a contratação já na Fase 1; piloto com poucos clientes acompanhados.
- **Conclusão:** `Setup.exe` estável assinado com o nome da empresa; instalado em máquina limpa, fora da rede do dono; o app conecta em produção; uma segunda versão estável chega sozinha ao app instalado; tag estável fora de `main` ou sem aprovação é recusada.
- **Observabilidade & Auditoria:** (a) resumo do job com versão, canal, SHA-256, editor e thumbprint; no servidor, `release.publicada`. No app, falha de atualização fica no log local do Velopack; acrescentar o envio da versão em uso no login, para saber quantos clientes estão em cada versão. (b) `audit_log`: `release.publicada` e `release.download_link.emitido`. (c) Credenciais de assinatura só como secret de ambiente; nenhuma chave privada no runner.

### Fase 11 — Validação, rollback ensaiado e go/no-go

- **Entregáveis:**
  - Ponta a ponta pelo **app Windows**: instalação limpa, login, pareamento, mensagem recebida e respondida pela IA, mídia, convite, isolamento entre dois tenants, atualização automática.
  - Rollback do servidor: publicar `v1.0.1` sem mudança, voltar para `v1.0.0` pela troca de versão, medir o tempo.
  - Correção para frente do app: publicar uma versão estável de teste e, em seguida, a de número maior com o código anterior; medir o tempo até um app aberto receber.
  - Restauração: banco e diretório de releases a partir da cópia externa.
- **Go:** críticos e altos fechados ou aceitos por escrito; restauração e rollback provados; alerta chegando; ponta a ponta completa; instalador assinado pela empresa (ou aceite escrito de operar o piloto com aviso do SmartScreen); 48 h sem reinício inesperado.
- **No-go:** mensagem de produção chegando na dev, ou o contrário; **`/v2/admin` ou `/v2/tenant` respondendo a qualquer rede pública**; **botões do site ativos**; tag estável publicável sem aprovação; restauração falhando; alerta sem destino; memória acima de 85 % em repouso.
- **Observabilidade & Auditoria:** (a) todos os alertas disparados uma vez de propósito, com registro de recebimento. (b) Conferência de que cada ação sensível do roteiro gerou linha em `audit_log`. (c) Varredura do Loki por telefone/CPF completos no período do teste.

### Fase 12 — Pós-go-live

- **Entregáveis (IA):** `cargo update` dos avisos e do 0459 (com ensaio do instalador); auditoria bloqueante e varredura de imagem; subida do Flutter; retry do `apt-get`; deploy da dev atrás da CI; recuperação por instante; limpeza do legado; enforce de quotas conforme o N12.
- **Dono:** rotina mensal de restauração, trimestral de troca de segredos; acompanhar a validade do certificado.
- **Conclusão:** 72 h de tráfego real sem alerta aberto; runbooks reescritos com o que de fato aconteceu.
- **Observabilidade & Auditoria:** (a) alerta de certificado a 60 dias do vencimento e de versão antiga do app ainda em uso. (b) Sem evento novo. (c) Sem mudança.

### Fase A — Abertura da web ao público (ADIADA)

**Não entra neste go-live.** Só começa com aprovação escrita do dono (D18). Quando entrar: reabrir `/v2/tenant` e `/v2/admin` na borda, ligar o perfil `web-publica`, preencher `S3_CORS_ALLOWED_ORIGINS` e a lista de origens do gRPC-Web, ativar os botões do site (e ajustar o teste da Fase 3), revisar limites de cadastro e verificação de e-mail (`RUNBOOK_CADASTRO_TENANT.md`), e repetir a Fase 11 pela web.

### O que é manual

| Ação | Quem |
|---|---|
| Revogar token e trocar senhas e chaves expostas; trocar a chave global do Evolution | Dono |
| Contratar o certificado de assinatura e validar a empresa | Dono |
| DNS, buckets e tokens R2, chave SMTP, chaves de LLM, canal de alerta | Dono |
| Ambientes protegidos, tags protegidas, visibilidade do repositório | Dono |
| IP fixo ou VPN para o admin; snapshot da VPS; eventual troca de plano | Dono |
| Aprovar cada deploy de servidor e cada versão estável do app; criar o superusuário; parear números | Dono |
| Guardar `ENCRYPTION_KEY` e `JWT_SECRET` fora do servidor | Dono |
| Código, compose, workflows, scripts, montagem dos `.env` com os valores recebidos, ensaios, runbooks | IA |

---

## 7. Decisões do dono (com recomendação)

Nenhuma bloqueia as Fases 0 a 3. D11 tem prazo externo: decidir cedo.

| # | Decisão | Recomendação |
|---|---|---|
| D1 | Mesma VPS da dev ou VPS própria | **Decidida (22/11/2026):** mesma VPS (7,8 GiB), tetos por ambiente nos `.vars` e `oom_score_adj` dev 900 / observabilidade 300 / prod 0. A recomendação original (16 GB) foi superada; a soma dos tetos (≈ 13 GiB) acima da RAM vai para a Fase 2B |
| D2 | Domínio | Manter `smartcoreassistant.com.br` (já embutido nos builds) |
| D3 | Runner de produção | O mesmo agora, com as proteções da Fase 1; próprio depois do go-live |
| D4 | Banco limpo ou ETL da v1 | Banco limpo se a v1 já estiver desligada; a Fase 0 confirma |
| D5 | Backup | Dump a cada 6 h; 30 dias locais; cópia externa por 90 dias, credencial só de escrita; restauração mensal |
| D6 | Retenção de logs, traces e mídia | 14 dias para logs e traces; auditoria no banco sem expiração; mídia 90 dias |
| D7 | Canal de alerta | Webhook em canal lido no celular + sonda externa no domínio e no `releases.` |
| D8 | Sessão do Claude Code como root no VPS | **Decidida pelo dono, diferente da recomendação:** sessão `claude-rc` como root, por Remote Control, com `--permission-mode bypassPermissions` e `IS_SANDBOX=1`, sem nenhuma regra `ask`, no mesmo VPS da prod. **Divergência registrada:** a recomendação era usuário sem `prod.env` e sem grupo `docker`. Com a decisão, a sessão lê o `prod.env`, controla os containers da prod e não pede confirmação; o controle passa a ser só a conta do Claude do dono e a disciplina de operação (CLAUDE.md, backups em `/root/backups/`, deploy só pelos workflows) |
| D9 | Risco do Evolution compartilhado | Aceitar agora, com prefixo e backup; rever com mais de um cliente pagante |
| D10 | Versões e política de release | Servidor `v1.0.0` e app `win-v1.0.0`, ambos a partir de `main`; toda versão estável do app fica antes no beta por 3 dias úteis |
| D11 | Certificado de assinatura | Conferir primeiro a elegibilidade no serviço da Microsoft (Artifact Signing); se a empresa brasileira não for aceita, certificado OV com assinatura em nuvem. Não comprar EV |
| D12 | Convite e redefinição de senha com a web fechada | Depende da verificação da Fase 4. Se o fluxo exigir página web, preferir concluir dentro do app Windows a abrir a web do tenant |
| D13 | `packId` próprio para o beta | Sim: permite beta e estável na mesma máquina e evita troca de canal por engano |
| D14 | Feed do Velopack público | Aceitar por ora (o app exige login); rever se o pacote passar a conter algo sensível |
| D15 | Loja da Microsoft como canal futuro | Avaliar depois do go-live: elimina o aviso do SmartScreen, mas muda empacotamento e atualização |
| D16 | Servidor MCP (`auth.` e `mcp.`) em produção no dia 1 | Deixar desligado no primeiro go-live e ligar em versão própria: é superfície web pública e não é necessária para o atendimento |
| D17 | Acesso ao admin de produção | Lista de IP se houver IP fixo; senão, VPN na VPS. Túnel SSH como reserva |
| D18 | Abertura da web e dos botões do site | **Adiada.** Só com aprovação escrita, após a Fase 11 aprovada e com a Fase A executada |
| D19 | Distribuição do instalador aos primeiros clientes | Link com ticket, gerado pelo dono no admin a cada cliente (vale 5 minutos), ou envio do arquivo com o SHA-256. Botão público de download só na Fase A |
| D20 | Transcrição de áudio e quotas no dia 1 | Transcrição desligada e ligada por tenant; quotas em modo log por duas semanas |
| D21 | MinIO na dev (Fase 2B) | **Adiada pelo dono (24/11):** sem gasto novo agora; o MinIO da dev fica como está. Retomar com bucket R2 de dev quando houver orçamento |
| D22 | Alloy no lugar do promtail (Fase 2B) | **Pendente.** Recomendação: trocar, pelo fim de vida do Promtail e para cobrir métricas de host (A8) no mesmo coletor |
| D23 | Socket do Docker em um só ponto (Fase 2B) | **Pendente.** Recomendação: um `docker-socket-proxy` com permissão mínima por cliente |
| D24 | Limpeza dos restos do servidor (Fase 2B) | **Feita em 24/11**, com backup e lista em `/root/backups/2026-11-24-limpeza-d24/` (ver R3.1, "Restos"). Ficou o prune semanal de 168 h, para o rollback achar a imagem anterior no disco |

Decisões do dono já tomadas, registradas na revisão 3: site junto com o admin na
stack de prod; web fechada (D18 adiada); canal estável do app com portões (C6);
app Windows com certificado de autoridade pública (A11; o fornecedor segue em
D11); D1; D8.

---

## 8. Riscos e o que NÃO fazer

### 8.1 Riscos

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Produção falando com serviço da dev por nome repetido | Alta se nada for feito | Crítico | Fase 2; `getent` antes do go-live |
| Mensagem de WhatsApp de produção entregue na dev | Alta se nada for feito | Crítico | Fase 2; teste da Fase 7 |
| Versão estável ruim distribuída a todos os clientes | Média | Crítico | C6; beta antes do estável; correção para frente ensaiada |
| Instalador bloqueado pelo Windows no cliente | Alta hoje | Alto (cliente não instala) | Fase 10; piloto acompanhado; envio para análise |
| Certificado demora ou a empresa não é aceita | Média | Alto (atrasa o go-live público) | Iniciar na Fase 1; piloto com aviso aceito por escrito |
| Web publicada sem querer | Média | Alto | Fase 4; teste negativo no deploy; critério de no-go |
| Falta de memória derrubando os dois ambientes | Média (uso real ≈ 1,5 GiB, mas tetos somam ≈ 13 GiB em 7,8 GiB) | Alto | D1 (`oom_score_adj`) + Fase 2B (tetos e alerta de host) |
| Sessão root com permissão total no servidor da prod (D8) | Baixa | Crítico (lê `prod.env`, para containers, apaga volumes sem confirmação) | Disciplina de operação: deploy só por workflow, backup antes de editar, nada de `compose` fora do bundle |
| Push na `dev` implanta sozinho, sem esperar a CI | Média | Médio (dev quebrada) | Validar mudanças arriscadas em branch `ci/`; Fase 12 (deploy da dev atrás da CI) |
| Perda da VPS sem cópia externa | Baixa | Catastrófico | C4 |
| Perda da `ENCRYPTION_KEY` | Baixa | Alto | Cópia fora do servidor |
| Migração quebrada no boot | Média | Alto | Ensaio em banco descartável |
| App antigo incompatível com servidor novo | Média | Médio | Regras da seção 5.5 |
| Servidor de releases fora do ar | Baixa | Médio (sem correção e sem instalador) | Sonda externa; GitHub Release como segunda cópia |
| Trancar o SSH ao endurecer | Baixa | Médio | Sessão aberta + console |
| Este plano divergir do servidor real | Média | Médio | Fase 0 antes de qualquer mudança |

### 8.2 O que NÃO fazer

1. Não subir compose de produção fora do bundle (`/opt/smartcore/prod/releases/current`) nem a partir do checkout `/opt/smartcore/ops/...`; prod só por tag (`deploy-prod.yml`) ou `rollback-prod.yml`. *(Revisão 3: substitui "não subir `docker/prod`", pasta que não existe mais.)*
2. Não editar `docker/*/.env` à mão; a fonte é `/opt/smartcore/*/env/`.
3. Não colocar `COMPOSE_PROJECT_NAME` em `dev.env` nem em `prod.env`.
4. Não trocar, recriar nem apagar volumes do Evolution; nenhuma versão além da `0.7.3-wa2` (27/11: patch do panic do evento Archive; troca de 26/11: a `0.7.2-wa1` não dava ack na stanza `<status>` e a recepção travava; rollback: padrão do compose de volta e `deploy-infra`).
5. Não rodar `infra/server-setup.sh` nem `infra/cleanup-hostinger.sh` no servidor em uso.
6. Não reaproveitar segredo da dev em produção (exceto os compartilhados por decisão).
7. Não usar `:latest` nem `:dev` em produção, incluindo releases, site e borda.
8. Não exibir valor de segredo em comando, log ou conversa.
9. Não rodar testes na máquina local; não fazer teste de carga contra o Evolution compartilhado.
10. Não restaurar backup em produção sem ensaio em dev (o `restore-postgres.sh` foi corrigido em 24/11, mas a restauração real ainda não foi ensaiada).
11. Não aplicar SQL direto em produção para configuração de tenant sem invalidar `core:settings:invalidate`.
12. **Não publicar a web admin/tenant nem ativar os botões do site** sem a decisão D18.
13. **Não criar tag `win-vX.Y.Z` (estável) antes dos portões da Fase 10.**
14. **Não pedir a cliente que instale o certificado de desenvolvimento como raiz confiável.**
15. **Não trocar de certificado ou de nome de editor entre versões** sem necessidade: zera a reputação.
16. Não republicar uma versão do app com o mesmo número; correção é sempre número maior.
17. Não dar `compose down` na stack de produção (leva o site junto); usar `up -d` e reinício por serviço.
18. Não mudar borda, observabilidade, Evolution ou releases por outro caminho que não o `deploy-infra.yml`. *(Revisão 3: o push na `dev` já não troca a borda.)*
19. Não exportar o contexto do dotcontext sem reverter `.context/agents/`.

---

## 9. Relação com outros planos

| Plano | Estado | Relação |
|---|---|---|
| `n12-cutover-producao` | preenchido, não iniciado | ETL da v1 e enforce. Entra na Fase 6 (se D4 = ETL) e na Fase 12 |
| `servidor-releases-windows` | `ready-para-detalhamento` | Plano original do servidor de releases; previa "página principal com botão de download". O botão fica para a Fase A. O que falta dele para produção está na Fase 8 |
| `windows-releases-v01-beta` | `aguardando-review`; substitui parcialmente o anterior | Entregou o canal beta para superusuários do admin de dev, o ticket e a auditoria. Este plano parte dali: canal estável, portões, certificado público, implantação por versão (Fases 8 e 10). Ao fechar a Fase 10, registrar lá o que foi superado |
| `visual-cliente-windows` | preenchido, não iniciado | Splash e marca do app. Independente; se a paleta mudar, entra antes da `win-v1.0.0` para não gastar reputação do instalador com uma versão que será trocada em seguida |
| `infra/RUNBOOK_ROBUSTEZ.md` | vigente | As duas pendências de lá (cópia externa, métricas de host) fecham aqui |

---

## 10. Correções aplicadas nesta revisão

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 1 | Incluídos o app Windows, o servidor de releases e o site no inventário, na segurança, nos parâmetros, na arquitetura e nas fases | A versão anterior tratava só da stack de servidor | `release-windows.yml`, `server/apps/releases_server`, `docker/releases`, `docker/site` |
| 2 | Novo bloqueador crítico C6 (canal estável sem portão) e altos A11, A12, A13 | Atualização silenciosa e obrigatória, sem aprovação, é o maior risco de distribuição | `release-windows.yml:28-38`; `auto_update_native.dart:36-43` |
| 3 | Web de produção passa a ficar **fechada**; site entra na stack de produção | Decisão do dono | `docker/edge/Caddyfile:36-67` |
| 4 | Retirada a validação "login web" e "download pelo R2 com CORS" dos critérios; a validação é pelo app Windows | Consequência do item 3 | — |
| 5 | C5 corrigido: a regra com segredo **existe**, mas não como chave "senha". São URLs de banco com senha embutida, um token do GitHub e um cabeçalho `Bearer` | A versão anterior registrou "não localizada" depois de buscar só pelas palavras "senha/password" | busca por padrão em `settings.local.json` |
| 6 | Servidor MCP deixa de ser pressuposto do dia 1 (D16) | É superfície web pública, e a web está adiada | `docker/edge/Caddyfile:177-206`, `:255-278` |
| 7 | Passo de assinatura: o fluxo com PFX em secret não serve para certificado de autoridade pública | Chave não exportável desde 01/06/2023 | documentação do Velopack (assinatura) |
| 8 | EV descartado; elegibilidade do serviço da Microsoft a conferir | EV perdeu a reputação imediata em 2024; a lista de países não inclui o Brasil | documentação da Microsoft |
| 9 | Rollback do app descrito como correção para frente | O app não rebaixa versão (parâmetro de downgrade não usado) | `auto_update_native.dart`; plugin `velopack_flutter` |
| 10 | Registrado que não há delta | O job empacota em pasta vazia, sem `vpk download` | `release-windows.yml:222-236`; documentação do Velopack (deltas) |
| 11 | Runbook de releases marcado como divergente do código | Descreve rollback por git e troca de segredo com chave antiga, que não existem | `doc_dev/runbooks/RUNBOOK_RELEASES.md` × `releases_server/src` |
| 12 | Cada fase ganhou a subseção "Observabilidade & Auditoria" | Exigência da skill `plan-restructuring` | `.context/skills/plan-restructuring/SKILL.md` |
| 13 | Contagem de migrações corrigida para 53 | A pasta tem 53 arquivos `.sql` e um `README.md` | `server/crates/infrastructure_postgres/migrations/` |

### Revisão 3 (24/11/2026)

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 14 | Nova seção R3 com o estado real e a tabela do que ficou superado; seções 2.1–2.4 marcadas como histórico | A revisão 2 foi escrita sem acesso ao servidor e antes da reestruturação dev/prod | Inventário de 23–24/11; `docker/stack/`; plano `servidor-reestruturacao-dev-prod` |
| 15 | Produção registrada como no ar (`v0.2.1` em 22/11, `v0.2.2` hoje); F0 e F9 marcadas como feitas | A revisão 2 dizia que a prod nunca subiu | `servidor-reestruturacao-dev-prod.md` (R6); servidor |
| 16 | C1, C2, C3, L1, L4–L9, A4 marcados como resolvidos; A5, M4, M7 como parciais | Resolvidos pela stack base + overlays, bundle, `deploy-infra.yml` e `e76adaf2` | `docker/stack/*.vars`, `prod.override.yml`, `infra/deploy/`, `.github/workflows/deploy-infra.yml` |
| 17 | L11 mantido com causa nova | `restore-postgres.sh` aponta para `docker/<env>/compose.yml`, removido | `infra/restore-postgres.sh:28-32` |
| 18 | Topologia 5.2 alinhada: releases como componente do `deploy-infra.yml`, projeto real `releases-stack`; borda e Evolution pelo `deploy-infra.yml` | Regra R-D1 e `CLAUDE.md` ("infra compartilhada só por `deploy-infra.yml`") | `CLAUDE.md`, seção "Ambientes na VPS" |
| 19 | Números de memória corrigidos (7,8 GiB, tetos ≈ 13 GiB, uso ≈ 1,5 GiB) e D1 marcada como decidida | Inventário | Servidor; `docker/stack/*.vars`; `docker/observability/compose.yml` |
| 20 | Nova Fase 2B (cenário B: MinIO fora da dev, `web-tenant` fora da prod, Alloy, socket em um ponto, tetos, restos) e decisões pendentes D21–D24 | Princípio de simplificação do inventário; sem decisão do dono, ficam pendentes | Inventário de 23–24/11 |
| 21 | Decisões do dono registradas: site com o admin na stack de prod, web fechada, canal estável com portões, certificado público, D8 com permissão total (divergência e risco anotados) | Decisões tomadas na conversa de 23–24/11 | Dono |
| 22 | Referências a `docker/prod/compose.yml`, `environment: production` e `smart-core-v2-releases` trocadas pelo que existe | Nomes antigos | Repositório na `dev` `0af1fd23` |

## Fontes externas

- [Velopack — assinatura de código](https://docs.velopack.io/packaging/signing)
- [Velopack — pacotes delta](https://docs.velopack.io/packaging/deltas)
- [Microsoft — reputação no SmartScreen](https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation)
- [Microsoft — opções de assinatura de código](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)
