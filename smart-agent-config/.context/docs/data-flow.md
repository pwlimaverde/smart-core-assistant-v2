---
type: doc
name: data-flow
description: How data moves through the system and external integrations
category: data-flow
generated: 2026-05-29
status: filled
scaffoldVersion: "2.0.0"
---

## Data Flow & Integrations

Dados entram exclusivamente via webhook do Evolution Go. O `messaging_gateway` é a única porta de entrada e nunca executa regra pesada. O domínio roda assincronamente no `worker` via Redis Streams. O `runtime_api` expõe os dados ao Flutter pelo **contrato unificado D7**: FlatBuffers padrão (req/reply), gRPC fallback e Server Streaming para realtime.

## Module Dependencies

- **Apps de negócio (`runtime_api`, `worker`, `messaging_gateway`, `control_plane`)** → `crates/application`, `crates/contracts`, `crates/transport` — **nunca** `crates/infrastructure_*`; dados só via RPC aos `data_*`
- **Serviços de dados (`apps/data_postgres`, `data_redis`, `data_storage`)** → únicos donos das respectivas `crates/infrastructure_*`
- **`crates/application`** → `crates/contracts`, `crates/transport` (e `domain_*` quando extraídos)
- **`crates/domain_*`** → nenhuma dependência de infraestrutura (regras puras)
- **`crates/local_engine`** → compilável como lib dos binários-servidor OU como cdylib/FFI
- **`ia_engine/`** (serviço Python separado) → chamado por `apps/worker` via **gRPC**; usa pgvector para RAG

## Service Layer

- `messaging_gateway` — valida webhook, resolve tenant, persiste raw, publica no bus
- `worker` — consome eventos, executa domínio, chama IA, envia outbound
- `runtime_api` — comandos/consultas req/reply + realtime via Server Streaming (contrato D7; web via WS binário/gRPC-Web)
- `control_plane` — CRUD de tenants, planos, instâncias Evolution; CLIs de superusuário
- `data_postgres` / `data_redis` / `data_storage` — servidores RPC de dados (RLS, cache/tokens/locks, mídia R2)
- `ia_engine` — transcrição, análise de mídia, RAG, geração de resposta (Python/gRPC; núcleo `FeaturesCompose`)

## High-level Flow

### Mensagem recebida (inbound)

```
1. WhatsApp → Evolution Go → webhook HTTP → messaging_gateway
2. Gateway: valida assinatura/origem
            resolve tenant_id pela instância Evolution
            persiste payload bruto (raw_events)
            publica message.received no Redis Streams (com tenant_id)
3. Worker consome evento:
   a. DEBOUNCE por contato (acumula rajada, adquire lock)
   b. domain_conversation: normaliza e atualiza thread
   c. domain_ticket: política (reaproveita ativo / reabre / cria novo)
   d. ia_engine (gRPC): converte mídia, classifica intents, RAG, gera resposta
   e. domain_kanban: atualiza etapa/fluxo, registra MovimentoFluxo
   f. BotRulesEngine: decide se bot responde; se sim, envia outbound via Evolution
4. runtime_api empurra pelo stream realtime (Server Streaming): nova mensagem + status → Flutter
```

### Mídia

```
Webhook → worker decifra via Evolution Go → ia_engine (gRPC) gera resumo_midia + analise_midia
→ banco: linha da mensagem + resumo + ponteiro (hash, mimetype, tamanho)
→ binário vai para storage transitório (Cloudflare R2 via data_storage, TTL curto)
→ Flutter recebe mensagem com resumo pronto (sem baixar binário)
→ Atendente abre conversa → local_engine verifica cache por hash
   → ausente: baixa uma única vez, persiste em disco
   → presente: leitura local sem tocar servidor
```

### Mensagem enviada pelo atendente (outbound)

```
Flutter → runtime_api (req/reply — contrato D7) → worker persiste (tipo: ATENDENTE_HUMANO)
→ bot_pode_atender = false (bloqueado permanentemente)
→ Evolution Go envia mensagem WhatsApp
→ stream realtime notifica todos os clientes do tenant
```

## External Integrations

- **Evolution Go**: gateway WhatsApp. Auth: `apikey` por instância. Retry/backoff necessário (403/500 transitório em mídia).
- **PostgreSQL + pgvector**: RLS com `SET app.current_tenant = '<uuid>'`. pgvector para embeddings RAG.
- **Redis**: Streams como event bus (consumer groups). Cache/presença com namespace por tenant.
- **OpenAI / Groq / Ollama**: abstraídos pelo LangChain no `ia_engine`; tokens em variáveis de ambiente (override por tenant via `tenant_config`).
- **worker → ia_engine**: gRPC (processos separados; FFI/PyO3 descartado — §13.1 do planejamento). O worker substitui o Celery da v1 (fila Redis Streams + agendamento de feedback/retenção).
- **Cloudflare R2 (S3-compatible)**: storage transitório de mídia com TTL/retenção curta; acesso só via `data_storage` (`aws-sdk-s3`).

## Observability & Failure Modes

- Logs estruturados (JSON) via crate `observability` (tracing + métricas)
- Dead-letter: eventos sem consumer após N tentativas vão para stream de erros
- Idempotência: `wa_message_id` já existente não é reprocessado
- Debounce: lock de agendamento por contato evita processamento fragmentado
- Retry/backoff no download de mídia do Evolution Go

## Related Resources

- [Architecture](architecture.md)
