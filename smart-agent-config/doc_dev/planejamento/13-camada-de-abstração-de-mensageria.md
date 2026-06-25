# Plano Consolidado: Módulo Rust de Mensageria WhatsApp (Evolution Go)

> Documento único consolidado. **Substituiu** os dois planos-base v2 que existiam antes
> (`-2.md` e a versão original deste arquivo), que assumiam *greenfield* + **Evolution API v2
> (Baileys)**. A realidade é outra: o scaffolding já existe no repositório **e** o servidor que
> está rodando é o **Evolution Go (whatsmeow)**, cujo contrato REST e cujos eventos divergem do
> v2. Este documento é a **única fonte de verdade técnica** e realinha a camada Rust ao Evolution
> Go, com a **superfície completa** de recursos, **estruturada para conformidade SOLID** —
> tudo atrás de interface, de modo a **plugar/desplugar provedores facilmente**.
>
> Estilo de referência: o `evolution_sync` do `old/` (adapter `evolution_go_adapter.py`).
> Organização em fases **PREVC** (Planning, Review, Execution, Validation, Confirmation).

---

## Objetivo

Estruturar o **módulo Rust único responsável por toda a comunicação com o Evolution Go**:
criação/gestão de instâncias, conexão/QR, envio de mensagens e mídia, recursos de sessão
(presença, leitura, reações, foto de perfil, download de mídia) e ingestão normalizada de
webhooks. As regras de negócio dos tenants nunca falam com o Evolution diretamente — só com
este módulo, através de **contratos em Rust (traits)** e eventos universais no barramento Redis
Streams.

### Premissas
1. **Tudo atrás de interface (DIP).** Nenhum consumidor depende de tipo concreto de provedor:
   sempre `dyn` trait. O provedor concreto (`EvolutionProvider`) é resolvido em runtime pelo
   campo `provider` da instância — **plugar/desplugar provedor não toca o consumidor**.
2. **Interfaces segregadas (ISP).** O contrato é quebrado em **capacidades** (gestão, envio,
   presença, reações, leitura, download, perfil, settings). Um provedor implementa **só o que
   suporta**; capacidades não suportadas são descobertas em runtime, não forçadas no trait.
3. **Aberto para extensão, fechado para modificação (OCP).** Adicionar um provedor novo (Z-API,
   Baileys, …) = nova crate `infrastructure_<provedor>` + registro num **registry**; nenhum
   `match` espalhado precisa ser editado (nem no `data_whatsapp`, nem no `webhook_ingress`).
4. **Normalização no ingress.** O `webhook_ingress` traduz webhooks proprietários do Go em
   eventos universais; o resto do sistema só consome eventos normalizados.
5. **Banco genérico, multi-provedor.** Tabelas `whatsapp_*` com coluna `provider` sem default
   acoplado. **Já implementado** (ver Reconciliação).
6. **Segredos sempre `SecretString`.** `global_api_key`/`instance_token` jamais em logs ou
   respostas; `api_key` encriptado em repouso.

---

## ⚠️ Reconciliação com o repositório real (pré-condição da execução)

Dois pontos centrais: (a) **boa parte do plano-base v2 já foi implementada**; (b) a divergência
restante é **v2 → Go** + **adequação a SOLID** (o código atual usa um trait único "gordo" e um
provedor concreto fixo, que não atendem ao requisito de plugabilidade).

### Já implementado e correto (não mexer, apenas validar)
| Componente | Caminho | Situação |
| --- | --- | --- |
| Migração genérica | `infrastructure_postgres/migrations/0008_whatsapp_sync.sql` | ✅ `whatsapp_instance/contact/whitelist`, RLS+FORCE, `provider` sem default. |
| Repositório WhatsApp | `infrastructure_postgres/src/integracoes/whatsapp.rs` + `whitelist.rs` | ✅ Neutro de provedor; serve ao Go sem alteração. |
| Port/Adapter no data_postgres | `data_postgres/src/ports/whatsapp.rs`, `src/adapters/whatsapp.rs` | ✅ `WhatsappStore` (port/adapter + `mockall`), RLS + admin BYPASSRLS. **Modelo SOLID exemplar a espelhar.** |

### A construir/ajustar (realinhamento Go + segregação SOLID)
| Componente | Caminho | Estado hoje | Trabalho |
| --- | --- | --- | --- |
| Crate de contrato | `crates/infrastructure_messaging` | trait **único** de 12 métodos (v2) | **E1**: segregar em traits de capacidade + fachada `MessagingProvider`; ampliar p/ superfície Go; adicionar `ProviderRegistry`. |
| Crate Evolution | `crates/infrastructure_evolution` | fala endpoints v2 | **E2**: realinhar ao contrato Go implementando os traits segregados. |
| App orquestrador | `apps/data_whatsapp` | `AppState` segura `EvolutionProvider` **concreto**; provedor vem fixo de env | **E3**: trocar por `ProviderRegistry` resolvendo `dyn` pelo `provider` da instância; novos RPCs. |
| App ingress | `apps/webhook_ingress` | `match provider` + só eventos v2 lowercase | **E4**: `WebhookNormalizer` registry (OCP) + canonização de eventos Go. |

### Divergência central: contrato v2 (no código) × Evolution Go (rodando)
| Operação | Código Rust atual (v2) | Evolution Go (alvo real) | Auth |
| --- | --- | --- | --- |
| Criar instância | `POST /instance/create` (`integration:WHATSAPP-BAILEYS`, `qrcode:true`) → lê `hash` | `POST /instance/create` body `{name, token?}` → lê `token` | global key |
| Conectar + webhook | `GET /instance/connect/{name}` **e** `PUT /webhook/set/{name}` (2 chamadas) | `POST /instance/connect` body `{instanceName, webhookUrl, subscribe[], immediate:true}` (**1 chamada**, webhook embutido) | **token da instância** |
| QR Code | `GET /instance/connect/{name}` | `GET /instance/qr` | token da instância |
| Estado | `GET /instance/connectionState/{name}` → `instance.state` | `GET /instance/status` → `{state}` (v2 retorna **503** no Go) | token da instância |
| Listar | `GET /instance/fetchInstances` | `GET /instance/all` → `{data:[...]}` | global key |
| Logout/desconectar | `POST /instance/logout/{name}` | `DELETE /instance/logout` (**sem nome no path**) | token da instância |
| Deletar | `DELETE /instance/delete/{name}` | `DELETE /instance/delete/{name}` (igual) | global key |
| Reconectar | (n/d) | `POST /instance/reconnect` | token da instância |
| Enviar texto | `POST /message/sendText/{name}` (`{number,text}`) | `POST /send/text` (`{number,text,quoted?}`) | token da instância |
| Enviar mídia | `POST /message/sendMedia/{name}` (`media`/`mediatype`) | `POST /send/media` (`type`/`url`/`caption`/`filename`) | token da instância |
| Advanced settings | (n/d) | `PUT /instance/{id}/advanced-settings` (`alwaysOnline`, `readMessages`, …) | token da instância |
| Eventos do webhook | `messages.upsert` / `connection.update` (lowercase) | `Message` / `Connection` / `Presence` / `QRCode` / `Contacts` (UPPERCASE/PascalCase + aliases) | — |

### Recursos extras do Go (superfície completa — escopo aprovado)
`POST /send/media` com `type:audio` (PTT) · `POST /message/react` · `POST /message/markread` ·
`POST /message/presence` (`composing`/`recording`, `isAudio`) · `POST /user/avatar` (foto de
perfil) · `POST /message/downloadmedia` (descriptografia/fallback de mídia grande sem base64
inline).

> ⚠️ **Armadilhas conhecidas do Go (do `evolution_go_adapter.py`):**
> 1. `POST /instance/connect` exige o **token da instância** no header `apikey`; a Global Key
>    retorna **401 "not authorized"** aqui.
> 2. O campo de eventos no connect é **`subscribe`** (array UPPERCASE: `MESSAGE`, `CONNECTION`,
>    `PRESENCE`, `QRCODE`). Nome inválido **zera** a assinatura → para toda entrega de webhook.
> 3. `readMessages` em advanced-settings deve ficar **`false`** — recibo de leitura é explícito.
> 4. `alwaysOnline:true` é o mecanismo documentado para manter a sessão whatsmeow viva.

Apps existentes: `control_plane`, `data_postgres`, `data_redis`, `data_storage`, `data_whatsapp`,
`webhook_ingress`, `messaging_gateway`, `runtime_api`, `worker`.
Crates existentes: `application`, `contracts`, `error_core`, `infrastructure_messaging`,
`infrastructure_evolution`, `infrastructure_postgres`, `infrastructure_redis`,
`infrastructure_storage`, `observability`, `test_support`, `transport`.

---

## Conformidade SOLID e plugabilidade de provedores (núcleo do design)

Esta seção é a espinha dorsal do requisito "tudo via interface, plugar/desplugar fácil".

### S — Single Responsibility
- `infrastructure_messaging`: **só contratos** (traits + tipos neutros + erro + registry). Pura.
- `infrastructure_evolution`: **só** o HTTP do Evolution Go atrás dos traits.
- `data_whatsapp`: **só** orquestração (resolve provedor, chama trait, persiste via RPC, audita).
- `webhook_ingress`: **só** normalização de webhook → evento universal.

### I — Interface Segregation (o ponto-chave do seu requisito)
Em vez de **um** trait de ~19 métodos (que obrigaria todo provedor novo a implementar
presença/reação/download mesmo sem suportar), o contrato é quebrado em **capacidades**:

```rust
// ---- Núcleo OBRIGATÓRIO: todo provedor precisa ter ----
#[async_trait]
pub trait InstanceManager: Send + Sync {
    fn provider_name(&self) -> &'static str;
    async fn create_instance(&self, name: &str, custom_token: Option<&SecretString>) -> Result<CreateInstanceResult, MessagingProviderError>;
    async fn delete_instance(&self, name: &str) -> Result<(), MessagingProviderError>;
    async fn connect_instance(&self, name: &str, token: &SecretString, webhook: &WebhookConfig) -> Result<(), MessagingProviderError>;
    async fn disconnect_instance(&self, name: &str, token: &SecretString) -> Result<(), MessagingProviderError>;
    async fn reconnect_instance(&self, name: &str, token: &SecretString) -> Result<(), MessagingProviderError>;
    async fn get_qr_code(&self, name: &str, token: &SecretString) -> Result<String, MessagingProviderError>;
    async fn get_connection_state(&self, name: &str, token: &SecretString) -> Result<ConnectionState, MessagingProviderError>;
    async fn list_all_instances(&self) -> Result<Vec<String>, MessagingProviderError>;
}

#[async_trait]
pub trait MessageSender: Send + Sync {
    async fn send_text(&self, name: &str, token: &SecretString, to: &str, text: &str) -> Result<SendMessageResult, MessagingProviderError>;
    async fn send_media(&self, name: &str, token: &SecretString, to: &str, media: MediaType, url: &str, caption: Option<&str>) -> Result<SendMessageResult, MessagingProviderError>;
}

// ---- Capacidades OPCIONAIS: implementa só quem suporta ----
#[async_trait] pub trait PresenceControl: Send + Sync { async fn set_presence(&self, name:&str, token:&SecretString, chat:&str, state:PresenceState, is_audio:bool) -> Result<(), MessagingProviderError>; }
#[async_trait] pub trait ReadReceipts:   Send + Sync { async fn mark_read(&self, name:&str, token:&SecretString, chat:&str, message_ids:&[String]) -> Result<(), MessagingProviderError>; }
#[async_trait] pub trait Reactions:      Send + Sync { async fn send_reaction(&self, name:&str, token:&SecretString, chat:&str, message_id:&str, emoji:&str, from_me:bool) -> Result<SendMessageResult, MessagingProviderError>; }
#[async_trait] pub trait MediaDownloader:Send + Sync { async fn download_media(&self, name:&str, token:&SecretString, message:&serde_json::Value) -> Result<MediaDownloadResult, MessagingProviderError>; }
#[async_trait] pub trait ProfileQuery:   Send + Sync { async fn get_profile_picture(&self, name:&str, token:&SecretString, number:&str) -> Result<Option<String>, MessagingProviderError>; }
#[async_trait] pub trait AdvancedSettingsControl: Send + Sync { async fn set_advanced_settings(&self, instance_id:&str, token:&SecretString, settings:AdvancedSettings) -> Result<(), MessagingProviderError>; }

// ---- Fachada: núcleo + DESCOBERTA de capacidades (default = None) ----
pub trait MessagingProvider: InstanceManager + MessageSender {
    fn presence(&self) -> Option<&dyn PresenceControl> { None }
    fn read_receipts(&self) -> Option<&dyn ReadReceipts> { None }
    fn reactions(&self) -> Option<&dyn Reactions> { None }
    fn media_downloader(&self) -> Option<&dyn MediaDownloader> { None }
    fn profiles(&self) -> Option<&dyn ProfileQuery> { None }
    fn advanced_settings(&self) -> Option<&dyn AdvancedSettingsControl> { None }
}
```

- A fachada `MessagingProvider` é **object-safe** (acessores não-genéricos, `&self`, retornam
  trait objects) ⇒ `Arc<dyn MessagingProvider>` funciona.
- Um provedor mínimo implementa **2 traits** (`InstanceManager` + `MessageSender`) e herda os
  `None`. O `EvolutionProvider` implementa todas e sobrescreve os acessores p/ `Some(self)`.
- O consumidor pede a capacidade e trata ausência explicitamente (LSP — sem método "no-op"):
  ```rust
  provider.reactions()
      .ok_or(MessagingProviderError::Unsupported("reaction"))?
      .send_reaction(...).await?;
  ```

### D — Dependency Inversion (resolve `dyn` por instância)
O `data_whatsapp` **não** segura `EvolutionProvider`. Segura um **registry** de implementações
e resolve em runtime pelo `provider` da instância:

```rust
// infrastructure_messaging (puro: só std + a fachada)
#[derive(Clone, Default)]
pub struct ProviderRegistry { map: Arc<HashMap<String, Arc<dyn MessagingProvider>>> }

impl ProviderRegistry {
    pub fn builder() -> ProviderRegistryBuilder { ProviderRegistryBuilder::default() }
    pub fn resolve(&self, provider: &str) -> Result<Arc<dyn MessagingProvider>, MessagingProviderError> {
        self.map.get(provider).cloned()
            .ok_or_else(|| MessagingProviderError::Config(format!("provedor não registrado: {provider}")))
    }
}
```

Composição (raiz = `data_whatsapp/main.rs`) — **único lugar** que conhece o concreto:
```rust
let registry = ProviderRegistry::builder()
    .register(Arc::new(EvolutionProvider::new(api_url, global_key)))  // "evolution"
    // .register(Arc::new(ZApiProvider::new(...)))   // futuro: 1 linha, sem tocar handlers
    .build();
let state = AppState { registry, redis_conn };
```

### O — Open/Closed (registry de normalizadores no ingress)
O `webhook_ingress` troca o `match params.provider` por um registry de `WebhookNormalizer`:
```rust
#[async_trait] // ou sync — normalização é pura
pub trait WebhookNormalizer: Send + Sync {
    fn provider(&self) -> &'static str;
    fn normalize(&self, event:&str, raw:&serde_json::Value, tenant:Uuid, instance:i32)
        -> Option<(&'static str, contracts::TenantEnvelope<serde_json::Value>)>;
}
```
Adicionar provedor = novo `XNormalizer` + `registry.register(...)`; o handler não muda (OCP).

> **Resultado**: plugar um provedor = (1) nova crate implementando os traits de capacidade que
> ele suporta; (2) uma linha no builder do `ProviderRegistry`; (3) um `WebhookNormalizer`. Zero
> alteração em consumidores, banco ou contratos existentes.

---

## Decisões de Design

### D1. Contratos segregados em `infrastructure_messaging`
Traits de capacidade + fachada `MessagingProvider` + `ProviderRegistry` + tipos neutros
(`ConnectionState`, `MediaType`, `PresenceState`, `WebhookConfig`, `AdvancedSettings`,
`CreateInstanceResult`, `SendMessageResult`, `MediaDownloadResult`) + `MessagingProviderError`
(novo variante `Unsupported(&'static str)`). Crate pura: sem runtime, sem I/O, sem logs.

### D2. `EvolutionProvider` implementa as capacidades do Go
Struct com `global_api_key` (criar/deletar/listar) e `instance_token` por chamada. Helper
interno `send_request(method, path, apikey, body)` espelha o `_send_request` do adapter Go
(header `apikey`, `Content-Type`, `ok_or_api`, body truncado a 200 chars). Implementa
`InstanceManager + MessageSender` + todas as capacidades opcionais, sobrescrevendo os acessores
da fachada para `Some(self)`.

### D3. `data_whatsapp` resolve provedor por instância (DIP)
`AppState { registry: ProviderRegistry, redis_conn }`. Cada handler: lê o `provider` da instância
no banco → `registry.resolve(provider)?` → chama via `dyn`. Capacidades opcionais via acessor +
`Unsupported`. **Nenhum tipo concreto de provedor no consumidor.**

### D4. Webhook: detecção por path (axum 0.8) + registry de normalizadores (OCP) + canonização
URL no `POST /instance/connect`: `http://webhook_ingress:9200/webhook/{provider}/{tenant_id}/{instance_id}`.
O ingress resolve o `WebhookNormalizer` pelo `provider` do path, **canoniza o nome do evento**
(UPPERCASE/PascalCase/aliases v2 → enum canônico, espelhando `EvolutionEventName.from_raw`) e
publica em `events:stream`.

### D5. Desconexão em massa pelo admin
RPC `AdminBulkDisconnectInstances` (`tenant_id: Option<Uuid>`; `None` ⇒ todos os tenants via
`AdminListAllConnectedInstances` BYPASSRLS, escopo `operacional:admin`). Para cada instância,
resolve o provedor pelo registry e chama `disconnect_instance`; atualiza `connection_state`.

---

# Fase P — Planning (output)

**Status: concluída.**

- **Escopo**: segregar o contrato (SOLID) + realinhar 4 componentes Rust ao Evolution Go +
  ampliar superfície. Nenhuma criação de app; **uma** estrutura nova (`ProviderRegistry`,
  `WebhookNormalizer`) dentro de crates existentes; nenhuma mudança de schema.
- **Contrato central**: fachada `MessagingProvider` (núcleo `InstanceManager`+`MessageSender`) +
  capacidades opcionais descobertas em runtime.
- **Eventos normalizados** em `events:stream`: `whatsapp.message.received` (Message),
  `whatsapp.connection.updated` (Connection), `whatsapp.message.status` (MessageUpdate),
  `whatsapp.presence.updated` (Presence), `whatsapp.contact.updated` (Contacts, opcional).
- **Auditoria** em `security:stream` → `audit_log`: `whatsapp.instance.create/delete`,
  `whatsapp.admin.bulk_disconnect`.
- **Mapa de risco**: a segregação do trait **quebra os call-sites atuais** de `data_whatsapp`
  (refactor maior que "só realinhar"); contrato Go indocumentado em pontos (mitigado pelo
  adapter do old); `subscribe` inválido zera webhooks; dois `axum` coexistem — não unificar.

---

# Fase R — Review (arquitetura e contratos)

### R1. Compatibilidade de versões
- `runtime_api` em **axum 0.7.5**; `webhook_ingress` em **axum 0.8** local (já assim). NÃO
  adicionar `axum` ao workspace. `reqwest 0.12` (feature `json`) em `infrastructure_evolution`.
- Reuso: `async-trait`, `serde`, `serde_json`, `secrecy`, `thiserror`, `uuid`, `tracing`, `redis`,
  `contracts`, `transport`, `error_core`, `observability`.

### R2. Sanidade de segurança
- `global_api_key`/`instance_token` sempre `SecretString`; sempre em `skip(...)` do `instrument`.
- `api_key` no banco encriptado. RLS+FORCE em todas as `whatsapp_*`; bypass cross-tenant só por
  `admin_pool`/transação admin sob `operacional:admin`. Body de erro truncado a 200 chars.

### R3. Decisões de contrato (SOLID + barramento)
- **Object-safety** confirmada para a fachada e o `ProviderRegistry` (`Arc<dyn MessagingProvider>`).
- **Capacidade opcional** retorna `Unsupported` (sem `panic`, sem no-op) — respeita LSP.
- Reaproveitar `contracts::TenantEnvelope<T>` + `transport::bus::publicar_evento(_seguranca)`.

**Gate R**: aprovado se R1/R2/R3 confirmados. Saída → Execution.

---

# Fase E — Execution (detalhe técnico)

## E1. `infrastructure_messaging` — segregar + ampliar o contrato
- Substituir o trait único por: `InstanceManager`, `MessageSender` (núcleo) + `PresenceControl`,
  `ReadReceipts`, `Reactions`, `MediaDownloader`, `ProfileQuery`, `AdvancedSettingsControl`
  (opcionais) + fachada `MessagingProvider: InstanceManager + MessageSender` com acessores
  `Option<&dyn …>` (default `None`).
- Tipos novos: `PresenceState`, `WebhookConfig { url: String, subscribe: Vec<String> }`,
  `AdvancedSettings { always_online, read_messages(=false), reject_call, msg_reject_call,
  ignore_groups, ignore_status }` (com `Default`), `MediaDownloadResult { base64, mime_type }`.
- `MessagingProviderError`: adicionar `#[error("Operação não suportada pelo provedor: {0}")]
  Unsupported(&'static str)`.
- `ProviderRegistry` + `ProviderRegistryBuilder` (só `std`/`Arc`/`HashMap` — mantém crate pura).
- **`connect_instance` recebe `&WebhookConfig`** (webhook embutido na conexão — contrato Go).
  Remover `configure_webhook` do contrato (era artefato v2; no Go vive dentro do connect).

**Obs/Auditoria E1**: crate pura — sem logs/auditoria. `SecretString` nas assinaturas; `Debug`
redige segredo.

## E2. `infrastructure_evolution` — implementar capacidades contra o Go
`EvolutionProvider` implementa os traits de E1 com a tabela canônica de endpoints Go:

| Trait::método | HTTP Go | apikey | Body / parse |
| --- | --- | --- | --- |
| `InstanceManager::create_instance` | `POST /instance/create` | global | `{name, token?}` → `token` |
| `InstanceManager::delete_instance` | `DELETE /instance/delete/{name}` | global | — |
| `InstanceManager::connect_instance` | `POST /instance/connect` | **instância** | `{instanceName, webhookUrl, subscribe:[…], immediate:true}` |
| `InstanceManager::reconnect_instance` | `POST /instance/reconnect` | instância | — |
| `InstanceManager::disconnect_instance` | `DELETE /instance/logout` | instância | — |
| `InstanceManager::get_qr_code` | `GET /instance/qr` | instância | `base64`/`code` |
| `InstanceManager::get_connection_state` | `GET /instance/status` | instância | `{state}` → `map_state` |
| `InstanceManager::list_all_instances` | `GET /instance/all` | global | `{data:[{name}]}` |
| `MessageSender::send_text` | `POST /send/text` | instância | `{number, text, quoted?}` → `key.id`/`id` |
| `MessageSender::send_media` | `POST /send/media` | instância | `{number, type, url, caption, filename}` → id |
| `AdvancedSettingsControl::set_advanced_settings` | `PUT /instance/{id}/advanced-settings` | instância | flags |
| `ReadReceipts::mark_read` | `POST /message/markread` | instância | `{number, id:[…]}` |
| `Reactions::send_reaction` | `POST /message/react` | instância | `{number, reaction, id, fromMe}` |
| `PresenceControl::set_presence` | `POST /message/presence` | instância | `{number, state, isAudio}` |
| `ProfileQuery::get_profile_picture` | `POST /user/avatar` | instância | `{number, preview:false}` → `profilePictureUrl`/`url` |
| `MediaDownloader::download_media` | `POST /message/downloadmedia` | instância | `{message}` → `base64`/`mimetype` |

- Sobrescrever os acessores da fachada (`fn reactions(&self) -> Some(self)`, etc.).
- `map_state`: `open`/`connected`→Connected, `close`/`disconnected`/`loggedOut`→Disconnected,
  `connecting`→Connecting, resto→Unknown.
- `client.rs`: structs de desserialização Go (`token`/`id` no create; `state` no topo do status).
- Helper `send_request` central; `ok_or_api` com body truncado.

**Obs/Auditoria E2**: `#[tracing::instrument(err, skip(self, token, text, caption))]`; fields
`provider="evolution"`, `instance_name`. Sem auditoria (infra). Nunca logar `apikey`.

## E3. `data_whatsapp` — registry + `dyn` + novos RPCs
- `AppState { registry: ProviderRegistry, redis_conn }`. Builder registra `EvolutionProvider` no
  `main` (composition root).
- Cada handler: lê instância (`provider`, `name`, `api_key`) via `chamar_data_postgres` →
  `let p = state.registry.resolve(provider)?;` → chama via `dyn`.
- **`CreateWhatsappInstance`**: `create_instance` → persistir registro → `p.connect_instance(name,
  token, &WebhookConfig{ url: http://webhook_ingress:9200/webhook/evolution/{tenant}/{db_id},
  subscribe: ["MESSAGE","CONNECTION","PRESENCE","QRCODE"] })`. Rollback (delete provedor + registro)
  se falhar. Opcional: `p.advanced_settings()`→`set_advanced_settings(always_online:true,
  read_messages:false)`.
- **`GetWhatsappInstanceStatus`**: `get_connection_state`; se desconectado/unknown, `get_qr_code`.
- **Envio/sessão**: `send_text`/`send_media` (núcleo); capacidades opcionais via acessor:
  - `MarkWhatsappMessageRead` → `p.read_receipts().ok_or(Unsupported)?.mark_read(...)`
  - `SendWhatsappReaction` → `p.reactions()...`
  - `SetWhatsappPresence` → `p.presence()...`
  - `GetWhatsappProfilePicture` → `p.profiles()...`
  - `DownloadWhatsappMedia` → `p.media_downloader()...` (usado pelo `worker`)
  - `ReconnectWhatsappInstance` → `p.reconnect_instance(...)`
- **Auditoria**: manter `whatsapp.instance.create/delete`, `whatsapp.admin.bulk_disconnect`.
  Recursos de mensagem não geram auditoria (alto volume; intencional).

**Obs/Auditoria E3**: `#[instrument(skip_all, fields(rpc, tenant_id, provider))]`; `instance_token`
`SecretString`; auditoria sem token.

## E4. `webhook_ingress` — `WebhookNormalizer` registry + eventos Go
- Definir o trait `WebhookNormalizer` (provider + normalize). `AppState` passa a ter
  `normalizers: HashMap<&'static str, Arc<dyn WebhookNormalizer>>` (registrado no `main`).
- Handler: `state.normalizers.get(provider)` → `normalize(...)`; provedor desconhecido = `202` +
  `warn` (sem `match` hardcoded).
- `EvolutionNormalizer::normalize`: `canonical_event(raw)` espelhando `EvolutionEventName.from_raw`
  (UPPERCASE/PascalCase/aliases v2) → enum `{ Message, MessageUpdate, Connection, Presence, Qrcode,
  Contacts }` → tópico universal:
  - `Message` → `whatsapp.message.received`
  - `Connection` → `whatsapp.connection.updated` (map `state` open/close/connecting/loggedOut)
  - `MessageUpdate` → `whatsapp.message.status`
  - `Presence` → `whatsapp.presence.updated`
  - `Contacts` → `whatsapp.contact.updated` *(2ª iteração)*
  - `Qrcode` → só `202` (QR é fluxo de UI via `GetStatus`)
- Dedup de `Message` por `key.id` é do **worker**, não do ingress. `body` sempre em `skip(...)`.

**Obs/Auditoria E4**: `#[instrument(skip(state, body), fields(provider, tenant_id, instance_id,
event_type))]`. Sem auditoria (volume alto). `body` nunca logado.

## E5. Banco e repositório — validação (sem mudança)
`0008_whatsapp_sync.sql` e `infrastructure_postgres/integracoes/whatsapp.rs` já atendem. **Não
reescrever.** Se um novo RPC exigir coluna não persistida, estender o repositório de forma
incremental e **regerar cache SQLx offline** (MEMORY "testes-db-tunel-e-reset").

## E6. `control_plane` — endpoint admin (sem regressão)
Manter `POST /api/v2/admin/whatsapp/disconnect-all` → `AdminBulkDisconnectInstances`, auditoria
enriquecida (`ip_address`/`user_agent`/`user_id`). Resposta **sem tokens**. Grep limpo de
`evolution_sync_*`.

---

## Arquitetura (visão consolidada)

```
control_plane / worker ──RPC──▶ data_whatsapp ──ProviderRegistry.resolve(provider)──▶ dyn MessagingProvider
                                     │                              └─(EvolutionProvider)─HTTP─▶ Evolution Go
                                     └──RPC──▶ data_postgres (whatsapp_* + audit_log)
        security:stream ─────────────────────▶ data_postgres ─▶ audit_log

Evolution Go ──webhook POST──▶ webhook_ingress ──WebhookNormalizer.resolve(provider).normalize──▶ events:stream ──▶ worker

Plugar provedor novo: nova crate infrastructure_<x> (traits de capacidade) +
  registry.register(...) no data_whatsapp + XNormalizer no webhook_ingress. Zero alteração nos consumidores.
```

---

# Fase V — Validation

### V1. Compilação
- `cargo build -p infrastructure_messaging -p infrastructure_evolution -p webhook_ingress -p data_whatsapp`.
- Regenerar cache SQLx offline se o repositório for tocado.

### V2. Testes (scripts canônicos — MEMORY "test-scripts")
- **Rust**: `.\infra\test-local.ps1` (NUNCA `cargo test` direto):
  - `infrastructure_messaging`: round-trip serde dos enums; `Display` de erro (incl. `Unsupported`);
    **`ProviderRegistry`** (resolve registrado / `Config` para desconhecido); object-safety (compila
    `Arc<dyn MessagingProvider>`); descoberta de capacidade (mock implementando só núcleo → acessores
    devolvem `None`).
  - `infrastructure_evolution`: **mock HTTP (wiremock)** dos endpoints Go (`/instance/create` lê
    `token`, `/instance/connect` com `subscribe`/`webhookUrl`, `/instance/status`, `/instance/all`,
    `/send/text`, `/send/media`, `/message/markread`, `/message/react`, `/message/presence`,
    `/user/avatar`, `/message/downloadmedia`, `DELETE /instance/logout`); `map_state`; truncamento.
    **Atualizar os mocks v2 existentes** em `data_whatsapp/tests` e `infrastructure_evolution/tests`.
  - `data_whatsapp`: handlers com `data_postgres` mockado + **registry com provider fake** (mock do
    trait via `mockall`) — prova que o consumidor depende só do `dyn`; fluxo create com
    `connect_instance`+webhook; capacidade ausente → `Unsupported`.
  - `webhook_ingress`: `WebhookNormalizer` registry (provedor desconhecido = 202); `canonical_event`
    para UPPERCASE/PascalCase/aliases; normalização de `Message`/`Connection`/`Presence`; `body` não
    vaza em logs.
- **Flutter** (se algum client for tocado): `.\infra\test-flutter.ps1`.

### V3. Validação manual (stack Docker, Evolution Go já rodando)
- Criar instância via `data_whatsapp`; confirmar `POST /instance/connect` com `subscribe`/`webhookUrl`;
  escanear QR (`/instance/qr`); enviar texto (`/send/text`); verificar `whatsapp.message.received`.
  Verificar `Connection` → `whatsapp.connection.updated`. Testar `markread`/`react`/`presence`.
  **Confirmar o campo `base64` do `/message/downloadmedia`** (estava incerto na coleta).

### V4. Observabilidade/auditoria
- Logs **sem** `apikey`/`instance_token`/body de webhook/telefone/conteúdo. `audit_log` com
  create/delete/bulk_disconnect, `context` sem segredos, `tenant_id` NULL quando global.

---

# Fase C — Confirmation

### C1. Critérios de pronto
- Build/testes (V1–V2) verdes via scripts canônicos; integração manual (V3) e auditoria (V4)
  confirmadas contra o Evolution Go real.
- Nenhuma referência a endpoints v2 (`/message/sendText`, `/webhook/set`,
  `/instance/connectionState`, `/instance/fetchInstances`) remanescente (grep limpo).
- Nenhum consumidor referencia `EvolutionProvider` concreto (só `dyn MessagingProvider` via
  registry) — grep por `EvolutionProvider` só em `infrastructure_evolution` e na composição.

### C2. Gate de final-review
- `prevc-final-review` (subagente Opus): compara implementado × este plano, corrige desvios,
  arquiva e commita. Sem auto-referência nos commits (MEMORY "git-no-self-reference"); gitflow.

### C3. Documentação
- Atualizar `doc_dev/libs/` (Evolution Go, axum 0.8) se o contrato real divergir do doc local.

---

# Resumo das mudanças vs. planos-base

1. **Conformidade SOLID + plugabilidade** (núcleo desta revisão):
   - **ISP**: trait único de ~19 métodos → **traits de capacidade** + fachada com descoberta
     (`Option<&dyn …>`). Provedor implementa só o que suporta.
   - **DIP**: `data_whatsapp` deixa de segurar `EvolutionProvider` concreto → **`ProviderRegistry`**
     resolve `dyn MessagingProvider` pelo `provider` da instância.
   - **OCP**: `match provider` do `webhook_ingress` → **registry de `WebhookNormalizer`**.
   - **LSP**: capacidade ausente retorna `Unsupported` (sem no-op/`panic`).
2. **Alvo corrigido: Evolution v2 → Evolution Go** (REST e eventos realinhados ao servidor que roda;
   referência `evolution_go_adapter.py`).
3. **Superfície completa do Go**: `markread`, `react`, `presence`, `download_media`,
   `advanced-settings` (`alwaysOnline`), `reconnect`, `profile picture`.
4. **Webhook unificado no connect** (Go não tem `/webhook/set`); `subscribe` UPPERCASE.
5. **Sem mudança de schema**: `0008_whatsapp_sync.sql` mantido; repositório/ports reaproveitados.
