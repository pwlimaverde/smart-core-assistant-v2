# Plano Completo — Refator de Arquitetura Modular por Contrato

> **Arquivo destino:** `.context/plans/refator-arquitetura-modular/plano_completo_refator-arquitetura-modular.md`
> **Origem:** `doc_dev/planejamento/refator-arquitetura-modular/05-refator-estado-atual.md` (+ docs 01–04)
> **Doc auxiliar (libs/toolchain validados):** `.context/plans/refator-arquitetura-modular/info_aux_refator-arquitetura-modular.md`
> **Idioma:** pt-br na documentação; identificadores/código em inglês; comentários de código em pt-br.
> **Estágio do projeto:** inicial — docker dos bancos pode ser refeito livremente onde o refator pedir.

---

## 0. Resumo executivo e a correção de manchete

Este plano reestrutura o refator faseado (RF0–RF6) que migra o `server/` de **crates in-process** para **serviços por contrato** (FlatBuffers-first sobre UDS, gRPC fallback plugável, dois planos de acesso a dados). É **mais *rewire* que *rewrite***: a base atual (`error_core`, `infrastructure_postgres`, `infrastructure_redis`, `observability`, `test_support`) já antecipa boa parte do alvo.

**Manchete da reestruturação (achado crítico já validado — ver `info_aux` §"ACHADO CRÍTICO"):**

> O plano-base assumia que o `build.rs` da crate `contracts` geraria o `.proto` **a partir do** `.fbs`. **Isso é inviável:** o `flatc` **não** transpila `.fbs`→`.proto` (não existe a flag). A direção nativa é a **inversa** (`flatc --proto` lê `.proto` e gera `.fbs`).
>
> **Correção adotada:** inverter a fonte canônica autorada para **`.proto`**. Daí:
> - `tonic-build`/`prost` geram gRPC/Protobuf **direto** do `.proto`;
> - `flatc --proto` gera `.fbs` (e `flatc --rust|--python|--dart` gera os tipos FlatBuffers).
>
> **A decisão "FlatBuffers-first" do dono NÃO é revertida.** FlatBuffers continua o **codec de fio padrão** (zero-copy). Só muda **qual IDL é autorado** (`.proto` em vez de `.fbs`). Bônus: `field number` é nativo do Protobuf (de graça) e o `protoc` vem **embutido** no `tonic-build 0.14.6` (instala-se só o `flatc`). Trade-off: `.proto`→`.fbs` é *best-effort* — cuidar `bytes`↔`[ubyte]` (pode virar `string`) e validar no round-trip/interop do CI. Fallback se o dono recusar a inversão: **Alternativa B** (`.proto` e `.fbs` como fontes separadas + teste de paridade) — ver §13.

### Tabela de versões fixadas (do `info_aux`)

| Item | Versão | Nota |
|---|---|---|
| `flatbuffers` (crate) | `25` | casar **major.minor** com o `flatc` |
| `flatc` (toolchain) | `v25.12.19` | fixar no CI; **único binário a instalar** (protoc é embutido) |
| `flatc-rust` (build helper) | `0.2` | ou `std::process::Command` |
| `prost` | `0.13` | `enum`→`i32`, validar `TryFrom<i32>` |
| `tonic-build` / `tonic` | `0.14.6` | `protoc` **embutido**; já no workspace |
| `redis` | `0.25.0` | Streams + consumer groups (já no workspace) |
| `tokio` | `1.38` | UDS, mux, keepalive, backpressure (já no workspace) |
| `sqlx` | `0.9` | `PgListener` LISTEN/NOTIFY (outbox relay) (já no workspace) |
| `opentelemetry` | `0.31/0.32` | OTLP grpc-tonic (já em `observability`) |

---

## 1. Estado atual ancorado (o que REAPROVEITA vs CRIA)

**Workspace real** (`server/Cargo.toml`): 5 crates, `edition = "2021"`, `resolver = "2"`. `tonic 0.14.6` já presente; **sem** `flatbuffers`/`prost`/`tonic-build`. Migrations **0001–0010** (0010 = `audit_log`).

| Crate atual | O que já tem (verificado) | Destino |
|---|---|---|
| `error_core` | `code.rs`: `ErrorCategory` {Auth, Storage, Database, Cache, Validation, Internal}, `ErrorCode` (17 variantes, `Display` SCREAMING_SNAKE, disciplina de não-remover documentada). `transport::to_status` atrás da feature `grpc` | **convenção** — ganha `ErrorEnvelope` serializável + categorias/campos novos |
| `infrastructure_postgres` | migrations 0001–0010, RLS (`0001_create_rls_function`), `crypto.rs`, `auth/`, `security.rs` (`RequestContext`), `config_cache.rs`, `auditoria/` (`inserir_audit_log`), domínios | **lib interna** do app `data_postgres` |
| `infrastructure_redis` | `event_bus.rs` (Streams: `publicar_evento`/`consumir`/`garantir_consumer_group`/`reprocessar_pendentes`/`confirmar`, `STREAM_EVENTOS`), `envelope.rs` (`TenantEnvelope<T>`, já com nota "migrar para contracts"), `cache.rs`, `auth_tokens.rs`, `keys.rs`, `connection.rs` | **dividida**: cache/token → lib do app `data_redis`; bus → `transport::bus` |
| `observability` | `telemetry.rs` (tracing JSON + OTLP), `propagation.rs` (W3C), `audit.rs` (`AuditLogger`), `span_helpers.rs`. **Depende de `infrastructure_postgres`** | **convenção** — ganha `traceparent` no envelope; auditoria rewired p/ Streams (remove o ciclo) |
| `test_support` | túnel SSH + reset DB | mantém; ganha fixtures de transporte (UDS em tmp) |

**A criar (não existe código):** `contracts`, `transport`, `application`, `apps/*`. Nascem já no padrão novo — não há o que refatorar neles.

**Reaproveitamentos-chave (de-risk):**
- `event_bus.rs` é a base direta de `transport::bus` (rewire, não rewrite).
- `TenantEnvelope<T>` migra para `contracts` (o próprio código já anota isso).
- `inserir_audit_log` + tabela `audit_log` (0010) são reusados pelo consumidor de consolidação.
- `RequestContext` (security.rs) é a semente do `ctx` que preenche o envelope.
- Mover auditoria para Streams **remove** a dependência `observability → infrastructure_postgres` (quebra o ciclo registrado na memória `arquitetura-erros-observabilidade`).

---

## 2. Alvo (estrutura final)

```
server/
├── crates/                      # CONVENÇÕES (libs, não processos)
│   ├── contracts/               # .proto canônico → tipos prost/tonic + .fbs gerado → tipos flatbuffers; Envelope; RequestContext
│   ├── transport/               # Codec (FB/gRPC) + Canal (UDS/TCP/WS) + framing + runtime (mux/keepalive/reconexão) + bus + client/server
│   ├── error_core/              # taxonomia + ErrorEnvelope (convenção)
│   ├── observability/           # tracing + traceparent (convenção; sem dep de postgres após RF1)
│   ├── infrastructure_postgres/ # repos/RLS/migr — lib interna de data_postgres
│   ├── infrastructure_redis/    # papel cache/token — lib interna de data_redis (bus sai daqui)
│   ├── infrastructure_storage/  # mídia — lib interna de data_storage
│   ├── application/             # casos de uso falando pelo contrato
│   └── test_support/
└── apps/                        # SERVIÇOS (processos por contrato)
    ├── data_postgres/           # server RPC (3 protocolos) + consumer do bus + processadores (RLS) + relay outbox
    ├── data_redis/              # cache/token/lock/presença (req/reply)
    ├── data_storage/            # put/get/presign (req/reply) + purga (evento)
    ├── messaging_gateway/       # ingestão → publica eventos
    ├── worker/                  # orquestra domínio
    ├── runtime_api/             # borda do cliente (FlatBuffers; gRPC fallback)
    └── control_plane/           # back office
```

Nomes `infrastructure_*` **mantidos** (decisão do dono): o app `data_postgres` depende da lib `infrastructure_postgres`; idem redis/storage.

---

## 3. RF0 — Camada de contrato/transporte (fundação)

**Objetivo:** entregar a runtime FlatBuffers-sobre-UDS com `.proto` canônico → ambos os codecs gerados no build, e gRPC plugável desde já.

**Agente:** `backend-specialist` (lead) + `devops-specialist` (toolchain `flatc`/CI). **Fase PREVC:** Execution (milestone E0).

### 3.1 O que CRIA vs REAPROVEITA

| Cria | Reaproveita |
|---|---|
| crate `contracts` (schemas `.proto`, `build.rs`, `envelope.rs`, `generated/`) | `TenantEnvelope<T>` (migra de `infrastructure_redis::envelope`) |
| crate `transport` (codec, channel, framing, runtime, client, server, bus) | `event_bus.rs` inteiro vira a base de `transport::bus` |
| deps novas no workspace: `flatbuffers="25"`, `prost="0.13"`, `tonic-build="0.14.6"`, `flatc-rust="0.2"` (build-dep) | `tonic="0.14.6"` já existe |

### 3.2 Pipeline de schema CORRIGIDO (`.proto` canônico)

```
contracts/schemas/*.proto   (ÚNICA fonte autorada — field numbers nativos)
        │  build.rs
        ├─► tonic-build/prost   → tipos gRPC/Protobuf (fallback)         [direto]
        └─► flatc --proto       → contracts/generated/fbs/*.fbs          [best-effort]
                  └─► flatc --rust → tipos FlatBuffers (codec PADRÃO)
```

**Disciplina de schema (subconjunto comum `.proto`↔`.fbs`):** usar só escalares, `string`, `bytes`(→`[ubyte]`), `message`(→`table`), `repeated`(→`[X]`), `enum` **com valor zero**, `oneof`(→`union`, via `flatc --proto --oneof-union`). Evitar `struct` de layout fixo; `service`/`rpc` do `.proto` são ignorados na conversão (ok, o gRPC os usa direto). **Armadilha:** `bytes`→`string` no `.fbs` — validar `bytes`↔`[ubyte]` no round-trip do CI.

### 3.3 `envelope.proto` (canônico)

```proto
// contracts/schemas/envelope.proto  (comentários em pt-br)
syntax = "proto3";
package smartcore.contracts;

import "errors.proto";

// Tipo de interação que o envelope transporta.
enum MessageKind {
  MESSAGE_KIND_UNSPECIFIED = 0; // valor zero obrigatório (proto3 + mapeia p/ FB)
  EVENT = 1;
  REQUEST = 2;
  REPLY = 3;
  STREAM_ITEM = 4;
  ERROR = 5;
}

// Invólucro comum a todo evento e toda requisição (independe de codec/canal).
message Envelope {
  string tenant_id = 1;       // UUID do tenant (vazio = superuser/global)
  uint32 schema_version = 2;  // versão do schema (evolução aditiva) — uint16 lógico
  string message_id = 3;      // UUIDv7 — ordenável e idempotente
  string causation_id = 4;    // id da mensagem que causou esta
  string traceparent = 5;     // W3C trace context — propaga o trace entre VMs
  int64 occurred_at = 6;      // epoch millis
  MessageKind kind = 7;
  string method = 8;          // nome lógico ("GetThread", "PersistMessage")
  bytes payload = 9;          // corpo FlatBuffers (opaco ao transporte)
  ErrorEnvelope error = 10;   // preenchido só quando kind = ERROR
}
```

> `payload` é `bytes` no `.proto` → garantir que vire `[ubyte]` (não `string`) no `.fbs` gerado — é o ponto exato do teste de round-trip.

### 3.4 `errors.proto` (canônico — base de RF1)

```proto
// contracts/schemas/errors.proto  (comentários em pt-br)
syntax = "proto3";
package smartcore.contracts;

enum ErrorCategory {
  ERROR_CATEGORY_UNSPECIFIED = 0;
  VALIDATION = 1;
  AUTH = 2;
  PERMISSION = 3;
  CONFLICT = 4;
  NOT_FOUND = 5;
  RATE_LIMIT = 6;
  DEPENDENCY = 7;
  TIMEOUT = 8;
  INTERNAL = 9;
}

enum Severity {
  SEVERITY_UNSPECIFIED = 0;
  INFO = 1;
  WARNING = 2;
  ERROR = 3;
  CRITICAL = 4;
}

message KeyValue { string key = 1; string value = 2; }

message ErrorEnvelope {
  string code = 1;                  // canônico, ex.: "AUTH_INVALID_CREDENTIALS"
  ErrorCategory category = 2;
  Severity severity = 3;
  string message = 4;               // técnica (log/dev; sem dado sensível)
  string user_message = 5;          // CHAVE i18n, ex.: "errors.auth.invalid_credentials"
  string user_message_fallback = 6; // texto seguro p/ consumidores sem i18n
  bool retryable = 7;
  string trace_id = 8;
  string source_svc = 9;            // ex.: "ia_engine@vm-gpu"
  repeated KeyValue details = 10;
  int64 occurred_at = 11;
}
```

### 3.5 `build.rs` da crate `contracts`

```rust
// contracts/build.rs  (comentários em pt-br)
use std::path::PathBuf;
use std::process::Command;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let schemas = PathBuf::from("schemas");
    let out_fbs = PathBuf::from("generated/fbs");
    let out_rs = std::env::var("OUT_DIR")?;

    // rebuild quando qualquer schema mudar
    println!("cargo:rerun-if-changed=schemas");

    // lista dos .proto canônicos autorados
    let protos = [
        "schemas/envelope.proto",
        "schemas/errors.proto",
        "schemas/events/message.proto",
        "schemas/events/persistence.proto",
        "schemas/queries/conversation.proto",
        "schemas/queries/auth.proto",
        "schemas/ai/ai_engine.proto",
    ];

    // (1) gRPC/Protobuf direto do .proto — protoc EMBUTIDO no tonic-build 0.14.6
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(&protos, &[schemas.to_str().unwrap()])?;

    // (2) .proto → .fbs (best-effort). --oneof-union mapeia oneof→union.
    std::fs::create_dir_all(&out_fbs)?;
    for proto in protos {
        let status = Command::new("flatc")
            .args(["--proto", "--oneof-union", "-o"])
            .arg(&out_fbs)
            .arg(proto)
            .status()?;
        assert!(status.success(), "flatc --proto falhou para {proto}");
    }

    // (3) .fbs → tipos Rust FlatBuffers (codec PADRÃO)
    let fbs: Vec<_> = std::fs::read_dir(&out_fbs)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "fbs"))
        .collect();
    flatc_rust::run(flatc_rust::Args {
        inputs: &fbs.iter().map(|p| p.as_path()).collect::<Vec<_>>(),
        out_dir: std::path::Path::new(&out_rs),
        ..Default::default()
    })?;

    Ok(())
}
```

> Alternativa sem `flatc-rust`: substituir o passo (3) por `Command::new("flatc").args(["--rust","-o",&out_rs]).args(&fbs)`. Em ambos os casos o `flatc` precisa estar no PATH (CI fixa `v25.12.19`).

### 3.6 Trait `Codec` (FlatbuffersCodec / GrpcCodec)

```rust
// transport/src/codec/mod.rs  (comentários em pt-br)
use bytes::Bytes;
use crate::error::TransportError;
use contracts::Envelope;

/// Serializa/deserializa o envelope. Desacoplado do canal.
pub trait Codec: Send + Sync {
    fn nome(&self) -> &'static str;                 // "flatbuffers" | "grpc"
    fn encode(&self, env: &Envelope) -> Bytes;      // envelope → bytes do fio
    fn decode(&self, raw: &[u8]) -> Result<Envelope, TransportError>;
}

/// Codec padrão — zero-copy na leitura do payload (FlatBuffers).
pub struct FlatbuffersCodec;
/// Codec fallback — usa prost/tonic por baixo (Protobuf).
pub struct GrpcCodec;

/// Seleção por config: SMARTCORE_<SVC>_CODEC=flatbuffers|grpc (default flatbuffers).
pub fn from_env(svc: &str) -> Box<dyn Codec> {
    match std::env::var(format!("SMARTCORE_{svc}_CODEC")).as_deref() {
        Ok("grpc") => Box::new(GrpcCodec),
        _ => Box::new(FlatbuffersCodec), // padrão
    }
}
```

### 3.7 Framing (len/flags/corr_id)

```rust
// transport/src/framing.rs  (comentários em pt-br)
// ┌────────┬──────────┬──────────────┬────────────────────────────┐
// │ len:u32│ flags:u8 │ corr_id:u128 │ envelope serializado (len)  │
// └────────┴──────────┴──────────────┴────────────────────────────┘
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub mod flags {
    pub const STREAM_ITEM: u8 = 0b0000_0001;
    pub const STREAM_END:  u8 = 0b0000_0010;
    pub const IS_ERROR:    u8 = 0b0000_0100;
    pub const COMPRESSED:  u8 = 0b0000_1000; // futuro
}

pub struct Frame { pub flags: u8, pub corr_id: u128, pub body: Vec<u8> }

pub async fn write_frame<W: AsyncWriteExt + Unpin>(w: &mut W, f: &Frame)
    -> std::io::Result<()> {
    w.write_u32(f.body.len() as u32).await?;   // prefixo de tamanho (resolve TCP stream)
    w.write_u8(f.flags).await?;
    w.write_u128(f.corr_id).await?;            // correlaciona REQUEST↔REPLY / itens de STREAM
    w.write_all(&f.body).await?;
    w.flush().await
}

pub async fn read_frame<R: AsyncReadExt + Unpin>(r: &mut R)
    -> std::io::Result<Frame> {
    let len = r.read_u32().await? as usize;
    let flags = r.read_u8().await?;
    let corr_id = r.read_u128().await?;
    let mut body = vec![0u8; len];
    r.read_exact(&mut body).await?;
    Ok(Frame { flags, corr_id, body })
}
```

### 3.8 Esqueleto do `transport::runtime` (mux/keepalive/reconexão)

```rust
// transport/src/runtime.rs  (comentários em pt-br)
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{oneshot, Mutex, mpsc};
use tokio::time::{timeout, Duration};

/// Multiplexa várias chamadas na mesma conexão (o que o HTTP/2 dá ao gRPC de graça).
pub struct MuxClient {
    tx: mpsc::Sender<Frame>,                                  // envio com backpressure (bounded)
    pendentes: Arc<Mutex<HashMap<u128, oneshot::Sender<Frame>>>>, // corr_id → resposta
}

impl MuxClient {
    /// Request/reply síncrono com timeout por corr_id.
    pub async fn call(&self, env: Envelope, prazo: Duration) -> Result<Envelope, TransportError> {
        let corr_id = uuid::Uuid::now_v7().as_u128();
        let (resp_tx, resp_rx) = oneshot::channel();
        self.pendentes.lock().await.insert(corr_id, resp_tx);
        self.tx.send(self.codec.frame(corr_id, &env)).await
            .map_err(|_| TransportError::Closed)?;             // backpressure: canal cheio bloqueia
        let frame = timeout(prazo, resp_rx).await
            .map_err(|_| TransportError::Timeout)??;           // cancelamento por prazo
        self.codec.decode(&frame.body)
    }
    // read_loop: lê frames, casa corr_id→oneshot; reconnect: backoff exponencial+jitter;
    // keepalive: ping periódico + timeout marca conexão morta e dispara reconexão.
}
```

### 3.9 `transport::bus` (reaproveita `event_bus`)

`transport/src/bus.rs` **move** `event_bus.rs` de `infrastructure_redis`. Mantém `STREAM_EVENTOS`, `publicar_evento`/`consumir`/`garantir_consumer_group`/`reprocessar_pendentes`/`confirmar`. Ajustes:
- `TenantEnvelope<T>` passa a ser reexportado de `contracts` (não mais definido em `infrastructure_redis`).
- O bus passa a transportar o `Envelope` do contrato no payload (FlatBuffers), preservando `tenant_id`/`traceparent`.
- A `infrastructure_redis` perde o `event_bus.rs` e o `envelope.rs` (mantém cache/token/keys/connection).

### 3.10 Ajuste docker/infra (RF0)

- **Sockets UDS:** criar volume/dir compartilhado `unix:///var/run/smartcore/<svc>.sock`. Na fase atual (apps ainda fora de container) basta um diretório local; previsão de volume no compose quando os `apps/` forem containerizados (RF2+).
- **CI/toolchain:** instalar `flatc v25.12.19` (binário fixado), **não** instalar `protoc` (embutido no tonic-build). Documentar no `development-workflow`.

### 3.11 DoD RF0 (verificável)

- [ ] `cargo build -p contracts` gera tipos prost **e** flatbuffers; `payload` é `[ubyte]` no `.fbs` (asserção de round-trip `bytes`↔`[ubyte]`).
- [ ] ping **request/reply** por UDS retorna o `Envelope` (tenant+traceparent preservados).
- [ ] um **evento** round-trip pelo `transport::bus` (XADD→XREADGROUP→XACK).
- [ ] codec comutável **FlatBuffers↔gRPC** no mesmo `method` (interop test verde).
- [ ] `infrastructure_redis` compila sem `event_bus`/`envelope` (movidos).

---

## 4. RF1 — Transversais ganham a fronteira (estender/rewire)

**Objetivo:** expor o formato de fronteira (`ErrorEnvelope`, `traceparent`) e fazer o rewire da auditoria para Streams, removendo o ciclo `observability → infrastructure_postgres`.

**Agente:** `backend-specialist` (error_core/observability) + `database-specialist` (consumidor de consolidação). **Fase PREVC:** Execution (E1).

### 4.1 O que CRIA vs REAPROVEITA

| Cria | Reaproveita |
|---|---|
| `ErrorEnvelope` serializável em `error_core` + `to_error_envelope`/`from_envelope` | `ErrorCode`/`ErrorCategory`/`AppError`/`public_message()` + disciplina de deprecação (`code.rs`) |
| categorias novas: `Permission`/`RateLimit`/`Timeout`/`Dependency`/`NotFound`/`Conflict` | as 6 existentes (Auth/Storage/Database/Cache/Validation/Internal) |
| campos `user_message`/`user_message_fallback`/`retryable`/`source_svc`/`trace_id` | mapeamento i18n |
| consumidor de consolidação de auditoria | `inserir_audit_log` + tabela `audit_log` (0010) + `event_bus` |

### 4.2 Extensão do `error_core` (respeitando a disciplina do `code.rs`)

Adicionar variantes **no fim** (nunca renomear/remover), espelhando o `errors.proto`:

```rust
// error_core/src/code.rs — extensão (comentários em pt-br)
pub enum ErrorCategory {
    Auth, Storage, Database, Cache, Validation, Internal, // EXISTENTES — não tocar
    Permission, RateLimit, Timeout, Dependency, NotFound, Conflict, // NOVOS
}
```

Ponte `AppError` ⇄ `ErrorEnvelope` (gerado de `contracts::ErrorEnvelope`):

```rust
// error_core/src/envelope_bridge.rs  (comentários em pt-br)
impl AppError {
    /// Converte o erro nativo no envelope de fronteira (dado serializável).
    pub fn to_error_envelope(&self, trace_id: &str, source_svc: &str)
        -> contracts::ErrorEnvelope {
        contracts::ErrorEnvelope {
            code: self.code().to_string(),
            category: self.code().category().into(), // map enum nativo → proto enum
            severity: self.severity().into(),
            message: self.to_string(),               // técnica (sem PII)
            user_message: self.i18n_key().into(),    // chave i18n
            user_message_fallback: self.public_message().into(), // já existe
            retryable: self.retryable(),
            trace_id: trace_id.into(),
            source_svc: source_svc.into(),
            details: self.details_kv(),
            occurred_at: chrono::Utc::now().timestamp_millis(),
        }
    }
    /// Reconstrói um AppError equivalente a partir do envelope recebido de outro processo.
    pub fn from_envelope(env: &contracts::ErrorEnvelope) -> Self { /* match por code */ }
}
```

> `prost` gera `category`/`severity` como `i32`; usar `TryFrom<i32>` na desserialização (`from_i32` está depreciado — `info_aux` nota 5).

### 4.3 `observability`: traceparent + remoção do ciclo

- `propagation.rs` (W3C, já existe) preenche/extrai `Envelope.traceparent` em cada salto.
- Coletor OTLP **sobe cedo** (stack LGTM já em `docker/observability`).
- **Auditoria rewired:** `audit.rs::AuditLogger` deixa de chamar `inserir_audit_log` (que vinha de `infrastructure_postgres`) e passa a **publicar no Redis Streams (segurança)** via `transport::bus`. Isso **remove `observability → infrastructure_postgres`** do `Cargo.toml` de `observability` (quebra o ciclo).

### 4.4 Consumidor de consolidação (database-specialist)

Stream de segurança dedicado (ex.: `security:stream`) → consumidor lê em **batch** → chama `inserir_audit_log` (reuso) dentro de `run_in_tenant_transaction`. Vive no app `data_postgres` (criado em RF2; em RF1 entra como módulo/binário mínimo de consolidação ou stub testável).

### 4.5 Ajuste docker/infra (RF1) — eviction do Redis

O Redis atual usa `--maxmemory-policy allkeys-lru` (data.yml linha 62) — **pode evictar entradas de Stream** sob pressão, perdendo eventos do bus/auditoria. **Correção:** isolar o namespace do bus de `allkeys-lru`. Opções (projeto inicial, docker livre):
- **Recomendado:** instância/serviço Redis separado para o bus durável com `--maxmemory-policy noeviction` e `--appendonly yes`; manter o `allkeys-lru` só para cache.
- Alternativa: subir `--maxmemory` e mover cache para `data_redis` com TTL explícito, deixando o bus protegido.

### 4.6 DoD RF1

- [ ] erro do processo B chega ao A como `ErrorEnvelope` → `AppError` equivalente (`from_envelope`).
- [ ] um **trace** cobre 2 processos (traceparent no envelope → 1 trace no coletor OTLP).
- [ ] `login_failed` percorre **Redis Streams (segurança) → consumidor → `audit_log`**.
- [ ] `observability/Cargo.toml` **sem** dependência de `infrastructure_postgres` (ciclo removido).
- [ ] Redis do bus com política que **não** evicta Streams (validado sob pressão).

---

## 5. RF2 — `data_postgres` como serviço (dois planos)

**Objetivo:** primeiro app — embrulha `infrastructure_postgres` com a anatomia do doc 03 §2 (servidor RPC 3 protocolos + consumer + processadores + relay outbox).

**Agente:** `database-specialist` (lead) + `backend-specialist` (server/handlers). **Fase PREVC:** Execution (E2).

### 5.1 Anatomia (`apps/data_postgres`)

```rust
// apps/data_postgres/src/main.rs  (comentários em pt-br)
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    observability::init();                          // OTLP cedo
    let pool = infrastructure_postgres::connect().await?; // REAPROVEITA pool/RLS/migr
    let proc = Processadores::new(pool.clone());    // handlers comuns aos dois planos

    // (1) SÍNCRONO — server RPC nos 3 protocolos (UDS padrão; FB/gRPC; TCP pronto p/ VM)
    let server = transport::Server::from_env("DATA_POSTGRES")
        .route("GetThread",       handler_get_thread)
        .route("PersistMessage",  handler_persist_message) // escrita-com-ack
        .route("UpsertContact",   handler_upsert_contact);

    // (2) ASSÍNCRONO — consumer do bus (Redis Streams) p/ ingestão/fire-and-forget
    let consumer = transport::bus::Consumer::new("data_postgres")
        .on_event(proc.clone());

    // (3) RELAY outbox — LISTEN/NOTIFY → publica eventos de domínio no bus
    let relay = OutboxRelay::new(pool.clone());

    tokio::try_join!(server.run(), consumer.run(), relay.run())?;
    Ok(())
}
```

**Processadores (comuns aos dois planos):** `run_in_tenant_transaction` (RLS, reuso) → repos existentes → escreve `outbox` na mesma transação ACID quando muda estado.

### 5.2 Relay outbox (`sqlx` PgListener)

```rust
// apps/data_postgres/src/outbox_relay.rs  (comentários em pt-br)
use sqlx::postgres::PgListener;

impl OutboxRelay {
    pub async fn run(&self) -> anyhow::Result<()> {
        let mut listener = PgListener::connect_with(&self.pool).await?;
        listener.listen("outbox_new").await?;       // trigger NOTIFY (migration nova)
        loop {
            let _ = listener.recv().await?;          // acordado pelo NOTIFY
            // lê linhas não publicadas do outbox, publica no bus, marca como publicado
            self.drenar_outbox().await?;
        }
    }
}
```

### 5.3 Ajuste docker/migrations (RF2) — tabela + trigger de outbox

Nova migration `0011_outbox.sql` (segue 0001–0010; `LISTEN/NOTIFY` funciona sem config extra no pgvector/pg16 — `info_aux`):

```sql
-- 0011_outbox.sql  (comentários em pt-br)
CREATE TABLE outbox (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     uuid NOT NULL,
    event_type    text NOT NULL,
    payload       bytea NOT NULL,          -- envelope FlatBuffers serializado
    occurred_at   timestamptz NOT NULL DEFAULT now(),
    published_at  timestamptz              -- NULL = ainda não publicado no bus
);
-- RLS herda o padrão dos demais (0001_create_rls_function)

CREATE OR REPLACE FUNCTION outbox_notify() RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify('outbox_new', NEW.id::text); -- acorda o relay (RF2 §5.2)
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER outbox_after_insert
    AFTER INSERT ON outbox
    FOR EACH ROW EXECUTE FUNCTION outbox_notify();
```

- **UDS no compose:** quando `data_postgres` containerizar, montar volume de sockets compartilhado.

### 5.4 DoD RF2

- [ ] ler e escrever um agregado (ex.: contato) por **RPC direto** nos **três** protocolos (RLS ativo, resposta na origem).
- [ ] um fluxo **assíncrono** pelo bus (consumer → processador → outbox).
- [ ] **outbox → relay (LISTEN/NOTIFY) → bus** publica evento de domínio.
- [ ] isolamento multi-tenant revalidado (RLS).
- [ ] migration `0011_outbox` aplicada (tabela+trigger).

---

## 6. RF3 — `data_redis` e `data_storage` como serviços

**Objetivo:** embrulhar cache/token (redis) e mídia (storage) como serviços req/reply; consolidar a saída do papel bus.

**Agente:** `backend-specialist` + `devops-specialist` (storage/MinIO). **Fase PREVC:** Execution (E3).

### 6.1 Cria vs reaproveita

| Cria | Reaproveita |
|---|---|
| `apps/data_redis` (server RPC get/set/exists/lock) | `infrastructure_redis::{cache, auth_tokens, keys, connection}` |
| `apps/data_storage` (put/get/presign + purga por evento) | `infrastructure_storage` (lib) |
| `crates/infrastructure_storage` se ainda não existir | — |

O papel **bus** já saiu de `infrastructure_redis` em RF0 (vive em `transport::bus`). Em RF3 confirma-se que `data_redis` cuida **só** de cache/token; o bus é alcançado por qualquer módulo via `transport`.

### 6.2 DoD RF3

- [ ] cache get/set e presign por **req/reply** (3 protocolos).
- [ ] bus operando pelo `transport` (não mais por `infrastructure_redis`).
- [ ] purga de mídia por **evento** (assíncrono).
- [ ] `infrastructure_redis` sem nenhum resíduo de bus.

---

## 7. RF4 — Flipar a `application` para o contrato

**Objetivo:** casos de uso deixam de chamar repositórios direto; passam a falar pelo `data_postgres` via clientes tipados do `transport`. Auth nasce no padrão novo.

**Agente:** `backend-specialist` (lead) + `test-writer` (fim-a-fim auth). **Fase PREVC:** Execution (E4).

### 7.1 Padrão de chamada

```rust
// application/src/auth/login.rs  (comentários em pt-br)
pub async fn login(ctx: &RequestContext, req: LoginRequest)
    -> Result<LoginReply, AppError> {
    // escrita-com-ack → RPC direto (a borda recebe tokens/erro na MESMA chamada)
    let pg = DataPostgresClient::from_env("DATA_POSTGRES"); // resolve endpoint+codec
    pg.verify_credentials(ctx, req).await   // erro → ErrorEnvelope (log+auditoria+propagação)
}
```

- Leitura/escrita-com-ack → **RPC direto**; efeitos assíncronos → **bus** (doc 03 §3).
- Auth (Register/Login/Refresh/Accept) → **RPC direto (escrita-com-ack)**.
- Senha errada → `AUTH_INVALID_CREDENTIALS`: log (sempre) + auditoria (Streams segurança→consolida) + `user_message` (chave i18n genérica, anti-enumeração) na UI (doc 04 §7).

### 7.2 DoD RF4

- [ ] fluxo de auth fim-a-fim **via contrato** (sem chamada direta a repositório).
- [ ] senha errada gera **log + auditoria + `user_message`** na UI.
- [ ] `application` sem nenhuma dependência direta de `infrastructure_postgres`.

---

## 8. RF5 — `runtime_api` no padrão FlatBuffers + borda do cliente

**Objetivo:** borda do cliente serve FlatBuffers (req/reply + stream) por TCP/TLS (desktop) e WebSocket binário (web); gRPC fallback comutável.

**Agente:** `backend-specialist` + `test-writer` (stream realtime). **Fase PREVC:** Execution (E5).

- `runtime_api` serve **FlatBuffers** req/reply + stream; **WebSocket binário** carrega frames FlatBuffers (browser não faz socket cru — doc 02 §4).
- Realtime (`StreamAtendimentos`) sobre o framing de stream do `transport` (`STREAM_ITEM`/`STREAM_END`).
- gRPC fallback comutável por config sem mudar handlers.

### 8.1 DoD RF5

- [ ] login e um **stream de realtime** funcionam por FlatBuffers (TCP/TLS e WS).
- [ ] fallback gRPC comutável por `SMARTCORE_RUNTIME_API_CODEC=grpc` sem tocar handlers.

---

## 9. RF6 — Demais serviços de domínio

**Objetivo:** `messaging_gateway`, `worker`, `control_plane` nascem/migram como serviços por contrato; `ia_engine` (Python) entra com codec FlatBuffers (gRPC fallback).

**Agente:** `backend-specialist` (Rust) + `devops-specialist` (ia_engine Python/GPU). **Fase PREVC:** Execution (E6).

- `ia_engine`: FlatBuffers em Python via `flatc --python` (do `.fbs` gerado do `.proto`); fallback gRPC via `grpcio/grpcio-tools 1.62.1`. Pronto para VM com GPU (troca `unix://`→`tcp://` por config — doc 01 §4.1).
- **Nota interop (info_aux §2):** `flatc --grpc` **não cobre Rust**; o fallback gRPC usa **prost/tonic** sobre o `.proto` (não FB-over-gRPC) — coerente com `GrpcCodec`.

### 9.1 DoD RF6

- [ ] mensagem do webhook → `worker` → `data_postgres` → realtime, tudo por contrato.
- [ ] promoção de um serviço a `tcp://` validada **só por config** (ensaio com `ia_engine`).

---

## 10. Tratamento especial das convenções (erro/observabilidade)

- `error_core` e `observability` **não ganham app** em nenhuma fase — permanecem libs (convenções).
- O trabalho nelas (RF1) é expor o **formato de fronteira** (`ErrorEnvelope`, `traceparent`, dado compilado nos dois lados) e o **rewire da auditoria** para o bus, que **remove o ciclo** `observability → infrastructure_postgres` (alinhado à memória `arquitetura-erros-observabilidade`).
- Ao mover um serviço para outra VM (RF5/RF6+), nada nessas convenções muda: a lib já está compilada no serviço; o coletor OTLP já junta os traces.

---

## 11. Riscos e mitigações (atualizados)

| Risco | Impacto | Mitigação |
|---|---|---|
| `.proto`→`.fbs` mapeia `bytes`→`string` (payload) | Round-trip quebra | asserção `bytes`↔`[ubyte]` no CI (RF0); escape hatch: `.fbs` à mão para a mensagem |
| Construir runtime FlatBuffers (mux/keepalive/reconexão) é trabalhoso | Atraso na fundação | gRPC fallback desde RF0; runtime incremental nos caminhos quentes |
| Redis `allkeys-lru` evicta Streams do bus | Perda de eventos/auditoria | instância/namespace `noeviction` p/ bus (RF1 §4.5) |
| Consistência eventual surpreende a UI | "li antes de escrever" | RPC direto (escrita-com-ack) p/ leitura/auth (doc 03 §3) |
| `flatc` ausente/versão divergente no CI | Build não determinístico | fixar `flatc v25.12.19`; casar major.minor com crate `25` |
| Overhead de N processos | Deploy complexo | supervisão (compose/systemd) + OTLP cedo |

---

## 12. Definition of Done global

- [ ] `transport` + `contracts` com envelope (tenant+traceparent+erro) e codec comutável; **`.proto` canônico** gerando ambos os formatos.
- [ ] `error_core`/`observability` permanecem libs; ciclo `observability→postgres` removido; trace distribuído provado em 2 processos.
- [ ] `data_postgres`/`data_redis`/`data_storage` como serviços por contrato (RPC direto + bus), RLS e outbox preservados.
- [ ] `application` sem chamada direta a repositório; auth via RPC direto (escrita-com-ack).
- [ ] `runtime_api` FlatBuffers (desktop+web) com gRPC fallback comutável.
- [ ] Promoção de um serviço a `tcp://` validada só por config (ensaio `ia_engine`).
- [ ] Lint/test por stack verdes; comentários pt-br; sem segredos.

---

## 13. Correções aplicadas

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| **1 (manchete)** | **Fonte canônica invertida de `.fbs` para `.proto`.** `tonic-build`/`prost` geram gRPC direto; `flatc --proto`→`.fbs`→`flatc --rust` geram FlatBuffers. FlatBuffers permanece **codec de fio padrão**. | `flatc` **não** transpila `.fbs`→`.proto`; a direção nativa é a inversa. Mantém o objetivo do dono ("uma fonte, ambos os formatos") só mudando o IDL autorado. | `info_aux` §"ACHADO CRÍTICO"; `flatc` docs |
| 2 | RF0 §3.2: subconjunto comum + asserção `bytes`↔`[ubyte]` no round-trip | `.proto`→`.fbs` é best-effort; `bytes` pode virar `string` | `info_aux` §flatc, nota 1 |
| 3 | `build.rs` usa `tonic_build::configure().compile_protos(...)` com **protoc embutido**; instala-se só `flatc` | `protoc` vem embutido no tonic-build 0.14.6 | `info_aux` §tonic-build, nota 3 |
| 4 | `build.rs` FlatBuffers via `flatc-rust 0.2` (ou `Command`), `cargo:rerun-if-changed=schemas` | padrão atual da crate flatbuffers 25.x | `info_aux` §flatbuffers |
| 5 | `ErrorCategory`/`Severity` desserializados com `TryFrom<i32>` (não `from_i32`) | `from_i32` depreciado no prost 0.13 | `info_aux` §prost, nota 5 |
| 6 | RF1: auditoria publica no Streams via `transport::bus`; remove dep `observability→infrastructure_postgres` | quebra o ciclo; deixa a convenção sem I/O de banco | doc 04; memória arquitetura-erros |
| 7 | RF1 §4.5: Redis do bus com `noeviction` (separar do `allkeys-lru`) | `allkeys-lru` evicta Streams sob pressão | `info_aux` §infra-dados, nota 6 |
| 8 | RF2 §5.3: migration `0011_outbox` (tabela+trigger NOTIFY) | outbox precisa de tabela+trigger; LISTEN/NOTIFY pronto no pg16 | `info_aux` §infra-dados; sqlx |
| 9 | RF6: fallback gRPC usa prost/tonic (não FB-over-gRPC); `flatc --grpc` não cobre Rust | `flatc --grpc --rust` não implementado | `info_aux` nota 2 |
| 10 | `TenantEnvelope` migra para `contracts`; `event_bus` vira `transport::bus` | o próprio código (`envelope.rs`) já anota; de-risk rewire | `infrastructure_redis/src/{envelope,event_bus}.rs` |

**Alternativa B (fallback se o dono recusar a inversão):** manter `.proto` (gRPC) e `.fbs` (FlatBuffers) como **fontes separadas**, sem conversão automática — custa duplicação de schema e um **teste de paridade** entre os dois IDLs (exatamente o que a fonte única evita). Registrada como contingência; não é a recomendação.

---

## 14. Mapeamento PREVC para o plano canônico (MCP dotcontext)

**Escala sugerida: LARGE** (refator estrutural multi-crate/multi-serviço, toolchain nova, migrations e docker, 7 milestones de execução).

| Fase PREVC | Nome | Agente sugerido | O que entra |
|---|---|---|---|
| **P — Planning** | Fundação de contrato e decisões | `backend-specialist` | Confirmar inversão `.proto`-canônica com o dono; congelar o subconjunto comum do schema; desenho de `contracts`/`transport`; decisões de eviction Redis e outbox; este plano canonizado |
| **R — Review** | Revisão do contrato + segurança | `code-review` + `security-audit` | Revisar `envelope.proto`/`errors.proto`, framing, mTLS entre VMs, anti-enumeração no auth, política de log/auditoria; aprovar arquitetura antes de E |
| **E — Execution** | Construção faseada (RF0–RF6) | conforme cada RF (ver abaixo) | **E0=RF0** (backend+devops), **E1=RF1** (backend+database), **E2=RF2** (database+backend), **E3=RF3** (backend+devops), **E4=RF4** (backend+test-writer), **E5=RF5** (backend+test-writer), **E6=RF6** (backend+devops) |
| **V — Validation** | Interop / trace / multi-tenant | `test-writer` | Interop FB↔gRPC do mesmo `method`; round-trip `bytes`↔`[ubyte]`; trace distribuído em 2 processos; RLS multi-tenant; promoção `unix://`→`tcp://` por config |
| **C — Confirmation** | Final-review + arquivamento | `prevc-final-review` (Opus) | Auditar implementado vs plano; corrigir desvios; atualizar docs 00–10; arquivar em `archive/` |

**Milestones de Execução (RF→agente→PREVC):**

| Milestone | RF | Agente lead | Co-agentes | Docker/migrations |
|---|---|---|---|---|
| E0 | RF0 contrato/transporte | backend-specialist | devops-specialist | volume UDS; flatc no CI |
| E1 | RF1 transversais/rewire | backend-specialist | database-specialist | Redis bus `noeviction` |
| E2 | RF2 data_postgres | database-specialist | backend-specialist | migration `0011_outbox`; UDS compose |
| E3 | RF3 data_redis/storage | backend-specialist | devops-specialist | MinIO/storage; sockets |
| E4 | RF4 application/auth | backend-specialist | test-writer | — |
| E5 | RF5 runtime_api | backend-specialist | test-writer | TCP/TLS, WS |
| E6 | RF6 domínio/ia_engine | backend-specialist | devops-specialist | VM GPU (TCP/TLS) |

> Próximo passo operacional (memória `planejamento-via-plan-restructuring`): finalizar via `/plan-restructuring` — `scaffoldPlan` + `workflow-init` referenciando este `plano_completo_*` e o `info_aux_*`, deixando o workflow PREVC LARGE pronto para implementação.

---

*Plano completo reestruturado. Pronto para canonização via MCP dotcontext.*
