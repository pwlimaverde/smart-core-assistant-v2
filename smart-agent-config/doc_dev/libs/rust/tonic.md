# Tonic (gRPC)

- **Versão Recomendada:** 0.14.6 (compatível com tokio 1.x)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-02
- **Propósito no Projeto:** Servidor gRPC do runtime_api — AuthService com interceptor JWT, extensões de Request e status codes de autenticação/autorização.
- **Documentação Oficial:** https://docs.rs/tonic/0.14.6
- **Library ID (Context7):** `/hyperium/tonic`

## Matriz de Compatibilidade de Versões

| Crate | Versão | Propósito |
|-------|--------|----------|
| `tonic` | `0.14.6` | Servidor/cliente gRPC com transport HTTP/2 |
| `tonic-build` | `0.14.6` | Compilação de `.proto` em `build.rs` |
| `prost` | `0.14` | Serialização/deserialização de mensagens protobuf |
| `tokio` | `1.x` | Runtime async (via `features = ["macros", "rt-multi-thread"]`) |

## Configuração do Cargo.toml

```toml
[package]
name = "smart-runtime-api"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.14"
prost = "0.14"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
tower = "0.4"  # Para interceptadores e middlewares
http = "1.0"   # Para tipos HTTP

[build-dependencies]
tonic-build = "0.14"
```

## Guia de Uso Rápido

### 1. Compilação de Protobufs com tonic-build (build.rs)

O arquivo `build.rs` na raiz do projeto compila os arquivos `.proto` em Rust durante a build:

```rust
// build.rs
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto_root = PathBuf::from("proto");
    
    tonic_build::configure()
        .build_server(true)           // Gerar código de servidor
        .build_client(false)           // Não gerar cliente (opcional)
        .compile_protos(
            &[proto_root.join("auth_service.proto").to_string_lossy()],
            &[proto_root.to_string_lossy().into_owned()],
        )?;
    
    Ok(())
}
```

**Estrutura esperada:**
```
projeto/
├── build.rs
├── proto/
│   └── auth_service.proto
└── src/
    └── lib.rs
```

### 2. Definição do Serviço gRPC (auth_service.proto)

```proto
syntax = "proto3";

package auth_service;

service AuthService {
    rpc Authenticate (AuthRequest) returns (AuthResponse) {}
    rpc Authorize (AuthorizeRequest) returns (AuthorizeResponse) {}
}

message AuthRequest {
    string token = 1;
}

message AuthResponse {
    string user_id = 1;
    repeated string roles = 2;
}

message AuthorizeRequest {
    string token = 1;
    string required_permission = 2;
}

message AuthorizeResponse {
    bool authorized = 1;
}
```

### 3. Implementação do Serviço gRPC

A geração automática do `tonic-build` cria um trait que você implementa:

```rust
use tonic::{Request, Response, Status, async_trait};
use crate::auth_service::{
    auth_service_server::{AuthService, AuthServiceServer},
    AuthRequest, AuthResponse, AuthorizeRequest, AuthorizeResponse,
};

#[derive(Debug, Default)]
pub struct AuthServiceImpl;

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn authenticate(
        &self,
        request: Request<AuthRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let req = request.into_inner();
        
        // Extrair e validar token
        if req.token.is_empty() {
            return Err(Status::unauthenticated("Token vazio"));
        }
        
        // Simular validação de JWT
        let response = AuthResponse {
            user_id: "user_123".to_string(),
            roles: vec!["admin".to_string()],
        };
        
        Ok(Response::new(response))
    }

    async fn authorize(
        &self,
        request: Request<AuthorizeRequest>,
    ) -> Result<Response<AuthorizeResponse>, Status> {
        let req = request.into_inner();
        
        // Verificar permissão
        let authorized = req.required_permission == "write";
        
        if !authorized {
            return Err(Status::permission_denied("Permissão insuficiente"));
        }
        
        Ok(Response::new(AuthorizeResponse { authorized: true }))
    }
}

// Incluir código gerado pelo tonic-build
pub mod auth_service {
    tonic::include_proto!("auth_service");
}
```

### 4. Interceptor de Autenticação JWT

Os interceptadores em tonic são middleware que processam requisições antes de chegarem ao serviço. Use a biblioteca `tower` para criar interceptadores:

```rust
use tower::Layer;
use tonic::service::Interceptor;
use tonic::{Request, Status};
use http::HeaderMap;

#[derive(Clone)]
pub struct AuthInterceptor;

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        // Extrair metadados (headers) da requisição
        let metadata = request.metadata();
        
        // Buscar o header Authorization
        let auth_header = metadata
            .get("authorization")
            .and_then(|h| h.to_str().ok())
            .ok_or_else(|| Status::unauthenticated("Header 'authorization' ausente"))?;
        
        // Validar formato "Bearer <token>"
        let token = if let Some(bearer_token) = auth_header.strip_prefix("Bearer ") {
            bearer_token
        } else {
            return Err(Status::unauthenticated("Formato inválido: esperado 'Bearer <token>'"));
        };
        
        // Validar JWT (simplificado; use jsonwebtoken ou similar em produção)
        if token.len() < 10 {
            return Err(Status::unauthenticated("Token inválido"));
        }
        
        // Opcionalmente, armazenar informações decodificadas nas extensões
        // para reutilização no serviço
        request.extensions_mut().insert(AuthContext {
            user_id: "user_123".to_string(),
            roles: vec!["admin".to_string()],
        });
        
        Ok(request)
    }
}

#[derive(Clone, Debug)]
pub struct AuthContext {
    pub user_id: String,
    pub roles: Vec<String>,
}
```

### 5. Extração de Metadados no Serviço

Dentro dos métodos do serviço, você pode acessar os metadados e extensões:

```rust
#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn authenticate(
        &self,
        request: Request<AuthRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        // Acessar metadados (headers)
        let metadata = request.metadata();
        
        // Buscar valor específico (ex: custom header)
        if let Some(custom_value) = metadata.get("x-custom-header") {
            if let Ok(value_str) = custom_value.to_str() {
                println!("Custom header: {}", value_str);
            }
        }
        
        // Acessar extensões (dados adicionados pelo interceptor)
        let auth_context = request
            .extensions()
            .get::<AuthContext>()
            .cloned()
            .ok_or_else(|| Status::internal("AuthContext não disponível"))?;
        
        println!("User ID: {}", auth_context.user_id);
        println!("Roles: {:?}", auth_context.roles);
        
        let req = request.into_inner();
        
        let response = AuthResponse {
            user_id: auth_context.user_id,
            roles: auth_context.roles,
        };
        
        Ok(Response::new(response))
    }
}
```

### 6. Configuração do Servidor com Interceptor

Ao criar o servidor, adicione o interceptor via Torre layers:

```rust
use tonic::transport::Server;
use tower::ServiceBuilder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let auth_service = AuthServiceImpl;
    let auth_service_server = AuthServiceServer::new(auth_service)
        .with_interceptor(AuthInterceptor);
    
    // Opcionalmente, adicione outras camadas (logging, timeout, etc)
    let layer = ServiceBuilder::new()
        .layer(tonic::service::interceptor(AuthInterceptor))
        .into_inner();
    
    Server::builder()
        .add_service(auth_service_server)
        .serve(addr)
        .await?;
    
    println!("AuthService listening on {}", addr);
    
    Ok(())
}
```

### 7. Status Codes de Autenticação e Autorização

Tonic fornece variantes de `Status` para diferentes cenários:

```rust
// Autenticação falhou (token ausente/inválido)
return Err(Status::unauthenticated("Token ausente ou inválido"));

// Autorização falhou (usuário autenticado mas sem permissão)
return Err(Status::permission_denied("Permissão insuficiente para acessar este recurso"));

// Requisição inválida (parâmetros malformados)
return Err(Status::invalid_argument("Campo obrigatório 'email' ausente"));

// Erro interno do servidor
return Err(Status::internal("Erro ao validar token no banco de dados"));

// Recurso não encontrado
return Err(Status::not_found("Usuário não encontrado"));

// Conflito (ex: usuário já existe)
return Err(Status::already_exists("Usuário com este email já existe"));
```

Mapeamento de códigos gRPC para HTTP:
| Status gRPC | Código HTTP |
|-------------|------------|
| `OK` | 200 |
| `CANCELLED` | 499 |
| `UNKNOWN` | 500 |
| `INVALID_ARGUMENT` | 400 |
| `DEADLINE_EXCEEDED` | 504 |
| `NOT_FOUND` | 404 |
| `ALREADY_EXISTS` | 409 |
| `PERMISSION_DENIED` | 403 |
| `UNAUTHENTICATED` | 401 |
| `INTERNAL` | 500 |

### 8. Exemplo Completo: Servidor com Interceptor

```rust
use tonic::{Request, Response, Status, transport::Server, async_trait};
use tower::Layer;
use tonic::service::Interceptor;

// 1. Tipos de autenticação
#[derive(Clone, Debug)]
pub struct AuthContext {
    pub user_id: String,
    pub roles: Vec<String>,
}

// 2. Implementação do Interceptor
#[derive(Clone)]
pub struct AuthInterceptor;

impl Interceptor for AuthInterceptor {
    fn call(&mut self, mut request: Request<()>) -> Result<Request<()>, Status> {
        let metadata = request.metadata();
        
        let auth_header = metadata
            .get("authorization")
            .and_then(|h| h.to_str().ok())
            .ok_or_else(|| Status::unauthenticated("Autenticação obrigatória"))?;
        
        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| Status::unauthenticated("Formato Bearer esperado"))?;
        
        // Simular validação de JWT
        if !token.starts_with("valid_") {
            return Err(Status::unauthenticated("Token inválido"));
        }
        
        // Armazenar contexto nas extensões
        request.extensions_mut().insert(AuthContext {
            user_id: "user_from_token".to_string(),
            roles: vec!["user".to_string()],
        });
        
        Ok(request)
    }
}

// 3. Implementação do Serviço
#[derive(Debug, Default)]
pub struct MyAuthService;

#[tonic::async_trait]
impl AuthService for MyAuthService {
    async fn authenticate(
        &self,
        request: Request<AuthRequest>,
    ) -> Result<Response<AuthResponse>, Status> {
        let auth_ctx = request
            .extensions()
            .get::<AuthContext>()
            .cloned()
            .ok_or_else(|| Status::internal("AuthContext missing"))?;
        
        Ok(Response::new(AuthResponse {
            user_id: auth_ctx.user_id,
            roles: auth_ctx.roles,
        }))
    }
}

// 4. Main: servidor com interceptor
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let svc = AuthServiceServer::new(MyAuthService::default())
        .with_interceptor(AuthInterceptor);
    
    Server::builder()
        .add_service(svc)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

## Referências Rápidas

### Metadados (Headers) em Requisições

```rust
// Acessar metadados
let metadata = request.metadata();

// Buscar valor específico (strings ASCII)
if let Some(value) = metadata.get("authorization") {
    if let Ok(value_str) = value.to_str() {
        println!("Authorization: {}", value_str);
    }
}

// Iterar sobre todos os headers
for (key, value) in metadata.iter() {
    println!("{}: {:?}", key, value);
}
```

### Resposta com Metadados (Trailer Headers)

```rust
use tonic::{Response, Metadata, MetadataValue};

let mut response = Response::new(my_response_data);

// Adicionar metadata na resposta
let mut metadata = Metadata::new();
metadata.insert("x-request-id", MetadataValue::from_static("12345"));
*response.metadata_mut() = metadata;

Ok(response)
```

### Extensions para Passar Dados entre Camadas

```rust
// No interceptor, inserir dados
request.extensions_mut().insert(my_context);

// No serviço, recuperar dados
let context = request.extensions().get::<MyContext>()?;

// Ou com clonagem
let context = request.extensions().get::<MyContext>().cloned()?;
```

## Notas Importantes

1. **Async Runtime:** Tonic requer tokio como runtime async. Sempre use `#[tokio::main]` ou configure o runtime explicitamente.

2. **Trait Async:** Use `#[tonic::async_trait]` para permitir `async fn` em traits. Isso usa internamente a macro `async-trait`.

3. **Request.into_inner():** Para acessar os dados da mensagem protobuf dentro de `Request<T>`, use `.into_inner()` pois os campos são privados.

4. **Versões Fixas:** Em produção, fixe as versões (`tonic = "0.14.6"`) em vez de usar `tonic = "0.14"` para evitar surpresas de breaking changes.

5. **HTTP/2 Obrigatório:** Tonic usa HTTP/2 por padrão. Para suporte a HTTP/1.1 (ex: gRPC-Web), use `accept_http1(true)` e adicione a camada `GrpcWebLayer`.

6. **Interceptadores vs Layers:** Interceptadores são específicos de tonic e operam sobre `Request` e `Response`. Layers são da biblioteca `tower` e operam em nível de serviço.

## Versão Verificada

- **Data:** 2026-06-02
- **Versão Tonic:** 0.14.6
- **Tokio:** 1.x (1.40+)
- **Prost:** 0.14
- **Tonic-Build:** 0.14.6
