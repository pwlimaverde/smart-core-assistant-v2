---
type: plan
name: "Pendências pós-paridade"
description: "Seis fases (P13–P18) que fecham o que sobrou depois da paridade v1: foto do contato, etiquetas e enriquecimento pela IA, acabamentos do quadro, revisão das avaliações do teste e o fechamento do fallback de escopos."
planSlug: pendencias-pos-paridade
generated: "2026-09-19"
summary: "Fechar as pendências conferidas no código em 19/09: N11 E6 (foto do contato, com o defeito do envelope da evolution-go), N10 E3 e E4 (etiquetas e contato pela análise), os três 'fica de fora' do quadro (B2, B4, B5), a revisão das avaliações do teste (B9) e o D4 passos 2 e 3, atrás de medição de produção."
agents:
  - type: "backend-specialist"
    role: "Contrato, migrations, data_postgres, runtime_api e worker"
  - type: "frontend-specialist"
    role: "App Windows (Flutter) — quadro, ficha, treinamento e aviso nativo"
  - type: "test-writer"
    role: "Testes de unidade, integração e tela por fase (piso de cobertura 78%)"
  - type: "security-auditor"
    role: "PII em log e auditoria (P15), RBAC das rotas novas e a migração de escopos (P18)"
docs:
  - "architecture.md"
  - "data-flow.md"
  - "security.md"
  - "testing-strategy.md"
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
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
    steps:
      - order: 1
        description: "P13 — foto e nome do contato: corrigir o envelope do avatar da evolution-go, busca sob demanda com freio de 7 dias, avatar no cartão, conversa e ficha"
        assignee: "backend-specialist"
      - order: 2
        description: "P14 — etiquetagem por intenção: coluna origem, bloqueio do que humano removeu, aplicação na transação da análise"
        assignee: "backend-specialist"
      - order: 3
        description: "P15 — enriquecimento do contato pelas entidades: só campo vazio, validado, com confiança mínima e auditoria sem valor"
        assignee: "backend-specialist"
      - order: 4
        description: "P16 — acabamentos do quadro: esconder escrita de quem só lê, marca 'revisar' e aviso nativo do Windows"
        assignee: "frontend-specialist"
      - order: 5
        description: "P17 — revisão das avaliações do teste de resposta e 'virar treinamento'"
        assignee: "frontend-specialist"
      - order: 6
        description: "P18 — fechar o fallback de escopos (D4 passos 2 e 3), com gate de medição em produção"
        assignee: "security-auditor"
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
status: filled
progress: 0
scaffoldVersion: "2.0.0"
lastUpdated: "2026-09-19T21:57:22.115Z"
---

# Pendências pós-paridade

> Plano canônico (leve). A verdade técnica está nos artefatos:
> - **Plano completo:** [`pendencias-pos-paridade/plano_completo_pendencias-pos-paridade.md`](./pendencias-pos-paridade/plano_completo_pendencias-pos-paridade.md)
> - **Docs de libs e do provedor:** [`pendencias-pos-paridade/info_aux_pendencias-pos-paridade.md`](./pendencias-pos-paridade/info_aux_pendencias-pos-paridade.md)
> - **Cronograma e andamento:** `doc_dev/planejamento/38-cronograma-pendencias-pos-paridade.md`

## Objetivo

Fechar o que a varredura de 19/09 encontrou pendente depois da paridade v1
(doc 37), conferido no código e não nos marcadores dos planos antigos.

## Fases de execução (dentro da fase E do PREVC)

| # | Fase | Origem | Depende de |
|---|---|---|---|
| P13 | Foto e nome do contato | N11 E6 | — |
| P14 | Etiquetagem por intenção | N10 E3 | — |
| P15 | Enriquecimento do contato | N10 E4 | P14 (mesmo handler) |
| P16 | Acabamentos do quadro | doc 36 B2, B4, B5 | — |
| P17 | Revisão das avaliações do teste | doc 36 B9 | — |
| P18 | Fechar o fallback de escopos | regras D4 | **gate:** medição de produção |

**Fora:** N12 (cutover, operação) e o teste com mídia (N10 E6.1, opcional).

## Regras

Uma fase por vez, ponta a ponta, com CI verde antes da próxima; testes só na
CI; consulta nova sem macro; tela nova com teste de widget; commits sem
auto-referência; comentários em pt-BR.

## Definition of Done

Cada fase com o DoD próprio no plano completo e a linha de andamento no doc 38
(commit + run de CI).

## Execution History

> Last updated: 2026-09-19T21:57:22.115Z | Progress: 0%
