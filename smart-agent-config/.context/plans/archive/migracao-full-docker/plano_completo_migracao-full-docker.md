# Plano Completo — Migração Full-Docker (dev + prod)

> Reestruturado em: 2026-06-20
> Origem: conversa (sessão de migração de infra)
> Plano canônico: `.context/plans/migracao-full-docker.md`
> Documentação auxiliar: `.context/plans/migracao-full-docker/info_aux_migracao-full-docker.md`

---

## Objetivo

Migrar a infraestrutura HOJE híbrida (binários Rust via systemd no host Hostinger + dados/observabilidade em Docker + Caddy no host) para **FULL-DOCKER**, do zero, com:

- **2 ambientes isolados** (`dev` / `prod`) em dados (postgres/redis/redis-bus/minio por ambiente) e observabilidade **LGTM compartilhada** (separação por `OTEL_SERVICE_NAMESPACE`).
- **Imagens no GHCR** (CI builda + push; servidor só `pull && up`).
- **Imagem Rust única** `smartcore-server` com os 7 binários (`command:` por serviço).
- **Imagem edge por-ambiente** `smartcore-edge` (Caddy + bundle Flutter embutido).
- Remoção de toda a poluição de systemd/host-provisioning.

### Decisões já fechadas (não reabrir)

- Registry: **GHCR**.
- Isolamento: dados por ambiente; observabilidade compartilhada.
- Imagem Rust única; edge por-ambiente.
- MinIO só em dev (profile); prod usa **R2**.
- Comunicação inter-serviços por **TCP via DNS do Compose** → exige alteração na `transport`.

---

## Estrutura-alvo de arquivos

```
docker/
  server/
    Dockerfile                 # NOVO — multi-stage cargo-chef → 7 binários, debian-slim non-root
    .dockerignore              # NOVO
  edge/
    Dockerfile                 # NOVO — caddy + bundle web embutido
    Caddyfile                  # NOVO — portado de infra/Caddyfile (reverse_proxy runtime_api:50051)
  init-scripts/
    01-extensions.sql          # MANTIDO
  observability/               # MANTIDO (configs LGTM já existentes)
    otel-collector-config.yml, loki-config.yml, tempo-config.yml,
    prometheus.yml, promtail-config.yml, provisioning/
  compose/
    compose.yml                # NOVO — 7 serviços Rust + edge + data (minio profile dev)
    compose.observability.yml  # NOVO — stack LGTM compartilhada (projeto próprio)
    env/
      dev.env.example          # NOVO (versionado)
      prod.env.example         # NOVO (versionado)
      # dev.env / prod.env reais ficam SÓ no servidor (fora do git)
.github/workflows/
  deploy-dev.yml               # REESCRITO — build+push GHCR (dev/sha) + deploy pull&up
  deploy-prod.yml              # REESCRITO — build+push GHCR (semver+latest) + approval manual
infra/
  systemd/                     # REMOVIDO
  server-setup.sh              # REESCRITO (remove provisioning Rust/Caddy/Flutter do host)
  cleanup-hostinger.sh         # NOVO — script de limpeza do legado (usuário roda via SSH)
server/crates/transport/src/runtime.rs   # EDITADO — Endpoint::Tcp resolve hostname (DNS)
```

> Os atuais `docker/compose/data.yml` e `docker/compose/observability.yml` são **reaproveitados/reorganizados** dentro de `compose.yml` (data) e `compose.observability.yml` (LGTM).

---

## Mapa de portas TCP internas (rede `internal` do ambiente)

| Serviço Rust        | Var de ambiente                        | Endpoint TCP                    |
|---------------------|----------------------------------------|---------------------------------|
| `data_postgres`     | `SMARTCORE_DATA_POSTGRES_ENDPOINT`     | `tcp://data_postgres:9101`      |
| `data_redis`        | `SMARTCORE_DATA_REDIS_ENDPOINT`        | `tcp://data_redis:9102`         |
| `data_storage`      | `SMARTCORE_DATA_STORAGE_ENDPOINT`      | `tcp://data_storage:9103`       |
| `control_plane`     | `SMARTCORE_CONTROL_PLANE_ENDPOINT`     | `tcp://control_plane:9104`      |
| `messaging_gateway` | `SMARTCORE_MESSAGING_GATEWAY_ENDPOINT` | `tcp://messaging_gateway:9105`  |
| `runtime_api`       | `SMARTCORE_RUNTIME_API_ENDPOINT`       | `tcp://runtime_api:9106`        |
| `worker`            | (cliente — não expõe servidor próprio) | —                               |

Fachada gRPC-Web do `runtime_api` (consumida pelo Caddy, NÃO é transport interna):

```
RUNTIME_API_GRPC_WEB_ADDR=0.0.0.0:50051
```

> O **mesmo** valor de env serve para bind e dial (o nome do serviço resolve para o IP do próprio container no bind e para o IP do par no dial), graças à resolução DNS introduzida na transport (ver Fase E / seção Transport). As portas internas (`91xx`) NÃO são publicadas no host (`ports:` ausente); só a porta `50051` chega ao host via o `edge`.

---

## Fase P — Planning (definir o que construir)

### Etapas

1. Confirmar inventário do estado atual (já consolidado no `info_aux` §0): 7 binários em `server/apps/`, transport própria UDS/TCP, dados/observabilidade já dockerizados, Caddy no host.
2. Fixar as decisões fechadas (GHCR, isolamento, imagem única Rust, edge por-ambiente, MinIO só dev) — ver "Decisões já fechadas".
3. Definir o **mapa de portas TCP** (tabela acima) e a chave de namespace de observabilidade por ambiente.
4. Identificar o **bloqueador técnico**: `Endpoint::parse` (`runtime.rs:25-37`) só aceita `SocketAddr` numérico → hostnames de serviço Docker falham. É pré-requisito da Fase E.
5. Levantar artefatos de build confirmados: `server/.sqlx/` (111 queries → `SQLX_OFFLINE=true`), `rust-toolchain.toml = stable`, `Cargo.lock` presente, `contracts/build.rs` exige protoc + flatc, flatc **v25.12.19** (URL do CI).
6. Definir critérios de aceite/smoke-test (ver seção final).

### Arquivos

- Sem alteração de código nesta fase; só planejamento (este documento) e o canônico.

### Observabilidade & Auditoria

- **Sem novo evento de auditoria** (fase de planejamento, sem comportamento).
- Declarar o invariante a preservar nas fases seguintes: pipeline OTLP → `otel-collector:4317`, namespace por ambiente, trilha `transport::bus` → `data_postgres` → `audit_log` intacta.

---

## Fase R — Review (validar approach e arquitetura)

### Etapas

1. **Revisar a alteração da transport** (resolução de hostname): confirmar que tornar `Endpoint::Tcp` portador de um alvo resolvível (`host:port`) e usar `ToSocketAddrs` do Tokio no bind/connect é a menor superfície de mudança e não quebra UDS nem os testes existentes (que usam `tcp://127.0.0.1:PORT`).
2. **Revisar isolamento dev/prod**: validar que `COMPOSE_PROJECT_NAME` + `--env-file` isolam volumes/redes/containers sem fixar `container_name`/`name:` no arquivo base.
3. **Revisar redes**: `internal` (bridge por ambiente) + `smartcore_observability` (external compartilhada). Confirmar ordem de subida: observabilidade primeiro (cria a rede external).
4. **Revisar o Dockerfile multi-stage** (cargo-chef): flatc na URL do CI (zip g++-13), protoc via apt, `SQLX_OFFLINE=true`, flatc/protoc presentes nos estágios `cook` E `build`, runtime debian-slim non-root com `libssl3`/`ca-certificates` (sem `libpq5`).
5. **Revisar o edge**: Caddy HTTP/1.1 plano para `runtime_api:50051` (sem h2c), bundle embutido, persistência de `/data` (certificados).
6. **Revisar CI/GHCR**: tags por ambiente, `packages: write`, cache `type=gha` com scope por imagem, approval manual em prod.

### Arquivos

- Sem alteração de código; revisão de design (atualiza este plano se necessário).

### Observabilidade & Auditoria

- **Sem novo evento de auditoria**.
- Validar no design que cada serviço Rust permanece em **duas redes** (`internal` + `observability`) quando emite OTLP, e que o `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` continua resolvível pela rede compartilhada.

---

## Fase E — Execution (construir)

### E.1 — Alteração da transport (resolução de hostname TCP) — PRÉ-REQUISITO

**Arquivo:** `server/crates/transport/src/runtime.rs`

**Problema:** `Endpoint::Tcp(SocketAddr)` + `addr_str.parse::<SocketAddr>()` só aceita IP:porta numérico; `tcp://data_postgres:9101` falha no parse.

**Mudança (Opção 1 do `info_aux` §6 — recomendada):** tornar `Endpoint::Tcp` portador de um alvo resolvível (`String` com `host:port`) e deixar o Tokio resolver DNS no bind e no connect.

#### (a) Enum + parse

```rust
#[derive(Debug, Clone)]
pub enum Endpoint {
    Uds(PathBuf),
    Tcp(String), // host:port resolvível (IP ou hostname) — antes era SocketAddr
}

impl Endpoint {
    pub fn parse(s: &str) -> anyhow::Result<Self> {
        if let Some(path) = s.strip_prefix("unix://") {
            Ok(Endpoint::Uds(PathBuf::from(path)))
        } else if let Some(addr_str) = s.strip_prefix("tcp://") {
            // Aceita IP:porta E hostname:porta (DNS do Docker). Validamos só que há
            // host e porta; a resolução acontece no bind/dial via ToSocketAddrs do Tokio.
            if addr_str.rsplit_once(':').map_or(true, |(h, p)| h.is_empty() || p.parse::<u16>().is_err()) {
                anyhow::bail!("Endpoint TCP invalido (esperado host:porta): {}", addr_str);
            }
            Ok(Endpoint::Tcp(addr_str.to_string()))
        } else {
            anyhow::bail!(
                "Formato de endpoint invalido: {}. Deve comecar com unix:// ou tcp://",
                s
            )
        }
    }
}
```

> Remover o `use std::net::SocketAddr;` se deixar de ser usado.

#### (b) Bind (`Server::run`, braço `Endpoint::Tcp`)

`TcpListener::bind` aceita `impl ToSocketAddrs`; passar `&str host:port` faz o Tokio resolver. Logar o endereço local resolvido (sem segredos):

```rust
Endpoint::Tcp(addr) => {
    let listener = TcpListener::bind(addr.as_str()).await?;
    let local = listener.local_addr().ok();
    tracing::info!(endpoint = %addr, local = ?local, "Servidor TCP rodando");
    loop {
        let (stream, _) = listener.accept().await?;
        // ... (resto inalterado)
    }
}
```

> Se o bind por nome-do-serviço apresentar atrito (o nome resolve para o IP do próprio container, o que normalmente funciona em Docker), aplicar o fallback: quando o host == nome do serviço, cair para `0.0.0.0:porta`. Manter como nota; só implementar se o smoke-test acusar falha de bind.

#### (c) Connect (`MuxClient::discar`, braço `Endpoint::Tcp`)

```rust
Endpoint::Tcp(addr) => {
    let stream = tokio::net::TcpStream::connect(addr.as_str()).await?;
    Ok(Conexao::nova(stream))
}
```

> `TcpStream::connect` também aceita `&str` e resolve DNS. Nenhuma mudança em `from_env`/`conectar_cliente` além de já passarem por `Endpoint::parse`.

#### (d) Testes

- **Manter** os testes existentes em `runtime.rs` (`parses_tcp_socket_endpoint_correctly` com `tcp://127.0.0.1:8080`, `parses_unix_...`, `fails_to_parse_endpoint_with_invalid_protocol`). Ajustar o match do teste TCP para a nova variante `Endpoint::Tcp(String)`:

```rust
match parsed.unwrap() {
    Endpoint::Tcp(addr) => assert_eq!(addr, "127.0.0.1:8080"),
    _ => panic!("Esperava Endpoint::Tcp"),
}
```

- **Novo teste** com hostname:

```rust
#[test]
fn parses_tcp_endpoint_com_hostname() {
    let parsed = Endpoint::parse("tcp://data_postgres:9101").unwrap();
    match parsed {
        Endpoint::Tcp(addr) => assert_eq!(addr, "data_postgres:9101"),
        _ => panic!("Esperava Endpoint::Tcp com hostname"),
    }
}
```

- Os testes de integração em `transport/tests/rpc/mod.rs` (que dão bind/dial em `tcp://127.0.0.1:PORT`) **continuam passando** porque IP:porta é um caso particular de host:porta. Opcional: adicionar um teste de round-trip com `localhost:PORT`.
- Rodar via script canônico: `.\infra\test-local.ps1` (Rust) — nunca `cargo test` direto.

#### Observabilidade & Auditoria (E.1)

- **Logs/traces**: manter `tracing::info!` no bind logando o endpoint e o `local_addr` resolvido. **Não** logar segredos. Métricas `smartcore_rpc_duration_ms` / `smartcore_rpc_total` e o slowlog permanecem intactos (não tocados).
- **Auditoria**: **sem novo evento de auditoria** — só muda o transporte (resolução de host). A trilha `transport::bus` → `data_postgres` → `audit_log` é exercida no smoke-test da Fase V.
- **Sanitização**: nenhum campo novo; nenhum segredo entra nos logs de bind/connect.

---

### E.2 — Dockerfile do servidor (imagem única, 7 binários)

**Arquivos:** `docker/server/Dockerfile`, `docker/server/.dockerignore` (NOVOS)

Multi-stage cargo-chef com pin de Rust, flatc/protoc nos estágios de build, `SQLX_OFFLINE=true`, runtime debian-slim non-root.

```dockerfile
# syntax=docker/dockerfile:1

# Base com toolchain + ferramentas de geração de contratos (flatc/protoc).
# Pin de versão concreta para cache determinístico (info_aux §1).
FROM rust:1-bookworm AS chef
RUN cargo install cargo-chef --locked
RUN apt-get update && apt-get install -y --no-install-recommends \
        protobuf-compiler wget unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# flatc — MESMA URL/método do CI (zip g++-13), não existe binário solto.
RUN wget -q -O /tmp/flatc.zip \
      https://github.com/google/flatbuffers/releases/download/v25.12.19-2026-02-06-03fffb2/Linux.flatc.binary.g%2B%2B-13.zip \
 && unzip -q -o /tmp/flatc.zip -d /tmp/flatc_extracted \
 && mv /tmp/flatc_extracted/flatc /usr/local/bin/flatc \
 && chmod +x /usr/local/bin/flatc && rm -rf /tmp/flatc.zip /tmp/flatc_extracted
WORKDIR /app

# 1) planner — gera o recipe (grafo de deps)
FROM chef AS planner
COPY server/ .
RUN cargo chef prepare --recipe-path recipe.json

# 2) builder — cozinha deps (cache) e compila os 7 binários
FROM chef AS builder
ENV SQLX_OFFLINE=true
COPY --from=planner /app/recipe.json recipe.json
# build.rs do contracts roda no cook E no build → flatc/protoc já presentes (estágio chef).
RUN cargo chef cook --release --recipe-path recipe.json
COPY server/ .
RUN cargo build --release --workspace

# 3) runtime — imagem final única, sem ENTRYPOINT fixo
FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -r -s /usr/sbin/nologin smartcore
# libpq5 NÃO é necessário (sqlx é puro-Rust, tls-rustls).
COPY --from=builder \
     /app/target/release/data_postgres \
     /app/target/release/data_redis \
     /app/target/release/data_storage \
     /app/target/release/control_plane \
     /app/target/release/messaging_gateway \
     /app/target/release/runtime_api \
     /app/target/release/worker \
     /usr/local/bin/
USER smartcore
# Sem ENTRYPOINT: o command: do compose escolhe o binário por serviço.
```

`.dockerignore` (no contexto que cobre `server/`):

```
**/target
**/*.bak
server/target
.git
docker/
clients/
```

> **Contexto de build**: o `context: .` do CI/compose deve cobrir `server/` (o `COPY server/ .` exige a raiz do repo como contexto). O `Cargo.lock` versionado garante reprodutibilidade.

#### Observabilidade & Auditoria (E.2)

- **Sem novo evento de auditoria** (mudança de empacotamento).
- A imagem não embute segredos; `.env` é injetado em runtime pelo compose (`--env-file`).
- Runtime non-root reduz superfície; `ca-certificates`/`libssl3` garantem TLS do exportador OTLP e do reqwest/aws-sdk.

---

### E.3 — Compose principal (`compose.yml`)

**Arquivo:** `docker/compose/compose.yml` (NOVO) — consolida data + 7 serviços Rust + edge.

Esqueleto (trechos-chave; sem `version:`):

```yaml
# Sem 'version:' (Compose Specification atual). Sem 'name:' fixo — quem isola é
# COMPOSE_PROJECT_NAME (info_aux §2).

x-server-image: &server-image ${SERVER_IMAGE:-ghcr.io/OWNER/REPO/smartcore-server:dev}

networks:
  internal:
    driver: bridge
  observability:
    name: smartcore_observability
    external: true

services:
  # ---------- DADOS (isolados por ambiente) ----------
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../init-scripts:/docker-entrypoint-initdb.d:ro
    networks: [internal]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: >
      redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
      --maxmemory 150mb --maxmemory-policy allkeys-lru --bind 0.0.0.0 --protected-mode yes
    volumes: [redis_data:/data]
    networks: [internal]
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  redis-bus:
    image: redis:7-alpine
    command: >
      redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
      --maxmemory 150mb --maxmemory-policy noeviction --bind 0.0.0.0 --protected-mode yes
    volumes: [redis_bus_data:/data]
    networks: [internal]
    restart: unless-stopped

  minio:
    image: minio/minio:latest
    profiles: ["dev"]            # só sobe quando COMPOSE_PROFILES inclui "dev"
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes: [minio_data:/data]
    networks: [internal]
    restart: unless-stopped

  # ---------- SERVIÇOS RUST (imagem única, command por serviço) ----------
  data_postgres:
    image: *server-image
    command: ["data_postgres"]
    env_file: [./env/${ENV_FILE}]   # ou injetado via --env-file no up
    networks: [internal, observability]
    depends_on:
      postgres: { condition: service_healthy }
    restart: unless-stopped

  data_redis:
    image: *server-image
    command: ["data_redis"]
    networks: [internal, observability]
    depends_on:
      redis: { condition: service_healthy }
      redis-bus: { condition: service_started }
    restart: unless-stopped

  data_storage:
    image: *server-image
    command: ["data_storage"]
    networks: [internal, observability]
    restart: unless-stopped

  control_plane:
    image: *server-image
    command: ["control_plane"]
    networks: [internal, observability]
    depends_on:
      data_postgres: { condition: service_started }
    restart: unless-stopped

  messaging_gateway:
    image: *server-image
    command: ["messaging_gateway"]
    networks: [internal, observability]
    restart: unless-stopped

  worker:
    image: *server-image
    command: ["worker"]
    networks: [internal, observability]
    depends_on:
      data_postgres: { condition: service_started }
      data_redis: { condition: service_started }
    restart: unless-stopped

  runtime_api:
    image: *server-image
    command: ["runtime_api"]
    networks: [internal, observability]
    depends_on:
      control_plane: { condition: service_started }
    restart: unless-stopped
    # 50051 NÃO é publicada no host; o edge fala com runtime_api:50051 pela rede internal.

  # ---------- BORDA ----------
  edge:
    image: ${EDGE_IMAGE:-ghcr.io/OWNER/REPO/smartcore-edge:dev}
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"        # HTTP/3 QUIC
    volumes:
      - caddy_data:/data     # PERSISTIR — certificados Let's Encrypt
      - caddy_config:/config
    networks: [internal]
    depends_on:
      runtime_api: { condition: service_started }
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  redis_bus_data:
  minio_data:
  caddy_data:
  caddy_config:
```

Pontos críticos:
- `$$` escapa `$` nos healthchecks.
- Nomes de volumes/redes/containers derivam de `COMPOSE_PROJECT_NAME` (sem `container_name`/`name:` no base) → isolamento automático dev/prod com o MESMO arquivo.
- Serviços que emitem OTLP entram em `internal` + `observability`.
- Para os serviços Rust entre si: `condition: service_started` (a transport já reconecta com backoff).

#### Observabilidade & Auditoria (E.3)

- **Logs/traces**: cada serviço Rust recebe via env `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` e `OTEL_SERVICE_NAMESPACE=smartcore-dev|smartcore-prod`; participa da rede `observability` para alcançar o collector. Campos de correlação (`service`/`env`/`tenant_id`/`trace_id`/`error_code`) seguem fluindo pelo Envelope/transport já instrumentados.
- **Auditoria**: **sem novo evento de auditoria** (mudança de empacotamento/transporte). A trilha `transport::bus` (redis-bus + data_postgres) → `audit_log` roda sobre a rede `internal`. Exigido no smoke-test (Fase V) que um evento real apareça no `audit_log`.
- **Sanitização**: segredos vêm do `--env-file ./env/{dev,prod}.env` (fora do git); só `*.env.example` versionado. Structs com credencial usam `secrecy` (sem mudança).

---

### E.4 — Compose de observabilidade (`compose.observability.yml`)

**Arquivo:** `docker/compose/compose.observability.yml` (NOVO) — porta o `observability.yml` atual para um projeto próprio que **cria** a rede external compartilhada.

```yaml
name: smartcore-observability   # projeto fixo e separado (cria a rede external)

networks:
  smartcore_observability:
    name: smartcore_observability
    driver: bridge              # AQUI a rede é criada (não external)

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    volumes:
      - ../observability/otel-collector-config.yml:/etc/otelcol-contrib/config.yaml:ro
    networks: [smartcore_observability]
    restart: unless-stopped
  loki:    { image: grafana/loki:latest,    networks: [smartcore_observability], volumes: [../observability/loki-config.yml:/etc/loki/local-config.yaml:ro, loki_data:/loki], restart: unless-stopped }
  tempo:   { image: grafana/tempo:latest,   networks: [smartcore_observability], command: ["-config.file=/etc/tempo/tempo.yaml"], volumes: [../observability/tempo-config.yml:/etc/tempo/tempo.yaml:ro, tempo_data:/var/tempo], restart: unless-stopped }
  prometheus: { image: prom/prometheus:latest, networks: [smartcore_observability], volumes: [../observability/prometheus.yml:/etc/prometheus/prometheus.yml:ro, prometheus_data:/prometheus], restart: unless-stopped }
  grafana: { image: grafana/grafana:latest, networks: [smartcore_observability], ports: ["3000:3000"], volumes: [../observability/provisioning:/etc/grafana/provisioning:ro, grafana_data:/var/lib/grafana], restart: unless-stopped }
  promtail: { image: grafana/promtail:latest, networks: [smartcore_observability], volumes: [../observability/promtail-config.yml:/etc/promtail/config.yml:ro, /var/run/docker.sock:/var/run/docker.sock:ro, /var/lib/docker/containers:/var/lib/docker/containers:ro], restart: unless-stopped }

volumes:
  loki_data:
  tempo_data:
  prometheus_data:
  grafana_data:
```

> **Ordem de subida**: este projeto sobe **primeiro** (cria `smartcore_observability`); depois os ambientes dev/prod (que a referenciam como `external: true`). Caso contrário, `up` dos ambientes falha por rede inexistente.

#### Observabilidade & Auditoria (E.4)

- Esta é a própria espinha dorsal de observabilidade. Configs LGTM mantidas (`docker/observability/*`). Sem auditoria de domínio.

---

### E.5 — Edge (Caddy + bundle Flutter)

**Arquivos:** `docker/edge/Dockerfile`, `docker/edge/Caddyfile` (NOVOS) — portados de `infra/Caddyfile`.

Dockerfile (recebe o bundle Flutter buildado pelo CI):

```dockerfile
FROM caddy:2-alpine
COPY docker/edge/Caddyfile /etc/caddy/Caddyfile
# O CI builda o Flutter Web e disponibiliza ./web no contexto; embutimos na imagem.
COPY web/ /srv/admin
```

Caddyfile portado (por-ambiente; cada edge trata só o seu domínio). DEV exemplo:

```caddyfile
dev.smartcoreassistant.com.br {
    encode gzip zstd

    # gRPC-Web por PATH (HTTP/1.1 plano; SEM h2c). Agora aponta para o DNS do compose.
    @grpcapi path /smartcore.contracts.*
    handle @grpcapi {
        reverse_proxy runtime_api:50051
    }

    handle_path /v2/admin/* {
        root * /srv/admin
        header {
            Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
            Strict-Transport-Security "max-age=31536000; includeSubDomains"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "DENY"
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
        }
        try_files {path} /index.html
        file_server
    }
}
```

> PROD: mesmo arquivo trocando o domínio para `smartcoreassistant.com.br` e HSTS com `preload`. Como o bundle é embutido (com `--base-href /v2/admin/` e `--dart-define` por ambiente), a imagem `smartcore-edge` é **por-ambiente** (`:dev` vs `:prod`/`:latest`).
>
> Persistir `caddy_data:/data` é obrigatório (certificados Let's Encrypt; sem isso, rate-limit no restart). **Não** configurar `transport http` h2c — a fachada Tonic é HTTP/1.1 plano. Não inventar health-check gRPC.

#### Observabilidade & Auditoria (E.5)

- **Sem novo evento de auditoria**. Logs de acesso do Caddy (já presentes no Caddyfile atual via bloco `log`) podem opcionalmente sair para stdout e serem coletados pelo `promtail`.
- Headers de segurança mantidos (CSP `wasm-unsafe-eval`, HSTS, X-Frame-Options).

---

### E.6 — Env-files de exemplo

**Arquivos:** `docker/compose/env/dev.env.example`, `docker/compose/env/prod.env.example` (NOVOS, versionados).

`dev.env.example` (sem segredos reais):

```dotenv
COMPOSE_PROJECT_NAME=smartcore-dev
COMPOSE_PROFILES=dev
ENV_FILE=dev.env
SERVER_IMAGE=ghcr.io/OWNER/REPO/smartcore-server:dev
EDGE_IMAGE=ghcr.io/OWNER/REPO/smartcore-edge:dev

# Dados
POSTGRES_DB=smartcore_v2
POSTGRES_USER=smartcore_app
POSTGRES_PASSWORD=__PREENCHER_NO_SERVIDOR__
REDIS_PASSWORD=__PREENCHER_NO_SERVIDOR__
MINIO_ROOT_USER=__PREENCHER_NO_SERVIDOR__
MINIO_ROOT_PASSWORD=__PREENCHER_NO_SERVIDOR__

# Transport TCP (DNS do compose) — mesmo valor serve bind e dial
SMARTCORE_DATA_POSTGRES_ENDPOINT=tcp://data_postgres:9101
SMARTCORE_DATA_REDIS_ENDPOINT=tcp://data_redis:9102
SMARTCORE_DATA_STORAGE_ENDPOINT=tcp://data_storage:9103
SMARTCORE_CONTROL_PLANE_ENDPOINT=tcp://control_plane:9104
SMARTCORE_MESSAGING_GATEWAY_ENDPOINT=tcp://messaging_gateway:9105
SMARTCORE_RUNTIME_API_ENDPOINT=tcp://runtime_api:9106
RUNTIME_API_GRPC_WEB_ADDR=0.0.0.0:50051

# Storage: dev usa MinIO
S3_ENDPOINT=http://minio:9000
S3_REGION=auto
S3_FORCE_PATH_STYLE=true
S3_BUCKET=media-smart-core-assistant

# Observabilidade
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAMESPACE=smartcore-dev
```

`prod.env.example`: idem trocando namespace para `smartcore-prod`, **sem** `COMPOSE_PROFILES` (MinIO não sobe), `S3_ENDPOINT=https://<conta>.r2.cloudflarestorage.com`, imagens `:prod`/`:latest`, e segredos (JWT_SECRET, ENCRYPTION_KEY, chaves R2) marcados como `__PREENCHER_NO_SERVIDOR__`.

#### Observabilidade & Auditoria (E.6)

- `OTEL_SERVICE_NAMESPACE` por ambiente é o que separa traces/métricas/logs no Grafana com a stack compartilhada.
- Os `*.env` REAIS (com segredos) ficam só no servidor, fora do git. Versionar apenas `*.env.example`.

---

### E.7 — Reescrita dos workflows CI (GHCR)

**Arquivos:** `.github/workflows/deploy-dev.yml`, `deploy-prod.yml` (REESCRITOS).

`deploy-dev.yml` (push em `dev` → build+push GHCR `:dev`/`:sha`, depois deploy pull&up):

```yaml
name: Deploy → DEV
on:
  push:
    branches: [dev]
permissions:
  contents: read
  packages: write
jobs:
  build-server:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: docker/login-action@v3
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}/smartcore-server
          tags: |
            type=ref,event=branch
            type=sha,format=short
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/server/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha,scope=server
          cache-to: type=gha,mode=max,scope=server
  build-edge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: stable, cache: true }
      - name: Build web admin (DEV, --wasm)
        working-directory: clients
        run: |
          flutter pub get
          cd apps/smart-core-admin
          flutter build web --wasm --base-href /v2/admin/ -t lib/main_dev.dart \
            --dart-define=SMARTCORE_API_ENDPOINT=https://dev.smartcoreassistant.com.br
      - run: cp -r clients/apps/smart-core-admin/build/web ./web
      - uses: docker/login-action@v3
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/edge/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository }}/smartcore-edge:dev
          cache-from: type=gha,scope=edge
          cache-to: type=gha,mode=max,scope=edge
  deploy-dev:
    needs: [build-server, build-edge]
    runs-on: [self-hosted, hostinger]
    environment: dev
    steps:
      - uses: actions/checkout@v5     # precisa do compose + env no servidor
      - run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
      - name: Pull & up (DEV)
        working-directory: docker/compose
        run: |
          export COMPOSE_PROJECT_NAME=smartcore-dev
          docker compose --env-file env/dev.env pull
          docker compose --env-file env/dev.env up -d --remove-orphans
```

`deploy-prod.yml` (tag `v*` → semver+latest, **approval manual** via `environment: production`):

```yaml
name: Deploy → PROD
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']
permissions:
  contents: read
  packages: write
jobs:
  build-server:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: docker/login-action@v3
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}/smartcore-server
          tags: |
            type=semver,pattern={{version}}
            type=raw,value=latest
      - uses: docker/build-push-action@v6
        with: { context: ., file: docker/server/Dockerfile, push: true, tags: "${{ steps.meta.outputs.tags }}", cache-from: type=gha,scope=server, cache-to: type=gha,mode=max,scope=server }
  build-edge:
    # idem dev, com main_prod.dart + dart-define prod e tags smartcore-edge:{version}/:latest
    runs-on: ubuntu-latest
    steps: [ ... ]
  deploy-prod:
    needs: [build-server, build-edge]
    runs-on: [self-hosted, hostinger]
    environment: production        # Required reviewers → pausa para approval manual
    steps:
      - uses: actions/checkout@v5
      - run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
      - name: Pull & up (PROD)
        working-directory: docker/compose
        run: |
          export COMPOSE_PROJECT_NAME=smartcore-prod
          docker compose --env-file env/prod.env pull
          docker compose --env-file env/prod.env up -d --remove-orphans
```

> **Approval manual prod**: GitHub → Settings → Environments → `production` → Required reviewers. **Rollback**: editar a tag de `SERVER_IMAGE`/`EDGE_IMAGE` no `env/prod.env` para a versão anterior e `up -d` de novo. Visibilidade do package no GHCR fica **private** (o self-hosted autentica por token).

#### Observabilidade & Auditoria (E.7)

- **Sem novo evento de auditoria** (mudança de pipeline). O CI nunca imprime segredos; `GITHUB_TOKEN` via `--password-stdin`.

---

### E.8 — Remoções e reescrita do provisioning de host

**Remover:**
- `infra/systemd/` (todos os 16 arquivos `.service`/`.target` + README).
- Blocos de provisioning de Rust/Caddy/Flutter e publicação de bundle no `infra/server-setup.sh`.
- Scripts de deploy/symlink do host que viram obsoletos (publicação web em `/srv/...`, instalação em `/opt/smartcore/.../bin`).

**Reescrever:** `infra/server-setup.sh` reduzido a: garantir Docker + plugin compose, criar a rede `smartcore_observability` (ou subir o projeto de observabilidade), criar diretórios `docker/compose/env/` com os `*.env` reais, fazer `docker login ghcr.io`.

**Portar:** `infra/Caddyfile` → `docker/edge/Caddyfile` (já em E.5). O host não roda mais Caddy.

#### Observabilidade & Auditoria (E.8)

- **Sem novo evento de auditoria**. Garantir que ao remover o systemd nenhum coletor de logs do host (journald) era a única fonte — a observabilidade passa a ser 100% via OTLP + promtail (Docker).

---

## Fase V — Validation (verificar que funciona)

### Etapas

1. Subir observabilidade primeiro: `docker compose -f compose.observability.yml up -d` (cria a rede external).
2. Subir DEV: `COMPOSE_PROJECT_NAME=smartcore-dev docker compose --env-file env/dev.env up -d`.
3. Rodar testes Rust da transport via `.\infra\test-local.ps1` (parse com hostname + round-trip TCP).
4. Executar o **smoke-test** (checklist abaixo).
5. Validar isolamento subindo PROD em paralelo (`smartcore-prod`) e confirmando volumes/redes distintos.

### Observabilidade & Auditoria (V)

- **Logs/traces**: confirmar no Grafana que traces de dev e prod aparecem **separados por `OTEL_SERVICE_NAMESPACE`**; campos `service/env/tenant_id/trace_id/error_code` presentes.
- **Auditoria (smoke-test obrigatório)**: disparar uma operação que gere evento de domínio e confirmar que ele percorre `transport::bus` → `data_postgres` e é **persistido no `audit_log`**. A migração não cria evento novo, mas a trilha deve continuar funcionando.
- **Sanitização**: inspecionar logs dos containers e confirmar ausência de segredos (senhas, JWT_SECRET, chaves R2).

---

## Fase C — Confirmation (entregar e documentar)

### Etapas

1. Gate `prevc-final-review` (subagente Opus) comparando implementado vs plano.
2. Atualizar docs em `doc_dev`/`.context` se necessário.
3. Commit seguindo gitflow (sem auto-referência a Claude).
4. **Limpeza do servidor Hostinger** (seção abaixo) executada pelo usuário via SSH.
5. Arquivar o plano em `archive/`.

### Observabilidade & Auditoria (C)

- **Sem novo evento de auditoria**. Registrar no relatório final que o smoke-test de auditoria passou.

---

## Estratégia de 2 ambientes (dev / prod)

| Eixo               | dev                              | prod                                   |
|--------------------|----------------------------------|----------------------------------------|
| Project name       | `COMPOSE_PROJECT_NAME=smartcore-dev` | `COMPOSE_PROJECT_NAME=smartcore-prod` |
| Env-file           | `--env-file env/dev.env`         | `--env-file env/prod.env`              |
| Profiles           | `COMPOSE_PROFILES=dev` (MinIO ON) | (sem profile; MinIO OFF, usa R2)      |
| Rede interna       | `internal` (isolada por project) | `internal` (isolada por project)       |
| Rede observab.     | `smartcore_observability` (external, compartilhada) | idem               |
| Namespace OTel     | `smartcore-dev`                  | `smartcore-prod`                       |
| Imagens            | `:dev` / `:sha`                  | `:vX.Y.Z` / `:latest`                  |
| Domínio (edge)     | `dev.smartcoreassistant.com.br`  | `smartcoreassistant.com.br`            |

**Ordem de subida (sempre):**
1. `compose.observability.yml` (projeto `smartcore-observability`) — **cria** a rede external.
2. `compose.yml` com `smartcore-dev` e/ou `smartcore-prod` — referenciam a rede como `external: true`.

> Mesmo arquivo `compose.yml` para os dois ambientes; o que diverge é só project name + env-file + profiles.

---

## Plano de migração/limpeza do servidor Hostinger

**Arquivo novo (opcional):** `infra/cleanup-hostinger.sh` (o usuário roda via SSH).

1. **Remover projetos Docker legados (v1)**: `smart-core-app`, `smart-core-data`, `smart-core-workers` (`docker compose -p <proj> down -v` ou `docker rm -f` + remoção de volumes órfãos).
2. **Remover systemd**: `systemctl disable --now smartcore-{dev,prod}-*`, remover units em `/etc/systemd/system/smartcore-*` e `daemon-reload`.
3. **Remover host-provisioning**: `/opt/smartcore/*` (binários/releases), `/srv/smart-core-admin/*` (bundles web), `/etc/caddy/Caddyfile` do host + parar/desinstalar o Caddy do host, `/etc/sudoers.d/gh-runner-smartcore`.
4. **Volumes postgres/redis**:
   - **Opção A (preservar)**: manter os volumes `smartcore_v2_postgres_data`/`smartcore_v2_redis_data` e referenciá-los por nome no novo compose (mapeando para o ambiente desejado). Fazer `pg_dump` antes por segurança.
   - **Opção B (recriar do zero)**: projeto novo, volumes novos por ambiente — `init-scripts/01-extensions.sql` recria extensões; migrations compiladas (`sqlx::migrate!`) recriam o schema no boot. Recomendado se o legado v1 não compartilha schema com v2.
5. **Garantir Docker + plugin compose** (já presentes via Hostinger Docker Manager) e `docker login ghcr.io`.
6. **Subir** observabilidade → dev → prod (ordem acima).

---

## Critérios de aceite / Checklist de validação (smoke-test)

- [ ] `docker compose ps` (dev e prod) mostra **todos os containers `healthy`/`running`** (postgres, redis, redis-bus, [minio em dev], 7 serviços Rust, edge).
- [ ] **gRPC-Web responde via Caddy**: requisição a `/smartcore.contracts.*` no domínio do ambiente retorna resposta válida do `runtime_api` (HTTP/1.1, sem h2c).
- [ ] **Admin Flutter carrega** em `https://<dominio>/v2/admin/` (WASM, base-href correto).
- [ ] **Traces no Grafana** separados por namespace (`smartcore-dev` vs `smartcore-prod`) via Tempo; logs no Loki; métricas no Prometheus.
- [ ] **Evento de auditoria persistido**: uma operação de domínio gera registro em `audit_log` (trilha `transport::bus` → `data_postgres` íntegra).
- [ ] **Isolamento**: volumes/redes/containers de dev e prod distintos; derrubar dev não afeta prod.
- [ ] **Certificados persistem** após `docker compose restart edge` (volume `caddy_data`).
- [ ] **Testes da transport** passam (parse hostname + round-trip TCP) via `.\infra\test-local.ps1`.
- [ ] **Sem segredos em logs** de nenhum container.
- [ ] **Rollback validado**: trocar tag de imagem no `env` e `up -d` reverte a versão.

---

## Correções aplicadas (sobre o plano-base, por causa da doc atual)

| # | Correção | Fonte |
|---|----------|-------|
| 1 | **flatc**: usar a URL/zip exato do CI (`v25.12.19-...Linux.flatc.binary.g++-13.zip`); não existe binário solto `flatc` no release. | `info_aux` §1; `deploy-dev.yml`/`deploy-prod.yml` atuais (mesma URL). |
| 2 | **Sem campo `version:`** nos arquivos compose (Compose Specification atual; legado deprecado). | `info_aux` §2 / Notas. |
| 3 | **Caddy HTTP/1.1 plano sem h2c**: a fachada Tonic escuta HTTP/1.1; `reverse_proxy runtime_api:50051` sem `transport http` versions h2c; sem health-check gRPC inventado. | `info_aux` §0/§4; `infra/Caddyfile` atual (comentário "SEM h2c"). |
| 4 | **`libpq5` desnecessário** no runtime (sqlx é puro-Rust com tls-rustls). Instalar só `ca-certificates`/`libssl3`. | `info_aux` §1 / Notas. |
| 5 | **Alteração obrigatória na transport**: `Endpoint::parse` só aceita `SocketAddr` numérico — hostnames do Docker DNS falham. `Endpoint::Tcp(SocketAddr)` → `Endpoint::Tcp(String)` + `ToSocketAddrs` no bind/connect. | `info_aux` §0/§6; `runtime.rs:25-37`. |
| 6 | **Persistir `caddy_data:/data`** (certificados Let's Encrypt) — sem isso, rate-limit no restart. | `info_aux` §4. |
| 7 | **Rede external de observabilidade sobe primeiro**: o projeto `smartcore-observability` **cria** `smartcore_observability`; os ambientes a referenciam como `external: true`. Ordem invertida quebra o `up`. | `info_aux` §2. |
| 8 | **Isolamento por `COMPOSE_PROJECT_NAME`** (não fixar `container_name`/`name:` no base) — colide entre dev/prod. MinIO via `profiles: ["dev"]`. | `info_aux` §2. |
| 9 | **GHCR substitui artefatos tar+systemd**: CI builda imagem (server env-agnóstica; edge por-ambiente) e dá push; servidor só `pull && up`. Remove build de binários no runner + instalação por checksum/symlink. | `info_aux` §3; `deploy-*.yml` atuais (que ainda usam tar/systemd). |
| 10 | **Sem ENTRYPOINT fixo na imagem Rust**: `command:` do compose escolhe o binário por serviço (imagem única com os 7). | `info_aux` §1. |
| 11 | **flatc/protoc nos estágios `cook` E `build`** (o `build.rs` do contracts roda em ambos) — instalar num estágio base compartilhado (`chef`). | `info_aux` §1. |
| 12 | **`$$` para escapar `$`** em healthchecks do compose. | `info_aux` §2. |
| 13 | **R2 sem mudança de contrato**: dev=`http://minio:9000`, prod=`https://<conta>.r2.cloudflarestorage.com`; muda só o host. | `info_aux` §5. |
| 14 | **Bundle Flutter embutido na imagem edge** (não volume de host) → imagem `smartcore-edge` por-ambiente (base-href/dart-define divergem). | `info_aux` §4. |
```