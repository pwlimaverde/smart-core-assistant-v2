# Plano completo — Correções do app Windows (smart-core-tenant)

> Gerado em: 2026-10-01
> Plano canônico: `.context/plans/correcoes-app-windows-flutter.md`
> Documentação auxiliar: [info_aux_correcoes-app-windows-flutter.md](./info_aux_correcoes-app-windows-flutter.md)
> Origem do plano-base: conversa (P1, P1.1, P2a, P2b, P3, P4, P5, P6)
> Restrição: nenhum teste, build, `flutter` ou `cargo` na máquina local. Validação por CI e deploy na dev
> (validar o merge antes numa branch `ci/` temporária: push na `dev` deploya junto com a CI).

---

## 0. Resumo

O app Windows do tenant tem oito defeitos visíveis. A investigação no código mostrou que **metade
deles não é problema de lib do Windows, e sim de servidor**:

- **Mídia não aparece (P2a):** nenhum caminho de leitura gera `url_assinada`. O `GetThread` devolve a
  linha crua de `oraculo_mensagem` e a galeria devolve só a `chave`; o `runtime_api` descarta o bloco
  porque não acha a URL. Além disso a bolha nem lê `mensagem.midia`.
- **Áudio gravado não chega (P2b):** o worker ignora o bloco `midia` do `message.persisted` e envia
  `SendWhatsappMessage` com o texto da mensagem — que, sem legenda, é o **nome do arquivo**
  (`audio.m4a`). O contato recebe um texto, não um áudio.
- **Mensagem pisca no topo (P1):** a cópia local da mensagem tem id negativo e a recarga ordena por
  `id`; numa lista invertida, id negativo é o topo. Cada envio dispara de 4 a 6 recargas sem
  coalescência.
- **Fotos de contato (P6):** o servidor persiste a URL do `pps.whatsapp.net` (expira em horas) e só
  reconsulta após 7 dias; só o cabeçalho do chat pede foto nova.
- **Rolagem do kanban (P5):** o `Listener` do quadro converte toda roda vertical em rolagem horizontal.
- **Ctrl+V de imagem (P3):** o `Clipboard` do Flutter só lê texto; falta plugin e interceptação do atalho.
- **Transferência automática (P4):** casamento exato de string entre a chave devolvida pela IA e a
  chave do fluxo, sem observabilidade que diga por que falhou; depende do plano `ia-engine-jev` (J3).

Nenhuma fase cria método novo de gRPC-Web nem muda `.proto`: as mudanças de contrato são rotas de
envelope internas (`data_storage`, `data_whatsapp`) e campos no JSON de `AtendimentoEvent.payload`.

---

## 1. Ordem de execução e dependências

Ordem revisada: **P1.1-B → P1.1-A → P1 → P1.1-D → P5 → P2a → P2b → P6 → P3**, com **P4 em paralelo**.

```
Trilha chat/realtime        Trilha mídia                     Trilha independente
--------------------        ------------                     -------------------
P1.1-B (servidor)           P2a (servidor+cliente) ------+   P4 (backend/IA, diagnóstico primeiro)
   |                           |                         |      ^ depende de ia-engine-jev J3
P1.1-A (cliente)            P2b (worker+gravador)        |      | (não pode reescrever o motor Jev)
   |                           |                         |
P1 (ordenação/otimista)     P6 (avatar no R2) <----------+  (reusa PresignFiles e content_type do P2a)
   |                           |
P1.1-D (agrupamento)        P3 (Ctrl+V; reusa envio de mídia e o render da bolha do P2a)
   |
P5 (kanban; independente, entra aqui por ser pequeno e só cliente)
```

| Fase | Depende de | Motivo da dependência |
|---|---|---|
| P1.1-B | — | Muda o payload dos eventos que a P1.1-A consome |
| P1.1-A | P1.1-B | Usa `mensagem_id`/`atendimento_id` nos eventos de status e o evento `stream.defasado` |
| P1 | P1.1-A | A ordenação nova roda dentro da recarga coalescida |
| P1.1-D | P1 | Agrupamento só é estável com a ordem corrigida |
| P5 | — | Isolada (só `kanban_page.dart`) |
| P2a | — (recomendado após P1.1-A) | Cria `PresignFiles` e `content_type` no storage; a bolha nova usa a recarga coalescida |
| P2b | P2a | O áudio enviado precisa aparecer na bolha para o aceite |
| P6 | P2a | Reusa `PresignFiles` em lote e `PutFile` com `content_type` |
| P3 | P2a | Reusa o envio de mídia e o render de imagem |
| P4 | ia-engine-jev J3 (coordenação) | O J3 mexe na mesma função de transferência |

### P1.1 — definição das sub-etapas

| Sub-etapa | Conteúdo | Situação |
|---|---|---|
| **P1.1-B** | Servidor: dedupe de eventos realtime por `(tipo, message_id)` com `SET NX EX 5`; ids no payload de status; `Lagged` não derruba o stream; chave do `buffer_mensagens` sem telefone | Nova |
| **P1.1-A** | Cliente: coalescência das recargas do chat (janela 300 ms, teto 1 s), patch local de status, fim do `abrir()` após envio de mídia | Nova |
| **P1.1-C** | Coalescência no `runtime_api` por conexão (janela no servidor antes de enviar ao cliente) | **Descartada** — ver C3 |
| **P1.1-D** | Agrupamento visual das bolhas consecutivas do mesmo remetente | Nova |

---

## 2. Correções aplicadas (vs. análise original)

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| C1 | P1: causa confirmada (ordenação por `id` com pendente negativo) e ampliada: `enviar()` recarrega explicitamente, eventos locais e remotos duplicam `mensagem.enviada`, envio de mídia chama `abrir()` (volta ao `LoadingState`, a tela inteira pisca) | Três fontes de recarga somam com o realtime | `chat_controller.dart:132,298,361-379`; `chat_page.dart:433`; `local_engine_gateway.dart:290,532-551`; `local_engine/src/lib.rs:187` |
| C2 | P1.1-B não cria buffer: `buffer_mensagens.rs` **já existe** (N8.5/E2, agrega rajada para o bot, `SET NX EX`, drenagem em Lua). A fase passa a ser dedupe/coalescência dos **eventos realtime** reaproveitando o mesmo padrão | Evitar duplicar o módulo e conflitar com a resposta única por rajada | `server/apps/worker/src/buffer_mensagens.rs` |
| C3 | P1.1-C explicitado e **descartado** | Uma janela no `runtime_api` atrasaria todos os eventos de todos os clientes do tenant (o broadcast é por tenant) e duplica o que A+B resolvem; fica como contingência se a métrica da P1.1-A mostrar mais de 2 recargas por mensagem | `runtime_api/src/realtime.rs`, `grpc_web.rs:9395-9409` |
| C4 | P2a não é só "player no Windows": **o servidor nunca assina a URL de leitura**. O comentário de `midia_do_item` ("a `url_assinada` vem pronta do `data_postgres`") está errado | `handler_get_thread` serializa `Mensagem` crua; `handler_listar_midias_atendimento` devolve só `chave` | `grpc_web.rs:470-502,8354,8687`; `data_postgres/src/main.rs:2122-2156,4847-4899` |
| C5 | P2a: o pipeline de mídia de entrada grava o ponteiro **só depois da IA**, sem `mimetype_midia`/`tamanho_midia`, sem `Content-Type` no objeto e sem evento realtime | A mensagem chega ao chat antes do anexo existir e ninguém avisa quando ele fica pronto | `worker/src/main.rs:3021-3269`; `mensagens.rs:712-738`; `data_storage/src/main.rs:391` |
| C6 | `video_player` não roda no Windows → `media_kit`. A doc da central `media_kit.md` tem dois pontos a corrigir: (a) o libmpv não é "baixado automaticamente em runtime" — vem de um pacote `media_kit_libs_*` no build; (b) a linha "Web ❌" contradiz o README oficial e precisa ser conferida, porque o `operacional_module` também compila para Web | Evitar build quebrado na CI Windows/Web | `doc_dev/libs/flutter/media_kit.md` §2.2, §7; info_aux §1 |
| C7 | P2b: causa principal é do **worker**, não do gravador. O cliente tem problemas secundários: `start()` sem `try/catch`, `AudioRecorder` sem `dispose()`, sem `isEncoderSupported` | O contato recebe "audio.m4a" como texto | `worker/src/main.rs:4135-4254`; `data_postgres/src/adapters/atendimento.rs:927-931,981-995`; `chat_page.dart:352,373-400` |
| C8 | PTT (nota de voz) fica para a segunda etapa da P2b: primeiro o áudio sai como `audio` (m4a/aacLc), depois se confere no código-fonte da tag da `evolution-go` a flag de voz e o contêiner do encoder `opus` no Windows | Ambos marcados NÃO CONFIRMADO na info_aux | info_aux §1 (record), §3 (`send/media`) |
| C9 | Sanitização: `send_media`, `send_text` e `get_profile_picture` usam `#[instrument(skip(self, token...))]` **sem** `skip_all` — o `to_number`/`number` e a `media_url` assinada entram como campos do span | Viola 08 §4.1 (telefone completo e credencial em trace) | `infrastructure_evolution/src/provider.rs:445,523,762` |
| C10 | P6: causa é a persistência da URL tokenizada do `pps.whatsapp.net` com cache de 7 dias, e só o cabeçalho do chat pede foto nova (`_fotoQuebrou`); cartões do kanban ficam com a URL morta | URL do CDN expira em horas | `grpc_web.rs:6389-6464`; `worker/src/main.rs:1590-1611`; `chat_page.dart:179-185`; info_aux §3 (`/user/avatar`) |
| C11 | P5: causa confirmada — `_RolagemDoQuadroState._rodar` faz `jumpTo` horizontal com o `dy` da roda sem passar pelo `PointerSignalResolver`, então a roda vertical sobre a coluna também arrasta o quadro de lado | `Listener.onPointerSignal` não participa da resolução de quem consome o evento | `kanban_page.dart:1843-1875` |
| C12 | P3: `Clipboard.getData` só lê texto; o `EditableText` registra suas próprias `Actions`, então sobrescrever `PasteTextIntent` num ancestral não funciona. Interceptar com `Focus.onKeyEvent` em volta do campo e deixar a colagem de texto seguir | Fluxo de colar texto não pode quebrar | info_aux §1 (super_clipboard); `chat_page.dart:1077-1086` |
| C13 | Redis 0.25 não tem `set_nx_ex`; usar `redis::cmd("SET")...NX EX` (padrão de `buffer_mensagens.rs` e do `webhook_ingress`); nunca `KEYS` | Exemplos dos relatórios coletados não compilam | info_aux §2 (redis), §4.1-2 |
| C14 | aws-sdk-s3 com `Config::builder()` manual; presign GET ganha `response_content_type`; assinatura em lote (`PresignFiles`) no `data_storage`, porque o `runtime_api` não importa `infrastructure_storage` | Arquitetura (apps de negócio só via RPC) e custo de N chamadas por página | info_aux §2 (aws-sdk-s3); `architecture.md:69,145`; `infrastructure_storage/src/lib.rs:205-225` |
| C15 | P4: hipóteses ancoradas no código e **diagnóstico antes de codar**; a correção mínima (normalizar a chave e instrumentar) não toca o motor Jev | O plano `ia-engine-jev` (J3) já mexe na transferência | `worker/src/main.rs:534-643,1091-1127`; `.context/plans/ia-engine-jev.md` (J3) |
| C16 | `mensagem.status_atualizado` sai sem `atendimento_id`/`mensagem_id`: os ticks não atualizam com a conversa aberta | O cliente filtra por `atendimento_id` | `worker/src/main.rs:4102-4124`; `atendimento_evento.dart:22-27` |
| C17 | URL assinada muda a cada recarga → `Image.network` baixa de novo e a imagem pisca. O cliente mantém a mídia antiga enquanto a URL dela estiver fresca (mesmo objeto, idade < 80% do TTL) | Efeito colateral de P2a sobre P1 | `midia_mensagem.dart:28-37`; `avatar_do_contato.dart:56` |
| C18 | `while let Ok(event) = broadcast_rx.recv()` encerra o stream no `Lagged` → o cliente reconecta e recarrega tudo | info_aux §2 (tokio): `Lagged` = "recarregar uma vez", não erro | `grpc_web.rs:9405` |
| C19 | A chave do `buffer_mensagens` contém o telefone (`tenant:{t}:buf:{sender}`); nome de chave aparece em `SLOWLOG`/`MONITOR` | 08 §4.1 (telefone completo) | `buffer_mensagens.rs:87-93` |

---

## 3. Fases

Convenção de log no Flutter: `developer.log(msg, name: 'operacional_module.<área>', level: n)` com
`500` = debug, `800` = info, `900` = aviso, `1000` = erro. Nunca conteúdo de mensagem, telefone, nome
de arquivo ou URL assinada.

Convenção Rust: `#[tracing::instrument(skip_all, fields(...))]` com `tenant_id`, `atendimento_id`,
`trace_id` (via `traceparent`) e `error_code` (`tracing::field::Empty` + `Span::record`).
`instrument(err)` só onde todo erro é falha real de infra; repositórios de tenant via
`run_in_tenant_transaction` + `#[instrument(skip_all)]`. Auditoria pelo `audit_logger` (publicação
assíncrona via `transport::bus` → `data_postgres`, `audit_log` com timestamp UTC, `user_id` do
`RequestContext`, `ip_address`, `user_agent`, `event_type`, descrição sem segredo).

---

### P1.1-B — Dedupe e enriquecimento dos eventos realtime (servidor)

- **Agente:** backend-specialist
- **Branch:** `feature/p1-1-b-eventos-realtime-dedupe`

**Objetivo.** Cada mudança de uma mensagem gera no máximo um evento realtime por tipo, com os ids
que o cliente precisa para aplicar sem recarregar; o stream não cai por atraso do assinante.

**Causa raiz confirmada.**
- `mensagem.status_atualizado` só leva `message_id_whatsapp` e `status` (`worker/src/main.rs:4102-4124`);
  sem `atendimento_id` o chat aberto ignora, sem `mensagem_id` não há como corrigir o tick localmente.
- Publicações diretas com `redis::cmd("PUBLISH")` espalhadas (`main.rs:615,2089,3992,4103`) sem dedupe;
  reentrega do consumer group (at-least-once) republica o mesmo evento.
- `stream_atendimentos` sai do laço no primeiro `RecvError::Lagged` (`grpc_web.rs:9405`).
- Chave do buffer do bot com telefone (`buffer_mensagens.rs:87-93`).

**Arquivos afetados.**
`server/apps/worker/src/main.rs` (`publicar_realtime`, `processar_status_mensagem`, `processar_mensagem_recebida`),
`server/apps/worker/src/buffer_mensagens.rs`, `server/apps/runtime_api/src/grpc_web.rs` (`stream_atendimentos`),
`server/apps/data_postgres/src/main.rs` (resposta de `UpdateMessageStatus` passa a devolver `mensagem_id` e `atendimento_id`).

**Passos.**
1. `UpdateMessageStatus` (data_postgres) devolve `{ mensagem_id, atendimento_id }` da linha atualizada
   (o `UPDATE ... RETURNING id, atendimento_id` dentro de `run_in_tenant_transaction`).
2. Criar `publicar_realtime_unico` no worker e usar nos eventos de mensagem
   (`mensagem.recebida`, `mensagem.status_atualizado`, `mensagem.midia_disponivel` da P2a):

```rust
/// Publica no realtime só a primeira ocorrência de (evento, mensagem) na janela.
/// Chave sem PII: só ids. Redis fora = publica assim mesmo (o evento vale mais que o dedupe).
async fn publicar_realtime_unico(
    state: &AppState,
    tenant_id: Uuid,
    tipo: &str,
    discriminador: &str, // ex.: "{mensagem_id}" ou "{mensagem_id}:delivered"
    payload: serde_json::Value,
) {
    if let Some(ref bus) = state.bus_conn {
        let mut con = bus.clone();
        let chave = format!("tenant:{tenant_id}:rt:{tipo}:{discriminador}");
        let novo: Option<String> = redis::cmd("SET")
            .arg(&chave).arg("1").arg("NX").arg("EX").arg(5)
            .query_async(&mut con)
            .await
            .unwrap_or(Some("OK".into()));
        if novo.is_none() {
            tracing::debug!(evento = tipo, "evento realtime repetido na janela; descartado");
            return;
        }
    }
    publicar_realtime(state, tenant_id, tipo, payload).await;
}
```

3. Payload de `mensagem.status_atualizado` passa a `{ atendimento_id, mensagem_id, status }`
   (mantém `message_id_whatsapp` para compatibilidade com clientes antigos durante o deploy).
4. Conferir o eco `fromMe` do `messages.upsert`: quando a persistência devolver "já existia"
   (`ON CONFLICT DO NOTHING` → `None`), não publicar `mensagem.recebida`.
5. `stream_atendimentos`: tratar `Lagged` sem encerrar:

```rust
loop {
    match broadcast_rx.recv().await {
        Ok(ev) => { if tx.send(Ok(ev)).await.is_err() { break; } }
        // O assinante atrasou: avisa o cliente para recarregar UMA vez em vez de derrubar o stream.
        Err(broadcast::error::RecvError::Lagged(n)) => {
            tracing::warn!(tenant_id = %tenant_uuid, perdidos = n, "stream realtime defasado");
            let aviso = AtendimentoEvent {
                event_type: "stream.defasado".into(),
                tenant_id: tenant_uuid.to_string(),
                payload: serde_json::json!({ "perdidos": n }).to_string(),
            };
            if tx.send(Ok(aviso)).await.is_err() { break; }
        }
        Err(broadcast::error::RecvError::Closed) => break,
    }
}
```

6. `buffer_mensagens`: `chave_buffer`/`chave_timer` usam `sha256(sender)` truncado (16 hex) no lugar do
   telefone. Deploy perde no máximo a agregação de uma rajada em voo (aceito; a mensagem já está persistida).

**Observabilidade & Auditoria.**
- a) Span `realtime.publicar` (`skip_all`, `tenant_id`, `evento`, `resultado = publicado|duplicado|redis_fora`);
  contador `smartcore_realtime_publicado_total{evento,resultado}` no padrão de `observability/usage_metrics.rs`
  (`tenant_id` nunca como label). `stream.defasado` em `WARN` com `tenant_id` e `perdidos`. Span `buffer.janela`
  do bot com `qtd_eventos` e `motivo_flush` (timer|vazio) e `smartcore_buffer_flush_total{motivo}`.
- b) **Sem evento de auditoria**: eventos realtime e status de entrega são estado trivial de alto volume
  (05 §10, "fora da trilha por decisão"); o status já é auditado como `mensagem.confirmada` no worker.
  `stream.aberto`/`stream.fechado` seguem como estão.
- c) Chaves Redis só com ids e hash; payload realtime sem texto além do que já trafegava; o
  `discriminador` nunca contém telefone. Nada de payload em log.

**Critérios de aceite (dev).**
- Com o chat aberto, enviar uma mensagem e ver os ticks mudarem sozinhos (enviado → entregue → lido).
- No Tempo/Loki, para uma mensagem, um único `mensagem.status_atualizado` por status.
- Forçar `Lagged` (teste unitário com canal de capacidade 1) devolve `stream.defasado` e o stream continua.
- Testes na CI: unidade de `publicar_realtime_unico` (chave sem telefone), `stream.defasado`, hash de `chave_buffer`.

**Riscos.** Clientes antigos ainda filtram por `atendimento_id` ausente (ok, ignoram); TTL de 5 s pode
descartar um status legítimo repetido com a mesma chave — por isso o status entra no discriminador.

---

### P1.1-A — Coalescência das recargas do chat (cliente)

- **Agente:** frontend-specialist
- **Branch:** `feature/p1-1-a-coalescencia-chat`

**Objetivo.** No máximo uma recarga da thread por rajada de eventos; status de entrega aplicado sem
recarga; o envio de mídia não volta a tela para o spinner.

**Causa raiz confirmada.** `_aoReceberEvento` chama `_recarregarThread()` para todo evento do
atendimento aberto (`chat_controller.dart:297-299`); `enviar()` recarrega explicitamente (`:132`); o
`LocalEngineGateway.streamAtendimentos` junta o stream do motor local com o remoto
(`local_engine_gateway.dart:532-551`) e os dois emitem `mensagem.enviada` para o mesmo envio
(`local_engine/src/lib.rs:187`; `grpc_web.rs:9292`); `_enviarMidia` chama `_controller.abrir()`
(`chat_page.dart:433`), que emite `LoadingState`.

**Arquivos afetados.** `presentation/controllers/chat_controller.dart`, `chat_state.dart`,
`domain/model/mensagem_thread.dart` (`copyWith(statusEnvio, entregueEm, lidaEm)`),
`presentation/pages/chat_page.dart`, `test/.../controllers/chat_controller_test.dart`.

**Passos.**
1. Agendador único de recarga (janela 300 ms, teto 1 s desde o primeiro pedido):

```dart
static const _janela = Duration(milliseconds: 300);
static const _teto = Duration(seconds: 1);
Timer? _recargaAgendada;
DateTime? _primeiroPedido;

/// Junta pedidos de recarga em rajada; o teto evita adiar para sempre sob fluxo contínuo.
void _agendarRecarga(String motivo) {
  final agora = DateTime.now();
  _primeiroPedido ??= agora;
  final restante = _teto - agora.difference(_primeiroPedido!);
  _recargaAgendada?.cancel();
  _recargaAgendada = Timer(restante < _janela ? restante : _janela, () {
    _primeiroPedido = null;
    if (isClosed) return;
    developer.log('recarga da thread', name: 'operacional_module.chat', level: 500, error: 'motivo=$motivo');
    unawaited(_recarregarThread());
  });
}
```

2. `_aoReceberEvento`: `mensagem.status_atualizado` com `mensagem_id` presente → patch local
   (`copyWith`) e **sem** recarga; `stream.defasado` → `_agendarRecarga('defasado')`; demais eventos do
   atendimento aberto → `_agendarRecarga(evento.tipo)`.
3. `enviar()` usa `_agendarRecarga('envio')` em vez de `await _recarregarThread()`.
4. Novo método público `recarregar()` (agenda); `_enviarMidia` na página chama `recarregar()` no lugar de `abrir()`.
5. `_recarregarThread` preserva a `midia` já carregada quando é o mesmo objeto e a URL ainda está fresca (C17):

```dart
/// Mantém a URL antiga enquanto válida: URL nova = download novo = imagem piscando.
MidiaMensagem? _midiaEstavel(MidiaMensagem? antiga, MidiaMensagem? nova) {
  if (antiga == null || nova == null) return nova;
  final mesmoObjeto = Uri.parse(antiga.urlAssinada).path == Uri.parse(nova.urlAssinada).path;
  final fresca = DateTime.now().difference(antiga.obtidaEm) < const Duration(minutes: 12); // TTL 15 min
  return mesmoObjeto && fresca ? antiga : nova;
}
```
   (`obtidaEm` é campo novo de `MidiaMensagem`, preenchido pelo gateway na conversão; não serializado.)
6. `close()` cancela `_recargaAgendada`; todo `emit` em callback assíncrono protegido por `isClosed`.
7. `connectivity_plus`: se o gateway recarrega ao voltar a rede, passar pelo mesmo agendador (doc central: debounce antes de recarregar).

**Observabilidade & Auditoria.**
- a) Debug (`level: 500`) por recarga efetiva com `motivo` (tipo de evento), e contador em memória
  `recargasPorEnvio` logado em debug ao fim da janela — é o instrumento do aceite. Falhas de recarga em
  aviso (`900`) só com o tipo do erro.
- b) **Sem evento de auditoria**: leitura da conversa no cliente, sem mudança de estado.
- c) Nunca logar `payload`, `conteudo`, `urlAssinada` ou `nomeArquivo`; `MidiaMensagem.toString()` já omite a URL — manter.

**Critérios de aceite (dev).**
- Log debug mostra **1 recarga** por mensagem de texto enviada (hoje 4–6) e **0** por mudança de tick.
- Enviar anexo não mostra o spinner de tela cheia.
- Imagem já exibida não pisca quando chega mensagem nova.
- CI: testes de `chat_controller_test.dart` com `fakeAsync` (rajada de 5 eventos → 1 chamada a `GetThreadUsecase`; status → 0 chamadas).

**Riscos.** Atraso perceptível de até 300 ms na mensagem recebida (aceito); teto evita fome sob rajada contínua.

---

### P1 — Mensagem pendente no lugar certo (cliente)

- **Agente:** frontend-specialist
- **Branch:** `feature/p1-ordem-mensagem-pendente`

**Objetivo.** A mensagem enviada aparece embaixo, no lugar definitivo, e não salta quando o sync a
promove ao id do servidor.

**Causa raiz confirmada.** `_recarregarThread` ordena por `a.id.compareTo(b.id)`
(`chat_controller.dart:374-375`); a cópia local tem id negativo (`local_engine_gateway.dart:285-290`,
`pendentes_locais.dart:5-9`); a lista é `reverse: true` e lê `mensagens[length - 1 - index]`
(`chat_page.dart:929-954`) → o id negativo é desenhado no topo até a promoção, quando pula para baixo.
Os itens não têm `key`, então a troca de id reconstrói a bolha na posição seguinte.

**Arquivos afetados.** `chat_controller.dart`, `data/gateways/pendentes_locais.dart`, `chat_page.dart`,
`test/.../pendentes_locais_test.dart`, `chat_controller_test.dart`.

**Passos.**
1. Ordenação única para exibição (usada também em `abrir` e `carregarAntigas`):

```dart
/// Confirmadas pela ordem do servidor (id); pendentes locais (id < 0) sempre no fim,
/// pela ordem em que foram escritas. Não ordenar tudo por horário: o relógio local e o
/// do servidor divergem, e a pendente é, por definição, a mais nova.
List<MensagemThread> ordenarParaExibir(Iterable<MensagemThread> todas) {
  final confirmadas = todas.where((m) => m.id > 0).toList()..sort((a, b) => a.id.compareTo(b.id));
  final pendentes = todas.where((m) => m.id < 0).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return [...confirmadas, ...pendentes];
}
```

2. `ListView.builder` com `key: ValueKey(mensagem.id)` no item (a promoção troca o id, mas a posição é a mesma: sem salto).
3. Garantir que `semAsJaEnviadas` continue removendo a pendente quando a remota correspondente chega
   (sem mudança de regra; só teste novo com pendente + remota na mesma recarga).

**Observabilidade & Auditoria.**
- a) Nada novo em produção; debug (`500`) quando uma pendente for descartada por casar com remota (só contagem).
- b) **Sem evento de auditoria**: ordenação de exibição.
- c) `semAsJaEnviadas` compara texto em memória; nunca logar o texto comparado.

**Critérios de aceite (dev).** Enviar 3 mensagens seguidas no app Windows: cada uma aparece embaixo,
na ordem, e não se move quando o relógio vira tick. Com a rede desligada, a pendente fica embaixo; ao
religar, continua no mesmo lugar. CI: teste unitário de `ordenarParaExibir`.

**Riscos.** Pendente antiga de outra sessão (falha permanente de sync) fica eternamente no fim — já é o
comportamento atual de "não enviada"; fora do escopo.

---

### P1.1-D — Agrupamento visual das bolhas (cliente)

- **Agente:** frontend-specialist
- **Branch:** `feature/p1-1-d-agrupamento-bolhas`

**Objetivo.** Mensagens consecutivas do mesmo remetente (até 2 min entre elas, mesmo dia) formam um
bloco: espaçamento menor, cantos ajustados, horário e ticks só na última, selo de IA só na primeira.

**Causa raiz.** Não é defeito: a bolha hoje não conhece vizinhas (`chat_message_bubble.dart:36-91`,
margem fixa `AppSpacing.xs`). O `itemBuilder` já calcula `anterior` (`chat_page.dart:953-957`).

**Arquivos afetados.** `chat_page.dart` (itemBuilder), `chat_message_bubble.dart`,
`test/.../chat_message_bubble_test.dart`.

**Passos.**
1. Enum `PosicaoNoGrupo { unica, primeira, meio, ultima }` calculada no itemBuilder com `anterior` e `proxima`:

```dart
/// Mesmo bloco = mesmo lado da conversa (bot e atendente contam separados), mesmo dia e até 2 min.
bool mesmoBloco(MensagemThread? a, MensagemThread? b) =>
    a != null && b != null && a.remetente == b.remetente &&
    DateUtils.isSameDay(a.timestamp, b.timestamp) &&
    b.timestamp.difference(a.timestamp).abs() <= const Duration(minutes: 2);
```

2. `ChatMessageBubble(posicao: ...)`: margem vertical 1 px dentro do bloco e `AppSpacing.xs` entre blocos;
   `BorderRadius` com canto reduzido no lado do remetente para `meio`/`ultima`; rodapé (hora + ticks)
   só em `unica`/`ultima`; `_IndicadorIa` só em `unica`/`primeira`.
3. Separador de dia continua tendo precedência (quebra o bloco).

**Observabilidade & Auditoria.** a) Nenhum log (render puro). b) **Sem evento de auditoria**. c) Nada sensível tocado.

**Critérios de aceite (dev).** Contato manda 3 mensagens em sequência: aparecem como bloco, hora só na
última. Bot responde em seguida: bloco separado. CI: teste de widget com 3 mensagens e asserção de que só uma mostra horário.

**Riscos.** Mensagem com ticks diferentes dentro do bloco: o tick do meio some — aceitar (WhatsApp Web faz igual) ou mostrar ticks em todas; decidir no review visual.

---

### P5 — Rolagem vertical das colunas do kanban (cliente)

- **Agente:** frontend-specialist
- **Branch:** `feature/p5-rolagem-colunas-kanban`

**Objetivo.** A roda do mouse sobre uma coluna rola a coluna; o quadro rola de lado com Shift+roda,
trackpad horizontal ou barra de rolagem.

**Causa raiz confirmada.** `_RolagemDoQuadroState._rodar` (`kanban_page.dart:1843-1854`) é
`Listener.onPointerSignal`, que recebe o sinal de qualquer ponto do quadro e aplica `scrollDelta.dy` na
rolagem **horizontal** com `jumpTo`, sem passar pelo `GestureBinding.instance.pointerSignalResolver`.
O `ListView.separated` da coluna (`:1170`) também rola, mas o quadro escorrega para o lado no mesmo
gesto — para o usuário, "a coluna não rola".

**Arquivos afetados.** `presentation/pages/kanban_page.dart`, `test/.../pages/kanban_page_test.dart`.

**Passos.**

```dart
void _rodar(PointerSignalEvent evento) {
  if (evento is! PointerScrollEvent || !_rolagem.hasClients) return;
  // Roda vertical é da coluna; o quadro só toma o dy com Shift. dx (trackpad) é sempre do quadro.
  final shift = HardwareKeyboard.instance.isShiftPressed;
  final delta = evento.scrollDelta.dx != 0 ? evento.scrollDelta.dx : (shift ? evento.scrollDelta.dy : 0.0);
  if (delta == 0) return;
  // Pelo resolver: se uma rolagem mais interna já reivindicou o evento, o quadro não mexe.
  GestureBinding.instance.pointerSignalResolver.register(evento, (e) {
    final p = _rolagem.position;
    final destino = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (destino != p.pixels) _rolagem.jumpTo(destino);
  });
}
```

2. Cada coluna com `ScrollController` próprio e `Scrollbar(thumbVisibility: true)` (desktop mostra onde rolar).
3. Conferir que a coluna recebe altura limitada (Row `stretch` dentro do `SingleChildScrollView`
   horizontal + `Expanded` no `ListView`) com teste de widget que rola a coluna por `PointerScrollEvent`.

**Observabilidade & Auditoria.** a) Sem log de servidor; no máximo debug de layout em desenvolvimento.
b) **Sem evento de auditoria**. c) Nenhum dado tocado.

**Critérios de aceite (dev).** Coluna com 20+ cartões: roda rola a coluna e o quadro não se move;
Shift+roda move o quadro; arrastar cartão até a borda ainda rola o quadro (auto-rolagem do arrasto
intacta). CI: teste em `kanban_page_test.dart` com `tester.sendEventToBinding(PointerScrollEvent)`.

**Riscos.** Quem já usava roda para andar no quadro precisa de Shift — mitigado pela barra visível; registrar no changelog.

---

### P2a — Mídia na bolha: imagem, áudio, vídeo e documento (servidor + cliente)

- **Agentes:** backend-specialist (servidor), frontend-specialist (cliente); devops-specialist apoia o build Windows/Web
- **Branch:** `feature/p2a-midia-na-bolha` (servidor e cliente em PRs separados, servidor primeiro)

**Objetivo.** Toda mensagem com anexo mostra o anexo: imagem inline, áudio com player, vídeo com
player, documento com nome/tamanho e "abrir". A galeria da ficha volta a listar.

**Causa raiz confirmada.**
1. **Leitura sem URL assinada** — `handler_get_thread` serializa `Vec<Mensagem>` (`data_postgres/src/main.rs:2150-2153`),
   que não tem bloco `midia`; `handler_listar_midias_atendimento` devolve `chave` sem URL (`:4878-4890`);
   `midia_do_item` exige `midia.url_assinada` e devolve `None` (`grpc_web.rs:475-480`). Nenhum `PresignFile`
   no caminho de leitura. O `SELECT` da thread nem traz `midia_purgada_em` (`mensagens.rs:284-286`).
2. **Pipeline de entrada incompleto** — `processar_pipeline_midia` grava o ponteiro só no fim, depois da IA
   (`worker/src/main.rs:3233-3246`), sem `mimetype_midia`/`tamanho_midia`/nome (`mensagens.rs:723-728`), via
   `PutFile` sem `Content-Type` (`:3099-3104`), e não publica nada ao concluir.
3. **Bolha não renderiza `midia`** — `chat_message_bubble.dart` só desenha texto, extras e `resumoMidia`.
4. **Sem player no Windows** — o módulo não tem lib de áudio/vídeo; `video_player` não roda no Windows (info_aux §1, §4.3).

**Arquivos afetados.**
Servidor: `server/crates/infrastructure_storage/src/lib.rs` (`put` com `content_type`; `presign` com
`response_content_type`), `server/apps/data_storage/src/main.rs` (rotas `PutFile`, `PresignFile`, nova `PresignFiles`),
`server/crates/infrastructure_postgres/src/atendimentos/mensagens.rs` (SELECT com `midia_purgada_em`;
`anexar_analise_midia` com mimetype/tamanho/nome), `server/apps/data_postgres/src/main.rs`
(`handler_get_thread` monta bloco `midia`; `AnexarAnaliseMidia` aceita os campos novos),
`server/apps/runtime_api/src/grpc_web.rs` (`get_thread`, `listar_midias_atendimento`: assinatura em lote),
`server/apps/worker/src/main.rs` (`processar_pipeline_midia`).
Cliente: `chat_message_bubble.dart` (+ widgets `_MidiaDaBolha`, `_PlayerDeAudio`, `_CartaoDeDocumento`),
`midia_mensagem.dart` (`obtidaEm`), `atendimento_remote_gateway.dart` (`_paraMidia` preenche `obtidaEm`),
`operacional_module/pubspec.yaml`, `clients/apps/smart-core-tenant/pubspec.yaml` e `lib/main_dev.dart`/`main_prod.dart`
(`MediaKit.ensureInitialized()`), `doc_dev/libs/flutter/media_kit.md` (corrigir C6).

**Passos — servidor.**
1. `infrastructure_storage`: `put(.., content_type: Option<&str>)` e `presign(.., response_content_type: Option<&str>)`:

```rust
let mut req = self.client.get_object().bucket(&self.bucket).key(&key);
if let Some(ct) = response_content_type {
    // O player e o navegador decidem pelo Content-Type da resposta, não pela extensão.
    req = req.response_content_type(ct);
}
let url = req.presigned(PresigningConfig::expires_in(Duration::from_secs(ttl))?).await?;
```
   Trocar o `instrument` de `presign` para não registrar o retorno (já não registra; manter `skip(self)` e
   nunca `ret`).
2. `data_storage`: rota `PresignFiles` `{ itens: [{ file_name, content_type? }], expires_in }` →
   `{ urls: [{ file_name, url }] }`, com teto de 100 itens; `PutFile` aceita `content_type` opcional.
   Rotas de envelope internas: **não** vão para `AdminService`/gRPC-Web.
3. `data_postgres`: SELECT da thread inclui `midia_purgada_em`; `handler_get_thread` acrescenta a cada item
   com `arquivo_midia` e sem purga o bloco `midia: { chave, kind, mimetype, filename, size_bytes, is_ptt }`
   (`kind` pelo prefixo do `mimetype_midia`, e na falta dele pelo `tipo`: `imageMessage`→`image` etc.).
   `handler_listar_midias_atendimento` devolve `kind` e `mimetype` também.
4. `runtime_api`: em `get_thread` e `listar_midias_atendimento`, uma chamada `PresignFiles` por página
   (TTL 900 s) e preenche `url_assinada` antes de `midia_do_item`; corrigir o comentário de `midia_do_item`.
   Falha do storage → mensagens saem sem `midia` (texto continua) e `error_code = "presign_falhou"`.
5. Worker, `processar_pipeline_midia`: depois do `PutFile` (agora com `content_type: mime`), chamar
   `AnexarAnaliseMidia` **já** com `arquivo_midia`, `mimetype`, `tamanho` (bytes decodificados) e `nome`
   (`documentMessage.fileName`), publicar `mensagem.midia_disponivel` `{ atendimento_id, mensagem_id }` via
   `publicar_realtime_unico`, e só então seguir para a IA (a segunda chamada grava só análise/resumo).
6. Backfill opcional (SQL na dev, sem migração estrutural): `mimetype_midia` a partir de `tipo` para
   mensagens antigas com `arquivo_midia` e mimetype nulo.

**Passos — cliente.**
1. Lib: `media_kit` (+ `media_kit_video` para vídeo e o pacote de binários `media_kit_libs_video`, ou
   `media_kit_libs_windows_video` — conferir nomes e versão no pub.dev ao instalar). Documento: `url_launcher`
   (doc na central). Justificativa: único player que cobre áudio ogg/opus e vídeo no Windows; imagem não precisa de lib.
2. Bolha:

```dart
Widget _midia(MidiaMensagem m) => switch (m.tipo) {
  // URL vencida vira pedido de recarga, não ícone quebrado: a próxima recarga traz URL nova.
  TipoMidia.imagem => Image.network(m.urlAssinada, fit: BoxFit.cover,
      errorBuilder: (_, _, _) { aoMidiaExpirada?.call(); return const _MidiaIndisponivel(); }),
  TipoMidia.audio => _PlayerDeAudio(midia: m, aoFalhar: aoMidiaExpirada),
  TipoMidia.video => _CartaoDeVideo(midia: m), // abre um diálogo com Video(controller:)
  TipoMidia.documento => _CartaoDeDocumento(midia: m), // launchUrl(.., mode: LaunchMode.externalApplication)
};
```
   O `conteudo` da mensagem de mídia só aparece quando é legenda (diferente de `nomeArquivo`).
3. `_PlayerDeAudio`: um `Player` por bolha, criado no primeiro "play" (não no build) e liberado no `dispose`;
   escuta `player.stream.error` para avisar falha.
4. `aoMidiaExpirada` → `ChatController.recarregar()` no máximo uma vez por mensagem (flag local).
5. `MediaKit.ensureInitialized()` nos `main_*.dart` do app; para a compilação Web do admin, import
   condicional se o `media_kit` não compilar para Web (ver risco).
6. Corrigir `doc_dev/libs/flutter/media_kit.md` (C6) na mesma branch.

**Observabilidade & Auditoria.**
- a) Rust: span `storage.presign_lote` (`skip_all`, `tenant_id`, `qtd`, `ttl`, `error_code`); no worker,
  `midia.pipeline` já existe — acrescentar `ponteiro_ms` (tempo até o ponteiro) e `resultado`. `instrument(err)`
  só em `infrastructure_storage` (erro = falha real do S3). Flutter: aviso (`900`) quando o player falha,
  com `tipo` e `mimetype`; debug (`500`) quando pede recarga por URL vencida.
- b) **Sem evento de auditoria novo**: leitura de mídia é consulta de alto volume (05 §10) e não há trilha
  de acesso existente a estender — decisão intencional. A chegada continua auditada em `midia.analisada`.
- c) **URL assinada nunca em log/span/erro** (contém `X-Amz-Signature`); `base64` e `mediaKey` fora do log
  (`processar_pipeline_midia` já usa `skip_all` — manter); `nomeArquivo`/`filename` nunca em log (PII);
  chave do objeto sem PII (`media/{tenant}/{instance}/{tipo}/{hash}` atende).

**Critérios de aceite (dev).**
- Contato manda imagem, áudio (PTT), vídeo e PDF: os quatro aparecem na bolha em até ~5 s, sem reabrir a conversa.
- Áudio e vídeo tocam no app Windows; PDF abre no visualizador do sistema.
- Galeria da ficha lista as quatro mídias.
- Deixar a conversa aberta 20 min e tocar o áudio: funciona (recarga transparente pela URL vencida).
- CI: Rust — `handler_get_thread` monta `midia` e omite purgada; `PresignFiles` valida teto e `file_name`;
  pipeline grava ponteiro antes da IA (rotas mock já usadas em `worker/src/main.rs:5187+`). Dart — teste de
  widget da bolha por tipo (sem tocar mídia).

**Riscos.** `media_kit` aumenta o instalador (libmpv) e baixa binários no build CMake — a CI Windows
precisa de rede nesse passo; suporte Web a confirmar; o `operacional_module` tem `test` de widget que não
pode inicializar o player (criar o `Player` só no primeiro play resolve). R2 sem CORS: irrelevante para Windows,
relevante se o admin Web tocar mídia (CORS só para o domínio do painel).

---

### P2b — Gravação e envio de áudio (servidor + cliente)

- **Agentes:** backend-specialist (worker), frontend-specialist (gravador)
- **Branch:** `feature/p2b-envio-de-audio`

**Objetivo.** O áudio gravado no app chega ao WhatsApp do contato como áudio (e, na segunda etapa, como
nota de voz), e aparece na bolha do atendente.

**Causa raiz confirmada.**
1. **Servidor (principal):** `processar_mensagem_persistida` sempre chama `SendWhatsappMessage` com
   `conteudo` (`worker/src/main.rs:4202-4229`) e ignora `payload.midia`, que o `data_postgres` publica
   justamente "para o worker chamar SendWhatsappMedia" (`adapters/atendimento.rs:986-994`). Sem legenda,
   `conteudo` é o nome do arquivo (`:927-931`): o contato recebe o texto "audio.m4a". `send_media` não envia
   nome de arquivo nem flag de voz (`provider.rs:540-548`) e registra `to_number`/`media_url` no span (C9).
2. **Cliente:** `_alternarGravacao` não trata exceção de `start()`, nunca chama `_gravador.dispose()`, usa
   `RecordConfig()` sem checar encoder (`chat_page.dart:352,389-400`). Default `aacLc` → `.m4a`/`audio/mp4`,
   aceito pelo servidor (`infrastructure_storage/src/midia.rs:127,207`) mas não é PTT no WhatsApp.

**Arquivos afetados.** `server/apps/worker/src/main.rs`, `server/apps/data_postgres/src/adapters/atendimento.rs`
(bloco `midia` do evento ganha `legenda`), `server/crates/infrastructure_evolution/src/provider.rs`
(`send_media`: `skip_all`, `fileName` opcional, flag de voz na etapa 2), `server/crates/infrastructure_messaging/src/lib.rs`
(assinatura do trait, se `file_name`/`ptt` entrarem), `server/apps/data_whatsapp/src/main.rs` (`handler_send_whatsapp_media`
repassa `file_name`/`ptt`), `chat_page.dart`.

**Passos — etapa 1 (áudio comum, todos os anexos).**
1. `data_postgres`: incluir `"legenda": midia.legenda` no bloco `midia` do `message.persisted`.
2. Worker: ramo de mídia em `processar_mensagem_persistida`:

```rust
if let Some(midia) = envelope.payload.get("midia") {
    let chave = midia.get("chave").and_then(|v| v.as_str()).unwrap_or_default();
    let mime = midia.get("mimetype").and_then(|v| v.as_str()).unwrap_or_default();
    // A Evolution baixa a mídia por URL: presign GET curto, mas maior que o download dela.
    let url = chamar_rpc(&state.storage_client, &tenant_id, "PresignFile",
        serde_json::json!({ "file_name": chave, "expires_in": 900, "content_type": mime }),
        &causation_id, &envelope.traceparent).await?
        .get("url").and_then(|u| u.as_str()).unwrap_or_default().to_string();
    let corpo = serde_json::json!({
        "id": instance_id, "to_number": to_number,
        "media_type": midia.get("categoria"), // image|audio|video|document
        "media_url": url,                     // credencial: só no corpo do RPC, nunca em log
        "caption": midia.get("legenda").and_then(|v| v.as_str()).filter(|s| !s.is_empty()),
        "file_name": midia.get("nome_arquivo"),
    });
    // mesmo laço de retry/backoff e MarcarMensagemEnviada do texto, com "SendWhatsappMedia"
}
```
3. `provider.rs::send_media`: `#[tracing::instrument(err, skip_all, fields(provider = "evolution", instance_name = %instance_name, media_type = %media_type_str))]`;
   aplicar o mesmo `skip_all` em `send_text`. `fileName` no corpo só para `document` (nome do campo a conferir na tag).
4. Cliente: gravador robusto:

```dart
Future<void> _iniciarGravacao() async {
  // aacLc (.m4a) é o encoder garantido no Windows e o que o servidor reconhece por assinatura.
  const config = RecordConfig(encoder: AudioEncoder.aacLc);
  try {
    if (!await _gravador.isEncoderSupported(config.encoder)) throw StateError('encoder');
    await _gravador.start(config, path: await _caminhoDoAudio());
    setState(() => _gravando = true);
  } catch (e) {
    developer.log('falha ao iniciar gravação', name: 'operacional_module.audio', level: 900, error: e.runtimeType);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não deu para usar o microfone.')));
  }
}
```
   `dispose()` da página chama `_gravador.dispose()`; apagar o arquivo temporário depois do envio; não enviar
   gravação com menos de 1 s.

**Passos — etapa 2 (nota de voz / PTT).**
5. Conferir no código-fonte da tag da `evolution-go` em uso: (a) campo de voz no `POST /send/media` (ou
   rota própria de áudio); (b) se ela converte m4a→ogg/opus sozinha. Se converter: passar a flag com
   `is_ptt`. Se não: testar `AudioEncoder.opus` no Windows e conferir o contêiner (precisa ser Ogg); se não
   for Ogg, converter no servidor (ffmpeg no `data_whatsapp`, decisão a registrar) ou manter áudio comum.
6. `is_ptt` persistido em `metadados` da mensagem (`{"ptt": true}`) para a bolha desenhar como voz.

**Observabilidade & Auditoria.**
- a) Rust: span `outbound.midia` no worker (`skip_all`, `tenant_id`, `mensagem_id`, `categoria`,
  `tentativas`, `http_status`, `error_code = presign_falhou|provedor_recusou|esgotou_retries`);
  `send_media` com `instrument(err)` mantido (erro do provedor HTTP é falha externa). Flutter: debug (`500`)
  no início/fim com `encoder`, `duracao_ms` e `bytes`; aviso (`900`) em falha com o tipo do erro.
- b) **Sem evento de auditoria novo**: o envio cria a mensagem e o outbox, e o status de entrega já é
  auditado como `mensagem.confirmada`; falha final segue o caminho existente de `status_envio=failed`.
- c) URL assinada só no corpo do RPC; `to_number` nunca em span (C9); caminho temporário do áudio fora do
  log (contém o nome do usuário do Windows); token da instância segue em `SecretString`.

**Critérios de aceite (dev).**
- Gravar 5 s no app Windows e enviar: o contato recebe um **áudio** (não o texto "audio.m4a"); a bolha do
  atendente mostra o player (depende da P2a); ticks evoluem.
- Anexar imagem/PDF: o contato recebe a mídia, com a legenda quando houver.
- Sem microfone: aviso claro, sem travar o botão.
- Etapa 2: o contato vê nota de voz (ícone de microfone).
- CI: teste do worker com rota mock `SendWhatsappMedia` (mídia) e `SendWhatsappMessage` (texto), e teste
  de que o span de `send_media` não contém `to_number`.

**Riscos.** Mensagens de mídia já marcadas como "enviadas" como texto antes do fix não são reenviadas;
limite de tamanho da Evolution NÃO CONFIRMADO (o projeto usa 16 MB para áudio/vídeo); TTL do presign tem de
cobrir fila + retry (900 s).

---

### P6 — Fotos dos contatos (servidor + cliente)

- **Agentes:** backend-specialist, frontend-specialist
- **Branch:** `feature/p6-foto-do-contato-no-r2`

**Objetivo.** A foto do contato aparece no cabeçalho, na ficha e nos cartões do kanban, e continua
aparecendo dias depois.

**Causa raiz confirmada.** A URL do `pps.whatsapp.net` é guardada em `foto_perfil_url_origem`
(`infrastructure_postgres/.../atendimentos.rs:1665,1717`) e só é reconsultada após 7 dias
(`grpc_web.rs:6395-6400`); ela expira em horas (info_aux §3). Só o cabeçalho do chat pede foto nova
(`chat_page.dart:179-185`), uma vez por abertura; os cartões do kanban usam a URL morta. O webhook de
contato grava a mesma URL (`worker/src/main.rs:1590-1611`). `get_profile_picture` registra o número no span (C9).

**Arquivos afetados.** `server/crates/infrastructure_evolution/src/provider.rs` (`skip_all`),
`server/apps/data_whatsapp/src/main.rs` (nova rota `BaixarFotoDoContato`), `server/apps/worker/src/main.rs`
(consumidor `contato.foto.sincronizar` e `processar_contato_atualizado`), `server/apps/runtime_api/src/grpc_web.rs`
(`obter_contato_do_atendimento` e montagem de `contato_foto_url` nas listagens),
`server/apps/data_postgres/src/main.rs` (`RegistrarFotoDoContato`/`AtualizarPerfilDoContato` gravam a chave
em `oraculo_contato.foto_perfil` e limpam `foto_perfil_url_origem`), `server/crates/infrastructure_postgres/src/clientes/contatos.rs`,
`avatar_do_contato.dart`, `chat_page.dart`, `kanban_controller.dart`.

**Passos.**
1. `data_whatsapp` — `BaixarFotoDoContato { id, number }`: pede `/user/avatar`, baixa o binário só de host
   `*.whatsapp.net` (anti-SSRF), teto de 1 MB, `Content-Type` `image/*`, devolve `{ base64, mime }` ou `{ sem_foto: true }`:

```rust
/// Só segue URL do CDN do WhatsApp: a URL vem do provedor, mas é dado externo.
fn host_permitido(url: &reqwest::Url) -> bool {
    url.scheme() == "https" && url.host_str().is_some_and(|h| h == "pps.whatsapp.net" || h.ends_with(".whatsapp.net"))
}
```
2. Worker — consumidor `contato.foto.sincronizar { contato_id, instance_id }`: `BaixarFotoDoContato` →
   `PutFile` (`contatos/{contato_id}/avatar-{sha8}.jpg`, com `content_type`) → `RegistrarFotoDoContato { contato_id, chave }`
   → `publicar_realtime(contato.foto_atualizada, { contato_id })`. Sem foto: grava `foto_verificada_em` e chave nula.
3. `runtime_api` — `ObterContatoDoAtendimento` devolve presign da chave (TTL 3600 s) e, se a verificação
   passou de 7 dias (ou `forcar` e mais de 10 min), publica `contato.foto.sincronizar` no bus e responde com
   o que tem (sem baixar no caminho da requisição). Listagens do quadro assinam as fotos em lote (`PresignFiles`).
4. Webhook de contato: `processar_contato_atualizado` deixa de gravar `profilePicUrl` e publica `contato.foto.sincronizar`.
5. Cliente: `AvatarDoContato` com falha → recarrega o contato (não força o provedor) uma vez; o
   `KanbanController` aplica `contato.foto_atualizada` recarregando o quadro pelo debounce existente; ao
   recarregar, mantém a `fotoUrl` antiga do mesmo objeto enquanto fresca (mesma regra do C17).
6. Parar de escrever `foto_perfil_url_origem` e limpar os valores existentes (SQL único na dev; PII tokenizada).

**Observabilidade & Auditoria.**
- a) Span `contato.foto.sincronizar` (`skip_all`, `tenant_id`, `contato_id`, `resultado = ok|sem_foto|host_recusado|grande_demais|erro`,
  `error_code`); contador `smartcore_contato_foto_total{resultado}`; `origem = cache|r2|agendada` no span do `runtime_api`
  (substitui `cache|provedor|sem_foto`). Flutter: debug (`500`) ao pedir contato de novo por foto quebrada.
- b) **Sem evento de auditoria**: atualização de foto é sincronização de sistema, não ação de usuário nem
  dado crítico de 08 §4.2.
- c) URL do `pps.whatsapp.net` **nunca** persistida nem logada; número mascarado (`mascarar_telefone`) se
  precisar aparecer; `get_profile_picture` com `skip_all`; URL assinada do R2 só na resposta.

**Critérios de aceite (dev).** Cartões do kanban e cabeçalho mostram as fotos; no dia seguinte, sem
reabrir o app, continuam aparecendo; contato que troca a foto é atualizado em até 7 dias (ou na hora com
`forcar`); contato sem foto mostra iniciais sem erro no log. CI: `host_permitido`, consumidor do worker com
rotas mock, `runtime_api` não chama o provedor no caminho da requisição.

**Riscos.** Contatos `@lid`: o `to_number` pode ser o LID e o `/user/avatar` não responder — usar
`remoteJidAlt` quando houver; R2 cresce um objeto pequeno por contato (aceitável); `foto_perfil` é
`VARCHAR(255)` — a chave cabe.

---

### P3 — Colar imagem com Ctrl+V (cliente)

- **Agente:** frontend-specialist (devops-specialist confere o build Windows)
- **Branch:** `feature/p3-colar-imagem`

**Objetivo.** Com uma imagem na área de transferência, Ctrl+V no campo de mensagem abre a prévia
"Enviar imagem?"; com texto, Ctrl+V cola o texto como hoje.

**Causa raiz confirmada.** O `TextField` do compositor (`chat_page.dart:1077-1086`) só tem a colagem de
texto do `EditableText`; `Clipboard.getData` só lê texto (info_aux §1). Não há plugin nem interceptação.

**Arquivos afetados.** `chat_page.dart` (`_Compositor`), `operacional_module/pubspec.yaml`,
`doc_dev/libs/flutter/super_clipboard.md` (sair de EM_HOMOLOGACAO após o build da CI).

**Decisão de lib.** `super_clipboard` (já na central, converte DIB/DIBv5 do Windows em PNG, tem
implementação Web). Exige toolchain Rust no build (`super_native_extensions`) — o projeto já tem por causa
do `local_engine_ffi`. Plano B, se o build da CI Windows falhar: `pasteboard` (`Pasteboard.image`), com doc
nova na central antes de entrar.

**Passos.**

```dart
Focus(
  // Não consome o atalho: a colagem de texto do EditableText segue normalmente;
  // em paralelo, se houver imagem, oferece o envio.
  onKeyEvent: (_, evento) {
    final ctrlV = evento is KeyDownEvent && evento.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed;
    if (ctrlV && !modoNota) unawaited(aoColarTalvezImagem());
    return KeyEventResult.ignored;
  },
  child: TextField(/* ... */),
)

Future<void> _colarImagem() async {
  final leitor = await SystemClipboard.instance?.read();
  if (leitor == null || !leitor.canProvide(Formats.png)) return;
  leitor.getFile(Formats.png, (arquivo) async {
    final bytes = await arquivo.readAll();
    if (!mounted || !await _confirmarEnvioDeImagem(bytes)) return;
    await _enviarMidia(nomeArquivo: 'colado_${DateTime.now().millisecondsSinceEpoch}.png',
        mimetype: 'image/png', bytes: bytes);
  });
}
```
2. Diálogo de prévia com `Image.memory(bytes)`; recusar acima de 5 MB com a mensagem do teto de imagem
   (`infrastructure_storage/src/midia.rs:49`) em vez de deixar o servidor recusar.
3. Botão direito → "Colar imagem" opcional (mesma função).

**Observabilidade & Auditoria.** a) Debug (`500`) com formato detectado e tamanho em bytes; aviso (`900`)
em falha de leitura com o tipo do erro. b) **Sem evento de auditoria**: o envio segue o caminho da P2b. c) Conteúdo da área de transferência nunca logado.

**Critérios de aceite (dev).** Print (Win+Shift+S) e Ctrl+V no campo: prévia aparece, "Enviar" manda a
imagem e ela aparece na bolha. Texto copiado + Ctrl+V cola texto, sem diálogo. Ctrl+V na aba "Nota interna"
não oferece imagem. CI: build Windows e Web do app verdes com a lib nova.

**Riscos.** Build nativo do `super_native_extensions` na CI; imagens grandes de print 4K acima de 5 MB
(mensagem clara; compressão fica fora do escopo).

---

### P4 — Transferência automática (backend/IA) — em paralelo

- **Agentes:** backend-specialist (worker), ai-specialist (ia_engine / coordenação com ia-engine-jev)
- **Branch:** `feature/p4-transferencia-automatica-diagnostico`

**Objetivo.** Saber, para cada resposta em que a IA decidiu transferir, se a transferência foi aplicada
e, se não, por quê; corrigir a falha de casamento de fluxo sem tocar o motor Jev.

**Causa raiz (hipóteses ancoradas no código, a confirmar com dados da dev antes de codar).**
- H1 — **casamento exato de string**: `fluxos.iter().find(|f| f.chave == fluxo_transferencia)` com chave
  montada como `"{setor} - {descricao}"` (`worker/src/main.rs:518,544,1091-1094`); qualquer variação do
  texto devolvido pela IA (caixa, espaço, acento, descrição × nome) cai em "fluxo desconhecido" só com `warn`.
- H2 — **lista de fluxos vazia** para a IA (`carregar_fluxos_disponiveis` degrada para vazio em erro, `:496-499`;
  cache por tenant pode estar velho após criar fluxo).
- H3 — `TransferirAtendimentoParaFluxo` responde `transferido=false` (motivo só no `warn`, `:568-580`).
- H4 — tenant no motor `llm` esperando as regras de transferência cadastradas (migração 0048), que são do
  motor Jev (plano `ia-engine-jev`, J3).

**Arquivos afetados.** `server/apps/worker/src/main.rs` (`aplicar_transferencia_ia`, `carregar_fluxos_disponiveis`).
Sem mudança em `ia_engine`/`ia_engine_jev` nem no proto.

**Passos.**
1. Diagnóstico na dev (somente leitura): `audit_log` sem `atendimento.transferido_por_ia` nos casos
   relatados; logs `fluxo desconhecido`/`não efetivada`; `oraculo_decisao_ia` (motor jev/sombra) com
   `fluxo_transferencia` e `fluxo_id` nulo; configuração do motor do tenant. Registrar qual hipótese vale.
2. Normalizar o casamento (corrige H1 sem contrato novo):

```rust
/// Casa a chave da IA com a do fluxo ignorando caixa, espaços e acentos.
fn normalizar_chave(s: &str) -> String {
    use unicode_normalization::UnicodeNormalization; // conferir se já é dependência do worker
    s.nfd().filter(|c| c.is_alphanumeric() || c.is_whitespace())
        .collect::<String>().split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}
```
   (Se a crate não estiver no workspace, usar só `trim` + `to_lowercase` + colapso de espaços — sem lib nova.)
3. Instrumentar a decisão e invalidar o cache de fluxos quando a chave não casar (uma recarga por tentativa).
4. H4 confirmada → não implementar aqui: registrar no plano `ia-engine-jev` (J3) e orientar o tenant a ligar o motor Jev.

**Observabilidade & Auditoria.**
- a) Span `ia.transferencia` (`skip_all`, `tenant_id`, `atendimento_id`, `motor`, `resultado =
  aplicada|fluxo_desconhecido|nao_efetivada|rpc_falhou`, `motivo`, `fluxos_disponiveis`) e
  `smartcore_transferencia_ia_total{resultado,motor}`. `warn` passa a carregar `atendimento_id` e `resultado`.
- b) `atendimento.transferido_por_ia` **já existe** (`:602-610`) e continua sendo o único evento (só quando
  efetiva); tentativa recusada não muda estado → log + métrica, e no motor Jev o registro em `oraculo_decisao_ia`.
- c) Nunca registrar a mensagem do contato nem a chave crua devolvida pela IA no log (pode ecoar texto do
  contato); `motivo` é nome de regra/sinal.

**Critérios de aceite (dev).** Conversa de teste que pede atendimento humano: o cartão muda de fluxo no
kanban em segundos e o `audit_log` tem `atendimento.transferido_por_ia` com `motivo`; quando não transfere,
o span diz qual `resultado`. CI: teste de `normalizar_chave` e de `aplicar_transferencia_ia` com chave em
caixa/acento diferente (rotas mock existentes em `main.rs:5517+`).

**Riscos.** Conflito com o J3 do `ia-engine-jev` na mesma função — combinar a ordem dos merges; normalização
pode casar dois fluxos com nomes quase iguais (tratar empate como `fluxo_desconhecido`).

---

## 4. Mapeamento PREVC

| Etapa PREVC | Fases / atividade | Responsável | Saída |
|---|---|---|---|
| **P** — Planejamento | Este plano + info_aux; triagem de libs e serviços | team lead / documentation-writer | Plano completo e auxiliar |
| **R** — Revisão | Revisão de arquitetura (sem gRPC-Web novo, sem proto, rotas de envelope), segurança (C9, P6 anti-SSRF) e da doc `media_kit.md` | architect-specialist, security-auditor | Plano aprovado |
| **E** — Execução | P1.1-B, P1.1-A, P1, P1.1-D, P5, P2a, P2b, P6, P3 (nesta ordem); P4 em paralelo | backend-specialist, frontend-specialist, ai-specialist, devops-specialist (build Windows/Web) | PRs por fase via `feature/...` |
| **V** — Validação | CI verde (format/analyze/clippy/testes novos); merge validado em `ci/` temporária; deploy na dev; critérios de aceite no app Windows | code-reviewer, test-writer | Checklist de aceite por fase |
| **C** — Conclusão | Atualizar central (`media_kit.md`, `super_clipboard.md` → homologada), changelog, memória de decisões (PTT, lib de clipboard) | documentation-writer | Docs e changelog |

| Fase | PREVC | Branch | Agente principal |
|---|---|---|---|
| P1.1-B | E | `feature/p1-1-b-eventos-realtime-dedupe` | backend-specialist |
| P1.1-A | E | `feature/p1-1-a-coalescencia-chat` | frontend-specialist |
| P1 | E | `feature/p1-ordem-mensagem-pendente` | frontend-specialist |
| P1.1-D | E | `feature/p1-1-d-agrupamento-bolhas` | frontend-specialist |
| P5 | E | `feature/p5-rolagem-colunas-kanban` | frontend-specialist |
| P2a | E | `feature/p2a-midia-na-bolha` | backend-specialist + frontend-specialist |
| P2b | E | `feature/p2b-envio-de-audio` | backend-specialist + frontend-specialist |
| P6 | E | `feature/p6-foto-do-contato-no-r2` | backend-specialist + frontend-specialist |
| P3 | E | `feature/p3-colar-imagem` | frontend-specialist |
| P4 | E (paralelo) | `feature/p4-transferencia-automatica-diagnostico` | backend-specialist + ai-specialist |

---

## 5. Pontos em aberto

1. Evolution Go (tag em uso): campo de voz/PTT e de nome de arquivo no `POST /send/media`, conversão
   automática para ogg/opus, limite de tamanho — conferir no código-fonte antes da etapa 2 da P2b.
2. Contêiner do `AudioEncoder.opus` no Windows (record 6.1.1) — só relevante se a Evolution não converter.
3. `media_kit` na compilação Web do `operacional_module` e download do libmpv no build da CI Windows.
4. `super_native_extensions` na CI Windows (toolchain Rust no job do app) — se falhar, `pasteboard` com doc nova.
5. P4: qual hipótese (H1–H4) vale só se sabe com os dados da dev; H4 pertence ao J3 do `ia-engine-jev`.
6. Eco `fromMe` do `messages.upsert` publicando `mensagem.recebida` duplicado — verificar na P1.1-B.
7. Contatos `@lid` sem número real para `/user/avatar` (P6).
8. Varredura de `skip_all` nos demais métodos do `provider.rs` (`set_presence`, `mark_read`, `send_reaction` registram argumentos) — fora do escopo das fases, recomendada.
