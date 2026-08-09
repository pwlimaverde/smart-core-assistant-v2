---
type: plan
name: "Fase N8.5 — Defeitos de comportamento do pipeline de mensagem"
planSlug: n85-defeitos-pipeline
description: "Correção (não feature) das cinco divergências de comportamento entre a v1 e a v2 no pipeline de mensagem, encontradas na auditoria de código de 2026-08-08/09: (1) mensagem de grupo virando atendimento individual — is_group preenchido e sem leitor; (2) bot respondendo ao fragmento inicial da rajada — lock SET NX EX 2 em vez do buffer de agregação da v1 (TIME_CACHE, 5s); (3) pesquisa de satisfação que expira sem nunca ter sido solicitada — avaliacao/feedback só em SELECT; (4) msg_fallback/msg_sem_info do tenant sem efeito (BOT_TEXT_FALLBACK constante no worker); (5) evento CONNECTION normalizado e publicado sem consumidor — estado da conexão só muda por consulta."
summary: "Entra na frente de N9-N12 por serem defeitos em caminho que já roda em produção, não lacunas de tela. Tudo em servidor: nenhum RPC de borda, nenhuma tela nova. Maior risco em E2 (buffer), que mexe no coração do pipeline."
status: filled
progress: 0
generated: "2026-08-09"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Filtro de grupo no webhook_ingress, buffer de agregação no Redis, ciclo de satisfação, aplicação de msg_fallback/msg_sem_info, consumo dos eventos CONNECTION/CONTACTS/PRESENCE"
  - type: "architect-specialist"
    role: "Aprovar o desenho do buffer (atomicidade, idempotência por message_id, degradação) e a decisão de não existir atendimento de grupo"
  - type: "database-specialist"
    role: "Migration de feedback_solicitado_em e ajuste da query do expirador de feedback"
  - type: "test-writer"
    role: "Regressão do pipeline: rajada, dedupe, grupo, satisfação e eventos de conexão"
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
    agent: "backend-specialist"
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
lastUpdated: "2026-08-09T03:46:01.711Z"
---

# Fase N8.5 — Defeitos de comportamento do pipeline de mensagem

> **Primeira fase do backlog N8.5–N12**, derivado da auditoria de código v1 × v2
> de 2026-08-08/09. É a única do conjunto que **não acrescenta funcionalidade**:
> conserta o que a v2 já faz, e faz diferente da v1, num caminho que roda em
> produção hoje. **Invariante:** nenhuma tela nova, nenhum contrato novo com o
> cliente — tudo se resolve entre `webhook_ingress`, `worker` e `data_postgres`.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n85-defeitos-pipeline.md](./n85-defeitos-pipeline/plano_completo_n85-defeitos-pipeline.md)
- **Documentação auxiliar**: [info_aux_n85-defeitos-pipeline.md](./n85-defeitos-pipeline/info_aux_n85-defeitos-pipeline.md)

## Origem
- [26-levantamento-paridade-v1-v2.md](../../doc_dev/planejamento/26-levantamento-paridade-v1-v2.md) §3.5b
- [02-fases-desenvolvimento.md](../../doc_dev/planejamento/02-fases-desenvolvimento.md) — cronograma N8.5–N12

## Etapas

| # | Entregável | Área | Risco |
|---|---|---|---|
| E1 | Descartar mensagem de grupo na ingestão (campo `is_group` + fallback `@g.us`) | `webhook_ingress` | baixo |
| E2 | **Buffer de agregação** por contato substituindo o lock "primeiro ganha" | `worker` + Redis | **alto** |
| E3 | Ciclo de satisfação: solicitar ao encerrar, interpretar a resposta, corrigir o expirador | `worker` + `data_postgres` + migration | médio |
| E4 | `msg_fallback`/`msg_sem_info` do tenant passam a valer | `worker` + `ia_engine` | baixo |
| E5 | Consumir `CONNECTION` (e avaliar `CONTACTS`/`PRESENCE`) | `worker` | baixo |

**Ordem recomendada:** E1 → E4 → E5 → E2 → E3.

## Observabilidade & Auditoria (resumo)
Eventos de auditoria novos: `atendimento.pesquisa_solicitada`,
`atendimento.avaliado`. Reaproveitado: `whatsapp_instance.state_updated` com
campo `origem`. **Sem evento (intencional)** em E1, E2 e E4 — filtro de ingestão,
agregação e escolha de texto não mudam estado sensível.

**Alerta de segurança novo:** a E2 faz o Redis de cache guardar **conteúdo de
mensagem** (PII transitória) durante a janela de agregação. TTL curto, chave por
tenant, nunca logar o texto. Registrar em `08_diretrizes_seguranca.md`.

## Definition of Done
- [ ] Grupo não gera atendimento.
- [ ] Três mensagens seguidas geram **uma** resposta ao conjunto.
- [ ] Encerrar envia a pesquisa; a nota do cliente fica gravada; não solicitado não expira.
- [ ] `msg_fallback`/`msg_sem_info` do tenant aparecem na conversa.
- [ ] Queda de conexão reflete no painel sem abrir a tela.
- [ ] `cargo fmt`/`clippy -D warnings`/`sqlx prepare --check` verdes; suíte via `.\infra\test-local.ps1`.

## Execution History

> Last updated: 2026-08-09T03:46:01.711Z | Progress: 0%
