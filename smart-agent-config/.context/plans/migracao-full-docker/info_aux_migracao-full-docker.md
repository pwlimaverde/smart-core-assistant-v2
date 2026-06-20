# Documentação Auxiliar — Migração Full-Docker (dev + prod)

> Gerado em: 2026-06-20
> Plano canônico: `.context/plans/migracao-full-docker.md`
> Plano completo: `.context/plans/migracao-full-docker/plano_completo_migracao-full-docker.md`

Este documento consolida a documentação ATUAL das ferramentas externas usadas na
migração da infraestrutura híbrida (systemd + Docker) para **full-Docker** com dois
ambientes (dev/prod) isolados e observabilidade compartilhada. As imprecisões dos
relatórios de coleta foram corrigidas para refletir as fontes-de-verdade do projeto
(CI atual, Caddyfile atual, manifests).

---

## 0. Inventário do estado atual (fonte da verdade do repo)

### Serviços Rust (`server/apps/`) — 7 binários
`data_postgres`, `data_redis`, `data_storage`, `control_plane`, `messaging_gateway`,
`worker`, `runtime_api`. Workspace em `server/Cargo.toml` (resolver 2), 9 crates de lib.

### Comunicação inter-serviços (`server/crates/transport`)
- Transport própria multiplexada sobre **UDS** (default) ou **TCP**.
- Endpoint lido de `SMARTCORE_{SVC}_ENDPOINT` (mesmo nome usado para **bind** em
  `Server::from_env` e para **dial** em `conectar_cliente`).
- ⚠️ **BLOQUEADOR para Docker DNS**: `Endpoint::parse` (`runtime.rs:25-37`) faz
  `addr_str.parse::<SocketAddr>()` — **só aceita IP:porta numérico**. Hostnames de
  serviço Docker (`tcp://data_postgres:9101`) **falham no parse hoje**. Requer
  alteração na transport (ver §6).
- `RUNTIME_API_GRPC_WEB_ADDR` (default `0.0.0.0:50051`): fachada gRPC-Web do
  `runtime_api`, em HTTP/1.1 PLANO (Tonic escuta HTTP/1.1; **sem h2c**). É o Caddy
  que faz a borda TLS e o proxy por path `/smartcore.contracts.*`.

### Stack de dados (`docker/compose/data.yml`) — já em Docker
`postgres` (pgvector/pgvector:pg16), `redis` (cache, allkeys-lru), `redis-bus`
(eventos, noeviction), `minio` (S3 dev). Em prod a mídia vai para Cloudflare R2.

### Observabilidade (`docker/compose/observability.yml`) — já em Docker
`otel-collector`, `loki`, `tempo`, `prometheus`, `grafana`, `promtail`. Rede
`smartcore_v2_network` (external). Apps enviam OTLP para `otel-collector:4317`.

### Borda / Web
- Caddy (hoje no host via systemd) faz TLS automático + proxy gRPC-Web + serve o
  bundle Flutter (`/srv/smart-core-admin/{env}/web`) sob `/v2/admin/*`.
- Admin Flutter Web (`clients/apps/smart-core-admin`): buildado no CI com
  `flutter build web --wasm --base-href /v2/admin/ --dart-define=SMARTCORE_API_ENDPOINT=...`.

### Build / artefatos confirmados
- `server/.sqlx/` versionado com **111** queries → `SQLX_OFFLINE=true` funciona na imagem.
- `server/rust-toolchain.toml` = `channel = "stable"`. `server/Cargo.lock` presente.
- `server/crates/contracts/build.rs` gera gRPC/FlatBuffers → exige **protoc + flatc** no build.
- flatc fixado no projeto: **v25.12.19** (mesma URL do CI, ver §1).

---

## 1. cargo-chef — Dockerfile multi-stage de workspace Rust

> Fonte: github.com/LukeMathWalker/cargo-chef ; lpalmieri.com/posts/fast-rust-docker-builds ;
> ajustado às fontes-de-verdade do projeto.

**Versão atual cargo-chef:** ~0.1.x (usar a imagem `lukemathwalker/cargo-chef`).
**Pin de Rust:** o projeto usa `stable`; para cache determinístico, **fixar uma versão
concreta** (ex.: `rust:1-bookworm` recente compatível com tonic 0.14 / sqlx 0.9) e usar
a mesma em todos os estágios.

### Fluxo de 3 estágios
| Estágio | Comando | Resultado |
|---------|---------|-----------|
| planner | `cargo chef prepare --recipe-path recipe.json` | grafo de deps |
| cooker  | `cargo chef cook --release --recipe-path recipe.json` | layer de deps cacheada |
| builder | `cargo build --release --workspace` | 7 binários em `target/release/` |

### Pontos críticos / correções
- **flatc**: NÃO existe binário solto `flatc` no release. Usar a **mesma URL/método do
  CI** (zip `Linux.flatc.binary.g++-13.zip`):
  ```dockerfile
  RUN wget -q -O /tmp/flatc.zip \
        https://github.com/google/flatbuffers/releases/download/v25.12.19-2026-02-06-03fffb2/Linux.flatc.binary.g%2B%2B-13.zip \
   && unzip -q -o /tmp/flatc.zip -d /tmp/flatc_extracted \
   && mv /tmp/flatc_extracted/flatc /usr/local/bin/flatc \
   && chmod +x /usr/local/bin/flatc && rm -rf /tmp/flatc.zip /tmp/flatc_extracted
  ```
- **protoc**: `apt-get install -y protobuf-compiler` (Debian bookworm).
- **SQLX_OFFLINE**: `ENV SQLX_OFFLINE=true` + `COPY server/.sqlx ./.sqlx` no builder.
- **flatc/protoc são necessários no estágio que roda `cargo chef cook` E no `cargo build`**
  (o `build.rs` do contracts roda em ambos). Instalar nos dois estágios (ou usar um único
  estágio base com as ferramentas).
- **Contexto de build**: o workspace está em `server/`. O build context do Dockerfile
  deve cobrir `server/` (cuidado com paths relativos no compose / CI).
- **Cache invalidation**: copiar só os `Cargo.toml`/`Cargo.lock` antes do `cook`; copiar o
  código-fonte só depois.

### Runtime stage (imagem final única, 7 binários)
- Base `debian:bookworm-slim`.
- Pacotes runtime: `ca-certificates`, `libssl3` (TLS do reqwest/aws-sdk/tonic). `libpq5`
  **não** é necessário (sqlx usa driver puro-Rust, sem libpq).
- Usuário não-root (`useradd -r -s /usr/sbin/nologin smartcore`).
- Copiar os 7 binários para `/usr/local/bin/`. **Sem ENTRYPOINT fixo** — o `command:` do
  compose escolhe qual binário roda por serviço.
- `curl` opcional para healthcheck (ou healthcheck via TCP).

---

## 2. Docker Compose — 2 ambientes isolados + observabilidade compartilhada

> Fonte: docs.docker.com/compose (Compose Specification, profiles, multiple files,
> project name, networking). **Sem o campo `version:`** (legado, deprecado).

### Isolamento por ambiente
- Selecionar ambiente por `COMPOSE_PROJECT_NAME=smartcore-dev|smartcore-prod` +
  `--env-file docker/compose/env/{dev,prod}.env`.
- Nomes de **volumes, redes e containers** derivam do project name → isolamento
  automático entre dev e prod usando o MESMO arquivo compose.
- Usar `name:` no topo do compose só se quiser nome fixo; aqui deixamos o project name
  controlar (não fixar `name:` no arquivo base, para dev/prod divergirem).

### Profiles (MinIO só em dev)
```yaml
services:
  minio:
    image: minio/minio:latest
    profiles: ["dev"]      # só sobe quando COMPOSE_PROFILES inclui "dev"
```
No `dev.env`: `COMPOSE_PROFILES=dev`. No `prod.env`: omitido (MinIO não sobe; usa R2).

### Redes — duas camadas
```yaml
networks:
  internal:                # mesh interno do ambiente (isolado por project name)
    driver: bridge
  observability:           # compartilhada entre dev, prod e a stack LGTM
    name: smartcore_observability
    external: true
```
- A stack de observabilidade (projeto separado `smartcore-observability`) **cria** a rede
  `smartcore_observability`; os ambientes a referenciam como `external: true`.
- Serviços que emitem OTLP participam de **duas redes** (internal + observability). Ex.:
  ```yaml
  worker:
    networks: [internal, observability]
  ```
- Ordem de subida: **primeiro** a stack de observabilidade (cria a rede), depois dev/prod.

### Healthcheck + depends_on condition
```yaml
postgres:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 20s
data_postgres:               # serviço Rust que depende do banco
  depends_on:
    postgres:
      condition: service_healthy
```
- Para os serviços Rust entre si: usar `condition: service_started` (ou healthcheck TCP
  próprio). A transport já tem reconexão com backoff, então a ordem estrita não é crítica,
  mas `depends_on` melhora o boot.

### Pitfalls
- `$$` para escapar `$` em comandos de healthcheck dentro do compose.
- Rede `external: true` precisa existir ANTES (`docker network create` ou subir a stack de
  observabilidade primeiro), senão `up` falha.
- Não fixar `container_name` quando o isolamento é por project name (colide entre dev/prod).

---

## 3. GitHub Actions → GHCR → deploy self-hosted

> Fonte: github.com/docker/{login,metadata,build-push}-action ; docs.github.com (GHCR).

### Permissões e login
```yaml
permissions:
  contents: read
  packages: write          # obrigatório para push no GHCR
jobs:
  build:
    steps:
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
```

### Tags (metadata-action)
- **DEV** (push branch `dev`): `type=ref,event=branch` + `type=sha,format=short` →
  `ghcr.io/OWNER/REPO/smartcore-server:dev`, `:sha-abc1234`.
- **PROD** (tag `v*`): `type=semver,pattern={{version}}` + `type=raw,value=latest`.
- Imagem `smartcore-server` é **env-agnóstica** (mesma para dev/prod; muda só a tag).
- Imagem `smartcore-edge` é **por-ambiente** (o bundle Flutter embute `--dart-define` e
  `--base-href` diferentes) → buildar `smartcore-edge:dev` no push dev e `:prod`/`:latest`
  na tag.

### build-push com cache
```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    file: docker/server/Dockerfile
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    cache-from: type=gha,scope=server
    cache-to: type=gha,mode=max,scope=server
```
- Usar `scope` distinto por imagem (server vs edge) — limite de 10GB de cache por repo.

### Deploy no self-hosted
```yaml
deploy-dev:
  runs-on: [self-hosted, hostinger]
  environment: dev
  steps:
    - uses: actions/checkout@v5         # precisa do compose + env no servidor
    - run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
    - run: |
        cd docker/compose
        export COMPOSE_PROJECT_NAME=smartcore-dev
        docker compose --env-file env/dev.env pull
        docker compose --env-file env/dev.env up -d --remove-orphans
```
- **Approval manual prod**: GitHub → Settings → Environments → `production` → Required
  reviewers. O job `deploy-prod` usa `environment: production` e pausa para aprovação.
- **Rollback**: trocar a tag da imagem (`:vX.Y.Z` anterior) no env e `up -d` de novo.
- Self-hosted precisa estar logado no GHCR (o `docker login` por run resolve, gravando em
  `~/.docker/config.json`).

### Pitfall
- Visibilidade do package no GHCR é **private** por padrão; o self-hosted autentica com o
  token. Manter assim (não tornar público).
- Secrets/`.env` reais **não** vão no git: ficam no servidor (`docker/compose/env/*.env`
  com segredos preenchidos, fora do versionamento — versionar só `*.env.example`).

---

## 4. Caddy v2 em container (edge: TLS + gRPC-Web + SPA)

> Fonte: caddyserver.com/docs (reverse_proxy, automatic-https, file_server, running#docker-compose).

### Serviço compose
```yaml
edge:
  image: ghcr.io/OWNER/REPO/smartcore-edge:dev   # caddy + bundle web embutido
  ports:
    - "80:80"
    - "443:443"
    - "443:443/udp"        # HTTP/3 QUIC
  volumes:
    - caddy_data:/data     # PERSISTIR — certificados Let's Encrypt
    - caddy_config:/config
  networks: [internal]
volumes:
  caddy_data:
  caddy_config:
```
⚠️ **Persistir `/data`** é obrigatório: sem isso o Caddy re-emite certificados a cada
restart e bate no rate limit do Let's Encrypt.

### Caddyfile (adaptado do `infra/Caddyfile` atual)
- Trocar `reverse_proxy 127.0.0.1:50051` por `reverse_proxy runtime_api:50051` (DNS do
  compose). **HTTP/1.1 plano** — a fachada Tonic NÃO usa h2c; não adicionar `transport http`
  com versions h2c. Não inventar health-check gRPC (a fachada não expõe grpc.health).
- Servir o bundle Flutter do próprio filesystem da imagem (COPY no Dockerfile do edge),
  mantendo `handle_path /v2/admin/*` + `try_files {path} /index.html` + `file_server`.
- Manter os headers de segurança (CSP com `wasm-unsafe-eval`, HSTS, X-Frame-Options) já
  presentes no Caddyfile atual.
- Domínios por ambiente: `smartcoreassistant.com.br` (prod) e `dev.smartcoreassistant.com.br`
  (dev). Como cada ambiente tem seu edge, cada Caddyfile trata só o seu domínio.

### Web bundle — embutir na imagem edge (recomendado p/ prod)
- O CI builda o Flutter Web e o Dockerfile do edge faz `COPY web/ /srv/admin`. Imagem
  auto-contida, sem volume de host. `--dart-define`/`--base-href` por ambiente justificam
  imagem por-env (`smartcore-edge:dev` vs `:prod`).
- Alternativa dev-local: volume montando o bundle (rebuild rápido), mas em servidor a imagem
  embutida é mais limpa.

---

## 5. Cloudflare R2 (storage de mídia em prod) — sem mudança de contrato

> Já em uso. S3-compatible. Em prod o `data_storage` aponta para R2 via `S3_ENDPOINT`
> (`https://<conta>.r2.cloudflarestorage.com`), `S3_REGION=auto`, `S3_FORCE_PATH_STYLE=true`,
> bucket `media-smart-core-assistant`. Em dev usa MinIO (`http://minio:9000`). A migração
> só muda o host (`minio` em vez de `localhost`) e mantém o resto.

---

## 6. Alteração necessária na transport (resolução de hostname TCP)

**Problema:** `Endpoint::parse` só aceita `SocketAddr` numérico; `tcp://data_postgres:9101`
não parseia. Em Docker o discovery é por DNS de serviço.

**Opções:**
1. **(Recomendada) Resolver hostname no bind/dial.** Tornar `Endpoint::Tcp` portador de um
   alvo resolvível (ex.: `Tcp(String)` com `host:port`), e usar `ToSocketAddrs` do Tokio
   (que resolve DNS) tanto em `TcpListener::bind(&addr)` quanto em `TcpStream::connect(&addr)`.
   Tokio aceita `&str`/`(host, port)` em ambos e faz o lookup. Mínima superfície de mudança:
   `runtime.rs` (parse, `Server::run` no braço `Tcp`, `MuxClient::conectar`).
   - Observabilidade: manter os `tracing::info!("Servidor TCP rodando em ...")` e logar o
     host resolvido; **não** logar segredos.
   - Testes: os testes em `transport/tests/rpc/mod.rs` usam `tcp://127.0.0.1:PORT` (IP) — devem
     continuar passando. Adicionar teste com hostname `localhost:PORT`.
2. Bind sempre em `0.0.0.0:porta` por serviço e dial por IP fixo — inviável (IP dinâmico no Docker).

**Endpoints TCP propostos (env de cada ambiente):**
```
SMARTCORE_DATA_POSTGRES_ENDPOINT=tcp://data_postgres:9101
SMARTCORE_DATA_REDIS_ENDPOINT=tcp://data_redis:9102
SMARTCORE_DATA_STORAGE_ENDPOINT=tcp://data_storage:9103
SMARTCORE_CONTROL_PLANE_ENDPOINT=tcp://control_plane:9104
SMARTCORE_MESSAGING_GATEWAY_ENDPOINT=tcp://messaging_gateway:9105
SMARTCORE_RUNTIME_API_ENDPOINT=tcp://runtime_api:9106
RUNTIME_API_GRPC_WEB_ADDR=0.0.0.0:50051
```
Como o nome do serviço resolve para o IP do próprio container no bind e para o IP do par no
dial, o **mesmo** valor de env serve para os dois lados (graças à resolução DNS). O bind em
`data_postgres:9101` dentro do container resolve para o IP próprio (funciona); se houver
qualquer atrito, fazer o lado servidor cair para `0.0.0.0` quando o host == nome do serviço.

---

## 7. Observabilidade & Auditoria (requisito transversal)

- **Pipeline preservado**: cada serviço Rust continua exportando OTLP para
  `otel-collector:4317` (var `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`), via a
  rede compartilhada `smartcore_observability`.
- **Namespace por ambiente**: `OTEL_SERVICE_NAMESPACE=smartcore-dev|smartcore-prod` separa os
  traces/métricas no Grafana/Tempo/Prometheus (a stack é compartilhada, a separação é por
  label/namespace).
- **Auditoria (`audit_log`)**: a migração **não cria nem altera** eventos de auditoria de
  domínio; só muda o transporte (UDS→TCP) e o empacotamento (binário→container). A trilha
  assíncrona `transport::bus` → `data_postgres` deve continuar funcionando sobre a rede
  interna do Docker. Verificar no smoke-test que eventos chegam ao `audit_log`.
- **Sanitização**: os `.env` com segredos (POSTGRES_PASSWORD, REDIS_PASSWORD, JWT_SECRET,
  ENCRYPTION_KEY, chaves R2) ficam **fora do git** (só no servidor) e **não** são logados.
  Logs de infra (bind, conexão) não emitem credenciais.

---

## 8. Limpeza do servidor Hostinger (executado pelo usuário via SSH)

- Projetos Docker **antigos** a remover: `smart-core-app`, `smart-core-data`,
  `smart-core-workers` (sistema legado v1).
- Remover units systemd `smartcore-*` (se instaladas no host), `/opt/smartcore/*`,
  `/srv/smart-core-admin/*`, `/etc/caddy/Caddyfile` host, `/etc/sudoers.d/gh-runner-smartcore`.
- Migrar/recriar volumes: os dados de `smartcore-v2-data` (postgres/redis) podem ser
  mantidos se os nomes de volume forem preservados, ou recriados do zero (projeto no início).
- Docker + plugin compose já presentes no servidor (Hostinger Docker Manager).

---

## Notas gerais / gotchas

- **Sem `version:`** nos arquivos compose (Compose Specification atual).
- **flatc**: usar a URL exata do CI (zip g++-13), não um binário inexistente.
- **libpq5 não é necessário** no runtime (sqlx é puro-Rust com tls-rustls).
- **HTTP/1.1 na fachada** gRPC-Web — não configurar h2c no Caddy.
- **Persistir `caddy_data`** (certificados) e os volumes de postgres/redis.
- **Rede external** de observabilidade deve subir primeiro.
- **Pin de versão do Rust** nos estágios do Dockerfile para cache estável.
