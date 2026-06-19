# Prost (Protocol Buffers)

- **Versão Recomendada:** 0.14.3 (compatível com tonic 0.14.x)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-18
- **Propósito no Projeto:** Codec gRPC/Protobuf de fallback do transport; serialização/deserialização de mensagens geradas do `.proto` em Rust — base para todas as mensagens do tonic.
- **Documentação Oficial:** https://docs.rs/prost/0.13.5
- **Library ID (Context7):** `/tokio-rs/prost`

## Matriz de Compatibilidade de Versões

| Crate | Versão | Propósito |
|-------|--------|----------|
| `prost` | `0.14.3` | Serialização/deserialização Protobuf, geração de código via prost-build |
| `prost-build` | `0.14.3` | Compilação de `.proto` em `build.rs` (usado via tonic-build) |
| `tonic` | `0.14.x` | Integração automática via tonic-build (que depende de prost-build) |
| `tokio` | `1.x` | Runtime async para gRPC |

## Configuração do Cargo.toml

```toml
[dependencies]
prost = "0.14"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
tonic = "0.14"

[build-dependencies]
prost-build = "0.14"
tonic-build = "0.14"
```

## Guia de Uso Rápido

### 1. Sintaxe de Mensagens Geradas (Derive + Atributos)

Após compilar um arquivo `.proto` com `tonic-build` (que usa `prost-build`), as mensagens são geradas com o derive `#[derive(::prost::Message)]`:

```rust
// GERADO AUTOMATICAMENTE por prost-build/tonic-build
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct Person {
    /// Campo obrigatório com tag 1
    #[prost(string, tag = "1")]
    pub name: String,
    
    /// Campo inteiro com tag 2
    #[prost(int32, tag = "2")]
    pub id: i32,
    
    /// Campo string com tag 3
    #[prost(string, tag = "3")]
    pub email: String,
    
    /// Campo repetido (lista) com tag 4 — mapeado para Vec<T>
    #[prost(message, repeated, tag = "4")]
    pub phones: Vec<PhoneNumber>,
}

/// Módulo de tipos aninhados
pub mod person {
    #[derive(Clone, PartialEq, ::prost::Message)]
    pub struct PhoneNumber {
        #[prost(string, tag = "1")]
        pub number: String,
        
        /// Enumeração com tag 2 — armazenada como i32
        #[prost(enumeration = "PhoneType", tag = "2")]
        pub r#type: i32,
    }
    
    /// Enumeração Protobuf mapeada para Rust
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, ::prost::Enumeration)]
    #[repr(i32)]
    pub enum PhoneType {
        Mobile = 0,
        Home = 1,
        Work = 2,
    }
}
```

### 2. Encode/Decode de Mensagens

A trait `Message` (de prost) fornece métodos para serializar/deserializar:

```rust
use prost::Message;

// ENCODE: serializar para bytes
let mut person = Person {
    name: "João Silva".into(),
    id: 123,
    email: "joao@example.com".into(),
    phones: vec![],
};

let mut buffer = Vec::new();
person.encode(&mut buffer).expect("encode falhou");
println!("Bytes serializados: {:?}", buffer);

// DECODE: desserializar de bytes
let decoded_person = Person::decode(&buffer[..])
    .expect("decode falhou");
assert_eq!(decoded_person.name, "João Silva");
assert_eq!(decoded_person.id, 123);
```

### 3. Mapeamento de Tipos Protobuf → Rust

| Tipo Protobuf | Tipo Rust | Sintaxe Prost |
|---------------|-----------|---------------|
| `double` | `f64` | `#[prost(double, ...)]` |
| `float` | `f32` | `#[prost(float, ...)]` |
| `int32` | `i32` | `#[prost(int32, ...)]` |
| `int64` | `i64` | `#[prost(int64, ...)]` |
| `uint32` | `u32` | `#[prost(uint32, ...)]` |
| `uint64` | `u64` | `#[prost(uint64, ...)]` |
| `bool` | `bool` | `#[prost(bool, ...)]` |
| `string` | `String` | `#[prost(string, ...)]` |
| `bytes` | `Vec<u8>` | `#[prost(bytes, ...)]` |
| `message` | Struct personalizado | `#[prost(message, ...)]` |
| `repeated <tipo>` | `Vec<T>` | `#[prost(<tipo>, repeated, ...)]` |
| `enum` | `i32` (em struct); enum Rust gerado | `#[prost(enumeration = "...", ...)]` |
| `oneof` | Enum Rust em módulo aninhado | `#[prost(oneof = "...", ...)]` |

### 4. Campos `oneof` (Escolha Exclusiva)

Em Protobuf, um `oneof` mapeia para um `Option<Enum>` em Rust:

```protobuf
// my_message.proto
message Foo {
  oneof widget {
    int32 quux = 1;
    string bar = 2;
  }
}
```

Gerado como:

```rust
pub struct Foo {
    /// Option contém o enum da escolha
    pub widget: Option<foo::Widget>,
}

pub mod foo {
    #[derive(Clone, PartialEq, ::prost::Oneof)]
    pub enum Widget {
        #[prost(int32, tag = "1")]
        Quux(i32),
        
        #[prost(string, tag = "2")]
        Bar(String),
    }
}
```

### 5. Enumerações

Protobuf enums mapeiam para `i32` em structs (obrigatório por spec), mas também geram um enum Rust para conveniência:

```rust
// Armazenado como i32 na struct
pub struct PhoneNumber {
    #[prost(enumeration = "PhoneType", tag = "2")]
    pub r#type: i32,  // 0, 1 ou 2
}

// Enum de verdade gerado para validação/conversão
#[derive(Clone, Copy, Debug, PartialEq, Eq, Enumeration)]
#[repr(i32)]
pub enum PhoneType {
    Mobile = 0,
    Home = 1,
    Work = 2,
}

// Métodos associados gerados:
impl PhoneType {
    /// Valida se o i32 é um valor enum válido
    pub const fn is_valid(value: i32) -> bool { ... }
    
    /// [DESCONTINUADO] Use conversão manual ou TryFrom
    #[deprecated]
    pub fn from_i32(value: i32) -> Option<PhoneType> { ... }
}
```

### 6. Campos Repetidos (Listas)

Mapeiam automaticamente para `Vec<T>`:

```rust
#[derive(Clone, PartialEq, ::prost::Message)]
pub struct AddressBook {
    /// Lista de pessoas — gerado como Vec<Person>
    #[prost(message, repeated, tag = "1")]
    pub people: Vec<Person>,
}

// Uso:
let mut book = AddressBook::default();
book.people.push(person1);
book.people.push(person2);

let mut buf = Vec::new();
book.encode(&mut buf)?;  // Serializa toda a lista
```

### 7. Integração com tonic-build

Em um `build.rs`, tonic-build orquestra prost-build:

```rust
// build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = std::path::PathBuf::from("proto");
    
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile(
            &["proto/my_service.proto"],
            &[&proto_root],
        )?;
    
    Ok(())
}
```

Não é necessário chamar `prost_build::Config` explicitamente — tonic-build encapsula tudo.

## Breaking Changes & Deprecações Recentes

### v0.14.3 (Atual, Recomendada)
- **Compatibilidade:** Totalmente estável com tonic 0.14.6
- **Mudanças notáveis:** APIs de encode/decode mantidas estáveis; trait `Message` com `encode(&mut self, buf: &mut impl BufMut)` e `decode(buf: impl Buf)` sem alterações
- **Enums:** `from_i32()` descontinuado desde v0.13 — use `TryFrom<i32>` ou validação manual com `is_valid()`
- **Sem breaking changes** entre v0.13.x → v0.14.3 para código que segue o padrão prost-build

### v0.13 → v0.14
- Melhorias internas de performance e segurança de memória
- APIs de codificação/decodificação mantidas idênticas
- Enumerações: `PhoneType::try_from(i32)` funciona sem alterações

### v0.12 → v0.13
- Melhorias de performance em serialização
- Sem breaking changes significativas para uso padrão

### Avisos de Deprecação
- **`PhoneType::from_i32()`** → Use `TryFrom<i32>` ou `PhoneType::is_valid(value: i32)` com conversão manual

## Notas de Arquitetura no Projeto

1. **Fallback de Codec:** Prost é o codec padrão (serialização Protobuf) — sempre ativo quando tonic está em uso.
2. **Compatibilidade com error_core:** Mensagens prost não dependem de error_core; podem ser usadas livremente em serialização.
3. **Comentários em Código Gerado:** Preserve comentários do `.proto` no Rust gerado — prost-build os mapeia automaticamente como `///` docs.
4. **Tags Explícitas:** Sempre especifique `#[prost(..., tag = "N")]` — sem tag, prost infere sequencialmente (frágil com evolução).

## Histórico de Atualizações

| Data | Versão | Mudanças |
|------|--------|----------|
| 2026-06-18 | 0.14.3 | Atualização via Context7: versão 0.14.3 confirmada compatível com tonic 0.14.6; APIs de `Message::encode()` e `Message::decode()` mantidas estáveis; enumerações com deprecação de `from_i32()` desde v0.13; sem breaking changes relevantes entre v0.13.5 → v0.14.3 para código padrão. |
| 2026-06-05 | 0.13.5 | Criação inicial com compatibilidade tonic 0.14.x, tipos Protobuf → Rust, encode/decode, campos oneof, enumerações, arrays repetidos, integração tonic-build. |
