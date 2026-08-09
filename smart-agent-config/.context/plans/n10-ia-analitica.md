---
type: plan
name: "Fase N10 — IA analítica no fluxo"
planSlug: n10-ia-analitica
description: "O ia_engine já sabe analisar e ninguém pede: IaEngineService.Analyse está implementado, testado e com prompts configuráveis por tenant (migration 0026), e grep '.analyse(' em server/apps não retorna nada. Como consequência, oraculo_mensagem.intent_detectado e entidades_extraidas estão vazias desde a migration 0006, tenants_tenantconfig.entity_types não tem efeito, e quatro comportamentos da v1 não existem: assunto automático, etiquetagem por intenção, enriquecimento do contato por entidades e o relatório de intenções. Completa também o ciclo de treinamento: upload de arquivo (7 formatos, como a v1) e feedback do teste com resposta correta."
summary: "Fase de backend + ia_engine, sem tela nova de peso. Paralelizável com N11. O Analyse roda em paralelo ao Responder (são independentes) para não somar latência, com kill-switch por tenant."
status: filled
progress: 0
generated: "2026-08-09"
scaffoldVersion: "2.0.0"
agents:
  - type: "ai-specialist"
    role: "Ligar Analyse ao worker, RPC de extração de texto no ia_engine (loaders LangChain), feedback do teste"
  - type: "backend-specialist"
    role: "AnexarAnaliseMensagem, assunto/etiqueta/contato derivados, job de extração no scheduler"
  - type: "database-specialist"
    role: "Migration de origem em atu_etiqueta_atendimento e colunas do ciclo de treinamento"
  - type: "security-auditor"
    role: "Valores de entidade são PII: garantir que não entrem em log, span, métrica nem auditoria"
  - type: "test-writer"
    role: "Testes do fluxo com Analyse ligado/desligado e da extração por formato"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
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
---

# Fase N10 — IA analítica no fluxo

> **Depende de N8.5** (o texto analisado é o agregado do buffer).
> **Paralelizável com N11** — esta é worker/`ia_engine`; aquela é infra e
> cadastros. **Invariante:** falha da análise nunca afeta a resposta ao cliente
> (degradação graciosa pelo `ia_client::resilient`).

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n10-ia-analitica.md](./n10-ia-analitica/plano_completo_n10-ia-analitica.md)
- **Documentação auxiliar**: [info_aux_n10-ia-analitica.md](./n10-ia-analitica/info_aux_n10-ia-analitica.md)

## Origem
- [26-levantamento-paridade-v1-v2.md](../../doc_dev/planejamento/26-levantamento-paridade-v1-v2.md) §3.9
- [27-mapa-telas-rotas-v2.md](../../doc_dev/planejamento/27-mapa-telas-rotas-v2.md) §D.7

## Etapas

| # | Entregável | Área |
|---|---|---|
| E1 | Ligar `Analyse` ao pipeline (paralelo ao `Responder`) + `AnexarAnaliseMensagem` | worker |
| E2 | Assunto automático do atendimento | worker + data_postgres |
| E3 | Etiquetagem por intenção (com coluna `origem` e regra "removida por humano não volta") | worker + migration |
| E4 | Enriquecimento do contato por entidades (**fill-if-empty**, validado, com confiança mínima) | worker |
| E5 | Treinamento por **upload de arquivo** (7 formatos) — presign + job de extração + RPC no `ia_engine` | ia_engine + scheduler |
| E6 | Feedback do teste com **resposta correta** (+ teste com mídia, opcional) | data_postgres + cliente |

**Ordem:** E1 → E2 → E3 → E4 (risco crescente), com E6 → E5 em paralelo.

## Observabilidade & Auditoria (resumo)
Auditar: `etiqueta.aplicada_por_ia`, **`contato.enriquecido_por_ia`** (lista de
campos, **nunca valores**), `treinamento.arquivo_enviado`, `.extracao_falhou`,
`treinamento.feedback_registrado`.
**Sem evento (intencional):** anotar análise na mensagem e definir assunto —
enriquecimento derivado, coberto por `mensagem.persistida`.
**Nunca em log:** valor de entidade (nome, e-mail, documento) e texto extraído
de arquivo — só tipos e contagens.

## Definition of Done
- [ ] `intent_detectado`/`entidades_extraidas` deixam de ser sempre vazios.
- [ ] Conversa nova ganha assunto e etiqueta sem intervenção.
- [ ] Contato completado sem sobrescrever o que humano preencheu.
- [ ] PDF vira material treinado e responde na aba de teste.
- [ ] Feedback com resposta correta gravado.
- [ ] `cargo` + `pytest` (`ruff`/`mypy`) verdes; cobertura do `ia_engine` mantida.
