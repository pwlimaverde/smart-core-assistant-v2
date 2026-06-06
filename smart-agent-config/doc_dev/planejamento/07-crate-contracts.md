# 07 — Crate de Contratos (`contracts`)

> **Status:** ✅ Concluída (Fase 0 e Fase 1). Crate `server/crates/contracts` totalmente implementada, atuando como o núcleo de schemas e tipos serializados para rede e IPC.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular. Estabelecimento da pipeline de contratos no Cargo workspace.

---

## 1. Objetivo

Concentrar em uma única crate **sem I/O direto** (`server/crates/contracts`) **todos os esquemas de comunicação e serialização de dados** que cruzam fronteiras de processos (IPC/RPC via Unix Domain Sockets) e barramentos de mensageria (Redis Streams). 

A crate serve como a **única fonte de verdade** para:
- Schemas protobuf (`.proto`) e FlatBuffers (`.fbs`).
- Estruturas de dados tipadas para serialização e desserialização de DTOs e eventos.
- O `Envelope` unificado contendo o roteamento de tenant (`tenant_id`), observabilidade (`traceparent`) e controle de versão.

---

## 2. Pipeline de Contratos (Compilação Automatizada)

Ao contrário do planejamento inicial conceitual que previa o gerenciamento manual e separado de arquivos `.proto` e `.fbs`, a implementação física estabeleceu uma **pipeline integrada de transpilação no build**:

1. **Fonte Única Canônica**: Todos os contratos e DTOs são autorados como arquivos `.proto` no diretório `server/crates/contracts/schemas/`, organizado por domínio: `envelope.proto`, `errors.proto`, `ai/ai_engine.proto`, `events/message.proto`, `events/persistence.proto`, `queries/auth.proto`, `queries/conversation.proto`.
2. **Transpilação via `build.rs`**: O arquivo `build.rs` da crate `contracts` executa o compilador `flatc` para transpilar automaticamente os arquivos `.proto` para esquemas FlatBuffers (`.fbs`), gerando os wrappers de serialização.
3. **Geração de Stubs Rust**: O `build.rs` gera código Rust idiomático tanto para o codec FlatBuffers (usado no IPC local por UDS) quanto para Tonic/gRPC (usado como fallback de comunicação TCP e rede).
4. **Benefício**: Elimina conflitos de importação circular e incompatibilidades de namespaces no compilador do FlatBuffers, garantindo que o mesmo schema de dados alimente ambos os transportes.

---

## 3. Os dois envelopes (RPC vs. barramento)

A crate expõe **dois** invólucros que coexistem, cada um para um transporte — não há
substituição de um pelo outro:

### 3.1 `Envelope` (protobuf/FlatBuffers) — RPC IPC/gRPC

Definido canonicamente em `schemas/envelope.proto` (`package smartcore.contracts`) e
gerado para gRPC (Tonic) e FlatBuffers. Embrulha **toda chamada RPC** entre serviços
(UDS/FlatBuffers e gRPC fallback). Campos:

- **`tenant_id`** (`string`): UUID do tenant (vazio = superuser/global).
- **`schema_version`** (`uint32`): versão do schema (evolução aditiva).
- **`message_id`** (`string`): UUIDv7 — ordenável e idempotente.
- **`causation_id`** (`string`): id da mensagem que causou esta.
- **`traceparent`** (`string`): W3C TraceContext, propaga o trace entre VMs.
- **`occurred_at`** (`int64`): epoch em **milissegundos**.
- **`kind`** (`MessageKind`): `EVENT` | `REQUEST` | `REPLY` | `STREAM_ITEM` | `ERROR`.
- **`method`** (`string`): nome lógico (ex.: `PutFile`, `GetThread`).
- **`payload`** (`bytes`): corpo FlatBuffers, opaco ao transporte.
- **`error`** (`ErrorEnvelope`): preenchido só quando `kind = ERROR`.

### 3.2 `TenantEnvelope<T>` (genérico Rust, serde/JSON) — barramento de eventos

Definido em `src/envelope.rs`. Embrulha **eventos publicados no Redis Streams**
(`transport::bus`). É um genérico serde (serializado em JSON no stream). Campos:
`tenant_id`, `event_id` (UUIDv7), `event_type`, `timestamp`, `traceparent` e `payload: T`.

> **Regra:** RPC entre serviços usa o `Envelope` protobuf; eventos assíncronos no
> barramento usam o `TenantEnvelope<T>`. Ambos carregam `tenant_id` e `traceparent`
> para isolamento multi-tenant e trace distribuído.

---

## 4. Decisões arquiteturais consolidadas

| # | Decisão | Escolha | Racional |
|---|---------|---------|----------|
| C1 | Crate sem I/O direto | Tipos puros, sem importação de `sqlx`, `tokio` ou `redis` | Qualquer serviço consome a crate sem acoplar runtime de persistência ou rede. |
| C2 | Pipeline integrada | `.proto` → transpilação `.fbs` no `build.rs` | Garante consistência absoluta de schemas de dados entre gRPC e FlatBuffers sem duplicação de esforço. |
| C3 | Nome do pacote de transporte | `Envelope` unificado | Simplifica serialização/desserialização direta sobre o barramento e IPC de rede. |
| C4 | Nomes de eventos desacoplados | `MessageReceived`, `MessageUpdate`, `ContactsUpsert` | Camadas de domínio e regras de negócio não dependem do formato do Evolution Gateway. |
| C5 | Geração automática | `tonic-build` + `flatc` integrado ao pipeline Cargo | Stubs são atualizados em tempo de compilação sem intervenção manual. |

---

## 5. Estrutura de módulos da crate

A estrutura física em `server/crates/contracts/` está organizada da seguinte forma:

- **`schemas/`**: Arquivos `.proto` (por domínio) que especificam os contratos RPC, o `Envelope` e os erros.
- **`generated/fbs/`**: Esquemas FlatBuffers (`.fbs`) transpilados a partir dos `.proto` (versionados como artefato intermediário).
- **`build.rs`**: Script de automação que executa o `flatc` e o `tonic-build` no Cargo workspace.
- **`src/lib.rs`**: Re-exporta os módulos gRPC (`tonic::include_proto!`) e os tipos FlatBuffers gerados em `OUT_DIR` para consumo transparente das demais crates.
- **`src/envelope.rs`**: Define o `TenantEnvelope<T>` (genérico serde) usado nos eventos do barramento.

---

## 6. Testes e Validação

- Testes de round-trip integrados validam que DTOs serializados em FlatBuffers podem ser lidos e convertidos para estruturas de dados equivalentes sem corrupção.
- O build script falha a compilação do Cargo workspace se houver erros de linting nos arquivos `.proto`.

---

*Documento de planejamento de contratos revisado e consolidado.*
