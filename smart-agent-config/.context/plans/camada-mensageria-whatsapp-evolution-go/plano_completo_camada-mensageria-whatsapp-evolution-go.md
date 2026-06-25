# Plano Consolidado (v4): Módulo Rust de Mensageria WhatsApp (Evolution Go) — **SOLID & Plugabilidade**

> **Documento único, fonte da verdade técnica.** Reestrutura o plano v3 com ênfase em **conformidade SOLID** e **plugar/desplugar provedores facilmente**. A base anterior usava **um trait gordo** (`MessagingProvider`, ~12-19 métodos) e o `data_whatsapp` segurava um `EvolutionProvider` **concreto** — isso viola **ISP** e **DIP**. Esta versão segrega o contrato em **traits de capacidade**, introduz um **`ProviderRegistry`** (resolve `dyn` pelo campo `provider` da instância) e um **registry de `WebhookNormalizer`** no ingress (OCP). Mantém o realinhamento **Evolution v2 → Evolution Go** (REST + eventos), validado contra o adapter battle-tested `evolution_go_adapter.py`.
>
> **Hierarquia de fontes:** onde a coleta web conflitar com o `evolution_go_adapter.py`, **o adapter prevalece**. Organização em fases **PREVC** (Planning, Review, Execution E1..E6, Validation, Confirmation).

---

## Objetivo

Estruturar o **módulo Rust único** responsável por toda a comunicação com o Evolution Go: criação/gestão de instâncias, conexão/QR, envio de texto/mídia, recursos de sessão (presença, leitura, reações, foto de perfil, download de mídia) e ingestão normalizada de webhooks. As regras de negócio dos tenants **nunca falam com o Evolution diretamente** — só com este módulo, através de **traits Rust** e eventos universais no barramento Redis Streams.

### Premissas (invioláveis)
1. **Tudo atrás de interface (DIP).** Nenhum consumidor depende de tipo concreto: sempre `dyn`. O concreto (`EvolutionProvider`) é resolvido em runtime pelo campo `provider` da instância.
2. **Interfaces segregadas (ISP).** O contrato é quebrado em **capacidades**. Um provedor implementa **só o que suporta**; capacidades ausentes são descobertas em runtime.
3. **Aberto/fechado (OCP).** Provedor novo (Z-API, Baileys…) = nova crate `infrastructure_<x>` + 1 linha no registry + 1 `WebhookNormalizer`. Nenhum `match` espalhado é editado.
4. **Normalização no ingress.** Webhooks proprietários do Go → eventos universais; o resto só consome o normalizado.
5. **Banco genérico multi-provedor.** `whatsapp_*` com coluna `provider` sem default acoplado. **Já implementado** (não mexer).
6. **Segredos sempre `SecretString`.** `global_api_key`/`instance_token`/`api_key` jamais em logs ou respostas; `api_key` encriptado em repouso.

---

## ⚠️ Reconciliação com o repositório real (pré-condição da execução)

### Já implementado e correto (não mexer, apenas validar)
| Componente | Caminho | Situação |
| --- | --- | --- |
| Migração genérica | `infrastructure_postgres/migrations/0008_whatsapp_sync.sql` | ✅ `whatsapp_instance/contact/whitelist`, RLS+FORCE, `provider` sem default. |
| Repositório WhatsApp | `infrastructure_postgres/src/integracoes/whatsapp.rs` | ✅ Neutro de provedor; serve ao Go sem alteração. |
| Port/Adapter | `data_postgres/src/ports/whatsapp.rs`, `src/adapters/whatsapp.rs` | ✅ `WhatsappStore` (port/adapter + `mockall`), RLS + admin BYPASSRLS. **Modelo SOLID exemplar a espelhar.** |

> **`WhatsappStore` é o gabarito a copiar:** port com `#[cfg_attr(test, mockall::automock)]`, métodos coesos, transação no adapter. Os traits de mensageria devem ter o mesmo cheiro.

### A construir/ajustar (realinhamento Go + segregação SOLID)
| Componente | Caminho | Estado HOJE (verificado) | Trabalho |
| --- | --- | --- | --- |
| Crate de contrato | `crates/infrastructure_messaging` | **trait único** de 12 métodos (`create/delete/connect/disconnect/get_qr/pair_by_phone/configure_webhook/get_connection_state/send_text/send_media/list_all` + `provider_name`); endpoints v2 | **E1**: segregar em traits de capacidade + fachada com acessores `Option<&dyn>`; ampliar p/ superfície Go; `Unsupported`; `WebhookConfig`/`AdvancedSettings`/etc.; `ProviderRegistry`. |
| Crate Evolution | `crates/infrastructure_evolution` | `provider.rs` fala **v2** (`/instance/connect/{name}`, `/webhook/set`, `/message/sendText/{name}`, `/instance/connectionState`, `/instance/fetchInstances`, `mediatype`/`media`); `client.rs` desserializa `hash`+`instance.state` (v2) | **E2**: realinhar 100% ao contrato Go implementando os traits segregados + acessores `Some(self)`; remover `pair_by_phone`/`configure_webhook`. |
| App orquestrador | `apps/data_whatsapp` | `AppState { provider: EvolutionProvider, redis_conn }` **concreto**; `configure_webhook` separado; testes wiremock v2 | **E3**: `AppState { registry, redis_conn }`; resolve `dyn` por instância; `connect_instance(&WebhookConfig)`; novos RPCs; testes v2→Go + mock `mockall`. |
| App ingress | `apps/webhook_ingress` | `match params.provider { "evolution" => … }` + só `messages.upsert`/`connection.update` (lowercase) | **E4**: `WebhookNormalizer` registry (OCP) + canonização UPPERCASE/PascalCase. |

### Divergência central: contrato v2 (no código) × Evolution Go (rodando) — **confirmado no `evolution_go_adapter.py`**
| Operação | Código Rust HOJE (v2) | Evolution Go (alvo) | Auth |
| --- | --- | --- | --- |
| Criar | `POST /instance/create` (`integration:WHATSAPP-BAILEYS`,`qrcode:true`) → lê `hash` | `POST /instance/create` `{name, token?}` → lê `token` | global |
| Conectar+webhook | `GET /instance/connect/{name}` **+** `PUT /webhook/set/{name}` (2 chamadas) | `POST /instance/connect` `{instanceName, webhookUrl, subscribe:[…], immediate:true}` (**1 chamada**) | **token instância** ⚠️ |
| QR | `GET /instance/connect/{name}` | `GET /instance/qr` | token instância |
| Estado | `GET /instance/connectionState/{name}` → `instance.state` | `GET /instance/status` → `{state}` (v2 dá **503**) | token instância |
| Listar | `GET /instance/fetchInstances` | `GET /instance/all` → `{data:[…]}` | global |
| Logout | `POST /instance/logout/{name}` | `DELETE /instance/logout` (**sem nome**) | token instância |
| Deletar | `DELETE /instance/delete/{name}` | igual | global |
| Reconectar | (n/d) | `POST /instance/reconnect` | token instância |
| Texto | `POST /message/sendText/{name}` (`{number,text}`) | `POST /send/text` (`{number,text,quoted?}`) | token instância |
| Mídia | `POST /message/sendMedia/{name}` (`media`/`mediatype`) | `POST /send/media` (`type`/`url`/`caption`/`filename`) | token instância |
| Advanced | (n/d) | `PUT /instance/{id}/advanced-settings` | token instância |
| Eventos | `messages.upsert`/`connection.update` | `Message`/`Connection`/`Presence`/`QRCode`/`Contacts` (UPPERCASE/PascalCase+aliases) | — |
| `pair_by_phone` | `POST /instance/pairingCode/{name}` (existe no código) | **fora de escopo** (não usado no Go) — remover do contrato | — |

### Recursos extras do Go (superfície completa — escopo aprovado, confirmados no adapter)
`POST /send/media` `type:audio` (PTT) · `POST /message/react` `{number,reaction,id,fromMe}` · `POST /message/markread` `{number,id:[…]}` · `POST /message/presence` `{number,state,isAudio}` (composing/recording/paused) · `POST /user/avatar` `{number,preview:false}` · `POST /message/downloadmedia` `{message}` → **`base64`**(+`mimetype`).

> ⚠️ **Armadilhas confirmadas no `evolution_go_adapter.py`:**
> 1. `POST /instance/connect` exige o **token da instância** no `apikey`; Global Key dá **401 "not authorized"**.
> 2. O body do connect usa o campo **`subscribe`** (array UPPERCASE: `MESSAGE`,`CONNECTION`,`PRESENCE`,`QRCODE`) + `immediate:true`. **Nota:** há um comentário stale no topo do adapter dizendo o contrário; o **código executado vence** (`connect_instance` envia `subscribe`). Nome inválido **zera** a assinatura → para todo webhook.
> 3. Status é **`GET /instance/status`** (v2 `/connectionState` dá 503 no Go).
> 4. `readMessages=false` em advanced-settings — recibo é explícito via `markread`.
> 5. `alwaysOnline=true` mantém a sessão whatsmeow viva.
> 6. Download: rota real `/message/downloadmedia` (swagger lista `/downloadimage`, incorreto); resposta traz **`base64`** (campo confirmado no docstring do adapter; validar mesmo assim em V3).

Apps existentes: `control_plane`, `data_postgres`, `data_redis`, `data_storage`, `data_whatsapp`, `webhook_ingress`, `messaging_gateway`, `runtime_api`, `worker`.
Crates existentes: `application`, `contracts`, `error_core`, `infrastructure_messaging`, `infrastructure_evolution`, `infrastructure_postgres`, `infrastructure_redis`, `infrastructure_storage`, `observability`, `test_support`, `transport`.

---

## Conformidade SOLID e plugabilidade de provedores (núcleo do design)

### S — Single Responsibility
- `infrastructure_messaging`: **só contratos** (traits + tipos neutros + erro + registry). **Pura** (sem runtime, sem I/O, sem logs).
- `infrastructure_evolution`: **só** o HTTP do Evolution Go atrás dos traits.
- `data_whatsapp`: **só** orquestração (resolve provedor, chama trait, persiste via RPC `data_postgres`, audita).
- `webhook_ingress`: **só** normalização de webhook → evento universal.

### I — Interface Segregation (o ponto-chave)
Em vez de **um** trait com presença/reação/download forçados em todo provedor, o contrato é quebrado em **capacidades**. Núcleo obrigatório (`InstanceManager` + `MessageSender`); o resto é opcional.

```rust
// crates/infrastructure_messaging/src/lib.rs  (PURA)
use async_trait::async_trait;
use secrecy::SecretString;
use std::{collections::HashMap, sync::Arc};
pub use errors::MessagingProviderError;

// ---------- Tipos neutros (independentes de provedor) ----------
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ConnectionState { Connected, Disconnected, Connecting, Unknown }

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MediaType { Image, Video, Audio, Document }

#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PresenceState { Composing, Recording, Paused }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CreateInstanceResult { pub provider_instance_id: String, pub instance_token: String }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SendMessageResult { pub message_id: String }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MediaDownloadResult { pub base64: String, pub mime_type: Option<String> }

/// Webhook embutido no connect do Go (NÃO existe /webhook/set).
#[derive(Debug, Clone)]
pub struct WebhookConfig { pub url: String, pub subscribe: Vec<String> }

#[derive(Debug, Clone)]
pub struct AdvancedSettings {
    pub always_online: bool,   // true: mantém sessão whatsmeow viva
    pub read_messages: bool,   // false: recibo explícito via markread
    pub reject_call: bool,
    pub msg_reject_call: String,
    pub ignore_groups: bool,
    pub ignore_status: bool,
}
impl Default for AdvancedSettings {
    fn default() -> Self {
        Self { always_online: true, read_messages: false, reject_call: false,
                msg_reject_call: String::new(), ignore_groups: false, ignore_status: false }
    }
}

// ---------- Núcleo OBRIGATÓRIO ----------
#[async_trait]
pub trait InstanceManager: Send + Sync {
    fn provider_name(&self) -> &'static str;
    async fn create_instance(&self, name: &str, custom_token: Option<&SecretString>)
        -> Result<CreateInstanceResult, MessagingProviderError>;
    async fn delete_instance(&self, name: &str) -> Result<(), MessagingProviderError>;
    async fn connect_instance(&self, name: &str, token: &SecretString, webhook: &WebhookConfig)
        -> Result<(), MessagingProviderError>;
    async fn disconnect_instance(&self, name: &str, token: &SecretString)
        -> Result<(), MessagingProviderError>;
    async fn reconnect_instance(&self, name: &str, token: &SecretString)
        -> Result<(), MessagingProviderError>;
    async fn get_qr_code(&self, name: &str, token: &SecretString)
        -> Result<String, MessagingProviderError>;
    async fn get_connection_state(&self, name: &str, token: &SecretString)
        -> Result<ConnectionState, MessagingProviderError>;
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}

#[async_trait]
pub trait MessageSender: Send + Sync {
    async fn send_text(&self, name: &str, token: &SecretString, to: &str, text: &str)
        -> Result<SendMessageResult, MessagingProviderError>;
    async fn send_media(&self, name: &str, token: &SecretString, to: &str,
        media: MediaType, url: &str, caption: Option<&str>)
        -> Result<SendMessageResult, MessagingProviderError>;
}

// ---------- Capacidades OPCIONAIS ----------
#[async_trait] pub trait PresenceControl: Send + Sync {
    async fn set_presence(&self, name:&str, token:&SecretString, chat:&str, state:PresenceState, is_audio:bool)
        -> Result<(), MessagingProviderError>;
}
#[async_trait] pub trait ReadReceipts: Send + Sync {
    async fn mark_read(&self, name:&str, token:&SecretString, chat:&str, message_ids:&[String])
        -> Result<(), MessagingProviderError>;
}
#[async_trait] pub trait Reactions: Send + Sync {
    async fn send_reaction(&self, name:&str, token:&SecretString, chat:&str, message_id:&str, emoji:&str, from_me:bool)
        -> Result<SendMessageResult, MessagingProviderError>;
}
#[async_trait] pub trait MediaDownloader: Send + Sync {
    async fn download_media(&self, name:&str, token:&SecretString, message:&serde_json::Value)
        -> Result<MediaDownloadResult, MessagingProviderError>;
}
#[async_trait] pub trait ProfileQuery: Send + Sync {
    async fn get_profile_picture(&self, name:&str, token:&SecretString, number:&str)
        -> Result<Option<String>, MessagingProviderError>;
}
#[async_trait] pub trait AdvancedSettingsControl: Send + Sync {
    async fn set_advanced_settings(&self, instance_id:&str, token:&SecretString, settings:AdvancedSettings)
        -> Result<(), MessagingProviderError>;
}

// ---------- Fachada: núcleo + DESCOBERTA de capacidades (default None) ----------
pub trait MessagingProvider: InstanceManager + MessageSender {
    fn presence(&self) -> Option<&dyn PresenceControl> { None }
    fn read_receipts(&self) -> Option<&dyn ReadReceipts> { None }
    fn reactions(&self) -> Option<&dyn Reactions> { None }
    fn media_downloader(&self) -> Option<&dyn MediaDownloader> { None }
    fn profiles(&self) -> Option<&dyn ProfileQuery> { None }
    fn advanced_settings(&self) -> Option<&dyn AdvancedSettingsControl> { None }
}
```

**Object-safety garantida:** todos os acessores são `&self`, não-genéricos, retornam trait objects ⇒ `Arc<dyn MessagingProvider>` compila. Um provedor mínimo implementa **só 2 traits** (`InstanceManager`+`MessageSender`) e herda os `None`.

**Uso no consumidor (LSP — ausência é explícita, sem no-op/panic):**
```rust
let provider: Arc<dyn MessagingProvider> = state.registry.resolve(provider_name)?;
provider
    .reactions()                                          // Option<&dyn Reactions>
    .ok_or(MessagingProviderError::Unsupported("reaction"))?
    .send_reaction(name, &token, chat, msg_id, emoji, from_me)
    .await?;
```

### D — Dependency Inversion (`ProviderRegistry`, resolve `dyn` por instância)
```rust
// crates/infrastructure_messaging/src/lib.rs  (continuação — só std/Arc/HashMap)
#[derive(Clone, Default)]
pub struct ProviderRegistry { map: Arc<HashMap<String, Arc<dyn MessagingProvider>>> }

impl ProviderRegistry {
    pub fn builder() -> ProviderRegistryBuilder { ProviderRegistryBuilder::default() }
    pub fn resolve(&self, provider: &str)
        -> Result<Arc<dyn MessagingProvider>, MessagingProviderError> {
        self.map.get(provider).cloned()
            .ok_or_else(|| MessagingProviderError::Config(format!("provedor não registrado: {provider}")))
    }
}

#[derive(Default)]
pub struct ProviderRegistryBuilder { map: HashMap<String, Arc<dyn MessagingProvider>> }
impl ProviderRegistryBuilder {
    /// A chave é o `provider_name()` do próprio provedor (fonte única da string).
    pub fn register(mut self, p: Arc<dyn MessagingProvider>) -> Self {
        self.map.insert(p.provider_name().to_string(), p);
        self
    }
    pub fn build(self) -> ProviderRegistry { ProviderRegistry { map: Arc::new(self.map) } }
}
```

**Composition root — `data_whatsapp/main.rs` (ÚNICO lugar que conhece o concreto):**
```rust
let registry = ProviderRegistry::builder()
    .register(Arc::new(EvolutionProvider::new(api_url, SecretString::from(global_key)))) // "evolution"
    // .register(Arc::new(ZApiProvider::new(...)))  // futuro: 1 linha, sem tocar handlers
    .build();
let state = AppState { registry, redis_conn };
```

### O — Open/Closed (registry de normalizadores no ingress)
```rust
// webhook_ingress
pub trait WebhookNormalizer: Send + Sync {
    fn provider(&self) -> &'static str;
    fn normalize(&self, event:&str, raw:&serde_json::Value, tenant:Uuid, instance:i32)
        -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)>;
}
```
Adicionar provedor = novo `XNormalizer` + `registry.register(...)`; o handler não muda.

### Erro (LSP) — novo variante `Unsupported`
```rust
// crates/infrastructure_messaging/src/errors.rs
#[derive(Debug, thiserror::Error)]
pub enum MessagingProviderError {
    #[error("Erro de conexão/rede no provedor: {0}")] Network(String),
    #[error("O provedor retornou erro HTTP (status {status}): {body}")] ProviderApi { status: u16, body: String },
    #[error("Falha ao processar resposta do provedor: {0}")] Deserialization(String),
    #[error("Erro de configuração do provedor: {0}")] Config(String),
    #[error("Operação inválida no estado atual: {0}")] InvalidState(String),
    #[error("Operação não suportada pelo provedor: {0}")] Unsupported(&'static str), // NOVO
}
```

> **Resultado:** plugar um provedor = (1) nova crate implementando só as capacidades suportadas; (2) uma linha no builder; (3) um `WebhookNormalizer`. **Zero** alteração em consumidores, banco ou contratos existentes.

---

## Decisões de Design

- **D1.** Contratos segregados + fachada + `ProviderRegistry` + tipos neutros + `Unsupported` na `infrastructure_messaging` (pura). Remover `pair_by_phone` e `configure_webhook` do contrato (artefatos v2; webhook vive no connect do Go).
- **D2.** `EvolutionProvider` implementa **todas** as capacidades do Go e sobrescreve os acessores da fachada para `Some(self)`. Helper `send_request` central (header `apikey`, `ok_or_api`, body truncado a 200). `global_api_key` (criar/deletar/listar); `instance_token` por chamada nas demais.
- **D3.** `data_whatsapp` resolve provedor por instância via `registry.resolve(provider)` → chama via `dyn`. Capacidades opcionais via acessor + `Unsupported`. Nenhum tipo concreto no consumidor.
- **D4.** Webhook: detecção por path (axum 0.8, `{param}`) + registry de `WebhookNormalizer` + canonização do nome do evento (UPPERCASE/PascalCase/aliases v2 → enum canônico, espelhando `EvolutionEventName.from_raw`).
- **D5.** Desconexão em massa: `AdminBulkDisconnectInstances` (`tenant_id: Option<Uuid>`; `None` ⇒ todos via `AdminListAllConnectedInstances` BYPASSRLS, escopo `operacional:admin`). Resolve o provedor por instância e chama `disconnect_instance`.

---

# Fase P — Planning (output)

**Status: concluída.**

- **Escopo:** segregar o contrato (SOLID) + realinhar 4 componentes Rust ao Evolution Go + ampliar superfície. Nenhuma criação de app; duas estruturas novas (`ProviderRegistry`, `WebhookNormalizer`) dentro de crates existentes; **nenhuma mudança de schema**.
- **Contrato central:** fachada `MessagingProvider` (núcleo `InstanceManager`+`MessageSender`) + capacidades opcionais descobertas em runtime.
- **Eventos normalizados** em `events:stream`: `whatsapp.message.received` (Message), `whatsapp.connection.updated` (Connection), `whatsapp.message.status` (MessageUpdate), `whatsapp.presence.updated` (Presence), `whatsapp.contact.updated` (Contacts — 2ª iteração).
- **Auditoria** em `security:stream` → `audit_log`: `whatsapp.instance.create/delete`, `whatsapp.admin.bulk_disconnect`.
- **Mapa de risco:** a segregação **quebra os call-sites atuais** de `data_whatsapp` (refactor maior que "só realinhar"); contrato Go indocumentado (mitigado pelo adapter); `subscribe` inválido zera webhooks; dois `axum` coexistem (0.7.5 runtime_api / 0.8 webhook_ingress) — **não unificar**.

### Observabilidade & Auditoria (P)
Definição transversal aplicada em todas as fases:
- **Eixo A (logs/traces):** `#[instrument(err, skip(<segredos>))]`; campos de correlação `service`, `env`, `tenant_id`, `trace_id`, `error_code`.
- **Eixo B (auditoria):** `audit_log` via `transport::bus::publicar_evento_seguranca` → `security:stream`. Eventos: `whatsapp.instance.create/delete`, `whatsapp.admin.bulk_disconnect`. `context` JSONB **sem token**; `tenant_id` NULL quando ação global de superusuário.
- **Eixo C (sanitização):** `SecretString` sempre em `skip(...)`; body de erro truncado a 200 chars; **body de webhook nunca logado** (PII).

---

# Fase R — Review (arquitetura e contratos)

### R1. Compatibilidade de versões
- `runtime_api` em **axum 0.7.5**; `webhook_ingress` em **axum 0.8** local. **NÃO** adicionar `axum` ao workspace. `reqwest 0.12` (feature `json`) em `infrastructure_evolution`.
- Reuso: `async-trait 0.1`, `serde`/`serde_json 1.0`, `secrecy 0.10`, `thiserror 1.0`, `uuid 1.0`, `tracing 0.1`, `redis 0.25`, `mockall 0.13` (dev), `wiremock 0.6` (dev), `contracts`, `transport`, `error_core`, `observability`. Todas USAR LOCAL (`doc_dev/libs/rust/`).

### R2. Sanidade de segurança
- `global_api_key`/`instance_token`/`api_key` sempre `SecretString`; sempre em `skip(...)`. `api_key` encriptado em repouso. RLS+FORCE em todas as `whatsapp_*`; bypass cross-tenant só por `admin_pool` sob `operacional:admin`. Body de erro truncado a 200.

### R3. Decisões de contrato (SOLID + barramento)
- **Object-safety** confirmada (`Arc<dyn MessagingProvider>`). Acessores `&self` não-genéricos.
- **Capacidade ausente** → `Unsupported` (sem `panic`, sem no-op) — respeita LSP.
- Reaproveitar `contracts::TenantEnvelope<T>` + `transport::bus::publicar_evento(_seguranca)`.
- **`connect_instance(&WebhookConfig)`** absorve o webhook (Go não tem `/webhook/set`); `configure_webhook`/`pair_by_phone` removidos do contrato.

### Observabilidade & Auditoria (R)
- Confirmado: política de `#[instrument(err, skip(segredos))]` é compatível com a assinatura de cada trait (segredos sempre em parâmetro próprio, fácil de pular). Auditoria reusa o mesmo `TenantEnvelope::novo(tenant, "whatsapp.*", context)` já presente no `data_whatsapp` atual.

**Gate R:** aprovado se R1/R2/R3 confirmados. Saída → Execution.

---

# Fase E — Execution (detalhe técnico)

## E1. `infrastructure_messaging` — segregar + ampliar o contrato

**Arquivos:** `src/lib.rs` (substituir trait único pelos snippets da seção SOLID), `src/errors.rs` (adicionar `Unsupported`), `src/registry.rs` (novo — `ProviderRegistry`/builder).

**Trabalho:**
1. **Remover** o trait único `MessagingProvider` de 12 métodos.
2. **Adicionar** `InstanceManager`, `MessageSender` (núcleo) + `PresenceControl`, `ReadReceipts`, `Reactions`, `MediaDownloader`, `ProfileQuery`, `AdvancedSettingsControl` (opcionais) + fachada `MessagingProvider` com acessores `Option<&dyn …>` default `None`.
3. **Tipos novos:** `PresenceState`, `WebhookConfig`, `AdvancedSettings` (com `Default` ⇒ `always_online:true`, `read_messages:false`), `MediaDownloadResult`. Manter `ConnectionState`, `MediaType`, `CreateInstanceResult`, `SendMessageResult`.
4. **`MessagingProviderError::Unsupported(&'static str)`**.
5. **`ProviderRegistry` + `ProviderRegistryBuilder`** (só `std`/`Arc`/`HashMap`).
6. **Remover** `pair_by_phone` e `configure_webhook` do contrato.

**Testes da crate (atualizar/adicionar):** round-trip serde dos enums (incl. `PresenceState`); `Display` de erro incl. `Unsupported` ("Operação não suportada pelo provedor: reaction"); **`ProviderRegistry`** (resolve registrado / `Config` para desconhecido); object-safety (compila `Arc<dyn MessagingProvider>`); descoberta de capacidade (mock implementando só núcleo → acessores devolvem `None`).

### Observabilidade & Auditoria (E1)
Crate **pura** — **sem evento de auditoria**, sem logs. `SecretString` nas assinaturas; `Debug` redige segredo automaticamente. Único cuidado: nenhum tipo neutro deve derivar `Serialize` expondo segredo (`WebhookConfig`/`AdvancedSettings` não carregam token).

## E2. `infrastructure_evolution` — implementar capacidades contra o Go

**Arquivos:** `src/client.rs` (structs de desserialização Go + helper `send_request`), `src/provider.rs` (reescrever os `impl` dos traits segregados).

**Tabela canônica (HTTP Go — confirmada no `evolution_go_adapter.py`):**

| Trait::método | HTTP Go | apikey | Body | Parse da resposta |
| --- | --- | --- | --- | --- |
| `InstanceManager::create_instance` | `POST /instance/create` | global | `{name, token?}` | `token` (campo top-level); `id`/`name` opcionais |
| `InstanceManager::delete_instance` | `DELETE /instance/delete/{name}` | global | — | — |
| `InstanceManager::connect_instance` | `POST /instance/connect` | **instância** | `{instanceName, webhookUrl, subscribe:[…], immediate:true}` | ignora corpo (pode trazer QR/status) |
| `InstanceManager::reconnect_instance` | `POST /instance/reconnect` | instância | `{name}` (ou vazio) | — |
| `InstanceManager::disconnect_instance` | `DELETE /instance/logout` | instância | — (sem nome no path) | — |
| `InstanceManager::get_qr_code` | `GET /instance/qr` | instância | — | `base64` ou `code` |
| `InstanceManager::get_connection_state` | `GET /instance/status` | instância | — | `{state}` top-level → `map_state` |
| `InstanceManager::list_all_instances` | `GET /instance/all` | global | — | `{data:[{name}]}` ou `[…]` |
| `MessageSender::send_text` | `POST /send/text` | instância | `{number, text, quoted?}` | `key.id` ou `id` |
| `MessageSender::send_media` | `POST /send/media` | instância | `{number, type, url, caption?, filename?}` | `key.id` |
| `AdvancedSettingsControl::set_advanced_settings` | `PUT /instance/{id}/advanced-settings` | instância | `{alwaysOnline, readMessages, rejectCall, msgRejectCall, ignoreGroups, ignoreStatus}` | — |
| `ReadReceipts::mark_read` | `POST /message/markread` | instância | `{number, id:[…]}` | — |
| `Reactions::send_reaction` | `POST /message/react` | instância | `{number, reaction, id, fromMe}` | `key.id` (se houver) |
| `PresenceControl::set_presence` | `POST /message/presence` | instância | `{number, state, isAudio}` | — |
| `ProfileQuery::get_profile_picture` | `POST /user/avatar` | instância | `{number, preview:false}` | `profilePictureUrl` ou `url` (Option) |
| `MediaDownloader::download_media` | `POST /message/downloadmedia` | instância | `{message:<obj whatsmeow>}` | **`base64`** (+`mimetype`) |

**Detalhes:**
- **`send_request(method, path, apikey, body)`** central espelhando `_send_request` do adapter: header `apikey`, `Content-Type: application/json`, `ok_or_api` (já existe, mantém truncamento a 200).
- **`map_state`:** `open`/`connected`→Connected; `close`/`disconnected`/`loggedOut`→Disconnected; `connecting`→Connecting; resto→Unknown. (Hoje só trata 3 estados — ampliar.)
- **`client.rs`:** trocar `CreateInstanceResp { instance.instanceName, hash }` (v2) por `{token, id?, name?}` (Go); trocar `ConnStateResp { instance.state }` por `{state}` top-level.
- **`media_type` body:** chave **`type`** (não `mediatype`) e **`url`** (não `media`); `caption`/`filename` opcionais.
- **`get_connection_state`** passa a exigir `token: &SecretString` (era global no v2; Go exige token da instância em `/instance/status`).
- Sobrescrever **todos** os acessores da fachada: `fn reactions(&self) -> Option<&dyn Reactions> { Some(self) }`, idem `presence`/`read_receipts`/`media_downloader`/`profiles`/`advanced_settings`.

**Testes (wiremock — reescrever os v2 para Go):** `/instance/create` lê `token`; `/instance/connect` recebe `subscribe`+`webhookUrl`+`immediate`; `/instance/status` top-level; `/instance/all` `{data}`; `/send/text`; `/send/media` (`type`/`url`); `/message/markread`; `/message/react`; `/message/presence`; `/user/avatar`; `/message/downloadmedia` (`base64`); `DELETE /instance/logout`; `map_state`; truncamento. **Apagar** mocks de `/webhook/set`, `/message/sendText/{name}`, `/instance/connectionState`, `/instance/fetchInstances`, `/instance/pairingCode`.

### Observabilidade & Auditoria (E2)
- `#[tracing::instrument(err, skip(self, token, custom_token, text, caption, message))]` em cada método; fields `provider="evolution"`, `instance_name`. **Sem evento de auditoria** (camada de infra). **Nunca** logar `apikey`/`token`/`text`/`caption`/conteúdo de `message` (PII + segredo). Body de erro já truncado a 200 no `ok_or_api`.

## E3. `data_whatsapp` — registry + `dyn` + novos RPCs

**Troca de AppState (concreto → registry):**
```rust
// ANTES (real, hoje): struct AppState { provider: EvolutionProvider, redis_conn: … }
// DEPOIS:
#[derive(Clone)]
struct AppState { registry: ProviderRegistry, redis_conn: redis::aio::ConnectionManager }
```
`main()`: remover `EvolutionProvider::new(...)` direto do state; construir o `ProviderRegistry::builder().register(Arc::new(EvolutionProvider::new(api_url, global_key))).build()` (composition root) e passar para `AppState`.

**Padrão de resolução por handler** (substitui `state.provider.<x>`):
```rust
let inst = chamar_data_postgres("GetWhatsappInstance", &env.tenant_id, json!({"id": db_id}), &env).await?;
let provider_name = inst.get("provider").and_then(|v| v.as_str()).unwrap_or("evolution");
let p = state.registry.resolve(provider_name).map_err(|e| AppError::Internal(e.to_string()))?;
let token = SecretString::from(inst.get("api_key").and_then(|v| v.as_str()).unwrap_or_default().to_string());
```

**`CreateWhatsappInstance` (fluxo novo com `connect_instance(&WebhookConfig)`):**
1. `provider_name` vem do payload (default `"evolution"`); `p = registry.resolve(provider_name)?`.
2. `p.create_instance(name, None)` → `CreateInstanceResult { provider_instance_id, instance_token }`.
3. Persistir via `chamar_data_postgres("CreateWhatsappInstanceRecord", …, {name, api_key, provider})` → `db_id`.
4. **`p.connect_instance(name, &token, &WebhookConfig { url, subscribe })`** onde
   `url = "http://webhook_ingress:9200/webhook/{provider}/{tenant}/{db_id}"`,
   `subscribe = ["MESSAGE","CONNECTION","PRESENCE","QRCODE"]`.
   → **substitui** a chamada atual de `configure_webhook` (que será removida).
5. (Opcional) `if let Some(adv) = p.advanced_settings() { adv.set_advanced_settings(provider_instance_id, &token, AdvancedSettings::default()).await?; }` (`always_online:true`, `read_messages:false`).
6. `AtualizarInstanciaProviderId`.
7. **Rollback** se 4/5 falhar: `p.delete_instance(name)` + `AdminDeletarInstancia(db_id)`.
8. Auditoria `whatsapp.instance.create`.

**`GetWhatsappInstanceStatus`:** `p.get_connection_state(name, &token)` (agora com token); se Disconnected/Unknown → `p.get_qr_code(name, &token)`; `AtualizarEstadoInstancia`.

**`DeleteWhatsappInstance`:** resolve por `provider` da instância → `p.delete_instance(name)` → `AdminDeletarInstancia` → auditoria `whatsapp.instance.delete`.

**`ReconnectWhatsappInstance`:** `p.reconnect_instance(name, &token)` (era `connect_instance` no v2).

**Envio (núcleo):** `SendWhatsappMessage` → `p.send_text(...)`; `SendWhatsappMedia` → `p.send_media(...)`.

**Novos RPCs (capacidades opcionais via acessor + `Unsupported`):**
| RPC | Acessor | Chamada |
| --- | --- | --- |
| `MarkWhatsappMessageRead` | `p.read_receipts().ok_or(Unsupported("read_receipts"))?` | `.mark_read(name,&token,chat,&ids)` |
| `SendWhatsappReaction` | `p.reactions().ok_or(Unsupported("reaction"))?` | `.send_reaction(name,&token,chat,msg_id,emoji,from_me)` |
| `SetWhatsappPresence` | `p.presence().ok_or(Unsupported("presence"))?` | `.set_presence(name,&token,chat,state,is_audio)` |
| `GetWhatsappProfilePicture` | `p.profiles().ok_or(Unsupported("profile"))?` | `.get_profile_picture(name,&token,number)` |
| `DownloadWhatsappMedia` (usado pelo `worker`) | `p.media_downloader().ok_or(Unsupported("download"))?` | `.download_media(name,&token,&message)` |

Registrar cada novo RPC no `Server::from_env("DATA_WHATSAPP").route(...)` (clonar o `state` por rota, como já é feito).

**Auditoria:** manter `whatsapp.instance.create/delete` e `whatsapp.admin.bulk_disconnect`. Recursos de mensagem (send/react/markread/presence/download) **sem auditoria** (alto volume; intencional).

**Testes (atualizar v2→Go + mock SOLID):**
- **Atualizar `setup_test_env`/mocks wiremock:** trocar `/instance/create` (lê `token`), `/instance/connect` (POST com `subscribe`/`webhookUrl`), `/instance/status`, `/send/text`, `/send/media`, `DELETE /instance/logout`. **Remover** os mocks `/webhook/set/instancia-test`, `/message/sendText/instancia-test`, `/message/sendMedia/instancia-test`, `/instance/connectionState/instancia-test`, `POST /instance/logout/inst-1`.
- **Mock do `dyn` com `mockall`** (prova DIP): definir `MockMessagingProvider` (via `mockall::mock!` para a fachada + núcleo), registrar no `ProviderRegistry`, e provar que `handler_send_whatsapp_message` chama `send_text` **sem** referenciar `EvolutionProvider`. Test de **capacidade ausente**: mock que implementa só núcleo → `SendWhatsappReaction` retorna erro mapeado de `Unsupported`.

### Observabilidade & Auditoria (E3)
- `#[instrument(skip_all, fields(rpc, tenant_id = %env.tenant_id, provider = tracing::field::Empty))]`; gravar `provider` após resolução. `instance_token`/`api_key` em `SecretString`, nunca em log.
- **Auditoria (eixo B):** `TenantEnvelope::novo(tenant_uuid, "whatsapp.instance.create", {user_id, instance_name, provider})` (sem token) e `"whatsapp.instance.delete"`; `whatsapp.admin.bulk_disconnect` no handler admin com `{user_id, scope, count}` (sem token), `tenant_id` NULL/nil quando escopo global. Publicado via `publicar_evento_seguranca` → `security:stream`.

## E4. `webhook_ingress` — `WebhookNormalizer` registry + eventos Go

**Trabalho:**
1. Definir o trait `WebhookNormalizer` (`provider()` + `normalize()`).
2. `AppState { redis, normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>> }`; registrar no `main` (`EvolutionNormalizer`).
3. **Handler:** `state.normalizers.get(provider.as_str())` → `.normalize(event_type, &raw, tenant, instance)`; provedor desconhecido = `202 ACCEPTED` + `warn` (substitui o `match params.provider`).
4. **`EvolutionNormalizer::normalize`:** `canonical_event(raw)` espelhando `EvolutionEventName.from_raw`:

   | Raw (qualquer destes) | Canônico | Tópico universal |
   | --- | --- | --- |
   | `Message`/`MESSAGE`/`messages.upsert`/`MESSAGES_UPSERT` | `Message` | `whatsapp.message.received` |
   | `Connection`/`CONNECTION`/`connection.update`/`Connected`/`Disconnected`/`LoggedOut` | `Connection` | `whatsapp.connection.updated` |
   | `MESSAGE_UPDATE`/`messages.update` | `MessageUpdate` | `whatsapp.message.status` |
   | `Presence`/`PRESENCE`/`presence.update` | `Presence` | `whatsapp.presence.updated` |
   | `Contacts`/`CONTACTS`/`contacts.update` | `Contacts` | `whatsapp.contact.updated` (2ª iteração) |
   | `QRCode`/`QRCODE`/`qrcode.updated` | `Qrcode` | só `202` (QR é fluxo de UI via `GetStatus`) |
   | `SendMessage`/`SEND_MESSAGE` | `SendMessage` | `202` (eco do próprio envio; ignorar) |

5. **Normalização por evento:** `Connection` mapeia `data.state`/`data.status` (open/close/connecting/loggedOut → connected/disconnected/connecting/disconnected). `Message` carrega `raw_event` (dedup por `key.id` é do **worker**, não do ingress).

**Testes:** `WebhookNormalizer` registry (provedor desconhecido = 202); `canonical_event` para UPPERCASE/PascalCase/aliases v2 (`Message`, `MESSAGE`, `messages.upsert` → mesmo tópico); normalização de `Message`/`Connection`/`Presence`; **`body` não vaza em logs**. Manter os 5 testes axum atuais, atualizando os payloads para os nomes Go.

### Observabilidade & Auditoria (E4)
- `#[instrument(skip(state, body), fields(provider = %params.provider, tenant_id = %params.tenant_id, instance_id = params.instance_id, event_type = tracing::field::Empty))]`; gravar `event_type` canônico. **Sem evento de auditoria** (volume alto). **`body` nunca logado** (PII: telefone/nome/conteúdo).

## E5. Banco e repositório — validação (sem mudança)
`0008_whatsapp_sync.sql` e `infrastructure_postgres/integracoes/whatsapp.rs` já atendem (coluna `provider` neutra). **Não reescrever.** Se um novo RPC exigir coluna não persistida, estender o repositório incrementalmente e **regerar cache SQLx offline** (MEMORY `testes-db-tunel-e-reset`). **Sem evento de auditoria** (validação).

## E6. `control_plane` — endpoint admin (sem regressão)
Manter `POST /api/v2/admin/whatsapp/disconnect-all` → `AdminBulkDisconnectInstances`; auditoria enriquecida (`ip_address`/`user_agent`/`user_id`). Resposta **sem tokens**. Grep limpo de `evolution_sync_*`/endpoints v2.

### Observabilidade & Auditoria (E6)
Auditoria `whatsapp.admin.bulk_disconnect` enriquecida no `control_plane` (já existe); `context` sem token; `tenant_id` NULL quando global.

---

## Arquitetura (visão consolidada)

```
control_plane / worker ──RPC──▶ data_whatsapp ──registry.resolve(provider)──▶ dyn MessagingProvider
                                     │                          └─(EvolutionProvider)──HTTP──▶ Evolution Go
                                     └──RPC──▶ data_postgres (whatsapp_* + audit_log)
       security:stream ─────────────────────▶ data_postgres ─▶ audit_log

Evolution Go ──webhook POST──▶ webhook_ingress ──normalizers.get(provider).normalize──▶ events:stream ──▶ worker

Plugar provedor novo: crate infrastructure_<x> (só traits suportados) +
  registry.register(...) no data_whatsapp + XNormalizer no webhook_ingress. Zero alteração nos consumidores.
```

---

# Fase V — Validation

### V1. Compilação
- `cargo build -p infrastructure_messaging -p infrastructure_evolution -p webhook_ingress -p data_whatsapp` (via build do script). Regenerar cache SQLx offline se o repositório for tocado.

### V2. Testes — **scripts canônicos** (MEMORY `test-scripts`; NUNCA `cargo test` direto)
- **Rust:** `.\infra\test-local.ps1`
  - `infrastructure_messaging`: round-trip serde; `Display` incl. `Unsupported`; **`ProviderRegistry`** (resolve registrado / `Config` para desconhecido); **object-safety** (compila `Arc<dyn MessagingProvider>`); **descoberta de capacidade** (mock só-núcleo → acessores `None`).
  - `infrastructure_evolution`: wiremock dos endpoints Go (lista de E2); `map_state`; truncamento. Mocks v2 removidos.
  - `data_whatsapp`: handlers com `data_postgres` mockado + **registry com provider fake (`mockall`)** provando dependência só do `dyn`; fluxo create com `connect_instance`+webhook; **capacidade ausente → `Unsupported`**.
  - `webhook_ingress`: registry (provedor desconhecido = 202); `canonical_event` (UPPERCASE/PascalCase/aliases); normalização de `Message`/`Connection`/`Presence`; `body` não vaza.
- **Flutter** (se algum client for tocado): `.\infra\test-flutter.ps1`.

### V3. Validação manual (stack Docker, Evolution Go rodando)
- Criar instância via `data_whatsapp`; confirmar `POST /instance/connect` com `subscribe`/`webhookUrl`/`immediate`; escanear QR (`/instance/qr`); enviar texto (`/send/text`); ver `whatsapp.message.received`. Confirmar `Connection` → `whatsapp.connection.updated`. Testar `markread`/`react`/`presence`/`avatar`/`reconnect`. **Confirmar o campo `base64` do `/message/downloadmedia`** (docstring do adapter diz `base64`; validar no servidor real). Confirmar que **Global Key dá 401** no connect (gotcha #1) e que o token da instância funciona.

### V4. Observabilidade/auditoria
- Logs **sem** `apikey`/`instance_token`/body de webhook/telefone/conteúdo. `audit_log` com create/delete/bulk_disconnect, `context` sem segredos, `tenant_id` NULL quando global.

---

# Fase C — Confirmation

### C1. Critérios de pronto
- Build/testes (V1–V2) verdes via scripts canônicos; integração manual (V3) e auditoria (V4) confirmadas contra o Evolution Go real.
- **Grep limpo** de endpoints v2: `/message/sendText`, `/message/sendMedia`, `/webhook/set`, `/instance/connectionState`, `/instance/fetchInstances`, `/instance/pairingCode`, `configure_webhook`, `pair_by_phone`.
- Nenhum consumidor referencia `EvolutionProvider` concreto — `grep EvolutionProvider` só em `infrastructure_evolution` e na composição (`data_whatsapp/main.rs`).

### C2. Gate de final-review
- `prevc-final-review` (subagente Opus): compara implementado × este plano, corrige desvios, arquiva e commita. **Sem auto-referência** nos commits (MEMORY `git-no-self-reference`); **gitflow** (MEMORY `use-gitflow`).

### C3. Documentação
- Atualizar `doc_dev/libs/` (Evolution Go, axum 0.8) se o contrato real divergir do doc local.

---

# Correções aplicadas (vs. v3)

1. **ISP** — trait único de ~19 métodos → **traits de capacidade** (`InstanceManager`+`MessageSender` núcleo; `PresenceControl`/`ReadReceipts`/`Reactions`/`MediaDownloader`/`ProfileQuery`/`AdvancedSettingsControl` opcionais) + fachada com descoberta `Option<&dyn …>`. Provedor implementa só o que suporta. **Fonte:** requisito do usuário de plugabilidade.
2. **DIP** — `data_whatsapp` deixa de segurar `EvolutionProvider` concreto → **`ProviderRegistry`** resolve `dyn MessagingProvider` pelo campo `provider` da instância; concreto só na composition root. **Fonte:** requisito de plugar/desplugar + modelo `WhatsappStore` (port/adapter).
3. **OCP** — `match params.provider` do `webhook_ingress` → **registry de `WebhookNormalizer`**. **Fonte:** requisito de plugabilidade.
4. **LSP** — capacidade ausente retorna `MessagingProviderError::Unsupported(&'static str)` (sem no-op/panic). **Fonte:** requisito SOLID.
5. **Realinhamento v2 → Go** — REST e eventos realinhados ao servidor que roda: `create` lê `token`; connect com `subscribe`+`immediate`+token da instância; `/instance/status`; `/instance/all`; `/send/text`/`/send/media` (`type`/`url`); `DELETE /instance/logout`; eventos UPPERCASE/PascalCase. Webhook embutido no connect (sem `/webhook/set`); `pair_by_phone`/`configure_webhook` removidos. **Fonte:** `evolution_go_adapter.py` (battle-tested; código vence o comentário stale sobre `subscribe`).
6. **Superfície completa** — `markread`, `react`, `presence` (composing/recording/paused + `isAudio`), `download_media` (`base64`), `advanced-settings` (`alwaysOnline:true`/`readMessages:false`), `reconnect`, `avatar`. **Fonte:** `evolution_go_adapter.py` + `info_aux`.

---

**Notas finais para o implementador:**
- A contradição interna do adapter (comentário linhas 21-23 diz "não usar `subscribe`", mas `connect_instance` linha 503-512 **usa** `subscribe`) foi resolvida a favor do **código executado**: o body do connect leva `{instanceName, webhookUrl, subscribe:[UPPERCASE], immediate:true}`. Validar empiricamente em V3.
- O `get_connection_state` muda de assinatura (passa a exigir `token: &SecretString`) — isso quebra o call-site atual em `handler_get_whatsapp_instance_status`, que já tem o `api_key` em mãos; ajuste trivial.
- Manter os dois `axum` separados; não tocar `runtime_api`.
