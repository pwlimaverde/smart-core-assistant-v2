---
type: plan
name: "Fase N8 — Migração de dados v1→v2 + cutover de produção (fim do port)"
planSlug: n8-migracao-e-cutover
description: "Terceira e última fase do port final (N6–N8): ETL idempotente v1→v2 (tenants/planos/assinaturas, usuários+RBAC aninhado→escopos planos, contatos/atendimentos/mensagens, documentos+embeddings pgvector 1536, credenciais Fernet→AES-256-GCM via CipherManager, instâncias Evolution), habilitação da produção web completa (/v2/admin + /v2/tenant nos blocos Caddy hoje comentados, role não-superuser em prod, CORS/lifecycle R2 de produção), rollout do enforce com dados da janela do N7 e cutover com rollback ensaiado, desligando o Django legado."
summary: "Marco que encerra o port: produção 100% na v2, dados migrados e conciliados, enforce ativo com limites reais, legado desligado. Majoritariamente ops+ETL; pré-condição dura: N7 concluída (não se faz cutover às cegas)."
status: filled
progress: 40
generated: "2026-07-18"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "ETL v1→v2 (recodificação RBAC e credenciais Fernet→AES via CipherManager), conciliação, verificação de instâncias"
  - type: "database-specialist"
    role: "De-para de entidades, preservação de ids/mapa de correspondência, migração de embeddings pgvector"
  - type: "devops-specialist"
    role: "Produção web (Caddy prod, role smartcore_app_rt, CORS/lifecycle R2), janela de cutover, DNS/rotas, rollback"
  - type: "architect-specialist"
    role: "Aprovar de-para, plano de janela/rollback e go/no-go do cutover"
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
  - id: "phase-2"
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
lastUpdated: "2026-07-23T19:53:59.925Z"
---

# Fase N8 — Migração de dados v1→v2 + cutover de produção (fim do port)

> Terceira e última fase do cronograma de **port final** (N6–N8). Migra os dados do
> legado Django (`old/paulo-ecoprint-server`, `old/smart-core-assistant-painel`)
> para a v2, habilita a produção web completa e **desliga o legado** — encerra o
> port. **Pré-condição dura:** N7 concluída (enforce validado log-only, operação
> observada com tráfego real). **Não se faz cutover às cegas.**

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n8-migracao-e-cutover.md](./n8-migracao-e-cutover/plano_completo_n8-migracao-e-cutover.md)
- **Documentação auxiliar** (destinos no código + libs): [info_aux_n8-migracao-e-cutover.md](./n8-migracao-e-cutover/info_aux_n8-migracao-e-cutover.md)
- **Origem:** `doc_dev/planejamento/23-fase-N8-migracao-e-cutover.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N8.1** | ETL v1→v2 (`infra/migracao-v1/`, idempotente, dry-run, conciliação por entidade): tenants/planos, usuários+RBAC, contatos/atendimentos/mensagens, documentos+embeddings, credenciais Fernet→AES, instâncias Evolution | Apêndice B mapeia v1→v2; recodificação (não é cópia 1:1) |
| **N8.2** | Produção web completa: habilitar `/v2/admin` e `/v2/tenant` no domínio prod (blocos Caddy comentados), role não-superuser em prod, CORS/lifecycle R2 de produção | apps prontos em dev (N5.3); é habilitação, não construção |
| **N8.3** | Rollout do enforce: analisar janela log-only do N7 → limites reais por plano → `SMARTCORE_QUOTA_ENFORCE=true` + rate limiting ativo | flag existe desde a N4 (log-only em todo lugar) |
| **N8.4** | Cutover: freeze v1 → ETL delta → conciliação → DNS/rotas p/ v2; rollback ensaiado; desligar legado e arquivar `old/` | domínio prod ainda serve o Django (`172.18.0.5:8000`) |

## Sequenciamento
**N8.1 (carga antecipada) → N8.2 → N8.3 → N8.4 (delta + virada).** Correções da
reestruturação (Fernet→`CipherManager::encrypt`; RBAC no shape de `derivar_escopos`;
Caddy é habilitação do bloco comentado; enforce informado pela janela do N7) no
[plano completo](./n8-migracao-e-cutover/plano_completo_n8-migracao-e-cutover.md).

## Fases (PREVC)
- **P:** inventário de dados da v1 real (dump) + decisões pendentes (path `/v2/tenant/`, portas host, janela de convivência com o Django).
- **R:** aprovar de-para de entidades + plano de janela/rollback + critérios go/no-go.
- **E:** ETL + habilitação prod + rollout enforce — cada etapa com Observabilidade & Auditoria do plano completo.
- **V:** dry-run conciliado + ensaio de rollback + smoke E2E na prod v2 + `.\infra\test-local.ps1`/`.\infra\test-flutter.ps1`.
- **C:** cutover executado; legado desligado; changelog **encerra o port**; gate `prevc-final-review`; arquivamento.

## Execution History

> Last updated: 2026-07-23T19:53:59.925Z | Progress: 40%

### phase-r [DONE]
- Started: 2026-07-23T18:24:10.068Z
- Completed: 2026-07-23T18:24:10.068Z

### phase-v [DONE]
- Started: 2026-07-23T19:53:59.925Z
- Completed: 2026-07-23T19:53:59.925Z
