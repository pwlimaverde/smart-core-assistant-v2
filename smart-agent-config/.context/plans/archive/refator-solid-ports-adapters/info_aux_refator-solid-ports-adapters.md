# Documentação Auxiliar — Refator SOLID (Ports & Adapters)

> Gerado em: 2026-06-21
> Plano canônico: `.context/plans/refator-solid-ports-adapters.md`
> Plano completo: `.context/plans/refator-solid-ports-adapters/plano_completo_refator-solid-ports-adapters.md`

---

## Grupo A — Libs Rust

### Triagem da Central Local (`doc_dev/libs/rust/`)

| Lib | Versão no workspace | Doc local | Status | Ação |
|-----|---------------------|-----------|--------|------|
| `async-trait` | 0.1.83 | `doc_dev/libs/rust/async_trait.md` | ✅ ATUALIZADA (2026-06-01) | USAR LOCAL |
| `tracing` | 0.1.40 | `doc_dev/libs/rust/tracing.md` | ✅ ATUALIZADA (2026-05-31) | USAR LOCAL |
| `secrecy` | 0.10.3 | `doc_dev/libs/rust/secrecy.md` | ✅ ATUALIZADA (2026-06-01) | USAR LOCAL |
| `redis` | 0.25.0 | `doc_dev/libs/rust/redis.md` | ✅ ATUALIZADA (2026-06-10) | USAR LOCAL |
| `mockall` | 0.13 (NEW) | `doc_dev/libs/rust/mockall.md` | ✅ CRIADA (2026-06-21) | CRIAR → Context7 |

---

### async-trait (0.1.83)
> Fonte: `doc_dev/libs/rust/async_trait.md`, verificada 2026-06-01

Permite declarar `async fn` em traits de objeto seguro (`dyn Trait`). A macro `#[async_trait]` reescreve cada `async fn` para retornar `Pin<Box<dyn Future + Send>>`.

**Uso crítico no plano:**
- Toda port trait (`WhatsappStore`, `AuditPort`, `CacheStore`, etc.) deve ser decorada com `#[async_trait]`
- A ordem com `mockall` é crítica: `#[cfg_attr(test, mockall::automock)]` ANTES de `#[async_trait]`

```toml
async-trait = "0.1.83"  # já está em [workspace.dependencies]
```

```rust
use async_trait::async_trait;

#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait WhatsappStore: Send + Sync {
    async fn create_instance(&self, ctx: &RequestContext, ...) -> Result<WhatsappInstance, DbError>;
}
```

**Nota:** `async-trait` já está no `[workspace.dependencies]`; apenas adicionar ao `[dependencies]` dos apps que ainda não o têm.

---

### tracing (0.1.40)
> Fonte: `doc_dev/libs/rust/tracing.md`, verificada 2026-05-31

Framework de instrumentação assíncrona. Em produção exporta JSON estruturado (campos: `service`, `env`, `tenant_id`, `trace_id`, `error_code`).

**Política de instrumentação para este plano:**

```rust
// Adapters de tenant: skip_all + campo de correlação manual
#[instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
async fn create_instance(&self, ctx: &RequestContext, ...) -> Result<WhatsappInstance, DbError> {
    // ...
}

// #[instrument(err)] SÓ onde todo erro é falha real de infra (não erros de validação)
```

**Níveis de log por handler:**
- Operações de escrita (create, update, delete): `INFO` na conclusão, `ERROR` em falha de infra
- Operações de leitura: `DEBUG` (sem logar dados sensíveis)
- Operações de segurança (token revoke, rate limit): `WARN` em casos suspeitos

**Proibição:** nunca usar `println!` — sempre `tracing::{info!, debug!, warn!, error!}`.

---

### secrecy (0.10.3)
> Fonte: `doc_dev/libs/rust/secrecy.md`, verificada 2026-06-01

Protege credenciais em memória. `SecretString` implementa `Debug` como `[REDACTED]` e zera na memória no `Drop`.

**Uso obrigatório no plano:**
- `global_api_key` e `instance_token` em structs de criação/atualização de instância WhatsApp
- Tokens JWT e refresh tokens nos handlers de `data_redis`
- Nunca serializar/logar o valor `.expose_secret()`

```rust
use secrecy::SecretString;

pub struct CreateInstanceRequest {
    pub instance_name: String,
    pub global_api_key: SecretString,  // nunca vaza em logs
    pub instance_token: SecretString,
}
```

---

### redis (0.25.0)
> Fonte: `doc_dev/libs/rust/redis.md`, verificada 2026-06-10

`ConnectionManager` é o tipo concreto que os adapters de `data_redis` encapsularão. Os ports (`CacheStore`, `RefreshTokenStore`, etc.) não expõem `ConnectionManager` — apenas tipos de domínio.

```toml
redis = { version = "0.25.0", features = ["aio", "tokio-comp", "connection-manager", "streams"] }
```

---

### mockall (0.13) — NOVO no workspace
> Fonte: `doc_dev/libs/rust/mockall.md`, criada 2026-06-21 via Context7
> Library ID: `/websites/rs_mockall_0_13_1_mockall`

**Padrão para este plano — ordem obrigatória dos atributos:**

```rust
// SEMPRE: #[cfg_attr(test, mockall::automock)] ANTES de #[async_trait]
#[cfg_attr(test, mockall::automock)]
#[async_trait]
pub trait WhatsappStore: Send + Sync {
    async fn create_instance(
        &self,
        ctx: &RequestContext,
        name: &str,
    ) -> Result<WhatsappInstance, DbError>;
}
```

**Uso nos testes:**

```rust
#[tokio::test]
async fn create_instance_rejects_missing_name() {
    // Arrange
    let mut mock_store = MockWhatsappStore::new();
    // mock_store.expect_create_instance() — NÃO configurado: payload inválido não deve chegar ao store
    let mut mock_audit = MockAuditPort::new();
    mock_audit.expect_publish().never();

    let env = build_envelope_sem_nome(); // payload inválido

    // Act
    let resp = handler_create_whatsapp_instance(&mock_store, &mock_audit, env).await;

    // Assert
    assert!(matches!(resp, Envelope::Error { .. }));
}

#[tokio::test]
async fn create_instance_returns_ok_on_success() {
    // Arrange
    let mut mock_store = MockWhatsappStore::new();
    mock_store
        .expect_create_instance()
        .once()
        .returning(|_, _| Box::pin(async { Ok(WhatsappInstance::fake()) }));

    let mut mock_audit = MockAuditPort::new();
    mock_audit.expect_publish().once().return_const(());

    let env = build_envelope_valido();

    // Act
    let resp = handler_create_whatsapp_instance(&mock_store, &mock_audit, env).await;

    // Assert
    assert!(matches!(resp, Envelope::Ok { .. }));
}
```

**Cargo.toml — NOVO no workspace:**

```toml
# apps/data_postgres/Cargo.toml e apps/data_redis/Cargo.toml
[dev-dependencies]
mockall = "0.13"

# workspace Cargo.toml — adicionar:
[workspace.dependencies]
mockall = "0.13"
```

**Gotchas relevantes:**
- Múltiplos `expect_foo()` **adicionam** expectativas (não sobrescrevem) — usar `.checkpoint()` ao final do teste para validar
- Retorno assíncrono requer `Box::pin(async { value })` no `.returning(...)`
- `.never()` para expectativas que NÃO devem ser chamadas (testa fail-closed)

---

## Grupo B — Serviços Externos

**Nenhum.** O plano é um refator interno puro (Ports & Adapters). Não há novas integrações com APIs externas. Os handlers existentes que interagem com WhatsApp, Redis, etc. não mudam suas integrações — apenas a orquestração migra do handler para o adapter.

---

## Grupo C — Observabilidade e Auditoria (por fase)

> Referência normativa: `doc_dev/planejamento/05-observabilidade.md` e `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` §4 e §4.2

### Princípio geral de instrumentação (codebase Rust)

| Contexto | Macro/Padrão | Justificativa |
|----------|-------------|---------------|
| Adapters de tenant (repos via `run_in_tenant_transaction`) | `#[instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]` | Evita logar structs grandes; correlaciona por tenant |
| Handlers RPC (parse + montagem envelope) | `#[instrument(skip_all)]` mínimo | Handlers não são "fronteira de infra real"; erros de validação não disparam `instrument(err)` |
| Erros reais de infra (falha de pool, timeout Redis) | `#[instrument(err)]` ou `error!(error = ?e, ...)` explícito | Só onde todo erro é falha de infra |
| Proibido | `println!`, `dbg!` em produção | Buropassam a infraestrutura Tracing |

### Fase 0 — Dependências (Cargo.toml)
- **Logs/trace:** sem mudança comportamental → sem eventos novos.
- **Auditoria:** sem evento de `audit_log`.
- **Sanitização:** sem código novo.

### Fase 1 — Domínio WhatsApp (data_postgres)

#### `create_whatsapp_instance_record`
- **Log:** `INFO` no adapter após commit bem-sucedido: campos `tenant_id`, `instance_name`; NUNCA `global_api_key`/`instance_token`
- **Auditoria:** Criação de instância WhatsApp altera `TenantConfig` (novo slot de credencial) → **event_type: `whatsapp_instance.created`** com metadados: `user_id` (do `RequestContext`), `tenant_id`, `ip_address`, `user_agent`, `instance_name`. Publicado via `AuditPort::publish` (assíncrono no bus → `data_postgres`).
- **Sanitização:** `global_api_key` e `instance_token` armazenados via `CipherManager::encrypt` ANTES da inserção SQL; campos na struct de request são `SecretString`; `#[instrument(skip_all)]` garante que os fields não vazem no span.

#### `get_whatsapp_instance` / `list_whatsapp_instances` / `admin_list_all_connected_instances`
- **Log:** `DEBUG` com `tenant_id`, count. Sem PII.
- **Auditoria:** Sem evento de `audit_log` (operações de leitura sem dados sensíveis em resultado).
- **Sanitização:** As instâncias retornadas NÃO devem incluir `global_api_key`/`instance_token` em plaintext nos spans/logs; o adapter só retorna o que o `WhatsappInstance` expõe (já controlado pelo repositório).

#### `admin_deletar_instancia`
- **Log:** `WARN` com `instance_id`, `tenant_id` (operação destrutiva).
- **Auditoria:** **event_type: `whatsapp_instance.deleted`** com metadados completos.
- **Sanitização:** sem segredos no log.

#### `atualizar_estado_instancia` / `atualizar_instancia_provider_id`
- **Log:** `DEBUG` com `instance_id`, `new_state`/`provider_id`.
- **Auditoria:** `whatsapp_instance.state_updated` / `whatsapp_instance.provider_updated`.
- **Sanitização:** sem segredos.

#### `AuditPort` (trait de auditoria)
- **Log:** sem log próprio (evita recursão); o adapter `RedisAuditPort` pode emitir `ERROR` se a publicação no bus falhar.
- **Auditoria:** sem evento de `audit_log` próprio (é a fronteira que publica os eventos).
- **Sanitização:** `AuditPort::publish` recebe `description` já sanitizada (sem segredos) — responsabilidade do caller.

### Fase D — data_redis

#### `RefreshTokenStore::store` / `validate_and_rotate` / `revoke_family`
- **Log:** `DEBUG` para store/rotate; `WARN` para revoke_family (família comprometida é evento de segurança).
- **Auditoria:** `revoke_family` → log de segurança (via tracing WARN + campo `reason`); sem `audit_log` formal para operações de rotação ordinária.
- **Sanitização:** Token nunca logado; apenas `jti` (JWT ID, não sensível) pode aparecer em logs.

#### `TokenBlocklist::block`
- **Log:** `INFO` com `jti` (nunca o token raw).
- **Auditoria:** sem `audit_log` (operação de infraestrutura de segurança; o bloqueio de sessão já é reflexo de evento auditado pela camada de autenticação).
- **Sanitização:** nunca logar o token; apenas o `jti`.

#### `LoginRateLimiter::register_login_attempt`
- **Log:** `DEBUG` para tentativa normal; `WARN` quando threshold ultrapassado (campos: `tenant_id`, `user_id`/`ip`, count).
- **Auditoria:** sem evento de `audit_log` formal (é métrica de segurança operacional, não mudança de estado de negócio).
- **Sanitização:** nunca logar credenciais; apenas identificadores de sessão/IP (parcialmente mascarados se PII).

### Fases 2..N — Rollout data_postgres

Padrão idêntico à Fase 1 por domínio. Eventos críticos adicionais:
- `TenantStore` (create/update/delete Tenant): **event_type: `tenant.created`**, `tenant.owner_changed`** → auditoria obrigatória (§4.2)
- `AuthStore` (invites, role changes): **event_type: `tenant_invite.created`**, `tenant_user.role_changed`** → auditoria obrigatória
- `PlansStore` (Subscription/PaymentRecord): **event_type: `subscription.updated`**, `payment.inserted`** → auditoria obrigatória

---

## Notas Gerais e Breaking Changes

- `mockall` 0.13 é **novo no workspace** — adicionar em `[workspace.dependencies]` do `server/Cargo.toml` além dos `[dev-dependencies]` dos apps.
- `async-trait` já é dependência de workspace; apenas adicionar nos `[dependencies]` de `data_postgres` e `data_redis` (que hoje não o declaram explicitamente).
- Nenhuma breaking change de `mockall 0.12 → 0.13` documentada — a API é compatível.
- O padrão `#[cfg_attr(test, mockall::automock)]` (não `#[automock]` diretamente) é o correto para ports: elimina a dependência de `mockall` de builds de produção, mesmo sem feature-gating explícito.
