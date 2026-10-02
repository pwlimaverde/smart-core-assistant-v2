# Documentação Auxiliar — Correções do app Windows (smart-core-tenant)

> Gerado em: 2026-10-01
> Plano canônico: `.context/plans/correcoes-app-windows-flutter.md`
> Plano completo: `.context/plans/correcoes-app-windows-flutter/plano_completo_correcoes-app-windows-flutter.md`
> Origem do plano-base: conversa (P1, P1.1, P2a, P2b, P3, P4, P5, P6).

Fontes: central local `doc_dev/libs/{flutter,rust}/` (citada com a data de
`Última Verificação`) e coleta web de 2026-10-01 (pub.dev, docs.rs, developers.cloudflare.com,
redis.io, github.com/EvolutionAPI/evolution-go). O MCP Context7 estava sem autenticação nesta
sessão; as libs marcadas para Context7 foram verificadas por WebFetch nas fontes oficiais e a
central foi atualizada do mesmo jeito.

---

## 0. Levantamento (etapa 1) e triagem da central (etapa 2a)

### Grupo A — Libs

| Stack | Lib | Manifesto | Central antes | Estado | Resultado |
|---|---|---|---|---|---|
| flutter | flutter_bloc | ^9.1.1 (+ bloc ^9.2.1) | 9.1.1, verif. 2026-06-14 (vencida) | ATUALIZAR | atualizada 2026-10-01 |
| flutter | record | ^6.1.1 | 5.1.2 (versão divergente) | ATUALIZAR | atualizada para 6.1.1 |
| flutter | file_picker | ^11.0.2 | 11.0.2, verif. 2026-08-09 | USAR LOCAL | — |
| flutter | http | ^1.2.2 | inexistente | CRIAR | `http.md` criado |
| flutter | flutter_local_notifications | ^22.3.1 | 22.3.1, verif. 2026-09-19 | USAR LOCAL | — |
| flutter | path_provider | ^2.1.5 | 2.1.2 (divergente, vencida) | ATUALIZAR | atualizada para 2.1.5 |
| flutter | connectivity_plus | ^7.3.0 | 6.x (divergente) | ATUALIZAR | atualizada para 7.3.0 |
| flutter | clipboard de imagem (P3) | ausente | inexistente | CRIAR (avaliação) | `super_clipboard.md` (🔍 EM_HOMOLOGACAO) |
| flutter | player de mídia no Windows (P2a) | ausente | just_audio/video_player sem nota Windows | CRIAR (avaliação) | `media_kit.md` (🔍); `just_audio.md`/`video_player.md` atualizados |
| rust | tokio | 1.38 (full) | verif. 2026-05-31 (vencida) | ATUALIZAR | atualizada |
| rust | sqlx | 0.9 | verif. 2026-06-10, trecho com 0.8.2 | ATUALIZAR | atualizada (features 0.9) |
| rust | serde | 1.0 | verif. 2026-05-31 | ATUALIZAR | atualizada |
| rust | tracing | 0.1.40 | verif. 2026-05-31 | ATUALIZAR | atualizada |
| rust | redis | 0.25.0 (aio, tokio-comp, connection-manager, streams) | verif. 2026-06-10 | ATUALIZAR | atualizada |
| rust | aws-sdk-s3 | 1 (lock 1.135) | 1.145.0, verif. 2026-09-06 | USAR LOCAL | — |
| rust | secrecy | 0.10.3 | verif. 2026-06-01 | USAR LOCAL (uso pontual) | — |

### Grupo B — Serviços externos

- **Evolution Go** (imagem `evolution-go` v2.3.x; base interna `http://evolution:8080`), auth header `apikey` (token da instância):
  `POST /message/downloadmedia`, `POST /send/media`, `POST /user/avatar`, webhook `messages.upsert` / `messages.update`, `POST /instance/connect` (lista `subscribe`).
- **Cloudflare R2** (`https://<account_id>.r2.cloudflarestorage.com`, region `auto`), auth SigV4 (chaves `S3_*`): presigned PUT/GET, multipart.
- **Redis 7.x** (via `data_redis` / bus): `SET NX EX` (idempotência), Streams (`XADD`/`XREADGROUP`/`XACK`), ZSET para janela, Pub/Sub.

### Grupo C — Observabilidade e auditoria por problema (insumo da etapa 4)

| Problema | Log/trace (Rust `tracing` / Flutter) | `audit_log` | Risco de vazamento |
|---|---|---|---|
| P1 / P1.1 (pisca, buffer, agrupamento) | span `buffer.janela` (tenant_id, atendimento_id, qtd_eventos, motivo_flush); contador de recargas por mensagem no cliente (debug), métrica `smartcore_buffer_flush_total` | sem evento de auditoria (estado trivial, alto volume — mesma regra da §10 do doc 05) | texto da mensagem e telefone nunca no span; só ids |
| P2a (mídia na bolha) | span de `downloadmedia` e presign GET (mime, tamanho, resultado); cliente loga falha de render por tipo | sem evento (leitura de mídia já coberta pela trilha de acesso existente, se houver; senão declarar intencional) | **URL assinada nunca logada** (contém `X-Amz-Signature`); `mediaKey`/`base64` fora do log |
| P2b (gravação de áudio) | cliente: início/fim/erro de gravação (encoder, duração, bytes); servidor: span de presign PUT e `send/media` (type=audio, http_status) | sem evento (envio já gera a mensagem e o histórico) | caminho temporário do arquivo sem nome de usuário; URL assinada fora do log |
| P3 (Ctrl+V imagem) | cliente: formato detectado (png/dib), tamanho, erro | sem evento | conteúdo do clipboard nunca logado |
| P4 (transferência automática) | span da decisão de transferência (regra, motivo, resultado) no worker/ia_engine | `atendimento.transferido_por_ia` (já existe; conferir que é emitido) | texto da conversa fora do audit e da métrica |
| P5 (rolagem kanban) | sem log de servidor; no máximo debug de layout | sem evento | nenhum |
| P6 (foto do contato) | span de `/user/avatar` (resultado: ok/sem_foto/erro), cache hit/miss | sem evento | URL do `pps.whatsapp.net` é temporária e tokenizada: não logar; telefone mascarado |

---

## 1. Libs Flutter

### flutter_bloc 9.1.1 (+ bloc 9.2.1) — `doc_dev/libs/flutter/flutter_bloc.md` (2026-10-01)
- API de `Cubit`/`Bloc`/`BlocBuilder`/`BlocListener` igual à 8.x; a 9.0 removeu só `BlocOverrides`.
- Proteja `emit` após fechamento com `if (isClosed) return;` em callbacks assíncronos.
- `buildWhen: (a, b) => ...` e `listenWhen` evitam rebuild quando só um campo irrelevante muda.
- Transformers de evento via `bloc_concurrency` (`droppable`, `restartable`, `sequential`) ou
  transformer próprio com debounce sobre `Stream`. Em `Cubit` não há transformer: o debounce fica
  no stream de origem (ex.: `Timer` / coalescência antes do `emit`).
- Estado com igualdade por valor (`Equatable` ou `==` manual) para o `BlocBuilder` não reconstruir
  com estado igual.

### record 6.1.1 — `doc_dev/libs/flutter/record.md` (2026-10-01)
- `final rec = AudioRecorder(); await rec.hasPermission(); await rec.start(const RecordConfig(encoder: AudioEncoder.opus), path: p); final path = await rec.stop(); await rec.dispose();`
- Encoders no Windows: `aacLc`, `opus`, `wav`, `flac`, `pcm16bits`. Use `await rec.isEncoderSupported(AudioEncoder.opus)` antes e caia para `aacLc` se faltar.
- 5.x → 6.x: streams viraram broadcast; `stop()` resolve mesmo fora de gravação; API central igual.
- Atenção (não confirmado na fonte, validar na implementação): o contêiner gerado pelo encoder
  `opus` no Windows pode não ser Ogg; o WhatsApp exige `audio/ogg; codecs=opus` para PTT. Se não for,
  a conversão fica no servidor (ffmpeg) ou o envio vai como áudio comum (`aacLc`/m4a), não PTT.

### file_picker 11.0.2 — `doc_dev/libs/flutter/file_picker.md` (2026-08-09, USAR LOCAL)
- `FilePicker.platform.pickFiles(...)`; Windows devolve `path`, Web devolve `bytes`.

### http 1.2.2 — `doc_dev/libs/flutter/http.md` (criado 2026-10-01)
- `await http.put(Uri.parse(url), headers: {'Content-Type': mime}, body: bytes).timeout(...)`.
- O `Content-Type` do PUT tem que ser o mesmo assinado no presign, senão 403 `SignatureDoesNotMatch`.
- Para arquivos grandes, `http.StreamedRequest('PUT', uri)` com `contentLength` definido.

### flutter_local_notifications 22.3.1 — `doc_dev/libs/flutter/flutter_local_notifications.md` (2026-09-19, USAR LOCAL)
- API com parâmetros nomeados (`initialize(settings: …)`, `show(id: …, notificationDetails: …)`).
- Debounce de ~500 ms ao disparar avisos em rajada (o Windows engole toasts < 100 ms).

### path_provider 2.1.5 — `doc_dev/libs/flutter/path_provider.md` (2026-10-01)
- `getTemporaryDirectory()` para o áudio gravado; `getApplicationSupportDirectory()` para cache persistente (ex.: avatares).

### connectivity_plus 7.3.0 — `doc_dev/libs/flutter/connectivity_plus.md` (2026-10-01)
- `Connectivity().onConnectivityChanged` → `Stream<List<ConnectivityResult>>`; 6 → 7 sem quebra de API.
- Mudança de interface não garante internet; debounce antes de disparar recarga (evita somar recargas no P1).

### super_clipboard 0.9.1 (proposta P3) — `doc_dev/libs/flutter/super_clipboard.md` (🔍 2026-10-01)
- `Clipboard.getData` do Flutter só lê texto; imagem exige plugin.
- `final reader = await SystemClipboard.instance?.read(); if (reader.canProvide(Formats.png)) reader.getFile(Formats.png, (f) async { final bytes = await f.readAll(); ... });`
- No Windows converte DIB/DIBv5 em PNG. Depende de `super_native_extensions` (Rust nativo → exige toolchain Rust no build do Windows; o projeto já tem por causa do `local_engine_ffi`).
- Alternativa mais leve: `pasteboard` (`Pasteboard.image` → `Uint8List?`). Decisão final na fase P3.
- Captura do atalho: `Shortcuts`/`CallbackShortcuts` com `SingleActivator(LogicalKeyboardKey.keyV, control: true)` ou `TextField.contentInsertionConfiguration` (só mobile). No Windows, interceptar o Ctrl+V no foco do campo de mensagem e cair para colar texto quando não houver imagem.

### Reprodução de mídia no Windows (proposta P2a) — `media_kit.md` (🔍), `just_audio.md`, `video_player.md` (2026-10-01)
- `video_player` não tem implementação oficial para Windows.
- `just_audio` no Windows precisa de backend (`just_audio_media_kit` recomendado; toca ogg/opus).
- `media_kit` (+ `media_kit_video`, `media_kit_libs_windows_video`) cobre áudio e vídeo via libmpv.
- Imagem não precisa de lib: `Image.network(urlAssinada)` com `errorBuilder`; documento abre com `url_launcher` (doc na central).

---

## 2. Libs Rust

### tokio 1.38 — `doc_dev/libs/rust/tokio.md` (2026-10-01)
- `tokio::time::{sleep, interval, timeout}`, `sync::{mpsc, broadcast, watch}`, `select!`, `JoinSet`.
- `broadcast::Receiver::recv` devolve `RecvError::Lagged(n)` quando o assinante atrasa — tratar como
  "recarregar a thread uma vez", não como erro.
- Debounce em memória: `select!` entre `rx.recv()` e `sleep_until(prazo)`; reinicia o prazo a cada evento, limitado por um teto (ex.: 5 s desde o primeiro).

### sqlx 0.9 — `doc_dev/libs/rust/sqlx.md` (2026-10-01)
- Features 0.9: `runtime-tokio` + `tls-rustls` (separadas). Macros `query!`/`query_as!` com `SQLX_OFFLINE`.
- Idempotência: `INSERT ... ON CONFLICT (tenant_id, provider_message_id) DO NOTHING RETURNING id` → `fetch_optional` (None = duplicada).

### serde 1.0 — `doc_dev/libs/rust/serde.md` (2026-10-01)
- `#[serde(default)]`, `rename_all = "camelCase"`, `skip_serializing_if = "Option::is_none"`, enums com `tag`/`content`; útil para os subtipos de mensagem de mídia do webhook.

### tracing 0.1.40 — `doc_dev/libs/rust/tracing.md` (2026-10-01)
- `#[instrument(skip_all, fields(tenant_id = %t, atendimento_id = %a, qtd = tracing::field::Empty), err)]` + `Span::current().record("qtd", n)`.
- Política do projeto: `instrument(err)` só onde todo erro é falha real de infra; repositórios de tenant com `run_in_tenant_transaction` + `#[instrument(skip_all)]`.

### redis 0.25.0 — `doc_dev/libs/rust/redis.md` (2026-10-01)
- `ConnectionManager` (sem `ConnectionManagerConfig`, que só chega em versões posteriores).
- Idempotência como o `webhook_ingress` já faz:
  `redis::cmd("SET").arg(&k).arg("1").arg("NX").arg("EX").arg(ttl).query_async::<_, Option<String>>(&mut con)` → `Some("OK")` = novo.
- Streams com a feature `streams`: `xadd_maxlen`, `xread_options` (`StreamReadOptions::default().group(g, c).block(ms).count(n)`), `xack`, `xpending`, `xclaim_options`.

### aws-sdk-s3 1.x — `doc_dev/libs/rust/aws_sdk_s3.md` (2026-09-06, USAR LOCAL)
- Cliente com `Config::builder()` manual (sem `aws-config`), `region("auto")`, `endpoint_url`, `force_path_style(true)`.
- Presign: `PresigningConfig::expires_in(Duration)`; `put_object().content_type(mime).presigned(cfg)`; `get_object().response_content_type(..).response_content_disposition(..).presigned(cfg)`.
- Exclusivo do `data_storage` (`infrastructure_storage`); apps de negócio pedem presign por RPC.

---

## 3. Serviços externos

### Evolution Go (v2.3.x)

#### Autenticação
Header `apikey: <token da instância>`; respostas embrulhadas em `{ "data": ... }` (o adaptador
`infrastructure_evolution` já desembrulha). Delete por UUID; QR é imagem; `ClientOutdated` = subir a tag.

#### Webhook `messages.upsert`
- Id para deduplicar: `data.key.id` (ou `data.Info.ID` no formato bruto do Go). O `webhook_ingress`
  já grava `webhook:idempotency:{tenant}:{msg_id}` com `SET NX EX 86400` e responde 202 ao duplicado.
- Contato: `data.key.remoteJid` (pode ser `@lid`); número real em `data.key.remoteJidAlt`.
- Mídia: `imageMessage` / `videoMessage` / `audioMessage` (PTT com `ptt: true`) / `documentMessage` /
  `stickerMessage`, com `url` cifrada do CDN do WhatsApp, `mimetype`, `caption`, `fileName`, `mediaKey`.
  O binário NÃO vem pronto: é preciso `POST /message/downloadmedia` logo (as URLs do CDN expiram).

#### `POST /message/downloadmedia`
- Body: `{ "message": <objeto message do webhook> }` → `{ data: { base64, mimetype } }`.
- Uso correto: baixar uma vez no ingresso/worker, gravar no R2 (`data_storage`) e guardar só a chave do objeto; o cliente recebe presigned GET.

#### `POST /send/media`
- Body: `{ number, type: image|video|audio|document, url, caption? }`. `url` precisa ser acessível pela Evolution (presigned GET do R2 serve). Base64 `data:` NÃO CONFIRMADO.
- Resposta: id em `data.id` ou `data.key.id`.
- PTT: WhatsApp espera Ogg/Opus; flag específica de voz NÃO CONFIRMADA na doc — conferir no código-fonte da tag em uso.
- Limite de tamanho NÃO CONFIRMADO (o projeto usa 20 MB / timeout 60 s).

#### `POST /user/avatar`
- Body: `{ number, preview: false }` → `{ data: { profilePictureUrl | url } }`; vazio/erro quando o contato não tem foto ou restringe privacidade.
- URLs de `pps.whatsapp.net` expiram (horas): não persistir a URL; persistir o binário no R2 com TTL de renovação, ou rebuscar sob demanda com cache.

#### Outros eventos
`messages.update` (status `server/delivered/read/played`), `presence.update`. Retries da Evolution sem número documentado — a dedup de 24 h cobre.

### Cloudflare R2

- Presigned: validade 1 s – 7 dias; PUT exige o mesmo `Content-Type` assinado; erros típicos `SignatureDoesNotMatch` (Content-Type/relógio) e 403 por expiração.
- CORS só para Flutter Web; o app Windows não precisa.
- Multipart: parte de 5 MiB a 5 GiB (última pode ser menor), até 10.000 partes; só vale acima de ~100 MiB — áudios, imagens e documentos do chat cabem em PUT simples.
- Sem ACL e sem tagging de objeto.
- Segurança: URL assinada é credencial — nunca em log/span/erro; TTL curto (upload 5–15 min, leitura 15–60 min); chave do objeto sem PII (`tenant/{id}/midia/{uuid}`).

### Redis 7.x (buffer de eventos)

- Dedup: `SET k v NX EX ttl` → `OK` (novo) / nil (duplicado).
- Janela de 5 s por conversa — opções: (a) ZSET `score=ts` + varredura periódica; (b) chave com `EX` reiniciada (expiração de chave é best effort, não serve para disparo); (c) Streams com consumer group (at-least-once).
- Pub/Sub é at-most-once (assinante desconectado perde); Streams guardam histórico e permitem replay.
- Prefixo `tenant:{id}:...`; nunca `KEYS` em produção (usar `SCAN`).

---

## 4. Notas gerais e correções sobre os relatórios coletados

1. Os exemplos Rust dos relatórios de R2/Redis usavam `aws_config::load_from_env` e um método
   `set_nx_ex` — nenhum dos dois existe no projeto/crate. Valem os padrões das seções 2 e 3 acima
   (config manual; `redis::cmd("SET")...NX EX`).
2. O script Lua com `KEYS` sugerido para limpeza por tenant é proibido em produção (bloqueia o Redis).
3. `video_player` não roda no Windows: P2a precisa de `media_kit` (ou `just_audio` + `just_audio_media_kit`) para áudio/vídeo.
4. `super_clipboard` traz dependência nativa em Rust; `pasteboard` é a alternativa sem isso. Decidir na fase P3.
5. O que está marcado NÃO CONFIRMADO (flag de PTT, base64 no `send/media`, limite de tamanho, número de retries do webhook) deve ser conferido no código-fonte da tag da `evolution-go` em uso antes de codar a fase correspondente.
6. Nenhum teste roda na máquina local: validação por `dart analyze`/`cargo check` na CI e no deploy da dev.
