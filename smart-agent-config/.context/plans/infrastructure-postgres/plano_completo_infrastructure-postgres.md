# Plano Completo — Fundação `infrastructure_postgres`

> Reestruturado em: 2026-06-01
> Feature: `infrastructure-postgres`
> Documentação auxiliar (libs atuais): `./info_aux_infrastructure-postgres.md`
> Fonte da verdade do schema: `smart-agent-config/doc_dev/modelagem_dados/` (01..09, `modulo_central_banco.md`, `estrategia_implementacao_rust.md`, `gerenciamento_configuracoes_ia.md`)
> Workflow: **PREVC** (Planning → Review → Execution → Validation → Confirmation)

## Escopo

**Dentro do escopo (FUNDAÇÃO):**
- Cargo workspace em `server/` (na raiz do repo).
- Crate `infrastructure_postgres` de ponta a ponta:
  - Migrations `0001..0009` com RLS (`ENABLE` + `FORCE` + `POLICY`).
  - Modelos/structs por domínio (campos exatos dos docs de modelagem).
  - Traits `*Repository` + implementações `Postgres*Repository` (SQLx).
  - `run_in_tenant_transaction` + `inicializar_banco_dados`.
  - `TenantConfigCache` (DashMap) + `RuntimeConfig`.
  - `CipherManager` (AES-256-GCM).
  - `DbError`, `RequestContext`.
  - Busca vetorial pgvector (`<=>` cosseno, índice HNSW).
- Modo SQLx **OFFLINE**: `.sqlx/` versionado + migrations aplicadas no Postgres real via túnel SSH.

**Fora do escopo (fases futuras):**
- `infrastructure_redis`, crate `application`, binários `apps/` (`control_plane`, `runtime_api`, `worker`).
- Middleware HTTP/JWT, gRPC `ia_engine`, publicação Redis Pub/Sub.
- Tabela `audit_log` (migração futura dedicada — ver `08_diretrizes_seguranca.md` §4.2).

## Arquitetura (invariantes obrigatórias)

1. **Banco PostgreSQL único + pgvector**, isolamento por **Row-Level Security (RLS)**.
2. **Pool global único** (`PgPool`); nunca múltiplos pools por tenant.
3. `infrastructure_postgres` é a **única** crate com acesso a SQLx.
4. Padrão **Repository**: trait + impl Postgres por entidade; **um arquivo por domínio**.
5. **`tenant_id` explícito** em toda query de tabela de tenant (dupla barreira: RLS + `WHERE tenant_id = $1`).
6. Role da app `smartcore_app` é **`NOBYPASSRLS`**; tabelas usam `ENABLE` + `FORCE ROW LEVEL SECURITY`.
7. Sem libs novas além das listadas no `info_aux`. Comentários de código em **pt-br**.

---

# FASES (mapeadas ao PREVC)

| Fase PREVC | Objetivo | Agente sugerido |
| --- | --- | --- |
| **P — Planning** | Consolidar schema, decisões de libs e correções; este plano. | **Database Specialist** |
| **R — Review** | Validar approach: RLS via `set_config`, modelagem das structs, índices HNSW, segurança (RLS/cripto/secrecy). | **Backend Specialist** (apoio: Security Reviewer) |
| **E — Execution** | Implementar workspace + crate completa (sub-etapas a..e abaixo). | **Backend Specialist** (apoio: Database Specialist nas migrations) |
| **V — Validation** | Túnel → `migrate run` → validar RLS → `sqlx prepare` → build offline → testes de integração → clippy/fmt. | **Test Writer** (apoio: Backend Specialist) |
| **C — Confirmation** | `final-review` (auditoria vs. plano), commit gitflow, arquivamento. | **Backend Specialist** |

---

## FASE P — Planning (Database Specialist)

**Saídas:** este plano + `info_aux_infrastructure-postgres.md` (libs atuais).

**Decisões fechadas (detalhadas na seção "Correções aplicadas"):**
- RLS ativado por `SELECT set_config('app.current_tenant', $1, true)` (NÃO `SET LOCAL = $1`).
- `auth_user` mínima (global, sem RLS) criada na `0001` (FKs do legado Django).
- `secrecy::SecretString` para chaves de API em runtime; feature `serde` só na ponte Redis (fase futura).
- Índice HNSW `vector_cosine_ops` em `oraculo_documento.embedding` e `treinamento_querycompose.embedding`.
- `oraculo_app_instance` (AppInstance) e `evolution_sync_instance` (EvolutionInstance) são tabelas distintas e coexistem.
- base64 0.22: `engine::general_purpose::STANDARD` + trait `Engine` (sem `base64::encode/decode` global).
- DashMap como cache de `RuntimeConfig` (`DashMap<Uuid, Arc<RuntimeConfig>>`), não pools por tenant.

---

## FASE R — Review (Backend Specialist + Security Reviewer)

Checklist de aprovação antes de codar:

- [ ] `run_in_tenant_transaction` usa `set_config(..., true)` (transação-local) e bind por `tenant_id` (`Uuid` via sqlx; o driver serializa para texto).
- [ ] Toda tabela de tenant: `ENABLE` + `FORCE ROW LEVEL SECURITY` + `POLICY ... USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)`.
- [ ] Tabelas globais sem RLS: `auth_user`, `tenants_plan`, `settings_manager_coresettings`.
- [ ] Structs mapeiam **exatamente** colunas dos docs (tipos: `Uuid`, `i32`/`i64`, `String`/`Option<String>`, `DateTime<Utc>`, `Decimal`, `serde_json::Value`, `Option<Vector>`).
- [ ] Busca vetorial com `tenant_id = $N` explícito + dimensão fixa `vector(1536)`.
- [ ] `CipherManager` com nonce 96 bits via `OsRng`; ciphertext/nonce/tag em base64 no JSONB `api_keys`.
- [ ] `RuntimeConfig` carrega chaves como `SecretString`; nada de chave em log/`Debug`.
- [ ] Validação de escopo (`ctx.has_permission(...)`) nos repos de escrita.
- [ ] Features SQLx mínimas necessárias; modo offline garantido por `.sqlx/`.

---

## FASE E — Execution (Backend Specialist + Database Specialist)

### (a) Scaffold do workspace

Criar em `server/`:

**`server/Cargo.toml`** (workspace virtual):
```toml
[workspace]
resolver = "2"
members = ["crates/infrastructure_postgres"]

[workspace.package]
edition = "2021"
license = "Proprietary"

[workspace.dependencies]
sqlx = { version = "0.8.2", features = [
    "postgres", "runtime-tokio-rustls", "macros",
    "migrate", "uuid", "chrono", "rust_decimal", "json",
] }
pgvector = { version = "0.4.0", features = ["sqlx"] }
dashmap = "6.1.0"
aes-gcm = "0.10.3"
rust_decimal = { version = "1.36.0", features = ["serde-with-str"] }
chrono = { version = "0.4.38", features = ["serde"] }
serde = { version = "1.0.219", features = ["derive"] }
serde_json = "1.0.219"
thiserror = "1.0"
tokio = { version = "1.38", features = ["full"] }
tracing = "0.1.40"
uuid = { version = "1.10.0", features = ["v4", "serde"] }
async-trait = "0.1.83"
base64 = "0.22.1"
secrecy = "0.10.3"
```

**`server/crates/infrastructure_postgres/Cargo.toml`**:
```toml
[package]
name = "infrastructure_postgres"
version = "0.1.0"
edition.workspace = true

[dependencies]
sqlx.workspace = true
pgvector.workspace = true
dashmap.workspace = true
aes-gcm.workspace = true
rust_decimal.workspace = true
chrono.workspace = true
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
tokio.workspace = true
tracing.workspace = true
uuid.workspace = true
async-trait.workspace = true
base64.workspace = true
secrecy.workspace = true

[dev-dependencies]
tokio = { version = "1.38", features = ["macros", "rt-multi-thread"] }
```

Arquivos de apoio:
- `server/.gitignore` — não ignorar `.sqlx/` (deve ser versionado); ignorar `target/`.
- `server/.env` (local, não versionado) com `DATABASE_URL` apontando para o túnel.
- `server/rust-toolchain.toml` (opcional) fixando a toolchain estável.

> **Nota de ambiente:** o `.env.example` da raiz usa `localhost:5434` para `DATABASE_URL`, enquanto `infra/tunnel.ps1` mapeia `localhost:5432`. Alinhar a porta do `server/.env` ao túnel efetivamente aberto antes de rodar migrations/prepare.

Estrutura de diretórios (de `modulo_central_banco.md` §2):
```
server/crates/infrastructure_postgres/
├── Cargo.toml
├── .sqlx/                      # gerado por `cargo sqlx prepare` (VERSIONADO)
├── migrations/                 # 0001..0009
└── src/
    ├── lib.rs
    ├── errors.rs
    ├── connection.rs
    ├── security.rs
    ├── crypto.rs
    ├── config_cache.rs
    ├── tenants/   {mod.rs, tenants.rs, plans.rs, config.rs, settings.rs}
    ├── clientes/  {mod.rs, contatos.rs, clientes.rs}
    ├── operacional/ {mod.rs, departamentos.rs, atendentes.rs, fluxos.rs}
    ├── atendimentos/ {mod.rs, atendimentos.rs, mensagens.rs, movimentos.rs, campos.rs}
    ├── treinamento/ {mod.rs, treinamentos.rs, documentos.rs, query_compose.rs}
    └── integracoes/ {mod.rs, evolution.rs, whitelist.rs}
```

---

### (b) Migrations SQL `0001..0009`

**Padrão RLS exato** (aplicar em TODA tabela com `tenant_id`):
```sql
ALTER TABLE <tabela> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <tabela> FORCE  ROW LEVEL SECURITY;
CREATE POLICY <tabela>_tenant_isolation ON <tabela>
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
```
Por que `NULLIF(current_setting(..., true), '')`: o segundo argumento `true` (`missing_ok`) evita erro quando a variável não está setada; `NULLIF(..,'')` transforma string vazia em `NULL`, fazendo a policy negar tudo (fail-closed) quando o contexto não foi configurado.

#### `0001_create_rls_function.sql` — base
- `CREATE EXTENSION IF NOT EXISTS vector;` e `"uuid-ossp"` (idempotente; já criadas pelo init-script, mas garantir na migration).
- **Tabela global `auth_user`** (mínima, sem RLS) — alvo das FKs do legado:
  - `id` SERIAL PK, `username` VARCHAR(150) UNIQUE NOT NULL, `email` VARCHAR(254), `is_active` BOOLEAN DEFAULT true, `date_joined` TIMESTAMPTZ DEFAULT NOW().
- (Opcional documentado, NÃO executado pela app) bloco de criação da role `smartcore_app NOBYPASSRLS` + GRANTs — fica como comentário/script à parte porque migrations rodam com o owner; a role é provisionada na infra. Referência: `08_diretrizes_seguranca.md` §1.2/§1.3.

#### `0002_tenants.sql` — `tenants_tenant`, `tenants_tenantconfig`, `tenants_tenantuser`, `tenants_tenantinvite`
- `tenants_tenant` (PK `id` UUID DEFAULT uuid_generate_v4()): `name`, `slug` UNIQUE, `api_key` UNIQUE, `owner_id` INT FK→auth_user, `email`, `phone`, `active`, `setup_completed`, `onboarding_step`, `access_code`, `created_at`, `updated_at`.
  - **Observação RLS:** `tenants_tenant` tem PK `id` (não `tenant_id`). Política especial: `USING (id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)`.
- `tenants_tenantconfig` (campos completos no item (c)/RuntimeConfig). FK `tenant_id` UUID UNIQUE → tenant; RLS por `tenant_id`.
- `tenants_tenantuser`: `id` SERIAL, `user_id` INT UNIQUE FK→auth_user, `tenant_id` UUID FK, `role`, `module_permissions` JSONB, `flow_permissions` JSONB, `is_active`, `created_at`, `created_by_id`. RLS por `tenant_id`.
- `tenants_tenantinvite`: `id` UUID PK, `tenant_id` UUID, `email`, `name`, `role`, `module_permissions` JSONB, `flow_permissions` JSONB, `token` VARCHAR(64) UNIQUE, `expires_at`, `used`, `created_at`, `created_by_id`. RLS por `tenant_id`.

#### `0003_plans_subscriptions.sql` — `tenants_plan` (GLOBAL), `tenants_subscription`, `tenants_paymentrecord`
- `tenants_plan` **sem RLS** (global): `id` SERIAL, `name`, `description`, `price` NUMERIC(10,2), `max_instances`, `max_departments`, `active`, `created_at`.
- `tenants_subscription`: `id` SERIAL, `tenant_id` UUID UNIQUE FK, `plan_id` INT FK→plan (ON DELETE RESTRICT), `status` VARCHAR(20) DEFAULT 'ACTIVE', `current_period_start/end`, `payment_gateway`, `external_customer_id`, `external_subscription_id`, `updated_at`. RLS por `tenant_id`.
- `tenants_paymentrecord`: `id` SERIAL, `tenant_id` UUID FK, `amount` NUMERIC(10,2), `payment_date` DATE, `payment_method` VARCHAR(20), `period_start` DATE, `period_end` DATE, `notes`, `recorded_by_id` INT FK→auth_user, `created_at`. RLS por `tenant_id`.

#### `0004_clientes_contatos.sql` — `oraculo_contato`, `oraculo_cliente`, `oraculo_cliente_contatos`
- `oraculo_contato`: `id` SERIAL, `tenant_id` UUID, `telefone` VARCHAR(20), `nome_contato`, `slug`, `email`, `nome_perfil_whatsapp`, `data_cadastro` TIMESTAMPTZ, `ultima_interacao` TIMESTAMPTZ, `ativo`, `metadados` JSONB DEFAULT '{}', `foto_perfil`, `foto_perfil_url_origem`. **UNIQUE (tenant_id, telefone)**. RLS.
- `oraculo_cliente`: `id` SERIAL, `tenant_id` UUID, `nome_fantasia` VARCHAR(200) NOT NULL, `slug`, `razao_social`, `tipo`, `cnpj`, `cpf`, `telefone`, `site`, `ramo_atividade`, `observacoes`, `cep`, `logradouro`, `numero`, `complemento`, `bairro`, `cidade`, `uf` VARCHAR(2), `pais` DEFAULT 'Brasil', `data_cadastro`, `ultima_atualizacao`, `ativo`, `metadados` JSONB. UNIQUE parcial (tenant_id, cnpj)/(tenant_id, cpf) quando preenchidos. RLS.
- `oraculo_cliente_contatos` (M2M): `id` SERIAL, `tenant_id` UUID, `cliente_id` INT FK, `contato_id` INT FK, UNIQUE (cliente_id, contato_id). RLS.

#### `0005_operacional.sql` — `oraculo_departamento`, `oraculo_fluxo_atendimento`, `oraculo_etapa_fluxo`, `oraculo_atendente`, `oraculo_app_instance`
> Ordem de criação por dependência de FK: departamento → fluxo → etapa → atendente → app_instance.
- `oraculo_departamento`: `id` SERIAL, `tenant_id`, `nome` VARCHAR(100), `slug`, `descricao`, `ativo`, `telefone_instancia`, `api_key`, `configuracoes` JSONB, `metadados` JSONB, `data_criacao`. UNIQUE (tenant_id, nome), (tenant_id, slug). Índices conforme doc. RLS.
- `oraculo_fluxo_atendimento`: `id` SERIAL, `tenant_id`, `departamento_id` INT FK, `nome`, `descricao`, `ativo`, `data_criacao`, `data_atualizacao`. RLS.
- `oraculo_etapa_fluxo`: `id` SERIAL, `tenant_id`, `fluxo_id` INT FK, `nome` VARCHAR(50), `descricao` VARCHAR(200), `ordem` INT NOT NULL, `cor` VARCHAR(7) DEFAULT '#6B7280', `tipo_etapa` VARCHAR(20) DEFAULT 'trabalho', `permite_atribuicao`, `automatico`, `regras_transicao` JSONB, `campos_obrigatorios` JSONB, `ativo`, `data_criacao`. UNIQUE (fluxo_id, ordem). RLS.
- `oraculo_atendente`: `id` SERIAL, `tenant_id`, `nome`, `slug`, `telefone`, `cargo`, `email`, `departamento_id` INT FK NULL, `fluxo_id` INT FK (ON DELETE RESTRICT), `usuario_id` INT (sem FK física — `db_constraint=False`), `usuario_sistema`, `ativo`, `disponivel`, `max_atendimentos_simultaneos` DEFAULT 5, `data_ultima_atribuicao`, `horario_trabalho` JSONB, `especialidades` JSONB, `metadados` JSONB, `data_cadastro`, `ultima_atividade`. UNIQUE (tenant_id, email), (tenant_id, telefone). RLS.
- `oraculo_app_instance`: `id` SERIAL, `tenant_id`, `api_key` VARCHAR(128) UNIQUE, `channel` VARCHAR(32), `display_name`, `departamento_id` INT FK NULL, `owner_id` INT FK→atendente NULL UNIQUE, `active`, `resposta_bot`, `metadata` JSONB, `created_at`. RLS.

#### `0006_atendimentos.sql` — `oraculo_atendimento`, `oraculo_mensagem`, `oraculo_movimento_fluxo`, `atu_campo_personalizado`, `atu_valor_campo`, `atu_etiqueta`, `atu_etiqueta_atendimento`, `atu_nota`
- `oraculo_atendimento`: `id` SERIAL, `tenant_id`, `contato_id` INT FK, `departamento_id` INT FK NULL, `fluxo_atendimento_id` INT FK NULL, `status` VARCHAR(20) DEFAULT 'fila', `etapa_atual_id` INT FK NULL, `data_inicio`, `data_fim`, `data_ultima_mensagem`, `assunto`, `prioridade` VARCHAR(10) DEFAULT 'normal', `atendente_humano_id` INT FK NULL, `contexto_conversa` JSONB, `historico_status` JSONB DEFAULT '[]', `tags` JSONB DEFAULT '[]', `avaliacao` INT NULL, `feedback`, `data_primeira_resposta`, `bot_pode_atender` BOOLEAN DEFAULT true. RLS.
- `oraculo_mensagem`: `id` SERIAL, `tenant_id`, `atendimento_id` INT FK, `tipo` VARCHAR(25) DEFAULT 'extendedTextMessage', `conteudo` TEXT, `remetente` VARCHAR(20) DEFAULT 'contato', `timestamp` TIMESTAMPTZ, `message_id_whatsapp`, `metadados` JSONB, `respondida`, `lido`, `resposta_bot`, `intent_detectado` JSONB DEFAULT '[]', `entidades_extraidas` JSONB DEFAULT '[]', `confianca_resposta` FLOAT NULL, `arquivo_midia`, `analise_midia`, `resumo_midia`, `mensagem_citada_id` INT FK→self NULL, `quoted_preview` JSONB NULL, `status_envio` VARCHAR(15) DEFAULT 'pending', `data_entregue`, `data_lida`. RLS.
- `oraculo_movimento_fluxo`: `id` SERIAL, `tenant_id`, `atendimento_id` INT FK, `etapa_origem_id` INT FK NULL, `etapa_destino_id` INT FK, `atendente_origem_id` INT FK NULL, `atendente_destino_id` INT FK NULL, `motivo`, `dados_complementares` JSONB, `automatico`, `data_movimento`, `duracao_segundos` INT NULL. RLS.
- `atu_campo_personalizado`: `id` BIGSERIAL, `tenant_id`, `slug`, `nome` VARCHAR(120), `descricao`, `escopo` VARCHAR(10) DEFAULT 'GLOBAL', `fluxo_id` INT FK NULL, `tipo` VARCHAR(20) DEFAULT 'texto', `opcoes` JSONB, `obrigatorio`, `extrair_automaticamente`, `extrair_hint`, `mostrar_no_card`, `ordem`, `ativo`, `data_criacao`, `data_atualizacao`. UNIQUE (tenant_id, slug, escopo, fluxo_id). RLS.
- `atu_valor_campo`: `id` BIGSERIAL, `tenant_id`, `atendimento_id` INT FK, `campo_id` BIGINT FK, `valor` JSONB NOT NULL, `origem` VARCHAR(10) DEFAULT 'MANUAL', `confianca` FLOAT NULL, `mensagem_origem_id` INT FK NULL, `editado_por_id` INT FK NULL, `data_atualizacao`. UNIQUE (tenant_id, atendimento_id, campo_id). RLS.
- `atu_etiqueta`: `id` BIGSERIAL, `tenant_id`, `nome` VARCHAR(50), `cor` VARCHAR(7) DEFAULT '#a98f71', `descricao`, `ativo`, `data_criacao`. UNIQUE (tenant_id, nome). RLS.
- `atu_etiqueta_atendimento`: `id` BIGSERIAL, `tenant_id`, `atendimento_id` INT FK, `etiqueta_id` BIGINT FK, `aplicada_em`, `aplicada_por_id` INT FK NULL. UNIQUE (tenant_id, atendimento_id, etiqueta_id). RLS.
- `atu_nota`: `id` BIGSERIAL, `tenant_id`, `atendimento_id` INT FK, `texto` TEXT NOT NULL, `criado_por_id` INT FK NULL, `criado_em`. RLS.

#### `0007_treinamento_rag.sql` — `oraculo_treinamento`, `oraculo_documento`, `treinamento_query_test_feedback`, `treinamento_querycompose`
- `oraculo_treinamento`: `id` SERIAL, `tenant_id`, `tag` VARCHAR(40), `grupo` VARCHAR(40), `conteudo`, `treinamento_finalizado`, `treinamento_vetorizado`, `data_criacao`, `data_atualizacao`. UNIQUE (tenant_id, tag, grupo). RLS.
- `oraculo_documento`: `id` SERIAL, `tenant_id`, `treinamento_id` INT FK, `conteudo`, `metadata` JSONB, `embedding` **VECTOR(1536)** NULL, `ordem` INT DEFAULT 1, `data_criacao`. RLS.
  - Índice HNSW: `CREATE INDEX oraculo_documento_embedding_hnsw ON oraculo_documento USING hnsw (embedding vector_cosine_ops);`
  - Índice B-tree: `(tenant_id, treinamento_id, ordem)`.
- `treinamento_query_test_feedback`: `id` SERIAL, `tenant_id`, `mensagem_original` TEXT, `resposta_bot` TEXT, `resposta_corrigida`, `avaliacao` VARCHAR(10), `confiabilidade` FLOAT DEFAULT 0.0, `entidades_json` JSONB, `intents_json` JSONB, `documentos_ids` JSONB DEFAULT '[]', `created_at`. RLS.
- `treinamento_querycompose`: `id` SERIAL, `tenant_id`, `tag` VARCHAR(40), `grupo` VARCHAR(40), `descricao` TEXT, `exemplo` TEXT, `comportamento` TEXT, `embedding` **VECTOR(1536)** NULL, `created_at`, `updated_at`. UNIQUE (tenant_id, tag, grupo). RLS.
  - Índice HNSW: `... USING hnsw (embedding vector_cosine_ops);`
  - Índice B-tree: `(tenant_id, tag)`.

#### `0008_evolution_sync.sql` — `evolution_sync_instance`, `evolution_sync_contact`, `evolution_sync_whitelist`
- `evolution_sync_instance`: `id` SERIAL, `tenant_id`, `name` VARCHAR(100), `instance_id` VARCHAR(100) UNIQUE NULL, `api_key` VARCHAR(256), `phone_number`, `active`, `connection_state` VARCHAR(20) DEFAULT 'unknown', `last_state_check`, `media_storage_backend` VARCHAR(10) DEFAULT 's3', `subscribed_events` JSONB DEFAULT '[]', `last_connection_state`, `created_at`. UNIQUE (tenant_id, name). RLS.
- `evolution_sync_contact`: `id` SERIAL, `tenant_id`, `contact_id` INT FK→oraculo_contato NULL, `instance_id` INT FK→evolution_sync_instance, `jid`, `lid`, `addressing_mode`, `active`, `metadados` JSONB, `created_at`, `updated_at`. UNIQUE (tenant_id, instance_id, jid). RLS.
- `evolution_sync_whitelist`: `id` SERIAL, `tenant_id`, `contact_id` INT FK NULL, `name` VARCHAR(100), `phone_number` VARCHAR(20), `active`, `created_at`. UNIQUE (tenant_id, phone_number). RLS.

#### `0009_settings_manager.sql` — `settings_manager_coresettings` (GLOBAL, sem RLS)
- `id` SERIAL, `key` VARCHAR(255) UNIQUE NOT NULL, `value` TEXT NOT NULL, `encrypted` BOOLEAN DEFAULT false, `description` TEXT, `created_at`, `updated_at`.

---

### (c) Núcleo (`errors` / `connection` / `security` / `crypto` / `config_cache`)

#### `errors.rs` — `DbError`
```rust
use thiserror::Error;

/// Erros da camada de persistência. Único enum de erro exposto pela crate.
#[derive(Debug, Error)]
pub enum DbError {
    #[error("erro do banco de dados: {0}")]
    SqlxError(#[from] sqlx::Error),

    #[error("erro de migração: {0}")]
    MigrateError(#[from] sqlx::migrate::MigrateError),

    #[error("permissão negada para a operação solicitada")]
    PermissionDenied,

    #[error("registro não encontrado")]
    NotFound,

    #[error("violação de restrição de unicidade: {0}")]
    UniqueViolation(String),

    #[error("erro de criptografia: {0}")]
    CryptoError(String),

    #[error("erro de configuração: {0}")]
    ConfigError(String),
}
```

#### `connection.rs` — `run_in_tenant_transaction` + `inicializar_banco_dados`
> **CORREÇÃO CRÍTICA vs. docs:** `SET LOCAL app.current_tenant = $1` NÃO funciona (o comando `SET` não aceita bind via prepared statement). Substituir por `set_config(..., true)`.
```rust
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;
use crate::errors::DbError;

/// Executa um bloco sob transação com o contexto de RLS do tenant configurado.
/// É a ÚNICA forma de executar queries em tabelas isoladas por tenant.
pub async fn run_in_tenant_transaction<F, T, Fut>(
    pool: &PgPool,
    tenant_id: Uuid,
    callback: F,
) -> Result<T, DbError>
where
    F: FnOnce(Transaction<'_, Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<(T, Transaction<'_, Postgres>), DbError>>,
{
    let mut tx = pool.begin().await?;

    // RLS local à transação. set_config(..., true) = escopo transação (equivale a SET LOCAL),
    // mas aceita bind do tenant_id (o SET clássico não aceita placeholders).
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant_id.to_string())
        .execute(&mut *tx)
        .await?;

    let (result, tx_final) = callback(tx).await?;
    tx_final.commit().await?;
    Ok(result)
}

/// Aplica as migrations embutidas na inicialização da aplicação.
pub async fn inicializar_banco_dados(pool: &PgPool) -> Result<(), DbError> {
    sqlx::migrate!("./migrations").run(pool).await?;
    Ok(())
}
```

#### `security.rs` — `RequestContext`
```rust
use uuid::Uuid;

/// Contexto de requisição com escopo do usuário e do tenant.
#[derive(Debug, Clone)]
pub struct RequestContext {
    pub tenant_id: Uuid,
    pub user_id: i32,
    pub user_scopes: Vec<String>,
    /// IDs de FluxoAtendimento permitidos (carregado do TenantUser no middleware JWT).
    pub flow_permissions: Vec<i32>,
}

impl RequestContext {
    pub fn has_permission(&self, permission: &str) -> bool {
        self.user_scopes.iter().any(|p| p == permission)
    }

    pub fn has_flow_permission(&self, flow_id: i32) -> bool {
        self.flow_permissions.contains(&flow_id)
    }
}
```

#### `crypto.rs` — `CipherManager` (AES-256-GCM, base64 0.22)
> **CORREÇÃO vs. base64 antigo:** `base64::encode/decode` globais foram removidas em 0.22. Usar `engine::general_purpose::STANDARD` + trait `Engine`.
```rust
use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use crate::errors::DbError;

/// Gerencia criptografia simétrica AES-256-GCM das chaves de API em repouso.
pub struct CipherManager {
    key: [u8; 32],
}

impl CipherManager {
    /// Carrega a chave mestra de 32 bytes da variável de ambiente ENCRYPTION_KEY (base64).
    pub fn new_from_env() -> Result<Self, DbError> {
        let key_str = std::env::var("ENCRYPTION_KEY")
            .map_err(|_| DbError::ConfigError("ENCRYPTION_KEY não configurada".into()))?;
        let key_bytes = BASE64
            .decode(key_str.trim())
            .map_err(|_| DbError::CryptoError("ENCRYPTION_KEY inválida (base64)".into()))?;
        if key_bytes.len() != 32 {
            return Err(DbError::CryptoError("a chave mestra precisa ter 32 bytes".into()));
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(&key_bytes);
        Ok(Self { key })
    }

    /// Retorna (ciphertext_b64, nonce_b64, tag_b64). Nonce de 96 bits via OsRng.
    pub fn encrypt(&self, plaintext: &[u8]) -> Result<(String, String, String), DbError> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| DbError::CryptoError("falha ao inicializar AES-GCM".into()))?;
        let nonce = Aes256Gcm::generate_nonce(&mut OsRng);
        let ct_tag = cipher
            .encrypt(&nonce, plaintext)
            .map_err(|_| DbError::CryptoError("falha na encriptação".into()))?;
        let (ct, tag) = ct_tag.split_at(ct_tag.len() - 16);
        Ok((BASE64.encode(ct), BASE64.encode(nonce), BASE64.encode(tag)))
    }

    /// Descriptografa a partir dos três componentes base64.
    pub fn decrypt(&self, ct_b64: &str, nonce_b64: &str, tag_b64: &str) -> Result<Vec<u8>, DbError> {
        let cipher = Aes256Gcm::new_from_slice(&self.key)
            .map_err(|_| DbError::CryptoError("falha ao inicializar AES-GCM".into()))?;
        let ct = BASE64.decode(ct_b64).map_err(|_| DbError::CryptoError("ciphertext inválido".into()))?;
        let nonce_bytes = BASE64.decode(nonce_b64).map_err(|_| DbError::CryptoError("nonce inválido".into()))?;
        let tag = BASE64.decode(tag_b64).map_err(|_| DbError::CryptoError("tag inválida".into()))?;
        let nonce = Nonce::from_slice(&nonce_bytes);
        let mut ct_tag = ct;
        ct_tag.extend_from_slice(&tag);
        cipher
            .decrypt(nonce, ct_tag.as_slice())
            .map_err(|_| DbError::CryptoError("integridade violada ou chave inválida".into()))
    }
}
```

#### `config_cache.rs` — `TenantConfigCache` (DashMap) + `RuntimeConfig`
> **CORREÇÃO vs. doc obsoleto:** DashMap guarda `Arc<RuntimeConfig>` por tenant (cache de config), NÃO pools por tenant. **Deadlock:** nunca segurar o `Ref` através de `.await` — clonar o `Arc` e soltar o guard antes do I/O.
> Chaves de API em `RuntimeConfig` usam `SecretString` (feature `serde` da `secrecy` só será habilitada na ponte Redis, fase futura).
```rust
use std::sync::Arc;
use dashmap::DashMap;
use rust_decimal::prelude::ToPrimitive;
use secrecy::SecretString;
use sqlx::PgPool;
use uuid::Uuid;
use crate::{crypto::CipherManager, errors::DbError};

/// Config resolvida (cascata Tenant > CoreSettings). Todos os campos já têm fallback aplicado.
#[derive(Debug, Clone)]
pub struct RuntimeConfig {
    pub tenant_id: Uuid,
    // Prompts
    pub dados_empresa: String,
    pub persona_bot: String,
    pub bot_agent_name: String,
    // Mensagens
    pub msg_fallback: String,
    pub msg_sem_info: String,
    pub msg_transferencia: String,
    // LLM
    pub llm_class: String,
    pub model: String,
    pub llm_temperature: f64,
    // Transcrição
    pub transcription_provider: String,
    pub transcription_model: String,
    // Visão
    pub vision_provider: String,
    pub vision_model: String,
    // Embeddings/RAG
    pub embeddings_class: String,
    pub embeddings_model: String,
    pub chunk_size: i32,
    pub chunk_overlap: i32,
    // Thresholds
    pub similarity_threshold: f64,
    pub vector_distance_threshold: f64,
    // Chaves de API (descriptografadas, protegidas por SecretString)
    pub openai_api_key: SecretString,
    pub groq_api_key: SecretString,
    pub google_api_key: SecretString,
}

/// Cache concorrente de RuntimeConfig por tenant.
pub struct TenantConfigCache {
    pool: PgPool,
    cipher: Arc<CipherManager>,
    cache: DashMap<Uuid, Arc<RuntimeConfig>>,
}

impl TenantConfigCache {
    pub fn new(pool: PgPool, cipher: Arc<CipherManager>) -> Self {
        Self { pool, cipher, cache: DashMap::new() }
    }

    pub async fn get_config(&self, tenant_id: Uuid) -> Result<Arc<RuntimeConfig>, DbError> {
        // Cache hit: clona o Arc e SOLTA o guard antes de qualquer await.
        if let Some(found) = self.cache.get(&tenant_id) {
            return Ok(found.clone());
        }
        let config = Arc::new(self.resolve_from_db(tenant_id).await?);
        self.cache.insert(tenant_id, config.clone());
        Ok(config)
    }

    pub fn invalidate(&self, tenant_id: &Uuid) {
        self.cache.remove(tenant_id);
    }

    async fn resolve_from_db(&self, tenant_id: Uuid) -> Result<RuntimeConfig, DbError> {
        // 1. CoreSettings (global) -> mapa key/value, descriptografando os encrypted.
        // 2. TenantConfig (sobrescreve campos não nulos; decimais via ToPrimitive::to_f64).
        // 3. api_keys (JSONB) do tenant tem prioridade; fallback para CoreSettings.
        // (implementação detalhada no item (d) — tenants/config.rs)
        todo!("ver tenants/config.rs")
    }
}
```
- `chunk_size`/`chunk_overlap` são `i32` (mapeiam `INTEGER`).
- `llm_temperature`, `similarity_threshold`, `vector_distance_threshold` chegam como `NUMERIC(3,2)` → `Decimal` no SQLx → `.to_f64()`.

---

### (d) Repositórios por domínio (trait + impl Postgres, um arquivo por domínio)

Padrão por arquivo (espelha `modulo_central_banco.md` §5): `#[derive(sqlx::FromRow)]` na struct; trait `#[async_trait]` com `&mut Transaction<'_, Postgres>` + `&RequestContext`; impl `Postgres*Repository` usando `query!`/`query_as!`, `&mut **tx` nas macros, `WHERE tenant_id = $1` explícito, e `ctx.has_permission(...)` nas escritas.

- **`tenants/tenants.rs`** — structs `Tenant`, `TenantUser`, `TenantInvite` + repos (CRUD; `Tenant.id` é a coluna de RLS).
- **`tenants/plans.rs`** — `Plan` (global), `Subscription`, `PaymentRecord` + repos.
- **`tenants/config.rs`** — leitura de `TenantConfig` + `resolve_from_db` (cascata Tenant > CoreSettings; descriptografia das chaves via `CipherManager`).
- **`tenants/settings.rs`** — CRUD de `CoreSettings` (global); helper `get_value` que descriptografa quando `encrypted = true`.
- **`clientes/contatos.rs`** — `Contato` + `buscar_por_telefone` + `salvar` com `ON CONFLICT (tenant_id, telefone) DO UPDATE`.
- **`clientes/clientes.rs`** — `Cliente` + M2M `oraculo_cliente_contatos` (`adicionar_contato`/`remover_contato`).
- **`operacional/departamentos.rs`** — `Departamento`.
- **`operacional/atendentes.rs`** — `Atendente` (round-robin/fairness: queries por `disponivel`, `data_ultima_atribuicao`).
- **`operacional/fluxos.rs`** — `FluxoAtendimento` + `EtapaFluxo`.
- **`atendimentos/atendimentos.rs`** — `Atendimento`.
- **`atendimentos/mensagens.rs`** — `Mensagem` (self-FK `mensagem_citada_id`).
- **`atendimentos/movimentos.rs`** — `MovimentoFluxo`.
- **`atendimentos/campos.rs`** — `CampoPersonalizado` + `ValorCampoAtendimento`.
- **`treinamento/treinamentos.rs`** — `Treinamento`.
- **`treinamento/documentos.rs`** — `Documento` + `buscar_documentos_similares` (pgvector `<=>`, JOIN `treinamento_finalizado = true`, filtro distância, `tenant_id` explícito).
- **`treinamento/query_compose.rs`** — `QueryCompose` + `to_embedding_text` + `buscar_comportamento_similar`.
- **`integracoes/evolution.rs`** — `EvolutionInstance` + `EvolutionContact`.
- **`integracoes/whitelist.rs`** — `WhiteList`.

**Busca vetorial (treinamento/documentos.rs)** — padrão atualizado pgvector 0.4 + sqlx 0.8:
```rust
use pgvector::Vector;

pub async fn buscar_documentos_similares(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    tenant_id: uuid::Uuid,
    query_embedding: Vec<f32>,
    top_k: i64,
    distance_threshold: f64,
) -> Result<Vec<(Documento, f64)>, crate::errors::DbError> {
    let query_vector = Vector::from(query_embedding);

    let rows = sqlx::query!(
        r#"
        SELECT d.id, d.treinamento_id, d.conteudo, d.metadata, d.ordem, d.data_criacao,
               (d.embedding <=> $1) AS "distancia!"
        FROM oraculo_documento d
        INNER JOIN oraculo_treinamento t ON d.treinamento_id = t.id
        WHERE d.tenant_id = $2
          AND t.treinamento_finalizado = true
          AND d.embedding IS NOT NULL
          AND (d.embedding <=> $1) <= $3
        ORDER BY d.embedding <=> $1
        LIMIT $4
        "#,
        query_vector as _,            // bind do Vector na macro: `as _`
        tenant_id,
        distance_threshold,
        top_k
    )
    .fetch_all(&mut **tx)            // macros usam &mut **tx
    .await?;

    let docs = rows.into_iter().map(|r| (
        Documento { /* mapear colunas */ id: r.id, /* ... */ },
        r.distancia,
    )).collect();
    Ok(docs)
}
```

---

### (e) `lib.rs` / exports

```rust
//! Crate de infraestrutura de persistência (PostgreSQL único + RLS + pgvector).

pub mod errors;
pub mod connection;
pub mod security;
pub mod crypto;
pub mod config_cache;

pub mod tenants;
pub mod clientes;
pub mod operacional;
pub mod atendimentos;
pub mod treinamento;
pub mod integracoes;

// Re-exports de conveniência
pub use errors::DbError;
pub use security::RequestContext;
pub use connection::{inicializar_banco_dados, run_in_tenant_transaction};
pub use config_cache::{RuntimeConfig, TenantConfigCache};
pub use crypto::CipherManager;
```
Cada `mod.rs` de domínio reexporta os submódulos (ex.: `tenants/mod.rs` → `pub mod tenants; pub mod plans; pub mod config; pub mod settings;`).

---

## FASE V — Validation (Test Writer + Backend Specialist)

Sequência end-to-end (detalhe na seção "Verificação end-to-end"):
1. Abrir túnel SSH (`infra/tunnel.ps1`) e configurar `server/.env` (`DATABASE_URL`).
2. `cargo sqlx migrate run` (aplica `0001..0009`).
3. Validar RLS manualmente (psql como `smartcore_app`, `set_config`, cross-tenant).
4. `cargo sqlx prepare` (gera/atualiza `.sqlx/`, versionado).
5. `SQLX_OFFLINE=true cargo build`.
6. Testes de integração:
   - **RLS cross-tenant:** tenant A não enxerga linhas do tenant B; sem `set_config`, policy nega tudo.
   - **Cipher round-trip:** `encrypt` → `decrypt` recupera o plaintext; tag adulterada falha.
   - **Cache fallback:** `RuntimeConfig` aplica CoreSettings quando campo do tenant é nulo; chave local sobrepõe global.
   - **Busca vetorial:** `buscar_documentos_similares`/`buscar_comportamento_similar` retornam ordenado por distância, respeitam `distance_threshold` e `treinamento_finalizado`.
7. `cargo clippy --all-targets -- -D warnings` e `cargo fmt --check`.

---

## FASE C — Confirmation (Backend Specialist)

- Gate obrigatório `prevc-final-review`: auditar implementação vs. este plano; corrigir desvios.
- Commit gitflow (`feature/infrastructure-postgres`), conventional commits, **sem auto-referência ao Claude**.
- Garantir `.sqlx/` versionado e migrations idempotentes.
- Consolidar este plano no canônico e mover para `archive/`.

---

## Correções aplicadas

Mudanças em relação ao plano-base/docs de modelagem, com motivo e fonte:

1. **RLS via `set_config(..., true)` (não `SET LOCAL = $1`).**
   O `connection.rs` dos docs (`modulo_central_banco.md` §3 e `estrategia_implementacao_rust.md` §2.2) usa `sqlx::query("SET LOCAL app.current_tenant = $1").bind(tenant_id)`. O comando `SET` do PostgreSQL **não aceita placeholders** via prepared statement, então o bind falha. Substituído por `SELECT set_config('app.current_tenant', $1, true)` com `tenant_id.to_string()`. O terceiro argumento `true` mantém o escopo transação-local (equivalente a `SET LOCAL`). Fonte: `info_aux` §sqlx (correção crítica) + nota geral §1.

2. **base64 0.22 — sem `encode/decode` globais.**
   As funções livres `base64::encode/decode` foram removidas. Usar `engine::general_purpose::STANDARD` + trait `Engine` (`BASE64.encode(...)` / `BASE64.decode(...)`). O snippet de `08_diretrizes_seguranca.md` §2.4 já antecipa isso, mas qualquer código antigo precisa revisão. Fonte: `info_aux` §base64.

3. **DashMap como cache de `RuntimeConfig`, não pools por tenant.**
   Doc local anterior descrevia arquitetura obsoleta (múltiplos bancos / `TenantPoolManager`). A arquitetura vigente é **pool global único** + isolamento por RLS; o `DashMap<Uuid, Arc<RuntimeConfig>>` guarda apenas configs resolvidas. Gotcha: nunca segurar o `Ref` do DashMap através de `.await` (clonar o `Arc` e soltar o guard antes do I/O). Fonte: `info_aux` §dashmap + `modulo_central_banco.md` §3.

4. **Tabela `auth_user` mínima na migration `0001`.**
   As FKs do legado Django (`owner_id`, `recorded_by_id`, `created_by_id`, `user_id`, `usuario_id`) apontam para `auth_user`, que ainda não tem módulo Rust. Criada tabela mínima global (sem RLS) na `0001` para satisfazer as FKs. Fonte: `info_aux` nota §3.

5. **`SecretString` (secrecy) para chaves de API em runtime.**
   `RuntimeConfig` carrega `openai_api_key`/`groq_api_key`/`google_api_key` como `SecretString` (`Debug = [REDACTED]`, zeroize no Drop), evitando vazamento em logs/panics. A feature `serde` da `secrecy` fica desabilitada nesta fase e só será ligada na ponte Redis (serialização opt-in). Fonte: `info_aux` §secrecy + `08_diretrizes_seguranca.md` §4.1.

6. **Índice HNSW `vector_cosine_ops` explícito + B-tree composto.**
   Os docs de modelagem citam o operador `<=>` mas não fixam o índice. Padronizado `CREATE INDEX ... USING hnsw (embedding vector_cosine_ops)` em `oraculo_documento.embedding` e `treinamento_querycompose.embedding`, mais B-tree composto (`(tenant_id, treinamento_id, ordem)` e `(tenant_id, tag)`), e dimensão fixa `vector(1536)`. Fonte: `info_aux` §pgvector + `05_modulo_treinamento.md`.

7. **AppInstance e EvolutionInstance são tabelas distintas que coexistem.**
   `oraculo_app_instance` (módulo operacional, `03`) e `evolution_sync_instance` (módulo integrações, `06`) descrevem instâncias em camadas diferentes e ambas são criadas (migrations `0005` e `0008`). Não consolidar. Fonte: plano-base + `03`/`06`.

8. **`FORCE ROW LEVEL SECURITY` + role `NOBYPASSRLS` + policy fail-closed.**
   Além de `ENABLE`, aplicar `FORCE` (RLS vale até para o owner) e a policy `USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid)` (nega tudo quando o contexto não está setado). A app conecta como `smartcore_app` (`NOBYPASSRLS`), nunca como superuser/owner. Fonte: `08_diretrizes_seguranca.md` §1.2/§1.3 + `info_aux` nota §2.

9. **Política RLS de `tenants_tenant` usa `id` (não `tenant_id`).**
   A tabela raiz `tenants_tenant` tem PK `id` (UUID) e não possui coluna `tenant_id`; sua policy filtra por `id = current_setting(...)`. Demais tabelas filtram por `tenant_id`. (Ajuste derivado da modelagem `01`.)

10. **Nota de porta do túnel.**
    `.env.example` (raiz) usa `localhost:5434` para `DATABASE_URL`, mas `infra/tunnel.ps1` mapeia `localhost:5432`. Alinhar a porta no `server/.env` ao túnel efetivamente aberto antes de `migrate`/`prepare`. (Observação operacional, não bloqueante.)

---

## Verificação end-to-end

Pré-requisitos: `infra/.env.deploy` preenchido; toolchain Rust estável; `sqlx-cli` instalado (`cargo install sqlx-cli --no-default-features --features rustls,postgres`).

```powershell
# 1. Abrir o túnel SSH (manter o terminal aberto)
cd infra ; .\tunnel.ps1
```

```powershell
# Em outro terminal — configurar o .env da crate
# server/.env:
#   DATABASE_URL=postgresql://smartcore_app:SENHA@localhost:5432/smartcore_v2
#   ENCRYPTION_KEY=<base64 de 32 bytes>
```

```bash
# 2. Aplicar migrations no Postgres real (via túnel)
cd server/crates/infrastructure_postgres
sqlx migrate run

# 3. Validar RLS (psql como smartcore_app)
#    - SELECT set_config('app.current_tenant', '<uuid-A>', false);
#      SELECT count(*) FROM oraculo_contato;   -- só linhas do tenant A
#    - sem set_config: SELECT * FROM oraculo_contato;  -- retorna 0 linhas (fail-closed)
#    - confirmar que smartcore_app NÃO tem BYPASSRLS

# 4. Gerar metadados offline do SQLx (.sqlx/ versionado)
cargo sqlx prepare

# 5. Build em modo offline (como no CI)
SQLX_OFFLINE=true cargo build

# 6. Testes de integração (RLS cross-tenant, cipher round-trip, cache fallback, busca vetorial)
cargo test

# 7. Lint e formatação
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

Critérios de aceite:
- `0001..0009` aplicam sem erro; extensões `vector`/`uuid-ossp` presentes.
- RLS isola cross-tenant e nega acesso sem contexto (policy fail-closed); `smartcore_app` é `NOBYPASSRLS`.
- `.sqlx/` versionado; `SQLX_OFFLINE=true cargo build` compila sem `DATABASE_URL`.
- Todos os testes de integração verdes; `clippy -D warnings` e `fmt --check` limpos.
