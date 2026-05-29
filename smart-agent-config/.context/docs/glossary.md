---
type: doc
name: glossary
description: Project terminology, type definitions, domain entities, and business rules
category: glossary
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Glossary & Domain Concepts

Terminologia extraída da v1 em produção e do planejamento da v2. Termos em português refletem o domínio de negócio; identificadores no código permanecem em inglês.

## Type Definitions

- `TenantId` — UUID que identifica um tenant em todas as tabelas de domínio
- `WaMessageId` — identificador de mensagem do WhatsApp (para idempotência)
- `TenantEnvelope<T>` — wrapper de evento no event bus; sempre carrega `tenant_id`
- `DataSource` — trait/interface Flutter que abstrai `LocalEngineFFI` vs `RemoteOnly`
- `MediaPointer` — JSON com `storage_key`, `mimetype`, `size`, `hash`

## Enumerations

- `TicketStatus` — `FILA | EM_ATENDIMENTO | PENDENCIA | RESOLVIDO | CANCELADO | ARQUIVADO`
- `MessageSender` — `CONTACT | BOT | AGENT`
- `MessageSendStatus` — `PENDING | SENT | DELIVERED | READ`

## Core Terms

| Termo | Definição |
|-------|-----------|
| **Tenant** | Cliente da plataforma (empresa). Dados isolados por `tenant_id` + RLS. |
| **Ticket** | Unidade operacional: status, SLA, etapa, dono, `bot_pode_atender`. |
| **Conversation** | Fluxo contínuo de comunicação com um Contato (thread de mensagens). |
| **Atendimento** | Termo da v1 que unifica Ticket + Conversation. Na v2 serão separados. |
| **Contato** | Cliente/número WhatsApp com perfil, metadados e histórico. |
| **Messaging Gateway** | Binário Rust que recebe webhooks do Evolution, resolve `tenant_id` e publica eventos internos. |
| **Worker / Support Core** | Binário Rust que executa o domínio (conversa, ticket, kanban, IA, outbound). |
| **Runtime API** | Binário Rust com gRPC/HTTP + WebSocket que serve o app Flutter. |
| **Control Plane** | Binário Rust para gestão de tenants, planos, credenciais, instâncias Evolution. |
| **Evolution Go** | Gateway de WhatsApp multi-instância. Um cluster gerencia N instâncias. |
| **EvolutionInstance** | Instância WhatsApp vinculada a um tenant. Controla `resposta_bot`. |
| **RLS** | Row-Level Security do PostgreSQL. Segunda barreira de isolamento multi-tenant. |
| **FFI** | Foreign Function Interface: `flutter_rust_bridge` embarca `local_engine` como lib nativa no Windows. |
| **Local Engine** | Crate Rust dual-target: cache local de conversas/mídia (SQLite) + fila offline. |
| **RAG** | Retrieval-Augmented Generation: busca de documentos similares via pgvector. |
| **Debounce por contato** | Acumular mensagens em rajada antes de processá-las como um lote. |
| **EtapaFluxo** | Coluna/etapa do Kanban dentro de um fluxo de um departamento. |
| **MovimentoFluxo** | Registro de auditoria de cada transição de etapa (com duração para SLA). |
| **resumo_midia** | Texto curto e amigável de uma mídia exibido no chat. |
| **analise_midia** | Transcrição/descrição completa de mídia usada internamente pela IA. |
| **bot_pode_atender** | Flag do Ticket. Bloqueado permanentemente por qualquer mensagem de atendente humano. |
| **Janela de reabertura** | 10 min após `RESOLVIDO`/`ARQUIVADO`: nova mensagem vira feedback; fora, abre novo atendimento. |

## Acronyms & Abbreviations

| Sigla | Expansão |
|-------|----------|
| RLS | Row-Level Security (PostgreSQL) |
| FFI | Foreign Function Interface |
| RAG | Retrieval-Augmented Generation |
| PREVC | Plan → Review → Execute → Verify → Complete |
| SLA | Service Level Agreement |

## Domain Rules & Invariants

1. **Um atendimento ativo por contato**: reaproveita ativo (`FILA`/`EM_ATENDIMENTO`/`PENDENCIA`).
2. **Bot bloqueado permanentemente** por qualquer mensagem de atendente humano.
3. **Webhook nunca executa regra pesada** — apenas autentica, resolve tenant, persiste bruto, publica evento.
4. **Idempotência**: `wa_message_id` duplicado não é reprocessado.
5. **`tenant_id` obrigatório em todas as tabelas**; RLS como segunda barreira.
6. **Mídia = mensagem própria; textos rápidos = concatenados** em uma única `Mensagem`.

## Related Resources

- [Project Overview](project-overview.md)
- [Planejamento Inicial §18](../doc_dev/planejamento/00-planejamento-inicial.md)
