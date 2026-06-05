# 02 — Camada de Contrato e Transporte

> **Status:** Planejamento (a revisar). Coração técnico do refator.
> **Idioma:** pt-br na documentação; identificadores em inglês.
> **Pré-leitura:** [01-visao-arquitetura-modular-contrato.md](./01-visao-arquitetura-modular-contrato.md).

Esta camada entrega a promessa central: **trocar host ou codec sem mudar o código de
aplicação**. Ela é dividida em duas crates compartilhadas:

- **`contracts`** — *o que* trafega: schemas (`.fbs`/`.proto`), tipos gerados, envelope.
- **`transport`** — *como* trafega: canais (UDS/TCP/WS), codecs (FlatBuffers/gRPC),
  framing RPC, streaming, reconexão, descoberta por config.

> Decisão de divisão: separar `contracts` (puro, sem I/O) de `transport` (I/O, tokio)
> preserva a regra "contrato sem runtime" (doc 07 C1) e deixa o `data_*` depender só de
> `contracts` para tipos, e do `transport` só nos *binários* que abrem sockets.

---

## 1. Fonte única de schema

Todo contrato nasce de **um schema declarativo**, versionado em `contracts/schemas/`:

```
contracts/schemas/
├── envelope.fbs          # o envelope comum (tenant, trace, erro, versão)
├── events/               # eventos do bus (escrita / domínio)
│   ├── message.fbs       # MessageReceived, MessageUpdate, ...
│   └── persistence.fbs   # PersistMessageCommand, UpsertContactCommand, ...
├── queries/              # leituras req/reply
│   ├── conversation.fbs  # GetThread, ListTickets, ...
│   └── auth.fbs          # comandos síncronos de auth
└── ai/
    └── ai_engine.fbs     # AnalisePreviaMensagem, TranscribeAudio, ...
```

### ✅ Decisão — uma fonte canônica, ambos os formatos gerados no build

**`.fbs` é a única fonte autorada.** Ninguém escreve `.proto` à mão: o **`build.rs`
gera o `.proto` a partir do `.fbs`** e roda os dois codegens. Sem schema duplicado, sem
teste de paridade (é geração, não cópia).

```
contracts/schemas/*.fbs   (ÚNICA fonte autorada)
        │  build.rs
        ├─► flatc        → tipos FlatBuffers (codec padrão)
        └─► transpile .fbs→.proto → protoc/tonic-build → tipos gRPC/Protobuf (fallback)
```

**Disciplina de schema (para a geração ser mecânica e confiável)** — restringe-se ao
**subconjunto comum** de FlatBuffers e Protobuf:

| Regra | Por quê |
|---|---|
| **`id:` explícito em todo campo** | Protobuf exige número de campo; garante compatibilidade na evolução |
| Tipos do denominador comum: escalares, `string`, `[ubyte]`→`bytes`, `table`→`message`, `[X]`→`repeated`, `enum` (com valor zero), `union`→`oneof` | mapeamento 1:1 entre os IDLs |
| Evitar construtos só-FlatBuffers (struct de layout fixo, unions exóticas) | manter o transpile determinístico |

> **Escape hatch:** se uma mensagem exótica não mapear, **aquela** ganha um `.proto`
> escrito à mão, sem afetar o resto. (Alternativa **FlatBuffers-sobre-gRPC** via
> `flatc --grpc` continua disponível para um módulo que queira o framing do gRPC **com**
> payload FlatBuffers — ex.: `ia_engine` com streaming pesado.)

**Mesma fonte cobre o erro:** `ErrorCode`/`ErrorCategory`/`ErrorEnvelope` (doc 04) moram
neste `.fbs` canônico e saem nos três idiomas **e** nos dois formatos pelo mesmo pipeline
— uma fonte de verdade para contrato **e** erro.

Codegen por linguagem (build):
- **Rust:** `flatc --rust` + `tonic-build` (sobre o `.proto` gerado). `build.rs` na `contracts`.
- **Python (`ia_engine`):** `flatc --python` (+ `grpcio-tools` no fallback).
- **Dart (Flutter):** `flatc --dart` (+ `protoc`/`grpc-web` só no fallback web).

---

## 2. O envelope (atravessa toda fronteira)

`envelope.fbs` define o invólucro comum a **todo** evento e **toda** requisição,
independente de codec/canal:

```fbs
// contracts/schemas/envelope.fbs  (comentários em pt-br)
namespace smartcore.contracts;

table Envelope {
  tenant_id:     string;   // UUID do tenant (vazio = superuser/global) — RA: tenant em tudo
  schema_version:uint16;   // versão do schema (evolução compatível)
  message_id:    string;   // UUIDv7 — ordenável e idempotente
  causation_id:  string;   // id da mensagem que causou esta (rastreio de cadeia)
  traceparent:   string;   // W3C trace context — propaga o trace entre VMs (doc 04)
  occurred_at:   long;     // epoch millis
  kind:          MessageKind;  // EVENT | REQUEST | REPLY | STREAM_ITEM | ERROR
  method:        string;   // nome lógico (ex.: "GetThread", "PersistMessage")
  payload:       [ubyte];  // corpo FlatBuffers (ou bytes gRPC) — opaco ao transporte
  error:         ErrorEnvelope;  // preenchido só quando kind = ERROR (doc 04 §3)
}

enum MessageKind : byte { EVENT, REQUEST, REPLY, STREAM_ITEM, ERROR }
```

Pontos-chave:
- **`tenant_id` é estrutural** — nenhuma mensagem cruza fronteira sem ele (RA + doc 02 §dados).
- **`traceparent` é estrutural** — é assim que o trace sobrevive a um salto de VM (doc 04).
- **`error` é estrutural** — erro de fronteira é **dado**, não exceção perdida (doc 04 §3).
- **`payload` é opaco** ao transporte — o transporte não precisa entender o corpo; só
  roteia pelo `method` e correlaciona pelo `message_id`/`causation_id`.

---

## 3. Codec plugável

```rust
/// Serializa/deserializa o corpo das mensagens. Desacoplado do canal.
pub trait Codec: Send + Sync {
    fn nome(&self) -> &'static str;            // "flatbuffers" | "grpc"
    fn encode(&self, env: &Envelope) -> Bytes; // envelope + payload → bytes do fio
    fn decode(&self, raw: &[u8]) -> Result<Envelope, TransportError>;
}

pub struct FlatbuffersCodec; // padrão — zero-copy na leitura do payload
pub struct GrpcCodec;        // fallback — usa prost/tonic por baixo
```

Seleção por **configuração**, por serviço:
`SMARTCORE_<SVC>_CODEC=flatbuffers|grpc` (default `flatbuffers`).

> **Por que o codec é trocável sem mexer na aplicação:** a aplicação fala em **tipos
> gerados** (`GetThreadRequest`, `MessageReceived`), não em bytes. O codec é quem
> transforma esses tipos no formato de fio. Trocar o codec troca a serialização, não a
> API que a aplicação usa.

---

## 4. Canal plugável

```rust
/// Move bytes entre processos. Desacoplado do codec.
pub enum Endpoint {
    Unix(PathBuf),        // unix:///var/run/smartcore/data_postgres.sock
    Tcp(SocketAddr, Tls), // tcp://10.0.0.5:7001 (+TLS) — outra VM
    WebSocket(Url),       // wss://api.host/stream — cliente web (borda Flutter)
}
```

Mapa de uso:

| Canal | Latência | Uso | Observação |
|---|---|---|---|
| **UDS** | velocidade da RAM | **padrão local** | mesmo host/Docker; cópia direta no kernel |
| **TCP/TLS** | rede | **promoção a VM** | troca de `unix://`→`tcp://` por config |
| **WebSocket (binário)** | rede | **borda web** (RA6) | browser não faz socket TCP cru; carrega frames FlatBuffers |

### 4.1 Dois transportes de fronteira, um contrato

O modo de **interação** (RA1) escolhe o transporte concreto, mas o **envelope é o mesmo**:

| Interação | Transporte concreto | Durabilidade |
|---|---|---|
| **Evento** (assíncrono, fire-and-forget) | **Redis Streams** (consumer groups) | durável, replay, fan-out |
| **Request/Reply** (síncrono, com resposta) | **UDS/TCP/WS** direto (framing §5) | efêmero, baixa latência |
| **Stream** (push p/ cliente) | **UDS/TCP/WS** direto (framing §5) | efêmero, contínuo |

> **Dois planos (padrão de mercado):** **leitura** e **escrita-com-ack** → req/reply
> direto (síncrono); **fire-and-forget/ingestão/eventos de domínio/auditoria** → bus
> (assíncrono). **Leitura nunca passa por fila.** A escolha por operação está em
> [03](./03-acesso-dados-orientado-eventos.md) §1/§3; aqui só descrevemos os mecanismos.

> O **bus** (Redis Streams) é o transporte do modo *Evento*. Não confundir com o
> serviço `data_redis` (cache/token), que é alcançado por **req/reply**. Mesmo Redis
> servidor, papéis distintos — herda o "papel duplo do Redis" do doc 04.

---

## 5. Framing RPC do transporte direto (a parte que o gRPC dá de graça)

Sobre UDS/TCP/WS precisamos de um **protocolo de enquadramento** próprio (o gRPC tem o
dele no HTTP/2). Proposta mínima, binária:

```
┌────────┬──────────┬───────────────┬───────────────────────────┐
│ len:u32│ flags:u8 │ corr_id:u128  │ envelope serializado (len) │
└────────┴──────────┴───────────────┴───────────────────────────┘
  prefixo de tamanho   correlação      corpo (FlatBuffers/gRPC)
```

- **`len`**: tamanho do envelope (frame delimitado por tamanho — resolve TCP stream).
- **`flags`**: bit de *stream* (item/fim), bit de *erro*, bit de *compressão* (futuro).
- **`corr_id`**: correlaciona REQUEST↔REPLY e itens de um STREAM. Permite **multiplexar**
  várias chamadas na mesma conexão (o que o HTTP/2 faz por nós no gRPC).

A **runtime de transporte** que precisamos construir (o custo assumido no doc 01 §6):

| Recurso | Por que | Estratégia inicial |
|---|---|---|
| **Multiplexação** | várias chamadas na mesma conexão | tabela `corr_id → oneshot/Sender` |
| **Keepalive/heartbeat** | detectar conexão morta | frame de ping periódico + timeout |
| **Reconexão com backoff** | UDS/TCP cai; cliente precisa voltar | `tokio` + backoff exponencial com jitter |
| **Streaming** | realtime ao Flutter; respostas grandes | frames `STREAM_ITEM` até `STREAM_END` |
| **Backpressure** | consumidor lento não estoura memória | canais limitados (`mpsc` bounded) |
| **Timeout/cancelamento** | toda chamada tem limite | `tokio::time::timeout` por `corr_id` |

> **Gatilho de fallback para gRPC (documentado):** se, para um módulo, esses recursos
> ficarem caros/instáveis de manter na nossa runtime, **vira o codec/transport desse
> módulo para gRPC** (que entrega tudo isso pelo HTTP/2) — `…_CODEC=grpc`. O contrato e
> a aplicação não mudam. É o "entrave" virando decisão de config, não refator.

---

## 6. A API que a aplicação enxerga

A aplicação **nunca** vê socket, frame ou codec. Vê um cliente tipado:

```rust
// Gerado/derivado do schema. A mesma API para FlatBuffers ou gRPC, UDS ou TCP.
let pg = DataPostgresClient::from_env("DATA_POSTGRES"); // resolve endpoint+codec da config

// Leitura — RPC direto, request/reply síncrono (RA1)
let thread = pg.get_thread(ctx, GetThreadRequest { conversation_id }).await?;

// Escrita-com-ack — RPC direto, recebe o resultado na mesma chamada (RA1)
let saved = pg.persist_message(ctx, PersistMessageRequest { /* … */ }).await?;

// Escrita assíncrona (fire-and-forget / rajada) — publica no bus
bus.publish(ctx, MessageReceivedEvent { /* … */ }).await?;

// Stream — realtime
let mut stream = runtime_api.stream_atendimentos(ctx, filtro).await?;
while let Some(item) = stream.next().await { /* … */ }
```

`ctx: &RequestContext` carrega `tenant_id` + `traceparent` e **preenche o envelope
automaticamente** — o desenvolvedor não escreve isso à mão (garante RA "tenant em tudo"
e o trace distribuído do doc 04).

### 6.1 Descoberta por configuração (o que muda ao escalar)

Cada serviço declara **só** seus endpoints; promover a VM é editar env:

```bash
# Fase atual (mesma máquina) — tudo UDS
SMARTCORE_DATA_POSTGRES_ENDPOINT=unix:///var/run/smartcore/data_postgres.sock
SMARTCORE_IA_ENGINE_ENDPOINT=unix:///var/run/smartcore/ia.sock
SMARTCORE_IA_ENGINE_CODEC=flatbuffers

# Promovendo o ia_engine para a VM com GPU — muda SÓ estas linhas
SMARTCORE_IA_ENGINE_ENDPOINT=tcp://ia.interno:7050
SMARTCORE_IA_ENGINE_TLS_CA=/etc/smartcore/ia-ca.pem
# (se FlatBuffers travar para streaming bidi, só então:)
# SMARTCORE_IA_ENGINE_CODEC=grpc
```

---

## 7. Versionamento e compatibilidade

- **`schema_version`** no envelope + evolução **aditiva** do FlatBuffers (campos novos
  com default; nunca renumerar/remover — FlatBuffers já favorece isso).
- Teste de **round-trip** por mensagem (encode→decode→igual) no CI. **Paridade
  `.fbs`↔`.proto` é estrutural** (o `.proto` é **gerado** do `.fbs` no build, §1) — não há
  schema duplicado para divergir; o teste vira **interop** FlatBuffers↔gRPC do mesmo `method`.
- Eventos persistidos no bus de uma versão anterior **devem desserializar** na nova
  (mantém o DoD de compatibilidade do doc 07 §7).

---

## 8. Estrutura das crates

```
server/crates/contracts/
├── schemas/            # .fbs (canônico) + .proto (espelho dos módulos gRPC)
├── build.rs            # flatc + tonic-build
├── src/
│   ├── envelope.rs     # Envelope + RequestContext (tenant + traceparent)
│   ├── generated/      # tipos gerados (fb/prost)
│   └── lib.rs
└── Cargo.toml          # sem tokio/sqlx/redis (puro)

server/crates/transport/
├── src/
│   ├── codec/          # FlatbuffersCodec, GrpcCodec
│   ├── channel/        # Unix, Tcp(+Tls), WebSocket
│   ├── framing.rs      # len/flags/corr_id + stream
│   ├── runtime.rs      # mux, keepalive, reconexão, backpressure, timeout
│   ├── bus.rs          # modo Evento sobre Redis Streams
│   ├── client.rs       # cliente tipado genérico (from_env)
│   ├── server.rs       # dispatcher por `method`
│   └── lib.rs
└── Cargo.toml          # tokio, redis, rustls, prost/tonic (fallback)
```

---

## 9. Decisões em aberto (para a revisão)

1. ✅ **RESOLVIDO — uma fonte canônica `.fbs` → `.proto` gerado no build** (subconjunto
   comum, `id:` explícito). Sem schema duplicado nem teste de paridade. Escape hatch:
   `.proto` à mão por mensagem exótica; FlatBuffers-sobre-gRPC disponível para `ia_engine`.
   Ver §1.
2. ✅ **RESOLVIDO — WebSocket** (binário) na borda web agora; WebTransport (HTTP/3)
   reavaliado no futuro.
3. ✅ **RESOLVIDO — mTLS entre VMs** (cada serviço com cert, autenticação mútua); dentro
   da VM continua UDS sem TLS.
4. ✅ **RESOLVIDO — FlatBuffers-first sobre UDS.** Construir a **runtime de transporte
   própria** (framing, mux, reconexão, streaming) desde a fundação, com **UDS como canal
   padrão** e **FlatBuffers como codec padrão**. O **gRPC** entra como **fallback
   plugável** (e como codec dos módulos que tiverem entrave), e **TCP/WebSocket** ficam
   prontos para o split-VM. Ver [05 §6](./05-refator-estado-atual.md).

---

## 10. Próximo documento

Como as **escritas viram eventos** e as **leituras continuam síncronas** — e como os
serviços `data_*` se comportam — está em
[03-acesso-dados-orientado-eventos.md](./03-acesso-dados-orientado-eventos.md).

---

*Camada de contrato e transporte. Sujeito a refinamento.*
