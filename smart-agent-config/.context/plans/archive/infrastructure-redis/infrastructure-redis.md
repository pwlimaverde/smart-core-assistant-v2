---
status: completed
generated: 2026-06-02
completed: 2026-06-02
slug: infrastructure-redis
scale: MEDIUM
artifacts:
  plano_completo: "./infrastructure-redis/plano_completo_infrastructure-redis.md"
  info_aux: "./infrastructure-redis/info_aux_infrastructure-redis.md"
  final_review: "../../workflow/docs/final-review-infrastructure-redis.md"
phases:
  - id: "phase-p"
    name: "Planning — escopo do cache/barramento e decisões"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review — chaves, envelope e segurança de tokens"
    prevc: "R"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-e"
    name: "Execution — crate infrastructure_redis"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
  - id: "phase-v"
    name: "Validation — testes de integração contra Redis real"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation — registro e arquivamento dotcontext"
    prevc: "C"
    agent: "backend-specialist"
    status: "completed"
---

# Fundação Redis de Cache e Barramento — crate `infrastructure_redis`

> Plano **canônico** (leve). A verdade técnica detalhada está nos artefatos abaixo.
> Reestruturado pela skill `plan-restructuring` a partir de
> `doc_dev/planejamento/04-infraestrutura-redis.md`.

## Artefatos

- **Plano completo (verdade técnica):**
  [`./infrastructure-redis/plano_completo_infrastructure-redis.md`](./infrastructure-redis/plano_completo_infrastructure-redis.md)
- **Documentação auxiliar (libs + decisões):**
  [`./infrastructure-redis/info_aux_infrastructure-redis.md`](./infrastructure-redis/info_aux_infrastructure-redis.md)

## Objetivo

Centralizar **todo** o acesso ao Redis em uma única crate
(`server/crates/infrastructure_redis`), análoga à ponte `infrastructure_postgres`. O Redis é o
coração de sincronização assíncrona da v2: barramento de eventos (Streams), cache de baixa latência
e primitivas de autenticação (refresh tokens e blocklist). É a **única** crate do workspace que
fala com o cliente Redis.

**Escopo (fundação):** conexão (`ConnectionManager` + cliente dedicado), namespacing por tenant,
refresh tokens com rotação/reuse-detection, blocklist por `jti`, cache de `flow_permissions` (TTL
curto), event bus (Redis Streams + consumer groups com `TenantEnvelope`), erro único `RedisError`
e testes de integração contra Redis real. **Fora do escopo:** pub/sub de invalidação de config,
fan-out realtime (WebSocket), lock de debounce, delayed tasks e presença (fases futuras); e o
**módulo de auth** (cadastro/login + JWT), que é plano separado e consome esta fundação.

**Sinal de sucesso:** `cargo build -p infrastructure_redis` compila; os testes de integração
(banco lógico 15) provam rotação/reuse-detection de refresh token, blocklist, cache de
flow_permissions e o ciclo publicar→consumir→confirmar/replay do event bus; `infrastructure_postgres`
segue compilando (feature `uuid v7` é aditiva); `cargo clippy` e `cargo fmt --check` limpos.

## Fases PREVC

| Fase | Nome | Agente | Status |
|---|---|---|---|
| **P** | Planning — escopo do cache/barramento e decisões | Backend Specialist | ✅ completed |
| **R** | Review — chaves, envelope e segurança de tokens | Backend Specialist (+ Security Reviewer) | ✅ completed |
| **E** | Execution — crate `infrastructure_redis` | Backend Specialist | ✅ completed |
| **V** | Validation — testes de integração contra Redis real | Test Writer (+ Backend Specialist) | ✅ completed |
| **C** | Confirmation — registro e arquivamento dotcontext | Backend Specialist | ✅ completed |

## Decisões-chave (resumo — detalhes no plano completo)

1. **Crate única de Redis** — nenhuma outra crate importa `redis` diretamente.
2. **`ConnectionManager`** para comandos; **conexão dedicada** para `XREADGROUP BLOCK`/pubsub.
3. **Namespacing por tenant** (`tenant:<uuid>:<recurso>:<chave>`); auth com prefixo `auth:`.
4. **Refresh token só como hash** no Redis; rotação com `SET ... KEEPTTL` e revogação de família
   no reuso (`TokenReuse`).
5. **`TenantEnvelope<T>`** com `event_id` UUID **v7** (ordenável/idempotente); `XADD MAXLEN ~`.
6. **`XGROUP CREATE` idempotente** — `BUSYGROUP` tolerado.
7. **Erro único `RedisError`** (thiserror), espelhando `DbError`.

## Verificação

`redis-server` local (ou docker `data.yml`/túnel) → `REDIS_URL` (testes anexam `/15`) →
`cargo build -p infrastructure_redis` → `RUST_TEST_THREADS=1 cargo test -p infrastructure_redis`
(10/10 verdes) → `SQLX_OFFLINE=true cargo build -p infrastructure_postgres` →
`cargo clippy --all-targets -D warnings` + `cargo fmt --check`. Branch
`claude/user-auth-module-plan-dykMV` a partir de `dev`; commits sem auto-referência ao modelo;
comentários em pt-br.
