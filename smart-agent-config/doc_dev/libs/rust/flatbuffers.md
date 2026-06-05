# FlatBuffers (Rust)

## Informações Gerais

| Campo | Valor |
| --- | --- |
| **Versão Recomendada** | `flatbuffers = "25"` (série `25.x`, versionamento `YY.MM.DD`; release verificada `flatc v25.12.19`) |
| **Status de Atualização** | ✅ ATUALIZADA |
| **Última Verificação** | 2026-06-05 |
| **Propósito no Projeto** | Codec padrão (zero-copy) da camada de contrato/transporte; tipos gerados de schemas `.fbs` |
| **Library ID Context7** | `/google/flatbuffers` |
| **Fonte Oficial** | https://github.com/google/flatbuffers |

> **Compatibilidade flatc ↔ crate:** o binário `flatc` e a crate `flatbuffers` devem
> casar em **major.minor** (ex.: `flatc 25.x` com `flatbuffers = "25"`). O Context7
> reportou `24.3.x` (defasado); a verificação direta nos *releases* do GitHub
> (2026-06-05) aponta a série `25.x` como atual.
>
> **⚠️ `flatc` NÃO gera `.proto` a partir de `.fbs`.** A direção nativa é a inversa
> (`flatc --proto` lê `.proto` e gera `.fbs`). Isso impacta o desenho da crate
> `contracts` — ver decisão no plano `refator-arquitetura-modular`.

---

## Resumo Executivo

FlatBuffers é uma biblioteca de serialização que oferece **acesso direto aos dados serializados sem parsing**, garantindo máxima eficiência de memória e compatibilidade forte em ambos os sentidos (forward/backward compatibility).

### Principais Características
- **Zero-copy**: leitura direta do buffer sem desserialização completa
- **Evolução de schema**: compatibilidade aditiva garantida (novos campos, deprecação segura)
- **Geração de tipos**: via `flatc --rust schema.fbs` → `schema_generated.rs`
- **Runtime Rust**: `FlatBufferBuilder` para serialização, `root_as_<Type>()` para leitura
- **Tipagem forte**: suporte a `enum`, `union` (oneof-like), vetores `[X]`, strings

---

## Guia de Uso Rápido

### 1. Geração de Tipos via `build.rs`

Arquivo: `build.rs` (raiz do crate ou `src/build.rs` se configurado em `Cargo.toml`)

```rust
// build.rs — invoca flatc durante compilação para gerar tipos Rust a partir de schemas

use std::path::Path;

fn main() {
    // Diretório onde estão os schemas .fbs
    let schema_dir = "schemas/";
    
    // Diretório de saída dos tipos gerados
    let output_dir = "src/generated/";
    
    // Certifica que diretório de saída existe
    std::fs::create_dir_all(&output_dir).unwrap();
    
    // Invoca flatc --rust para cada schema .fbs
    for entry in std::fs::read_dir(schema_dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();
        
        if path.extension().map_or(false, |ext| ext == "fbs") {
            // Gera arquivo_generated.rs no diretório de saída
            let flatc_cmd = format!(
                "flatc --rust -o {} {}",
                output_dir,
                path.display()
            );
            
            // Executa flatc como subprocesso
            let output = std::process::Command::new("flatc")
                .args(&["--rust", "-o", &output_dir])
                .arg(&path)
                .output()
                .expect("Falha ao executar flatc");
            
            if !output.status.success() {
                panic!(
                    "flatc retornou erro ao processar {}: {}",
                    path.display(),
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }
    }
    
    // Recompila se algum .fbs mudar
    println!("cargo:rerun-if-changed={}", schema_dir);
}
```

### 2. Schema `.fbs` (exemplo)

Arquivo: `schemas/contract.fbs`

```flatbuffers
// Namespace para evitar colisões
namespace SmartAgent.Contract;

// Enum com suporte a valores inteiros
enum MessageType : byte {
    Request = 0,
    Response = 1,
    Event = 2
}

// Union (oneof-like) — escolhe uma de várias tabelas
union Payload {
    RequestPayload,
    ResponsePayload,
    EventPayload
}

// Struct — serializado inline (value type)
struct Timestamp {
    seconds: ulong;
    nanos: uint;
}

// Table — estrutura principal (evolui aditivamete)
table Message {
    id: string (required);
    msg_type: MessageType = Request;
    timestamp: Timestamp;
    payload_type: Payload;
    payload: Payload;
    metadata: [ubyte];  // vetor de bytes (binary data)
    tags: [string];     // vetor de strings
}

// Root type — tipo que raiz do arquivo será
root_type Message;
```

### 3. Round-trip: Serialização (encode)

```rust
// src/lib.rs ou src/main.rs
extern crate flatbuffers;

#[path = "generated/contract_generated.rs"]
mod contract_generated;

use contract_generated::smart_agent::contract::{
    Message, MessageArgs, MessageType, Timestamp,
    Payload, RequestPayload, RequestPayloadArgs,
};

/// Exemplo: serializar uma mensagem de requisição
pub fn encode_request(request_id: &str, body: &str) -> Vec<u8> {
    let mut builder = flatbuffers::FlatBufferBuilder::with_capacity(512);
    
    // 1. Serializar strings (reference types, obrigatório antes de tabelas)
    let id_offset = builder.create_string(request_id);
    let body_offset = builder.create_string(body);
    
    // 2. Serializar estruturas aninhadas (se usadas)
    let timestamp = Timestamp::new(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        0,
    );
    
    // 3. Serializar payload (union — precisa de tipo + offset)
    let request_payload = RequestPayload::create(
        &mut builder,
        &RequestPayloadArgs {
            body: Some(body_offset),
        },
    );
    
    // 4. Criar mensagem raiz com todos os dados
    let message = Message::create(
        &mut builder,
        &MessageArgs {
            id: Some(id_offset),
            msg_type: MessageType::Request,
            timestamp: Some(&timestamp),
            payload_type: Payload::RequestPayload,
            payload: Some(request_payload.as_union_value()),
            metadata: None,  // opcional
            tags: None,      // opcional
            ..Default::default()
        },
    );
    
    // 5. Finalizar buffer e retornar bytes
    builder.finish(message, None);
    builder.finished_data().to_vec()
}
```

### 4. Round-trip: Desserialização (decode)

```rust
use contract_generated::smart_agent::contract::{
    root_as_message, MessageType, Payload,
};

/// Exemplo: desserializar e acessar dados sem cópia
pub fn decode_request(buffer: &[u8]) -> Result<String, String> {
    // root_as_message acessa dados zero-copy diretamente do buffer
    let message = root_as_message(buffer)
        .map_err(|e| format!("Erro ao desserializar: {}", e))?;
    
    // Acesso aos campos — não há cópia, apenas ponteiros no buffer original
    let request_id = message
        .id()
        .ok_or_else(|| "Campo 'id' não presente".to_string())?;
    
    let ts = message.timestamp();
    if let Some(timestamp) = ts {
        println!("Timestamp: {} s", timestamp.seconds());
    }
    
    // Verificar union type antes de unwrap (segurança)
    if message.payload_type() == Payload::RequestPayload {
        if let Some(payload) = message.payload_as_request_payload() {
            if let Some(body) = payload.body() {
                println!("Request body: {}", body);
            }
        }
    }
    
    Ok(request_id.to_string())
}

/// Acesso a vetores (também zero-copy)
pub fn decode_tags(buffer: &[u8]) -> Result<Vec<String>, String> {
    let message = root_as_message(buffer)?;
    
    let mut tags = Vec::new();
    if let Some(tag_vec) = message.tags() {
        for i in 0..tag_vec.len() {
            if let Some(tag) = tag_vec.get(i) {
                tags.push(tag.to_string());
            }
        }
    }
    
    Ok(tags)
}
```

### 5. Evolução de Schema (Compatibilidade)

**Regra de Ouro**: ao adicionar campos, sempre no **final da tabela** e com **default explícito**.

```flatbuffers
// Schema V1 (original)
table Message {
    id: string (required);
    msg_type: MessageType = Request;
    timestamp: Timestamp;
}

// Schema V2 (evolutiva — COMPATÍVEL)
table Message {
    id: string (required);
    msg_type: MessageType = Request;
    timestamp: Timestamp;
    // ✅ Novo campo no final com default
    version: uint = 1;
    // ✅ Outro novo campo
    priority: byte = 0;
}
```

**Operações SEGURAS (forward/backward compatible)**:
- ✅ Adicionar campo novo no final com default
- ✅ Deprecar campo: `field: type (deprecated)`
- ✅ Renomear campo (não afeta binário)
- ✅ Adicionar novo variant a union no final

**Operações PERIGOSAS (quebram compatibilidade)**:
- ❌ Remover campo
- ❌ Inserir campo no meio da tabela
- ❌ Mudar default de campo
- ❌ Mudar tipo de campo
- ❌ Renumerar enum values

---

## Compatibilidade: `flatc` ↔ Crate Rust

| Aspecto | Regra |
| --- | --- |
| **Versão `flatc`** | Usar mesma série que crate (ex: `flatc 24.x` com `flatbuffers = "24.3"`) |
| **Geração de código** | `flatc --rust` gera código compatível com versão equivalente da crate |
| **Breaking changes** | Raros entre minor versions; verificar release notes do repo Google |
| **Recomendação** | Manter `flatc` e crate na mesma série principal (24.x, 25.x) |

**Verificação**: 
```bash
# Confirmar versão do flatc instalado
flatc --version

# Conferir crate no Cargo.toml
grep flatbuffers Cargo.toml
```

---

## APIs Atuais (24.3.x)

### Builder (Serialização)

```rust
let mut builder = flatbuffers::FlatBufferBuilder::with_capacity(1024);

// Métodos principais:
builder.create_string(&str) -> Offset<String>
builder.create_vector(&[T]) -> Offset<Vector<T>>
builder.finish(root_table, ...) -> ()
builder.finished_data() -> &[u8]
builder.reset()  // reutilizar builder
```

### Root Access (Desserialização)

```rust
// Gerado via flatc --rust
root_as_<TableName>(buf: &[u8]) -> Result<Table, Error>

// Exemplo:
let msg = root_as_message(buffer)?;
msg.field_name() -> Option<T>
msg.vector_field() -> Option<Vector<T>>
msg.union_type() -> UnionType
msg.union_field_as_<Type>() -> Option<Type>
```

---

## Recursos e Links

- **Repositório oficial**: https://github.com/google/flatbuffers
- **Documentação Rust**: https://github.com/google/flatbuffers/tree/master/docs/source/languages/rust.md
- **Tutorial completo**: https://github.com/google/flatbuffers/blob/master/docs/source/tutorial.md
- **Schema evolution guide**: https://github.com/google/flatbuffers/blob/master/docs/source/evolution.md

---

## Notas para o Projeto

1. **build.rs**: configurar script em `build.rs` para invocar `flatc` automaticamente (CI/CD e dev)
2. **Geração em CI**: considerar gerar `*_generated.rs` no repositório ou em build-time
3. **Organização**: manter schemas `.fbs` em diretório dedicado (`schemas/`)
4. **Versionamento**: ao evoluir schema, testar compatibilidade com `flatc --conform`
5. **Comentários**: código gerado é automático; comentários no schema `.fbs` documentam contrato
