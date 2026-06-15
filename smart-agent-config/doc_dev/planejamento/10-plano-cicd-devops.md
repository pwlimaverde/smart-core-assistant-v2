# 10 — DevOps Completo: CI/CD, Ambientes e Provisionamento do Servidor

> **Status:** ⬜ **Próxima fase a implementar** — executar ANTES de F6 (auth/runtime_api).
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Servidor:** Hostinger KVM2 — 2 vCPU / 8 GB RAM / Ubuntu 22.04 LTS
> **IP:** `76.13.229.210` | **SSH:** `root@76.13.229.210 -p 22`
> **Referência v1:** `old/smart-core-assistant-painel/.github/workflows/deploy.yml`

---

## 1. Visão Geral e Objetivos

Este plano estabelece toda a infraestrutura de CI/CD e DevOps **antes** de qualquer
feature de negócio. O objetivo é que, ao iniciar a implementação do módulo auth (F6),
o pipeline já esteja funcional e o código seja entregue automaticamente nos dois
ambientes a cada push/tag.

**Dois ambientes independentes no mesmo servidor:**

| Aspecto | Dev | Prod |
|---|---|---|
| Trigger | Push na branch `dev` (GitHub) | Tag semântica `v*.*.*` → merge em `main` |
| Banco | `smartcore_v2_dev` | `smartcore_v2` |
| Redis (banco lógico) | DB 1 | DB 0 |
| Sockets UDS | `/run/smartcore-dev/` | `/run/smartcore/` |
| Binários | `/opt/smartcore/dev/bin/` | `/opt/smartcore/prod/releases/<tag>/` |
| API gRPC porta | `8090` (dev) | `8080` (prod) |
| Domínio | `dev-api.smartcoreassistant.com.br` | `api.smartcoreassistant.com.br` |
| Aprovação manual | Não | Sim (GitHub Environment protection) |

**Estratégia de build:**
- **Self-hosted runner** instalado no próprio Hostinger para builds Rust (cache de
  `~/.cargo` persiste entre builds → 3-5 min em vez de 30-40 min em runner hosted).
- Runner CI (lint + testes) usa runner **GitHub-hosted** `ubuntu-latest` (segurança:
  PRs de forks não executam no servidor).
- Flutter Windows: runner **GitHub-hosted** `windows-latest` acionado apenas em tags.

---

## 2. Estratégia de Branches e Releases

```
main          ──────────────────────────────── (produção — merge via PR após tag)
                  ↑ merge via PR
dev           ──●──●──●──────────────────────── (deploy automático em push)
               ↑           ↑
feature/...  ──●    feature/...  ──●
                                    ↑ PR → dev
```

**Fluxo de release:**
1. Desenvolvimento acontece em `feature/*` → PR para `dev`.
2. Push em `dev` → CI completo + **deploy automático no ambiente dev**.
3. Quando pronto para release: criar tag `vX.Y.Z` na `dev` (ou no último commit
   estável).
4. A tag `v*` dispara: CI + build release + **deploy no ambiente prod** (com
   aprovação manual no GitHub) + PR automático `dev → main`.
5. Merge em `main` registra o estado de produção no histórico.

**Convenção de tags:** `vMAJOR.MINOR.PATCH` (ex.: `v1.0.0`, `v1.1.3`).

**Branches protegidas:**
- `main`: só aceita merge via PR aprovado; sem push direto.
- `dev`: push direto permitido (só para o owner); PRs de feature obrigatórios para o time.

---

## 3. Estrutura de Diretórios no Servidor

```
/opt/smartcore/
├── dev/
│   ├── bin/                    # binários dev (copiados pelo runner)
│   │   ├── data_postgres
│   │   ├── data_redis
│   │   ├── data_storage
│   │   ├── runtime_api
│   │   ├── control_plane
│   │   ├── messaging_gateway
│   │   └── worker
│   └── .env                    # variáveis de ambiente dev (nunca commitado)
│
├── prod/
│   ├── releases/               # versionamento de binários prod
│   │   ├── v1.0.0/             # release anterior (rollback)
│   │   ├── v1.1.0/             # release atual
│   │   └── current -> v1.1.0/  # symlink atualizado pelo deploy
│   └── .env                    # variáveis de ambiente prod (nunca commitado)
│
└── shared/
    └── sqlx-cli                # binário sqlx para migrações

/run/smartcore/                 # sockets UDS prod (criado pelo systemd)
/run/smartcore-dev/             # sockets UDS dev (criado pelo systemd)

/var/log/smartcore/             # logs se necessário (alternativa ao journald)

/etc/systemd/system/
├── smartcore-dev-data_postgres.service
├── smartcore-dev-data_redis.service
├── smartcore-dev-data_storage.service
├── smartcore-dev-runtime_api.service
├── smartcore-dev-control_plane.service
├── smartcore-dev-messaging_gateway.service
├── smartcore-dev-worker.service
├── smartcore-prod-data_postgres.service
├── smartcore-prod-data_redis.service
├── smartcore-prod-data_storage.service
├── smartcore-prod-runtime_api.service
├── smartcore-prod-control_plane.service
├── smartcore-prod-messaging_gateway.service
└── smartcore-prod-worker.service

/etc/caddy/Caddyfile            # reverse proxy (TLS automático)
```

---

## 4. Provisionamento do Servidor (script único)

Executar **uma vez** no servidor limpo. Salvar como `infra/server-setup.sh`.

```bash
#!/usr/bin/env bash
# Provisionamento do servidor Hostinger KVM2 para Smart Core Assistant v2
# Executar como root: bash server-setup.sh
set -euo pipefail

# ── 1. Pacotes do sistema ─────────────────────────────────────────────────────
apt-get update && apt-get upgrade -y
apt-get install -y \
    curl wget git unzip \
    build-essential pkg-config \
    libssl-dev \
    ufw \
    jq \
    ca-certificates gnupg lsb-release

# ── 2. Caddy (reverse proxy) ──────────────────────────────────────────────────
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy

# ── 3. Rust toolchain (para sqlx-cli e builds locais) ─────────────────────────
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain stable
source "$HOME/.cargo/env"
rustup target add x86_64-unknown-linux-gnu

# sqlx-cli para rodar migrações no servidor
cargo install sqlx-cli --no-default-features --features postgres

# ── 4. Usuários e diretórios ──────────────────────────────────────────────────
# Usuário de runtime das aplicações (sem login, sem sudo)
useradd --system --no-create-home --shell /usr/sbin/nologin smartcore || true

# Usuário para o GitHub Actions runner (com acesso limitado ao systemd)
useradd --system --create-home --shell /bin/bash gh-runner || true

# Diretórios de binários e config
mkdir -p /opt/smartcore/{dev/bin,prod/releases,shared}
mkdir -p /run/smartcore /run/smartcore-dev
chown -R smartcore:smartcore /opt/smartcore /run/smartcore /run/smartcore-dev

# gh-runner pode escrever nos binários e fazer systemctl restart dos serviços
chown -R gh-runner:gh-runner /opt/smartcore
# sudoers para systemctl restart somente nos serviços smartcore
echo 'gh-runner ALL=(ALL) NOPASSWD: /bin/systemctl restart smartcore-*,/bin/systemctl start smartcore-*,/bin/systemctl stop smartcore-*,/bin/systemctl is-active smartcore-*' \
    > /etc/sudoers.d/gh-runner-smartcore

# Instalar sqlx-cli no shared
cp "$HOME/.cargo/bin/sqlx" /opt/smartcore/shared/sqlx
chmod +x /opt/smartcore/shared/sqlx

# ── 5. Firewall (ufw) ─────────────────────────────────────────────────────────
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP (Caddy → HTTPS redirect)'
ufw allow 443/tcp comment 'HTTPS (Caddy TLS)'
ufw allow 443/udp comment 'HTTP/3 QUIC'
# Portas internas NÃO expostas (UDS ou loopback apenas):
# 8080 (prod gRPC), 8090 (dev gRPC) — só Caddy acessa via loopback
ufw --force enable

# ── 6. systemd runtime directories (tmpfiles.d) ───────────────────────────────
# Garante que /run/smartcore* é recriado após reboot
cat > /etc/tmpfiles.d/smartcore.conf << 'EOF'
d /run/smartcore     0755 smartcore smartcore -
d /run/smartcore-dev 0755 smartcore smartcore -
EOF

# ── 7. Banco de dados dev (no PostgreSQL já existente via Docker) ─────────────
# Executar após o data stack estar no ar:
# docker exec smartcore-v2-postgres psql -U smartcore_app -c \
#   "CREATE DATABASE smartcore_v2_dev;"
# docker exec smartcore-v2-postgres psql -U smartcore_app -c \
#   "GRANT ALL PRIVILEGES ON DATABASE smartcore_v2_dev TO smartcore_app;"

echo "Provisionamento base concluído. Próximos passos:"
echo "  1. Configurar Caddyfile em /etc/caddy/Caddyfile"
echo "  2. Criar arquivos .env em /opt/smartcore/{dev,prod}/.env"
echo "  3. Instalar systemd units (infra/systemd/*.service)"
echo "  4. Registrar GitHub Actions self-hosted runner (ver seção 6)"
echo "  5. Criar banco smartcore_v2_dev no PostgreSQL"
```

---

## 5. Configuração do Caddy (Reverse Proxy + TLS)

**Arquivo:** `/etc/caddy/Caddyfile`

```caddyfile
# ── Produção ──────────────────────────────────────────────────────────────────
api.smartcoreassistant.com.br {
    # gRPC (Tonic) exige HTTP/2 cleartext (h2c) no upstream
    reverse_proxy h2c://localhost:8080 {
        flush_interval -1
        transport http {
            versions h2c
        }
    }
    # Headers de segurança
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
    }
    log {
        output file /var/log/caddy/api-prod.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}

# ── Desenvolvimento ───────────────────────────────────────────────────────────
dev-api.smartcoreassistant.com.br {
    reverse_proxy h2c://localhost:8090 {
        flush_interval -1
        transport http {
            versions h2c
        }
    }
    log {
        output file /var/log/caddy/api-dev.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}

# ── Grafana (observabilidade) ─────────────────────────────────────────────────
grafana.smartcoreassistant.com.br {
    reverse_proxy localhost:3000
}

# ── Redirect HTTP → HTTPS ─────────────────────────────────────────────────────
http:// {
    redir https://{host}{uri} permanent
}
```

Habilitar e iniciar:
```bash
mkdir -p /var/log/caddy
systemctl enable caddy
systemctl start caddy
```

---

## 6. Systemd Service Units

### 6.1 Template base (prod — repetir para cada serviço)

Criar um arquivo por serviço em `/etc/systemd/system/smartcore-prod-<nome>.service`:

```ini
# Exemplo: /etc/systemd/system/smartcore-prod-data_postgres.service
[Unit]
Description=SmartCore PROD — data_postgres
Documentation=https://github.com/seu-org/smart-core-assistant-v2
After=network.target docker.service
Requires=docker.service
# Garante que data_postgres só sobe após o Redis estar disponível
After=smartcore-prod-data_redis.service

[Service]
Type=simple
User=smartcore
Group=smartcore
WorkingDirectory=/opt/smartcore/prod
EnvironmentFile=/opt/smartcore/prod/.env
ExecStart=/opt/smartcore/prod/releases/current/data_postgres
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
# Tempo máximo para graceful shutdown
TimeoutStopSec=30s
# Logs para journald (ver com: journalctl -u smartcore-prod-data_postgres -f)
StandardOutput=journal
StandardError=journal
SyslogIdentifier=smartcore-prod-data_postgres
# Segurança mínima
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

### 6.2 Tabela de todos os serviços e dependências

| Serviço | Porta / Socket | Depende de | Notas |
|---|---|---|---|
| `smartcore-{env}-data_redis` | `/run/smartcore{-dev}/data_redis.sock` | docker | Sobe primeiro |
| `smartcore-{env}-data_postgres` | `/run/smartcore{-dev}/data_postgres.sock` | docker, data_redis | Roda migrations embutidas no boot (`sqlx::migrate!` + `DATABASE_ADMIN_URL`) |
| `smartcore-{env}-data_storage` | `/run/smartcore{-dev}/data_storage.sock` | docker | R2 é externo |
| `smartcore-{env}-control_plane` | `/run/smartcore{-dev}/control_plane.sock` | data_postgres, data_redis | |
| `smartcore-{env}-messaging_gateway` | `/run/smartcore{-dev}/messaging_gateway.sock` | data_postgres, data_redis | Recebe webhooks |
| `smartcore-{env}-worker` | Sem socket (consumer) | data_postgres, data_redis, data_storage | Consome bus |
| `smartcore-{env}-runtime_api` | TCP `8080` (prod) / `8090` (dev) | todos acima | Último a subir |

### 6.3 Ordem de boot via systemd target

Criar `/etc/systemd/system/smartcore-prod.target`:
```ini
[Unit]
Description=SmartCore PROD — todos os serviços
Requires=smartcore-prod-data_redis.service smartcore-prod-data_postgres.service \
         smartcore-prod-data_storage.service smartcore-prod-control_plane.service \
         smartcore-prod-messaging_gateway.service smartcore-prod-worker.service \
         smartcore-prod-runtime_api.service
After=smartcore-prod-data_redis.service smartcore-prod-data_postgres.service \
      smartcore-prod-data_storage.service smartcore-prod-control_plane.service \
      smartcore-prod-messaging_gateway.service smartcore-prod-worker.service \
      smartcore-prod-runtime_api.service

[Install]
WantedBy=multi-user.target
```

Ativar: `systemctl enable smartcore-prod.target smartcore-dev.target`

### 6.4 Migrations no boot

O serviço `data_postgres` roda as migrations **automaticamente ao iniciar** via
`inicializar_banco_dados`. As migrations são **embutidas no binário** em build time
(macro `sqlx::migrate!` lendo `crates/infrastructure_postgres/migrations`), então o
binário é autossuficiente — não depende da pasta `migrations/` no servidor.

A migração roda com o pool administrativo (`DATABASE_ADMIN_URL`, BYPASSRLS + DDL).
**`DATABASE_ADMIN_URL` é obrigatório** — o `data_postgres` aborta no boot sem ela
(`outbox_relay` faz `expect("DATABASE_ADMIN_URL ausente")`).

Se uma migração falhar no boot, o serviço **não fica `active`** e o smoke test do
deploy detecta a falha (disparando rollback do binário).

Para rodar migrations manualmente em emergência (a cópia da pasta vai junto na release):
```bash
# Rodar migrations manualmente no prod:
DATABASE_URL="$(grep '^DATABASE_ADMIN_URL=' /opt/smartcore/prod/.env | cut -d= -f2-)" \
  /opt/smartcore/shared/sqlx migrate run \
  --source /opt/smartcore/prod/releases/current/migrations/
```

> ⚠️ **Migrations devem ser backward-compatible (padrão expand/contract).** O rollback
> de binário (symlink `current`) **não desfaz** mudanças de schema. Uma migração que
> dropa/renomeia coluna quebra a versão anterior caso seja necessário reverter o binário.
> Regra: primeiro `expand` (adiciona coluna/tabela nova, código novo passa a usá-la),
> só em uma release **posterior** o `contract` (remove o antigo). Ver checklist seção 13.

---

## 7. Variáveis de Ambiente por Ambiente

### 7.1 `/opt/smartcore/prod/.env`

```dotenv
# ── Banco de dados ────────────────────────────────────────────────────────────
DATABASE_URL=postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2
DATABASE_ADMIN_URL=postgresql://smartcore_admin:SENHA_ADMIN@localhost:5434/smartcore_v2

# ── Redis ─────────────────────────────────────────────────────────────────────
# ATENÇÃO: hoje o código lê APENAS `REDIS_URL` (cache, tokens, locks E bus usam a
# mesma instância). O compose provisiona dois containers (redis :6380 cache/lru e
# redis-bus :6381 noeviction), mas `REDIS_BUS_URL` ainda NÃO é consumida pelo código.
# Ver pendência na seção 7.3. Até lá, aponte REDIS_URL para o redis-bus (:6381),
# pois o bus exige durabilidade (noeviction) e não pode perder eventos por LRU.
REDIS_URL=redis://:SENHA@localhost:6381/0
# Previsto (quando o código separar bus de cache):
# REDIS_BUS_URL=redis://:SENHA@localhost:6381/0   # bus durável (noeviction)
# REDIS_URL=redis://:SENHA@localhost:6380/0       # cache (allkeys-lru)

# ── Storage (Cloudflare R2) ───────────────────────────────────────────────────
S3_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
S3_REGION=auto
S3_ACCESS_KEY_ID=<id>
S3_SECRET_ACCESS_KEY=<secret>
S3_BUCKET=media-smart-core-assistant
S3_FORCE_PATH_STYLE=true

# ── Auth / JWT ────────────────────────────────────────────────────────────────
JWT_SECRET=<32-bytes-base64>
ENCRYPTION_KEY=<32-bytes-base64>

# ── Transport (UDS) ───────────────────────────────────────────────────────────
SMARTCORE_DATA_POSTGRES_ENDPOINT=unix:///run/smartcore/data_postgres.sock
SMARTCORE_DATA_REDIS_ENDPOINT=unix:///run/smartcore/data_redis.sock
SMARTCORE_DATA_STORAGE_ENDPOINT=unix:///run/smartcore/data_storage.sock
SMARTCORE_CONTROL_PLANE_ENDPOINT=unix:///run/smartcore/control_plane.sock
SMARTCORE_MESSAGING_GATEWAY_ENDPOINT=unix:///run/smartcore/messaging_gateway.sock

# ── runtime_api ───────────────────────────────────────────────────────────────
RUNTIME_API_GRPC_PORT=8080
RUNTIME_API_GRPC_LISTEN=0.0.0.0:8080

# ── Observabilidade ───────────────────────────────────────────────────────────
RUST_LOG=info
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
OTEL_SERVICE_NAMESPACE=smartcore-prod

# ── Email (SMTP via Brevo) ────────────────────────────────────────────────────
SMTP_HOST=smtp-relay.brevo.com
SMTP_PORT=587
SMTP_USER=<email>
SMTP_PASSWORD=<senha>
FROM_EMAIL=noreply@smartcoreassistant.com.br
```

### 7.2 `/opt/smartcore/dev/.env`

Idem ao prod, com as seguintes diferenças:

```dotenv
DATABASE_URL=postgresql://smartcore_app:SENHA@localhost:5434/smartcore_v2_dev
DATABASE_ADMIN_URL=postgresql://smartcore_admin:SENHA@localhost:5434/smartcore_v2_dev
# DEV usa o banco lógico 1 do MESMO Redis (isola eventos/cache de PROD que usa DB 0)
REDIS_URL=redis://:SENHA@localhost:6381/1
SMARTCORE_DATA_POSTGRES_ENDPOINT=unix:///run/smartcore-dev/data_postgres.sock
# ... demais ENDPOINT com -dev (data_redis, data_storage, control_plane, messaging_gateway)
RUNTIME_API_GRPC_PORT=8090
RUNTIME_API_GRPC_LISTEN=0.0.0.0:8090
RUST_LOG=debug
OTEL_SERVICE_NAMESPACE=smartcore-dev
```

> **Isolamento dev/prod no Redis:** como há uma única `REDIS_URL`, dev e prod
> compartilham a mesma instância Redis mas em **bancos lógicos diferentes** (prod=DB 0,
> dev=DB 1). Isso evita que eventos/cache de um ambiente vazem para o outro. Os
> consumer groups do bus e as chaves de cache ficam naturalmente segregados por DB.

### 7.3 Pendência — separar `redis-bus` no código

O `docker/compose/data.yml` já provisiona **dois** Redis com políticas distintas:

| Container | Porta | Política | Uso pretendido |
|---|---|---|---|
| `smartcore-v2-redis` | 6380 | `allkeys-lru` | Cache, tokens, locks (descartável) |
| `smartcore-v2-redis-bus` | 6381 | `noeviction` | Bus de eventos + auditoria (durável) |

**Estado atual do código:** todos os apps (`data_redis`, `data_postgres`,
`messaging_gateway`, `worker`, `data_storage`) leem **apenas `REDIS_URL`** — cache e bus
acabam na mesma instância. Se essa instância for a de `allkeys-lru`, **eventos do bus
podem ser despejados sob pressão de memória** (perda de mensagens). Por isso, até a
separação, `REDIS_URL` deve apontar para o `redis-bus` (`:6381`, noeviction).

**Tarefa de correção (registrar como issue):** introduzir `REDIS_BUS_URL` e fazer
`transport::bus` consumi-la, deixando `REDIS_URL` exclusiva para cache/tokens/locks.
Afeta: `infrastructure_redis::connection`, `transport::bus`, e os `main.rs` dos apps.
Não bloqueia a fundação DevOps, mas deve entrar **antes da F3** (quando o volume de
eventos do bus cresce com a ingestão de webhooks).

---

## 8. GitHub Actions Self-Hosted Runner

### 8.1 Instalação no servidor

```bash
# Como gh-runner no servidor:
su - gh-runner
mkdir -p ~/actions-runner && cd ~/actions-runner

# Baixar o runner (verificar versão atual em: github.com/actions/runner/releases)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Configurar (token obtido em: github.com/SEU-ORG/REPO/settings/actions/runners/new)
./config.sh \
  --url https://github.com/SEU-ORG/smart-core-assistant-v2 \
  --token <TOKEN_DO_GITHUB> \
  --name hostinger-kvm2 \
  --labels self-hosted,linux,hostinger,x64 \
  --runnergroup Default \
  --work _work

# Instalar como serviço systemd (executa como gh-runner)
sudo ./svc.sh install gh-runner
sudo ./svc.sh start
```

### 8.2 Manutenção do Rust toolchain no runner

```bash
# O runner herda o PATH do usuário gh-runner
# Adicionar ao ~/.bashrc do gh-runner:
echo 'source "$HOME/.cargo/env"' >> ~/.bashrc
rustup update stable   # executar periodicamente ou via cron
```

### 8.3 Segurança do runner

- Runner roda como `gh-runner` (sem sudo irrestrito).
- Permissão sudoers limitada a `systemctl restart/start/stop/is-active smartcore-*`.
- Workflows que usam self-hosted **nunca** são acionados por PRs externos (forks).
- Configurar no GitHub: `Settings → Actions → General → Fork pull request workflows` = `Require approval`.

---

## 9. GitHub Actions Workflows

> **Fonte da verdade:** os arquivos em `.github/workflows/` (`ci.yml`, `deploy-dev.yml`,
> `deploy-prod.yml`, `pr-to-main.yml`) já existem versionados no repositório. Os blocos
> abaixo documentam as decisões; ao editar, mantenha os dois em sincronia (ou trate o
> arquivo como canônico e este doc como explicação).

### 9.1 CI — Lint e Testes (todo push e PR)

**Arquivo:** `.github/workflows/ci.yml`

Decisões-chave:
- **Runner GitHub-hosted** (`ubuntu-latest`) — PRs de forks não tocam o servidor.
- **`cargo fmt --check` + `clippy -D warnings` + `test --workspace`** com `SQLX_OFFLINE=true`.
- **`cargo sqlx prepare --check`** — valida que o cache `.sqlx/` versionado está em
  sincronia com as queries. Sem isto, uma query nova sem `prepare` passaria no CI mas
  **quebraria o build de release no deploy** (que também usa `SQLX_OFFLINE`).
- **Job `detect` + `flutter`** — o app Flutter ainda não existe (`clients/` é ⬜). Um job
  `detect` faz checkout e expõe `outputs.flutter`; o job `flutter` só roda se
  `clients/flutter_windows/pubspec.yaml` existir. (`hashFiles()` **não** funciona em `if`
  de nível de job, pois é avaliado antes do checkout — daí o job de detecção.)

```yaml
jobs:
  rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with: { components: rustfmt, clippy }
      - uses: Swatinem/rust-cache@v2
        with: { workspaces: server }
      - run: cargo fmt --all -- --check
        working-directory: server
      - run: cargo clippy --all-targets --all-features -- -D warnings
        working-directory: server
        env: { SQLX_OFFLINE: "true" }
      - run: cargo test --workspace --lib --bins
        working-directory: server
        env: { SQLX_OFFLINE: "true" }
      - name: cargo sqlx prepare --check
        working-directory: server
        env: { SQLX_OFFLINE: "true" }
        run: |
          cargo install sqlx-cli --no-default-features --features postgres --locked || true
          cargo sqlx prepare --workspace --check

  detect:
    runs-on: ubuntu-latest
    outputs:
      flutter: ${{ steps.check.outputs.flutter }}
    steps:
      - uses: actions/checkout@v4
      - id: check
        run: |
          if [ -f clients/flutter_windows/pubspec.yaml ]; then
            echo "flutter=true" >> "$GITHUB_OUTPUT"
          else
            echo "flutter=false" >> "$GITHUB_OUTPUT"
          fi

  flutter:
    runs-on: ubuntu-latest
    needs: detect
    if: needs.detect.outputs.flutter == 'true'
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: stable, cache: true }
      - run: flutter pub get
        working-directory: clients/flutter_windows
      - run: flutter analyze
        working-directory: clients/flutter_windows
      - run: flutter test
        working-directory: clients/flutter_windows
```

### 9.2 Deploy Dev — push na branch `dev`

**Arquivo:** `.github/workflows/deploy-dev.yml`

```yaml
name: Deploy → DEV

on:
  push:
    branches: [dev]

concurrency:
  group: deploy-dev
  cancel-in-progress: false   # não cancela; espera o anterior terminar

jobs:
  build-and-deploy:
    name: Build Rust + Deploy DEV
    runs-on: [self-hosted, hostinger]
    environment: dev
    steps:
      - uses: actions/checkout@v4

      - name: Cargo build release (workspace)
        working-directory: server
        env:
          SQLX_OFFLINE: "true"
          RUSTFLAGS: "-C target-cpu=native"
        run: cargo build --release --workspace

      - name: Backup binários anteriores
        run: |
          BACKUP_DIR="/opt/smartcore/dev/bin.bak"
          rm -rf "$BACKUP_DIR"
          cp -r /opt/smartcore/dev/bin "$BACKUP_DIR" 2>/dev/null || true

      - name: Instala novos binários
        run: |
          BIN_DIR="/opt/smartcore/dev/bin"
          SRC="server/target/release"
          for svc in data_postgres data_redis data_storage \
                     runtime_api control_plane messaging_gateway worker; do
            cp "$SRC/$svc" "$BIN_DIR/$svc"
          done
          chmod +x "$BIN_DIR"/*

      - name: Reinicia serviços DEV
        run: |
          sudo systemctl restart smartcore-dev-data_redis
          sleep 2
          sudo systemctl restart smartcore-dev-data_postgres
          sleep 2
          sudo systemctl restart smartcore-dev-data_storage \
                                 smartcore-dev-control_plane \
                                 smartcore-dev-messaging_gateway \
                                 smartcore-dev-worker
          sleep 3
          sudo systemctl restart smartcore-dev-runtime_api

      - name: Smoke test DEV
        run: |
          sleep 5
          # Verifica se o runtime_api está respondendo (gRPC health check)
          for svc in data_postgres data_redis data_storage runtime_api; do
            STATUS=$(sudo systemctl is-active smartcore-dev-$svc 2>/dev/null)
            if [ "$STATUS" != "active" ]; then
              echo "ERRO: smartcore-dev-$svc não está ativo (status: $STATUS)"
              sudo journalctl -u smartcore-dev-$svc --no-pager -n 50
              exit 1
            fi
            echo "✓ smartcore-dev-$svc ativo"
          done

      - name: Rollback em falha
        if: failure()
        run: |
          echo "Falha detectada — revertendo para binários anteriores..."
          cp -r /opt/smartcore/dev/bin.bak/* /opt/smartcore/dev/bin/ 2>/dev/null || true
          sudo systemctl restart smartcore-dev-data_redis \
                                 smartcore-dev-data_postgres \
                                 smartcore-dev-data_storage \
                                 smartcore-dev-control_plane \
                                 smartcore-dev-messaging_gateway \
                                 smartcore-dev-worker \
                                 smartcore-dev-runtime_api
          echo "Rollback concluído."
```

### 9.3 Deploy Prod — tag `v*.*.*`

**Arquivo:** `.github/workflows/deploy-prod.yml`

```yaml
name: Deploy → PROD

on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']

concurrency:
  group: deploy-prod
  cancel-in-progress: false

jobs:
  build-and-deploy:
    name: Build Rust + Deploy PROD
    runs-on: [self-hosted, hostinger]
    environment: prod   # requer aprovação manual configurada no GitHub

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Extrai versão da tag
        id: version
        run: echo "TAG=${GITHUB_REF_NAME}" >> "$GITHUB_OUTPUT"

      - name: Backup banco de dados (pg_dump)
        env:
          TAG: ${{ steps.version.outputs.TAG }}
        run: |
          BACKUP_FILE="/opt/smartcore/prod/db-backup-${TAG}-$(date +%Y%m%d%H%M).dump"
          docker exec smartcore-v2-postgres pg_dump \
            -U smartcore_app \
            -F c \
            smartcore_v2 > "$BACKUP_FILE"
          echo "Backup gerado: $BACKUP_FILE"
          # Mantém apenas os últimos 5 backups
          ls -t /opt/smartcore/prod/db-backup-*.dump | tail -n +6 | xargs rm -f || true

      - name: Cargo build release
        working-directory: server
        env:
          SQLX_OFFLINE: "true"
          RUSTFLAGS: "-C target-cpu=native"
        run: cargo build --release --workspace

      - name: Cria diretório da release
        env:
          TAG: ${{ steps.version.outputs.TAG }}
        run: |
          RELEASE_DIR="/opt/smartcore/prod/releases/$TAG"
          mkdir -p "$RELEASE_DIR"
          SRC="server/target/release"
          for svc in data_postgres data_redis data_storage \
                     runtime_api control_plane messaging_gateway worker; do
            cp "$SRC/$svc" "$RELEASE_DIR/$svc"
          done
          chmod +x "$RELEASE_DIR"/*
          # Copia migrations para o diretório da release
          cp -r server/crates/infrastructure_postgres/migrations "$RELEASE_DIR/migrations"

      - name: Atualiza symlink current
        env:
          TAG: ${{ steps.version.outputs.TAG }}
        run: |
          RELEASES_DIR="/opt/smartcore/prod/releases"
          ln -sfn "$RELEASES_DIR/$TAG" "$RELEASES_DIR/current"

      - name: Reinicia serviços PROD (rolling restart)
        run: |
          # Para o runtime_api primeiro (para de aceitar novas requisições)
          sudo systemctl stop smartcore-prod-runtime_api
          # Reinicia serviços internos
          sudo systemctl restart smartcore-prod-data_redis
          sleep 2
          sudo systemctl restart smartcore-prod-data_postgres
          sleep 3
          sudo systemctl restart smartcore-prod-data_storage \
                                 smartcore-prod-control_plane \
                                 smartcore-prod-messaging_gateway \
                                 smartcore-prod-worker
          sleep 3
          # Sobe runtime_api com a nova versão
          sudo systemctl start smartcore-prod-runtime_api

      - name: Smoke test PROD
        run: |
          sleep 8
          for svc in data_postgres data_redis data_storage runtime_api; do
            STATUS=$(sudo systemctl is-active smartcore-prod-$svc 2>/dev/null)
            if [ "$STATUS" != "active" ]; then
              echo "ERRO: smartcore-prod-$svc não está ativo"
              sudo journalctl -u smartcore-prod-$svc --no-pager -n 50
              exit 1
            fi
            echo "✓ smartcore-prod-$svc ativo"
          done

      - name: Rollback em falha
        if: failure()
        env:
          TAG: ${{ steps.version.outputs.TAG }}
        run: |
          echo "Falha — executando rollback..."
          RELEASES_DIR="/opt/smartcore/prod/releases"
          # Volta symlink para a release anterior
          PREV=$(ls -t "$RELEASES_DIR" | grep -v current | grep -v "$TAG" | head -1)
          if [ -n "$PREV" ]; then
            ln -sfn "$RELEASES_DIR/$PREV" "$RELEASES_DIR/current"
            echo "Revertendo para $PREV..."
            sudo systemctl restart smartcore-prod-data_redis \
                                   smartcore-prod-data_postgres \
                                   smartcore-prod-data_storage \
                                   smartcore-prod-control_plane \
                                   smartcore-prod-messaging_gateway \
                                   smartcore-prod-worker \
                                   smartcore-prod-runtime_api
            echo "Rollback para $PREV concluído."
          else
            echo "Sem release anterior — rollback manual necessário."
          fi

      - name: Cria GitHub Release
        if: success()
        uses: softprops/action-gh-release@v2
        with:
          name: "v${{ steps.version.outputs.TAG }}"
          generate_release_notes: true
          draft: false

      - name: Remove releases antigas (mantém últimas 5)
        if: success()
        run: |
          RELEASES_DIR="/opt/smartcore/prod/releases"
          ls -dt "$RELEASES_DIR"/v* | tail -n +6 | xargs rm -rf || true

  flutter-windows:
    name: Build Flutter Windows
    runs-on: windows-latest
    needs: build-and-deploy
    if: success()
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
          channel: stable

      - name: flutter build windows
        working-directory: clients/flutter_windows
        run: flutter build windows --release

      - name: Empacota release
        run: |
          Compress-Archive `
            -Path "clients/flutter_windows/build/windows/x64/runner/Release/*" `
            -DestinationPath "SmartCore-Windows-${{ github.ref_name }}.zip"
        shell: pwsh

      - name: Upload para GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: SmartCore-Windows-*.zip
```

### 9.4 PR automático `dev → main` após tag

**Arquivo:** `.github/workflows/pr-to-main.yml`

```yaml
name: PR dev → main após release

on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']

jobs:
  create-pr:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Cria PR dev → main
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          TAG: ${{ github.ref_name }}
        run: |
          gh pr create \
            --base main \
            --head dev \
            --title "Release $TAG — merge dev → main" \
            --body "Deploy da versão **$TAG** concluído em produção. Merge automático para registrar o estado no \`main\`." \
            --label "release" || echo "PR já existe ou erro não crítico"
```

---

### 9.5 Deploy do admin Flutter Web sob `/v2/admin`

A partir do ciclo de implantação do web admin (`deploy-admin-web`), o bundle do Flutter Web (`smart-core-admin`) foi incluído no fluxo de CI/CD.

#### Estratégia de Build
- O build é executado no **runner self-hosted** (Hostinger), exigindo a instalação do Flutter SDK no usuário `gh-runner` (realizado via `server-setup.sh`).
- O build utiliza compilação para **WASM** (`--wasm`), definindo a base das URLs como `/v2/admin/` (`--base-href /v2/admin/`) e injetando o endpoint correto em build-time por meio de `--dart-define=SMARTCORE_API_ENDPOINT`.
- Comando de build (DEV):
  ```bash
  flutter build web --wasm --base-href /v2/admin/ -t lib/main_dev.dart --dart-define=SMARTCORE_API_ENDPOINT=https://dev.smartcoreassistant.com.br
  ```
- Comando de build (PROD):
  ```bash
  flutter build web --wasm --base-href /v2/admin/ -t lib/main_prod.dart --dart-define=SMARTCORE_API_ENDPOINT=https://smartcoreassistant.com.br
  ```

#### Publicação e Diretórios
- **Ambiente DEV:** Publicado atômica e diretamente em `/srv/smart-core-admin/dev/web`, realizando backup em `/srv/smart-core-admin/dev/web.bak` para permitir rollback rápido.
- **Ambiente PROD:** Publicado de forma versionada sob `/srv/smart-core-admin/prod/releases/$TAG/web`, apontando o symlink estável `/srv/smart-core-admin/prod/web` para a versão ativa.
- **Rollback:** Integrado ao rollback de falha dos binários no pipeline (DEV restaura o backup e PROD reverte o symlink estável para a release anterior `PREV_WEB`).

#### Roteamento no Caddy
- O Caddy atua como borda única, realizando o roteamento com same-origin para as chamadas de API gRPC-Web e SPA fallback no subpath `/v2/admin/*` direcionando para `index.html`.
- Fachadas gRPC-Web (bind localhost):
  - PROD: `127.0.0.1:50051` (Caddy direciona `path /smartcore.contracts.*`)
  - DEV: `127.0.0.1:50061` (Caddy direciona `path /smartcore.contracts.*`)

---

## 10. GitHub Secrets e Environments

### 10.1 Secrets necessários (Settings → Secrets → Actions)

| Secret | Descrição | Usado em |
|---|---|---|
| `GHCR_TOKEN` | PAT com `packages:write` (para releases) | deploy-prod |
| Nenhum outro | Runner self-hosted acessa `.env` diretamente no disco | — |

**Observação:** Como o runner roda no próprio servidor, não precisamos de secrets SSH
para deploy — o runner já está na máquina certa.

### 10.2 Environments do GitHub (Settings → Environments)

| Environment | Configuração |
|---|---|
| `dev` | Sem proteção — deploy automático em push |
| `prod` | `Required reviewers`: 1 (o próprio owner) + `Deployment branches`: somente tags `v*` |

---

## 11. Observabilidade (Grafana LGTM Stack)

Instalar via Docker Compose no mesmo servidor. Criar `docker/compose/observability.yml`:

```yaml
# Stack LGTM: Loki (logs) + Grafana (UI) + Tempo (traces) + Mimir (métricas)
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel_collector
    volumes:
      - ./config/otel-collector.yml:/etc/otelcol-contrib/config.yaml
    ports:
      - "4317:4317"   # gRPC OTLP (recebe traces dos microsserviços)
      - "4318:4318"   # HTTP OTLP (alternativa)
    networks: [observability]
    restart: unless-stopped

  loki:
    image: grafana/loki:latest
    container_name: loki
    volumes:
      - loki_data:/loki
    networks: [observability]
    restart: unless-stopped

  tempo:
    image: grafana/tempo:latest
    container_name: tempo
    volumes:
      - tempo_data:/var/tempo
      - ./config/tempo.yml:/etc/tempo.yaml
    networks: [observability]
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - prometheus_data:/prometheus
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
    networks: [observability]
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
      GF_SERVER_ROOT_URL: https://grafana.smartcoreassistant.com.br
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"
    networks: [observability]
    restart: unless-stopped
    depends_on: [loki, tempo, prometheus]

networks:
  observability:
    name: smartcore_observability
    driver: bridge

volumes:
  loki_data:
  tempo_data:
  prometheus_data:
  grafana_data:
```

**Datasources pré-configurados no Grafana:**
- Loki → `http://loki:3100`
- Tempo → `http://tempo:3200`
- Prometheus → `http://prometheus:9090`

**OTEL Collector config** (`config/otel-collector.yml`):
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s

exporters:
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
  otlp/tempo:
    endpoint: http://tempo:4317
  prometheus:
    endpoint: 0.0.0.0:8889

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/tempo]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [loki]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

---

## 12. Rollback e Disaster Recovery

### 12.1 Rollback de binários (prod)

```bash
# Lista releases disponíveis
ls -lt /opt/smartcore/prod/releases/

# Volta para versão anterior
TARGET="v1.0.0"   # substitua pela versão desejada
ln -sfn /opt/smartcore/prod/releases/$TARGET /opt/smartcore/prod/releases/current
sudo systemctl restart smartcore-prod-data_redis smartcore-prod-data_postgres \
     smartcore-prod-data_storage smartcore-prod-control_plane \
     smartcore-prod-messaging_gateway smartcore-prod-worker smartcore-prod-runtime_api
```

### 12.2 Rollback de banco de dados

```bash
# Lista backups disponíveis
ls -lt /opt/smartcore/prod/db-backup-*.dump

# Restaura backup (CUIDADO: destrói dados atuais)
BACKUP="/opt/smartcore/prod/db-backup-v1.1.0-20260601.dump"
docker exec -i smartcore-v2-postgres pg_restore \
  -U smartcore_app \
  -d smartcore_v2 \
  --clean \
  < "$BACKUP"
```

### 12.3 Política de retenção

| Item | Retenção |
|---|---|
| Releases de binários prod | Últimas 5 versões |
| Backups de banco de dados | Últimos 5 por release |
| Logs do journald | 7 dias (configurar em `/etc/systemd/journald.conf`) |
| Logs do Caddy | 10 MB por arquivo, mantém 5 arquivos |
| Binários dev | Apenas a versão atual + backup imediato |

---

## 13. Checklist de Implementação (sequência)

### Fase devops-1 — Servidor
- [ ] Executar `infra/server-setup.sh` no Hostinger como root
- [ ] Criar banco `smartcore_v2_dev` no PostgreSQL existente
- [ ] Criar usuário `smartcore_admin` com BYPASSRLS no PostgreSQL
- [ ] Configurar `/etc/caddy/Caddyfile` e iniciar Caddy
- [ ] Apontar DNS: `api.smartcoreassistant.com.br` → IP do servidor
- [ ] Apontar DNS: `dev-api.smartcoreassistant.com.br` → IP do servidor
- [ ] Apontar DNS: `grafana.smartcoreassistant.com.br` → IP do servidor
- [ ] Verificar TLS automático do Caddy (Let's Encrypt)

### Fase devops-2 — Systemd
- [ ] Criar todos os `.service` files em `/etc/systemd/system/`
- [ ] `systemctl daemon-reload`
- [ ] Criar `.env` files em `/opt/smartcore/{dev,prod}/` com os valores reais
- [ ] Habilitar targets: `systemctl enable smartcore-prod.target smartcore-dev.target`
- [ ] `systemctl daemon-reload` (sem `start` ainda — os binários não existem; o
      `ExecStart` aponta para `releases/current` (prod) / `bin/` (dev) que só são
      populados no **primeiro deploy**. Iniciar antes disso falha, é esperado.)

### Fase devops-3 — GitHub Actions
- [ ] Criar environments `dev` e `prod` no GitHub (Settings → Environments)
- [ ] Configurar `prod` com `Required reviewers`
- [ ] Instalar self-hosted runner no servidor (seção 8)
- [ ] Workflows já versionados em `.github/workflows/` — revisar `SEU-ORG` nos comentários
- [ ] Ajustar `Description=`/`Documentation=` dos `.service` (placeholder `seu-org`)
- [ ] Fazer push de teste na `dev` e verificar que CI passa
- [ ] Verificar que runner self-hosted executa o build

### Fase devops-4 — Primeiro deploy completo
- [ ] Primeiro push em `dev` com algum código compilável
- [ ] Verificar build no runner self-hosted (primeira vez compila tudo — 20-40 min)
- [ ] Após o deploy popular os binários, **só então** os serviços sobem
- [ ] Verificar que `smoke test` passa
- [ ] Testar rollback manualmente (simular falha → confirma retorno à versão anterior)
- [ ] Criar tag `v0.1.0` → verificar deploy prod com aprovação manual
- [ ] Verificar GitHub Release criada automaticamente
- [ ] Confirmar PR automático `dev → main` aberto pela `pr-to-main.yml`

### Fase devops-5 — Observabilidade
- [ ] Subir stack LGTM: `docker compose -f docker/compose/observability.yml up -d`
- [ ] Verificar Grafana em `https://grafana.smartcoreassistant.com.br`
- [ ] Configurar datasources (Loki, Tempo, Prometheus)
- [ ] Criar dashboard básico: uptime dos serviços, latência gRPC, erros

---

## 14. Manutenção Contínua

### Atualizações de sistema
```bash
# Atualização mensal do servidor (via cron no servidor ou manual)
apt-get update && apt-get upgrade -y
systemctl restart caddy

# Atualização do runner (via cron no gh-runner)
cd ~/actions-runner && ./run.sh --once  # atualização automática pelo runner
```

### Cron jobs no servidor
```bash
# /etc/cron.d/smartcore
# Renovação de certificados (Caddy faz automático, mas bom ter fallback)
0 3 * * * root caddy reload --config /etc/caddy/Caddyfile 2>/dev/null

# Limpeza de logs antigos do journald
0 4 * * 0 root journalctl --vacuum-time=7d
```

### Monitoramento de recursos (alertas)
Configurar no Grafana:
- Alerta: CPU > 80% por mais de 5 minutos
- Alerta: RAM disponível < 1 GB
- Alerta: Disco > 80% de uso
- Alerta: Qualquer serviço `smartcore-prod-*` não está `active`

---

## 15. Riscos Operacionais e Capacidade do Servidor

Um único KVM2 (2 vCPU / 8 GB) hospeda **tudo**: 2 ambientes × 7 serviços Rust + Postgres
+ 2 Redis + stack LGTM (5 containers) + self-hosted runner + builds de release.
Os riscos abaixo precisam de mitigação explícita.

### 15.1 Disco — o risco mais provável

Fontes de crescimento que podem **encher o disco e derrubar tudo**:
- `server/target/` no runner: build de release Rust facilmente passa de **5-15 GB**.
- Releases versionadas em `/opt/smartcore/prod/releases/` (7 binários cada).
- Backups `pg_dump` por release.
- Imagens e volumes Docker (Postgres data, Loki/Tempo/Prometheus).
- Logs do journald e do Caddy.

**Mitigações (todas já previstas, reforçar):**
```bash
# /etc/cron.d/smartcore — limpeza de disco
# Limpa o target/ do runner semanalmente (rust-cache do CI já guarda o essencial)
0 5 * * 0 gh-runner find /home/gh-runner/_work -name target -type d -exec cargo clean --manifest-path {}/../Cargo.toml \; 2>/dev/null
# Prune de imagens Docker órfãs
0 5 * * 1 root docker image prune -af --filter 'until=168h'
```
- Releases: workflow já mantém só as **últimas 5**.
- Backups DB: workflow já mantém só os **últimos 5**.
- **Alerta de disco > 75%** no Grafana (mais agressivo que os 80% genéricos).
- Considerar `target-dir` compartilhado entre dev/prod no runner para não duplicar.

### 15.2 Runner único serializa os deploys

Há **um** self-hosted runner. Os workflows `deploy-dev` e `deploy-prod` usam `concurrency`
com `cancel-in-progress: false`, mas como compartilham o mesmo runner, um deploy de prod
**espera** um build de dev em andamento (e vice-versa). Para o estágio atual (um
desenvolvedor) isso é aceitável. Se virar gargalo: registrar um segundo runner ou separar
o build (hosted) da entrega (self-hosted via artifact).

### 15.3 RAM sob pressão durante builds

`cargo build --release` consome bastante RAM e pode competir com Postgres/Redis/LGTM em
produção. Mitigações:
- Limitar paralelismo do build no runner: `CARGO_BUILD_JOBS=2` no `.bashrc` do `gh-runner`.
- Os limites de memória do compose (Postgres 512M, Redis 200M×2) já protegem
  os dados; o LGTM stack também deve ganhar `mem_limit`.
- Se a RAM for insuficiente, criar swap de 2-4 GB (`fallocate`/`swapon`).

### 15.4 Health check raso (apenas `systemctl is-active`)

O smoke test atual só verifica se o processo está `active`, não se o gRPC responde de fato.
Quando o `runtime_api` existir (F6), **promover o smoke test** para uma chamada real:
```bash
# Requer grpcurl instalado no servidor
grpcurl -plaintext localhost:8080 grpc.health.v1.Health/Check
```
Implementar o serviço de health gRPC (`tonic-health`) no `runtime_api` é pré-requisito.
Até lá, o `is-active` é a melhor verificação disponível.

### 15.5 Backup e segurança dos `.env`

Os `.env` de prod/dev contêm **todos os segredos** (DB, JWT, R2, SMTP) e **não** estão no
Git. Riscos: perda do servidor = perda dos segredos; ninguém mais tem cópia.
- Guardar cópia cifrada dos `.env` num cofre (1Password / Bitwarden / `age`-encrypted no Git).
- Permissão `chmod 600` e dono `smartcore` nos `.env`.
- Rotação periódica de `JWT_SECRET` e `ENCRYPTION_KEY` (atenção: girar `ENCRYPTION_KEY`
  exige redecifrar credenciais já gravadas — planejar antes).

### 15.6 Migrations e rollback (resumo do risco)

Rollback de binário **não** desfaz schema. Toda migração deve seguir **expand/contract**
(ver seção 6.4). Antes de tag de release com migração destrutiva, confirmar que a versão
anterior do binário ainda funciona com o schema novo — senão o rollback automático falha.

---

## 16. Resumo dos Achados de Auditoria (2026-06-07)

Correções aplicadas nos arquivos reais e nos planos durante a auditoria:

| # | Achado | Severidade | Correção |
|---|---|---|---|
| 1 | Container chamado `smartcore_v2_postgres` (underscore) nos scripts; o real é `smartcore-v2-postgres` (hífen) | 🔴 Crítico | Corrigido em workflow, `server-setup.sh`, planos 10 e 03 |
| 2 | Migrations em `server/migrations` (inexistente); reais em `crates/infrastructure_postgres/migrations` | 🔴 Crítico | Corrigido `cp` no workflow + comandos `--source` |
| 3 | CI sem validação do cache `.sqlx/` → query nova sem `prepare` quebraria o deploy | 🟠 Alto | Adicionado `cargo sqlx prepare --check` |
| 4 | Job Flutter usava `hashFiles()` em `if` de job (sempre vazio → nunca roda) | 🟠 Alto | Job `detect` com checkout + output |
| 5 | Plano assumia `REDIS_BUS_URL`/2 instâncias; código usa só `REDIS_URL` | 🟠 Alto | Alinhado; pendência registrada (§7.3) |
| 6 | Rollback de binário não desfaz migração de schema | 🟡 Médio | Documentado padrão expand/contract (§6.4) |
| 7 | Disco de 8 GB sob risco (target/, releases, backups, Docker) | 🟡 Médio | Seção de capacidade + crons de limpeza (§15) |
| 8 | Smoke test raso; health gRPC real só com runtime_api | 🟢 Baixo | Documentado plano de promoção (§15.4) |
| 9 | `.env` sem estratégia de backup/rotação | 🟡 Médio | Documentado (§15.5) |

---

*Documento criado em 2026-06-07 e auditado no mesmo dia. Executar o checklist da seção 13
antes de iniciar F6 (auth/runtime_api).*
