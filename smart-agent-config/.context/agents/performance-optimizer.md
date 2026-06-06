---
type: agent
name: Performance Optimizer
description: Identify performance bottlenecks
agentType: performance-optimizer
phases: [E, V]
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Identificar gargalos no `worker` (tempo de processamento por evento, fila crescente).
- Otimizar queries PostgreSQL com índices em `(tenant_id, <campo>)`.
- Monitorar Redis Streams: consumer lag, throughput de eventos.
- Otimizar debounce: ajustar janela de acumulação de rajadas por contato.
- Garantir que o cache local do `local_engine` reduz acessos ao servidor.

## Key Bottlenecks

- **ia_engine**: a chamada à LLM domina o pipeline (200–5000ms); o transporte gRPC é desprezível. Escalar por N réplicas do `ia_engine` (vence o GIL) em vez de otimizar o transporte.
- **pgvector RAG**: busca de embeddings pode ser lenta sem índice HNSW/IVFFlat.
- **Download de mídia**: Evolution Go com retry/backoff pode bloquear o worker.
- **Debounce**: lock por contato pode serializar excessivamente sob alta carga.

## Quality Checks

- `cargo bench` para casos de uso críticos.
- Query explain para `message` e `ticket` por `tenant_id`.
- Índice pgvector configurado (`CREATE INDEX USING hnsw` na coluna `embedding`).
