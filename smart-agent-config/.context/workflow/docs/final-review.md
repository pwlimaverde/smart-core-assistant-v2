# Final Review — migracao-full-docker
Data: 2026-06-20 · Modelo: Opus · Diff auditado: commit `df02554` (working tree limpo)

## Rótulo: CORRIGIDO  (informativo — não bloqueia o ciclo)

## Resumo das correções
A implementação do commit `df02554` estava majoritariamente fiel ao plano (transport,
Dockerfile, compose, edge, workflows, remoção do systemd). Foram corrigidos **10 desvios**:
3 bugs que impediriam o deploy (Caddyfile sem `DOMAIN`, `env_file` em YAML de fluxo inválido,
referência `id.meta-edge` no workflow prod), 1 script quebrado (`server-setup.sh` com bloco
de echo malformado), 1 falha de versionamento (env.example gitignored), o descompasso de
caminho do env real entre `server-setup.sh` e os workflows, e a limpeza de configuração
morta (compose antigos + scripts de deploy host obsoletos).

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---------------|--------|------------|
| E.1 Transport resolve hostname TCP (`Endpoint::Tcp(String)` + `ToSocketAddrs`) | ✅ | Fiel: parse validado, bind/connect via `as_str()`, teste de hostname adicionado, testes antigos ajustados. |
| E.2 Dockerfile server (cargo-chef, flatc URL do CI, SQLX_OFFLINE, debian-slim non-root, sem ENTRYPOINT) | ✅ | Fiel; `libpq5` corretamente ausente. |
| E.3 `compose.yml` (7 serviços, minio profile dev, redes internal+observability, healthchecks `$$`) | ⚠️→✅ | `env_file` em sequência de fluxo quebrava o YAML; edge sem `DOMAIN`. Corrigidos. |
| E.4 `compose.observability.yml` (projeto próprio cria a rede external) | ✅ | Fiel. |
| E.5 Edge (Caddy + bundle, HTTP/1.1 sem h2c, persiste `caddy_data`) | ⚠️→✅ | Caddyfile usa `{$DOMAIN}` mas o container não recebia a var. Corrigido. |
| E.6 Env-files de exemplo versionados | ❌→✅ | Existiam no working tree mas **gitignored** (`env/` pegava `docker/compose/env/`). Agora versionados. |
| E.7 Workflows GHCR (tags por ambiente, approval prod, cache scope) | ⚠️→✅ | `deploy-prod` referenciava `id.meta-edge` (inválido) e ambos não provisionavam o env real. Corrigidos. |
| E.8 Remoções (systemd, Caddyfile host, provisioning) | ⚠️→✅ | systemd e `infra/Caddyfile` removidos; faltou remover compose antigos e scripts host obsoletos. Removidos agora. |
| Transport: testes mantidos + novo teste hostname | ✅ | `parses_tcp_endpoint_com_hostname` presente. |
| `cleanup-hostinger.sh` (limpeza do legado) | ✅ | Presente e com sintaxe válida. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---------------|----------|----------|
| `docker/compose/compose.yml` (edge) | Caddyfile usa `{$DOMAIN}` mas o serviço `edge` não recebia a variável → borda subiria sem domínio (TLS falha). | Adicionado `environment: DOMAIN: ${DOMAIN}` ao serviço edge. |
| `docker/compose/compose.yml` (7×) | `env_file: [./env/${ENV_FILE}]` — em sequência de fluxo YAML o `{` de `${...}` é indicador inválido → `docker compose config` falharia. | Convertido para forma de bloco (`env_file:` + item `- ./env/${ENV_FILE}`). |
| `.github/workflows/deploy-prod.yml:90` | `tags: ${{ id.meta-edge.outputs.tags }}` — sintaxe inválida; imagem edge sairia sem tag → build falha. | Corrigido para `${{ steps.meta-edge.outputs.tags }}`. |
| `.github/workflows/deploy-dev.yml`, `deploy-prod.yml` | Compose roda `--env-file env/{env}.env`, mas esse arquivo (com segredos) é gitignored e o `checkout` limpa o working tree → env real some no deploy. | Passo novo "Provisiona env real do servidor" copia de `/opt/smartcore/{env}/env/{env}.env` (caminho do `server-setup.sh`). |
| `infra/server-setup.sh:108-117` | Bloco "PRÓXIMOS PASSOS" malformado (linhas `2.`, `3.`… fora de `echo`) → com `set -e` o script abortaria. | Reescrito como `echo` válidos. |
| `infra/server-setup.sh` (mkdir/chown) | Criava dirs vestigiais do modelo host (`/srv/smart-core-admin`, `prod/releases`) que o full-docker não usa. | Mantidos só `dev/env`, `prod/env`, `prod/backups`. |
| `.gitignore` | Regra `env/` (venvs) capturava `docker/compose/env/`, impedindo versionar os `*.env.example`. | Re-inclusão explícita: `!docker/compose/env/`, ignora `*.env` reais, versiona `*.env.example`. |
| `docker/compose/env/{dev,prod}.env.example` | Não estavam versionados. | `git add` após corrigir o gitignore. |
| `docker/compose/data.yml`, `observability.yml` | Superados por `compose.yml`/`compose.observability.yml` (config morta). | Removidos (`git rm`). |
| `infra/deploy-data.sh`, `deploy-data.ps1`, `manage.ps1` | Scripts do fluxo host antigo (push de `data.yml` via scp) — obsoletos no GHCR/compose. | Removidos (`git rm`). |
| `docker/compose/env/prod.env.example` | `S3_FORCE_PATH_STYLE=false` divergia da config R2 já validada no projeto (`infra/.env.deploy.example` usa `true`). | Ajustado para `true`. |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---------------|-----------|-----------|-------------|------------|
| Transport TCP (resolução de hostname) | ✅ | N/A | ✅ | `tracing::info!(endpoint, local)` no bind; sem segredos; sem novo evento de domínio. |
| Empacotamento em containers (Dockerfile/compose) | ✅ | N/A | ✅ | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` + `OTEL_SERVICE_NAMESPACE` por ambiente; serviços em `internal`+`observability`. |
| Edge (Caddy) | ✅ | N/A | ✅ | Headers de segurança (CSP `wasm-unsafe-eval`, HSTS) mantidos. |
| Env-files | N/A | N/A | ✅ | Só `*.env.example` com placeholders versionado; `*.env` reais gitignored. |

> A migração **não cria nem altera eventos de auditoria de domínio** — só muda transporte e
> empacotamento. A trilha `transport::bus → data_postgres → audit_log` deve ser exercida no
> smoke-test ao subir o stack (ver Pendências).

## 3. Decisões Autônomas (revisar depois)
- **Remoção de `infra/deploy-data.{sh,ps1}` e `manage.ps1`**: assumi que o fluxo host de deploy
  de dados foi totalmente substituído pelo compose+GHCR. `infra/tunnel.{sh,ps1}` foram **mantidos**
  (uso de dev local contra DB remoto).
- **`env_file` em forma de bloco**: mudança puramente sintática, sem efeito de runtime.

## 4. Revalidação
- lint/type-check Python: N/A (nenhum código Python tocado neste ciclo).
- compile Rust: a transport (única mudança Rust) veio do commit `df02554` e **não foi alterada**
  neste review; diff revisado estaticamente (correto). Não re-executei `cargo` para não subir
  túnel/infra de teste; recomenda-se rodar `.\infra\test-local.ps1` antes do próximo deploy.
- YAML (compose + workflows): ✅ validado com parser após correção do `env_file`.
- Shell (`bash -n`): ✅ `server-setup.sh` e `cleanup-hostinger.sh` sem erro de sintaxe.
- `docker compose config`: ⚠️ não executável aqui (Docker só no servidor Hostinger); YAML validado por parser como proxy.

## 5. Pendências (escopo extra ou fora do plano)
- **Smoke-test no servidor** (Fase V do plano, exige Docker/servidor): subir observabilidade →
  dev → prod, confirmar containers `healthy`, gRPC-Web via Caddy, admin em `/v2/admin/`, traces
  separados por namespace no Grafana, e **um evento real persistido em `audit_log`**.
- **Limpeza do Hostinger**: rodar `infra/cleanup-hostinger.sh` + remover projetos Docker legados
  `smart-core-app/-data/-workers` (o usuário executa via SSH).
- **GitHub Environment `production`**: configurar Required reviewers para o approval manual do `deploy-prod`.
- **`bind` por nome-de-serviço**: se o smoke-test acusar falha de bind TCP no container, aplicar o
  fallback `0.0.0.0:porta` previsto no plano (E.1).
