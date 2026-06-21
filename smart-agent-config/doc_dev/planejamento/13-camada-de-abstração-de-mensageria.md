# Plano de Implementação: Camada de Abstração de Mensageria (WhatsApp) e Integração com Evolution API

Este plano detalha o design arquitetural para introduzir uma **camada de abstração completa de mensageria** no Smart Core Assistant v2. A arquitetura foi desenhada para permitir que qualquer provedor de WhatsApp (como Evolution API, Z-API, Baileys, etc.) seja plugado ou trocado facilmente, de forma totalmente transparente para as regras de negócio dos inquilinos (tenants).

A stack do Evolution API será isolada em um ambiente Docker separado (estilo stack de observabilidade), contendo seu próprio PostgreSQL dedicado de forma autocontida.

---

## Contexto e Premissas

### Abstração e Desacoplamento
Para que o sistema seja agnóstico a fornecedores:
1. **Contratos em Rust (Traits)**: Definiremos os comportamentos de mensageria e gerenciamento de instâncias em uma interface genérica (`MessagingProvider`).
2. **Normalização de Dados**: Todas as informações específicas de provedores (respostas de criação, estados de conexão, mídias e webhooks) serão traduzidas para estruturas de dados neutras da nossa aplicação.
3. **Normalização no Ingress**: O micro-serviço `webhook_ingress` receberá webhooks proprietários de cada provedor, convertendo-os em eventos universais antes de publicá-los no barramento Redis Streams (ex: `whatsapp.message.received`, `whatsapp.connection.updated`). O restante do sistema (worker, CRM) só consumirá eventos normalizados.
4. **Banco de Dados Limpo (WhatsApp Sync)**: Como o sistema está no início da implementação, reescreveremos o schema de banco de dados original. O arquivo de migração original de sincronização será redefinido diretamente para criar tabelas genéricas (`whatsapp_instance`, `whatsapp_contact` e `whatsapp_whitelist`) contendo a coluna `provider` (sem valor padrão físico que acople ao Evolution API).

---

## Decisões de Design

### D1. Estruturação das Crates de Abstração
Criaremos duas crates para separar a interface dos provedores reais:
- **`crates/infrastructure_messaging`**: Crate abstrata que define a trait `MessagingProvider`, os enums normalizados (ex: `ConnectionState`, `MediaType`) e as structs de payloads de entrada/saída comuns.
- **`crates/infrastructure_evolution`**: Crate que depende da anterior e implementa a trait `MessagingProvider` fazendo chamadas HTTP REST para o servidor Evolution API.

Se no futuro surgir outro provedor, basta implementar a trait em um novo crate `crates/infrastructure_outro` sem alterar o restante da aplicação.

### D2. Roteamento Dinâmico em `apps/data_whatsapp`
O app `apps/data_evolution` será renomeado para `apps/data_whatsapp`. Ele atuará como o orquestrador RPC genérico. Ao receber um comando RPC (ex: `CreateWhatsappInstance`, `SendWhatsappMessage`):
1. Ele consultará o banco para obter os dados da instância (incluindo o campo `provider`).
2. Em tempo de execução, delegará a operação para a struct correspondente que implementa `MessagingProvider` baseado no provedor configurado.

### D3. Webhooks com Detecção de Provedor via Path da URL
Para evitar consultas de banco de dados na hot path do webhook, a URL configurada nos provedores terá o seguinte formato:
```
http://webhook_ingress:9200/webhook/{provider}/{tenant_id}/{instance_id}
```
Onde `{provider}` indica o parser que o `webhook_ingress` deve usar (ex: `evolution`). O `webhook_ingress` extrai o provedor e os IDs do path, parseia o JSON proprietário correspondente ao provedor e publica o evento normalizado no barramento contendo `{tenant_id}` e `{instance_id}`.

### D4. Desconexão em Massa pelo Administrador
O administrador do Smart Core precisa conseguir desconectar instâncias em lote. Criaremos a rota RPC `AdminBulkDisconnectInstances` em `data_whatsapp`, consumida por rotas do painel admin em `control_plane`.
Essa rota funcionará da seguinte forma:
- Aceita um parâmetro opcional `tenant_id: Option<Uuid>`.
- Se `tenant_id` for fornecido: busca todas as instâncias ativas daquele tenant e executa o logout no provedor associado.
- Se `tenant_id` for `None` (Global): roda com bypass de RLS (`operacional:admin`) buscando todas as instâncias ativas de todos os tenants no sistema e desconecta todas elas individualmente em seus respectivos provedores.
- Atualiza os registros do banco de dados para `connection_state = 'disconnected'`.

---

## Arquitetura Proposta

```
                     === STACK DE APLICAÇÃO PRINCIPAL ===
  ┌──────────────────────────────────────────────────────────────────┐
  │ ┌──────────────┐    ┌──────────────┐         ┌────────────────┐ │
  │ │control_plane │    │    worker    │ ◄─────► │  runtime_api   │ │
  │ └──────┬───────┘    └──────┬───────┘         └────────────────┘ │
  │        │ RPC               │ RPC                                │
  │        └─────────────────┐ │                                    │
  │                          ▼ ▼                                    │
  │                  ┌──────────────────┐                           │
  │                  │  data_whatsapp   │ ── RPC ──► data_postgres  │
  │                  │ (usa Trait gen.) │   (limites, registros)   │
  │                  └────────┬─────────┘                           │
  │                           │                                     │
  │  ┌────────────────────────┼───────────────────────────────────┐ │
  │  │ Rede: smart_core_v2_evolution_net (external)               │ │
  │  └────────────────────────┼───────────────────────────────────┘ │
  │                           │ HTTP REST                           │
  │  ┌────────────────────┐   │                                     │
  │  │  webhook_ingress   │◄──┼──── Webhook HTTP POST ───────────── │
  │  │  (normalizador)    │   │                                     │
  │  └────────┬───────────┘   │                                     │
  │           │ Redis Streams │                                     │
  │           ▼               │                                     │
  │  ┌────────────────────┐   │                                     │
  │  │messaging_gateway   │   │  (inalterado — consome barramento) │
  │  └────────────────────┘   │                                     │
  └───────────────────────────┼─────────────────────────────────────┘
                              │
                      === STACK DO EVOLUTION API ===
  ┌───────────────────────────┼─────────────────────────────────────┐
  │                    ┌──────▼───────┐                             │
  │                    │  evolution   │ (evoapicloud/evolution-go)  │
  │                    └──────┬───────┘                             │
  │                           │                                     │
  │                ┌──────────▼──────────┐                          │
  │                │ postgres-evolution  │                          │
  │                └─────────────────────┘                          │
  └─────────────────────────────────────────────────────────────────┘
```

---

## User Review Required

> [!IMPORTANT]
> **Modificação do Banco de Dados**: Reescreveremos o arquivo de migração original em vez de fazer migrações incrementais de renomeação. O arquivo original [0008_evolution_sync.sql](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_postgres/migrations/0008_evolution_sync.sql) será renomeado para `0008_whatsapp_sync.sql` e seu conteúdo alterado para criar as tabelas `whatsapp_instance` (contendo o campo `provider` sem valor padrão fixo), `whatsapp_contact` e `whatsapp_whitelist`.

> [!TIP]
> **Gestão de Provedor por Instância**: Com o campo `provider` na tabela `whatsapp_instance`, as instâncias são vinculadas ao seu respectivo provedor na criação, permitindo roteamento dinâmico transparente durante o envio de mensagens e processamento de status.

---

## Open Questions

*Nenhuma questão em aberto identicada.*

---

## Proposed Changes

### Componente 1: Camada de Abstração de Mensageria (`infrastructure_messaging`)

#### [NEW] [Cargo.toml](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_messaging/Cargo.toml)
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

#### [NEW] [errors.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_messaging/src/errors.rs)
```rust
#[derive(Debug, thiserror::Error)]
pub enum MessagingProviderError {
    #[error("Erro de conexão/rede no provedor: {0}")]
    Network(String),
    
    #[error("O provedor retornou erro HTTP (status {status}): {body}")]
    ProviderApi { status: u16, body: String },
    
    #[error("Falha ao processar resposta do provedor: {0}")]
    Deserialization(String),
    
    #[error("Erro de configuração do provedor: {0}")]
    Config(String),
    
    #[error("Operação inválida no estado atual: {0}")]
    InvalidState(String),
}
```

#### [NEW] [lib.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_messaging/src/lib.rs)
```rust
pub mod errors;

use async_trait::async_trait;
use secrecy::SecretString;

pub use errors::MessagingProviderError;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState {
    Connected,
    Disconnected,
    Connecting,
    Unknown,
}

impl ConnectionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Connected => "connected",
            Self::Disconnected => "disconnected",
            Self::Connecting => "connecting",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreateInstanceResult {
    pub provider_instance_id: String,
    pub instance_token: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SendMessageResult {
    pub message_id: String,
}

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MediaType {
    Image,
    Video,
    Audio,
    Document,
}

impl MediaType {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Image => "image",
            Self::Video => "video",
            Self::Audio => "audio",
            Self::Document => "document",
        }
    }
}

/// Contrato abstrato e unificado de provedores de WhatsApp/Chat.
#[async_trait]
pub trait MessagingProvider: Send + Sync {
    /// Nome identificador do provedor (ex: "evolution").
    fn provider_name(&self) -> &'static str;

    /// Cria fisicamente uma instância de comunicação no provedor.
    async fn create_instance(
        &self,
        instance_name: &str,
        custom_token: Option<&SecretString>,
    ) -> Result<CreateInstanceResult, MessagingProviderError>;

    /// Exclui permanentemente uma instância física do provedor.
    async fn delete_instance(&self, instance_name: &str) -> Result<(), MessagingProviderError>;

    /// Inicia/conecta a sessão de uma instância no provedor.
    async fn connect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError>;

    /// Faz logout/desconecta a sessão de WhatsApp da instância sem excluí-la.
    async fn disconnect_instance(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<(), MessagingProviderError>;

    /// Retorna o QR Code em base64 para conexão.
    async fn get_qr_code(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
    ) -> Result<String, MessagingProviderError>;

    /// Envia solicitação de pareamento via código de telefone.
    async fn pair_by_phone(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        phone_number: &str,
    ) -> Result<String, MessagingProviderError>;

    /// Configura o destino e eventos do webhook da instância.
    async fn configure_webhook(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        webhook_url: &str,
        events: &[String],
    ) -> Result<(), MessagingProviderError>;

    /// Retorna o estado atual da conexão da instância.
    async fn get_connection_state(
        &self,
        instance_name: &str,
    ) -> Result<ConnectionState, MessagingProviderError>;

    /// Envia uma mensagem de texto simples.
    async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        text: &str,
    ) -> Result<SendMessageResult, MessagingProviderError>;

    /// Envia uma mensagem de mídia (imagem, vídeo, áudio ou documento).
    async fn send_media(
        &self,
        instance_name: &str,
        instance_token: &SecretString,
        to_number: &str,
        media_type: MediaType,
        media_url: &str,
        caption: Option<&str>,
    ) -> Result<SendMessageResult, MessagingProviderError>;

    /// Lista todas as instâncias existentes no provedor físico.
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}
```

---

### Componente 2: Implementação da Evolution API (`infrastructure_evolution`)

#### [NEW] [Cargo.toml](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_evolution/Cargo.toml)
```toml
[package]
name = "infrastructure_evolution"
version = "0.1.0"
edition.workspace = true

[dependencies]
infrastructure_messaging = { path = "../infrastructure_messaging" }
reqwest                  = { version = "0.12", features = ["json"] }
serde                    = { workspace = true }
serde_json               = { workspace = true }
secrecy                  = { workspace = true }
async-trait              = { workspace = true }
thiserror                = { workspace = true }
tracing                  = { workspace = true }
```

#### [NEW] [client.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_evolution/src/client.rs)
Contém a struct `EvolutionProvider` que implementa `MessagingProvider` realizando as chamadas REST mapeadas.

---

### Componente 3: Alterações no Banco de Dados (Reescrita do Schema)

#### [NEW] [0008_whatsapp_sync.sql](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_postgres/migrations/0008_whatsapp_sync.sql) (Substitui `0008_evolution_sync.sql`)
```sql
-- =============================================================================
-- Módulo Integrações WhatsApp Genérico: instâncias, contatos e whitelist
-- =============================================================================

-- whatsapp_instance: configuração da instância física na API de WhatsApp configurada
CREATE TABLE whatsapp_instance (
    id                    SERIAL PRIMARY KEY,
    tenant_id             UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    name                  VARCHAR(100) NOT NULL,
    instance_id           VARCHAR(100) UNIQUE,
    api_key               VARCHAR(256) NOT NULL,
    phone_number          VARCHAR(20),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    connection_state      VARCHAR(20) NOT NULL DEFAULT 'unknown',
    last_state_check      TIMESTAMPTZ,
    media_storage_backend VARCHAR(10) NOT NULL DEFAULT 's3',
    provider              VARCHAR(50) NOT NULL, -- evolution, zapi, etc.
    subscribed_events     JSONB NOT NULL DEFAULT '[]',
    last_connection_state VARCHAR(50),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name),
    UNIQUE (tenant_id, name)
);

ALTER TABLE whatsapp_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_instance FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_instance_tenant_isolation ON whatsapp_instance
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX whatsapp_instance_tenant_state
    ON whatsapp_instance (tenant_id, active, connection_state);

-- whatsapp_contact: mapeamento JID/LID → Contato do CRM
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
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX whatsapp_contact_tenant_jid ON whatsapp_contact (tenant_id, jid);
CREATE INDEX whatsapp_contact_tenant_lid ON whatsapp_contact (tenant_id, lid);
CREATE INDEX whatsapp_contact_tenant_crm ON whatsapp_contact (tenant_id, contact_id);

-- whatsapp_whitelist: números que o bot deve ignorar completamente
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
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX whatsapp_whitelist_tenant_phone ON whatsapp_whitelist (tenant_id, phone_number);
```

#### [DELETE] [0008_evolution_sync.sql](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_postgres/migrations/0008_evolution_sync.sql)
Removido em favor da migração limpa `0008_whatsapp_sync.sql`.

---

### Componente 4: Crate `infrastructure_postgres` (Repositório)

#### [NEW] [whatsapp.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_postgres/src/integracoes/whatsapp.rs) (Substitui `evolution.rs`)
- Structs atualizadas: `WhatsappInstance`, `WhatsappContact`.
- Toda interação SQL direcionada às novas tabelas `whatsapp_instance` e `whatsapp_contact`.
- Mapeamento e persistência do campo `provider` sem valores defaults acoplados.

#### [DELETE] [evolution.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/crates/infrastructure_postgres/src/integracoes/evolution.rs)
Removido para dar lugar ao arquivo agnóstico `whatsapp.rs`.

---

### Componente 5: Novo Micro-serviço `apps/webhook_ingress`

#### [NEW] [Cargo.toml](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/webhook_ingress/Cargo.toml)
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
tokio                    = { workspace = true }
serde_json               = { workspace = true }
serde                    = { workspace = true }
tracing                  = { workspace = true }
axum                     = "0.8"
redis                    = { workspace = true }
uuid                     = { workspace = true }
```

#### [NEW] [main.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/webhook_ingress/src/main.rs)
- Expõe a rota axum `POST /webhook/:provider/:tenant_id/:instance_id`.
- Lê o payload bruto, decide qual parser usar baseado no parâmetro `:provider` do path:
  - Se for `evolution`: converte de `MESSAGES_UPSERT` para evento normalizado `whatsapp.message.received`, e de `CONNECTION_UPDATE` para `whatsapp.connection.updated`.
- Publica o evento normalizado no Redis Streams do barramento interno do Smart Core.

---

### Componente 6: Crate `apps/data_whatsapp` (antigo `data_evolution`)

#### [NEW] [Cargo.toml](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/data_whatsapp/Cargo.toml)
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
tokio                    = { workspace = true }
serde_json               = { workspace = true }
serde                    = { workspace = true }
tracing                  = { workspace = true }
secrecy                  = { workspace = true }
async-trait              = { workspace = true }
uuid                     = { workspace = true }
```

#### [NEW] [main.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/data_whatsapp/src/main.rs)
- Carrega as configurações dos provedores (ex: url e global token da Evolution).
- Provê factory para instanciar a trait `dyn MessagingProvider` com base no provedor solicitado.
- Executa as rotas RPC de orquestração:
  - `CreateWhatsappInstance`
  - `DeleteWhatsappInstance`
  - `ReconnectWhatsappInstance`
  - `GetWhatsappInstanceStatus`
  - `SendWhatsappMessage`
  - `SendWhatsappMedia`
  - **`AdminBulkDisconnectInstances`** (Busca em lote no Postgres desativando o RLS e desconecta tudo via trait de provedor).

---

### Componente 7: Handlers no `data_postgres` e `control_plane`

#### [MODIFY] [data_postgres/src/main.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/data_postgres/src/main.rs)
- Substituir queries das tabelas antigas para as novas `whatsapp_*`.
- Implementar os handlers: `GetWhatsappInstance`, `CreateWhatsappInstanceRecord`, `ListWhatsappInstances`, `DeactivateWhatsappInstanceRecord`, `AdminListAllConnectedInstances`.

#### [MODIFY] [control_plane/src/main.rs](file:///c:/PROJETOS/FULL-STACK/smart-core-assistant-v2/server/apps/control_plane/src/main.rs)
- Mapear endpoints de controle do WhatsApp para redirecionar RPCs para `data_whatsapp`.
- Adicionar endpoint de admin: `/api/v2/admin/whatsapp/disconnect-all` que dispara RPC `AdminBulkDisconnectInstances` para o `data_whatsapp`.

---

## Verification Plan

### Sequência de Inicialização das Stacks
1. **Stack de Observabilidade**: `docker/observability` → Cria a rede `smart_core_v2_observability`.
2. **Stack do Evolution**: `docker/evolution` → Cria a rede `smart_core_v2_evolution_net` + postgres-evolution + evolution.
3. **Stack Principal**: `docker/dev` → Referencia ambas as redes como `external` e inicia os microsserviços Rust (incluindo `data_whatsapp` e `webhook_ingress`).

### Manual Verification
1. **Camada de Abstração Funcional**:
   - Chamar RPC `CreateWhatsappInstance` com provedor = `evolution`.
   - Confirmar que a instância foi criada no servidor da Evolution e o registro foi inserido na tabela `whatsapp_instance` com `provider = 'evolution'`.
2. **Normalização de Webhooks**:
   - Disparar um webhook simulado de mensagens recebidas para `POST /webhook/evolution/{tenant_id}/{instance_id}`.
   - Monitorar o barramento do Redis para garantir que o evento foi publicado no barramento em formato neutro normalizado (`whatsapp.message.received`) sem vazar chaves da Evolution.
3. **Desconexão e Troca de Provedor**:
   - Executar a desconexão no painel para desvincular a instância.
   - Simular a mudança do registro da instância para um provedor dummy ou novo provedor na tabela e validar se o sistema direciona as chamadas subsequentes de forma limpa.
4. **Desconexão Massiva do Admin**:
   - Criar 3 instâncias conectadas de inquilinos diferentes.
   - Disparar rota admin `/api/v2/admin/whatsapp/disconnect-all` (sem tenant).
   - Verificar nos logs e no servidor Evolution que todas as instâncias foram desconectadas/deslogadas de uma vez, e que todas foram marcadas como `disconnected` no Postgres.
   - Testar o mesmo endpoint passando um `tenant_id` específico, certificando-se de que apenas as instâncias daquele inquilino foram afetadas.
