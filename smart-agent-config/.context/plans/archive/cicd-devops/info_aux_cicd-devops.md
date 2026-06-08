# Documentação Auxiliar — CI/CD DevOps

> Gerado em: 2026-06-07
> Plano canônico: `.context/plans/archive/cicd-devops/cicd-devops.md`
> Plano completo: `.context/plans/archive/cicd-devops/plano_completo_cicd-devops.md`

## Natureza do Plano

Este plano é **puramente de infraestrutura/DevOps** — não consome libs Rust/Python
como código de aplicação. As dependências são **ferramentas CLI**, **serviços de
infraestrutura** e **configurações de sistema operacional**.

## Artefatos Já Existentes no Repositório

Os seguintes artefatos já foram criados e estão versionados:

### GitHub Actions Workflows
| Arquivo | Status | Localização |
|---|---|---|
| `ci.yml` | ✅ Existente | `.github/workflows/ci.yml` |
| `deploy-dev.yml` | ✅ Existente | `.github/workflows/deploy-dev.yml` |
| `deploy-prod.yml` | ✅ Existente | `.github/workflows/deploy-prod.yml` |
| `pr-to-main.yml` | ✅ Existente | `.github/workflows/pr-to-main.yml` |

### Infra Scripts
| Arquivo | Status | Localização |
|---|---|---|
| `server-setup.sh` | ✅ Existente | `infra/server-setup.sh` |
| Systemd services (14 units + 2 targets) | ✅ Existentes | `infra/systemd/` |
| `.env.deploy.example` | ✅ Existente | `infra/.env.deploy.example` |

### Docker Compose & Observabilidade
| Arquivo | Status | Localização |
|---|---|---|
| `observability.yml` | ✅ Existente | `docker/compose/observability.yml` |
| `otel-collector-config.yml` | ✅ Existente | `docker/observability/otel-collector-config.yml` |
| `loki-config.yml` | ✅ Existente | `docker/observability/loki-config.yml` |
| `tempo-config.yml` | ✅ Existente | `docker/observability/tempo-config.yml` |
| `prometheus.yml` | ✅ Existente | `docker/observability/prometheus.yml` |
| `promtail-config.yml` | ✅ Existente | `docker/observability/promtail-config.yml` |
| Grafana provisioning | ✅ Existente | `docker/observability/provisioning/` |

## Ferramentas e Serviços Externos

### GitHub Actions (CI/CD)
- **Versões das actions utilizadas:**
  - `actions/checkout@v4` — estável, sem breaking changes
  - `dtolnay/rust-toolchain@stable` — referência para Rust CI
  - `Swatinem/rust-cache@v2` — cache de Cargo eficiente
  - `subosito/flutter-action@v2` — setup Flutter
  - `softprops/action-gh-release@v2` — criação de releases
- **Self-hosted runner:** versão 2.317.0+ (atualização automática)
- **Environments:** `dev` (sem proteção) + `prod` (approval manual)

### Caddy v2 (Reverse Proxy)
- **Funcionalidade:** reverse proxy com TLS automático (Let's Encrypt/ZeroSSL)
- **Configuração:** h2c para gRPC (Tonic), rolling logs 10MB × 5
- **Domínios:** `api.smartcoreassistant.com.br` (prod), `dev-api.smartcoreassistant.com.br` (dev), `grafana.smartcoreassistant.com.br`
- **Referência:** [Caddy docs](https://caddyserver.com/docs/)

### systemd (Gerenciamento de Serviços)
- **14 service units** (7 por ambiente: data_redis, data_postgres, data_storage, control_plane, messaging_gateway, worker, runtime_api)
- **2 target units** (smartcore-prod.target, smartcore-dev.target)
- **Ordem de boot:** redis → postgres → storage/control_plane/messaging_gateway/worker → runtime_api
- **tmpfiles.d:** garante `/run/smartcore*` após reboot
- **Referência:** Arquivos existentes em `infra/systemd/`

### Stack LGTM (Observabilidade)
- **Grafana** — painel visual (porta 3000)
- **Loki** — agregação de logs (porta 3100)
- **Tempo** — traces distribuídos (porta 3200)
- **Prometheus** — métricas (porta 9090)
- **OTEL Collector** — ponto de entrada OTLP (gRPC 4317 / HTTP 4318)
- **Promtail** — coleta de logs Docker
- **Rede:** `smartcore_v2_network` (externa, compartilhada com data stack)
- **Limites de memória:** OTEL 128M, Loki 256M, Tempo 256M, Prometheus 256M, Grafana 128M, Promtail 64M

### PostgreSQL (via Docker)
- **Container:** `smartcore-v2-postgres` (porta 5434)
- **Bancos:** `smartcore_v2` (prod), `smartcore_v2_dev` (dev)
- **Usuários:** `smartcore_app` (RLS), `smartcore_admin` (BYPASSRLS, DDL)
- **Migrations:** embutidas nos binários via `sqlx::migrate!`

### Redis (via Docker)
- **Container cache:** `smartcore-v2-redis` (porta 6380, allkeys-lru)
- **Container bus:** `smartcore-v2-redis-bus` (porta 6381, noeviction)
- **Isolamento dev/prod:** bancos lógicos (prod=DB 0, dev=DB 1)
- **Pendência:** separar `REDIS_BUS_URL` no código (§7.3 do plano)

### Rust Toolchain (no servidor)
- **sqlx-cli:** instalado em `/opt/smartcore/shared/sqlx` para migrations manuais
- **Build flags:** `SQLX_OFFLINE=true`, `RUSTFLAGS="-C target-cpu=native"`
- **CARGO_BUILD_JOBS:** recomendação de limitar a 2 no runner (mitigação de RAM)

### Cloudflare R2 / MinIO
- **Storage:** S3-compatible, endpoint + credentials via `.env`
- **Bucket:** `media-smart-core-assistant`

## Divergências Identificadas (Plano vs. Artefatos Reais)

### Já Corrigidas (Auditoria 2026-06-07, seção 16 do plano)
1. ✅ Container name `smartcore-v2-postgres` (hífen, não underscore)
2. ✅ Path de migrations corrigido para `crates/infrastructure_postgres/migrations`
3. ✅ `cargo sqlx prepare --check` adicionado ao CI
4. ✅ Job Flutter com detecção dinâmica (job `detect`)
5. ✅ `REDIS_URL` único documentado (pendência de separação registrada)
6. ✅ Padrão expand/contract para migrations documentado

### Diferenças Menores (Plano doc_dev vs. Workflow Real)
- **Plano:** smoke test com `sleep 5` → **Real:** `sleep 8` (dev) / `sleep 10` (prod) — OK, margem maior
- **Plano:** workflow deploy-dev sem `rustup update stable` → **Real:** tem step de update — melhoria
- **Plano:** `FAILED=0` pattern não aparece → **Real:** usa pattern correto para exit code
- **Plano:** deploy-prod sem `PREV_RELEASE` tracking → **Real:** salva via `readlink` + `GITHUB_ENV`
- **Plano:** deploy-prod rollback remove release com falha → **Real:** sim, `rm -rf "$RELEASES_DIR/$TAG"` — melhoria
- **Plano:** observability sem Promtail → **Real:** tem Promtail para logs Docker
- **Plano:** observability sem `mem_limit` → **Real:** todos os containers têm `deploy.resources.limits.memory`
- **Plano:** server-setup.sh sem journald config → **Real:** configura `SystemMaxUse=500M` e `MaxRetentionSec=7day`
- **Plano:** server-setup.sh sem docker install → **Real:** instala `docker.io` e `postgresql-client`

> **Conclusão:** Os artefatos reais estão **mais maduros** que o plano documentado.
> Os workflows e scripts já incorporam melhorias que o plano-base não previu.
> O plano reestruturado deve refletir o estado real dos artefatos.

## Notas Gerais

- **Servidor:** Hostinger KVM2 (2 vCPU / 8 GB RAM / Ubuntu 22.04 LTS)
- **IP:** 76.13.229.210
- **Risco principal:** disco (target/ do runner pode crescer 5-15 GB)
- **Mitigação:** crons de limpeza semanais já previstos
- **Health check:** atual é `systemctl is-active` (raso); promoção para `grpcurl` planejada após F6
