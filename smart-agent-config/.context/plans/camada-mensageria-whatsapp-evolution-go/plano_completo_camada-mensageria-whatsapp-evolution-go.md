# Plano Consolidado (v3 — Realinhamento Evolution Go): Módulo Rust de Mensageria WhatsApp

> Consolida o documento único `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`
> (que substituiu os planos-base v2 anteriores). Realinha a camada Rust de mensageria do
> **contrato Evolution API v2 (Baileys)** — que está escrito no código atual — para o
> **Evolution Go (whatsmeow)**, que é o servidor que está rodando, e amplia para a
> **superfície completa** (presença, reações, recibo de leitura, download de mídia,
> advanced-settings, reconnect, foto de perfil).
>
> **Fonte da verdade do contrato Go**: `old/.../evolution_sync/services/evolution_go_adapter.py`
> e `.../domain/schemas.py` (battle-tested, rodam contra o **mesmo servidor** em produção).
> Onde a coleta web conflitar com o adapter, **o adapter prevalece**.
>
> **Natureza do trabalho**: NÃO é greenfield. O scaffolding (crates, apps, migração,
> ports/adapters) **já existe**. Não há criação de crate/app, **não há mudança de schema**.
> O trabalho é **realinhamento + ampliação** de 4 componentes Rust.
>
> Organização em fases **PREVC** (Planning, Review, Execution, Validation, Confirmation).

---

## Objetivo

Estruturar o **módulo Rust único responsável por toda a comunicação com o Evolution Go**:
criação/gestão de instâncias, conexão/QR, envio de mensagens e mídia, recursos de sessão
(presença, leitura, reações, foto de perfil, download de mídia) e ingestão normalizada de
webhooks. As regras de negócio dos tenants nunca falam com o Evolution diretamente — só com
este módulo, através do contrato Rust `MessagingProvider` e de eventos universais no
barramento Redis Streams.

### Premissas

1. **Provedor único hoje = Evolution Go.** A abstração `MessagingProvider` permanece, mas a
   implementação concreta (`EvolutionProvider`) passa a falar o contrato **Go**, não o v2.
2. **Normalização no ingress.** O `webhook_ingress` recebe webhooks proprietários do Go
   (eventos UPPERCASE/PascalCase + envelope whatsmeow `data.Info`/`data.Message`) e publica
   eventos universais (`whatsapp.message.received`, `whatsapp.connection.updated`, …). O resto
   do sistema só consome eventos normalizados.
3. **Banco genérico, multi-provedor.** Tabelas `whatsapp_*` com coluna `provider` sem default
   acoplado. **Já implementado** — inclusive `subscribed_events JSONB` e `last_connection_state`
   já existem na migração `0008` (ver E5).
4. **Segredos sempre `SecretString`.** `global_api_key` e `instance_token` jamais em logs ou
   respostas; `api_key` encriptado em repouso.

---

## ⚠️ Reconciliação com o repositório real (pré-condição da execução)

### Já implementado e correto (não mexer, apenas validar)

| Componente | Caminho | Situação |
| --- | --- | --- |
| Migração genérica | `server/crates/infrastructure_postgres/migrations/0008_whatsapp_sync.sql` | ✅ `whatsapp_instance/contact/whitelist`, RLS+FORCE, `provider` sem default, `UNIQUE(tenant_id,name)`, já tem colunas `subscribed_events JSONB` e `last_connection_state`. |
| Repositório WhatsApp | `infrastructure_postgres/src/integracoes/whatsapp.rs` + `whitelist.rs` | ✅ Neutro de provedor; serve ao Go sem alteração. |
| Port/Adapter no data_postgres | `data_postgres/src/ports/whatsapp.rs`, `src/adapters/whatsapp.rs` | ✅ `WhatsappStore` (`criar_instancia`/`buscar_instancia`/`listar_ativas`/`admin_listar_conectadas`/`admin_deletar_instancia`/`atualizar_estado`/`atualizar_provider_id`), RLS + admin BYPASSRLS. |
| Crate de contrato | `server/crates/infrastructure_messaging` | ⚠️ Existe; **trait precisa ampliar** (ver E1). |
| Crate Evolution | `server/crates/infrastructure_evolution` | ⚠️ Existe; **fala v2, precisa realinhar ao Go** (ver E2). |
| App orquestrador | `server/apps/data_whatsapp` | ⚠️ Existe; RPCs em cima da trait v2 — **realinhar + ampliar** (ver E3); testes wiremock batem em paths v2. |
| App ingress | `server/apps/webhook_ingress` | ⚠️ Existe; **só trata `messages.upsert`/`connection.update` (v2 lowercase)** — realinhar p/ Go (ver E4). |

### Divergência central: contrato v2 (no código) × Evolution Go (rodando)

> Tabela de endpoints Go — **fonte: `evolution_go_adapter.py`** (cada operação tem o método
> Python equivalente entre parênteses, validado contra o servidor real).

| Operação | Código Rust atual (v2) | Evolution Go (alvo real) | Auth `apikey` |
| --- | --- | --- | --- |
| Criar instância | `POST /instance/create` `{instanceName, qrcode:true, integration:"WHATSAPP-BAILEYS"}` → lê `hash` | `POST /instance/create` `{name, token?}` → lê `token` (`create_instance`) | **global** |
| Conectar + webhook | `GET /instance/connect/{name}` **+** `PUT /webhook/set/{name}` (2 chamadas) | `POST /instance/connect` `{instanceName, webhookUrl, subscribe:[…], immediate:true}` (**1 chamada**, webhook embutido) (`connect_instance`) | **instância** ⚠️ |
| QR Code | `GET /instance/connect/{name}` | `GET /instance/qr` → `{base64?, code?}` (`get_qr_code`) | **instância** |
| Estado | `GET /instance/connectionState/{name}` → `instance.state` | `GET /instance/status` → `{state}` (v2 retorna **503** no Go) (`get_status`) | **instância** |
| Listar | `GET /instance/fetchInstances` (array) | `GET /instance/all` → `{data:[…]}` ou `[…]` (`fetch_instances`) | **global** |
| Logout/desconectar | `POST /instance/logout/{name}` | `DELETE /instance/logout` (**sem nome no path**) (`logout_instance`) | **instância** |
| Deletar | `DELETE /instance/delete/{name}` | `DELETE /instance/delete/{name}` (igual) (`delete_instance`) | **global** |
| Reconectar | (usa `connect`) | `POST /instance/reconnect` (`reconnect_instance`) | **instância** |
| Advanced settings | (n/d) | `PUT /instance/{id}/advanced-settings` `{alwaysOnline, readMessages, rejectCall, msgRejectCall, ignoreGroups, ignoreStatus}` (`set_advanced_settings`) | **instância** |
| Enviar texto | `POST /message/sendText/{name}` `{number,text}` → `key.id` | `POST /send/text` `{number, text, quoted?}` → `key.id` (`send_text`) | **instância** |
| Enviar mídia | `POST /message/sendMedia/{name}` `{media, mediatype}` | `POST /send/media` `{number, type, url, caption, filename}` (`send_media`) | **instância** |
| Enviar áudio/PTT | (via send_media) | `POST /send/media` `{number, type:"audio", url}` (`send_audio`) | **instância** |
| Reagir | (n/d) | `POST /message/react` `{number, reaction, id, fromMe}` (`send_reaction`) | **instância** |
| Marcar lido | (n/d) | `POST /message/markread` `{number, id:[…]}` (`mark_read`) | **instância** |
| Presença | (n/d) | `POST /message/presence` `{number, state, isAudio}` (`set_presence`) | **instância** |
| Foto de perfil | (n/d) | `POST /user/avatar` `{number, preview:false}` → `profilePictureUrl`/`url` (`get_profile_picture`) | **instância** |
| Download mídia | (n/d) | `POST /message/downloadmedia` `{message}` → `base64` (`download_media`) | **instância** |
| Eventos webhook | `messages.upsert`/`connection.update` (lowercase) | `Message`/`Connection`/`Presence`/`QRCode`/`Contacts` (UPPERCASE/PascalCase + aliases); envelope whatsmeow `data.Info` | — |

### ⚠️ Armadilhas confirmadas do Go (notas inline do adapter battle-tested)

1. **`POST /instance/connect` exige o TOKEN DA INSTÂNCIA** no header `apikey`. A Global Key
   retorna **401 "not authorized"** aqui. *(O subagente web disse "global key" — INCORRETO para
   este servidor; o adapter vence.)*
2. **Campo de eventos é `subscribe`** (array UPPERCASE: `MESSAGE`, `CONNECTION`, `PRESENCE`,
   `QRCODE`) no body do `connect`. Nome inválido **zera** a assinatura (`events=""`) → para
   toda entrega de webhook. **Não usar o campo `events` do v2.**
   > ⚠️ **Contradição interna do adapter (resolvida):** o *docstring* no topo do
   > `evolution_go_adapter.py` (linhas 21-29) diz "NÃO usar `subscribe`, usar `events`", mas o
   > **código real** de `connect_instance` (linhas 504-512) envia `subscribe` e o info_aux
   > confirma `subscribe`. **O código executável vence o docstring**: usar `subscribe`.
3. **Status é `GET /instance/status`** — **NÃO** `/instance/connectionState/{name}` (v2;
   retorna **503** no Go). A resposta tem `state` no topo, não em `instance.state`.
4. **Envio é `/send/text` e `/send/media`** — NÃO `/message/sendText/{name}` (v2). Body de
   mídia usa `type`/`url`/`caption`/`filename` (NÃO `mediatype`/`media`/`fileName`).
5. **Logout é `DELETE /instance/logout`** (sem nome no path), token da instância.
6. **`readMessages` deve ser `false`** — recibo de leitura é explícito via `markread`, nunca
   automático (whatsmeow mandaria ticks azuis em toda mensagem se `true`).
7. **`alwaysOnline:true`** é o mecanismo documentado para manter a sessão whatsmeow viva.
8. **Download**: a rota real é `/message/downloadmedia` (o swagger lista `/downloadimage`,
   incorreto). Resposta traz **`base64`** (subagente web disse `media` — **INCERTO**, validar
   no servidor real em V3).
9. **Idempotência**: webhooks de mensagem podem chegar 2× (retry); dedup por `key.id` é do
   **worker** (consumidor), não do ingress.
10. **Dois formatos de envelope Go**: o webhook do Go chega em formato **whatsmeow nativo**
    (`data.Info.{Chat,Sender,ID,IsFromMe,PushName,Timestamp,MediaType}` + `data.Message.<tipo>Message`
    com chaves `URL`/`fileEncSHA256`/`mediaKey`…) **ou** já em formato Node-like
    (`data.key`/`data.message`/`data.pushName`). O `translate_go_payload` do `schemas.py` detecta
    `data.Info` e converte. O ingress **deve preservar o `raw_event` íntegro** e deixar a
    conversão para o worker (ver E4), OU canonizar minimamente (decisão D6).

Apps existentes (confirmados): `control_plane`, `data_postgres`, `data_redis`, `data_storage`,
`data_whatsapp`, `webhook_ingress`, `messaging_gateway`, `runtime_api`, `worker`.
Crates: `application`, `contracts`, `error_core`, `infrastructure_messaging`,
`infrastructure_evolution`, `infrastructure_postgres`, `infrastructure_redis`,
`infrastructure_storage`, `observability`, `test_support`, `transport`.

---

## Decisões de Design

### D1. Duas crates de abstração (mantidas)
- **`infrastructure_messaging`**: trait `MessagingProvider`, enums normalizados
  (`ConnectionState`, `MediaType`, `PresenceState`), structs de payload (`CreateInstanceResult`,
  `SendMessageResult`, `MediaDownloadResult`, `AdvancedSettings`) e `MessagingProviderError`.
  Pura: sem runtime, sem I/O, sem logs.
- **`infrastructure_evolution`**: implementa `MessagingProvider` via HTTP REST (reqwest 0.12)
  contra o **Evolution Go**.

### D2. `EvolutionProvider` com `base_url` + helper `send_request` central
A struct carrega `http: reqwest::Client` (pool interno, clone barato), `base_url: String` e
`global_api_key: SecretString` (criar/deletar/listar). O `instance_token` é recebido **por
chamada** (conectar/QR/status/enviar/sessão/download). Um helper interno
`send_request(method, path, apikey, body)` **espelha o `_send_request` do adapter Go**,
centralizando header `apikey`, `Content-Type: application/json`, e o tratamento de erro
(`ok_or_api`, body truncado a 200 chars). Isso elimina a repetição atual de
`.header("apikey", …).send().await.map_err(Network)?` em cada método.

### D3. Roteamento dinâmico em `data_whatsapp`
Ao receber um RPC, o app: (1) resolve `name`/`api_key`/`provider` da instância via
`GetWhatsappInstance` (data_postgres); (2) delega à struct que implementa `MessagingProvider`
(hoje só `EvolutionProvider`). Factory trivial agora, fronteira pronta para 2º provedor.

### D4. Webhook embutido no connect (Go não tem `/webhook/set`)
URL configurada no body do `POST /instance/connect`:
```
http://webhook_ingress:9200/webhook/{provider}/{tenant_id}/{instance_id}
```
O `connect` carrega `webhookUrl` + `subscribe:["MESSAGE","CONNECTION","PRESENCE","QRCODE"]` +
`immediate:true`. **`configure_webhook` deixa de existir como chamada de rede separada**: no
trait permanece por compatibilidade, mas a implementação Go o transforma em delegação ao
`connect` (idempotente) — ou no-op documentado. A responsabilidade de URL+subscribe migra para
o fluxo `CreateWhatsappInstance` (E3).

### D5. Desconexão em massa pelo admin (mantida)
RPC `AdminBulkDisconnectInstances`: `tenant_id: Option<Uuid>`; `None` ⇒ todas as instâncias de
todos os tenants (BYPASSRLS via `AdminListAllConnectedInstances`, exige escopo
`operacional:admin`). Atualiza `connection_state='disconnected'`. **Passa a usar `DELETE
/instance/logout`** (sem nome no path) após E2.

### D6. Canonização de eventos no ingress, normalização "fina" + `raw_event` íntegro
O ingress **canoniza** o nome do evento (`canonical_event`, espelhando
`EvolutionEventName.from_raw`: UPPERCASE/PascalCase/aliases v2 → enum canônico) e publica em
`events:stream`. A **extração profunda de conteúdo** (texto, mídia, JID, `translate_go_payload`
do envelope whatsmeow `data.Info`) **fica no worker** — o ingress repassa `raw_event` íntegro
(sem logar PII), apenas anexando `instance_id`/`provider`/`event_type` canônico e, p/
`Connection`, o `state` normalizado (já é barato e útil p/ atualização de estado). Isso mantém o
ingress simples, sem PII em logs, e centraliza a complexidade de payload no consumidor — igual
ao split do projeto old (ingress/`from_raw` vs. `WebhookProcessor`).

---

## Arquitetura (visão consolidada)

```
control_plane / worker ──RPC──▶ data_whatsapp ──(MessagingProvider)──▶ infrastructure_evolution ──HTTP──▶ Evolution Go
        │                            │
        │ (auditoria)                └──RPC──▶ data_postgres (whatsapp_* + audit_log)
        ▼
   security:stream ───────────────▶ data_postgres ─▶ audit_log

Evolution Go ──webhook POST──▶ webhook_ingress ──canoniza+normaliza fina──▶ events:stream ──▶ worker/messaging_gateway

Stacks Docker:
  - principal: control_plane, data_whatsapp, webhook_ingress, data_postgres, worker, …
  - Evolution Go isolada: container `evolution` (evoapicloud/evolution-go) + postgres próprio
  - rede external compartilhada entre as stacks (MEMORY "deploy-evolution-remove-orphans")
```

---

# Fase P — Planning (output)

**Status: concluída.**

- **Escopo**: realinhamento de 4 componentes Rust ao Evolution Go + ampliação de superfície.
  Nenhuma crate/app nova; nenhuma mudança de schema (DB pronto, inclusive `subscribed_events`).
- **Contrato central**: `MessagingProvider` ampliado para a superfície completa do Go.
- **Eventos normalizados** publicados em `events:stream`:
  - `whatsapp.message.received` (de `MESSAGE`)
  - `whatsapp.connection.updated` (de `CONNECTION`)
  - `whatsapp.message.status` (de `MESSAGE_UPDATE`)
  - `whatsapp.presence.updated` (de `PRESENCE`)
  - `whatsapp.contact.updated` (de `CONTACTS`) *(opcional na 1ª entrega)*
  - `QRCODE` → **não** publica no barramento de domínio (fluxo de UI via `GetStatus`); só `202`.
- **Auditoria** em `security:stream` → `data_postgres` → `audit_log`:
  `whatsapp.instance.create`, `whatsapp.instance.delete`, `whatsapp.admin.bulk_disconnect`.
- **Mapa de risco**: contrato Go indocumentado em alguns pontos (mitigado pelo adapter);
  `subscribe` inválido zera webhooks; campo `base64` do download incerto (validar V3); dois
  `axum` coexistem (0.7.5 `runtime_api`, 0.8 `webhook_ingress`) — **não unificar** via workspace.

---

# Fase R — Review (arquitetura e contratos)

### R1. Compatibilidade de versões (USAR LOCAL — `doc_dev/libs/rust/`)
- `reqwest 0.12.4` (feature `json`) em `infrastructure_evolution` (já está). Reusar um único
  `reqwest::Client` (pool interno, clone barato); `.json(&body)`; checar `status().is_success()`
  antes de desserializar. Doc local menciona Evolution Go explicitamente.
- `axum 0.8` declarado **localmente** no `Cargo.toml` do `webhook_ingress` (já está). NÃO
  adicionar `axum` ao workspace (`runtime_api` permanece 0.7.5). Sintaxe 0.8 já em uso:
  rotas `{param}`, `State`, `axum::serve(listener, app)`, `.with_state`.
- `secrecy 0.10.3` (`SecretString`, `ExposeSecret`); `async-trait 0.1.83`; `serde/serde_json 1`;
  `thiserror 1`; `uuid 1`; `tracing 0.1.40`; `redis 0.25` (`transport::bus`); `tokio 1.38`.
- Dev: `wiremock 0.6` (mock HTTP dos endpoints Go), `mockall 0.13` (mock da port `WhatsappStore`).

### R2. Sanidade de segurança
- `global_api_key`/`instance_token` sempre `SecretString`; sempre em `skip(...)` do `instrument`.
- `api_key` no banco encriptado (mesma política das demais credenciais de tenant).
- RLS+FORCE em todas as `whatsapp_*`; bypass cross-tenant só por `admin_pool`/transação admin
  explícita, sob escopo `operacional:admin`.
- Body de erro do provedor truncado a 200 chars (evita vazar telefone/conteúdo). Body do
  webhook **nunca** logado.

### R3. Contrato de barramento
- Reaproveitar `contracts::TenantEnvelope<T>` + `transport::bus::publicar_evento` /
  `publicar_evento_seguranca` (já em uso no `webhook_ingress` e `data_whatsapp`). Não inventar
  stream key.

**Gate R**: aprovado se R1/R2/R3 confirmados. Saída → Execution.

---

# Fase E — Execution (detalhe técnico por componente)

## E1. `infrastructure_messaging` — ampliar o contrato

### O que existe hoje (`src/lib.rs`)
Trait `MessagingProvider` com 12 métodos (`provider_name`, `create_instance`, `delete_instance`,
`connect_instance`, `disconnect_instance`, `get_qr_code`, `pair_by_phone`, `configure_webhook`,
`get_connection_state`, `send_text`, `send_media`, `list_all_instances`). Tipos:
`ConnectionState` (lowercase serde), `CreateInstanceResult { provider_instance_id, instance_token }`,
`SendMessageResult { message_id }`, `MediaType` (Image/Video/Audio/Document). Erros em
`src/errors.rs`: `MessagingProviderError` (`Network`/`ProviderApi{status,body}`/`Deserialization`/
`Config`/`InvalidState`).

### O que muda (Go)
Manter os 12 métodos atuais; **acrescentar** a superfície Go. Adicionar enums/structs neutros.

```rust
// --- Novos tipos neutros (src/lib.rs) ---

/// Estado de presença (typing/recording) normalizado.
#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PresenceState {
    Composing, // digitando
    Paused,    // parou de digitar
    Recording, // gravando áudio
}

/// Resultado do download/descriptografia de mídia.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MediaDownloadResult {
    pub base64: String,
    pub mime_type: Option<String>,
}

/// Flags de advanced-settings do Go. `read_messages` default `false` (recibo explícito).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AdvancedSettings {
    pub always_online: bool,
    pub read_messages: bool,
    pub reject_call: bool,
    pub msg_reject_call: String,
    pub ignore_groups: bool,
    pub ignore_status: bool,
}

impl Default for AdvancedSettings {
    fn default() -> Self {
        Self {
            always_online: true,    // mantém a sessão whatsmeow viva
            read_messages: false,   // recibo de leitura é explícito (markread)
            reject_call: false,
            msg_reject_call: String::new(),
            ignore_groups: false,
            ignore_status: false,
        }
    }
}
```

Novos métodos no trait `MessagingProvider` (todos `async`, erro `MessagingProviderError`):

```rust
async fn reconnect_instance(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
) -> Result<(), MessagingProviderError>;

async fn set_advanced_settings(
    &self,
    instance_id: &str,                 // UUID da instância no Go (path)
    instance_token: &SecretString,
    settings: AdvancedSettings,
) -> Result<(), MessagingProviderError>;

async fn mark_read(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    chat: &str,                        // remoteJid / número
    message_ids: &[String],
) -> Result<(), MessagingProviderError>;

async fn send_reaction(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    chat: &str,
    message_id: &str,
    emoji: &str,                       // "" remove a reação
    from_me: bool,
) -> Result<SendMessageResult, MessagingProviderError>;

async fn set_presence(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    chat: &str,
    state: PresenceState,
    is_audio: bool,                    // true → "gravando áudio…"
) -> Result<(), MessagingProviderError>;

async fn get_profile_picture(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    number: &str,
) -> Result<Option<String>, MessagingProviderError>; // None se não houver foto

async fn download_media(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    message: &serde_json::Value,       // sub-objeto whatsmeow com chaves de descriptografia
) -> Result<MediaDownloadResult, MessagingProviderError>;
```

- **`configure_webhook`**: permanece no trait por compatibilidade do contrato. Documentar no
  doc-comment que **no Go é no-op/delegação a `connect_instance`** (D4): a URL e o `subscribe`
  são responsabilidade do fluxo de conexão.
- **`pair_by_phone`**: mantido no trait (não há equivalente direto confirmado no adapter Go;
  manter assinatura, sinalizar `InvalidState` ou no-op até confirmar suporte no servidor).
- Testes da crate: ampliar `tests` para round-trip serde de `PresenceState`,
  `MediaDownloadResult`, `AdvancedSettings::default()` (garantir `always_online=true`,
  `read_messages=false`) e `Display` dos erros (já cobertos parcialmente).

### Observabilidade & Auditoria — E1
- **a) Logs/traces**: **nenhum** — crate pura, sem runtime/I/O/logs (mantém o invariante atual).
- **b) Auditoria**: **sem evento de auditoria** (intencional — crate pura, sem efeito colateral).
- **c) Sanitização**: `instance_token` é `SecretString` em todas as assinaturas novas; o `Debug`
  derivado de `SecretString` redige o segredo. Structs de payload (`AdvancedSettings`) não
  carregam segredo.

## E2. `infrastructure_evolution` — realinhar `provider.rs`/`client.rs` ao Go

### O que existe hoje
`client.rs`: `EvolutionProvider { http, base_url, global_api_key }`, helper `ok_or_api`
(trunca erro a 200 chars — manter), structs `CreateInstanceResp { instance, hash }` /
`ConnStateResp { instance: { state } }` (v2). `provider.rs`: cada método monta a request
inline com `.header("apikey", …)` e bate em **paths v2**; `map_state` cobre só
`open`/`close`/`connecting`.

### O que muda (Go) — tabela canônica de endpoints (substitui a lista v2)

| Método trait | HTTP Go | Header `apikey` | Body / parse |
| --- | --- | --- | --- |
| `create_instance` | `POST /instance/create` | global | `{name, token?}` → `token` (e `id`/`name`) |
| `delete_instance` | `DELETE /instance/delete/{name}` | global | — |
| `connect_instance` | `POST /instance/connect` | **instância** | `{instanceName, webhookUrl, subscribe:[…], immediate:true}` |
| `configure_webhook` | (delega a `connect_instance`) | **instância** | no-op de rede / idempotente |
| `get_qr_code` | `GET /instance/qr` | instância | `base64`/`code` |
| `get_connection_state` | `GET /instance/status` | instância | `{state}` (topo) → `map_state` |
| `disconnect_instance` | `DELETE /instance/logout` | instância | — (sem nome no path) |
| `reconnect_instance` | `POST /instance/reconnect` | instância | — |
| `list_all_instances` | `GET /instance/all` | global | `{data:[{name}]}` ou `[{name}]` |
| `send_text` | `POST /send/text` | instância | `{number, text, quoted?}` → `key.id`/`id` |
| `send_media` | `POST /send/media` | instância | `{number, type, url, caption, filename}` → `key.id` |
| `set_advanced_settings` | `PUT /instance/{id}/advanced-settings` | instância | flags `AdvancedSettings` |
| `mark_read` | `POST /message/markread` | instância | `{number, id:[…]}` |
| `send_reaction` | `POST /message/react` | instância | `{number, reaction, id, fromMe}` → id |
| `set_presence` | `POST /message/presence` | instância | `{number, state, isAudio}` |
| `get_profile_picture` | `POST /user/avatar` | instância | `{number, preview:false}` → `profilePictureUrl`/`url` |
| `download_media` | `POST /message/downloadmedia` | instância | `{message}` → `base64`/`mimetype` |

### Mudanças concretas em `client.rs`

```rust
#[derive(Clone)]
pub struct EvolutionProvider {
    pub(crate) http: reqwest::Client,
    pub(crate) base_url: String,
    pub(crate) global_api_key: SecretString, // gerencia instâncias; NUNCA logar
}

impl EvolutionProvider {
    pub fn new(base_url: impl Into<String>, global_api_key: SecretString) -> Self {
        Self { http: reqwest::Client::new(), base_url: base_url.into(), global_api_key }
    }

    /// Helper central — espelha `_send_request` do adapter Go. Centraliza header
    /// `apikey`, `Content-Type` e o map de erro de rede; reusa `ok_or_api` p/ status.
    /// `apikey` é `&SecretString` e nunca é logado.
    pub(crate) async fn send_request(
        &self,
        method: reqwest::Method,
        path: &str,
        apikey: &SecretString,
        body: Option<&serde_json::Value>,
    ) -> Result<reqwest::Response, MessagingProviderError> {
        let url = format!("{}{}", self.base_url, path);
        let mut req = self
            .http
            .request(method, url)
            .header("apikey", apikey.expose_secret());
        if let Some(b) = body {
            req = req.json(b);
        }
        let resp = req
            .send()
            .await
            .map_err(|e| MessagingProviderError::Network(e.to_string()))?;
        Self::ok_or_api(resp).await
    }

    /// (mantido) status != 2xx vira ProviderApi com body truncado a 200 chars.
    pub(crate) async fn ok_or_api(
        resp: reqwest::Response,
    ) -> Result<reqwest::Response, MessagingProviderError> { /* inalterado */ }
}

// Structs de desserialização Go (substituem CreateInstanceResp/ConnStateResp v2):
#[derive(serde::Deserialize)]
pub(crate) struct CreateInstanceResp {
    pub(crate) token: Option<String>,
    pub(crate) id: Option<String>,
    pub(crate) name: Option<String>,
}

#[derive(serde::Deserialize)]
pub(crate) struct ConnStateResp {
    pub(crate) state: String, // `state` no TOPO (não em `instance.state`)
}
```

### Exemplos de métodos realinhados em `provider.rs`

```rust
#[tracing::instrument(err, skip(self, custom_token), fields(provider = "evolution", instance_name = %instance_name))]
async fn create_instance(
    &self,
    instance_name: &str,
    custom_token: Option<&SecretString>,
) -> Result<CreateInstanceResult, MessagingProviderError> {
    let mut body = serde_json::json!({ "name": instance_name });
    if let Some(tok) = custom_token {
        body["token"] = serde_json::Value::String(tok.expose_secret().to_string());
    }
    let resp = self
        .send_request(reqwest::Method::POST, "/instance/create", &self.global_api_key, Some(&body))
        .await?;
    let parsed: CreateInstanceResp = resp
        .json().await
        .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
    let token = parsed.token.ok_or_else(|| {
        MessagingProviderError::Deserialization("token ausente na resposta".into())
    })?;
    Ok(CreateInstanceResult {
        provider_instance_id: parsed.id.or(parsed.name).unwrap_or_else(|| instance_name.to_string()),
        instance_token: token,
    })
}

#[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
async fn connect_instance(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
) -> Result<(), MessagingProviderError> {
    // ⚠️ token da INSTÂNCIA; global key dá 401 aqui.
    // NOTE: a URL e o subscribe são montados em data_whatsapp (E3) e passados via
    // um método dedicado `connect_with_webhook`. Aqui mantemos a assinatura neutra
    // do trait: se chamado sem webhook (reconnect simples), envia subscribe default.
    let body = serde_json::json!({
        "instanceName": instance_name,
        "subscribe": ["MESSAGE", "CONNECTION", "PRESENCE", "QRCODE"],
        "immediate": true
    });
    self.send_request(reqwest::Method::POST, "/instance/connect", instance_token, Some(&body)).await?;
    Ok(())
}

#[tracing::instrument(err, skip(self), fields(provider = "evolution", instance_name = %instance_name))]
async fn get_connection_state(
    &self,
    instance_name: &str,
) -> Result<ConnectionState, MessagingProviderError> {
    // ⚠️ Go: GET /instance/status com TOKEN da instância. Mas a assinatura atual do
    // trait não recebe instance_token aqui. Ver "Ajuste de assinatura" abaixo.
    // ...
}

#[tracing::instrument(err, skip(self, instance_token, text), fields(provider = "evolution", instance_name = %instance_name))]
async fn send_text(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    to_number: &str,
    text: &str,
) -> Result<SendMessageResult, MessagingProviderError> {
    let body = serde_json::json!({ "number": to_number, "text": text });
    let resp = self
        .send_request(reqwest::Method::POST, "/send/text", instance_token, Some(&body))
        .await?;
    let v: serde_json::Value = resp.json().await
        .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
    let id = v.get("key").and_then(|k| k.get("id")).and_then(|i| i.as_str())
        .or_else(|| v.get("id").and_then(|i| i.as_str()))
        .ok_or_else(|| MessagingProviderError::Deserialization("key.id ausente na resposta de envio".into()))?;
    Ok(SendMessageResult { message_id: id.to_string() })
}

#[tracing::instrument(err, skip(self, instance_token), fields(provider = "evolution", instance_name = %instance_name))]
async fn download_media(
    &self,
    instance_name: &str,
    instance_token: &SecretString,
    message: &serde_json::Value,
) -> Result<MediaDownloadResult, MessagingProviderError> {
    let body = serde_json::json!({ "message": message });
    let resp = self
        .send_request(reqwest::Method::POST, "/message/downloadmedia", instance_token, Some(&body))
        .await?;
    let v: serde_json::Value = resp.json().await
        .map_err(|e| MessagingProviderError::Deserialization(e.to_string()))?;
    // ⚠️ V3: confirmar o campo — adapter diz `base64`; subagente web disse `media`.
    let base64 = v.get("base64").and_then(|b| b.as_str())
        .or_else(|| v.get("media").and_then(|b| b.as_str())) // fallback defensivo até validar
        .ok_or_else(|| MessagingProviderError::Deserialization("base64 ausente no download".into()))?;
    let mime_type = v.get("mimetype").and_then(|m| m.as_str()).map(str::to_string);
    Ok(MediaDownloadResult { base64: base64.to_string(), mime_type })
}
```

- **`map_state`** ampliado para variações do Go:
  ```rust
  fn map_state(s: &str) -> ConnectionState {
      match s.to_lowercase().as_str() {
          "open" | "connected" => ConnectionState::Connected,
          "close" | "disconnected" | "loggedout" | "logged_out" => ConnectionState::Disconnected,
          "connecting" => ConnectionState::Connecting,
          _ => ConnectionState::Unknown,
      }
  }
  ```
- **Ajuste de assinatura `get_connection_state`/`disconnect_instance`**: hoje
  `get_connection_state(&self, instance_name)` usa `global_api_key`, mas o Go exige **token da
  instância** em `/instance/status` e `/instance/logout`. Como o `data_whatsapp` já resolve o
  `api_key` da instância antes de chamar, **acrescentar `instance_token: &SecretString`** a esses
  dois métodos do trait (E1) e ajustar os call-sites em E3. (Decisão de R: alterar a assinatura é
  preferível a vazar o token global, que daria 503/401.)
- **`connect` com webhook**: para o fluxo de criação (E3) que precisa passar `webhookUrl`+
  `subscribe`, adicionar um método dedicado no `EvolutionProvider` (inerente, não do trait):
  `connect_with_webhook(&self, instance_name, instance_token, webhook_url, subscribe: &[String])`.
  O método do trait `connect_instance` cobre o reconnect/connect "simples".

### Observabilidade & Auditoria — E2
- **a) Logs/traces**: `#[tracing::instrument(err, skip(self, instance_token, text, caption,
  custom_token, message))]` em cada método; `fields(provider = "evolution", instance_name)`.
  `err` registra o `MessagingProviderError` (já com body truncado). Campos de correlação herdados
  do span pai (`service`, `env`, `tenant_id`, `trace_id`); `error_code` deriva do `Display` do
  erro. Nível: `ERROR` no retorno de erro (via `err`), sem `info` por chamada (alto volume).
- **b) Auditoria**: **sem evento de auditoria** (infra/transporte HTTP — intencional). A
  auditoria de negócio (create/delete) vive no `data_whatsapp` (E3).
- **c) Sanitização**: `apikey` **nunca** logado (passado por `send_request`, não aparece em
  `fields`); `instance_token`/`global_api_key`/`custom_token` em `skip(...)`; `text`/`caption`/
  `message` (PII) em `skip(...)`; body de erro truncado a 200 chars no `ok_or_api`.

## E3. `data_whatsapp` — realinhar fluxo + novos RPCs

### O que existe hoje (`src/main.rs`)
`AppState { provider: EvolutionProvider, redis_conn }`. RPCs roteados: `CreateWhatsappInstance`,
`DeleteWhatsappInstance`, `ReconnectWhatsappInstance`, `GetWhatsappInstanceStatus`,
`SendWhatsappMessage`, `SendWhatsappMedia`, `AdminBulkDisconnectInstances`. Helpers `erro`,
`ok_reply`, `chamar_data_postgres`. Auditoria via `publicar_evento_seguranca`. **O
`CreateWhatsappInstance` atual faz `create_instance` → grava DB → `configure_webhook` (PUT
/webhook/set) → `atualizar_provider_id` → auditoria** (fluxo v2).

### O que muda (Go)

1. **`CreateWhatsappInstance`** — após criar a instância e persistir o registro, **conectar via
   `connect_with_webhook`** (E2), passando `webhook_url` e `subscribe`. **Remover** a chamada
   `configure_webhook`/`PUT /webhook/set`. Manter o rollback (delete no provedor + remoção do
   registro) se a conexão falhar. **Opcional/recomendado**: `set_advanced_settings` com
   `AdvancedSettings::default()` (`always_online=true`, `read_messages=false`) logo após
   conectar. Persistir `subscribed_events` no DB (coluna já existe).

   ```rust
   // 3. (NOVO) Conecta + configura webhook embutido (Go não tem /webhook/set)
   let webhook_url = format!(
       "http://webhook_ingress:9200/webhook/{}/{}/{}",
       provider_name, env.tenant_id, db_id
   );
   let subscribe = ["MESSAGE", "CONNECTION", "PRESENCE", "QRCODE"]
       .map(String::from);
   if let Err(e) = state
       .provider
       .connect_with_webhook(instance_name, &instance_token, &webhook_url, &subscribe)
       .await
   {
       let _ = state.provider.delete_instance(instance_name).await;
       let _ = chamar_data_postgres("AdminDeletarInstancia", &env.tenant_id,
           serde_json::json!({ "id": db_id }), &env).await;
       return erro(error_core::AppError::Internal(format!("Falha ao conectar instância: {e}")), &env);
   }

   // 3b. (opcional) advanced-settings: alwaysOnline=true, readMessages=false
   let _ = state.provider.set_advanced_settings(
       &provider_instance_id, &instance_token,
       infrastructure_messaging::AdvancedSettings::default(),
   ).await;
   ```

2. **`GetWhatsappInstanceStatus`** — `get_connection_state` agora exige `instance_token` (E2);
   passar o `api_key_sec` já resolvido. Quando desconectado/unknown, obter QR via
   `get_qr_code` (`/instance/qr`).

3. **`SendWhatsappMessage` / `SendWhatsappMedia`** — já delegam à trait; passam a usar
   `/send/text` e `/send/media` automaticamente após E2. `media_type:audio` → PTT.

4. **`ReconnectWhatsappInstance`** — trocar `connect_instance` por **`reconnect_instance`**
   (`POST /instance/reconnect`, token da instância). (O `connect` simples ainda existe p/ casos
   que precisem re-subscrever.)

5. **Novos RPCs** (superfície completa), no mesmo padrão dos handlers atuais (resolver
   `name`/`api_key` via `GetWhatsappInstance`, delegar à trait):
   - `MarkWhatsappMessageRead` → `mark_read` (`{id, chat, message_ids:[…]}`)
   - `SendWhatsappReaction` → `send_reaction` (`{id, chat, message_id, emoji, from_me}`)
   - `SetWhatsappPresence` → `set_presence` (`{id, chat, state, is_audio}`)
   - `GetWhatsappProfilePicture` → `get_profile_picture` (`{id, number}`)
   - `DownloadWhatsappMedia` → `download_media` (`{id, message}`) — usado pelo **worker** no
     fallback de mídia grande (quando o webhook não traz `base64` inline).
   Registrar cada um no builder `Server::from_env("DATA_WHATSAPP").route(...)` com seu clone de
   `state`.

6. **`AdminBulkDisconnectInstances`** — `disconnect_instance` passa a `DELETE /instance/logout`
   (E2), sem nome no path. Lógica de listagem/escopo inalterada.

7. **Auditoria** — manter `whatsapp.instance.create`/`whatsapp.instance.delete` e
   `whatsapp.admin.bulk_disconnect` (já implementados). Recursos de mensagem
   (`react`/`markread`/`presence`/`download`/`profile`) **não** geram auditoria (alto volume;
   intencional).

### Observabilidade & Auditoria — E3
- **a) Logs/traces**: `#[tracing::instrument(skip_all, fields(rpc = "<Nome>", tenant_id =
  %env.tenant_id))]` por handler (padrão já existente; replicar nos novos RPCs). `instance_id`/
  `db_id` como field quando disponível. `instance_token` materializado como `SecretString` e
  jamais em field. Campos de correlação: `service=data_whatsapp`, `env`, `tenant_id`, `trace_id`
  (via `traceparent` do `Envelope`), `error_code` (do `AppError`).
- **b) Auditoria no banco**: `publicar_evento_seguranca` → `security:stream` → `data_postgres` →
  `audit_log`:
  - `whatsapp.instance.create` (context: `user_id`, `instance_name`, `provider` — **sem token**).
  - `whatsapp.instance.delete` (context: `user_id`, `instance_name`).
  - `whatsapp.admin.bulk_disconnect` (no `control_plane`/handler admin; `tenant_id` **NULL**
    quando ação global de superusuário; context com `ip_address`/`user_agent`/`user_id`, **sem
    token**).
  - Demais RPCs (status/send/react/markread/presence/download/profile/reconnect): **sem evento de
    auditoria** (declarado intencionalmente — alto volume / sem mudança de estado sensível).
- **c) Sanitização**: `api_key`/`instance_token` sempre `SecretString` em `skip`; `text`/
  `caption`/conteúdo de mensagem nunca em fields; respostas RPC **sem** tokens; `context` da
  auditoria sem segredo.

## E4. `webhook_ingress` — canonizar eventos do Go

### O que existe hoje (`src/main.rs`)
Rota axum 0.8 `/webhook/{provider}/{tenant_id}/{instance_id}` → `handle_webhook` →
`normalize_evolution(event, raw, tenant_id, instance_id)`. **Só reconhece `messages.upsert` e
`connection.update`** (v2 lowercase); qualquer outro evento retorna `None` (ignorado).
`build_connection_payload` já normaliza `open/close/connecting`. Body em `skip(...)`.

### O que muda (Go)

1. **Canonização de evento** — função `canonical_event(raw: &str) -> Option<CanonicalEvent>`
   **espelhando `EvolutionEventName.from_raw`** (`schemas.py`): match direto UPPERCASE; depois
   `raw.to_uppercase().replace('.', "_")` (cobre PascalCase `Message`→`MESSAGE`,
   `QRCode`→`QRCODE`, `Presence`→`PRESENCE`); depois tabela de aliases
   (`MESSAGES_UPSERT`/`MESSAGE_UPSERT`→Message, `CONNECTED`/`DISCONNECTED`/`LOGGEDOUT`/
   `LOGGED_OUT`/`LOGOUT`/`CONNECTION_UPDATE`→Connection, `MESSAGES_UPDATE`→MessageUpdate,
   `PRESENCE_UPDATE`→Presence, `QRCODE_UPDATED`→Qrcode, `CONTACTS_UPDATE`→Contacts,
   `SEND_MESSAGE`→SendMessage), com fallback para a forma singular (`rstrip('S')`).

   ```rust
   #[derive(Debug, Clone, Copy, PartialEq, Eq)]
   enum CanonicalEvent { Message, MessageUpdate, Connection, Presence, Qrcode, Contacts, SendMessage }

   fn canonical_event(raw: &str) -> Option<CanonicalEvent> {
       use CanonicalEvent::*;
       let direct = |s: &str| match s {
           "MESSAGE" => Some(Message),
           "MESSAGE_UPDATE" => Some(MessageUpdate),
           "CONNECTION" => Some(Connection),
           "PRESENCE" => Some(Presence),
           "QRCODE" => Some(Qrcode),
           "CONTACTS" => Some(Contacts),
           "SEND_MESSAGE" => Some(SendMessage),
           _ => None,
       };
       if let Some(e) = direct(raw) { return Some(e); }
       let up = raw.to_uppercase().replace('.', "_");
       if let Some(e) = direct(&up) { return Some(e); }
       let alias = |s: &str| match s {
           "MESSAGES_UPSERT" | "MESSAGE_UPSERT" => Some(Message),
           "MESSAGES_UPDATE" => Some(MessageUpdate),
           "CONNECTED" | "DISCONNECTED" | "LOGGEDOUT" | "LOGGED_OUT" | "LOGOUT"
               | "CONNECTION_UPDATE" => Some(Connection),
           "PRESENCE_UPDATE" => Some(Presence),
           "QRCODE_UPDATED" => Some(Qrcode),
           "CONTACTS_UPDATE" => Some(Contacts),
           "SEND_MESSAGE" => Some(SendMessage),
           _ => None,
       };
       alias(&up).or_else(|| alias(up.trim_end_matches('S')))
   }
   ```

2. **Normalização por evento** → tópico universal (`normalize_evolution` reescrito sobre
   `canonical_event`):
   - `Message` → `whatsapp.message.received` (payload: `instance_id`, `provider`, `raw_event`
     **íntegro** — o worker aplica `translate_go_payload`/extração de `key.id`/`remoteJid`/
     `fromMe`/`pushName`/conteúdo/mídia; D6).
   - `Connection` → `whatsapp.connection.updated` (normalizar `state` lendo
     `data.state`/`data.status`; também aceitar o evento `Connected`/`Disconnected`/`LoggedOut`
     como sinal direto de estado quando `data.state` ausente — mapear via mesma tabela de
     `map_state`).
   - `MessageUpdate` → `whatsapp.message.status`.
   - `Presence` → `whatsapp.presence.updated`.
   - `Contacts` → `whatsapp.contact.updated` *(pode ficar para 2ª iteração — declarar)*.
   - `Qrcode` / `SendMessage` → **não publica** no barramento de domínio; apenas `202`.

3. **Idempotência/dedup** — `Message` pode chegar 2× (retry do Go); a deduplicação por `key.id`
   é do **worker** (consumidor), não do ingress.

4. **Sanitização** — `body` permanece em `skip(...)`; **nunca** logar telefone/nome/conteúdo. Só
   `event`(raw)/`event_type`(canônico)/tópico/`instance_id`/`tenant_id`.

5. **Testes** — atualizar/ampliar os testes existentes (que hoje usam `messages.upsert`/
   `connection.update`) para cobrir também `MESSAGE`/`Message`/`Connection`/`PRESENCE` e o
   envelope whatsmeow (`data.Info`/`data.Message`). Garantir que `body` não vaza em logs.

### Observabilidade & Auditoria — E4
- **a) Logs/traces**: `#[tracing::instrument(skip(state, body), fields(provider, tenant_id,
  instance_id, event_type = tracing::field::Empty))]` (já no padrão); `record("event_type",
  <canônico>)`. Nível `info` no publish (`topico`, sem PII), `warn` para provedor/evento
  desconhecido, `error` em falha de parse/publish. Campos de correlação: `service=webhook_ingress`,
  `env`, `tenant_id`, `instance_id`, `trace_id` (gerado no ingress, propagado no `TenantEnvelope`).
- **b) Auditoria**: **sem evento de auditoria** (alto volume de webhooks — intencional). O estado
  de conexão é fato de domínio publicado em `events:stream`, não em `security:stream`.
- **c) Sanitização**: `body` (PII: telefone/nome/conteúdo/base64) **nunca** logado — só
  identificadores e nome do evento. `raw_event` trafega no barramento (interno), nunca em log.

## E5. Banco e repositório — validação (sem mudança de schema)

`0008_whatsapp_sync.sql` e `infrastructure_postgres/integracoes/whatsapp.rs` **já atendem**: a
tabela `whatsapp_instance` tem `provider` (sem default), `subscribed_events JSONB DEFAULT '[]'`,
`last_connection_state`, RLS+FORCE, `UNIQUE(tenant_id,name)`. A port `WhatsappStore` expõe
`criar_instancia`/`buscar_instancia`/`listar_ativas`/`admin_listar_conectadas`/
`admin_deletar_instancia`/`atualizar_estado`/`atualizar_provider_id` — **neutros de provedor**.

- **Não reescrever** migração nem repositório.
- Se o fluxo `CreateWhatsappInstance` (E3) for persistir `subscribed_events`, isso pode ser feito
  via um campo extra em `criar_instancia` **ou** via `atualizar_provider_id` estendido — preferir
  **não** alterar a port agora (gravar `subscribed_events` é opcional na 1ª entrega; a coluna tem
  default `[]`). Se for alterar SQL/queries `sqlx`, **regerar cache SQLx offline** (MEMORY
  "testes-db-tunel-e-reset"; `SQLX_OFFLINE`).

### Observabilidade & Auditoria — E5
- **a) Logs/traces**: inalterado — o repositório já usa `run_in_tenant_transaction` +
  `#[instrument(skip_all)]` nos métodos do adapter (padrão do projeto). Nada novo a adicionar.
- **b) Auditoria**: **sem evento de auditoria** neste nível (DDL/persistência pura; a auditoria de
  negócio vive em `data_whatsapp`). Declarado intencional.
- **c) Sanitização**: `api_key` é gravado encriptado e nunca logado; queries não logam valores de
  coluna sensível.

## E6. `control_plane` — endpoint admin (sem regressão)

Manter `POST /api/v2/admin/whatsapp/disconnect-all` → RPC `AdminBulkDisconnectInstances`,
enriquecendo a auditoria (`ip_address`/`user_agent`/`user_id` do `RequestContext`). Resposta
**sem tokens**. Confirmar (grep) que **nenhuma referência a endpoints v2** ou a `evolution_sync_*`
legado permanece.

### Observabilidade & Auditoria — E6
- **a) Logs/traces**: `#[instrument(skip_all, fields(rota, user_id, tenant_id))]` no handler HTTP
  do admin (padrão `control_plane`); propagar `traceparent` ao RPC.
- **b) Auditoria**: `whatsapp.admin.bulk_disconnect` em `security:stream` (`tenant_id` NULL p/
  ação global; context com `ip_address`/`user_agent`/`user_id`/`scope`, **sem token**).
- **c) Sanitização**: resposta sem tokens; logs sem credenciais.

---

# Fase V — Validation

### V1. Compilação e contratos
- `cargo build -p infrastructure_messaging -p infrastructure_evolution -p webhook_ingress -p data_whatsapp`
  (via build local; **não** rodar `cargo test` direto — ver V2).
- Regenerar cache SQLx offline **somente se** o repositório/queries forem tocados.

### V2. Testes (scripts canônicos — MEMORY "test-scripts")
- **Rust**: `.\infra\test-local.ps1` (NUNCA `cargo test` direto; o script sobe túnel SSH +
  `SQLX_OFFLINE`). Cobrir:
  - `infrastructure_messaging`: round-trip serde de `PresenceState`, `MediaDownloadResult`,
    `AdvancedSettings` (incl. `Default` → `always_online=true`/`read_messages=false`); `Display`
    dos erros.
  - `infrastructure_evolution`: **mock HTTP (wiremock 0.6)** dos endpoints **Go**:
    `/instance/create` (lê `token`), `/instance/connect` (body com `subscribe`+`webhookUrl`+
    `immediate`), `/instance/qr`, `/instance/status` (lê `state` no topo), `/instance/all`
    (`{data:[…]}`), `DELETE /instance/logout`, `POST /instance/reconnect`,
    `PUT /instance/{id}/advanced-settings`, `/send/text`, `/send/media`, `/message/markread`,
    `/message/react`, `/message/presence`, `/user/avatar`, `/message/downloadmedia`; `map_state`
    (open/connected/close/disconnected/loggedout/connecting/unknown); truncamento de body de erro
    a 200 chars; helper `send_request`.
  - `data_whatsapp`: **atualizar os mocks wiremock v2 existentes** em `tests`/`#[cfg(test)]`
    (`/instance/create` lê `token` não `hash`; `/instance/connect` em vez de `PUT /webhook/set`;
    `/instance/status` em vez de `/instance/connectionState`; `/send/text` em vez de
    `/message/sendText`; `/send/media` em vez de `/message/sendMedia`; `DELETE /instance/logout`
    em vez de `POST /instance/logout/{name}`). Cobrir fluxo de `create` com
    `connect_with_webhook`+webhook e os novos RPCs (`markread`/`react`/`presence`/`download`/
    `profile`) com `data_postgres` mockado (padrão `setup_test_env` já existe).
  - `webhook_ingress`: `canonical_event` para UPPERCASE (`MESSAGE`), PascalCase (`Message`,
    `QRCode`), aliases v2 (`messages.upsert`, `connection.update`) e Go
    (`Connected`/`Disconnected`/`LoggedOut`); normalização de `Message`/`Connection`/`Presence`
    (incl. envelope whatsmeow `data.Info`); garantia de que `body` não vaza em logs; `Qrcode`/
    `SendMessage` → `202` sem publish.
- **Flutter** (se algum client for tocado): `.\infra\test-flutter.ps1` (NUNCA `flutter test`
  direto).

### V3. Validação manual (stack Docker, Evolution Go já rodando)
- Subir a stack (Evolution Go isolado em projeto compose próprio + rede external — MEMORY
  "deploy-evolution-remove-orphans"). `data_whatsapp` com `SMARTCORE_*_ENDPOINT=tcp://` em
  Windows (MEMORY "transport-windows-tcp").
- Criar instância via `data_whatsapp`; confirmar **`POST /instance/connect`** com `subscribe`
  (UPPERCASE) e `webhookUrl` corretos (e que a Global Key **não** é usada aqui — evitar 401);
  escanear QR (`/instance/qr`); enviar texto (`/send/text`); verificar
  `whatsapp.message.received` em `events:stream`. Verificar `Connection` →
  `whatsapp.connection.updated`. Testar `markread`/`react`/`presence`/`profile`.
- **Confirmar o campo `base64` do `/message/downloadmedia`** (armadilha #8 — incerto entre
  `base64` e `media`): enviar mídia grande sem base64 inline, chamar `DownloadWhatsappMedia` com
  o sub-objeto whatsmeow, inspecionar a chave real da resposta e **fixar** o parse em E2 (remover
  o fallback defensivo se confirmado `base64`).

### V4. Observabilidade/auditoria
- Logs **sem** `apikey`/`instance_token`/body de webhook/telefone/conteúdo/base64.
- `audit_log` com `whatsapp.instance.create`/`delete`/`admin.bulk_disconnect`, `context` sem
  segredos, `tenant_id` NULL quando ação global.
- Spans com campos de correlação (`service`/`env`/`tenant_id`/`trace_id`/`error_code`).

---

# Fase C — Confirmation

### C1. Critérios de pronto
- Build e testes (V1–V2) verdes via scripts canônicos.
- Integração manual (V3) e auditoria (V4) confirmadas contra o Evolution Go real (incl. campo
  `base64` do download fixado).
- **Grep limpo**: nenhuma referência remanescente a `/message/sendText`, `/message/sendMedia`,
  `/webhook/set`, `/instance/connectionState`, `/instance/fetchInstances`,
  `/instance/logout/{name}` (com nome), `integration:WHATSAPP-BAILEYS`, `hash` (como token), ou
  a `evolution_sync_*` legado.

### C2. Gate de final-review
- Rodar `prevc-final-review` (subagente Opus): compara implementado × este plano, corrige
  desvios, arquiva e commita. **Sem auto-referência** nos commits (MEMORY
  "git-no-self-reference"); branches **gitflow** (MEMORY "use-gitflow"); comentários de código em
  **pt-br** (MEMORY "code-comments-portuguese").

### C3. Documentação
- Arquivar os planos-base v2 referenciando este consolidado v3.
- Atualizar `doc_dev/libs/` se aplicável (contrato Evolution Go real; axum 0.8 já documentado).

---

# Correções aplicadas (vs. planos-base v2)

| # | O que mudou | Por quê | Fonte |
| --- | --- | --- | --- |
| 1 | **Alvo: Evolution v2 → Evolution Go** em todo o contrato REST e nomes de evento. | O servidor que está rodando é o Go (whatsmeow); o código v2 dava 503/401/404. | `evolution_go_adapter.py`, info_aux |
| 2 | **"Criar do zero" → "realinhar o existente".** | Migração `0008`, repositório, ports/adapters e scaffolding das crates/apps **já existem** no repo. | Leitura de `lib.rs`/`provider.rs`/`main.rs`/`whatsapp.rs`/`0008_*.sql` |
| 3 | **Helper `send_request` central** no `EvolutionProvider`. | Elimina repetição de header/erro em cada método; espelha `_send_request` do adapter. | `client.rs` atual + `evolution_go_adapter.py` |
| 4 | **`create_instance` lê `token`** (não `hash`); body `{name, token?}` (sem `integration`/`qrcode`). | Contrato Go. | `evolution_go_adapter.create_instance` |
| 5 | **Webhook embutido no `POST /instance/connect`** (`webhookUrl`+`subscribe`+`immediate`); **remoção do `PUT /webhook/set`**. | Go não tem `/webhook/set`; o connect carrega o webhook. | `connect_instance`, armadilha #2 |
| 6 | **`connect` exige TOKEN da instância** (não global key). | Global Key dá 401 "not authorized" no connect do Go. | Nota inline do adapter, armadilha #1 |
| 7 | **Campo `subscribe` (UPPERCASE)**, não `events`. | Nome inválido zera a assinatura e para os webhooks. Código real do adapter usa `subscribe` (vence o próprio docstring contraditório). | `connect_instance` (cód.), info_aux |
| 8 | **Estado via `GET /instance/status`** (lê `state` no topo), não `/instance/connectionState`. | v2 retorna 503 no Go; struct de resposta diferente. | `get_status`, armadilha #3 |
| 9 | **`get_connection_state`/`disconnect_instance` ganham `instance_token`.** | Go exige token da instância nesses endpoints; usar a global key falharia. | `get_status`/`logout_instance` |
| 10 | **Envio via `/send/text` e `/send/media`** com `type`/`url`/`caption`/`filename`. | Paths/campos v2 (`/message/sendText`, `media`/`mediatype`) não existem no Go. | `send_text`/`send_media`, armadilha #4 |
| 11 | **`DELETE /instance/logout`** (sem nome no path) para desconectar. | Contrato Go (logout único, token da instância). | `logout_instance`, armadilha #5 |
| 12 | **`list_all_instances` via `GET /instance/all`** (`{data:[…]}`/`[…]`). | Go não tem `/instance/fetchInstances`. | `fetch_instances` |
| 13 | **Superfície completa adicionada**: `reconnect_instance`, `set_advanced_settings`, `mark_read`, `send_reaction`, `set_presence`, `get_profile_picture`, `download_media`. | Recursos nativos do Go fora do escopo v2. | métodos homônimos do adapter |
| 14 | **`AdvancedSettings::default()` = `always_online:true`, `read_messages:false`.** | `alwaysOnline` mantém a sessão whatsmeow viva; recibo de leitura deve ser explícito via `markread`. | `set_advanced_settings`, armadilhas #6/#7 |
| 15 | **Canonização de eventos no ingress** (`canonical_event` espelhando `from_raw`): UPPERCASE/PascalCase/aliases v2 e Go. | O ingress atual só reconhecia `messages.upsert`/`connection.update`; eventos Go caíam em `None` e mensagens inbound se perdiam. | `EvolutionEventName.from_raw` (`schemas.py`) |
| 16 | **`raw_event` íntegro repassado ao worker** (extração profunda/`translate_go_payload` no consumidor). | O Go tem 2 formatos de envelope (whatsmeow `data.Info` vs Node-like); centralizar a conversão no worker mantém o ingress simples e sem PII. | `translate_go_payload`/`WebhookProcessor` (old) |
| 17 | **`download_media`: campo `base64` com fallback `media` + validação obrigatória em V3.** | Adapter diz `base64`; subagente web diz `media` — conflito não resolvido sem o servidor real. | armadilha #8, conflitos do info_aux |
| 18 | **Sem mudança de schema**; `subscribed_events`/`last_connection_state` já existem. | Migração `0008` já é genérica e multi-provedor. | `0008_whatsapp_sync.sql` |
