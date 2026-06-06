# Final Review — refator-arquitetura-modular
Data: 2026-06-05 · Modelo: Opus · Branch: feature/refator-arquitetura-modular · Commit do ciclo: eb426b9

## Veredito de qualidade: CORRIGIDO
## Veredito de gate (arquivamento): INCOMPLETO — plano não arquivado

A implementação está fiel ao plano na decisão de manchete (`.proto` canônico, FlatBuffers como
codec padrão, `bytes`→`[ubyte]` correto) e nos RFs centrais. Havia defeitos reais de qualidade
(clippy `-D warnings` quebrando em `build.rs`, `codec.rs`, `runtime.rs`, `worker`,
`observability/audit`, mais um `format!` inútil que mascarava um traceparent inválido hardcoded)
e desformatação geral. Todos corrigidos e revalidados. Os apps de domínio marcados como stub
permanecem stubs (conforme commit/plano), compilam e passam clippy.

**Por que INCOMPLETO no gate:** as fases R/E/V/C do plano continuam `pending` no frontmatter e há
stubs intencionais por completar (`control_plane`, realtime/WS de `runtime_api`, handlers mock).
O ciclo PREVC não está fechado — a auditoria acima é um **checkpoint de qualidade** do trabalho
parcial, não a liberação de arquivamento.

## 1. Plano vs. Implementado
| Item do plano (RF) | Status | Observação |
|---|---|---|
| RF0 — `.proto` canônico → prost+fbs no `build.rs` | ✅ | `tonic_prost_build` (crate correto do split tonic 0.14) + `flatc --proto`→`.fbs`→`flatc --rust`. `payload:[ubyte]` confirmado em `generated/fbs/envelope.fbs:25` (NÃO virou `string`). |
| RF0 — `find_protoc`/protoc vendorizado | ➕ | O plano (§13.3) afirmava "protoc embutido no tonic-build". **Verificado falso para prost-build 0.14.3** (sem `protoc-bin-vendored`/`protobuf-src` na árvore). O `protoc.exe` vendorizado em `server/bin/` é **necessário, não redundante**. Código correto; o plano estava desatualizado. |
| RF0 — Codec FB/gRPC comutável | ✅ | `codec.rs`: `FlatbuffersCodec`/`GrpcCodec` + `from_env`. |
| RF0 — Framing len/flags/corr_id | ✅ | `framing.rs` conforme spec do plano §3.7. |
| RF0 — Runtime mux/timeout/backpressure | ⚠️ | `MuxClient` (corr_id→oneshot, mpsc bounded(100), timeout) ok. **Sem keepalive/reconexão/backoff** (plano §3.8 previa "incremental"); read_loop só loga e encerra na queda. Aceitável como fundação; ver Pendências. |
| RF0 — `transport::bus` (reaproveita event_bus) | ✅ | `bus.rs` com `STREAM_EVENTOS`+`STREAM_SEGURANCA`, consumer group, XACK, reprocessamento PEL e `Consumer`. `infrastructure_redis` perdeu `event_bus.rs` e reexporta de `transport::bus`. |
| RF1 — `ErrorEnvelope` + 6 categorias novas | ✅ | `code.rs` +6 categorias no fim (disciplina respeitada); `envelope_bridge.rs` com `to_error_envelope`/`from_envelope`. |
| RF1 — `TryFrom<i32>` (não `from_i32`) | ✅ | prost gera enums como `i32`; código usa `as i32`/`.0` direto, sem `from_i32` depreciado. |
| RF1 — traceparent no Envelope | ✅ | Campo presente e propagado nos handlers (exceto worker, corrigido). |
| RF1 — rewire auditoria p/ Streams | ✅ | `audit.rs` publica em `STREAM_SEGURANCA` via `transport::bus`; consumidor de consolidação em `data_postgres`. |
| RF1 — remover ciclo `observability→postgres` | ⚠️ | `infrastructure_postgres` virou `optional`, **mas `default=["postgres-audit"]`** ainda puxa postgres no build padrão. Não é ciclo de compilação real, mas o DoD "Cargo.toml sem dependência" não foi cumprido à risca. Ver Pendências. |
| RF2 — `data_postgres` (RPC+consumer+relay+outbox) | ✅ | `main.rs`: server 3 protocolos, consumer de auditoria, `OutboxRelay` (PgListener+reconexão), handlers com RLS e padrão outbox na mesma transação. |
| RF2 — migration `0011_outbox` | ✅ | Tabela + trigger `outbox_notify`/`pg_notify('outbox_new')`. |
| RF3 — `data_redis`/`data_storage` | 🟡/✅ | `data_redis` e `data_storage` implementados como serviços req/reply; `infrastructure_storage` criada. |
| RF4 — `application`/auth via contrato | ✅ | `auth/login.rs` fala por `transport::conectar_cliente` (RPC), sem repositório direto; `from_envelope` na borda. |
| RF5 — `runtime_api` | 🟡 | Server FB/gRPC + handlers Login/StreamAtendimentos; stream/WS realtime ainda mock (stub por design). |
| RF6 — `messaging_gateway`/`worker`/`control_plane` | 🟡 | Topologia ponta-a-ponta (gateway→bus→worker→data_postgres RPC); `control_plane` e parte do realtime são stubs declarados. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `crates/contracts/build.rs:18-23` | clippy `collapsible_if` | Fundido em `if cond && cond`. |
| `crates/contracts/build.rs:108` | clippy `unnecessary_map_or` | `map_or(false, …)` → `is_some_and(…)`. |
| `crates/contracts/build.rs:125,127` | clippy `single_char_add_str` | `push_str("\n")` → `push('\n')`. |
| `crates/transport/src/codec.rs:50,51,80,125,126,145` | clippy `unnecessary_cast` (`i32`→`i32`) | Removido `as i32` nos construtores FB de enum. |
| `crates/transport/src/runtime.rs:107` | clippy `redundant_pattern_matching` | `if let Err(_) = …` → `… .is_err()`. |
| `apps/worker/src/main.rs:80` | clippy `useless_format` **e** traceparent W3C inválido hardcoded (`"00-000…-00"`) quebrando propagação de trace (RF1) | `String::new()` com TODO(RF6) p/ propagar traceparent do evento. |
| `crates/observability/src/audit.rs:1` | clippy `too_many_arguments` (5 funções 8–9 args) | `#![allow(clippy::too_many_arguments)]` no módulo (padrão já usado em `infrastructure_redis`), justificativa pt-br. |
| 24 arquivos in-scope | `cargo fmt --check` falhava | `cargo fmt` aplicado; revertido nos 13 arquivos fora do escopo (ciclos anteriores). |

## 3. Decisões Autônomas (revisar depois)
- **`observability/audit.rs` `#![allow(too_many_arguments)]`**: suprimido (consistente com `infrastructure_redis`) em vez de introduzir struct de contexto, para não alterar a API pública da auditoria neste ciclo. Refatorar para `AuditEvent` é o caminho limpo futuro.
- **`cargo fmt` no working tree**: reformatados só os arquivos do commit eb426b9; arquivos de ciclos anteriores revertidos (mantêm débito de fmt pré-existente).

## 4. Revalidação
- fmt: ✅ (in-scope) — limpo para todos os arquivos do commit. 13 arquivos de ciclos anteriores com débito de fmt pré-existente (fora do escopo).
- clippy: ✅ — `cargo clippy -p contracts -p transport -p application -p error_core -p observability -p infrastructure_storage -p infrastructure_redis -p messaging_gateway -p worker -p runtime_api -p control_plane -p data_redis -p data_storage --all-targets -- -D warnings` → exit 0. `data_postgres` validado à parte com `SQLX_OFFLINE=true` → exit 0.
- build contracts: ✅ — `cargo build -p contracts` (gera prost + fbs via `flatc 25.12.19` e `protoc 25.1` vendorizados em `server/bin/`) → exit 0.
- testes: N/A (não executados por diretriz).

## 5. Pendências (escopo extra ou fora do plano / stubs a completar)
- **Runtime de transporte** (`transport/src/runtime.rs`): falta keepalive (ping periódico), reconexão com backoff+jitter e detecção de conexão morta. Plano §3.8 admitia "incremental"; concluir nos caminhos quentes.
- **Ciclo `observability→infrastructure_postgres`**: feature `postgres-audit` é `default`. Para cumprir o DoD RF1 à risca, remover do `default` (deixar em feature de teste) e validar build de produção sem postgres.
- **`worker` traceparent**: `EventoBruto` não carrega `traceparent`; o salto bus→RPC inicia novo trace. Para trace distribuído ponta-a-ponta (DoD RF1/RF6), carregar o traceparent no evento do bus.
- **Taxonomia `AppError` x proto**: `from_envelope`/`category()` nunca produzem `Permission`/`RateLimit`/`Timeout`/`Dependency`/`NotFound` (mapeiam p/ `Internal`); `RATE_LIMIT_EXCEEDED` não tratado em `from_envelope`. Limitação de design, não defeito de compilação.
- **Stubs por design (manter)**: `control_plane`, realtime/WS de `runtime_api` (`StreamAtendimentos` mock), handlers mock de `data_postgres` (`GetThread`). Declarados no commit ("app topology stubs").
- **Compose UDS**: volume de sockets compartilhado para containerização dos `apps/` ainda não previsto (esperado para RF2+).
