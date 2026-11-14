---
type: plan
name: "Conversão para produção (go-live da v2)"
planSlug: producao-go-live
description: "Coloca em produção a stack de servidor da v2 (ao lado da dev, com o Evolution Go compartilhado), o aplicativo Windows no canal estável com instalador assinado e auto-update, o servidor de releases e o site público, todos por versão e pelo deploy. A versão web (admin e tenant) NÃO é publicada neste go-live: fica fechada na borda até decisão do dono. Fecha os bloqueadores de isolamento entre ambientes, o canal estável sem portão, o backup só local e os segredos expostos."
summary: "Seis bloqueadores críticos (C1–C6). Fase 0 é levantamento do servidor, somente leitura. O produto que vai a público é o app Windows; web e botões do site ficam na Fase A, adiada e condicionada a aprovação. Não substitui o N12 nem os planos de releases Windows: amarra-os ao go-live. Decisões D1–D20; D11 (certificado) tem prazo externo."
status: filled
progress: 0
generated: "2026-11-14"
revised: "2026-11-14"
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
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "devops-specialist"
    status: "pending"
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

> A produção está desenhada no repositório e nunca subiu
> (`docker/edge/Caddyfile:209`). **Não subir `docker/prod` como está hoje.**
> **A web admin/tenant não é publicada neste go-live.**
> O servidor não foi acessado na elaboração: a Fase 0 confirma o estado real.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_producao-go-live.md](./producao-go-live/plano_completo_producao-go-live.md)
- **Documentação auxiliar**: [info_aux_producao-go-live.md](./producao-go-live/info_aux_producao-go-live.md)
- Relacionados: [n12-cutover-producao.md](./n12-cutover-producao.md), [servidor-releases-windows.md](./servidor-releases-windows.md), [windows-releases-v01-beta.md](./windows-releases-v01-beta.md), `infra/RUNBOOK_ROBUSTEZ.md`

## Bloqueadores críticos
| ID | Bloqueador |
|---|---|
| C1 | Nomes de serviço repetidos na rede `smart_core_v2_observability`, comum a dev e produção |
| C2 | Webhook do Evolution fixo em `http://webhook_ingress:9200` (`data_whatsapp/src/main.rs:362-365`) |
| C3 | Portas 8095, 8099 e 9200 iguais no host para os dois ambientes |
| C4 | Backup só no disco do banco (vale para Evolution e releases) |
| C5 | Segredos em texto puro em `settings.local.json` (URLs de banco com senha, token do GitHub) |
| C6 | Canal estável do app Windows sem portão: tag `win-vX.Y.Z` atualiza todos os clientes sem aprovação |

## Fases
| # | Fase | Dono |
|---|---|---|
| F0 | Levantamento do servidor (somente leitura) | IA + Dono |
| F1 | Saneamento de segurança | Dono + IA |
| F2 | Isolamento dev×produção e correções do servidor | IA |
| F3 | Site público por versão, na stack de produção | IA |
| F4 | Web de produção fechada na borda; admin restrito | IA + Dono |
| F5 | Provisionamento (DNS, R2, `prod.env`, `releases.env`) | Dono + IA |
| F6 | Banco de produção, backup externo, restauração ensaiada | IA |
| F7 | Evolution compartilhado, sem trocar a versão `0.7.2-wa1` | IA + Dono |
| F8 | Servidor de releases em produção, por versão | IA + Dono |
| F9 | Primeiro deploy do servidor por tag | Dono + IA |
| F10 | App Windows: certificado, portões do estável, primeira versão | Dono + IA |
| F11 | Validação pelo app Windows, rollback ensaiado, go/no-go | Dono + IA |
| F12 | Pós-go-live | IA |
| FA | Abertura da web ao público — **adiada**, só com aprovação do dono | — |

## Critérios
**Go:** críticos e altos fechados ou aceitos por escrito; restauração e rollback
provados; alerta chegando; ponta a ponta pelo app Windows; instalador assinado
pela empresa (ou aceite escrito do piloto com aviso); 48 h sem reinício inesperado.

**No-go:** mensagem de produção chegando na dev; `/v2/admin` ou `/v2/tenant`
respondendo a rede pública; botões do site ativos; tag estável publicável sem
aprovação; restauração falhando; alerta sem destino.

## Decisões do dono
D1 VPS · D2 domínio · D3 runner · D4 banco limpo ou ETL · D5 backup ·
D6 retenções · D7 alerta · D8 sessão root · D9 Evolution compartilhado ·
D10 versões e política de release · **D11 certificado de assinatura (prazo
externo)** · D12 convite com a web fechada · D13 `packId` do beta · D14 feed
público · D15 loja da Microsoft · D16 MCP no dia 1 · D17 acesso ao admin ·
**D18 abertura da web (adiada)** · D19 distribuição do instalador ·
D20 transcrição e quotas.

## Definition of Done
- [ ] Stack `smart-core-v2-prod` no ar por tag, imagens em versão exata, com o site.
- [ ] Nenhuma rede com serviços de aplicação dos dois ambientes.
- [ ] Mensagem de WhatsApp de produção chega só no `webhook_ingress` de produção.
- [ ] Web admin restrita ao dono; web tenant fechada; botões do site inativos.
- [ ] Servidor de releases implantado por versão, com token por canal e cópia externa.
- [ ] `win-v1.0.0` assinado pela empresa, publicado com aprovação; atualização automática provada.
- [ ] Backup externo restaurado em ensaio; rollback do servidor e correção para frente do app medidos.
- [ ] Alertas de serviço, host e releases entregues no canal definido.
- [ ] 72 h de tráfego real sem alerta aberto; runbooks reescritos.
