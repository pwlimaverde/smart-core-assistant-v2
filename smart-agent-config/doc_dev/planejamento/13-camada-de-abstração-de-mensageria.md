# Plano Consolidado: Módulo Rust de Mensageria WhatsApp (Evolution Go)

> Documento único consolidado. **Substituiu** os dois planos-base v2 que existiam antes
> (`-2.md` e a versão original deste arquivo), que assumiam
> *greenfield* + **Evolution API v2 (Baileys)**. A realidade é outra: o scaffolding já existe
> no repositório **e** o servidor que está rodando é o **Evolution Go (whatsmeow)**, cujo
> contrato REST e cujos eventos divergem do v2. Este documento é a **única fonte de verdade
> técnica** e realinha a camada Rust ao Evolution Go, com a **superfície completa** de recursos
> (envio, gestão, presença, reações, recibo de leitura, download de mídia, advanced-settings).
>
> Estilo de referência: o `evolution_sync` do `old/` (adapter `evolution_go_adapter.py`).
> Organização em fases **PREVC** (Planning, Review, Execution, Validation, Confirmation).

---

## Objetivo

Estruturar o **módulo Rust único responsável por toda a comunicação com o Evolution Go**:
criação/gestão de instâncias, conexão/QR, envio de mensagens e mídia, recursos de sessão
(presença, leitura, reações) e ingestão normalizada de webhooks. As regras de negócio dos
tenants nunca falam com o Evolution diretamente — só com este módulo, através de contratos
em Rust (`MessagingProvider`) e eventos universais no barramento Redis Streams.

### Premissas
1. **Provedor único hoje = Evolution Go.** A abstração `MessagingProvider` permanece, mas a
   implementação concreta (`EvolutionProvider`) passa a falar o contrato **Go**, não o v2.
2. **Normalização no ingress.** O `webhook_ingress` recebe webhooks proprietários do Go
   (eventos UPPERCASE/PascalCase) e publica eventos universais (`whatsapp.message.received`,
   `whatsapp.connection.updated`, …) no barramento. O resto do sistema só consome eventos
   normalizados.
3. **Banco genérico, multi-provedor.** Tabelas `whatsapp_*` com coluna `provider` sem default
   acoplado. **Já implementado** (ver Reconciliação).
4. **Segredos sempre `SecretString`.** `global_api_key` e `instance_token` jamais em logs ou
   respostas; `api_key` encriptado em repouso.

---

## ⚠️ Reconciliação com o repositório real (pré-condição da execução)

O ponto central da consolidação: **boa parte do plano-base v2 já foi implementada**, e a
divergência relevante restante é **v2 → Go**, não "criar do zero".

### Já implementado e correto (não mexer, apenas validar)
| Componente | Caminho | Situação |
| --- | --- | --- |
| Migração genérica | `server/crates/infrastructure_postgres/migrations/0008_whatsapp_sync.sql` | ✅ `whatsapp_instance/contact/whitelist`, RLS+FORCE, `provider` sem default. Já sem `UNIQUE(name)` global. |
| Repositório WhatsApp | `infrastructure_postgres/src/integracoes/whatsapp.rs` + `whitelist.rs` | ✅ Neutro de provedor; serve ao Go sem alteração. |
| Port/Adapter no data_postgres | `data_postgres/src/ports/whatsapp.rs`, `src/adapters/whatsapp.rs` | ✅ `WhatsappStore` (criar/buscar/listar/admin/estado/provider_id), RLS + admin BYPASSRLS. |
| Crate de contrato | `server/crates/infrastructure_messaging` | ⚠️ Existe; **trait precisa ampliar** (ver E1). |
| Crate Evolution | `server/crates/infrastructure_evolution` | ⚠️ Existe; **fala v2, precisa realinhar ao Go** (ver E2). |
| App orquestrador | `server/apps/data_whatsapp` | ⚠️ Existe; RPCs implementados em cima da trait v2 — **realinhar + ampliar** (ver E3). |
| App ingress | `server/apps/webhook_ingress` | ⚠️ Existe; **só trata eventos v2 lowercase** — realinhar para eventos Go (ver E4). |

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
> 3. `readMessages` em advanced-settings deve ficar **`false`** — recibo de leitura é explícito
>    (via `markread`), nunca automático.
> 4. `alwaysOnline:true` é o mecanismo documentado para manter a sessão whatsmeow viva.

Apps existentes (confirmados): `control_plane`, `data_postgres`, `data_redis`, `data_storage`,
`data_whatsapp`, `webhook_ingress`, `messaging_gateway`, `runtime_api`, `worker`.
Crates existentes (confirmados): `application`, `contracts`, `error_core`, `infrastructure_messaging`,
`infrastructure_evolution`, `infrastructure_postgres`, `infrastructure_redis`, `infrastructure_storage`,
`observability`, `test_support`, `transport`.

---

## Decisões de Design

### D1. Duas crates de abstração (mantidas)
- **`infrastructure_messaging`**: trait `MessagingProvider`, enums normalizados
  (`ConnectionState`, `MediaType`, `PresenceState`), structs de payload e
  `MessagingProviderError`. Pura: sem runtime, sem I/O, sem logs.
- **`infrastructure_evolution`**: implementa `MessagingProvider` via HTTP REST (reqwest) contra
  o **Evolution Go**.

### D2. `EvolutionProvider` com base_url + duas credenciais
A struct carrega `global_api_key` (criar/deletar/listar) e recebe `instance_token` por chamada
(conectar/QR/status/enviar/sessão). Um helper interno `send_request(method, path, apikey, body)`
espelha o `_send_request` do adapter Go, centralizando header `apikey`, `Content-Type` e o
tratamento de erro (`ok_or_api`, body truncado a 200 chars).

### D3. Roteamento dinâmico em `data_whatsapp`
Ao receber um RPC, o app: (1) resolve o `provider` da instância no banco (via `data_postgres`);
(2) delega à struct que implementa `MessagingProvider` (hoje só `EvolutionProvider`). Como há um
único provedor, a factory pode ser trivial agora, mas a fronteira fica pronta para um segundo.

### D4. Webhook com detecção de provedor via path (axum 0.8) + canonização de eventos
URL configurada no `POST /instance/connect` do Go:
```
http://webhook_ingress:9200/webhook/{provider}/{tenant_id}/{instance_id}
```
O ingress extrai `provider`/`tenant_id`/`instance_id` do path, **canoniza o nome do evento**
(UPPERCASE/PascalCase/aliases v2 → enum canônico, espelhando `EvolutionEventName.from_raw`),
normaliza o payload e publica em `events:stream`. `webhookByEvents=false` conceitual: todos os
eventos chegam na mesma URL; o ingress discrimina pelo campo `event`.

### D5. Desconexão em massa pelo admin
RPC `AdminBulkDisconnectInstances` em `data_whatsapp` (já existe): `tenant_id: Option<Uuid>`;
`None` ⇒ todas as instâncias de todos os tenants (BYPASSRLS via `AdminListAllConnectedInstances`,
exige escopo `operacional:admin`). Atualiza `connection_state='disconnected'`.

---

# Fase P — Planning (output)

**Status: concluída.**

- **Escopo**: realinhamento de 4 componentes Rust ao Evolution Go + ampliação de superfície.
  Nenhuma criação de crate/app nova; nenhuma mudança de schema (DB pronto).
- **Contrato central**: `MessagingProvider` ampliado para a superfície completa do Go.
- **Eventos normalizados** publicados em `events:stream`:
  - `whatsapp.message.received` (de `Message`)
  - `whatsapp.connection.updated` (de `Connection`)
  - `whatsapp.message.status` (de `MessageUpdate`)
  - `whatsapp.presence.updated` (de `Presence`)
  - `whatsapp.contact.updated` (de `Contacts`) *(opcional na 1ª entrega)*
- **Auditoria** em `security:stream` → `data_postgres` → `audit_log`:
  `whatsapp.instance.create`, `whatsapp.instance.delete`, `whatsapp.admin.bulk_disconnect`.
- **Mapa de risco**: contrato Go indocumentado em alguns pontos (mitigado pelo adapter de
  referência do old); `subscribe` inválido zera webhooks; dois `axum` coexistem (0.7.5 no
  `runtime_api`, 0.8 no `webhook_ingress`) — **não unificar** via workspace.

---

# Fase R — Review (arquitetura e contratos)

### R1. Compatibilidade de versões
- `runtime_api` permanece em **axum 0.7.5**; `webhook_ingress` usa **axum 0.8** declarado
  **localmente** no `Cargo.toml` do app (já está assim). NÃO adicionar `axum` ao workspace.
- `reqwest 0.12` (feature `json`) em `infrastructure_evolution` (já está).
- Reuso obrigatório: `async-trait`, `serde`, `serde_json`, `secrecy`, `thiserror`, `uuid`,
  `tracing`, `redis`, `contracts`, `transport`, `error_core`, `observability`.

### R2. Sanidade de segurança
- `global_api_key`/`instance_token` sempre `SecretString`; sempre em `skip(...)` do `instrument`.
- `api_key` no banco encriptado (mesma política das demais credenciais de tenant).
- RLS+FORCE em todas as `whatsapp_*`; bypass cross-tenant só por `admin_pool`/transação admin
  explícita, sob escopo `operacional:admin`.
- Body de erro do provedor truncado a 200 chars (evita vazar telefone/conteúdo).

### R3. Contrato de barramento
- Reaproveitar `contracts::TenantEnvelope<T>` + `transport::bus::publicar_evento` /
  `publicar_evento_seguranca` (já em uso no `webhook_ingress` e `data_whatsapp`). Não inventar
  stream key.

**Gate R**: aprovado se R1/R2/R3 confirmados. Saída → Execution.

---

# Fase E — Execution (detalhe técnico)

## E1. `infrastructure_messaging` — ampliar o contrato

Manter os 12 métodos atuais e **acrescentar** a superfície Go. Adicionar enums/structs neutros.

```rust
// Novos tipos neutros
#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PresenceState { Composing, Paused, Recording }

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MediaDownloadResult { pub base64: String, pub mime_type: Option<String> }
```

Novos métodos no trait `MessagingProvider` (todos `async`, erro `MessagingProviderError`):
```rust
async fn reconnect_instance(&self, instance_name: &str, instance_token: &SecretString) -> Result<(), _>;
async fn set_advanced_settings(&self, instance_id: &str, instance_token: &SecretString, settings: AdvancedSettings) -> Result<(), _>;
async fn mark_read(&self, instance_name: &str, instance_token: &SecretString, chat: &str, message_ids: &[String]) -> Result<(), _>;
async fn send_reaction(&self, instance_name: &str, instance_token: &SecretString, chat: &str, message_id: &str, emoji: &str, from_me: bool) -> Result<SendMessageResult, _>;
async fn set_presence(&self, instance_name: &str, instance_token: &SecretString, chat: &str, state: PresenceState, is_audio: bool) -> Result<(), _>;
async fn get_profile_picture(&self, instance_name: &str, instance_token: &SecretString, number: &str) -> Result<Option<String>, _>;
async fn download_media(&self, instance_name: &str, instance_token: &SecretString, message: &serde_json::Value) -> Result<MediaDownloadResult, _>;
```
- `AdvancedSettings`: struct com `always_online: bool`, `read_messages: bool` (default `false`),
  `reject_call`, `msg_reject_call`, `ignore_groups`, `ignore_status`.
- **Compatibilidade**: `configure_webhook` permanece no trait (assinatura neutra), mas no Go a
  implementação será dobrada dentro do `connect_instance` (ver E2 — D4/D2). Decisão de R:
  manter o método por compatibilidade do contrato; documentar que no Go ele é no-op explícito
  ou delega a um `connect` idempotente.

**Observabilidade/Auditoria E1**: crate pura — sem logs, sem auditoria. `SecretString` nas
assinaturas; `Debug` redige segredo.

## E2. `infrastructure_evolution` — realinhar `provider.rs` ao Go

Reescrever cada método de `provider.rs` para o contrato Go, reusando um helper único
`send_request`. Tabela canônica de endpoints (substitui a lista v2):

| Método trait | HTTP Go | Header `apikey` | Body / parse |
| --- | --- | --- | --- |
| `create_instance` | `POST /instance/create` | global | `{name, token?}` → `token` (e `id`/`name`) |
| `delete_instance` | `DELETE /instance/delete/{name}` | global | — |
| `connect_instance` | `POST /instance/connect` | **instância** | `{instanceName, webhookUrl, subscribe:[…], immediate:true}` |
| `get_qr_code` | `GET /instance/qr` | instância | `base64`/`code` |
| `get_connection_state` | `GET /instance/status` | instância | `{state}` → `map_state` |
| `disconnect_instance` | `DELETE /instance/logout` | instância | — |
| `reconnect_instance` | `POST /instance/reconnect` | instância | — |
| `list_all_instances` | `GET /instance/all` | global | `{data:[{name}]}` |
| `send_text` | `POST /send/text` | instância | `{number, text, quoted?}` → `key.id`/`id` |
| `send_media` | `POST /send/media` | instância | `{number, type, url, caption, filename}` → id |
| `set_advanced_settings` | `PUT /instance/{id}/advanced-settings` | instância | flags |
| `mark_read` | `POST /message/markread` | instância | `{number, id:[…]}` |
| `send_reaction` | `POST /message/react` | instância | `{number, reaction, id, fromMe}` |
| `set_presence` | `POST /message/presence` | instância | `{number, state, isAudio}` |
| `get_profile_picture` | `POST /user/avatar` | instância | `{number, preview:false}` → `profilePictureUrl`/`url` |
| `download_media` | `POST /message/downloadmedia` | instância | `{message}` → `base64`/`mimetype` |

- **`map_state`**: aceitar variações do Go — `open`/`connected`→Connected, `close`/`disconnected`/`loggedOut`→Disconnected, `connecting`→Connecting, resto→Unknown.
- **`configure_webhook`**: no Go não há `/webhook/set`; a configuração ocorre no
  `connect_instance`. Implementar como delegação a `connect_instance` (idempotente) ou no-op
  documentado. **A URL do webhook e o `subscribe` passam a ser responsabilidade do fluxo de
  conexão** (ver E3, `CreateWhatsappInstance`).
- **`client.rs`**: ajustar structs de desserialização (`CreateInstanceResp` lê `token`/`id`;
  `ConnStateResp` lê `state` no topo, não em `instance.state`). Helper `send_request` central.

**Observabilidade/Auditoria E2**: `#[tracing::instrument(err, skip(self, instance_token, …))]`
em cada método; fields `provider="evolution"`, `instance_name`. Sem evento de auditoria (infra).
Body de erro truncado; nunca logar `apikey`.

## E3. `data_whatsapp` — realinhar fluxo + novos RPCs

O `main.rs` já tem o esqueleto RPC e o padrão (`chamar_data_postgres`, `erro`, `ok_reply`,
auditoria via `publicar_evento_seguranca`). Ajustes:

1. **`CreateWhatsappInstance`** — após criar a instância e persistir o registro, **conectar via
   `connect_instance`** passando a `webhook_url`
   (`http://webhook_ingress:9200/webhook/evolution/{tenant_id}/{db_id}`) e `subscribe`
   (`["MESSAGE","CONNECTION","PRESENCE","QRCODE"]`). Remover a chamada separada a
   `configure_webhook`/`PUT /webhook/set`. Manter o rollback (delete no provedor + remoção do
   registro) se a conexão falhar. Opcional: `set_advanced_settings(always_online:true,
   read_messages:false)` logo após conectar.
2. **`GetWhatsappInstanceStatus`** — usar `/instance/status`; quando desconectado/unknown, obter
   QR via `/instance/qr`.
3. **`SendWhatsappMessage` / `SendWhatsappMedia`** — já delegam à trait; passam a usar `/send/*`
   automaticamente após E2. `media_type:audio` → PTT.
4. **Novos RPCs** (superfície completa), no mesmo padrão dos handlers atuais:
   - `MarkWhatsappMessageRead` → `mark_read`
   - `SendWhatsappReaction` → `send_reaction`
   - `SetWhatsappPresence` → `set_presence`
   - `GetWhatsappProfilePicture` → `get_profile_picture`
   - `DownloadWhatsappMedia` → `download_media` (usado pelo `worker` no fallback de mídia grande)
   - `ReconnectWhatsappInstance` → trocar para `reconnect_instance` (hoje usa `connect`)
5. **Auditoria** — manter `whatsapp.instance.create/delete` e `whatsapp.admin.bulk_disconnect`
   (já implementados). Recursos de mensagem (react/markread/presence) **não** geram auditoria
   (alto volume; intencional).

**Observabilidade/Auditoria E3**: `#[instrument(skip_all, fields(rpc, tenant_id))]` por handler
(já no padrão); `instance_token` como `SecretString`; auditoria sem token.

## E4. `webhook_ingress` — canonizar eventos do Go

O `main.rs`/`normalize_evolution` atual só reconhece `messages.upsert`/`connection.update`.
Ajustar:

1. **Canonização de evento** — função `canonical_event(raw: &str) -> Option<CanonicalEvent>`
   espelhando `EvolutionEventName.from_raw`: aceita UPPERCASE (`MESSAGE`), PascalCase
   (`Message`, `QRCode`), e aliases v2 (`messages.upsert`, `connection.update`, …). Mapear para
   enum `{ Message, MessageUpdate, Connection, Presence, Qrcode, Contacts }`.
2. **Normalização por evento** → tópico universal:
   - `Message` → `whatsapp.message.received` (payload com `instance_id`, `provider`, `raw_event`;
     o worker extrai `key.id`/`remoteJid`/`fromMe`/`pushName`/conteúdo).
   - `Connection` → `whatsapp.connection.updated` (mapear `state` open/close/connecting/loggedOut).
   - `MessageUpdate` → `whatsapp.message.status`.
   - `Presence` → `whatsapp.presence.updated`.
   - `Contacts` → `whatsapp.contact.updated` *(pode ficar para 2ª iteração)*.
   - `Qrcode` → não publica no barramento de domínio (QR é fluxo de UI via `GetStatus`); apenas
     `202`.
3. **Idempotência/dedup** — `Message` pode chegar 2×; a deduplicação por `key.id` é do **worker**
   (consumidor), não do ingress.
4. **Sanitização** — `body` permanece em `skip(...)`; nunca logar telefone/nome/conteúdo. Só
   `event`/tópico/identificadores.

**Observabilidade/Auditoria E4**: `#[instrument(skip(state, body), fields(provider, tenant_id,
instance_id, event_type))]`. Sem auditoria (volume alto). `info` no publish, `warn` para
provedor/evento desconhecido.

## E5. Banco e repositório — validação (sem mudança)

`0008_whatsapp_sync.sql` e `infrastructure_postgres/integracoes/whatsapp.rs` já atendem.
**Não reescrever.** Apenas, se algum novo handler RPC exigir coluna ainda não persistida (ex.:
`last_connection_state`/`subscribed_events`), estender o repositório de forma incremental.
Após qualquer alteração SQL, **regerar cache SQLx offline** (MEMORY "testes-db-tunel-e-reset").

## E6. `control_plane` — endpoint admin (sem regressão)

Manter `POST /api/v2/admin/whatsapp/disconnect-all` → RPC `AdminBulkDisconnectInstances`,
enriquecendo a auditoria (`ip_address`/`user_agent`/`user_id` do `RequestContext`). Resposta
**sem tokens**. Confirmar que nenhuma referência a `evolution_sync_*` legado permanece (grep
limpo).

---

## Arquitetura (visão consolidada)

```
control_plane / worker ──RPC──▶ data_whatsapp ──(MessagingProvider)──▶ infrastructure_evolution ──HTTP──▶ Evolution Go
        │                            │
        │ (auditoria)                └──RPC──▶ data_postgres (whatsapp_* + audit_log)
        ▼
   security:stream ───────────────▶ data_postgres ─▶ audit_log

Evolution Go ──webhook POST──▶ webhook_ingress ──canoniza+normaliza──▶ events:stream ──▶ worker/messaging_gateway

Stacks Docker:
  - principal: control_plane, data_whatsapp, webhook_ingress, data_postgres, worker, …
  - Evolution Go isolada: container `evolution` (evoapicloud/evolution-go) + postgres próprio
  - rede external compartilhada entre as stacks
```

---

# Fase V — Validation

### V1. Compilação e contratos
- `cargo build -p infrastructure_messaging -p infrastructure_evolution -p webhook_ingress -p data_whatsapp`.
- Regenerar cache SQLx offline se o repositório for tocado.

### V2. Testes (scripts canônicos — MEMORY "test-scripts")
- **Rust**: `.\infra\test-local.ps1` (NUNCA `cargo test` direto). Cobrir:
  - `infrastructure_messaging`: round-trip serde dos enums novos; `Display` de erro.
  - `infrastructure_evolution`: **mock HTTP (wiremock)** dos endpoints Go reais — `/instance/create`
    (lê `token`), `/instance/connect` (body com `subscribe`/`webhookUrl`), `/instance/status`,
    `/instance/all`, `/send/text`, `/send/media`, `/message/markread`, `/message/react`,
    `/message/presence`, `/user/avatar`, `/message/downloadmedia`, `DELETE /instance/logout`;
    `map_state`; truncamento de body de erro a 200 chars. **Atualizar os mocks v2 existentes**
    em `data_whatsapp/tests` e `infrastructure_evolution/tests` para os paths Go.
  - `data_whatsapp`: handlers com `data_postgres` mockado (já há padrão wiremock); fluxo de
    create com `connect_instance`+webhook; novos RPCs.
  - `webhook_ingress`: `canonical_event` para UPPERCASE/PascalCase/aliases; normalização de
    `Message`/`Connection`/`Presence`; garantia de que `body` não vaza em logs.
- **Flutter** (se algum client for tocado): `.\infra\test-flutter.ps1`.

### V3. Validação manual (stack Docker, Evolution Go já rodando)
- Criar instância via `data_whatsapp`; confirmar `POST /instance/connect` com `subscribe` e
  `webhookUrl` corretos; escanear QR (`/instance/qr`); enviar texto (`/send/text`); verificar
  `whatsapp.message.received` em `events:stream`. Verificar `Connection` →
  `whatsapp.connection.updated`. Testar `markread`/`react`/`presence`.

### V4. Observabilidade/auditoria
- Logs **sem** `apikey`/`instance_token`/body de webhook/telefone/conteúdo.
- `audit_log` com create/delete/bulk_disconnect, `context` sem segredos, `tenant_id` NULL quando
  ação global.

---

# Fase C — Confirmation

### C1. Critérios de pronto
- Build e testes (V1–V2) verdes via scripts canônicos.
- Integração manual (V3) e auditoria (V4) confirmadas contra o Evolution Go real.
- Nenhuma referência a endpoints v2 (`/message/sendText`, `/webhook/set`,
  `/instance/connectionState`, `/instance/fetchInstances`) remanescente (grep limpo).

### C2. Gate de final-review
- Rodar `prevc-final-review` (subagente Opus): compara implementado × este plano, corrige
  desvios, arquiva e commita. Sem auto-referência nos commits (MEMORY "git-no-self-reference");
  branches gitflow (MEMORY "use-gitflow").

### C3. Documentação
- Arquivar os dois planos-base v2 (`13-...md`, `13-...-2.md`) referenciando este consolidado.
- Se aplicável, atualizar `doc_dev/libs/` (Evolution Go, axum 0.8) com o contrato real.

---

# Resumo das mudanças vs. planos-base

1. **Alvo corrigido: Evolution v2 → Evolution Go.** Todo o contrato REST e os nomes de eventos
   foram realinhados ao servidor que está rodando (referência: `evolution_go_adapter.py` do old).
2. **De "criar do zero" → "realinhar o existente".** Migração, repositório, ports/adapters e o
   scaffolding das crates/apps **já existem**; o trabalho é realinhamento + ampliação, não
   bootstrap.
3. **Superfície completa do Go** adicionada ao contrato e ao `data_whatsapp`: `markread`,
   `react`, `presence`, `download_media`, `advanced-settings` (`alwaysOnline`), `reconnect`,
   `profile picture`.
4. **Webhook unificado no connect** (Go não tem `/webhook/set`); `subscribe` UPPERCASE
   obrigatório; canonização de eventos no ingress.
5. **Sem mudança de schema**: `0008_whatsapp_sync.sql` mantido.
