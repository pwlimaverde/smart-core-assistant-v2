# Plano de Implementação: Refatoração SOLID (Ports & Adapters) nos Serviços de Dados e Alinhamento das Boas Práticas de Teste

> **Versão reestruturada** — exemplos de código validados contra o código-fonte atual de `apps/data_postgres/src/main.rs`, `apps/data_redis/src/main.rs` e `crates/infrastructure_postgres/src/integracoes/whatsapp.rs`, e contra a documentação local das libs em `smart-agent-config/doc_dev/libs/rust/` (`async_trait.md`, `mockall.md`, `redis.md`, `secrecy.md`, `tracing`/`opentelemetry.md`).

Este plano detalha a refatoração arquitetural que introduz o padrão **Ports & Adapters (arquitetura hexagonal)** nas camadas donas de datastore do Smart Core Assistant v2 (`data_postgres` e `data_redis`), aplicando os princípios **SOLID à risca** e alinhando todos os testes tocados às boas práticas da skill [`test-rust`].

O objetivo central é **inverter as dependências** (DIP): os handlers RPC passam a depender de **abstrações** (traits/ports), nunca de implementações concretas. Como consequência direta, a lógica de tradução RPC↔domínio fica testável com **mocks**, sem banco/Redis real, tornando o caminho rápido de testes (`test-quick.ps1` / `test-local.ps1 -Fast`) independente de infraestrutura.

A entrega é **piloto-primeiro**: o padrão completo é implementado no domínio WhatsApp do `data_postgres`, validado e mesclado; em seguida, replicado domínio a domínio.

---

## Contexto e Motivação

Os testes locais haviam se tornado inviáveis (lentos, consumindo recursos excessivos da máquina). Duas frentes foram identificadas:

1. **Gargalo de compilação (já corrigido):** um reset incorreto de `SQLX_OFFLINE=""` fazia o SQLx conectar ao banco remoto a cada macro `query!()` durante o build, transformando ~20 s de compilação em ~14 min. Adicionalmente, foi criado o script `infra/test-quick.ps1` para feedback rápido por pacote alterado.

2. **Problema arquitetural (escopo deste plano):** as camadas donas de datastore violam o **Princípio da Inversão de Dependência (DIP)**. Os handlers instanciam repositórios **concretos** e orquestram transações internamente, prendendo a lógica pura ao banco/cache real. Isso faz com que testes que deveriam ser unitários (rápidos, isolados) só funcionem batendo no datastore via túnel SSH.

### Premissa central (SOLID — DIP)

> Módulos de alto nível não devem depender de módulos de baixo nível. Ambos devem depender de abstrações.

Hoje, o handler de alto nível depende do adapter concreto de baixo nível. Trecho **real** atual (`apps/data_postgres/src/main.rs:3469`):

```rust
async fn handler_create_whatsapp_instance_record(pool: PgPool, env: Envelope) -> Envelope {
    // ... parse de name/api_key/provider ...
    let tenant_id = Uuid::parse_str(&env.tenant_id).unwrap_or_else(|_| Uuid::nil());
    let ctx = contexto_do_envelope(&env);
    let repo = infrastructure_postgres::integracoes::whatsapp::PostgresWhatsappInstanceRepository; // CONCRETO (viola DIP)

    let result =
        infrastructure_postgres::run_in_tenant_transaction(&pool, tenant_id, |mut tx| async move { // handler abre a transação (viola SRP)
            use infrastructure_postgres::integracoes::whatsapp::WhatsappInstanceRepository;
            let inst = repo.criar(&mut tx, &ctx, name, api_key, provider).await?;
            Ok((inst, tx))
        })
        .await;
    // ... monta envelope ...
}
```

Os repositórios **já são traits** (`WhatsappInstanceRepository`, `TenantRepository`, etc.), mas seus métodos recebem `&mut Transaction<'_, Postgres>`/`&PgPool` por parâmetro e **o handler abre a transação** via `run_in_tenant_transaction(&pool, ...)`. Por isso, mockar apenas o repositório não elimina o banco do teste: o handler ainda precisa de um `pool` real para abrir a transação. A solução é introduzir uma **port** (abstração de operação de domínio) que encapsula a transação dentro do adapter.

---

## Audit SOLID (codebase-wide, somente-leitura)

| Local | Princípio violado | Sintoma | Correção |
|---|---|---|---|
| `apps/data_postgres/src/main.rs` (~50 handlers, **22** instanciações concretas) | **DIP** | `let repo = PostgresXxxRepository` + `run_in_tenant_transaction(&pool, ...)` no handler; depende de `ConnectionManager` p/ auditoria | Handler depende de **port** (trait); adapter Pg encapsula a transação |
| idem | **SRP** | handler faz parse + transação + repo + auditoria + montagem de envelope (5 motivos para mudar) | Extrair `parse_*` puro; port assume persistência; `AuditPort` assume auditoria |
| idem | **OCP** | não é possível substituir comportamento (mock/outro backend) sem editar o handler | injeção via trait permite estender sem modificar |
| `apps/data_postgres/src/outbox_relay.rs` | **DIP** | `OutboxRelay { pool, redis_conn }` concretos; teste conecta no Postgres real | adapter atrás de port; lógica de drenagem testável com mock |
| `apps/data_redis/src/main.rs` (8 handlers) | **DIP/SRP** | handlers recebem `ConnectionManager` concreto; instanciam `RefreshTokenStore::new(con)` / `CachePermissoes::new(con)` inline | ports `CacheStore`/`RefreshTokenStore`/`TokenBlocklist`/`LoginRateLimiter` (ISP) + adapter Redis |
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
- **Assíncrono:** `#[tokio::test]`; **timeout** em qualquer I/O; **eliminar `sleep` arbitrário**.
- **Fail-closed:** cobrir explicitamente a negação (payload inválido, erro do port, isolamento RLS).
- **Banco real, nunca mock de SQL:** a regra do projeto se mantém — mocka-se apenas a **port** (a fronteira); o SQL continua testado contra Postgres real sob transação+rollback nos `tests/integracoes/`.

---

## Fases de Execução

### Fase 0 — Canonização do plano + infraestrutura de mocks

- Este documento canoniza o plano em `.context/plans/refator-solid-ports-adapters/`.
- `server/Cargo.toml` (`[workspace.dependencies]`): adicionar `mockall = "0.13"`. `async-trait` **já está** em `[workspace.dependencies]` (confirmado nos crates `infrastructure_postgres`/`infrastructure_redis`).
- `apps/data_postgres/Cargo.toml` e `apps/data_redis/Cargo.toml`:
  - em `[dependencies]`: `async-trait = { workspace = true }`;
  - em `[dev-dependencies]`: `mockall = { workspace = true }`.

```toml
# server/Cargo.toml — [workspace.dependencies]
async-trait = "0.1.83"   # já existente
mockall = "0.13"         # NOVO no workspace

# apps/data_postgres/Cargo.toml
[dependencies]
async-trait = { workspace = true }

[dev-dependencies]
mockall = { workspace = true }
```

> **Nota de versão (doc local `mockall.md`, verificado 2026-06-21):** versão recomendada 0.13.x; sem breaking changes relevantes vs 0.12. Library ID Context7: `/websites/rs_mockall_0_13_1_mockall`.

#### Observabilidade & Auditoria

- **Logs/traces:** nenhum evento novo. Mudança de build apenas.
- **Auditoria no banco:** sem evento de auditoria.
- **Sanitização:** N/A.

---

### Fase 1 — Piloto: domínio WhatsApp (data_postgres)

Domínio isolado e recém-criado, com 7 handlers (a partir de `apps/data_postgres/src/main.rs:3469`):
`create_whatsapp_instance_record`, `get_whatsapp_instance`, `list_whatsapp_instances`, `admin_list_all_connected_instances`, `admin_deletar_instancia`, `atualizar_estado_instancia`, `atualizar_instancia_provider_id`.

> **Tipos reusados de `infrastructure_postgres` (confirmados no código):** `WhatsappInstance` (struct `Serialize`/`Deserialize`), `RequestContext`, `DbError`, `run_in_tenant_transaction`, `PostgresWhatsappInstanceRepository` + trait `WhatsappInstanceRepository`.

#### 1a) Port `src/ports/whatsapp.rs`

A trait `WhatsappStore` expõe **uma operação de domínio por handler**, já recebendo `RequestContext`/`tenant_id` e devolvendo tipos de domínio — a transação fica escondida no adapter. Ordem dos atributos conforme `doc_dev/libs/rust/mockall.md` §3: **`#[cfg_attr(test, mockall::automock)]` ANTES de `#[async_trait]`**.

```rust
//! Port (abstração) do domínio WhatsApp do data_postgres.
//! O handler depende SOMENTE desta trait; a transação vive no adapter (DIP).

use async_trait::async_trait;
use infrastructure_postgres::integracoes::whatsapp::WhatsappInstance;
use infrastructure_postgres::{DbError, RequestContext};

/// Operações de persistência do domínio WhatsApp expostas aos handlers RPC.
/// Cada método encapsula a abertura/commit da transação no adapter concreto.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait WhatsappStore: Send + Sync {
    /// Cria um registro de instância (encapsula run_in_tenant_transaction + repo.criar).
    async fn criar_instancia(
        &self,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError>;

    /// Busca instância por id (tenant-scoped via RLS).
    async fn buscar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError>;

    /// Lista instâncias ativas do tenant.
    async fn listar_ativas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    /// Lista cross-tenant de instâncias conectadas (admin/BYPASSRLS no adapter).
    async fn admin_listar_conectadas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError>;

    /// Remoção admin de instância.
    async fn admin_deletar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<(), DbError>;

    /// Atualiza o estado de conexão da instância.
    async fn atualizar_estado(
        &self,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError>;

    /// Atualiza o provider_id (instance_id) e telefone da instância.
    async fn atualizar_provider_id(
        &self,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<&str>,
    ) -> Result<(), DbError>;
}
```

#### 1b) Audit port `src/ports/audit.rs`

Abstrai a função livre `publicar_auditoria` (`main.rs:1492`), que hoje recebe `&mut ConnectionManager`. O caller passa a **descrição já sanitizada** (sem segredos).

```rust
//! Port de auditoria: abstrai a publicação de eventos no bus de segurança.
//! O handler não conhece o ConnectionManager do Redis (DIP).

use async_trait::async_trait;
use contracts::Envelope;

/// Publica um evento de auditoria a partir do envelope da requisição.
/// `event` é o event_type estável (ex.: "whatsapp_instance.created").
/// `message`/`context` JÁ devem estar sanitizados pelo caller (sem segredos).
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait AuditPort: Send + Sync {
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    );
}
```

E o módulo agregador `src/ports/mod.rs`:

```rust
pub mod audit;
pub mod whatsapp;

pub use audit::AuditPort;
pub use whatsapp::WhatsappStore;

#[cfg(test)]
pub use audit::MockAuditPort;
#[cfg(test)]
pub use whatsapp::MockWhatsappStore;
```

#### 1c) Adapters `src/adapters/whatsapp.rs` e `src/adapters/audit.rs`

O adapter `PgWhatsappStore` move a orquestração de transação para dentro de si, reusando `run_in_tenant_transaction` e `PostgresWhatsappInstanceRepository`. **O SQL não muda.**

```rust
//! Adapter concreto do domínio WhatsApp: reusa os repositórios de
//! infrastructure_postgres e encapsula a transação (antes vivia no handler).

use async_trait::async_trait;
use sqlx::PgPool;
use uuid::Uuid;

use infrastructure_postgres::integracoes::whatsapp::{
    PostgresWhatsappInstanceRepository, WhatsappInstance, WhatsappInstanceRepository,
};
use infrastructure_postgres::{run_in_tenant_transaction, DbError, RequestContext};

use crate::ports::WhatsappStore;

/// Implementação Postgres da port WhatsApp.
/// `admin_pool` (BYPASSRLS) é usado apenas nas consultas cross-tenant; quando
/// ausente, recai no pool de aplicação (RLS ativa) com aviso observável.
#[derive(Clone)]
pub struct PgWhatsappStore {
    pub pool: PgPool,
    pub admin_pool: Option<PgPool>,
}

impl PgWhatsappStore {
    pub fn new(pool: PgPool, admin_pool: Option<PgPool>) -> Self {
        Self { pool, admin_pool }
    }
}

#[async_trait]
impl WhatsappStore for PgWhatsappStore {
    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_name = name))]
    async fn criar_instancia(
        &self,
        ctx: &RequestContext,
        name: &str,
        api_key: &str,
        provider: &str,
    ) -> Result<WhatsappInstance, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let name = name.to_string();
        let api_key = api_key.to_string();
        let provider = provider.to_string();

        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo
                .criar(&mut tx, &ctx, &name, &api_key, &provider)
                .await?;
            Ok((inst, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn buscar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<Option<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let inst = repo.buscar_por_id(&mut tx, &ctx, id).await?;
            Ok((inst, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn listar_ativas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            let list = repo.listar_ativas(&mut tx, &ctx).await?;
            Ok((list, tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
    async fn admin_listar_conectadas(
        &self,
        ctx: &RequestContext,
    ) -> Result<Vec<WhatsappInstance>, DbError> {
        // Consulta cross-tenant exige BYPASSRLS: usa admin_pool quando disponível.
        if self.admin_pool.is_none() {
            tracing::warn!(
                "admin_listar_conectadas sem DATABASE_ADMIN_URL: a RLS bloqueará a \
                 consulta cross-tenant e a lista virá vazia"
            );
        }
        let effective_pool = self.admin_pool.as_ref().unwrap_or(&self.pool);
        let repo = PostgresWhatsappInstanceRepository;
        let mut tx = effective_pool.begin().await?;
        let list = repo.admin_listar_todas_conectadas(&mut tx, ctx).await?;
        tx.commit().await?;
        Ok(list)
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn admin_deletar_instancia(
        &self,
        ctx: &RequestContext,
        id: i32,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.admin_deletar_instancia(&mut tx, &ctx, id).await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn atualizar_estado(
        &self,
        ctx: &RequestContext,
        id: i32,
        connection_state: &str,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let connection_state = connection_state.to_string();
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_estado(&mut tx, &ctx, id, &connection_state)
                .await?;
            Ok(((), tx))
        })
        .await
    }

    #[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id, instance_id = id))]
    async fn atualizar_provider_id(
        &self,
        ctx: &RequestContext,
        id: i32,
        instance_id: &str,
        phone_number: Option<&str>,
    ) -> Result<(), DbError> {
        let repo = PostgresWhatsappInstanceRepository;
        let ctx = ctx.clone();
        let tenant_id = ctx.tenant_id;
        let instance_id = instance_id.to_string();
        let phone_number = phone_number.map(|s| s.to_string());
        run_in_tenant_transaction(&self.pool, tenant_id, |mut tx| async move {
            repo.atualizar_instancia_provider_id(
                &mut tx,
                &ctx,
                id,
                &instance_id,
                phone_number.as_deref(),
            )
            .await?;
            Ok(((), tx))
        })
        .await
    }
}
```

> **Nota sobre `_ = &Uuid::nil()`:** o `Uuid` é apenas para evitar warning de import não usado caso o módulo seja recortado; remova-o se não for necessário no arquivo final. (Mantido aqui apenas como lembrete — o import real é `uuid::Uuid` somente se algum método o usar diretamente.)

Adapter de auditoria `src/adapters/audit.rs` — envolve `publicar_auditoria`. Como `publicar_auditoria` recebe `&mut ConnectionManager` e o `ConnectionManager` é clonável e barato (doc local `redis.md`), o adapter mantém uma cópia clonada por chamada.

```rust
//! Adapter de auditoria: publica no bus de segurança via ConnectionManager.

use async_trait::async_trait;
use contracts::Envelope;
use redis::aio::ConnectionManager;

use crate::ports::AuditPort;

/// Publica eventos de auditoria no bus de segurança (REDIS_BUS_URL).
#[derive(Clone)]
pub struct RedisAuditPort {
    conn: ConnectionManager,
}

impl RedisAuditPort {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl AuditPort for RedisAuditPort {
    #[tracing::instrument(skip_all, fields(event = event))]
    async fn publish(
        &self,
        env: &Envelope,
        event: &str,
        message: String,
        context: serde_json::Value,
    ) {
        // ConnectionManager é clonável (compartilha a conexão multiplexada subjacente).
        let mut conn = self.conn.clone();
        // Reusa a função existente: NÃO há auditoria própria aqui (evita recursão);
        // a falha de publicação é registrada como ERROR dentro de publicar_auditoria.
        crate::publicar_auditoria(&mut conn, env, event, message, context).await;
    }
}
```

E `src/adapters/mod.rs`:

```rust
pub mod audit;
pub mod whatsapp;

pub use audit::RedisAuditPort;
pub use whatsapp::PgWhatsappStore;
```

#### 1d) Handlers refatorados

Cada handler vira: (1) `parse_*` puro, (2) chamada à port, (3) montagem do envelope. Exemplo do handler de criação (o único com auditoria entre os 7):

```rust
/// Resultado puro do parse do payload de criação (sem I/O).
struct CreateWhatsappInput {
    name: String,
    api_key: String,
    provider: String,
}

/// Parse PURO do payload — testável sem datastore.
fn parse_create_whatsapp(env: &Envelope) -> Result<CreateWhatsappInput, error_core::AppError> {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload)
        .map_err(|e| error_core::AppError::Validation(e.to_string()))?;

    let name = payload
        .get("name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("name ausente".into()))?
        .to_string();
    let api_key = payload
        .get("api_key")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("api_key ausente".into()))?
        .to_string();
    let provider = payload
        .get("provider")
        .and_then(|v| v.as_str())
        .ok_or_else(|| error_core::AppError::Validation("provider ausente".into()))?
        .to_string();

    Ok(CreateWhatsappInput { name, api_key, provider })
}

/// Handler refatorado: depende SOMENTE das ports (DIP). Sem pool, sem transação.
async fn handler_create_whatsapp_instance_record(
    store: &dyn WhatsappStore,
    audit: &dyn AuditPort,
    env: Envelope,
) -> Envelope {
    // 1) parse puro
    let input = match parse_create_whatsapp(&env) {
        Ok(v) => v,
        Err(e) => return erro(e, &env),
    };
    let ctx = contexto_do_envelope(&env);

    // 2) chama a port (transação encapsulada no adapter)
    match store
        .criar_instancia(&ctx, &input.name, &input.api_key, &input.provider)
        .await
    {
        Ok(inst) => {
            // 3a) auditoria com descrição SANITIZADA (sem api_key/instance_token)
            audit
                .publish(
                    &env,
                    "whatsapp_instance.created",
                    format!("instância '{}' criada", input.name),
                    serde_json::json!({ "instance_name": input.name, "provider": input.provider }),
                )
                .await;
            // 3b) sucesso
            tracing::info!(instance_name = %input.name, "instância WhatsApp criada");
            ok_reply(
                &env,
                "CreateWhatsappInstanceRecordReply",
                serde_json::to_value(&inst).unwrap_or_default(),
            )
        }
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}
```

Handlers de leitura (`get`/`list`/`admin_list`) recebem só `store: &dyn WhatsappStore` (sem `audit`). Exemplo enxuto:

```rust
async fn handler_list_whatsapp_instances(store: &dyn WhatsappStore, env: Envelope) -> Envelope {
    let ctx = contexto_do_envelope(&env);
    match store.listar_ativas(&ctx).await {
        Ok(list) => ok_reply(
            &env,
            "ListWhatsappInstancesReply",
            serde_json::json!({ "instances": list }),
        ),
        Err(e) => erro(error_core::AppError::Database(e.to_string()), &env),
    }
}
```

#### 1e) AppState com ports

```rust
#[derive(Clone)]
struct AppState {
    pool: PgPool,
    admin_pool: Option<PgPool>,
    redis_conn: ConnectionManager,
    cipher: std::sync::Arc<infrastructure_postgres::crypto::CipherManager>,
    config_cache: std::sync::Arc<infrastructure_postgres::TenantConfigCache>,
    // NOVO: ports injetadas como trait objects (DIP)
    whatsapp: std::sync::Arc<dyn ports::WhatsappStore>,
    audit: std::sync::Arc<dyn ports::AuditPort>,
}
```

> Durante o rollout incremental, `pool`/`admin_pool`/`redis_conn` continuam em `AppState` para os handlers ainda não migrados. Ao final do rollout completo eles podem ser removidos.

#### 1f) Wiring no `main()`

```rust
// (após criar pool, admin_pool e bus_conn — ver main.rs:90)
let whatsapp_store: std::sync::Arc<dyn ports::WhatsappStore> =
    std::sync::Arc::new(adapters::PgWhatsappStore::new(pool.clone(), admin_pool.clone()));
let audit_port: std::sync::Arc<dyn ports::AuditPort> =
    std::sync::Arc::new(adapters::RedisAuditPort::new(bus_conn.clone()));

let state = AppState {
    pool: pool.clone(),
    admin_pool: admin_pool.clone(),
    redis_conn: bus_conn.clone(),
    cipher,
    config_cache,
    whatsapp: whatsapp_store,
    audit: audit_port,
};
```

E o registro da rota passa a injetar as ports (em vez de `state.pool`):

```rust
.route("CreateWhatsappInstanceRecord", move |env| {
    let state = state_for_create_whatsapp_instance_record.clone();
    Box::pin(async move {
        handler_create_whatsapp_instance_record(
            state.whatsapp.as_ref(),
            state.audit.as_ref(),
            env,
        )
        .await
    })
})
```

No topo do `main.rs`, declarar os módulos:

```rust
mod adapters;
mod ports;
```

#### 1g) Testes unitários (sem DB) — substituem os 7 que usam `setup_teste()`

Dois testes completos para o handler de criação: **fail-closed** (payload inválido — port NUNCA chamada) e **happy path**. Conforme `mockall.md` §3: retorno assíncrono via `.returning(|...| Box::pin(async { ... }))`; `.never()` para fail-closed.

```rust
#[cfg(test)]
mod tests_whatsapp_unit {
    use super::*;
    use crate::ports::{MockAuditPort, MockWhatsappStore};
    use contracts::{Envelope, MessageKind};
    use infrastructure_postgres::integracoes::whatsapp::WhatsappInstance;

    /// Helper: monta um Envelope mínimo com payload arbitrário.
    fn envelope_com_payload(method: &str, payload: serde_json::Value) -> Envelope {
        Envelope {
            kind: MessageKind::Request as i32,
            method: method.to_string(),
            tenant_id: uuid::Uuid::new_v4().to_string(),
            traceparent: "00-trace-span-01".to_string(),
            payload: serde_json::to_vec(&payload).unwrap(),
            ..Default::default()
        }
    }

    /// Instância fake retornada pelo mock no happy path.
    fn instancia_fake(name: &str) -> WhatsappInstance {
        WhatsappInstance {
            id: 1,
            tenant_id: uuid::Uuid::nil(),
            name: name.to_string(),
            instance_id: None,
            api_key: "k".to_string(),
            phone_number: None,
            active: true,
            connection_state: "close".to_string(),
            last_state_check: None,
            media_storage_backend: "r2".to_string(),
            provider: "evolution".to_string(),
            subscribed_events: serde_json::json!([]),
            last_connection_state: None,
            created_at: chrono::Utc::now(),
        }
    }

    /// FAIL-CLOSED: payload sem api_key deve retornar erro de validação
    /// e a port NUNCA pode ser chamada (não toca o banco).
    #[tokio::test]
    async fn create_instance_rejects_missing_api_key() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store.expect_criar_instancia().never(); // fail-closed: persistência não pode ocorrer
        let mut audit = MockAuditPort::new();
        audit.expect_publish().never(); // sem auditoria em payload inválido
        let env = envelope_com_payload(
            "CreateWhatsappInstanceRecord",
            serde_json::json!({ "name": "inst1", "provider": "evolution" }), // api_key ausente
        );

        // Act
        let resp = handler_create_whatsapp_instance_record(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Error as i32);
        let err = resp.error.expect("deveria ter envelope de erro");
        // valida a VARIANTE/código do erro, não apenas is_err()
        assert!(
            err.code.contains("validation") || err.message.contains("api_key"),
            "erro inesperado: {:?}",
            err
        );
    }

    /// HAPPY PATH: payload válido chama a port uma vez, publica auditoria e
    /// devolve Reply com a instância serializada.
    #[tokio::test]
    async fn create_instance_persists_and_audits_on_valid_payload() {
        // Arrange
        let mut store = MockWhatsappStore::new();
        store
            .expect_criar_instancia()
            .times(1)
            .returning(|_ctx, name, _api_key, _provider| {
                let inst = instancia_fake(name);
                Box::pin(async move { Ok(inst) })
            });
        let mut audit = MockAuditPort::new();
        audit
            .expect_publish()
            .withf(|_, event, _, _| event == "whatsapp_instance.created")
            .times(1)
            .returning(|_, _, _, _| Box::pin(async {}));
        let env = envelope_com_payload(
            "CreateWhatsappInstanceRecord",
            serde_json::json!({ "name": "inst1", "api_key": "secret", "provider": "evolution" }),
        );

        // Act
        let resp = handler_create_whatsapp_instance_record(&store, &audit, env).await;

        // Assert
        assert_eq!(resp.kind, MessageKind::Reply as i32);
        assert_eq!(resp.method, "CreateWhatsappInstanceRecordReply");
        let body: serde_json::Value = serde_json::from_slice(&resp.payload).unwrap();
        assert_eq!(body["name"], "inst1");
    }
}
```

#### 1h) Integração (DB real)

Confirmar/complementar a cobertura SQL/RLS do repositório WhatsApp em `crates/infrastructure_postgres/tests/integracoes/mod.rs` (transação+rollback / `#[sqlx::test]`). Nenhum teste de SQL real fica em `apps/data_postgres/src/**`.

#### 1i) Critério de pronto

`cargo test -p data_postgres --lib --bins` (via `.\infra\test-quick.ps1 -Pkg data_postgres`) roda **sem abrir o túnel SSH**.

#### Observabilidade & Auditoria (Fase 1, por handler)

| Handler | Log/trace | Auditoria (audit_log / event_type) | Sanitização |
|---|---|---|---|
| `create_whatsapp_instance_record` | `#[instrument(skip_all, fields(tenant_id, instance_name = name))]` no adapter; `info!(instance_name)` após sucesso. **Nunca** logar `api_key`/`instance_token`. | `AuditPort::publish` event_type **`whatsapp_instance.created`**; campos: user_id, tenant_id, instance_name, provider (via `env` + context). Assíncrono (bus → data_postgres). | `api_key` jamais entra em log/span/context; só `instance_name`/`provider`. Persistência da chave é responsabilidade do repositório/`CipherManager` (sem mudança de SQL). |
| `get_whatsapp_instance` / `list_whatsapp_instances` | `#[instrument(skip_all, fields(tenant_id))]`; nível **DEBUG**. | **Sem evento de auditoria** (leitura). | Resposta não inclui chaves em plaintext nos spans (não logar a struct inteira). |
| `admin_list_all_connected_instances` | `#[instrument(skip_all, fields(tenant_id))]` + `warn!` quando `admin_pool` ausente (degradação observável). | **Sem evento de auditoria** (leitura). | idem leitura. |
| `admin_deletar_instancia` | `#[instrument(skip_all, fields(tenant_id, instance_id = id))]`; nível **WARN**. | event_type **`whatsapp_instance.deleted`**; metadados: instance_id, tenant_id, user_id. | sem segredos no context. |
| `atualizar_estado_instancia` | `#[instrument(...)]` nível **DEBUG**. | event_type **`whatsapp_instance.state_updated`**. | sem segredos. |
| `atualizar_instancia_provider_id` | `#[instrument(...)]` nível **DEBUG**. | event_type **`whatsapp_instance.provider_updated`**. | `instance_id`/`phone_number` são identificadores de provider (não segredos); ok no context. |
| `RedisAuditPort::publish` | `#[instrument(skip_all, fields(event))]`; **ERROR** em falha de publicação no bus (dentro de `publicar_auditoria`). | **Sem audit próprio** (evita recursão). | Caller já passa descrição sanitizada. |

> **Convenção `#[instrument]` (doc local tracing/opentelemetry):** sempre `skip_all` + `fields(...)` explícitos com chaves de correlação (`tenant_id`, eventualmente `trace_id`). `#[instrument(err)]` SÓ onde todo erro é falha real de infra (não usar nos handlers, cujos erros incluem validação esperada). Nunca `println!`.

---

### Fases 2..N — Rollout do data_postgres (um domínio por fase/merge)

Replicar o padrão da Fase 1, um domínio por vez:
`TenantStore` → `AuthStore` → `AtendimentoStore` → `ClienteStore` → `OperacionalStore` → `PlansStore` → `TreinamentoStore`.

Inclui migrar `test_outbox_relay_drenar` para integração e abstrair `OutboxRelay` atrás de uma port (`OutboxDrainPort` ou similar), tornando a lógica de drenagem testável com mock.

#### Observabilidade & Auditoria (Fases 2..N)

Eventos críticos obrigatórios (referência 08 §4.2), publicados via `AuditPort::publish` nos handlers correspondentes:
`tenant.created`, `tenant.owner_changed`, `tenant_invite.created`, `tenant_user.role_changed`, `subscription.updated`, `payment.inserted`.
- **Sanitização:** nenhum segredo (tokens, chaves, dados de pagamento brutos) em log/span/context. Pagamentos auditam metadados (id, valor, status), nunca PAN/credenciais.
- Cada novo `Pg*Store` segue a mesma convenção de `#[instrument(skip_all, fields(tenant_id, ...))]` dos adapters da Fase 1.

---

### Fase D — data_redis

Ports por capacidade (aplicando ISP), uma trait por responsabilidade:
- `CacheStore` — `get` / `set` (reusa `infrastructure_redis::CachePermissoes`).
- `RefreshTokenStore` — `store` / `validate_and_rotate` / `revoke_family` (reusa `infrastructure_redis::RefreshTokenStore`).
- `TokenBlocklist` — `block` / `is_blocked`.
- `LoginRateLimiter` — `register_login_attempt`.

> **Atenção a colisão de nomes:** já existe `infrastructure_redis::RefreshTokenStore` (struct concreta). A **port** deve ter nome distinto para evitar ambiguidade — recomenda-se `RefreshTokenPort` (ou colocá-la em `ports::refresh_token::RefreshTokenStore` e sempre referenciar qualificada). Abaixo usamos `RefreshTokenPort`.

#### Port `src/ports/refresh_token.rs`

```rust
//! Port de refresh tokens (ISP): segrega a capacidade de rotação/revogação
//! do restante do cache. O handler depende SOMENTE desta trait.

use async_trait::async_trait;
use infrastructure_redis::{RedisError, RefreshTokenRegistro};
use uuid::Uuid;

/// Operações de ciclo de vida de refresh tokens.
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait RefreshTokenPort: Send + Sync {
    /// Armazena um novo refresh token (hash) vinculado a usuário/tenant/família.
    async fn store(
        &self,
        token_hash: &str,
        user_id: i32,
        tenant_id: Option<Uuid>,
        family_id: &str,
        ttl: u64,
    ) -> Result<(), RedisError>;

    /// Valida e rotaciona o token; erro `TokenReuse` em reuso (família comprometida).
    async fn validate_and_rotate(
        &self,
        token_hash: &str,
    ) -> Result<RefreshTokenRegistro, RedisError>;

    /// Revoga toda a família (em caso de reuso detectado).
    async fn revoke_family(&self, family_id: &str) -> Result<(), RedisError>;
}
```

> Os tipos `RedisError` e `RefreshTokenRegistro` devem ser confirmados/exportados de `infrastructure_redis` (o registro hoje é serializado em `handler_validate_and_rotate`). Se o nome real do registro diferir, ajustar o alias na port.

#### Adapter `src/adapters/refresh_token.rs`

```rust
//! Adapter Redis de refresh tokens: reusa infrastructure_redis::RefreshTokenStore.

use async_trait::async_trait;
use redis::aio::ConnectionManager;
use uuid::Uuid;

use infrastructure_redis::{RedisError, RefreshTokenRegistro};

use crate::ports::RefreshTokenPort;

#[derive(Clone)]
pub struct RedisRefreshTokenStore {
    conn: ConnectionManager,
}

impl RedisRefreshTokenStore {
    pub fn new(conn: ConnectionManager) -> Self {
        Self { conn }
    }
}

#[async_trait]
impl RefreshTokenPort for RedisRefreshTokenStore {
    #[tracing::instrument(skip_all, fields(user_id, family_id))]
    async fn store(
        &self,
        token_hash: &str,
        user_id: i32,
        tenant_id: Option<Uuid>,
        family_id: &str,
        ttl: u64,
    ) -> Result<(), RedisError> {
        // NUNCA logar token_hash (segredo). Só user_id/family_id nos fields.
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store
            .armazenar(token_hash, user_id, tenant_id, family_id, ttl)
            .await
    }

    #[tracing::instrument(skip_all)]
    async fn validate_and_rotate(
        &self,
        token_hash: &str,
    ) -> Result<RefreshTokenRegistro, RedisError> {
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store.validar_e_rotacionar(token_hash).await
    }

    #[tracing::instrument(skip_all, fields(family_id))]
    async fn revoke_family(&self, family_id: &str) -> Result<(), RedisError> {
        // WARN: revogação de família indica possível comprometimento.
        tracing::warn!(family_id, "revogando família de refresh tokens");
        let mut store = infrastructure_redis::RefreshTokenStore::new(self.conn.clone());
        store.revogar_familia(family_id).await
    }
}
```

#### Handler refatorado (`validate_and_rotate`)

```rust
async fn handler_validate_and_rotate(
    store: &dyn RefreshTokenPort,
    env: Envelope,
) -> Envelope {
    let payload: serde_json::Value = serde_json::from_slice(&env.payload).unwrap_or_default();
    let token_hash = payload.get("token_hash").and_then(|v| v.as_str()).unwrap_or("");

    match store.validate_and_rotate(token_hash).await {
        Ok(reg) => Envelope {
            kind: MessageKind::Reply as i32,
            method: "ValidateAndRotateReply".to_string(),
            payload: serde_json::to_vec(&reg).unwrap_or_default(),
            error: None,
            ..env
        },
        Err(e) => {
            // Reuso de token = falha de autenticação (possível roubo), não miss de cache.
            let app_err = match e {
                infrastructure_redis::RedisError::TokenReuse => {
                    error_core::AppError::Auth("token_reuse_detected".to_string())
                }
                outro => error_core::AppError::Cache(outro.to_string()),
            };
            let err_env = app_err.to_error_envelope(&env.traceparent, "data_redis");
            Envelope {
                kind: MessageKind::Error as i32,
                method: "ValidateAndRotateReply".to_string(),
                error: Some(err_env),
                ..env
            }
        }
    }
}
```

#### AppState + wiring (data_redis)

```rust
#[derive(Clone)]
struct AppState {
    redis_conn: ConnectionManager,
    // ports por capacidade (ISP)
    refresh_token: std::sync::Arc<dyn ports::RefreshTokenPort>,
    // ... cache, blocklist, rate_limiter ...
}

// em main(), após criar redis_conn:
let refresh_token: std::sync::Arc<dyn ports::RefreshTokenPort> =
    std::sync::Arc::new(adapters::RedisRefreshTokenStore::new(redis_conn.clone()));

// rota:
.route("ValidateAndRotate", move |env| {
    let state = state_for_validate.clone();
    Box::pin(async move {
        handler_validate_and_rotate(state.refresh_token.as_ref(), env).await
    })
})
```

#### Teste unitário (fail-closed: reuso de token detectado)

```rust
#[tokio::test]
async fn validate_and_rotate_maps_token_reuse_to_auth_error() {
    // Arrange: a port reporta reuso de token (família comprometida).
    let mut store = MockRefreshTokenPort::new();
    store
        .expect_validate_and_rotate()
        .times(1)
        .returning(|_| Box::pin(async { Err(infrastructure_redis::RedisError::TokenReuse) }));
    let env = Envelope {
        kind: MessageKind::Request as i32,
        method: "ValidateAndRotate".to_string(),
        payload: serde_json::to_vec(&serde_json::json!({ "token_hash": "h" })).unwrap(),
        traceparent: "00-t-s-01".to_string(),
        ..Default::default()
    };

    // Act
    let resp = handler_validate_and_rotate(&store, env).await;

    // Assert: erro de AUTENTICAÇÃO com marcador estável, não erro de cache.
    assert_eq!(resp.kind, MessageKind::Error as i32);
    let err = resp.error.expect("deveria ter erro");
    assert!(err.message.contains("token_reuse_detected"), "err: {:?}", err);
}
```

#### Observabilidade & Auditoria (Fase D)

| Capacidade | Log/trace | Auditoria | Sanitização |
|---|---|---|---|
| `RefreshTokenPort::store` | `#[instrument(skip_all, fields(user_id, family_id))]`. | Sem audit_log formal nesta camada (a runtime_api audita login). | **NUNCA** logar `token_hash`. |
| `RefreshTokenPort::validate_and_rotate` | `#[instrument(skip_all)]`; **WARN** quando reuso detectado (handler/adaptador). | A runtime_api transforma `token_reuse_detected` em evento de segurança. | só `jti`/`family_id`, nunca o token raw. |
| `RefreshTokenPort::revoke_family` | **WARN** com `family_id` (família comprometida). | — | nunca token raw. |
| `TokenBlocklist` | **INFO** com `jti`. | Sem audit_log formal. | só `jti`. |
| `LoginRateLimiter` | **WARN** quando threshold ultrapassado. | — | **nunca** logar credenciais. |

---

### Estado final

Nenhum teste em `apps/data_postgres/src/**` ou `apps/data_redis/src/**` toca o datastore; toda a cobertura real fica em `tests/`. `test-quick.ps1` e `test-local.ps1 -Fast` ficam **100% sem banco/Redis**.

---

## Arquivos-chave

- **Novos:** `apps/data_postgres/src/ports/{mod,whatsapp,audit,...}.rs` e `apps/data_postgres/src/adapters/{mod,whatsapp,audit,...}.rs`; estrutura equivalente em `apps/data_redis/src/ports/` e `apps/data_redis/src/adapters/`.
- **Modificados:** `apps/data_postgres/src/main.rs` (AppState, declaração `mod ports;`/`mod adapters;`, wiring das rotas, assinaturas e corpos dos handlers, `mod tests`), `apps/data_postgres/src/outbox_relay.rs`, `apps/data_redis/src/main.rs`, `server/Cargo.toml` (`mockall` no workspace) e o `Cargo.toml` dos dois apps (async-trait em deps, mockall em dev-deps).
- **Reuso (sem alterar a lógica de SQL):** repositórios em `crates/infrastructure_postgres/src/**` e `crates/infrastructure_redis/src/**`, `run_in_tenant_transaction`, `RequestContext`, `DbError`, `publicar_auditoria`.
- **Integração:** `crates/infrastructure_postgres/tests/integracoes/mod.rs`; novos diretórios `tests/` nos apps quando necessário.

---

## Não-objetivos

- **Não** redesenhar as traits `*Repository` nem o padrão `&mut Transaction`.
- **Não** mexer nos clientes finos — já estão SOLID via RPC.
- **Não** mockar SQL/banco.
- **Não** reescrever testes não tocados pelas fases.
- **Não** introduzir libs novas além de `mockall` (`async-trait`, `tracing`, `secrecy`, `redis` já estão no workspace).

---

## Verificação (por fase)

1. `.\infra\test-quick.ps1 -Pkg data_postgres` (ou `-Pkg data_redis`) → clippy + `--lib --bins` **sem túnel/datastore**.
2. `.\infra\test-local.ps1` (pré-merge) → fmt + clippy + integração com banco/Redis real + `sqlx prepare --check`.
3. Inspeção: `grep` por instanciação concreta (`PostgresWhatsappInstanceRepository`, `RefreshTokenStore::new`) no domínio refatorado deve retornar vazio dentro dos handlers.
4. Confirmar que `cargo test -p <app> --lib --bins` **não** abre o túnel SSH.

---

## Correções Aplicadas (vs plano base + info_aux)

1. **Ordem dos atributos mockall confirmada e aplicada em TODAS as traits.** `doc_dev/libs/rust/mockall.md` §3 (verificado 2026-06-21) confirma: `#[cfg_attr(test, mockall::automock)]` vem **ANTES** de `#[async_trait]`. Aplicado em `WhatsappStore`, `AuditPort` e `RefreshTokenPort`. O retorno assíncrono nos mocks usa `.returning(|...| Box::pin(async { ... }))`, conforme a doc.

2. **`async-trait` já está no `[workspace.dependencies]`** (confirmado em `infrastructure_postgres`/`whatsapp.rs`, `infrastructure_redis`). A Fase 0 foi corrigida: nos apps usa-se `async-trait = { workspace = true }`, sem fixar versão local. Só `mockall` é novidade no workspace.

3. **Nomes/tipos de campos do WhatsApp reconciliados com o código real.** O `info_aux` mencionava `global_api_key`/`instance_token` como `SecretString`. O código atual (`handler_create_whatsapp_instance_record` + struct `WhatsappInstance`) usa os campos do payload **`name`/`api_key`/`provider`**, e `api_key` na struct é `String`. As assinaturas da port `WhatsappStore::criar_instancia(ctx, name, api_key, provider)` seguem o contrato **real** do `WhatsappInstanceRepository::criar`. A diretriz de sanitização foi mantida (não logar `api_key`/`instance_token`); a criptografia em repouso permanece responsabilidade do repositório/`CipherManager` (que já está no `AppState`), sem alterar SQL.

4. **`AuditPort` modelada sobre a função real `publicar_auditoria`** (`main.rs:1492`), cuja assinatura é `(&mut ConnectionManager, &Envelope, event: &str, message: String, context: serde_json::Value)`. A port `AuditPort::publish` espelha exatamente esses parâmetros (menos a conexão, que fica no adapter). O adapter clona o `ConnectionManager` (clonável/barato, doc `redis.md`) por chamada.

5. **`admin_listar_conectadas` preserva o caminho admin_pool/BYPASSRLS** que existe hoje no handler `handler_admin_list_all_connected_instances` (warn quando `admin_pool` ausente) — movido para dentro do adapter, mantendo a degradação observável.

6. **Colisão de nomes na Fase D resolvida.** Já existe `infrastructure_redis::RefreshTokenStore` (struct concreta). Para não criar ambiguidade, a **port** foi renomeada para **`RefreshTokenPort`** (o plano base sugeria reusar o nome `RefreshTokenStore`). O adapter `RedisRefreshTokenStore` reusa a struct concreta `infrastructure_redis::RefreshTokenStore::new(conn)` internamente — exatamente como os handlers fazem hoje (`main.rs:204/242/286`).

7. **Mapeamento de erro de reuso de token preservado.** O handler `validate_and_rotate` mantém a tradução `RedisError::TokenReuse → AppError::Auth("token_reuse_detected")` que já existe (`data_redis/src/main.rs:258`), agora coberta por teste unitário fail-closed com mock.

8. **`#[instrument]` ajustado à política do projeto:** `skip_all` + `fields(...)` de correlação nos adapters (onde há I/O e contexto de tenant), **não** nos handlers; sem `#[instrument(err)]` em handlers (cujos erros incluem validação esperada). Sem `println!`.

9. **Testes unitários seguem a skill `test-rust`:** padrão AAA explícito, um Act por teste, nomes em inglês comportamentais, comentários pt-br, `#[tokio::test]`, validação da **variante** do erro (não `is_err()`), e `.never()` para garantir fail-closed (port não chamada em payload inválido).
