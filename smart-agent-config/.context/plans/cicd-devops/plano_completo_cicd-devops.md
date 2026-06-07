# Plano Completo — CI/CD DevOps

> Reestruturado em: 2026-06-07
> Origem: `doc_dev/planejamento/10-plano-cicd-devops.md`
> Plano canônico: `.context/plans/cicd-devops.md`
> Documentação auxiliar: `.context/plans/cicd-devops/info_aux_cicd-devops.md`

---

## 1. Objetivo

Estabelecer toda a infraestrutura de CI/CD e DevOps do Smart Core Assistant v2
**antes** de qualquer feature de negócio. Ao final, o pipeline estará funcional e o
código será entregue automaticamente nos dois ambientes (dev/prod) a cada push/tag.

**Servidor alvo:** Hostinger KVM2 — 2 vCPU / 8 GB RAM / Ubuntu 22.04 LTS
**IP:** `76.13.229.210` | **SSH:** `root@76.13.229.210 -p 22`

---

## 2. Ambientes

| Aspecto | Dev | Prod |
|---|---|---|
| Trigger | Push na branch `dev` | Tag semântica `v*.*.*` |
| Banco | `smartcore_v2_dev` | `smartcore_v2` |
| Redis (banco lógico) | DB 1 | DB 0 |
| Sockets UDS | `/run/smartcore-dev/` | `/run/smartcore/` |
| Binários | `/opt/smartcore/dev/bin/` | `/opt/smartcore/prod/releases/<tag>/` |
| API gRPC porta | `8090` | `8080` |
| Domínio | `dev-api.smartcoreassistant.com.br` | `api.smartcoreassistant.com.br` |
| Aprovação manual | Não | Sim (GitHub Environment protection) |

---

## 3. Estado Atual dos Artefatos

Todos os artefatos de infraestrutura já estão **versionados e operacionais**:

### ✅ Já implementados
- **GitHub Actions Workflows** (4 arquivos em `.github/workflows/`)
  - `ci.yml` — lint, testes, sqlx prepare --check, detecção Flutter
  - `deploy-dev.yml` — build + deploy automático em push/dev
  - `deploy-prod.yml` — build + deploy com approval + rollback + Flutter Windows
  - `pr-to-main.yml` — PR automático dev→main após tag
- **Server setup** (`infra/server-setup.sh`) — provisionamento completo do servidor
- **Systemd services** (`infra/systemd/`) — 14 units + 2 targets
- **Caddy config** (embutido no server-setup.sh)
- **Docker Compose observabilidade** (`docker/compose/observability.yml`)
- **Configs OTEL/Loki/Tempo/Prometheus/Promtail** (`docker/observability/`)
- **Grafana provisioning** (`docker/observability/provisioning/`)

### ⬜ Pendente de execução (no servidor)
- Rodar `server-setup.sh` no Hostinger
- Criar bancos de dados (dev + admin user)
- Criar arquivos `.env` de produção/dev
- Copiar systemd units para `/etc/systemd/system/`
- Apontar DNS (3 domínios)
- Instalar self-hosted runner
- Subir stack de observabilidade
- Executar primeiro deploy de validação

---

## 4. Fases de Implementação (PREVC)

### Fase P — Planning (esta etapa)

**Escopo:** reestruturar o plano, validar artefatos existentes contra o plano
documentado, identificar divergências e corrigir.

**Entregas:**
- [x] Plano reestruturado (`plano_completo_cicd-devops.md`)
- [x] Documentação auxiliar (`info_aux_cicd-devops.md`)
- [x] Plano canônico (`cicd-devops.md`)

---

### Fase R — Review (validação de artefatos)

**Escopo:** revisar todos os artefatos existentes, garantir consistência entre eles,
e verificar que cobrem todos os requisitos do plano.

**Checklist de review:**

#### R.1 — Workflows GitHub Actions
- [ ] `ci.yml`: verificar que `SQLX_OFFLINE=true` está em todos os steps necessários
- [ ] `ci.yml`: confirmar que `cargo sqlx prepare --check` funciona com offline mode
- [ ] `deploy-dev.yml`: validar lista de binários (7 apps)
- [ ] `deploy-prod.yml`: validar rollback (captura de PREV_RELEASE via readlink)
- [ ] `deploy-prod.yml`: confirmar que Flutter job tem `if: needs.build-and-deploy.result == 'success'`
- [ ] `pr-to-main.yml`: verificar permissões `pull-requests: write`

#### R.2 — Server Setup
- [ ] `server-setup.sh`: confirmar que instala `docker.io`, `postgresql-client`
- [ ] `server-setup.sh`: verificar que configura journald (SystemMaxUse, MaxRetentionSec)
- [ ] `server-setup.sh`: confirmar que cria Caddyfile com h2c para gRPC
- [ ] `server-setup.sh`: verificar sudoers para `gh-runner` (inclui journalctl)
- [ ] `server-setup.sh`: confirmar que adiciona `gh-runner` ao grupo docker

#### R.3 — Systemd
- [ ] Verificar que todos os 14 services + 2 targets existem
- [ ] Confirmar dependências: runtime_api depende de todos os demais
- [ ] Verificar `EnvironmentFile=` apontando para o `.env` correto
- [ ] Confirmar `User=smartcore`, `NoNewPrivileges=yes`, `PrivateTmp=yes`

#### R.4 — Observabilidade
- [ ] `observability.yml`: verificar `mem_limit` em todos os containers
- [ ] `observability.yml`: confirmar que usa rede `smartcore_v2_network` (externa)
- [ ] Configs OTEL: validar pipelines (traces→Tempo, logs→Loki, metrics→Prometheus)
- [ ] Grafana provisioning: verificar datasources pré-configurados

#### R.5 — Segurança
- [ ] Verificar que nenhum `.env` real está commitado (apenas `.env.example`)
- [ ] Confirmar que `.gitignore` cobre `*.env`, `/infra/.env.*` (exceto .example)
- [ ] Verificar que firewall bloqueia portas internas (8080, 8090, 5434, 6380, 6381)

---

### Fase E — Execution (provisionamento do servidor)

**Pré-requisito:** acesso SSH ao servidor Hostinger como root.

#### E.1 — Servidor Base
```bash
# Conectar ao servidor
ssh root@76.13.229.210 -p 22

# Clonar o repositório (ou copiar os scripts)
git clone https://github.com/pwlimaverde/smart-core-assistant-v2.git /tmp/sca-setup
cd /tmp/sca-setup

# Executar provisionamento
bash infra/server-setup.sh
```

**Validação:**
- `caddy version` retorna versão ≥ 2.7
- `rustc --version` retorna stable
- `id smartcore` e `id gh-runner` existem
- `/opt/smartcore/{dev/bin,prod/releases,shared}` existem
- `ufw status` mostra apenas portas 22, 80, 443

#### E.2 — Banco de Dados
```bash
# Criar banco de dados dev
docker exec smartcore-v2-postgres psql -U smartcore_app \
  -c "CREATE DATABASE smartcore_v2_dev;"
docker exec smartcore-v2-postgres psql -U smartcore_app \
  -c "GRANT ALL ON DATABASE smartcore_v2_dev TO smartcore_app;"

# Criar usuário admin com BYPASSRLS
docker exec smartcore-v2-postgres psql -U smartcore_app \
  -c "CREATE USER smartcore_admin WITH PASSWORD '<SENHA_SEGURA>' BYPASSRLS;"
docker exec smartcore-v2-postgres psql -U smartcore_app \
  -c "GRANT ALL PRIVILEGES ON DATABASE smartcore_v2 TO smartcore_admin;"
docker exec smartcore-v2-postgres psql -U smartcore_app \
  -c "GRANT ALL PRIVILEGES ON DATABASE smartcore_v2_dev TO smartcore_admin;"
```

#### E.3 — Variáveis de Ambiente
```bash
# Criar .env de prod (usar template da seção 7 do plano original)
vim /opt/smartcore/prod/.env
chmod 600 /opt/smartcore/prod/.env
chown smartcore:smartcore /opt/smartcore/prod/.env

# Criar .env de dev
vim /opt/smartcore/dev/.env
chmod 600 /opt/smartcore/dev/.env
chown smartcore:smartcore /opt/smartcore/dev/.env
```

**Variáveis obrigatórias (ambos):**
- `DATABASE_URL` / `DATABASE_ADMIN_URL`
- `REDIS_URL`
- `S3_ENDPOINT` / `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` / `S3_BUCKET`
- `JWT_SECRET` / `ENCRYPTION_KEY`
- `SMARTCORE_*_ENDPOINT` (sockets UDS)
- `RUNTIME_API_GRPC_PORT` / `RUNTIME_API_GRPC_LISTEN`
- `RUST_LOG` / `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_SERVICE_NAMESPACE`

#### E.4 — Systemd Units
```bash
# Copiar todos os service files
cp infra/systemd/*.service /etc/systemd/system/
cp infra/systemd/*.target /etc/systemd/system/
systemctl daemon-reload

# Habilitar targets (NÃO iniciar — binários ainda não existem)
systemctl enable smartcore-prod.target smartcore-dev.target
```

#### E.5 — DNS
Apontar os seguintes registros A para o IP `76.13.229.210`:
- `api.smartcoreassistant.com.br`
- `dev-api.smartcoreassistant.com.br`
- `grafana.smartcoreassistant.com.br`

```bash
# Após DNS propagado, iniciar Caddy
systemctl start caddy
# Verificar TLS automático
curl -I https://api.smartcoreassistant.com.br 2>/dev/null | head -5
```

#### E.6 — Self-Hosted Runner
```bash
# Como usuário gh-runner
su - gh-runner
mkdir -p ~/actions-runner && cd ~/actions-runner

# Baixar runner (verificar versão atual)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Configurar (obter token em: github.com/pwlimaverde/smart-core-assistant-v2/settings/actions/runners/new)
./config.sh \
  --url https://github.com/pwlimaverde/smart-core-assistant-v2 \
  --token <TOKEN_DO_GITHUB> \
  --name hostinger-kvm2 \
  --labels self-hosted,linux,hostinger,x64 \
  --runnergroup Default \
  --work _work

# Instalar como serviço systemd
sudo ./svc.sh install gh-runner
sudo ./svc.sh start

# Limitar paralelismo de builds (mitigação de RAM)
echo 'export CARGO_BUILD_JOBS=2' >> ~/.bashrc
```

#### E.7 — GitHub Settings
- Criar environment `dev` (sem proteção) em Settings → Environments
- Criar environment `prod` com `Required reviewers`: 1 (owner)
- Configurar `prod` Deployment branches: somente tags `v*`
- Verificar `Settings → Actions → General → Fork pull request workflows` = `Require approval`

#### E.8 — Observabilidade
```bash
# Subir stack LGTM
docker compose -f docker/compose/observability.yml up -d

# Verificar Grafana
curl -s http://localhost:3000/api/health | jq .
# Deve retornar: {"commit":"...","database":"ok","version":"..."}

# Verificar OTEL Collector
curl -s http://localhost:4318/v1/traces -X POST \
  -H "Content-Type: application/json" -d '{}' || echo "OTEL respondendo"
```

#### E.9 — Crons de Manutenção
```bash
# /etc/cron.d/smartcore
cat > /etc/cron.d/smartcore << 'EOF'
# Limpeza do target/ do runner (semanal)
0 5 * * 0 gh-runner find /home/gh-runner/_work -name target -type d -exec cargo clean --manifest-path {}/../Cargo.toml \; 2>/dev/null

# Prune de imagens Docker órfãs (semanal)
0 5 * * 1 root docker image prune -af --filter 'until=168h'

# Limpeza de logs antigos do journald (semanal)
0 4 * * 0 root journalctl --vacuum-time=7d

# Caddy reload (diário — renovação TLS já é automática, mas garante config)
0 3 * * * root caddy reload --config /etc/caddy/Caddyfile 2>/dev/null
EOF
chmod 644 /etc/cron.d/smartcore
```

---

### Fase V — Validation (primeiro deploy completo)

#### V.1 — Deploy DEV (teste completo)
```bash
# No ambiente local (Windows), fazer push para dev
git push origin dev
```

**Verificações:**
- [ ] CI (`ci.yml`) passa em ubuntu-latest
- [ ] `deploy-dev.yml` é acionado e roda no self-hosted runner
- [ ] Build completa (primeira vez: 20-40 min com cache frio)
- [ ] Binários copiados para `/opt/smartcore/dev/bin/`
- [ ] Serviços DEV reiniciam na ordem correta
- [ ] Smoke test passa (todos os serviços `active`)
- [ ] Logs visíveis no Grafana (via Loki/Promtail)

#### V.2 — Teste de Rollback DEV
```bash
# Simular falha: parar runtime_api manualmente
ssh root@76.13.229.210 'sudo systemctl stop smartcore-dev-runtime_api'
# Verificar que o próximo push/deploy detecta a falha e faz rollback
```

#### V.3 — Deploy PROD (com tag)
```bash
# Criar primeira tag
git tag v0.1.0
git push origin v0.1.0
```

**Verificações:**
- [ ] `deploy-prod.yml` é acionado e aguarda approval
- [ ] Após approval, build + deploy executa
- [ ] Backup de banco gerado (`db-backup-v0.1.0-*.dump`)
- [ ] Binários em `/opt/smartcore/prod/releases/v0.1.0/`
- [ ] Symlink `current → v0.1.0`
- [ ] Serviços PROD reiniciam (rolling restart)
- [ ] Smoke test passa
- [ ] GitHub Release criada automaticamente
- [ ] PR automático `dev → main` aberto

#### V.4 — Rollback PROD manual
```bash
# Se necessário, testar rollback manual
ssh root@76.13.229.210
ln -sfn /opt/smartcore/prod/releases/v0.1.0 /opt/smartcore/prod/releases/current
sudo systemctl restart smartcore-prod-data_redis smartcore-prod-data_postgres \
     smartcore-prod-data_storage smartcore-prod-control_plane \
     smartcore-prod-messaging_gateway smartcore-prod-worker smartcore-prod-runtime_api
```

#### V.5 — Observabilidade
- [ ] Grafana acessível em `https://grafana.smartcoreassistant.com.br`
- [ ] Datasources configurados (Loki, Tempo, Prometheus)
- [ ] Logs dos serviços visíveis no Loki
- [ ] Traces visíveis no Tempo (quando serviços emitirem OTLP)
- [ ] Dashboard básico criado: uptime, latência, erros

#### V.6 — Segurança
- [ ] `ufw status` confirma apenas portas 22, 80, 443 abertas
- [ ] gRPC (8080/8090) **não** acessível externamente (apenas via Caddy)
- [ ] `.env` files com `chmod 600` e dono correto
- [ ] Runner roda como `gh-runner` (sem sudo irrestrito)
- [ ] Sudoers limitado a `systemctl` dos serviços smartcore

---

### Fase C — Confirmation (fechamento)

- [ ] Todos os checks da fase V passaram
- [ ] README atualizado com instruções de deploy
- [ ] `.env.example` atualizado em `infra/` com todas as variáveis necessárias
- [ ] Alertas do Grafana configurados (CPU, RAM, disco, serviços down)
- [ ] Backup cifrado dos `.env` guardado em cofre (1Password/Bitwarden)
- [ ] PR mergeado em dev e documentação atualizada

---

## 5. Riscos e Mitigações

| Risco | Severidade | Mitigação |
|---|---|---|
| Disco cheio (target/, releases, backups, Docker) | 🟡 Médio | Crons de limpeza + alerta disco > 75% |
| Runner único serializa deploys | 🟢 Baixo | Aceitável para 1 dev; escalar com 2º runner se necessário |
| RAM sob pressão durante builds | 🟡 Médio | `CARGO_BUILD_JOBS=2` + swap 2-4 GB se necessário |
| Health check raso (`is-active`) | 🟢 Baixo | Promoção para `grpcurl` após F6 (runtime_api + tonic-health) |
| `.env` sem backup | 🟡 Médio | Cópia cifrada em cofre externo |
| Migrations e rollback incompatíveis | 🟡 Médio | Padrão expand/contract obrigatório |
| Redis único para cache + bus | 🟡 Médio | Separar `REDIS_BUS_URL` antes de F3 |

---

## 6. Correções Aplicadas vs. Plano Base

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 1 | Plano alinhado com artefatos reais (workflows, scripts) | Artefatos já existiam e estavam mais maduros que o plano doc_dev | Comparação direta código vs. plano |
| 2 | Incluído Promtail na stack de observabilidade | `observability.yml` real já tem Promtail, plano não mencionava | `docker/compose/observability.yml` |
| 3 | Incluídos `mem_limit` em todos os containers LGTM | Real já tem, plano mencionava como pendência | `docker/compose/observability.yml` |
| 4 | Step `rustup update stable` no deploy | Real já tem, plano não previa | `.github/workflows/deploy-dev.yml:21` |
| 5 | Pattern `FAILED=0` no smoke test | Real já usa, plano usava `exit 1` direto | `.github/workflows/deploy-dev.yml:66` |
| 6 | Tracking de `PREV_RELEASE` via `readlink` no prod | Real já tem, plano usava `ls -t | grep` | `.github/workflows/deploy-prod.yml:75` |
| 7 | Remoção de release com falha no rollback prod | Real já faz `rm -rf`, plano não previa | `.github/workflows/deploy-prod.yml:140` |
| 8 | Config de journald no server-setup.sh | Real já configura, plano não mencionava | `infra/server-setup.sh:149` |
| 9 | Instalação de docker.io e postgresql-client | Real já instala, plano não listava | `infra/server-setup.sh:39` |
| 10 | `gh-runner` no grupo docker | Real já faz, necessário para `docker exec pg_dump` | `infra/server-setup.sh:85` |

---

## 7. Dependências de Outras Features

| Feature | Relação | Impacto |
|---|---|---|
| **F6 (Auth/runtime_api)** | Primeira feature a passar pelo pipeline | Valida deploy completo end-to-end |
| **F3 (Webhooks/messaging_gateway)** | Volume de eventos cresce | Separação `REDIS_BUS_URL` antes desta |
| **F5 (ia_engine Python)** | Novo serviço fora do Cargo workspace | Workflow adicional para Docker build Python |
| **F8 (Flutter Windows)** | Job Flutter no deploy-prod | Ativado automaticamente quando `clients/flutter_windows/pubspec.yaml` existir |
