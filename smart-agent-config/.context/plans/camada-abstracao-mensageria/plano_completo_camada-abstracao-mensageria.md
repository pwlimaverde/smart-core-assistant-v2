# Plano Completo: Camada de Abstração de Mensageria (WhatsApp)

> Plano reestruturado a partir de `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`, validado
> contra a árvore real do repositório (`server/apps`, `server/crates`), a documentação atual do **axum 0.8**
> e da **Evolution API**. Este documento é a **única fonte de verdade técnica** para a implementação.
> Organizado em fases **PREVC** (Planning, Review, Execution, Validation, Confirmation).

---

## Objetivo

Introduzir uma **camada de abstração de mensageria** que permita plugar/trocar qualquer provedor de WhatsApp
(Evolution API, Z-API, Baileys, etc.) de forma transparente para as regras de negócio dos tenants. A stack do
Evolution API roda isolada em Docker, com PostgreSQL próprio (estilo stack de observabilidade).

### Premissas de abstração e desacoplamento
1. **Contratos em Rust (traits)**: comportamento de mensageria atrás de uma interface única `MessagingProvider`.
2. **Normalização de dados**: tudo específico de provedor é traduzido para estruturas neutras.
3. **Normalização no ingress**: o micro-serviço `webhook_ingress` recebe webhooks proprietários, converte em
   eventos universais e publica no barramento Redis Streams. O resto do sistema só consome eventos normalizados.
4. **Banco limpo**: reescrita do schema `0008_*` para tabelas genéricas (`whatsapp_instance`, `whatsapp_contact`,
   `whatsapp_whitelist`) com coluna `provider` **sem default acoplado**.

---

## Reconciliação com o repositório real (pré-condição da execução)

Durante a reestruturação, o plano-base foi confrontado com a árvore real. Divergências detectadas e tratadas
ao longo das fases:

| Item do plano-base | Realidade no repo | Decisão |
| --- | --- | --- |
| "Renomear `apps/data_evolution` → `apps/data_whatsapp`" | **`apps/data_evolution` NÃO existe.** A lógica WhatsApp/Evolution vive hoje em `apps/control_plane/src/evolution.rs` e `crates/infrastructure_postgres/src/integracoes/evolution.rs` | `apps/data_whatsapp` é **app novo**, extraído do código atual de `control_plane`/`infrastructure_postgres` |
| "Renomear `0008_evolution_sync.sql`" | Existe `crates/infrastructure_postgres/migrations/0008_evolution_sync.sql` com `evolution_sync_instance/contact/whitelist` | Reescrita do `0008` (seguro: sem dados em produção) |
| Stream key `smart_core:events:{topic}` | Stream real é **`events:stream`** (`STREAM_EVENTOS`) e **`security:stream`** (`STREAM_SEGURANCA`), ver `crates/transport/src/bus.rs` | Publicar via `transport::bus::publicar_evento` / `publicar_evento_seguranca`; **não** inventar key nova |
| "Eventos de auditoria via `transport::bus` → `data_postgres`" | Auditoria já tem stream dedicado `STREAM_SEGURANCA` e tabela `audit_log` (migração `0010_audit_log.sql`) | Auditoria = `publicar_evento_seguranca` → consumer grava em `audit_log` |
| `crates/` para as novas crates | Crates reais ficam em `server/crates/` e apps em `server/apps/` | Caminhos ajustados: `server/crates/infrastructure_messaging`, `server/apps/webhook_ingress` |

Apps existentes (confirmados): `control_plane`, `data_postgres`, `data_redis`, `data_storage`,
`messaging_gateway`, `runtime_api`, `worker`.

Crates existentes (confirmados): `application`, `contracts`, `error_core`, `infrastructure_postgres`,
`infrastructure_redis`, `infrastructure_storage`, `observability`, `test_support`, `transport`.

---

## Decisões de Design

### D1. Duas crates de abstração
- **`server/crates/infrastructure_messaging`**: trait `MessagingProvider`, enums normalizados
  (`ConnectionState`, `MediaType`), structs de payload comuns e `MessagingProviderError`. Sem runtime, sem I/O.
- **`server/crates/infrastructure_evolution`**: implementa `MessagingProvider` via HTTP REST (reqwest) contra o
  Evolution API.

### D2. Roteamento dinâmico em `apps/data_whatsapp`
Ao receber um RPC, o app:
1. Consulta o banco (via `data_postgres`) para obter o `provider` da instância.
2. Delega para a struct correspondente que implementa `MessagingProvider` (hoje só `EvolutionProvider`).

### D3. Webhooks com detecção de provedor via path (axum 0.8)
URL configurada no provedor (sintaxe de chaves do axum 0.8):
```
http://webhook_ingress:9200/webhook/{provider}/{tenant_id}/{instance_id}
```
O `webhook_ingress` extrai `provider` do path, parseia o JSON proprietário e publica evento normalizado em
`events:stream`.

### D4. Desconexão em massa pelo admin
RPC `AdminBulkDisconnectInstances` em `data_whatsapp`, consumida pelo `control_plane`:
- `tenant_id: Option<Uuid>` — se `None`, desconecta todas as instâncias de todos os tenants (bypass RLS via
  transação admin, exige escopo `operacional:admin`).
- Atualiza `connection_state = 'disconnected'` no banco.

---

# Fase P — Planning (output)

**Status: concluída.** Saídas desta fase:

- **Escopo**: 7 componentes (2 crates novas, 1 migração reescrita, 1 módulo de repositório, 1 app novo
  `webhook_ingress`, 1 app novo `data_whatsapp`, alterações em `control_plane`/`data_postgres`).
- **Contrato central**: `MessagingProvider` (11 métodos async) — fronteira única entre regra de negócio e provedor.
- **Modelo de eventos normalizados** publicados em `events:stream`:
  - `whatsapp.message.received`
  - `whatsapp.connection.updated`
- **Modelo de auditoria** publicado em `security:stream` (consumido por `data_postgres` → `audit_log`):
  - `whatsapp.instance.create`, `whatsapp.instance.delete`, `whatsapp.admin.bulk_disconnect`.
- **Mapa de risco**: reescrita de migração só é segura pré-produção; dois `axum` coexistem (0.7.5 no
  `runtime_api`, 0.8 no `webhook_ingress`) — não unificar via workspace.

---

# Fase R — Review (arquitetura e contratos)

### R1. Compatibilidade de versões
- `runtime_api` permanece em **axum 0.7.5**. `webhook_ingress` usa **axum 0.8** declarado **localmente** no
  `Cargo.toml` do app — **NÃO** adicionar `axum` ao `Cargo.toml` do workspace (evita forçar bump no `runtime_api`).
- `reqwest 0.12` com feature `json` para `infrastructure_evolution`.
- Reuso obrigatório de libs já no workspace: `async-trait`, `serde`, `serde_json`, `secrecy`, `thiserror`,
  `uuid`, `tracing`, `redis`, `contracts`, `transport`, `error_core`, `observability`.

### R2. Sanidade de segurança (revisada antes da execução)
- `global_api_key` e `instance_token` sempre `SecretString`. Nunca em logs, nunca na resposta de endpoints.
- `api_key`/`instance_token` no banco: armazenados encriptados (mesma política das demais credenciais de tenant).
- RLS ativa em todas as tabelas `whatsapp_*`; bypass só por transação admin explícita.

### R3. Decisão de contrato de barramento
- Reaproveitar `TenantEnvelope<T>` + `transport::bus::publicar_evento(_seguranca)` (já existentes). O webhook de
  conexão sem tenant resolvido usa `tenant_id` extraído do path.

**Gate R**: aprovado se R1/R2/R3 confirmados em revisão. Saída → Execution.

### Observabilidade & Auditoria — Fase R
- **a) Logs/traces**: nada executado; apenas definição da política de spans/fields que cada fase E deve seguir
  (campos de correlação obrigatórios: `service`, `env`, `tenant_id`, `trace_id`, `error_code`).
- **b) Auditoria no banco**: define-se o catálogo de eventos de auditoria (acima) e o destino (`audit_log`). Nada
  gravado nesta fase.
- **c) Sanitização**: revisão confirma que toda assinatura que carrega segredo usa `SecretString` e que nenhum
  campo de auditoria/contexto inclui token/PII sensível.

---

# Fase E — Execution (detalhe técnico máximo)

## E1. Crate `server/crates/infrastructure_messaging`

**`Cargo.toml`**
```toml
[package]
name = "infrastructure_messaging"
version = "0.1.0"
edition.workspace = true

[dependencies]
async-trait = { workspace = true }
serde       = { workspace = true }
secrecy     = { workspace = true }
thiserror   = { workspace = true }
uuid        = { workspace = true }
```

**`src/lib.rs`**
```rust
//! Contrato genérico de mensageria (WhatsApp). Sem runtime, sem I/O, sem logs.
pub mod errors;

use async_trait::async_trait;
use secrecy::SecretString;
pub use errors::MessagingProviderError;

/// Estado de conexão normalizado (independente de provedor).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState { Connected, Disconnected, Connecting, Unknown }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreateInstanceResult { pub provider_instance_id: String, pub instance_token: String }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SendMessageResult { pub message_id: String }

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MediaType { Image, Video, Audio, Document }

/// Fronteira única entre regra de negócio e provedor de WhatsApp.
#[async_trait]
pub trait MessagingProvider: Send + Sync {
    fn provider_name(&self) -> &'static str;
    async fn create_instance(&self, instance_name: &str, custom_token: Option<&SecretString>) -> Result<CreateInstanceResult, MessagingProviderError>;
    async fn delete_instance(&self, instance_name: &str) -> Result<(), MessagingProviderError>;
    async fn connect_instance(&self, instance_name: &str, instance_token: &SecretString) -> Result<(), MessagingProviderError>;
    async fn disconnect_instance(&self, instance_name: &str, instance_token: &SecretString) -> Result<(), MessagingProviderError>;
    async fn get_qr_code(&self, instance_name: &str, instance_token: &SecretString) -> Result<String, MessagingProviderError>;
    async fn pair_by_phone(&self, instance_name: &str, instance_token: &SecretString, phone_number: &str) -> Result<String, MessagingProviderError>;
    async fn configure_webhook(&self, instance_name: &str, instance_token: &SecretString, webhook_url: &str, events: &[String]) -> Result<(), MessagingProviderError>;
    async fn get_connection_state(&self, instance_name: &str) -> Result<ConnectionState, MessagingProviderError>;
    async fn send_text(&self, instance_name: &str, instance_token: &SecretString, to_number: &str, text: &str) -> Result<SendMessageResult, MessagingProviderError>;
    async fn send_media(&self, instance_name: &str, instance_token: &SecretString, to_number: &str, media_type: MediaType, media_url: &str, caption: Option<&str>) -> Result<SendMessageResult, MessagingProviderError>;
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}
```

**`src/errors.rs`**
```rust
#[derive(Debug, thiserror::Error)]
pub enum MessagingProviderError {
    #[error("Erro de conexão/rede no provedor: {0}")] Network(String),
    #[error("O provedor retornou erro HTTP (status {status}): {body}")] ProviderApi { status: u16, body: String },
    #[error("Falha ao processar resposta do provedor: {0}")] Deserialization(String),
    #[error("Erro de configuração do provedor: {0}")] Config(String),
    #[error("Operação inválida no estado atual: {0}")] InvalidState(String),
}
```

### Observabilidade & Auditoria — E1
- **a) Logs/traces**: **nenhum**. A crate é pura (sem runtime). Erros são *valores* (`MessagingProviderError`),
  logados por quem chama (`infrastructure_evolution`/`data_whatsapp`).
- **b) Auditoria no banco**: **sem evento de auditoria** (intencional — crate sem identidade de usuário nem I/O).
- **c) Sanitização**: `SecretString` já presente nas assinaturas (`custom_token`, `instance_token`); o `Debug` de
  `SecretString` imprime `[REDACTED]`. Nenhum segredo em texto plano nas structs.

---

## E2. Crate `server/crates/infrastructure_evolution`

**`Cargo.toml`**
```toml
[package]
name = "infrastructure_evolution"
version = "0.1.0"
edition.workspace = true

[dependencies]
infrastructure_messaging = { path = "../infrastructure_messaging" }
reqwest     = { version = "0.12", features = ["json"] }
serde       = { workspace = true }
serde_json  = { workspace = true }
secrecy     = { workspace = true }
async-trait = { workspace = true }
thiserror   = { workspace = true }
tracing     = { workspace = true }
```

**`src/client.rs`** (struct e helpers)
```rust
use infrastructure_messaging::{
    ConnectionState, CreateInstanceResult, MediaType, MessagingProvider,
    MessagingProviderError, SendMessageResult,
};
use secrecy::{ExposeSecret, SecretString};
use serde::Deserialize;

/// Cliente REST do Evolution API. `reqwest::Client` mantém pool interno e é barato de clonar.
#[derive(Clone)]
pub struct EvolutionProvider {
    http: reqwest::Client,
    base_url: String,
    global_api_key: SecretString, // gerencia instâncias; NUNCA logar
}

impl EvolutionProvider {
    pub fn new(base_url: impl Into<String>, global_api_key: SecretString) -> Self {
        Self { http: reqwest::Client::new(), base_url: base_url.into(), global_api_key }
    }

    /// Trata a resposta HTTP: erro de rede vira Network, status != 2xx vira ProviderApi
    /// com o body truncado a 200 chars (evita vazar PII/segredo em logs).
    async fn ok_or_api(resp: reqwest::Response) -> Result<reqwest::Response, MessagingProviderError> {
        if resp.status().is_success() {
            Ok(resp)
        } else {
            let status = resp.status().as_u16();
            let body = resp.text().await.unwrap_or_default();
            let body = body.chars().take(200).collect::<String>();
            Err(MessagingProviderError::ProviderApi { status, body })
        }
    }
}

#[derive(Deserialize)]
struct CreateInstanceResp { instance: CreateInstanceInner, hash: Option<String> }
#[derive(Deserialize)]
struct CreateInstanceInner { #[serde(rename = "instanceName")] instance_name: String, hash: Option<String> }

#[derive(Deserialize)]
struct ConnStateResp { instance: ConnStateInner }
#[derive(Deserialize)]
struct ConnStateInner { state: String }
```

**`src/provider.rs`** (implementação da trait — métodos representativos)

> Auth (Evolution API): header `apikey: <global_api_key>` para **gerenciar instâncias**;
> header `apikey: <instance_token>` (campo `hash` retornado no create) para **enviar mensagens**.

```rust
use async_trait::async_trait;

#[async_trait]
impl MessagingProvider for EvolutionProvider {
    fn provider_name(&self) -> &'static str { "evolution" }

    #[tracing::instrument(err, skip(self, custom_token), fields(provider = "evolution", instance_name))]
    async fn create_instance(
        &self,
        instance_name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError> {
        let mut body = serde_json::json!({
            "instanceName": instance_name,
            "qrcode": true,
            "integration": "WHATSAPP-BAILEYS"
        });
        if let Some(tok) = custom_token {
            body["token"] = serde_json::Value::String(tok.expose_secret().to_string());
        }
        let resp = self.http
            .post(format!("{}/instance/create", self.base_url))
            .header("apikey", self.global_api_key.expose_secret())
            .json(&body)
            .send().await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        let resp = Self::ok_or_api(resp).await?;
        let parsed: CreateInstanceResp = resp.json().await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
        let token = parsed.hash.or(parsed.instance.hash)
            .ok_or_else(|| MessagingProviderError::Deserialization("hash ausente na resposta".into()))?;
        Ok(CreateInstanceResult {
            provider_instance_id: parsed.instance.instance_name,
            instance_token: token,
        })
    }

    #[tracing::instrument(err, skip(self), fields(provider = "evolution", instance_name))]
    async fn get_connection_state(&self, instance_name: &str) -> Result<ConnectionState, MessagingProviderError> {
        let resp = self.http
            .get(format!("{}/instance/connectionState/{instance_name}", self.base_url))
            .header("apikey", self.global_api_key.expose_secret())
            .send().await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        let resp = Self::ok_or_api(resp).await?;
        let parsed: ConnStateResp = resp.json().await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
        Ok(map_state(&parsed.instance.state))
    }

    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name))]
    async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError> {
        let resp = self.http
            .post(format!("{}/message/sendText/{instance_name}", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .json(&serde_json::json!({ "number": to_number, "text": text }))
            .send().await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        let resp = Self::ok_or_api(resp).await?;
        let v: serde_json::Value = resp.json().await
            .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
        let id = v.get("key").and_then(|k| k.get("id")).and_then(|i| i.as_str())
            .ok_or_else(|| MessagingProviderError::Deserialization("key.id ausente".into()))?;
        Ok(SendMessageResult { message_id: id.to_string() })
    }

    // CORREÇÃO: Evolution API usa PUT /webhook/set/{name} (não POST).
    // webhookByEvents=false → todos os eventos na mesma URL; ingress discrimina por campo `event`.
    #[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name))]
    async fn configure_webhook(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        webhook_url: &str,
        events: &[String],
    ) -> Result<(), MessagingProviderError> {
        let resp = self.http
            .put(format!("{}/webhook/set/{instance_name}", self.base_url))
            .header("apikey", instance_token.expose_secret())
            .json(&serde_json::json!({
                "enabled": true,
                "url": webhook_url,
                "webhookByEvents": false,
                "events": events
            }))
            .send().await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        Self::ok_or_api(resp).await?;
        Ok(())
    }

    // send_media: vídeo/arquivo > 3MB SEMPRE por URL remota (R2); base64 só < 3MB.
    // Demais métodos: mesmo padrão (header apikey adequado, ok_or_api, parse mínimo).
}

/// Mapeamento de estado Evolution → normalizado.
fn map_state(s: &str) -> ConnectionState {
    match s {
        "open"       => ConnectionState::Connected,
        "close"      => ConnectionState::Disconnected,
        "connecting" => ConnectionState::Connecting,
        _            => ConnectionState::Unknown,
    }
}
```

Endpoints Evolution usados (referência atual):
- `POST /instance/create` (`qrcode:true`) → `response.hash` / `instance.hash` (instance token)
- `GET /instance/connect/{name}` → QR base64 (renova QR expirado)
- `GET /instance/connectionState/{name}` → `instance.state`: `open`|`close`|`connecting`
- `POST /instance/logout/{name}` → desconecta sem deletar
- `DELETE /instance/delete/{name}` → remove instância
- `GET /instance/fetchInstances` → lista paginada (`?page=1&offset=50`)
- `POST /message/sendText/{name}` → `{ "number", "text" }` → `key.id`
- `POST /message/sendMedia/{name}` → URL (>3MB) ou base64 (<3MB)
- `PUT /webhook/set/{name}` → `{ "enabled", "url", "webhookByEvents":false, "events":[...] }`
- `POST /instance/pairingCode/{name}` → `{ "number" }`

### Observabilidade & Auditoria — E2
- **a) Logs/traces**: `#[tracing::instrument(err, skip(self, instance_token))]` em cada método async; fields
  `instance_name`, `provider = "evolution"`. Erro HTTP loga `status` e `body` truncado (≤ 200 chars).
- **b) Auditoria no banco**: **sem evento de auditoria** (intencional — camada de infra sem identidade de
  usuário; auditoria é responsabilidade da camada de aplicação `data_whatsapp`).
- **c) Sanitização**: `global_api_key` e `instance_token` são `SecretString` na struct/assinaturas, sempre em
  `skip(...)` do `instrument`. Body de erro truncado para não vazar telefone/conteúdo. Nunca logar `apikey`.

---

## E3. Banco de Dados — reescrita do schema

Reescrever `server/crates/infrastructure_postgres/migrations/0008_evolution_sync.sql` →
**`0008_whatsapp_sync.sql`** (renomear arquivo + conteúdo). Seguro: sem dados em produção.

```sql
-- ============================================================
-- Módulo Mensageria WhatsApp (genérico, multi-provedor)
-- ============================================================
CREATE TABLE whatsapp_instance (
    id                    SERIAL PRIMARY KEY,
    tenant_id             UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    name                  VARCHAR(100) NOT NULL,
    instance_id           VARCHAR(100) UNIQUE,
    api_key               VARCHAR(256) NOT NULL,          -- encriptado em repouso
    phone_number          VARCHAR(20),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    connection_state      VARCHAR(20) NOT NULL DEFAULT 'unknown',
    last_state_check      TIMESTAMPTZ,
    media_storage_backend VARCHAR(10) NOT NULL DEFAULT 's3',
    provider              VARCHAR(50) NOT NULL,           -- SEM default acoplado
    subscribed_events     JSONB NOT NULL DEFAULT '[]',
    last_connection_state VARCHAR(50),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)                              -- removido UNIQUE(name) global (quebra multi-tenancy)
);
ALTER TABLE whatsapp_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_instance FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_instance_tenant_isolation ON whatsapp_instance
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_instance_tenant_state ON whatsapp_instance (tenant_id, active, connection_state);

CREATE TABLE whatsapp_contact (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id      INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    instance_id     INT NOT NULL REFERENCES whatsapp_instance(id) ON DELETE CASCADE,
    jid             VARCHAR(100),
    lid             VARCHAR(100),
    addressing_mode VARCHAR(8),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    metadados       JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, instance_id, jid)
);
ALTER TABLE whatsapp_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_contact FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_contact_tenant_isolation ON whatsapp_contact
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_contact_tenant_jid ON whatsapp_contact (tenant_id, jid);
CREATE INDEX whatsapp_contact_tenant_lid ON whatsapp_contact (tenant_id, lid);
CREATE INDEX whatsapp_contact_tenant_crm ON whatsapp_contact (tenant_id, contact_id);

CREATE TABLE whatsapp_whitelist (
    id           SERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id   INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    name         VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, phone_number)
);
ALTER TABLE whatsapp_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_whitelist FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_whitelist_tenant_isolation ON whatsapp_whitelist
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_whitelist_tenant_phone ON whatsapp_whitelist (tenant_id, phone_number);
```

> Após reescrever, **regerar cache SQLx offline** (`SQLX_OFFLINE`) — ver MEMORY "testes-db-tunel-e-reset".

### Observabilidade & Auditoria — E3
- **a) Logs/traces**: migração é DDL; logs ficam a cargo do runner de migração existente (sem instrumentação nova).
- **b) Auditoria no banco**: **sem evento de auditoria** (intencional — DDL de bootstrap).
- **c) Sanitização**: `api_key` armazenado encriptado; RLS + FORCE em todas as tabelas garante isolamento de
  tenant. Nenhuma coluna expõe token em texto plano para consultas de outro tenant.

---

## E4. `infrastructure_postgres` — módulo `whatsapp`

Substituir `server/crates/infrastructure_postgres/src/integracoes/evolution.rs` por
`server/crates/infrastructure_postgres/src/integracoes/whatsapp.rs`.
Ajustar `integracoes/mod.rs`.

Structs: `WhatsappInstance`, `WhatsappContact`.

Handlers (repositório):
- `GetWhatsappInstance` — por `(tenant_id, name)` ou `instance_id`.
- `CreateWhatsappInstanceRecord` — insere instância (com `provider`).
- `ListWhatsappInstances` — por tenant.
- `DeactivateWhatsappInstanceRecord`.
- `AdminListAllConnectedInstances` — cross-tenant, exige transação admin.

```rust
// Padrão tenant (RLS por current_setting('app.current_tenant')):
#[tracing::instrument(skip_all, fields(tenant_id = %ctx.tenant_id))]
pub async fn create_whatsapp_instance_record(
    pool: &PgPool,
    ctx: &RequestContext,
    novo: NovaInstancia,
) -> Result<WhatsappInstance, DbError> {
    ctx.exigir_qualquer(&["integracoes:write", "tenant:admin"])?;
    run_in_tenant_transaction(pool, ctx, |tx| async move {
        // INSERT ... RETURNING — NUNCA logar api_key ao mapear a linha
    }).await
}

// Admin bypass (cross-tenant) — exige escopo operacional:admin:
#[tracing::instrument(skip_all, fields(operation = "admin_list_all_whatsapp_instances"))]
pub async fn admin_list_all_connected_instances(
    pool: &PgPool,
    ctx: &RequestContext,
) -> Result<Vec<WhatsappInstance>, DbError> {
    ctx.exigir_qualquer(&["operacional:admin"])?;
    run_in_admin_transaction(pool, |tx| async move { /* SELECT cross-tenant */ }).await
}
```

### Observabilidade & Auditoria — E4
- **a) Logs/traces**: `#[instrument(skip_all)]` em todo handler; queries de tenant dentro de
  `run_in_tenant_transaction`; admin via `run_in_admin_transaction` com field
  `operation = "admin_list_all_whatsapp_instances"`. Negação de escopo já loga `warn` via
  `RequestContext::exigir_qualquer`.
- **b) Auditoria no banco**: **sem evento de auditoria no repositório** (intencional — o evento é
  publicado pela camada de aplicação `data_whatsapp`/`control_plane`; o repositório só persiste).
- **c) Sanitização**: ao mapear linhas, **não logar** `api_key`/`instance_token`. `skip_all` evita capturar args
  com segredos.

---

## E5. App novo `server/apps/webhook_ingress`

**`Cargo.toml`** (axum **0.8** local — NÃO no workspace)
```toml
[package]
name = "webhook_ingress"
version = "0.1.0"
edition.workspace = true

[[bin]]
name = "webhook_ingress"
path = "src/main.rs"

[dependencies]
contracts                = { workspace = true }
transport                = { workspace = true }
error_core               = { workspace = true }
observability            = { workspace = true }
infrastructure_messaging = { path = "../../crates/infrastructure_messaging" }
tokio      = { workspace = true }
serde      = { workspace = true }
serde_json = { workspace = true }
tracing    = { workspace = true }
redis      = { workspace = true }
uuid       = { workspace = true }
axum       = "0.8"
```

**`src/main.rs`** — sintaxe axum 0.8 (chaves `{param}`, `State`, `axum::serve`)
```rust
use axum::{
    extract::{Path, State},
    routing::post,
    Router,
    body::Bytes,
    response::IntoResponse,
    http::StatusCode,
};
use serde::Deserialize;
use transport::bus;

#[derive(Clone)]
struct AppState {
    redis: redis::aio::ConnectionManager,
}

// axum 0.8: Path desestrutura por chaves {provider}/{tenant_id}/{instance_id}
#[derive(Deserialize)]
struct WebhookPath {
    provider: String,
    tenant_id: uuid::Uuid,
    instance_id: i32,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init("webhook_ingress")?;

    let client = redis::Client::open(std::env::var("SMARTCORE_REDIS_URL")?)?;
    let redis = redis::aio::ConnectionManager::new(client).await?;
    let state = AppState { redis };

    let app = Router::new()
        // CORREÇÃO axum 0.8: chaves {param}, NÃO :param (0.7 dá panic em 0.8)
        .route("/webhook/{provider}/{tenant_id}/{instance_id}", post(handle_webhook))
        .with_state(state); // .with_state() obrigatório em 0.8

    // CORREÇÃO axum 0.8: TcpListener + axum::serve (Server::bind().serve() removido)
    let listener = tokio::net::TcpListener::bind("0.0.0.0:9200").await?;
    tracing::info!("webhook_ingress ouvindo em 0.0.0.0:9200");
    axum::serve(listener, app).await?;
    Ok(())
}

// NUNCA logar `body` bruto (PII: telefone, nome, conteúdo). Só metadados.
#[tracing::instrument(
    skip(state, body),
    fields(
        provider    = %params.provider,
        tenant_id   = %params.tenant_id,
        instance_id = params.instance_id,
        event_type
    )
)]
async fn handle_webhook(
    Path(params): Path<WebhookPath>,
    State(mut state): State<AppState>,
    body: Bytes,
) -> Result<impl IntoResponse, StatusCode> {
    let raw: serde_json::Value = serde_json::from_slice(&body)
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    // webhookByEvents=false => todos os eventos na mesma URL; discrimina por `event`.
    let event_type = raw.get("event").and_then(|e| e.as_str()).unwrap_or("");
    tracing::Span::current().record("event_type", event_type);

    let normalizado = match params.provider.as_str() {
        "evolution" => normalize_evolution(event_type, &raw, params.tenant_id, params.instance_id),
        outro => {
            tracing::warn!(provider = outro, "provedor desconhecido no path do webhook");
            None
        }
    };

    if let Some((topic, envelope)) = normalizado {
        bus::publicar_evento(&mut state.redis, &envelope)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        tracing::info!(topico = topic, "evento normalizado publicado no barramento");
    }

    Ok(StatusCode::ACCEPTED) // 202: aceito mesmo para evento ignorado (idempotência do provedor)
}
```

**Normalização (exemplo Evolution):**
```rust
// messages.upsert   → "whatsapp.message.received"
// connection.update → "whatsapp.connection.updated"
fn normalize_evolution(
    event: &str,
    raw: &serde_json::Value,
    tenant_id: uuid::Uuid,
    instance_id: i32,
) -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)> {
    let (topic, payload) = match event {
        "messages.upsert"   => ("whatsapp.message.received",   build_message_payload(raw, instance_id)),
        "connection.update" => ("whatsapp.connection.updated", build_connection_payload(raw, instance_id)),
        _                   => return None,
    };
    Some((topic, contracts::TenantEnvelope::novo(tenant_id, topic.to_string(), payload)))
}
```

`build_connection_payload` mapeia `data.state`:
`"open"` → `"connected"`, `"close"` → `"disconnected"`, `"connecting"` → `"connecting"`, `_` → `"unknown"`.

> Deduplicação de `MESSAGES_UPSERT` por `key.id` é responsabilidade do **worker** (pode chegar 2×).

### Observabilidade & Auditoria — E5
- **a) Logs/traces**: `#[instrument(skip(state, body), fields(provider, tenant_id, instance_id, event_type))]`.
  Loga apenas metadados (`event_type`, tópico publicado). Nível `info` no publish, `warn` para provedor
  desconhecido.
- **b) Auditoria no banco**: **sem evento de auditoria** (intencional — volume alto de webhooks; auditoria de
  mensagens é responsabilidade do `worker` ao processar o evento normalizado).
- **c) Sanitização**: `body` em `skip(...)` — **nunca** logado. Apenas `event` (tipo) e identificadores
  não-sensíveis são registrados.

---

## E6. App novo `server/apps/data_whatsapp`

Extraído de `control_plane`/`infrastructure_postgres` (não é renomeação — `data_evolution` não existe).
Recebe RPCs, resolve `provider` no banco e delega ao `MessagingProvider`.

**`Cargo.toml`**
```toml
[package]
name = "data_whatsapp"
version = "0.1.0"
edition.workspace = true

[[bin]]
name = "data_whatsapp"
path = "src/main.rs"

[dependencies]
contracts                = { workspace = true }
transport                = { workspace = true }
error_core               = { workspace = true }
observability            = { workspace = true }
infrastructure_messaging = { path = "../../crates/infrastructure_messaging" }
infrastructure_evolution = { path = "../../crates/infrastructure_evolution" }
tokio      = { workspace = true }
serde      = { workspace = true }
serde_json = { workspace = true }
tracing    = { workspace = true }
secrecy    = { workspace = true }
async-trait = { workspace = true }
uuid       = { workspace = true }
```

RPCs: `CreateWhatsappInstance`, `DeleteWhatsappInstance`, `ReconnectWhatsappInstance`,
`GetWhatsappInstanceStatus`, `SendWhatsappMessage`, `SendWhatsappMedia`, `AdminBulkDisconnectInstances`.

```rust
#[tracing::instrument(skip_all, fields(rpc = "CreateWhatsappInstance", tenant_id = %req.tenant_id))]
async fn create_whatsapp_instance(&self, req: CreateReq) -> Result<CreateResp, RpcError> {
    // 1. cria no provedor
    let result = self.provider.create_instance(&req.instance_name, None).await?;
    let instance_token = SecretString::new(result.instance_token.clone());

    // 2. persiste via data_postgres (token encriptado)
    let db_record = rpc_data_postgres
        .create_whatsapp_instance_record(/* ... */)
        .await?;

    // 3. configura webhook: URL inclui provider no path para detecção automática
    let webhook_url = format!(
        "http://webhook_ingress:9200/webhook/evolution/{}/{}",
        req.tenant_id, db_record.id
    );
    self.provider
        .configure_webhook(
            &req.instance_name,
            &instance_token,
            &webhook_url,
            &["MESSAGES_UPSERT".into(), "CONNECTION_UPDATE".into()],
        )
        .await?;

    // 4. publica auditoria em security:stream (sem token)
    transport::bus::publicar_evento_seguranca(
        &mut self.redis,
        &TenantEnvelope::novo(
            req.tenant_id,
            "whatsapp.instance.create".into(),
            serde_json::json!({
                "user_id":       req.user_id,
                "instance_name": req.instance_name,
                "provider":      "evolution"
            }),
        ),
    ).await?;

    Ok(/* ... */)
}

#[tracing::instrument(skip_all, fields(rpc = "AdminBulkDisconnectInstances"))]
async fn admin_bulk_disconnect(&self, tenant_id: Option<Uuid>) -> Result<u32, RpcError> {
    let instancias = if tenant_id.is_some() {
        rpc_data_postgres.list_whatsapp_instances(tenant_id).await?
    } else {
        rpc_data_postgres.admin_list_all_connected_instances().await?
    };
    for inst in &instancias {
        let token = SecretString::new(inst.api_key_decrypted.clone());
        let _ = self.provider.disconnect_instance(&inst.name, &token).await;
        rpc_data_postgres.set_connection_state(&inst.id, "disconnected").await?;
    }
    Ok(instancias.len() as u32)
}
```

### Observabilidade & Auditoria — E6
- **a) Logs/traces**: `#[instrument(skip_all, fields(rpc, tenant_id))]` em cada handler RPC. `instance_token`
  em memória como `SecretString`; nunca em fields de tracing.
- **b) Auditoria no banco** (via `transport::bus::publicar_evento_seguranca` → `security:stream` →
  `data_postgres` consumer → `audit_log`):
  - `whatsapp.instance.create` — `context`: `{ instance_name, provider }`; `user_id`; `tenant_id`. **Sem token.**
  - `whatsapp.instance.delete` — `context`: `{ instance_name }`; `user_id`; `tenant_id`.
  - Campos `audit_log`: `timestamp` (UTC), `level = "INFO"`, `service = "data_whatsapp"`, `trace_id`,
    `event`, `message`, `context` (JSONB), `user_id`.
- **c) Sanitização**: nenhum payload de auditoria inclui `api_key`/`instance_token`. `skip_all` no instrument.

---

## E7. `control_plane` + `data_postgres`

- **`data_postgres`**: registra os handlers do módulo `whatsapp` (E4); o consumer do `security:stream`
  (já existente) apenas adiciona os novos `event_type` `whatsapp.*` ao catálogo.
- **`control_plane`**: remove `src/evolution.rs` legado; expõe endpoint admin
  `POST /api/v2/admin/whatsapp/disconnect-all` → RPC `AdminBulkDisconnectInstances`.

```rust
// control_plane: endpoint admin (mantém axum 0.7.5)
#[tracing::instrument(err, skip_all, fields(admin_action = "bulk_disconnect", scope))]
async fn disconnect_all(
    Extension(ctx): Extension<RequestContext>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<DisconnectAllBody>,
) -> Result<Json<DisconnectAllResp>, ApiError> {
    let scope = body.tenant_id
        .map(|t| t.to_string())
        .unwrap_or_else(|| "global".into());
    tracing::Span::current().record("scope", &scope);

    let count = rpc_data_whatsapp.admin_bulk_disconnect(body.tenant_id).await?;

    // auditoria enriquecida com ip_address, user_agent e user_id do RequestContext
    let ip = addr.ip().to_string();
    let ua = headers.get("user-agent").and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    transport::bus::publicar_evento_seguranca(
        &mut redis,
        &TenantEnvelope::novo(
            body.tenant_id.unwrap_or(Uuid::nil()), // tenant_id nil → ação global
            "whatsapp.admin.bulk_disconnect".into(),
            serde_json::json!({
                "scope":      scope,
                "count":      count,
                "user_id":    ctx.user_id,
                "ip_address": ip,
                "user_agent": ua,
            }),
        ),
    ).await?;

    // resposta SEM tokens — apenas count, scope
    Ok(Json(DisconnectAllResp { count, scope }))
}
```

### Observabilidade & Auditoria — E7
- **a) Logs/traces**: `data_postgres` consumer com `#[instrument]` no handler de gravação de `audit_log`.
  `control_plane`: `#[instrument(err, fields(admin_action = "bulk_disconnect", scope))]`.
- **b) Auditoria no banco**: `control_plane` publica `whatsapp.admin.bulk_disconnect` enriquecido com
  `ip_address`, `user_agent`, `user_id`; `data_postgres` consumer grava em `audit_log` (campo `context` JSONB).
  `tenant_id` `nil` (UUID zero) para ação global — suportado pelo schema real `0010_audit_log.sql`
  (coluna `tenant_id` NULLABLE com índice dedicado para ações globais).
- **c) Sanitização**: resposta do endpoint **não inclui tokens** — apenas `count` e `scope`. Nenhum segredo
  no `context` da auditoria.

---

## Arquitetura (visão consolidada)

```
control_plane / worker ──RPC──► data_whatsapp ──(MessagingProvider)──► infrastructure_evolution ──HTTP──► Evolution API
       │                             │
       │ (auditoria)                 └──RPC──► data_postgres (whatsapp_* + audit_log)
       ▼
  security:stream ────────────────► data_postgres consumer ──► audit_log

Evolution API ──POST webhook──► webhook_ingress ──normaliza──► events:stream ──► messaging_gateway / worker

Stacks Docker:
  - principal : control_plane, data_whatsapp, webhook_ingress, data_postgres, worker, ...
  - Evolution  : container `evolution` + `postgres-evolution` (isolados)
  - rede       : smart_core_v2_evolution_net (external para a stack principal)
```

---

# Fase V — Validation

### V1. Compilação e contratos
- `cargo build -p infrastructure_messaging -p infrastructure_evolution -p webhook_ingress -p data_whatsapp`.
- Regenerar cache **SQLx offline** após reescrita da migração `0008_whatsapp_sync.sql`.

### V2. Testes (scripts canônicos — `.\infra\test-local.ps1`)
- `infrastructure_messaging`: enums round-trip serde; `MessagingProviderError` Display.
- `infrastructure_evolution`: `map_state` (open/close/connecting/unknown); parse de `key.id`;
  truncamento de body de erro ≤ 200 chars; fronteira HTTP mockada (não bater no Evolution real).
- `infrastructure_postgres` módulo whatsapp: handlers com transação+rollback (`#[sqlx::test]`);
  RLS por tenant; admin bypass exige `operacional:admin`.
- `webhook_ingress`: roteamento axum 0.8 com `{param}`; `normalize_evolution` para `messages.upsert`
  e `connection.update`; `body` **não aparece** em fields de spans (asserção explícita).

### V3. Validação manual de integração (stack Docker)
1. Subir stack Evolution isolada.
2. `CreateWhatsappInstance` → confirmar `PUT /webhook/set/{name}` com `webhookByEvents:false` e URL correta.
3. Escanear QR; enviar texto; verificar `whatsapp.message.received` em `events:stream`.
4. Verificar `connection.update` → `whatsapp.connection.updated` em `events:stream`.

### V4. Validação de observabilidade/auditoria
- Confirmar que logs **não** contêm `apikey`, `instance_token`, body de webhook, telefone ou conteúdo.
- Confirmar registros em `audit_log` para create/delete/bulk_disconnect com `context` sem segredos e
  `tenant_id` nil quando ação global.

### Observabilidade & Auditoria — Fase V
- **a)** Validação ativa de spans esperados com fields de correlação (`service`, `env`, `tenant_id`, `trace_id`).
- **b)** Testes de integração verificam linhas em `audit_log` para os 3 eventos `whatsapp.*`.
- **c)** Teste explícito (V4) garantindo ausência de segredos/PII em logs e em `audit_log.context`.

---

# Fase C — Confirmation

### C1. Critérios de pronto
- Build e testes (V1–V2) verdes via `.\infra\test-local.ps1`.
- Integração manual (V3) e auditoria (V4) confirmadas.
- `control_plane/src/evolution.rs` e `infrastructure_postgres/src/integracoes/evolution.rs` removidos;
  nenhuma referência a `evolution_sync_*` remanescente (grep limpo).
- Nenhum `axum` adicionado ao `Cargo.toml` do workspace.

### C2. Gate de final-review
- Rodar `/prevc-final-review`: compara implementado × este plano, corrige desvios, arquiva e commita.
- Sem auto-referência nos commits (MEMORY "git-no-self-reference"); branches gitflow.

### C3. Documentação
- `doc_dev/apis/evolution/` já atualizado (docs do Evolution API criados neste ciclo).
- `doc_dev/libs/rust/axum.md` já atualizado com 0.7.5 / 0.8 (feito na reestruturação).

### Observabilidade & Auditoria — Fase C
- **a)** Confirmar dashboards reconhecem `service = "webhook_ingress"` e `service = "data_whatsapp"`.
- **b)** Confirmar eventos `whatsapp.*` visíveis no painel admin (via `runtime_api`).
- **c)** Assinatura final de revisão confirmando que nenhum segredo vazou em logs ou em `audit_log.context`.

---

# Correções Aplicadas

1. **axum 0.8 — rota do `webhook_ingress`**: `:provider/:tenant_id/:instance_id` (causa **panic** em 0.8)
   → **`{provider}/{tenant_id}/{instance_id}`**.
2. **axum 0.8 — inicialização do servidor**: `Server::bind().serve()` → **`TcpListener` + `axum::serve(listener, app)`**;
   `.with_state(state)` obrigatório; `Extension<T>` → `State<T>`.
3. **axum não entra no workspace**: `runtime_api` mantém 0.7.5; `webhook_ingress` declara `axum = "0.8"` **localmente**.
4. **Evolution API — `configure_webhook`**: método corrigido para **`PUT /webhook/set/{name}`** (não POST);
   body com **`webhookByEvents: false`** (todos os eventos na mesma URL).
5. **Auth Evolution explicitada**: header `apikey` com **global token** para operações de instância e
   **instance token (`hash`)** para enviar mensagens.
6. **Stream key real**: `events:stream` (`STREAM_EVENTOS`) via `transport::bus::publicar_evento`;
   auditoria via `security:stream` (`STREAM_SEGURANCA`) → `audit_log` real (`0010_audit_log.sql`).
7. **`data_whatsapp` é app novo, não renomeação**: `apps/data_evolution` não existe; código extraído de
   `control_plane/src/evolution.rs` + `infrastructure_postgres/src/integracoes/evolution.rs`.
8. **Migração — arquivo e conteúdo**: `0008_evolution_sync.sql` → `0008_whatsapp_sync.sql`; tabelas
   `evolution_sync_*` → `whatsapp_*`; `UNIQUE (name)` global removido (quebrava multi-tenancy).
9. **Caminhos ajustados** ao layout real: `server/crates/`, `server/apps/`.
10. **Campos de auditoria alinhados** ao schema real `audit_log` (`event`, `message`, `context` JSONB,
    `user_id`, `ip_address`, `trace_id`, `service`; `tenant_id` nil para ação global).
11. **Observabilidade & Auditoria por componente** (eixos a/b/c em E1–E7 e fases R/V/C), com declaração
    explícita de "sem evento de auditoria" onde intencional (E1, E2, E3, E4, E5).
