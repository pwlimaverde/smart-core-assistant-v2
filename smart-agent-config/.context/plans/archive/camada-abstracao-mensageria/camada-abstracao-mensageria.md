---
status: active
generated: 2026-06-20
agents:
  - type: "backend-specialist"
    role: "Implementar crates infrastructure_messaging, infrastructure_evolution, apps data_whatsapp e webhook_ingress"
  - type: "database-specialist"
    role: "Reescrever migração 0008_whatsapp_sync.sql e módulo whatsapp no infrastructure_postgres"
  - type: "security-auditor"
    role: "Revisar sanitização de SecretString, RLS e eventos de auditoria"
  - type: "test-writer"
    role: "Escrever testes unitários e de integração para os novos componentes"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "backend-specialist"
    status: "pending"
---

# Camada de Abstração de Mensageria (WhatsApp)

> Introduzir trait `MessagingProvider` + `infrastructure_evolution` + `webhook_ingress` + `data_whatsapp`
> para abstrair provedores de WhatsApp de forma transparente para as regras de negócio dos tenants,
> com normalização de webhooks em Redis Streams e reescrita do schema de banco de dados.

## Artefatos detalhados
- **Plano completo**: [plano_completo_camada-abstracao-mensageria.md](./camada-abstracao-mensageria/plano_completo_camada-abstracao-mensageria.md)
- **Documentação auxiliar**: [info_aux_camada-abstracao-mensageria.md](./camada-abstracao-mensageria/info_aux_camada-abstracao-mensageria.md)
- **Origem**: `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`
- **Docs Evolution API**: `doc_dev/apis/evolution/`
- **Doc axum atualizado**: `doc_dev/libs/rust/axum.md` (v0.7.5 / v0.8)

## Escopo (7 componentes)
| Componente | Tipo | Descrição |
|---|---|---|
| `server/crates/infrastructure_messaging` | Nova crate | Trait `MessagingProvider` + tipos normalizados |
| `server/crates/infrastructure_evolution` | Nova crate | Implementação REST para Evolution API |
| `0008_whatsapp_sync.sql` | Reescrita | Schema genérico `whatsapp_*` |
| `infrastructure_postgres/integracoes/whatsapp.rs` | Substituição | Repositório genérico (substitui `evolution.rs`) |
| `server/apps/webhook_ingress` | Novo app | Normaliza webhooks → `events:stream` (axum 0.8) |
| `server/apps/data_whatsapp` | Novo app | Orquestrador RPC (extraído de `control_plane`) |
| `control_plane` + `data_postgres` | Modificação | Endpoint admin + remoção de `evolution.rs` legado |

## Decisões arquiteturais críticas
- `axum 0.8` declarado **localmente** em `webhook_ingress` (não no workspace) — `runtime_api` fica em 0.7.5
- `PUT /webhook/set/{name}` com `webhookByEvents: false` (todos eventos na mesma URL)
- Streams reais: `events:stream` (STREAM_EVENTOS) e `security:stream` (STREAM_SEGURANCA)
- `data_whatsapp` é **app novo** (não renomeação — `data_evolution` não existe)
- `UNIQUE (tenant_id, name)` apenas — sem `UNIQUE (name)` global (quebrava multi-tenancy)

## Fases

### P — Planning (concluída)
Output: plano-base analisado, 7 componentes identificados, contrato `MessagingProvider` definido.

### R — Review (concluída)
Output: compatibilidade de versões validada, sanidade de segurança aprovada, contrato de barramento confirmado.
Gates R1/R2/R3 concluídos no `info_aux` e `plano_completo`.

### E — Execution (próxima)
Implementar os 7 componentes na ordem: E1→E2→E3→E4→E5→E6→E7.
Ver [plano_completo](./camada-abstracao-mensageria/plano_completo_camada-abstracao-mensageria.md) para detalhe técnico máximo.

### V — Validation
Executar `.\infra\test-local.ps1`; validação manual de integração; checagem de auditoria.

### C — Confirmation
Gate de `prevc-final-review`; remoção do código legado; commit gitflow.
