# Tonic-Build (Compilação gRPC)

- **Versão Recomendada:** 0.14.6 (compatível com tonic 0.14.6)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-05
- **Propósito no Projeto:** Geração de stubs gRPC no `build.rs` da crate `contracts` a partir do `.proto` gerado do `.fbs` (FlatBuffers → Proto → Rust gRPC stubs).
- **Documentação Oficial:** https://docs.rs/tonic-build/0.14.6
- **Library ID (Context7):** `/websites/rs_tonic_0_14_6_tonic`

## Visão Geral

`tonic-build` é a ferramenta de build-time que compila arquivos `.proto` (Protocol Buffers) em código Rust durante a compilação. Usa `prost-build` internamente para processar o `.proto` e gera:
- **Structs de mensagem** (`prost`): Serialização/deserialização automática
- **Traits de serviço gRPC:** Servidores e clientes async/await ready

## Matriz de Compatibilidade

| Crate | Versão | Propósito |
|-------|--------|----------|
| `tonic-build` | `0.14.6` | Compilação de `.proto` → código Rust gRPC |
| `tonic` | `0.14.6` | Runtime gRPC (depende de `prost` 0.14) |
| `prost` | `0.14` | Serialização/deserialização protobuf |
| `prost-build` | `0.14` | Compiler backend (usado internamente por `tonic-build`) |

## Configuração do Cargo.toml

```toml
[build-dependencies]
tonic-build = "0.14"

[dependencies]
tonic = "0.14"
prost = "0.14"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
```

## Guia de Uso Rápido

### 1. build.rs: Exemplo Completo

```rust
// build.rs — Compilado e executado ANTES do resto do crate

use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Definir diretório de origem dos .proto (relativo à raiz do projeto)
    let proto_dir = PathBuf::from("proto");
    
    // Configurar tonic-build
    tonic_build::configure()
        // Gerar código de servidor gRPC
        .build_server(true)
        // NÃO gerar código de cliente (se só implementar servidor)
        .build_client(false)
        // Compilar arquivos .proto
        .compile_protos(
            // Lista de arquivos .proto relativos ao proto_dir
            &[
                proto_dir.join("auth_service.proto").to_string_lossy(),
                proto_dir.join("runtime_api.proto").to_string_lossy(),
            ],
            // Incluir paths para resolver imports no .proto
            &[proto_dir.to_string_lossy().into_owned()],
        )?;
    
    Ok(())
}
```

**Estrutura esperada:**
```
projeto/
├── build.rs
├── proto/
│   ├── auth_service.proto
│   └── runtime_api.proto
├── src/
│   ├── lib.rs
│   └── services/
└── Cargo.toml
```

### 2. Usar Output no Código

Os stubs gerados são salvos em `$OUT_DIR` (varia por target/profile). Use a macro `tonic::include_proto!` para incluí-los:

```rust
// src/lib.rs ou src/services/auth.rs

// Módulo auto-gerado pelo tonic-build
pub mod auth_service {
    tonic::include_proto!("auth_service");  // Busca em OUT_DIR/auth_service.rs
}

// Agora os tipos estão disponíveis:
// - auth_service::AuthRequest
// - auth_service::AuthResponse
// - auth_service::auth_service_server::AuthService (trait)
// - auth_service::auth_service_server::AuthServiceServer (implementação)
// - auth_service::auth_service_client::AuthServiceClient (cliente)
```

### 3. Configurações Avançadas

```rust
// build.rs — exemplo com mais opções

tonic_build::configure()
    // Gerar descriptor set (útil para reflection/introspection)
    .file_descriptor_set_path("descriptor_set.bin")
    
    // Adicionar derives customizados às mensagens
    .type_attribute("auth_service.AuthRequest", "#[derive(Hash)]")
    
    // Compilar com features específicas
    .build_server(true)
    .build_client(true)
    
    // Protobuf 3 (padrão)
    .compile_protos(
        &["proto/service.proto"],
        &["proto/"],
    )?;
```

### 4. Exemplo Completo: Servidor Autenticado

**proto/auth.proto:**
```proto
syntax = "proto3";

package auth;

service AuthService {
    rpc Authenticate (AuthRequest) returns (AuthResponse) {}
}

message AuthRequest {
    string username = 1;
    string password = 2;
}

message AuthResponse {
    string token = 1;
    string user_id = 2;
}
```

**build.rs:**
```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .compile_protos(&["proto/auth.proto"], &["proto/"])?;
    Ok(())
}
```

**src/lib.rs:**
```rust
use tonic::{Request, Response, Status, async_trait};

// Incluir stubs gerados
pub mod auth {
    tonic::include_proto!("auth");
}

use auth::{
    auth_service_server::{AuthService, AuthServiceServer},
    AuthRequest, AuthResponse,
};

#[derive(Debug, Default)]
pub struct AuthServiceImpl;

#[async_trait]
impl AuthService for AuthServiceImpl {
    async fn authenticate(
        &self,
        request: Request<AuthRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let req = request.into_inner();
        
        // Simular autenticação
        if req.username.is_empty() || req.password.is_empty() {
            return Err(Status::invalid_argument("Credenciais vazias"));
        }
        
        Ok(Response::new(AuthResponse {
            token: format!("token_{}", req.username),
            user_id: "user_123".to_string(),
        }))
    }
}

// Exportar para uso em main.rs
pub use auth_service_server::AuthServiceServer;
```

**src/main.rs:**
```rust
use tonic::transport::Server;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let auth_service = myservice::AuthServiceImpl;
    let auth_server = myservice::AuthServiceServer::new(auth_service);
    
    Server::builder()
        .add_service(auth_server)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

## Protoc: Necessário ou Embutido?

### Status no Windows

**Resposta curta:** `tonic-build` **não requer** `protoc` instalado no sistema.

- **tonic-build 0.14.6** vem com `protoc` **embutido** (pre-compiled binary).
- A crate `prost-build` detecta automaticamente a arquitetura (Windows x86_64, ARM64, etc.) e usa o binário apropriado.
- **Não há necessidade** de instalar Protobuf manual via `vcpkg`, `chocolatey`, ou Downloads.

**Se você tiver `protoc` instalado:** tonic-build pode opcionalmente usá-lo, mas não é obrigatório.

### Quando Pode Ser Necessário (Edge Cases)

1. **Arquitetura não suportada:** Se usar ARM em Windows ou arquitetura não padrão.
2. **Custom plugins:** Se precisar gerar código com plugins `protoc` customizados (raro).

Para 99% dos casos: **ignore, funciona sozinho.**

## Breaking Changes: 0.12 → 0.14

| Versão | Mudança | Impacto |
|--------|---------|--------|
| 0.12→0.13 | `prost` para `0.13` | Mensagens protobuf agora implementam `Default` por padrão |
| 0.13→0.14 | `prost` para `0.14` | Nenhum breaking change significativo; melhorias internas |
| 0.14.x | Recomendado para novos projetos | Compatível com `tokio 1.40+` |

**Ação:** Se migrar de 0.12, revisar se código existente depende de comportamento antigo de `Default` ou serialização.

## Erros Comuns

### "OUT_DIR não encontrado"
```rust
// ❌ Errado
let out_dir = std::env::var("OUT_DIR").unwrap();

// ✅ Correto (build.rs tem acesso a OUT_DIR)
let out_dir = std::env::var("OUT_DIR")?;
```
O `OUT_DIR` só existe durante o build. Não acesse em `src/lib.rs`.

### "include_proto!("myproto") não encontrado"
- Verificar se `build.rs` rodou com sucesso (cargo build -vv).
- Verificar nome: `tonic::include_proto!("mypackage")` corresponde ao `package mypackage;` no `.proto`.
- Não confundir com nome de arquivo.

### "Proto file not found"
```rust
// ❌ Errado (caminhos relativos a CWD, não a src/)
.compile_protos(&["proto/auth.proto"], &["proto/"])

// ✅ Correto (relativo à raiz do projeto)
.compile_protos(
    &[PathBuf::from("proto").join("auth.proto").to_string_lossy()],
    &[PathBuf::from("proto").to_string_lossy().into_owned()],
)
```

## Integração com o Projeto

### Fluxo no Smart Agent Config

1. **FlatBuffers → Proto:** Um conversor gera `.proto` a partir de `.fbs` (schema FlatBuffers).
2. **Proto → Rust:** `tonic-build` (no build.rs da crate `contracts`) compila `.proto` → código gRPC.
3. **Uso:** Crates como `worker` e `runtime_api` importam os stubs gerados.

### Configuração Recomendada para `contracts/build.rs`

```rust
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = PathBuf::from("proto");
    
    // Listar todos os .proto gerados
    let proto_files: Vec<String> = std::fs::read_dir(&proto_root)?
        .filter_map(|e| {
            e.ok().and_then(|entry| {
                let path = entry.path();
                if path.extension().map(|ext| ext == "proto").unwrap_or(false) {
                    Some(path.to_string_lossy().into_owned())
                } else {
                    None
                }
            })
        })
        .collect();
    
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(&proto_files, &[proto_root.to_string_lossy().into_owned()])?;
    
    Ok(())
}
```

## Referências

| Tópico | Link |
|--------|------|
| Documentação Oficial tonic-build | https://docs.rs/tonic-build/0.14.6 |
| Documentação prost-build | https://docs.rs/prost-build/0.14 |
| Guia Protocol Buffers | https://developers.google.com/protocol-buffers |
| Tonic Book | https://tokio.rs/tokio/tutorial/select |

## Histórico de Atualização

| Data | Status | Evento |
|------|--------|--------|
| 2026-06-05 | ✅ CRIADA | Documentação criada a partir de Context7 (`/websites/rs_tonic_0_14_6_tonic`). Foco em build.rs, compatibilidade com tonic 0.14.6, protoc embutido, breaking changes 0.12→0.14, integração com projeto. |

---

**Nota:** Este documento é mantido como referência para a crate `contracts` do projeto. Consulte tonic.md para informações sobre runtime gRPC (servidores, clientes, interceptors).
