---
type: plan
name: "ia_engine_jev — decisões da IA pelo Jev, geração pela LLM"
planSlug: ia-engine-jev
description: "Serviço Python ia_engine_jev, derivado do ia_engine, com o mesmo contrato IaEngineService (plugar = trocar o endpoint). Toda decisão sobre a mensagem — intenção, entidades, sentimento, transferência para atendente, relevância dos trechos do RAG e conferência da resposta — passa ao Jev (TypeSafe System One), com a regra final em código; a LLM só escreve a resposta e extrai valor livre. A transferência passa a ser governada por um cadastro de regras do tenant, visível nas configurações, auditado e operável pelo MCP. A chave TypeSafe é da plataforma e fica na configuração geral (CoreSettings TYPESAFE_API_KEY, cifrada), junto com as demais chaves."
summary: "J0.1 põe a chave e o modelo na configuração geral; J0 mede o Jev em português no VPS e decide go/no-go; J1 esqueleto do serviço com análise e sentimento; J2 contrato aditivo e modo sombra; J3 transferência pelo Jev com cadastro de regras, tela, MCP e auditoria; J4 entidades por candidatos; J5 troca e remoção do motor antigo. Nenhum teste roda na máquina local: CI e VPS."
status: filled
progress: 20
generated: "2026-09-28"
scaffoldVersion: "2.0.0"
agents:
  - type: "ai-specialist"
    role: "ia_engine_jev: cliente TypeSafe, perguntas e decisões puras, features Analyse/Sentimento/Responder, conjunto de avaliação da J0"
  - type: "backend-specialist"
    role: "RuntimeConfig/config_publisher (chave e modelo), worker (sombra, intenções completas, motivo), CRUD de regras no data_postgres, gRPC-Web e rbac"
  - type: "database-specialist"
    role: "Migrações 0046–0049: CoreSettings do Jev, motor por tenant, oraculo_decisao_ia com retenção, oraculo_regra_transferencia com RLS"
  - type: "frontend-specialist"
    role: "Tela Transferência para atendente no tenant_module e troca de motor no admin_module"
  - type: "security-auditor"
    role: "Chave fora de log/env/span, conteúdo de conversa fora de auditoria e métricas, DPA com a TypeSafe"
  - type: "devops-specialist"
    role: "Job de CI e imagem do ia_engine_jev, serviço no compose, execução da J0 no VPS, alertas no Grafana"
  - type: "test-writer"
    role: "Testes sobre respostas gravadas do Jev, paridade das ferramentas MCP, testes de widget da tela"
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
    agent: "ai-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
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
lastUpdated: "2026-09-28T21:13:10.372Z"
---

# ia_engine_jev — decisões da IA pelo Jev, geração pela LLM

> **Branch:** `feature/ia-engine-jev` (a partir da `dev`).
> **Chave:** `TYPESAFE_API_KEY` nas CoreSettings (configuração geral, cifrada), editada na
> tela de configurações globais do painel do superusuário — sem chave por tenant.
> **Restrição:** nenhum teste na máquina local; testes na CI, avaliação no VPS de dev.
> **Plano aprovado:** decisões de 2026-09-28 (38 §11); planejamento e revisão concluídos.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_ia-engine-jev.md](./ia-engine-jev/plano_completo_ia-engine-jev.md)
- **Documentação auxiliar**: [info_aux_ia-engine-jev.md](./ia-engine-jev/info_aux_ia-engine-jev.md)
- **Referência da lib**: [typesafe_sdk.md](../../doc_dev/libs/python/typesafe_sdk.md)

## Origem
- [38-plano-ia-engine-jev.md](../../doc_dev/planejamento/38-plano-ia-engine-jev.md) — plano-base, comparativo e diagramas (histórico)
- [37-estudo-ia-engine-jev.md](../../doc_dev/planejamento/37-estudo-ia-engine-jev.md) — estudo e fontes

## Fases de execução (dentro de E)

| Fase | Entrega | Aceite |
|---|---|---|
| **J0.1** | CoreSettings `TYPESAFE_API_KEY` (cifrada), `JEV_MODELO`, `MOTOR_ANALISE`; `RuntimeConfig` + publisher + `config/models.py` | chave gravada na tela chega à config publicada |
| **J0** | conjunto rotulado, script de métricas, 3 variantes de idioma, rodada no VPS | relatório e go/no-go |
| **J1** | `ia_engine_jev` com contrato completo, `Analyse` e `Sentimento` pelo Jev, telemetria | CI verde; imagem publicada |
| **J2** | proto aditivo, sombra, motor por tenant, `oraculo_decisao_ia` | sombra num tenant; Jev ≥ atual na intenção |
| **J3** | transferência pelo Jev, cadastro e tela de regras, MCP, auditoria, trechos separados | 6 perguntas certas; toda transferência com motivo |
| **J4** | entidades por candidatos; LLM só em `livre` | nenhum valor fora do texto |
| **J5** | troca por tenant e global; alertas; remoção do motor antigo | uma semana sem regressão |

## Correções da reestruturação (resumo)
C1 chave como CoreSetting cifrada; C2 sem override por tenant; C3 chave antecipada para a
J0.1; C4 `JEV_MODELO`/`MOTOR_ANALISE` como CoreSettings; C5 container sem a variável de
ambiente do SDK; C6 dependências do SDK (`httpx2`, `tenacity`, pydantic ≥ 2.12); C7 422 sem
retry e `body` fora do log; C8 J0 no VPS; C9 migrações a partir de 0046; C10 observabilidade
por fase. Detalhe no plano completo §3.

## Execution History

> Last updated: 2026-09-28T21:13:10.372Z | Progress: 20%

### phase-e [DONE]
- Started: 2026-09-28T21:13:07.134Z
- Completed: 2026-09-28T21:13:07.134Z
