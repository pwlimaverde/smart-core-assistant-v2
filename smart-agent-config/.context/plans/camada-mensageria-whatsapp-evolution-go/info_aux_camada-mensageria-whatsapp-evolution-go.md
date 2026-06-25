# Documentação Auxiliar — Módulo Rust de Mensageria WhatsApp (Evolution Go)

> Gerado em: 2026-06-25
> Plano canônico: `.context/plans/camada-mensageria-whatsapp-evolution-go.md`
> Plano completo: `.context/plans/camada-mensageria-whatsapp-evolution-go/plano_completo_camada-mensageria-whatsapp-evolution-go.md`
>
> ⚠️ **Hierarquia de fontes para o Evolution Go**: o contrato REST do Go é mal documentado
> publicamente (fork de nicho). A **fonte da verdade** é o adapter battle-tested do projeto
> antigo — `old/smart-core-assistant-painel/.../evolution_sync/services/evolution_go_adapter.py`
> — que roda contra o **mesmo servidor** que está em produção, com notas de debugging inline.
> A coleta web (subagente) é **complementar** e, onde conflita com o adapter, **o adapter
> prevalece** (conflitos sinalizados abaixo).

---

## Libs Rust (todas USAR LOCAL — central `doc_dev/libs/rust/` fresca)

| Lib | Versão (workspace) | Doc local | Status / Verificação | Uso no plano |
| --- | --- | --- | --- | --- |
| reqwest | 0.12.4 | `doc_dev/libs/rust/reqwest.md` | ✅ 2026-05-31 (menciona Evolution Go) | cliente HTTP de `infrastructure_evolution` |
| axum | 0.8 (local no webhook_ingress) | `doc_dev/libs/rust/axum.md` | ✅ 2026-06-20 (cobre webhook_ingress + breaking 0.7→0.8) | rotas do `webhook_ingress` |
| secrecy | 0.10.3 | `doc_dev/libs/rust/secrecy.md` | ✅ | `SecretString` p/ global_api_key/instance_token |
| async-trait | 0.1.83 | `doc_dev/libs/rust/async_trait.md` | ✅ | trait `MessagingProvider` |
| serde / serde_json | 1.0 | `doc_dev/libs/rust/serde.md` | ✅ | (de)serialização de payloads |
| tracing | 0.1.40 | `doc_dev/libs/rust/tracing.md` | ✅ | spans/instrument |
| redis | 0.25 | `doc_dev/libs/rust/redis.md` | ✅ | `transport::bus` (events:stream / security:stream) |
| tokio | 1.38 | `doc_dev/libs/rust/tokio.md` | ✅ | runtime async |
| uuid | 1.0 | `doc_dev/libs/rust/uuid.md` | ✅ | tenant_id / instance_id |
| thiserror | 1.0 | `doc_dev/libs/rust/thiserror_anyhow.md` | ✅ | `MessagingProviderError` |
| mockall | 0.13 | `doc_dev/libs/rust/mockall.md` | ✅ | mock da port `WhatsappStore` |
| wiremock (dev) | 0.6 | — | n/d | mock HTTP dos endpoints Go nos testes |

**Nenhuma lib exigiu Context7** — todas USAR LOCAL. Pontos-chave reaproveitados da central:
- **reqwest**: reutilizar um único `reqwest::Client` (pool interno, clone barato); `.json()` para
  body; tratar `status().is_success()` antes de desserializar.
- **axum 0.8** (breaking vs 0.7, do doc local): rotas com chaves `{param}` (não `:param`);
  `Extension` → `State`; `Server::bind().serve()` → `TcpListener` + `axum::serve(listener, app)`;
  `.with_state(state)` obrigatório. O `webhook_ingress` atual já segue isso.

---

## Serviço Externo — Evolution Go (`evoapicloud/evolution-go`, whatsmeow)

> Base URL no projeto: `EVOLUTION_API_URL` (ex.: `http://evolution:8080`). Auth: header `apikey`.
> Doc oficial (escassa): https://docs.evolutionfoundation.com.br/evolution-go .
> **Contrato canônico abaixo = extraído do `evolution_go_adapter.py` (battle-tested).**

### Autenticação (duas chaves, header `apikey`)
- **Global API Key** (`EVOLUTION_GLOBAL_API_KEY`): criar / deletar / **listar** instâncias.
- **Token da instância** (campo `api_key`/`token` da instância): conectar, QR, status, enviar,
  sessão (markread/react/presence), logout, advanced-settings, download.

### Endpoints (contrato Go — fonte: adapter)

| Operação | Método + Path | Auth | Body | Resposta |
| --- | --- | --- | --- | --- |
| Criar instância | `POST /instance/create` | global | `{name, token?}` | `{token, id?, name?}` |
| **Conectar + webhook** | `POST /instance/connect` | **instância** ⚠️ | `{instanceName, webhookUrl, subscribe:[...], immediate:true}` | `{...}` (pode trazer QR/status) |
| QR code | `GET /instance/qr` | instância | — | `{base64?, code?}` |
| Estado | `GET /instance/status` | instância | — | `{state}` (ex.: `open`) |
| Listar | `GET /instance/all` | global | — | `{data:[...]}` ou `[...]` |
| Logout (desconectar) | `DELETE /instance/logout` | instância | — (sem nome no path) | — |
| Deletar | `DELETE /instance/delete/{name}` | global | — | — |
| Reconectar | `POST /instance/reconnect` | instância | — | `{...}` |
| Advanced settings | `PUT /instance/{id}/advanced-settings` | instância | `{alwaysOnline, readMessages, rejectCall, msgRejectCall, ignoreGroups, ignoreStatus}` | `{...}` |
| Enviar texto | `POST /send/text` | instância | `{number, text, quoted?}` | `{key:{id}}` |
| Enviar mídia | `POST /send/media` | instância | `{number, type, url, caption, filename}` | `{key:{id}}` |
| Enviar áudio/PTT | `POST /send/media` | instância | `{number, type:"audio", url}` | `{key:{id}}` |
| Reagir | `POST /message/react` | instância | `{number, reaction, id, fromMe}` | `{...}` |
| Marcar lido | `POST /message/markread` | instância | `{number, id:[...]}` | `{...}` |
| Presença | `POST /message/presence` | instância | `{number, state, isAudio}` | `{...}` |
| Foto de perfil | `POST /user/avatar` | instância | `{number, preview:false}` | `{profilePictureUrl?, url?}` |
| Download mídia | `POST /message/downloadmedia` | instância | `{message:<obj whatsmeow>}` | `{base64, mimetype?}` |

### Eventos do webhook (do Go) — nomes UPPERCASE/PascalCase + aliases
Canonização (espelhar `EvolutionEventName.from_raw` do old; `data/domain/schemas.py`):
- `Message` / `MESSAGE` / `messages.upsert` / `MESSAGES_UPSERT` → **MESSAGE**
- `Connection` / `CONNECTION` / `connection.update` / `Connected` / `Disconnected` / `LoggedOut` → **CONNECTION**
- `MESSAGE_UPDATE` / `messages.update` → **MESSAGE_UPDATE**
- `Presence` / `PRESENCE` / `presence.update` → **PRESENCE**
- `QRCode` / `QRCODE` / `qrcode.updated` → **QRCODE**
- `Contacts` / `CONTACTS` / `contacts.update` → **CONTACTS**
- `SendMessage` / `SEND_MESSAGE` → **SEND_MESSAGE**

Envelope base do webhook: `{event, data, instanceName, instanceToken?, timestamp}`.
Payload de **MESSAGE**: `data.key.{remoteJid,id,fromMe,participant}`, `data.message.{conversation,
imageMessage,...}`, `data.pushName`, `data.messageTimestamp`, `data.type`. Mídia pode vir com
`base64` inline (pequena) ou exigir `downloadmedia` (grande).
Payload de **CONNECTION**: `data.state`/`data.status` (open/close/connecting/loggedOut).

### ⚠️ Gotchas confirmados (notas inline do adapter battle-tested)
1. **`POST /instance/connect` exige o TOKEN DA INSTÂNCIA** no `apikey`. A Global Key retorna
   **401 "not authorized"** aqui. *(O subagente web disse "global key" — INCORRETO para este
   servidor; o adapter vence.)*
2. **Campo de eventos é `subscribe`** (array UPPERCASE: `MESSAGE`, `CONNECTION`, `PRESENCE`,
   `QRCODE`). Nome inválido **zera** a assinatura (`events=""`) → para toda entrega de webhook.
   Não usar o campo `events` do v2.
3. **Status é `GET /instance/status`** — **NÃO** usar `/instance/connectionState/{name}` (v2;
   retorna **503** no Go).
4. **Envio é `/send/text` e `/send/media`** — NÃO `/message/sendText/{name}` (v2). Body de mídia
   usa `type`/`url`/`caption`/`filename` (NÃO `mediatype`/`media`/`fileName`).
5. **Logout é `DELETE /instance/logout`** (sem nome no path), token da instância.
6. **`readMessages` deve ser `false`** — recibo de leitura é explícito via `markread`, nunca
   automático.
7. **`alwaysOnline:true`** é o mecanismo documentado para manter a sessão whatsmeow viva.
8. **Download**: a rota real é `/message/downloadmedia` (o swagger lista `/downloadimage`,
   incorreto). Resposta traz `base64` (campo `base64`; o subagente web disse `media` — **incerto**,
   validar no servidor real durante V3).
9. **Idempotência**: webhooks de mensagem podem chegar 2× (retry); dedup por `key.id` é do worker.

### Conflitos subagente-web × adapter (adapter prevalece)
| Item | Subagente web | Adapter (canônico) |
| --- | --- | --- |
| Auth do `/instance/connect` | global key | **token da instância** |
| Path de envio | `/message/sendText/{name}` | **`/send/text`** |
| Status | `/instance/connectionState` ok | **só `/instance/status`** |
| Logout | `/instance/{name}/logout` (global) | **`DELETE /instance/logout` (instância)** |
| Body de mídia | `mediatype`/`url`/`fileName` | **`type`/`url`/`filename`** |
| Campo base64 do download | `media` | **`base64`** (validar em V3) |

---

## Grupo C — Observabilidade & Auditoria (transversal)

- **Logs/trace**: `infrastructure_evolution` usa `#[tracing::instrument(err, skip(self,
  instance_token, text, caption))]` com `provider="evolution"`, `instance_name`. `data_whatsapp`
  e `webhook_ingress` usam `#[instrument(skip_all/skip(state,body), fields(rpc|provider, tenant_id,
  instance_id, event_type))]`. Campos de correlação: `service`, `env`, `tenant_id`, `trace_id`,
  `error_code`.
- **Auditoria (`audit_log` via `transport::bus::publicar_evento_seguranca` → `security:stream` →
  `data_postgres`)**: eventos `whatsapp.instance.create`, `whatsapp.instance.delete`,
  `whatsapp.admin.bulk_disconnect`. `context` JSONB **sem** token. `tenant_id` NULL quando ação
  global de superusuário. Recursos de mensagem (send/react/markread/presence) **sem auditoria**
  (alto volume — intencional).
- **Sanitização**: `global_api_key`/`instance_token`/`api_key` sempre `secrecy::SecretString`,
  sempre em `skip(...)`; body de erro do provedor truncado a 200 chars; `body` do webhook **nunca**
  logado (PII: telefone/nome/conteúdo).

## Notas gerais
- DB já pronto (`0008_whatsapp_sync.sql` + repositório + ports/adapters); **sem mudança de schema**.
- Dois `axum` coexistem (0.7.5 runtime_api / 0.8 webhook_ingress) — não unificar no workspace.
- Plano arquivado relacionado: `.context/plans/archive/camada-abstracao-mensageria/` (versão v2;
  este plano é o realinhamento ao Go).
