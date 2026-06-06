# Documentação Auxiliar — Refator de Arquitetura Modular por Contrato

> Gerado em: 2026-06-05
> Plano canônico: `.context/plans/refator-arquitetura-modular.md`
> Plano completo: `.context/plans/refator-arquitetura-modular/plano_completo_refator-arquitetura-modular.md`
> Origem: `doc_dev/planejamento/refator-arquitetura-modular/05-refator-estado-atual.md` (+ docs 01–04)

---

## ⚠️ ACHADO CRÍTICO — o transpile `.fbs` → `.proto` do plano NÃO é suportado pelo `flatc`

O plano-base (doc 02 §1 e doc 05 RF0) assume que **"o `build.rs` gera o `.proto` a
partir do `.fbs`"** — uma fonte canônica `.fbs` produzindo ambos os formatos. **Isso
não é possível com o `flatc`:**

- `flatc` **não** converte `.fbs` → `.proto` (não existe flag para essa direção).
- A direção **suportada nativamente é a inversa**: `flatc --proto` lê um `.proto` e
  **gera o `.fbs`** (best-effort, com `--oneof-union` para mapear `oneof`→`union`).
- Ferramenta de terceiros `fbs2proto` (Go) existe, mas é **experimental, sem manutenção
  desde 2019** e exige ajustes manuais — **não confiável** para um build determinístico.
- `flatc --grpc` **não é implementado para Rust** (só C++/Go/Java/Python parcial). FB-
  over-gRPC em Rust dependeria do experimental `flatbuffers-tonic` — fora do caminho do
  fallback, que usa **prost/tonic (Protobuf padrão)**.

### Decisão recomendada (a confirmar pelo dono no plano completo): inverter a fonte canônica para `.proto`

Mantém **literalmente** o objetivo do dono ("uma fonte canônica, ambos os formatos
gerados no build") — só **inverte qual IDL é autorado**:

| Aspecto | Plano original (inviável) | Recomendado (viável) |
|---|---|---|
| Fonte autorada | `.fbs` | **`.proto`** (canônica em `contracts/schemas/`) |
| Gera FlatBuffers | `flatc --rust` direto | `flatc --proto` (`.proto`→`.fbs`) → `flatc --rust` |
| Gera gRPC/Protobuf | transpile `.fbs`→`.proto` (**não existe**) | `tonic-build`/`prost` direto do `.proto` |
| Codec de fio padrão | **FlatBuffers** | **FlatBuffers** (inalterado — decisão do dono preservada) |
| `id:`/field number | explícito no `.fbs` | **nativo** do Protobuf (de graça) |

> **A decisão "FlatBuffers-first" do dono NÃO é revertida.** FlatBuffers continua o
> **codec de fio padrão** (zero-copy); só a **fonte de autoria** vira `.proto`, que é o
> IDL com transpile nativo para os dois lados e já obriga `field number` explícito.
> Bônus: `tonic-build` traz `protoc` **embutido** (não precisa instalar `protoc` no
> Windows). Custo: a conversão `.proto`→`.fbs` é best-effort — atenção ao mapeamento
> `bytes`↔`[ubyte]` (pode virar `string`); validar no round-trip do CI.

Alternativa B (híbrida, se o dono recusar inverter): manter `.proto` para gRPC e `.fbs`
para FlatBuffers como **fontes separadas**, sem conversão automática — custa duplicação
e um teste de paridade (o que o plano queria evitar).

---

## Libs Rust

### flatbuffers (`25.x` — série `YY.MM.DD`, `flatc v25.12.19`)
> Fonte: Context7 `/google/flatbuffers` + verificação de releases GitHub (2026-06-05).
> Doc local: `doc_dev/libs/rust/flatbuffers.md`.

- **Crate:** `flatbuffers = "25"`. **Compatibilidade:** `flatc` e crate devem casar em
  **major.minor** (Context7 reportou 24.3.x defasado; releases apontam 25.x).
- **Runtime:** `FlatBufferBuilder::with_capacity(n)` → `create_string`/`create_vector`
  (reference types **antes** das tabelas) → `finish()` → `finished_data()`. Leitura
  zero-copy via `root_as_<Tipo>(buf)`.
- **Tipos:** `enum` (com valor zero), `union` (checa `*_type()` e desembrulha
  `*_as_<Tipo>()`), `[X]`→`Vector<T>`, `[ubyte]` binário, `string` UTF-8.
- **Evolução aditiva:** campos novos **no fim** com default; `(deprecated)` para aposentar;
  nunca remover/reinserir/renumerar/trocar tipo. `flatc --conform` valida evoluções.
- **build.rs:** crate helper `flatc-rust = "0.2"` (`Builder::new().inputs(&["schemas/"]).out_dir(...).build()`)
  ou `std::process::Command::new("flatc")`. `cargo:rerun-if-changed=schemas/`.

### prost (`0.13.x` — compatível com tonic 0.14)
> Fonte: Context7 `/tokio-rs/prost`. Doc local: `doc_dev/libs/rust/prost.md`.

- **Versão:** `prost = "0.13"` (estável, compatível com tonic 0.14.x; sem breaking vs 0.12).
- **Mensagens:** `#[derive(prost::Message)]` + `#[prost(<tipo>, tag = "N")]` por campo.
- **Encode/decode:** `msg.encode(&mut buf)?` / `Message::decode(&bytes[..])?`.
- **Mapeamento Protobuf→Rust:** escalares (`double`→`f64`…), `string`→`String`,
  `bytes`→`Vec<u8>`, `repeated`→`Vec<T>`, `oneof`→`Option<Enum>` com variantes, `enum`
  armazenado como `i32` (validar com `TryFrom<i32>`; `from_i32` está depreciado).
- **Build:** `prost-build` é usado **por baixo** do `tonic-build` — normalmente não se
  chama `prost-build` direto.

### tonic-build (`0.14.6` — alinhado a tonic 0.14.6)
> Fonte: Context7 (tonic 0.14.6). Doc local: `doc_dev/libs/rust/tonic-build.md`.

- **build.rs:** `tonic_build::configure().build_server(true).build_client(true).compile_protos(&["proto/x.proto"], &["proto/"])?;`
  ou `tonic_build::compile_protos("proto/x.proto")?`.
- **`protoc` EMBUTIDO:** tonic-build 0.14.6 traz binário `protoc` pré-compilado por
  arquitetura — **não precisa instalar `protoc` no Windows**. Reduz risco de toolchain.
- **Saída:** incluída via `tonic::include_proto!("pacote")` no `lib.rs`.
- **Sem breaking 0.12→0.14** significativo; melhor compat com prost 0.13/0.14, `Default`
  automático em mensagens.

### tonic (`0.14.6`) — USAR LOCAL
> Doc local: `doc_dev/libs/rust/tonic.md` (✅ 2026-06-04). Codec/transporte gRPC de
> **fallback** plugável (já no workspace). Library ID `/hyperium/tonic`.

### redis (`0.25.0`) — USAR LOCAL
> Doc local: `doc_dev/libs/rust/redis.md` (✅ 2026-05-31). **Redis Streams** (consumer
> groups, `XADD`/`XREADGROUP`) é o substrato do **bus** (modo Evento) que sai de
> `infrastructure_redis::event_bus` para `transport::bus`. Também cache/token (papel
> `data_redis`). Features já no workspace: `aio,tokio-comp,connection-manager,streams`.

### tokio (`1.38.0`) — USAR LOCAL
> Doc local: `doc_dev/libs/rust/tokio.md` (✅ 2026-05-31). **UDS** (`tokio::net::UnixListener`/
> `UnixStream`), runtime da camada `transport` (mux por `corr_id`→`oneshot`, keepalive,
> reconexão com backoff, `tokio::time::timeout`, `mpsc` bounded p/ backpressure).

### opentelemetry (`0.31/0.32`) — USAR LOCAL
> Doc local: `doc_dev/libs/rust/opentelemetry.md` (✅ 2026-06-04). OTLP (grpc-tonic) já em
> `observability`; W3C trace context (`propagation`) → liga `traceparent` do `Envelope`.
> Coletor OTLP sobe cedo (stack LGTM já em `docker/observability`).

### sqlx (`0.9.0`) — USAR LOCAL
> Doc local: `doc_dev/libs/rust/sqlx.md` (✅ 2026-06-01). `LISTEN/NOTIFY` (`PgListener`)
> para o **relay de outbox** do `data_postgres`; transações RLS (`run_in_tenant_transaction`),
> migrations 0001–0010. `SQLX_OFFLINE` nos testes.

## Libs Python (RF6 — tangencial)

### grpcio / grpcio-tools (`1.62.1`) — USAR LOCAL
> Doc local: `doc_dev/libs/python/grpcio.md` (✅ 2026-05-31). Fallback gRPC do `ia_engine`.
> FlatBuffers em Python via `flatc --python` (do `.fbs` gerado do `.proto`).

---

## Serviços Externos / Toolchain

### `flatc` — compilador FlatBuffers (build tooling)
> Fonte: WebSearch/WebFetch oficiais (github.com/google/flatbuffers, flatbuffers.dev).

- **Versão atual:** `v25.12.19` (versionamento `YY.MM.DD`). Suporte a Rust edition 2024.
- **Instalação (Windows):** binário pré-compilado dos *releases* do GitHub (recomendado),
  `choco install flatbuffers`, `vcpkg install flatbuffers:x64-windows`, ou build via CMake.
  Verificar com `flatc --version`. **Fixar a versão no repo/CI** para builds reproduzíveis.
- **Codegen:** `flatc --rust|--python|--dart -o <out> -I <inc> schema.fbs`.
- **`flatc --proto -o schemas/ x.proto`** → gera `.fbs` a partir de `.proto` (com
  `--oneof-union` p/ `oneof`→`union`). **É a única direção de transpile suportada.**
- **`flatc --grpc --rust`:** ❌ não implementado (emite aviso e gera só os tipos).
- **Subconjunto comum `.proto`↔`.fbs`:** field number explícito (nativo no proto),
  `enum` com zero, `oneof`↔`union`, evitar `struct` de layout fixo e `service`/`rpc`
  (ignorados na conversão). Armadilha: `bytes` pode virar `string` — revisar/validar.

### Stack de observabilidade (LGTM) — já provisionada
> `docker/compose/observability.yml` + `docker/observability/` (otel-collector, tempo,
> loki, prometheus, promtail, grafana provisioning, dashboard `audit_log.json`). O coletor
> OTLP junta os traces dos N processos — observabilidade **não** vira serviço de domínio.

---

## Infra de dados atual (relevante p/ RF2/RF3 e nota do dono "pode refazer os docker dos bancos")
> `docker/compose/data.yml`. Projeto em estágio inicial — docker pode ser ajustado livre.

- **PostgreSQL 16 + pgvector** (`pgvector/pgvector:pg16`), RLS, init `01-extensions.sql`.
  `LISTEN/NOTIFY` (relay de outbox) **funciona sem config extra**. Outbox precisa de
  **tabela + trigger** via migration nova (segue 0001–0010).
- **Redis 7-alpine** com `--appendonly yes` (durabilidade p/ Streams), `--maxmemory 150mb`
  `allkeys-lru`. Streams já disponível; **atenção:** `allkeys-lru` pode **evictar entradas
  de Stream** sob pressão — para o bus durável, considerar política/instância separada ou
  `noeviction` no namespace do bus (revisar no RF1/RF3).
- **MinIO** (S3-compat) p/ `data_storage` (mídia; R2 em prod).
- **UDS:** os apps `data_*`/serviços conversam por `unix:///var/run/smartcore/<svc>.sock`
  — exige **volume/diretório de sockets** compartilhado entre containers (ou rodar fora de
  container na fase atual). Ajuste de compose previsto quando os `apps/` nascerem.

---

## Notas Gerais (breaking changes / gotchas)

1. **`.fbs`→`.proto` não existe** → inverter para `.proto`-canônico (ou híbrido). É o
   ponto que mais muda o desenho da crate `contracts` (RF0).
2. **`flatc --grpc` não cobre Rust** → o fallback gRPC usa **prost/tonic** sobre o
   `.proto` (não FB-over-gRPC). Coerente com o plano (GrpcCodec usa prost/tonic).
3. **`protoc` embutido no tonic-build 0.14.6** → não instalar protoc; instalar **só** o
   `flatc` na máquina/CI.
4. **`flatc` deve estar no PATH** do build (ou usar `flatc-rust`) → documentar no
   `development-workflow`/CI; fixar versão.
5. **prost:** `enum`→`i32`; validar com `TryFrom<i32>` (`from_i32` depreciado).
6. **Redis `allkeys-lru`** pode evictar Streams do bus → revisar política no RF1/RF3.
7. **Versionamento de schema:** evolução aditiva (FlatBuffers favorece); teste vira
   **interop** FB↔gRPC do mesmo `method` (não paridade de schema, pois é gerado).
