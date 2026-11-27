---
type: plan
name: "Conversão para produção (go-live da v2)"
planSlug: producao-go-live
description: "Leva ao público a stack de servidor da v2 que JÁ RODA na VPS (smart-core-v2-prod por tag desde 22/11/2026, ao lado da dev, com o Evolution Go compartilhado), o aplicativo Windows no canal estável com instalador assinado por certificado público e auto-update com portões, o servidor de releases e o site público, todos por versão e pelo deploy. A versão web (admin e tenant) NÃO é publicada neste go-live: fica fechada na borda até decisão do dono. Restam backup externo, canal estável sem portão, segredos expostos, web aberta na borda, site/releases fora do deploy e a simplificação do servidor."
summary: "Revisão 3 (24/11/2026): C1–C3 resolvidos pelo plano servidor-reestruturacao-dev-prod (stack docker/stack/, bundle, deploy-infra.yml); C4, C5 e C6 seguem abertos. Fase 0 feita pelo inventário de 23–24/11. Prod v0.2.2 no ar; dev 0.2.4-beta.N. O produto público é o app Windows; web e botões do site ficam na Fase A. Nova Fase 2B (simplificação do servidor, cenário B) com decisões pendentes D21–D24."
status: in_progress
progress: 30
generated: "2026-11-14"
revised: "2026-11-24"
scaffoldVersion: "2.0.0"
agents:
  - type: "devops-specialist"
    role: "Composes, workflows, borda, site e releases no deploy, provisionamento dos .env, deploy por tag, rollback"
  - type: "security-auditor"
    role: "Saneamento de segredos, SSH/firewall, runner, portões de release, revisão de dados pessoais em log"
  - type: "backend-specialist"
    role: "Webhook por ambiente, prefixo de instância, CORS, token de upload por canal, canal estável no control_plane"
  - type: "frontend-specialist"
    role: "Pipeline do app Windows: assinatura, packId, delta, envio da versão em uso"
  - type: "database-specialist"
    role: "Banco de produção, papel de runtime, backup externo e restauração ensaiada"
  - type: "architect-specialist"
    role: "Critérios de go/no-go e decisões de topologia"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "completed"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "devops-specialist"
    status: "in_progress"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "devops-specialist"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
---

# Conversão para produção (go-live da v2)

> **Revisão 3 (24/11/2026).** A produção **já está no ar**: projeto
> `smart-core-v2-prod`, `v0.2.2`, implantado por tag com aprovação no
> environment `prod` (primeira subida `v0.2.1` em 22/11/2026). `docker/prod` e
> `docker/dev` não existem mais: as duas stacks saem de `docker/stack/`
> (`docker-compose.base.yml` + `<env>.override.yml` + `<env>.vars`) por bundle em
> `/opt/smartcore/<env>/releases/current`. Borda, observabilidade e Evolution só
> mudam por `deploy-infra.yml`. Regras do ambiente: `CLAUDE.md`, seção
> "Ambientes na VPS". **A web admin/tenant não é publicada neste go-live**, mas
> hoje a borda de produção ainda a roteia (Fase 4 aberta).
>
> **Fases PREVC (24/11/2026):** P e R concluídas. O plano está na revisão 3, e a
> revisão de segurança e as decisões D1, D8 e C6 foram tomadas. E está em andamento:
> F0 e F9 feitas, F2 quase toda feita. V e C ficam pendentes até o go/no-go.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_producao-go-live.md](./producao-go-live/plano_completo_producao-go-live.md)
- **Documentação auxiliar**: [info_aux_producao-go-live.md](./producao-go-live/info_aux_producao-go-live.md)
- Pré-requisito já executado: [servidor-reestruturacao-dev-prod.md](./servidor-reestruturacao-dev-prod.md) (stack base + overlays, bundle, deploy por tag, `deploy-infra.yml`, rollback)
- Relacionados: [n12-cutover-producao.md](./n12-cutover-producao.md), [servidor-releases-windows.md](./servidor-releases-windows.md), [windows-releases-v01-beta.md](./windows-releases-v01-beta.md), `infra/RUNBOOK_ROBUSTEZ.md`

## Bloqueadores críticos
| ID | Bloqueador | Estado em 24/11/2026 |
|---|---|---|
| C1 | Nomes de serviço repetidos na rede `smart_core_v2_observability`, comum a dev e produção | **Resolvido**: rede de telemetria por ambiente (`OBS_NET` em `docker/stack/<env>.vars`; prod em `smart_core_v2_telemetria_prod`) |
| C2 | Webhook do Evolution fixo em `http://webhook_ingress:9200` | **Resolvido**: `WEBHOOK_INGRESS_URL` por ambiente; prod em `http://172.17.0.1:9211`, fora da `evolution_net` (`prod.override.yml`) |
| C3 | Portas 8095, 8099 e 9200 iguais no host para os dois ambientes | **Resolvido**: dev 8095/8099/9210, prod 8096/8100/9211 (`<env>.vars`) |
| C4 | Backup só no disco do banco (vale para Evolution e releases) | **Aberto** (sem cópia externa) |
| C5 | Segredos em texto puro em `settings.local.json` (URLs de banco com senha, token do GitHub) | **Aberto** (padrões ainda presentes; arquivo coberto só pelo gitignore global da máquina) |
| C6 | Canal estável do app Windows sem portão: tag `win-vX.Y.Z` atualiza todos os clientes sem aprovação | **Aberto** (`release-windows.yml` sem `environment` nem gate de origem). Portões decididos pelo dono |

## Fases
| # | Fase | Dono | Estado |
|---|---|---|---|
| F0 | Levantamento do servidor (somente leitura) | IA + Dono | **Feita** (inventário de 23–24/11/2026) |
| F1 | Saneamento de segurança | Dono + IA | Parcial: `environment: prod` com revisor e rulesets feitos; C5, `production-windows` e endurecimento de SSH abertos |
| F2 | Isolamento dev×produção e correções do servidor | IA | Quase toda feita (C1–C3, A4, L1, L4–L9, L11); A3 parcial (instâncias novas da dev nascem `dev-<nome>` e o gateway recusa nome repetido, `ac9bc814`/`c4595a6a`; a prod fica sem prefixo); abertos C4, M1, M7 (Evolution), M8–M10, A8 |
| F2B | Simplificação do servidor (cenário B) | IA + Dono | **Nova**, pendente de D21–D24 |
| F3 | Site público por versão, na stack de produção | IA | Aberta (decisão do dono tomada) |
| F4 | Web de produção fechada na borda; admin restrito | IA + Dono | Aberta: `/v2/tenant` e `/v2/admin` roteados; `web-tenant` de pé na prod |
| F5 | Provisionamento (DNS, R2, `prod.env`, `releases.env`) | Dono + IA | Parcial: `prod.env` materializado de `ENV_FILE_B64`; `releases.env` e bucket de backup abertos |
| F6 | Banco de produção, backup externo, restauração ensaiada | IA | Parcial: banco no ar com migrações; backup externo e ensaio abertos |
| F7 | Evolution compartilhado, versão fixa `0.7.3-wa2` (26/11: a `0.7.2-wa1` não dava ack na stanza `<status>` e travava a recepção; 27/11: wa2 corrige o panic do evento Archive) | IA + Dono | Parcial: webhook isolado; prefixo de instância parcial (A3, ver F2); chave nova (A2) aberta. Intermediário de webhooks `provider_edge` pronto na `dev` (`44d41b86`, ADR `doc_dev/arquitetura/adr-intermediario-webhooks-provedores.md`). Não está ativo: falta levar o código à `main`, aprovar o `deploy-infra` e fazer o cutover |
| F8 | Servidor de releases em produção, por versão | IA + Dono | Aberta (`releases-stack` à mão, `:latest`) |
| F9 | Primeiro deploy do servidor por tag | Dono + IA | **Feita** com `v0.2.1`/`v0.2.2`; a versão do go-live público segue D10 |
| F10 | App Windows: certificado, portões do estável, primeira versão | Dono + IA | Aberta (certificado público decidido; fornecedor em D11) |
| F11 | Validação pelo app Windows, rollback ensaiado, go/no-go | Dono + IA | Aberta (ensaio `v0.2.2 → v0.2.1` pendente no plano irmão) |
| F12 | Pós-go-live | IA | Aberta (RUSTSEC-2026-0459 já corrigido) |
| FA | Abertura da web ao público — **adiada**, só com aprovação do dono | — | Adiada |

## Critérios
**Go:** críticos e altos fechados ou aceitos por escrito; restauração e rollback
provados; alerta chegando; ponta a ponta pelo app Windows; instalador assinado
pela empresa (ou aceite escrito do piloto com aviso); 48 h sem reinício inesperado.

**No-go:** mensagem de produção chegando na dev; `/v2/admin` ou `/v2/tenant`
respondendo a rede pública; botões do site ativos; tag estável publicável sem
aprovação; restauração falhando; alerta sem destino.

## Decisões do dono
**Tomadas:** D1 mesma VPS com tetos por ambiente e `oom_score_adj` (dev 900,
observabilidade 300, prod 0) · D8 sessão do Claude Code como root no VPS, por
Remote Control, com permissão total (diverge da recomendação; risco aceito,
ver seção 7 do plano completo) · site junto com o admin na stack de prod ·
web fechada (D18 adiada) · canal estável com portões (C6) · app Windows com
certificado de autoridade pública (A11).

**Pendentes:** D2 domínio · D3 runner · D4 banco limpo ou ETL · D5 backup ·
D6 retenções · D7 alerta · D9 Evolution compartilhado · D10 versões ·
**D11 fornecedor do certificado (prazo externo)** · D12 convite com a web
fechada · D13 `packId` do beta · D14 feed público · D15 loja da Microsoft ·
D16 MCP no dia 1 · D17 acesso ao admin · D19 distribuição do instalador ·
D20 transcrição e quotas · D21 MinIO na dev · D22 Alloy no lugar do promtail ·
D23 socket do Docker em um só ponto · D24 limpeza dos restos do servidor.

## Definition of Done
- [ ] Stack `smart-core-v2-prod` no ar por tag, imagens em versão exata, com o site. (no ar por tag e versão exata desde 22/11; falta o site)
- [x] Nenhuma rede com serviços de aplicação dos dois ambientes.
- [ ] Mensagem de WhatsApp de produção chega só no `webhook_ingress` de produção. (isolado no código; falta prova com instância `prod-`)
- [ ] Servidor simplificado (Fase 2B): soma dos tetos coerente com a RAM da VPS, restos removidos.
- [ ] Web admin restrita ao dono; web tenant fechada; botões do site inativos.
- [ ] Servidor de releases implantado por versão, com token por canal e cópia externa.
- [ ] `win-v1.0.0` assinado pela empresa, publicado com aprovação; atualização automática provada.
- [ ] Backup externo restaurado em ensaio; rollback do servidor e correção para frente do app medidos.
- [ ] Alertas de serviço, host e releases entregues no canal definido.
- [ ] 72 h de tráfego real sem alerta aberto; runbooks reescritos.
