# Final Review — camada-mensageria-whatsapp-evolution-go
Data: 2026-06-25 · Modelo: Opus · Diff: main...HEAD + working tree

## Rótulo: CORRIGIDO  (informativo — não bloqueia o ciclo)

## Resumo das correções
A implementação está, em sua quase totalidade, **conforme o plano consolidado v4**. Os 4
componentes do escopo (`infrastructure_messaging`, `infrastructure_evolution`, `data_whatsapp`,
`webhook_ingress`) foram realinhados ao contrato Evolution Go, com SOLID real (ISP/DIP/OCP/LSP),
observabilidade e auditoria conformes. Foi encontrado e corrigido **um desvio de LSP**: os 5
handlers de capacidade opcional em `data_whatsapp` retornavam `AppError::Internal` com strings
ad-hoc ("Provedor não suporta…") em vez de derivar do variante canônico
`MessagingProviderError::Unsupported(&'static str)` que o plano (premissa #4, tabela E3) exige.
Corrigidos os 5 handlers para construir `Unsupported(...)` e ajustado o assert do teste
`test_lsp_unsupported_error` para a mensagem canônica. Build, clippy `-D warnings` (all-targets) e
a suíte de testes (`test-local.ps1 -Fast`) ficaram 100% verdes nos 4 crates do escopo.

## 1. Plano vs. Implementado

| Item | Status | Observação |
| --- | --- | --- |
| **E1** Segregar trait em traits de capacidade (ISP) | ✅ | `InstanceManager`+`MessageSender` núcleo; `PresenceControl`/`ReadReceipts`/`Reactions`/`MediaDownloader`/`ProfileQuery`/`AdvancedSettingsControl` opcionais. |
| **E1** Fachada `MessagingProvider` com `Option<&dyn Cap>` default `None` | ✅ | Acessores `&self` não-genéricos; object-safety OK (`Arc<dyn MessagingProvider>` compila). |
| **E1** `ProviderRegistry` + builder (DIP) | ✅ | `registry.rs`; chave = `provider_name()`; `resolve` → `Config` para desconhecido. |
| **E1** `MessagingProviderError::Unsupported` | ✅ | `errors.rs`; Display "Operação não suportada pelo provedor: {0}". |
| **E1** Remover `pair_by_phone`/`configure_webhook` | ✅ | Grep limpo no workspace inteiro. |
| **E2** EvolutionProvider implementa todos os traits + acessores `Some(self)` | ✅ | `provider.rs`; todos os 8 traits implementados. |
| **E2** Contrato Go (endpoints/auth/body) | ✅ | Ver seção 3. |
| **E2** `map_state` ampliado (open/connected/close/disconnected/loggedOut/connecting) | ✅ | `provider.rs`. |
| **E2** `client.rs` desserializa Go (`token`, `state` top-level) | ✅ | `CreateInstanceResp.token`, `ConnStateResp.state`. |
| **E2** Body de erro truncado a 200 | ✅ | `client.rs`. |
| **E3** `AppState { registry, redis_conn }` (DIP) | ✅ | Concreto só na composition root (`main`). |
| **E3** Resolução `dyn` por instância via `registry.resolve(provider)` | ✅ | Em todos os handlers. |
| **E3** `connect_instance(&WebhookConfig)` no fluxo create | ✅ | subscribe `["MESSAGE","CONNECTION","PRESENCE","QRCODE"]`+`immediate`. |
| **E3** advanced-settings no create (`always_online:true`,`read_messages:false`) | ✅ | Via acessor; falha não bloqueia (warn). |
| **E3** Novos RPCs markread/react/presence/avatar/download/reconnect | ✅ | 5 RPCs de capacidade + reconnect registrados. |
| **E3** Capacidade ausente → `Unsupported` | ⚠️→✅ | **Corrigido**: usava `AppError::Internal` ad-hoc; agora deriva de `MessagingProviderError::Unsupported`. |
| **E3** Mock `FakeMessagingProvider` provando DIP/LSP | ✅ | Prova que handler depende só do `dyn`. |
| **E4** `WebhookNormalizer` registry (OCP) | ✅ | `HashMap<&str, Arc<dyn WebhookNormalizer>>`; sem `match` hardcoded. |
| **E4** Canonização eventos Go UPPERCASE/PascalCase/aliases | ✅ | `canonical_event` cobre MESSAGE/CONNECTION/PRESENCE/CONTACTS/QRCODE/MESSAGE_UPDATE. |
| **E4** Provedor desconhecido = 202 + warn | ✅ | Testado (`test_webhook_unknown_provider`). |
| **E5** DB sem mudança | ✅ | Nenhum arquivo de migração/repo tocado. |
| **E6** control_plane sem regressão | ✅ | `AdminBulkDisconnect`→`AdminBulkDisconnectInstances`; grep limpo de `evolution_sync`/v2. |
| ➕ `translate_go_payload` no ingress (mapeia `data.Info`/`Message` whatsmeow → shape canônico) | ➕ | Além do plano; útil e bem isolado. Ver seção 5. |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
| --- | --- | --- |
| `data_whatsapp/src/main.rs` ~1017 (`handler_mark_whatsapp_message_read`) | Capacidade ausente retornava `AppError::Internal("Provedor não suporta recibos de leitura")` — não usa o variante canônico `Unsupported` (desvio LSP do plano). | Passa a construir `MessagingProviderError::Unsupported("read_receipts").to_string()`. Comentário pt-br explicando LSP. |
| `data_whatsapp/src/main.rs` ~1133 (`handler_send_whatsapp_reaction`) | Idem ("Provedor não suporta reações"). | `Unsupported("reactions")`. |
| `data_whatsapp/src/main.rs` ~1251 (`handler_set_whatsapp_presence`) | Idem ("Provedor não suporta presença"). | `Unsupported("presence")`. |
| `data_whatsapp/src/main.rs` ~1342 (`handler_get_whatsapp_profile_picture`) | Idem ("Provedor não suporta consulta de fotos de perfil"). | `Unsupported("profile")`. |
| `data_whatsapp/src/main.rs` ~1437 (`handler_download_whatsapp_media`) | Idem ("Provedor não suporta download de mídia"). | `Unsupported("download")`. |
| `data_whatsapp/src/main.rs` ~2062 (`test_lsp_unsupported_error`) | Assert casava as strings antigas; após a correção a mensagem é canônica. | Assert ajustado para `"não suportada pelo provedor"` + `"reactions"`. |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
| --- | --- | --- | --- | --- |
| **Eixo A — logs/traces** | ✅ | — | — | `tracing` em todos (sem `println!`); `#[instrument(skip_all, fields(rpc, tenant_id))]` nos handlers; `#[instrument(err, skip(self,token,…))]` nos métodos de infra (falha real). traceparent flui no Envelope; telemetry injeta correlação. |
| **Eixo B — auditoria** | — | ✅ | ✅ | `whatsapp.instance.create`/`delete` e `whatsapp.admin.bulk_disconnect` via `publicar_evento_seguranca` → `security:stream`. Context = `{user_id, instance_name, provider}` / `{user_id, count, scope}` — **sem token**. `tenant_id`=`Uuid::nil()` quando bulk global. Recursos de mensagem (send/react/markread/presence/download) sem auditoria (intencional, alto volume). |
| **Eixo C — sanitização** | ✅ | ✅ | ✅ | `SecretString` em `skip(...)` em todos os métodos; `apikey`/`token`/`text`/`caption`/`message` nunca logados; body de erro truncado a 200; **body do webhook NUNCA logado** no ingress (só `event_type` canônico no span). Nenhum segredo/PII em log. |

## 3. Confirmação do contrato Go (adapter prevalece)

| Operação | Esperado (Go) | Implementado | Status |
| --- | --- | --- | --- |
| `/instance/connect` auth | TOKEN da instância | `header("apikey", instance_token.expose_secret())` | ✅ |
| Campo de eventos | `subscribe` UPPERCASE (não `events`) | `"subscribe": webhook.subscribe` + `"immediate": true` | ✅ |
| Status | `GET /instance/status` (não `/connectionState`) | `GET /instance/status` | ✅ |
| Envio texto | `POST /send/text` | `POST /send/text` `{number,text}` | ✅ |
| Envio mídia | `POST /send/media` `{type,url,caption,filename}` | `POST /send/media` `{number,type,url,caption?}` | ✅ |
| Logout | `DELETE /instance/logout` (sem nome) | `DELETE /instance/logout` | ✅ |
| Criar/Listar/Deletar (global key) | create/`/instance/all`/`/instance/delete/{name}` | conforme | ✅ |

Nenhum endpoint v2 remanescente (`connectionState`, `fetchInstances`, `sendText/{name}`,
`sendMedia/{name}`, `webhook/set`, `pairingCode`, `mediatype`) — grep limpo no workspace inteiro,
incluindo testes. Mocks wiremock já apontam para os endpoints Go.

## 4. Revalidação

| Etapa | Resultado |
| --- | --- |
| `cargo build` (4 crates do escopo, SQLX_OFFLINE) | ✅ Finished, sem erros |
| `cargo clippy --all-targets -- -D warnings` (4 crates) | ✅ Finished, zero warnings |
| `test-local.ps1 -Fast` (fmt + clippy + unit/integração, sem DB) | ✅ TUDO VERDE |

Resultados por crate do escopo:
- `infrastructure_messaging`: **4/4** ok (serde round-trip, Display incl. `Unsupported`).
- `infrastructure_evolution`: lib **2/2** + integração `client_tests` **20/20** ok (endpoints Go + truncamento).
- `data_whatsapp`: **8/8** ok (inclui `test_lsp_unsupported_error` corrigido + DIP via `FakeMessagingProvider`).
- `webhook_ingress`: **6/6** ok (registry, provedor desconhecido=202, canonização Go/v2).

> Nota: usado `-Fast` (fmt+clippy+unit, sem banco). Os 4 componentes do escopo não tocam
> `sqlx`/Postgres, então o túnel SSH não acrescenta cobertura para eles — todos os seus testes
> rodam em `-Fast`.

## 5. Pendências (escopo extra ou fora do plano)
- ➕ **`translate_go_payload` (webhook_ingress)**: feature além do plano que converte o payload
  nativo whatsmeow (`data.Info`/`data.Message`) para um shape canônico estilo Baileys antes de
  empacotar em `raw_event`. Bem isolado, testado (`test_webhook_evolution_go_message_received`) e
  não loga PII. Mantido — melhoria útil para o `worker` a jusante. Recomenda-se documentar no
  plano que o ingress já faz essa tradução.
- **Contrato gRPC dos novos RPCs** (`MarkWhatsappMessageRead`/`SetWhatsappPresence` etc.): o
  `.proto` desses RPCs não foi auditado (fora do escopo dos 4 componentes). Confirmar com o time
  de contratos que os nomes de campo do payload JSON casam com o cliente Flutter/worker quando
  forem consumidos.
- **Campo `base64` do `/message/downloadmedia`**: confirmar empiricamente contra o Evolution Go
  real (a doc web divergia; o adapter diz `base64`). Validação de integração V3.
- Nenhuma pendência bloqueante.
