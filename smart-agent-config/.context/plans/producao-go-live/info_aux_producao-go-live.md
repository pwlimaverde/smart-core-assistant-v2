# Documentação Auxiliar — Conversão para produção (go-live da v2)

> Gerado em: 14/11/2026 (revisão 2); revisado em 24/11/2026 (revisão 3)
> Plano canônico: `.context/plans/producao-go-live.md`
> Plano completo: `.context/plans/producao-go-live/plano_completo_producao-go-live.md`

## Grupo A — Libs e ferramentas

| Item | Versão no projeto | Uso no plano | Fonte |
|---|---|---|---|
| `vpk` (Velopack CLI) | 1.2.161 (`release-windows.yml:45`) | `pack`, assinatura, delta | docs.velopack.io (consultado em 14/11/2026) |
| `velopack` (crate) | 1.2.0 (`clients/plugins/velopack_flutter/rust/Cargo.toml:12`) | Auto-update no app | idem |
| `velopack_flutter` | 0.3.2, cópia vendorizada (`clients/plugins/velopack_flutter`) | `initializeVelopack`, `isUpdateAvailable`, `updateAndRestart` | código local |
| `axum` | conforme `doc_dev/libs/rust/axum.md` | `releases_server`; o plano não altera a API | central local |
| Caddy | `caddy:2-alpine` | Borda, site | sem mudança de sintaxe além de `remote_ip` e cabeçalhos |

A central `doc_dev/libs/` não tem doc de Velopack. Como o plano não muda código
que chama a biblioteca (só o pipeline), não foi criado doc novo; se a Fase 10
tocar o plugin, criar `doc_dev/libs/flutter/velopack_flutter.md` nessa hora.

## Grupo B — Serviços externos

### Velopack — assinatura (`vpk pack`)

| Opção | O que faz |
|---|---|
| `--signParams "<args>"` | Repassa argumentos ao `signtool.exe` (sem o `sign`). É o que o projeto usa hoje, com PFX. Usar caminhos absolutos |
| `--signTemplate "<comando>"` | Roda um comando externo de assinatura; `{{file}}` assina um arquivo por chamada, `{{file...}}` vários |
| `--azureTrustedSignFile <json>` | Assina pelo serviço da Microsoft (Artifact Signing); autentica por `DefaultAzureCredential` |
| `--signParallel 1` | Desliga o lote de 10 arquivos por chamada; útil em assinatura interativa |

Notas da documentação:
- Desde 01/06/2023 o certificado não pode ser baixado: fica em HSM de nuvem ou
  token USB. Várias opções exigem passo manual e podem não funcionar em CI.
- OV: a reputação se acumula no certificado; ao renovar, o aviso pode voltar.
- Artifact Signing: reputação imediata, sem hardware, automatizável.
- A documentação do Velopack ainda diz que EV dá reputação imediata; a
  documentação da Microsoft diz o contrário (abaixo). Prevalece a da Microsoft.

### Velopack — delta

- `vpk pack` gera delta sozinho **se a versão anterior estiver na pasta de
  saída**. Em CI, rodar `vpk download` antes.
- `--delta None | BestSpeed (padrão) | BestSize`.
- O cliente decide entre vários deltas e o pacote completo por heurística.

### Microsoft — SmartScreen e assinatura

- Arquivos assinados com EV **não** passam mais direto pelo SmartScreen; a
  reputação padrão do EV deixou de existir em 2024 (as fontes divergem entre
  março e agosto).
- Artifact Signing (antes Trusted Signing): organizações dos EUA, Canadá, União
  Europeia e Reino Unido; pessoas físicas só EUA e Canadá. **Conferir na página
  atual antes de decidir** (D11) — é a única fonte com a lista de países.
- Detecção indevida: envio do arquivo pelo portal da Microsoft Security
  Intelligence.

### Evolution Go (inalterado)

`http://smartcore-evolution:8080`, cabeçalho `apikey`; contrato registrado na
memória do projeto (`evolution-go-contrato`). O plano não muda chamadas, só o
endereço de webhook que o `data_whatsapp` registra.

## Grupo C — Observabilidade e auditoria por fase

| Fase | Log/trace | `audit_log` | Sanitização |
|---|---|---|---|
| F0 | — | sem evento | só nomes de chave |
| F1 | `sshd`, `fail2ban` via promtail | sem evento | nenhum segredo em comando |
| F2 | `whatsapp.webhook.regravado` | `whatsapp.instance.webhook_update` | token em `SecretString`; sem telefone completo |
| F3 | acesso do Caddy em JSON; sonda externa | sem evento | site sem dado pessoal |
| F4 | recusas por rota; alerta de 200 fora da lista | sem evento novo | sem `Authorization` no log |
| F5 | — | sem evento | conferência por nome ou hash |
| F6 | `backup.copia_externa.*` | `migracao.*` se houver ETL | credenciais do ETL fora de log |
| F7 | webhooks recusados por ambiente | `whatsapp.instance.create` | chave global fora do log |
| F8 | `release.publicada`, `release.upload.recusado`, `release.download` | `release.download_link.emitido` (existe), `release.publicada` | ticket, token e segredo fora do log |
| F9 | anotação de deploy | `cutover.iniciado`/`.concluido` | chaves de LLM só pelo painel |
| F10 | resumo do job; versão em uso no login | `release.publicada` | chave privada nunca no runner |
| F11 | alertas disparados de propósito | conferência das linhas geradas | varredura por telefone/CPF |

## Arquivos de referência no repositório

| Assunto | Arquivo |
|---|---|
| Stack de produção | `docker/prod/compose.yml`, `docker/prod/.env.example` |
| Borda | `docker/edge/Caddyfile` |
| Deploy | `.github/workflows/deploy-dev.yml`, `deploy-prod.yml`, `pr-to-main.yml` |
| App Windows | `.github/workflows/release-windows.yml`, `infra/windows/README.md`, `infra/build-windows.ps1`, `clients/apps/smart-core-tenant/lib/platform/auto_update*.dart`, `lib/main_prod.dart`, `lib/main_dev.dart` |
| Servidor de releases | `server/apps/releases_server/src/`, `server/crates/release_ticket/`, `server/apps/control_plane/src/releases.rs`, `docker/releases/`, `doc_dev/runbooks/RUNBOOK_RELEASES.md` |
| Site | `docker/site/` |
| Backup | `docker/backup/backup.sh`, `infra/restore-postgres.sh`, `infra/RUNBOOK_ROBUSTEZ.md` |
| Webhook do Evolution | `server/apps/data_whatsapp/src/main.rs:362-365` |

## A validar no servidor (Fase 0)

1. Resolução de nome em rede compartilhada: `getent hosts data_postgres` e
   `getent hosts webhook_ingress` de dentro de um container.
2. Memória e disco (`free -h`, `df -h`).
3. Cadeia `DOCKER-USER` e portas escutando.
4. Versão do Evolution e existência de outra instância.
5. Resto da v1.
6. Container e versão do servidor de releases; conteúdo de
   `/opt/smartcore/releases-data`.
7. Container do site em uso (`smart-core-site-site-1`).
8. Ambientes protegidos, tags protegidas, visibilidade do repositório e das
   GitHub Releases.

## Convenções (revisão 3: valores reais de `docker/stack/<env>.vars`)

| Item | Dev | Produção |
|---|---|---|
| Rede de telemetria | `smart_core_v2_observability` (rede histórica) | `smart_core_v2_telemetria_prod` |
| URL do webhook registrada no Evolution | `http://webhook_ingress:9200` (pela `evolution_net`) | `http://172.17.0.1:9211` (fora da `evolution_net`) |
| Prefixo de instância (proposto, A3 aberto) | `dev-` | `prod-` |
| gRPC no host | 50051 | 50052 |
| Web admin / tenant | 8081 / 8083 | 8082 / 8084 (hoje de pé; fechar na Fase 2B/4) |
| OAuth / MCP | 8095 / 8099 | 8096 / 8100 |
| Webhook no host | 9210 | 9211 |
| Site | — | 8085 |
| Releases | 8086 (servidor único, dois canais) | 8086 |
| Canal do app | `beta` (build dev) | `stable` (build prod) |
| Tag | `win-vX.Y.Z-beta.N` | `vX.Y.Z` (servidor), `win-vX.Y.Z` (app) |
| Arquivo de ambiente | secret `ENV_FILE_B64` (env `dev`) → `/opt/smartcore/dev/env/dev.env` | secret `ENV_FILE_B64` (env `prod`) → `/opt/smartcore/prod/env/prod.env`; releases ainda em `/opt/smartcore/releases-stack/.env` (proposto: `/opt/smartcore/releases/env/releases.env`) |

## Notas gerais

- O passo 5 da skill (`scaffoldPlan`, `workflow-init`, `plan link`) é da sessão
  principal e não foi executado aqui: o canônico foi escrito à mão no formato
  dos planos existentes.
- Fontes: https://docs.velopack.io/packaging/signing ·
  https://docs.velopack.io/packaging/deltas ·
  https://learn.microsoft.com/windows/apps/package-and-deploy/smartscreen-reputation ·
  https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options

## Revisão 3 — Grafana Alloy e fim de vida do Promtail

- Fonte: https://grafana.com/docs/loki/latest/send-data/promtail/ (consultada em 24/11/2026).
- Texto oficial: "Promtail is end of life (EOL) as of March 2, 2026." Sem novas
  correções nem atualizações; a Grafana indica o **Grafana Alloy** como
  substituto e oferece conversão da configuração do Promtail
  (`alloy convert --source-format=promtail`).
- Relevância: o `docker/observability/compose.yml` ainda usa `promtail`. A troca
  é a decisão pendente D22 (Fase 2B). O Alloy tem os componentes
  `prometheus.exporter.unix` (host) e `prometheus.exporter.cadvisor`
  (containers), o que cobre A8 sem `node_exporter` e `cAdvisor` separados.
- Documentação do Alloy: https://grafana.com/docs/alloy/latest/
