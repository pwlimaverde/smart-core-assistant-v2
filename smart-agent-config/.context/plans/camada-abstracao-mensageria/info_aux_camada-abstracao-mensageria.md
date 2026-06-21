# Documentação Auxiliar — Camada de Abstração de Mensageria (WhatsApp)

> Gerado em: 2026-06-20
> Plano canônico: `.context/plans/camada-abstracao-mensageria.md`
> Plano completo: `.context/plans/camada-abstracao-mensageria/plano_completo_camada-abstracao-mensageria.md`

---

## Grupo A — Libs Rust (USAR LOCAL)

As libs abaixo têm documentação local válida e atualizada. Versões extraídas do `server/Cargo.toml` (workspace).

| Lib | Versão | Status | Doc Local |
|-----|--------|--------|-----------|
| `async-trait` | 0.1.83 | ✅ USAR LOCAL | `doc_dev/libs/rust/async_trait.md` (verificado 2026-06-01) |
| `reqwest` | 0.12.4 | ✅ USAR LOCAL | `doc_dev/libs/rust/reqwest.md` (verificado 2026-05-31) |
| `redis` | 0.25.0 | ✅ USAR LOCAL | `doc_dev/libs/rust/redis.md` (verificado 2026-06-10) |
| `secrecy` | 0.10.3 | ✅ USAR LOCAL | `doc_dev/libs/rust/secrecy.md` (verificado 2026-06-01) |
| `tracing` | 0.1.40 | ✅ USAR LOCAL | `doc_dev/libs/rust/tracing.md` (verificado 2026-05-31) |
| `serde`/`serde_json` | 1.0 | ✅ USAR LOCAL | `doc_dev/libs/rust/serde.md` |
| `tokio` | 1.38 | ✅ USAR LOCAL | `doc_dev/libs/rust/tokio.md` |
| `uuid` | 1.0 | ✅ USAR LOCAL | `doc_dev/libs/rust/uuid.md` |
| `thiserror` | 1.0 | ✅ USAR LOCAL | `doc_dev/libs/rust/thiserror_anyhow.md` |

### Destaques dos docs locais

#### `async-trait` (0.1.83) — `doc_dev/libs/rust/async_trait.md`
Permite `async fn` em traits (`dyn Trait`). O plano usa `#[async_trait]` na trait `MessagingProvider`. Padrão:
```toml
async-trait = "0.1.83"
```
```rust
#[async_trait]
pub trait MessagingProvider: Send + Sync {
    async fn create_instance(&self, ...) -> Result<...>;
}
```

#### `reqwest` (0.12.4) — `doc_dev/libs/rust/reqwest.md`
Já documentado especificamente para o `EvolutionClient` / `infrastructure_evolution`. Padrões-chave:
- Instanciar **um único** `reqwest::Client` com pool; compartilhar via `Arc` ou clone barato.
- `.error_for_status()` para propagar falhas HTTP de forma idiomática.
- Header `apikey: {token}` — global token para operações de instância, instance token para mensagens.

#### `secrecy` (0.10.3) — `doc_dev/libs/rust/secrecy.md`
- Campos de chave de API e tokens de instância devem ser `SecretString`.
- `Debug` imprime `[REDACTED]`; memória zerada no `Drop`.
- Expor valor apenas dentro de `expose_secret()` — nunca logar.

#### `redis` (0.25.0) — `doc_dev/libs/rust/redis.md`
- O `webhook_ingress` publica eventos normalizados em Redis Streams.
- Stream key padrão do projeto: `smart_core:events:{topic}`.
- Usar `connection-manager` feature para reconexão automática.

#### `tracing` (0.1.40) — `doc_dev/libs/rust/tracing.md`
- Política de instrumentação da infra: `#[tracing::instrument(err)]` apenas onde todo erro é falha real de infra.
- Repositórios de tenant via `run_in_tenant_transaction` + `#[instrument(skip_all)]`.
- Campos de correlação obrigatórios: `service`, `env`, `tenant_id`, `trace_id`, `error_code`.

---

## Grupo A — Libs Rust (ATUALIZADO via Context7)

### `axum` — ATUALIZADO de 0.7.5 → 0.8 (doc atualizado em `doc_dev/libs/rust/axum.md`)

**Contexto:** O `runtime_api` existente usa `axum 0.7.5`. O novo `webhook_ingress` usa `axum 0.8`. São apps separados, sem conflito.

**Library ID Context7:** `/tokio-rs/axum/axum_v0_8_4`

#### Breaking changes críticos (0.7 → 0.8):

| Recurso | 0.7 | 0.8 |
|---------|-----|-----|
| Estado compartilhado | `Extension<T>` | `State<T>` (Extension **removido**) |
| Parâmetro de path | `:param` | `{param}` (`:param` dá **panic**) |
| Iniciar servidor | `Server::bind().serve()` | `axum::serve(listener, app)` |
| `.with_state()` | opcional | **obrigatório** |

#### Padrão correto para `webhook_ingress` (0.8):
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
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub redis: Arc<redis::Client>,
}

#[derive(Deserialize)]
struct WebhookPath {
    provider: String,
    tenant_id: uuid::Uuid,
    instance_id: i32,
}

async fn handle_webhook(
    Path(params): Path<WebhookPath>,
    State(state): State<AppState>,
    body: Bytes,
) -> Result<impl IntoResponse, StatusCode> {
    // parseia body bruto baseado em params.provider
    Ok(StatusCode::ACCEPTED)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let app = Router::new()
        .route("/webhook/{provider}/{tenant_id}/{instance_id}", post(handle_webhook))
        .with_state(AppState { redis: Arc::new(client) });

    let listener = tokio::net::TcpListener::bind("0.0.0.0:9200").await?;
    axum::serve(listener, app).await?;
    Ok(())
}
```

**Cargo.toml do `webhook_ingress`:**
```toml
axum = "0.8"
```
> Nota: `axum 0.8` NÃO deve ser adicionado ao workspace — cada app declara sua própria versão.

---

## Grupo B — Serviços Externos

### Evolution API (Evolution Go)

> Doc completa: `doc_dev/apis/evolution/evolution-api-documentation.md`
> Referência rápida: `doc_dev/apis/evolution/evolution-api-quick-reference.md`
> Guia de implementação: `doc_dev/apis/evolution/evolution-api-implementation-guide.md`
> Setup local: `doc_dev/apis/evolution/evolution-api-local-setup.md`

**Repositório oficial:** https://github.com/evolution-foundation/evolution-api
**Stack:** Node.js 20+ / TypeScript 5+ (versão TS) ou Go 1.24+ / Gin (versão Go)
**Licença:** Apache 2.0
**Porta padrão:** 3000 (configurável)
**Docker image:** `evoapicloud/evolution-api:latest` ou `evoapicloud/evolution-go:latest`

#### Autenticação (dois níveis)

| Nível | Header | Usado em |
|-------|--------|----------|
| **Global Token** | `apikey: {GLOBAL_API_KEY}` | Criar/listar/deletar instâncias, GET connectionState |
| **Instance Token** | `apikey: {INSTANCE_HASH}` | Enviar mensagens, configurar webhook, GET QR |

O `INSTANCE_HASH` é retornado no campo `response.instance.hash` ao criar a instância (`POST /instance/create`).

#### Endpoints (resumo para implementação)

```
POST   /instance/create                     → cria instância; retorna hash (instance token)
GET    /instance/connect/{name}             → obtém QR code base64
GET    /instance/connectionState/{name}     → estado: "open" | "close" | "connecting"
POST   /instance/logout/{name}             → desconecta sem deletar
DELETE /instance/delete/{name}             → remove instância completamente
GET    /instance/fetchInstances            → lista todas (paginado: ?page=1&offset=50)
POST   /message/sendText/{name}           → envia texto (usa INSTANCE_TOKEN)
POST   /message/sendMedia/{name}          → envia mídia (url/base64/upload)
PUT    /webhook/set/{name}                → configura URL e eventos do webhook
POST   /instance/pairingCode/{name}       → gera código de pareamento por telefone
```

#### POST /instance/create — Body mínimo
```json
{
  "instanceName": "tenant-uuid-suffix",
  "integration": "WHATSAPP-BAILEYS",
  "qrcode": true
}
```
Resposta: `{ "response": { "instance": { "instanceName": "...", "hash": "ABC123", "status": "connecting" } } }`

#### PUT /webhook/set/{name} — Body
```json
{
  "enabled": true,
  "url": "http://webhook_ingress:9200/webhook/evolution/{tenant_id}/{instance_id}",
  "webhookByEvents": false,
  "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]
}
```
> O campo `url` inclui `provider` no path para detecção automática no `webhook_ingress`.

#### POST /message/sendText/{name} — Body
```json
{
  "number": "5511999999999",
  "text": "Mensagem de texto aqui",
  "delay": 0
}
```
Resposta: `{ "response": { "key": { "id": "3EB0ABC..." } } }` — o `key.id` é o `message_id`.

#### Formato do Webhook Recebido (`MESSAGES_UPSERT`)
```json
{
  "event": "messages.upsert",
  "instance": "nome-da-instancia",
  "data": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "id": "3EB0ABC123DEF456",
      "fromMe": false
    },
    "message": { "conversation": "Olá, tudo bem?" },
    "messageTimestamp": 1718873400,
    "pushName": "João Silva",
    "status": "PENDING"
  }
}
```

#### Formato do Webhook Recebido (`CONNECTION_UPDATE`)
```json
{
  "event": "connection.update",
  "instance": "nome-da-instancia",
  "data": {
    "state": "open",
    "statusReason": 0,
    "lastDisconnect": null
  }
}
```

**Mapeamento `state` → `ConnectionState` Rust:**
```
"open"       → ConnectionState::Connected
"close"      → ConnectionState::Disconnected
"connecting" → ConnectionState::Connecting
_            → ConnectionState::Unknown
```

#### Erros comuns
| Código | Causa | Solução |
|--------|-------|---------|
| 400 | Número no formato errado | Usar DDI: `5511999999999` (13 dígitos) |
| 401 | Token errado (global vs instância) | Verificar qual token o endpoint exige |
| 404 | Instância não encontrada | Verificar nome e se foi deletada |
| 500 | Erro interno (ex: vídeo > 3MB via base64) | Enviar mídia grande via URL |

---

## Grupo C — Observabilidade e Auditoria (Transversal)

Referências: `doc_dev/planejamento/05-observabilidade.md`, `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` §4 e §4.2.

### Componente 1: `crates/infrastructure_messaging`
- **Logs/traces:** Nenhum — crate apenas de definição de tipos/traits, sem runtime.
- **Auditoria:** Sem evento de auditoria (intencional — apenas contratos).
- **Sanitização:** `MessagingProvider::create_instance` recebe `Option<&SecretString>` para o custom token — o tipo protege contra vazamento.

### Componente 2: `crates/infrastructure_evolution`
- **Logs/traces:** `#[tracing::instrument(err, skip(self, instance_token))]` em cada método `async fn` da impl — fields: `instance_name`, `provider = "evolution"`. Erros HTTP (4xx/5xx) logados como `error!` com `status_code` e `body` truncado (máx 200 chars). NÃO logar o `instance_token`.
- **Auditoria:** Sem evento de auditoria — é camada de infraestrutura sem identidade de usuário.
- **Sanitização:** `instance_token: &SecretString` — nunca passa por `{:?}` ou `to_string()` sem `expose_secret()`. O `global_api_key` da struct `EvolutionProvider` também deve ser `SecretString`.

### Componente 3: `apps/data_whatsapp`
- **Logs/traces:** `#[instrument(skip_all, fields(rpc = "CreateWhatsappInstance", tenant_id = %req.tenant_id))]` em cada handler RPC. Level `info!` em criação/exclusão; `warn!` em falhas de conexão de instância; `error!` em falhas de infra.
- **Auditoria:** Eventos críticos que **devem** gerar `audit_log`:
  - `whatsapp.instance.create` — ao criar instância (campos: `tenant_id`, `user_id`, `instance_name`, `provider`; **não** logar tokens).
  - `whatsapp.instance.delete` — ao deletar instância.
  - `whatsapp.admin.bulk_disconnect` — operação admin global/por-tenant (campo extra: `scope = "global" | tenant_id`).
  - Publicar assincronamente via `transport::bus` → `data_postgres`.
- **Sanitização:** `instance_token` (retornado pelo Evolution) armazenado no banco encriptado e, em memória, como `SecretString`. NÃO aparece em spans nem em respostas RPC não-seguras.

### Componente 4: `apps/webhook_ingress`
- **Logs/traces:** `#[instrument(skip(body), fields(provider, tenant_id, instance_id))]` no handler de webhook. Log `debug!` para eventos processados com sucesso; `warn!` para eventos desconhecidos; `error!` para falhas de publicação no Redis. NÃO logar o corpo raw do webhook (contém PII: número de telefone, nome, conteúdo de mensagem).
- **Auditoria:** Sem evento de auditoria (intencional — é hot path de volume alto; auditoria de mensagens é responsabilidade do `worker`).
- **Sanitização:** Payload do webhook NUNCA deve ser logado em nível `info!` ou superior. Apenas metadados: `event_type`, `instance_name`, `tenant_id`. O campo `pushName` (nome do contato) e `remoteJid` (telefone) são PII — nunca logar em produção.

### Componente 5: `infrastructure_postgres` — módulo whatsapp
- **Logs/traces:** `#[instrument(skip_all)]` + `run_in_tenant_transaction` para queries de tenant. Repositório admin (AdminListAllConnectedInstances com bypass de RLS) usa `run_in_admin_transaction` + `#[instrument(skip_all, fields(operation = "admin_list_all_whatsapp_instances"))]`.
- **Auditoria:** Sem evento de auditoria no repositório — eventos são publicados pela camada de aplicação (`data_whatsapp`).
- **Sanitização:** Não logar valores de `api_key` ou `instance_token` ao mapear linhas do banco.

### Componente 6: `apps/control_plane` — endpoints admin WhatsApp
- **Logs/traces:** `#[instrument(err, fields(admin_action = "bulk_disconnect", scope))]` no handler do endpoint `/api/v2/admin/whatsapp/disconnect-all`.
- **Auditoria:** O `control_plane` **replica** o evento de auditoria com contexto HTTP enriquecido: `ip_address`, `user_agent`, `user_id` (do `RequestContext`). O `data_whatsapp` também publica o evento — o `control_plane` enriquece com metadados de HTTP que o gRPC/RPC interno não carrega.
- **Sanitização:** Resposta do endpoint admin não deve incluir tokens de instância — apenas `instance_name`, `tenant_id` e `status`.

---

## Notas Gerais / Gotchas

1. **Diferença de versão axum:** `runtime_api` permanece em 0.7.5. `webhook_ingress` usará 0.8. Não adicionar axum ao workspace `Cargo.toml` — cada app declara independentemente.
2. **Evolution API — Webhook vs. QR:** Ao chamar `POST /instance/create` com `qrcode: true`, o QR já vem na resposta. O endpoint `GET /instance/connect/{name}` é para renovar o QR quando expira.
3. **Deduplicação de MESSAGES_UPSERT:** O mesmo evento pode chegar duas vezes (uma no envio, outra na entrega). O worker deve deduplicar por `key.id`.
4. **Base64 e mídias grandes:** Vídeos > 3MB causam "Maximum call stack size exceeded" se enviados em base64. Usar sempre URL remota (campo `media` como URL do R2/CDN).
5. **Evolution API — `webhookByEvents: false`:** Configurar como `false` para receber todos os eventos na mesma URL (o `webhook_ingress` discrimina por `event` field no JSON). Se `true`, a Evolution enviaria para URLs diferentes por tipo de evento.
6. **`AdminBulkDisconnectInstances` e RLS:** A query admin usa bypass de RLS (`current_setting('app.current_tenant')` não setado, ou set como role `operacional:admin`). Verificar padrão do projeto em `run_in_admin_transaction`.
7. **Reescrita de migração:** O plano reescreve `0008_evolution_sync.sql` → `0008_whatsapp_sync.sql`. Isso é seguro apenas no início da implementação (sem dados em produção). Em produção, exigiria migração incremental.
