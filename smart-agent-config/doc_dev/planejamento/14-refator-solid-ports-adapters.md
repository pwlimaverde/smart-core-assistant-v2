# Plano de Implementação: Refatoração SOLID (Ports & Adapters) nos Serviços de Dados e Alinhamento das Boas Práticas de Teste

Este plano detalha a refatoração arquitetural que introduz o padrão **Ports & Adapters (arquitetura hexagonal)** nas camadas donas de datastore do Smart Core Assistant v2 (`data_postgres` e `data_redis`), aplicando os princípios **SOLID à risca** e alinhando todos os testes tocados às boas práticas da skill [`test-rust`](../../.context/skills/test-rust/SKILL.md).

O objetivo central é **inverter as dependências** (DIP): os handlers RPC passam a depender de **abstrações** (traits/ports), nunca de implementações concretas. Como consequência direta, a lógica de tradução RPC↔domínio fica testável com **mocks**, sem banco/Redis real, tornando o caminho rápido de testes (`test-quick.ps1` / `test-local.ps1 -Fast`) independente de infraestrutura.

A entrega é **piloto-primeiro**: o padrão completo é implementado no domínio WhatsApp do `data_postgres`, validado e mesclado; em seguida, replicado domínio a domínio.

---

## Contexto e Motivação

Os testes locais haviam se tornado inviáveis (lentos, consumindo recursos excessivos da máquina). Duas frentes foram identificadas:

1. **Gargalo de compilação (já corrigido):** um reset incorreto de `SQLX_OFFLINE=""` fazia o SQLx conectar ao banco remoto a cada macro `query!()` durante o build, transformando ~20 s de compilação em ~14 min. Adicionalmente, foi criado o script `infra/test-quick.ps1` para feedback rápido por pacote alterado.

2. **Problema arquitetural (escopo deste plano):** as camadas donas de datastore violam o **Princípio da Inversão de Dependência (DIP)**. Os handlers instanciam repositórios **concretos** e orquestram transações internamente, prendendo a lógica pura ao banco/cache real. Isso faz com que testes que deveriam ser unitários (rápidos, isolados) só funcionem batendo no datastore via túnel SSH.

### Premissa central (SOLID — DIP)

> Módulos de alto nível não devem depender de módulos de baixo nível. Ambos devem depender de abstrações.

Hoje, o handler de alto nível depende do adapter concreto de baixo nível:

```rust
// apps/data_postgres/src/main.rs — handler_create_tenant (estado atual)
use infrastructure_postgres::tenants::tenants::{PostgresTenantRepository, TenantRepository};
let repo = PostgresTenantRepository;        // depende da implementação CONCRETA (viola DIP)
let mut tx = pool.begin().await?;            // orquestra infraestrutura (transação) no handler (viola SRP)
publicar_auditoria(&mut redis_conn, ...)     // depende do ConnectionManager concreto (viola DIP)
```

Os repositórios **já são traits** (`TenantRepository`, `WhatsappInstanceRepository`, etc.), mas seus métodos recebem `&mut Transaction`/`&PgPool` por parâmetro e **o handler abre a transação**. Por isso, mockar apenas o repositório não elimina o banco do teste: o handler ainda precisa de um `pool` real para `pool.begin()`. A solução é introduzir uma **port** (abstração de operação de domínio) que encapsula a transação dentro do adapter.

---

## Audit SOLID (codebase-wide, somente-leitura)

| Local | Princípio violado | Sintoma | Correção |
|---|---|---|---|
| `apps/data_postgres/src/main.rs` (~50 handlers, **22** instanciações concretas) | **DIP** | `let repo = PostgresXxxRepository` + `pool.begin()` no handler; depende de `ConnectionManager` p/ auditoria | Handler depende de **port** (trait); adapter Pg encapsula a transação |
| idem | **SRP** | handler faz parse + transação + repo + auditoria + montagem de envelope (5 motivos para mudar) | Extrair `parse_*` puro; port assume persistência; `AuditPort` assume auditoria |
| idem | **OCP** | não é possível substituir comportamento (mock/outro backend) sem editar o handler | injeção via trait permite estender sem modificar |
| `apps/data_postgres/src/outbox_relay.rs` | **DIP** | `OutboxRelay { pool, redis_conn }` concretos; teste conecta no Postgres real | adapter atrás de port; lógica de drenagem testável com mock |
| `apps/data_redis/src/main.rs` (8 handlers) | **DIP/SRP** | handlers recebem `ConnectionManager` concreto; comandos Redis inline | ports `CacheStore`/`RefreshTokenStore`/`TokenBlocklist`/`LoginRateLimiter` (ISP) + adapter Redis |
| Apps clientes (`data_whatsapp`, `webhook_ingress`, `control_plane`, `worker`, `runtime_api`, `messaging_gateway`) | — | **OK**: já dependem de abstração (RPC/`MuxClient`) e mockam via servidor falso in-process | sem mudança |
| `crates/infrastructure_*` | — | repositórios **já são traits**; `*Repository` corretos | sem mudança (servem os adapters) |

**Conclusão:** os pontos sensíveis são exatamente as duas camadas donas de datastore (`data_postgres`, `data_redis`) somadas ao `outbox_relay`. Os clientes finos já estão SOLID (dependem do contrato RPC, não de implementações).

---

## Arquitetura Proposta (Ports & Adapters)

```
Handler (RPC)  ──depende──▶  Port (trait, abstração)  ◀──implementa──  Adapter (concreto)
   │ parse/validate payload (puro)                                        │ transação / comando Redis
   │ chama a port                                                         │ reusa repositórios existentes
   │ monta Envelope (ok_reply / erro)                                     │
   ▼                                                                      ▼
 teste UNITÁRIO com MockPort (SEM datastore)             teste de INTEGRAÇÃO (DB/Redis real + rollback/FLUSHDB)
```

### Princípios SOLID aplicados

- **S — SRP (Responsabilidade Única):** o handler passa a ter um único motivo para mudar (tradução RPC↔domínio). Persistência vive no adapter; auditoria vive no `AuditPort`.
- **O — OCP (Aberto/Fechado):** novos adapters (mock para teste, ou um backend alternativo) podem ser plugados sem editar o handler.
- **L — LSP (Substituição de Liskov):** mocks e adapters reais honram o mesmo contrato da trait — mesmos invariantes de retorno e de erro (`DbError`/`AppError`).
- **I — ISP (Segregação de Interface):** uma port por domínio/capacidade, não uma God-interface. O handler enxerga somente as operações que de fato usa.
- **D — DIP (Inversão de Dependência):** o handler de alto nível depende apenas de traits; os concretos são injetados via `AppState`.

### Localização das ports e adapters

Decisão: **dentro do próprio app de dados** (mantém o blast radius confinado e torna o mock visível no mesmo crate, sem feature-gating).

- `apps/data_postgres/src/ports/` — traits com `#[cfg_attr(test, mockall::automock)]`.
- `apps/data_postgres/src/adapters/` — implementações concretas (`Pg*Store`).
- `apps/data_redis/src/ports/` e `apps/data_redis/src/adapters/` — mesma estrutura.

Os adapters **reusam** os repositórios de `infrastructure_postgres` e o helper `run_in_tenant_transaction` (já existentes). **O SQL não muda** — apenas a orquestração da transação migra do handler para o adapter.

---

## Boas Práticas de Teste (skill `test-rust`, aplicadas a todo teste tocado)

- **Taxonomia correta:**
  - Testes de handler com mock = **unitários** inline (`#[cfg(test)] mod tests`), sem datastore, executados no caminho rápido `--lib --bins`.
  - Testes de SQL/RLS/Redis real = **integração** em `tests/`, executados somente na suíte completa via `test-local.ps1`.
- **Padrão AAA** explícito (Arrange/Act/Assert), com **um Act por teste**.
- **Nomes de teste em inglês**, comportamentais (ex.: `create_instance_rejects_missing_api_key`); **comentários explicativos em pt-br**.
- **Validar a variante do erro** com `matches!(err, AppError::Validation(_))`, nunca apenas `is_err()`.
- **Assíncrono:** `#[tokio::test]`; **timeout** em qualquer I/O; **eliminar `sleep` arbitrário** (ex.: os stubs em `application/tests/login/mod.rs` usam `sleep(200ms)` para aguardar o servidor — substituir por readiness explícito quando esses testes forem tocados).
- **Fail-closed:** cobrir explicitamente a negação (payload inválido, erro do port, isolamento RLS).
- **Banco real, nunca mock de SQL:** a regra do projeto se mantém — mocka-se apenas a **port** (a fronteira); o SQL continua testado contra Postgres real sob transação+rollback nos `tests/integracoes/`.

---

## Fases de Execução

### Fase 0 — Canonização do plano + infraestrutura de mocks

- Este documento canoniza o plano em `doc_dev/planejamento`.
- `apps/data_postgres/Cargo.toml` e `apps/data_redis/Cargo.toml`: adicionar `async-trait` (em `dependencies`) e `mockall = "0.13"` (em `dev-dependencies`). O `mockall` é uma dependência nova no workspace.

### Fase 1 — Piloto: domínio WhatsApp (data_postgres)

Domínio isolado e recém-criado, com 7 handlers (a partir de `apps/data_postgres/src/main.rs:3469`):
`create_whatsapp_instance_record`, `get_whatsapp_instance`, `list_whatsapp_instances`, `admin_list_all_connected_instances`, `admin_deletar_instancia`, `atualizar_estado_instancia`, `atualizar_instancia_provider_id`.

1. **Port** `src/ports/whatsapp.rs`: trait `WhatsappStore` (`#[cfg_attr(test, mockall::automock)]`, `#[async_trait]`) com um método por operação. Tipos reusados de `infrastructure_postgres` (`WhatsappInstance`, `RequestContext`, `DbError`).
2. **Audit port** `src/ports/audit.rs`: trait `AuditPort` abstraindo `publicar_auditoria` (`main.rs:1492`).
3. **Adapters** `src/adapters/whatsapp.rs`: `PgWhatsappStore { pool, admin_pool }` move a lógica de `run_in_tenant_transaction` + `PostgresWhatsappInstanceRepository` para dentro do adapter. `src/adapters/audit.rs`: `RedisAuditPort` envolvendo o `publicar_auditoria` atual.
4. **Refatorar os 7 handlers:** assinatura passa a `(store: &dyn WhatsappStore, [audit: &dyn AuditPort,] env)`; extrair função pura `parse_*` por handler; o corpo apenas traduz RPC↔port.
5. **Wiring no `main()`:** estender `AppState` (`main.rs:25`) com `whatsapp: Arc<dyn WhatsappStore>` e `audit: Arc<dyn AuditPort>`; as rotas (`main.rs:447+`) injetam a port no lugar de `state.pool`.
6. **Testes unitários (sem DB)** substituindo os 7 atuais que usam `setup_teste()`: usar `MockWhatsappStore`/`MockAuditPort`; cobrir payload inválido, erro do port (validando a variante) e envelope de sucesso.
7. **Integração (DB real):** confirmar/complementar a cobertura SQL/RLS em `crates/infrastructure_postgres/tests/integracoes/mod.rs` (já há `test_evolution_sync_crud` e `test_whatsapp_repo_extended`).
8. **Critério de pronto:** `cargo test -p data_postgres --lib --bins` roda **sem abrir o túnel SSH**.

### Fases 2..N — Rollout do data_postgres (um domínio por fase/merge)

Replicar o padrão da Fase 1, um domínio por vez:
`TenantStore` → `AuthStore` → `AtendimentoStore` → `ClienteStore` → `OperacionalStore` → `PlansStore` → `TreinamentoStore`.

Inclui migrar `test_outbox_relay_drenar` para integração e abstrair `OutboxRelay` atrás de uma port.

### Fase D — data_redis

Ports por capacidade (aplicando ISP):
- `CacheStore` — `get` / `set`.
- `RefreshTokenStore` — `store` / `validate_and_rotate` / `revoke_family`.
- `TokenBlocklist` — `block` / `is_blocked`.
- `LoginRateLimiter` — `register_login_attempt`.

O adapter Redis reusa os comandos atuais. Refatorar os 8 handlers (a partir de `apps/data_redis/src/main.rs:83`) e os 4 testes (hoje usam `setup_redis()` real → migram para mocks no caminho rápido; a cobertura de integração Redis real vai para `tests/`).

### Estado final

Nenhum teste em `apps/data_postgres/src/**` ou `apps/data_redis/src/**` toca o datastore; toda a cobertura real fica em `tests/`. `test-quick.ps1` e `test-local.ps1 -Fast` ficam **100% sem banco/Redis**. Atualizar o rótulo "(modo rapido, sem banco)" dos scripts para refletir a realidade.

---

## Arquivos-chave

- **Novos:** `apps/data_postgres/src/ports/{mod,whatsapp,audit,tenant,auth,...}.rs` e `apps/data_postgres/src/adapters/{mod,...}.rs`; estrutura equivalente em `apps/data_redis/src/`.
- **Modificados:** `apps/data_postgres/src/main.rs` (AppState, wiring das rotas, assinaturas e corpos dos handlers, `mod tests`), `apps/data_postgres/src/outbox_relay.rs`, `apps/data_redis/src/main.rs`, e o `Cargo.toml` dos dois apps (async-trait, mockall).
- **Reuso (sem alterar a lógica de SQL):** repositórios em `crates/infrastructure_postgres/src/**`, `run_in_tenant_transaction`, `RequestContext`, `DbError`.
- **Integração:** `crates/infrastructure_postgres/tests/integracoes/mod.rs`; novos diretórios `tests/` nos apps.

---

## Não-objetivos

- **Não** redesenhar as traits `*Repository` nem o padrão `&mut Transaction` (continuam servindo os adapters e os testes de integração).
- **Não** mexer nos clientes finos (`data_whatsapp`, `webhook_ingress`, `control_plane`, `worker`, `runtime_api`, `messaging_gateway`) — já estão SOLID via RPC.
- **Não** mockar SQL/banco (o SQL é testado contra Postgres real; mocka-se apenas a port).
- **Não** reescrever testes não tocados pelas fases (as boas práticas são aplicadas ao que for refatorado).

---

## Verificação (por fase)

1. `.\infra\test-quick.ps1 -Pkg data_postgres` (ou `-Pkg data_redis`) → clippy + `--lib --bins` **sem túnel/datastore**; os testes de handler do domínio refatorado passam com mocks.
2. `.\infra\test-local.ps1` (pré-merge) → fmt + clippy + integração com banco/Redis real + `sqlx prepare --check`; confirmar a cobertura SQL/RLS dos `tests/integracoes/`.
3. Inspeção: `grep` por instanciação concreta no domínio refatorado deve retornar vazio; as rotas usam a port injetada (não `state.pool`/`ConnectionManager`).
4. Confirmar que `cargo test -p <app> --lib --bins` **não** abre o túnel SSH.
