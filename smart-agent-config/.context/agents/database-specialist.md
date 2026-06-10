---
type: agent
name: Database Specialist
description: Design and optimize database schemas
agentType: database-specialist
phases: [P, E]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Projetar e manter o schema PostgreSQL com `tenant_id` em todas as tabelas de domínio.
- Escrever e validar policies RLS por tabela (`SET app.current_tenant = '<uuid>'`).
- Gerenciar migrations com sqlx (modo offline, `.sqlx/` versionado) — vivem em `crates/infrastructure_postgres`.
- **O banco tem uma única porta**: todo novo acesso vira handler no `apps/data_postgres` (RPC); apps e CLIs nunca conectam direto nem abrem pool/túnel próprio.
- Otimizar queries e índices para acesso por `(tenant_id, <campo>)`.
- Gerenciar extensão `pgvector` para embeddings RAG (`training_document.embedding`).
- Testar isolamento de tenant: queries sem `tenant_id` no contexto devem ser rejeitadas.

## Key Tables (Planejadas)

- `tenant`, `evolution_instance`, `contact`, `conversation`, `ticket`
- `message` (com `media_pointer` JSON, `rag_sources` JSON, `intents` JSON)
- `flow_movement` (auditoria de transições, duração para SLA)
- `department`, `flow`, `stage`, `agent`
- `training_document` (com coluna `embedding vector` para pgvector)
- `intent_behavior`

## Quality Checks

- Toda tabela de domínio com `tenant_id UUID NOT NULL` + policy RLS.
- Testes de integração com banco real (nunca mock de banco).
- `cargo sqlx prepare` atualizado após cada migration.
- Índices em `(tenant_id, <campo_filtravel>)` para queries frequentes.
