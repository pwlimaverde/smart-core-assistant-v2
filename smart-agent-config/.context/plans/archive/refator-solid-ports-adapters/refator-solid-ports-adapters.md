---
status: completed
generated: 2026-06-21
completed: 2026-06-22
agents:
  - type: "refactoring-specialist"
    role: "Implementar o padrão Ports & Adapters nos apps de dados"
  - type: "test-writer"
    role: "Criar testes unitários com mocks e complementar integração SQL/RLS"
  - type: "backend-specialist"
    role: "Wiring de AppState, injeção de ports e manutenção dos adapters"
  - type: "security-auditor"
    role: "Garantir sanitização de SecretString e trilhas de auditoria por handler"
docs:
  - "architecture.md"
  - "testing-strategy.md"
  - "security.md"
phases:
  - id: "fase-0"
    name: "Infraestrutura de mocks (Cargo.toml + mockall)"
    prevc: "P"
    agent: "backend-specialist"
    status: "completed"
  - id: "fase-1"
    name: "Piloto — domínio WhatsApp (data_postgres)"
    prevc: "E"
    agent: "refactoring-specialist"
    status: "completed"
  - id: "fase-2-n"
    name: "Rollout data_postgres (domínio a domínio)"
    prevc: "E"
    agent: "refactoring-specialist"
    status: "completed"
  - id: "fase-d"
    name: "data_redis — ports por capacidade (ISP)"
    prevc: "E"
    agent: "refactoring-specialist"
    status: "completed"
  - id: "verificacao"
    name: "Verificação final e atualização dos scripts"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
---

# Refatoração SOLID (Ports & Adapters) — data_postgres e data_redis

> Introduz o padrão Ports & Adapters (hexagonal) nas camadas donas de datastore, invertendo
> dependências (DIP) para que handlers dependam apenas de traits/ports. Testes unitários de
> handler passam a rodar sem banco/Redis real, via mocks (`mockall = "0.13"`). Entrega
> piloto-primeiro no domínio WhatsApp, depois rollout por domínio.

## Artefatos

- **Plano completo detalhado:** [plano_completo_refator-solid-ports-adapters.md](./refator-solid-ports-adapters/plano_completo_refator-solid-ports-adapters.md)
- **Documentação auxiliar (libs + observabilidade):** [info_aux_refator-solid-ports-adapters.md](./refator-solid-ports-adapters/info_aux_refator-solid-ports-adapters.md)
- **Planejamento canônico em doc_dev:** [14-refator-solid-ports-adapters.md](../doc_dev/planejamento/14-refator-solid-ports-adapters.md)

## Objetivo e sinal de sucesso

- **Objetivo:** Todos os handlers de `data_postgres` e `data_redis` dependem apenas de ports
  (traits); adapters concretos encapsulam a transação/comando Redis.
- **Sinal de sucesso:** `.\infra\test-quick.ps1 -Pkg data_postgres` e `-Pkg data_redis` passam
  clippy + `--lib --bins` **sem abrir o túnel SSH**. Nenhum teste inline em `src/**` toca o
  datastore.

## Fases

### Fase 0 — Infraestrutura de mocks

**Objetivo:** Preparar workspace para usar `mockall`.

| # | Tarefa | Status |
| --- | --- | --- |
| 0.1 | Adicionar `mockall = "0.13"` em `[workspace.dependencies]` do `server/Cargo.toml` | pending |
| 0.2 | Adicionar `async-trait` em `[dependencies]` de `apps/data_postgres/Cargo.toml` e `apps/data_redis/Cargo.toml` | pending |
| 0.3 | Adicionar `mockall = { workspace = true }` em `[dev-dependencies]` dos dois apps | pending |

---

### Fase 1 — Piloto: domínio WhatsApp (data_postgres)

**Objetivo:** Provar o padrão completo nos 7 handlers WhatsApp; critério de pronto: `cargo test -p data_postgres --lib --bins` sem túnel.

| # | Tarefa | Status |
| --- | --- | --- |
| 1.1 | Criar `src/ports/whatsapp.rs` — trait `WhatsappStore` com `#[cfg_attr(test, mockall::automock)]` + `#[async_trait]` | pending |
| 1.2 | Criar `src/ports/audit.rs` — trait `AuditPort` | pending |
| 1.3 | Criar `src/ports/mod.rs` | pending |
| 1.4 | Criar `src/adapters/whatsapp.rs` — `PgWhatsappStore { pool, admin_pool }` | pending |
| 1.5 | Criar `src/adapters/audit.rs` — `RedisAuditPort` | pending |
| 1.6 | Criar `src/adapters/mod.rs` | pending |
| 1.7 | Refatorar 7 handlers WhatsApp em `main.rs:3469+` para `(store: &dyn WhatsappStore, audit: &dyn AuditPort, env)` | pending |
| 1.8 | Estender `AppState` com `whatsapp: Arc<dyn WhatsappStore>` e `audit: Arc<dyn AuditPort>` | pending |
| 1.9 | Atualizar wiring em `main()` | pending |
| 1.10 | Substituir 7 testes `setup_teste()` por testes mockall (fail-closed + happy path) | pending |
| 1.11 | Confirmar/complementar integração SQL/RLS em `infrastructure_postgres/tests/integracoes/` | pending |

---

### Fases 2..N — Rollout data_postgres (um domínio por merge)

**Objetivo:** Replicar o padrão da Fase 1 em todos os domínios restantes.

Domínios: `TenantStore` → `AuthStore` → `AtendimentoStore` → `ClienteStore` → `OperacionalStore` → `PlansStore` → `TreinamentoStore`.
Inclui abstração do `OutboxRelay` atrás de port.

---

### Fase D — data_redis: ports por capacidade (ISP)

**Objetivo:** 8 handlers de `data_redis` dependem de traits; 4 testes deixam de usar `setup_redis()`.

Ports: `CacheStore`, `RefreshTokenPort`, `TokenBlocklist`, `LoginRateLimiter`.

---

### Verificação final

**Critérios:**

1. `.\infra\test-quick.ps1 -Pkg data_postgres` e `-Pkg data_redis` passam sem túnel SSH.
2. `.\infra\test-local.ps1` passa completo (integração real + `sqlx prepare --check`).
3. `grep` por instanciação concreta nos domínios refatorados retorna vazio.
4. Scripts atualizados: remover a ressalva "(banco real)" do caminho rápido.

## Não-objetivos

- Não redesenhar traits `*Repository` nem o padrão `&mut Transaction`.
- Não mexer nos clientes finos (já SOLID via RPC).
- Não mockar SQL/banco.
- Não reescrever testes não tocados pelas fases.
