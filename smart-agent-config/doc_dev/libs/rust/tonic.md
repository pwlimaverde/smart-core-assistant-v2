# Tonic (gRPC)

- **Versão Recomendada:** 0.14.6 (compatível com tokio 1.x)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-04
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

## Server Streaming (realtime — decisão D7)

### Definição no .proto

Uma RPC de server streaming é declarada com a palavra-chave `stream` no tipo de retorno:

```proto
service RouteGuide {
  // Server-side streaming RPC
  rpc ListFeatures(Rectangle) returns (stream Feature) {}
}

message Rectangle {
  Point lo = 1;
  Point hi = 2;
}

message Feature {
  string name = 1;
  Point location = 2;
}
```

### Associated Type no Trait Gerado

O `tonic-build` gera um associated type `*Stream` para cada RPC com `stream` no retorno:

```rust
// Gerado automaticamente pelo tonic-build
pub trait RouteGuide: Send + Sync + 'static {
    type ListFeaturesStream: Stream<Item = Result<Feature, Status>> + Send + 'static;
    
    async fn list_features(
        &self,
        request: Request<Rectangle>,
    ) -> Result<Response<Self::ListFeaturesStream>, Status>;
}
```

### Implementação com `ReceiverStream` (Tokio MPSC)

Padrão mais comum: usar um canal `tokio::sync::mpsc` e encapsular em `ReceiverStream`:

```rust
use std::pin::Pin;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tonic::{Request, Response, Status};

#[tonic::async_trait]
impl RouteGuide for RouteGuideService {
    type ListFeaturesStream = ReceiverStream<Result<Feature, Status>>;

    async fn list_features(
        &self,
        request: Request<Rectangle>,
    ) -> Result<Response<Self::ListFeaturesStream>, Status> {
        let req = request.into_inner();
        
        // Criar canal MPSC (buffer de 100 mensagens)
        let (mut tx, rx) = mpsc::channel(100);
        
        // Spawn uma tarefa async que envia as features
        tokio::spawn(async move {
            let features = vec![
                Feature { name: "Central Park".to_string(), location: Some(Point { latitude: 407572761, longitude: -739858788 }) },
                Feature { name: "Times Square".to_string(), location: Some(Point { latitude: 409000000, longitude: -740000000 }) },
            ];
            
            for feature in features {
                if let Err(_) = tx.send(Ok(feature)).await {
                    // Receptor desconectado; parar de enviar
                    break;
                }
            }
        });
        
        // Retornar o receptor encapsulado em ReceiverStream
        Ok(Response::new(ReceiverStream::new(rx)))
    }
}
```

**Dependências necessárias:**
```toml
tokio = { version = "1.x", features = ["sync", "rt"] }
tokio-stream = "0.1"  # Para ReceiverStream
tonic = "0.14"
```

### Alternativa com `async_stream::stream!` (Pin<Box<dyn Stream>>)

Para operações mais complexas ou quando você prefere usar um generator, use `async_stream`:

```rust
use std::pin::Pin;
use tonic::{Request, Response, Status};
use futures::stream::Stream;

#[tonic::async_trait]
impl RouteGuide for RouteGuideService {
    // Tipo complexo: precisa ser Pin<Box<...>>
    type ListFeaturesStream = Pin<Box<dyn Stream<Item = Result<Feature, Status>> + Send + 'static>>;

    async fn list_features(
        &self,
        request: Request<Rectangle>,
    ) -> Result<Response<Self::ListFeaturesStream>, Status> {
        let req = request.into_inner();
        
        // Usar async_stream::stream! para gerar o stream
        let stream = async_stream::stream! {
            let features = vec![
                Feature { name: "Feature 1".to_string(), ..Default::default() },
                Feature { name: "Feature 2".to_string(), ..Default::default() },
            ];
            
            for feature in features {
                yield Ok(feature);
            }
        };
        
        Ok(Response::new(Box::pin(stream)))
    }
}
```

**Dependências:**
```toml
async-stream = "0.3"  # Macro stream! para generators
futures = "0.3"       # Para Stream trait
```

### Integração com Redis Pub/Sub (Fan-out)

Exemplo: receber eventos de um channel broadcast Redis e fazer fan-out para múltiplos clientes:

```rust
use tokio::sync::{broadcast, mpsc};
use tokio_stream::wrappers::BroadcastStream;
use tonic::{Request, Response, Status};

pub struct RealTimeService {
    // Canal broadcast compartilhado (criado na inicialização do servidor)
    broadcast_tx: broadcast::Sender<EventMessage>,
}

#[tonic::async_trait]
impl RealTimeService for RealTimeServiceImpl {
    type SubscribeStream = ReceiverStream<Result<EventMessage, Status>>;

    async fn subscribe(
        &self,
        request: Request<SubscriptionRequest>,
    ) -> Result<Response<Self::SubscribeStream>, Status> {
        // Subscrever ao canal broadcast
        let broadcast_rx = self.broadcast_tx.subscribe();
        
        // Converter broadcast receiver em stream (filtrando erros de desconexão)
        let (tx, rx) = mpsc::channel(100);
        
        tokio::spawn(async move {
            let mut stream = BroadcastStream::new(broadcast_rx);
            use futures::StreamExt;
            
            while let Some(event) = stream.next().await {
                match event {
                    Ok(msg) => {
                        if let Err(_) = tx.send(Ok(msg)).await {
                            break; // Cliente desconectou
                        }
                    }
                    Err(_) => {
                        // Mensagens foram perdidas (buffer cheio)
                        let _ = tx.send(Err(Status::resource_exhausted("Buffer overflow"))).await;
                        break;
                    }
                }
            }
        });
        
        Ok(Response::new(ReceiverStream::new(rx)))
    }
}
```

### Aplicar Interceptor JWT na Abertura do Stream

O mesmo `AuthInterceptor` (seção 4 desta doc) funciona para server streaming. Ele é acionado no início da conexão:

```rust
#[derive(Clone)]
pub struct AuthInterceptor;

impl Interceptor for AuthInterceptor {
    fn call(&mut self, request: Request<()>) -> Result<Request<()>, Status> {
        // Validar token no header "authorization" ANTES de iniciar o stream
        let metadata = request.metadata();
        
        let auth_header = metadata
            .get("authorization")
            .and_then(|h| h.to_str().ok())
            .ok_or_else(|| Status::unauthenticated("Token ausente"))?;
        
        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| Status::unauthenticated("Formato Bearer esperado"))?;
        
        // Validar JWT (usar `jsonwebtoken` ou similar)
        validate_jwt_token(token)?;
        
        Ok(request)
    }
}

// Ao configurar o servidor:
Server::builder()
    .add_service(
        RouteGuideServer::new(route_guide_service)
            .with_interceptor(AuthInterceptor)  // Interceptor aplicado antes do stream
    )
    .serve(addr)
    .await?;
```

**Nota:** O interceptor é acionado uma vez, antes da stream ser aberta. Dados do contexto (user_id, roles) podem ser armazenados em `request.extensions_mut()` e serão acessíveis dentro do handler de streaming.

---

## gRPC-Web (tonic-web) para Flutter Web

### Visão Geral

`tonic-web` é uma camada que permite clientes gRPC-Web (como Flutter Web) se comunicarem com servidores gRPC padrão. Traduz HTTP/1.1 + gRPC-Web em HTTP/2 nativo.

**Suporte:** Server streaming É suportado em gRPC-Web. Client streaming e bidi NÃO são.

### Versão Recomendada

```toml
[dependencies]
tonic = "0.14"
tonic-web = "0.12"  # Compatível com tonic 0.14.6
tower = "0.4"
tower-http = { version = "0.5", features = ["trace", "cors"] }
http = "1.0"
tokio = { version = "1.x", features = ["macros", "rt-multi-thread"] }
```

### Configuração do Servidor: accept_http1 + GrpcWebLayer

```rust
use tonic::transport::Server;
use tonic_web::GrpcWebLayer;
use tower_http::cors::CorsLayer;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let greeter = GreeterServer::new(MyGreeter::default());
    
    Server::builder()
        .accept_http1(true)  // Essencial: permite HTTP/1.1 (gRPC-Web usa HTTP/1.1)
        .layer(GrpcWebLayer::new())  // Adiciona tradução gRPC-Web
        .add_service(greeter)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

**Explicação:**
- `accept_http1(true)`: O servidor agora aceita conexões HTTP/1.1 além de HTTP/2.
- `GrpcWebLayer::new()`: Middleware que traduz requests gRPC-Web (HTTP/1.1) para gRPC (HTTP/2) internamente.

### CORS: Configuração para Navegador

gRPC-Web é acessado via navegador/Flutter Web, que impõe política CORS. Você DEVE adicionar `CorsLayer`:

```rust
use tonic::transport::Server;
use tonic_web::GrpcWebLayer;
use tower_http::cors::{CorsLayer, Any};
use tower::ServiceBuilder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let greeter = GreeterServer::new(MyGreeter::default());
    
    // Configurar CORS: permitir todas as origens (ajustar em produção)
    let cors = CorsLayer::permissive();  // Modo permissivo para dev
    
    Server::builder()
        .accept_http1(true)
        .layer(ServiceBuilder::new()
            .layer(cors)
            .layer(GrpcWebLayer::new())
            .into_inner())
        .add_service(greeter)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

**CORS Restritivo (Produção):**

```rust
use tower_http::cors::CorsLayer;
use http::Method;

let cors = CorsLayer::permissive()
    .allow_origin("https://myapp.com".parse()?)
    .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
    .allow_headers(vec!["content-type", "grpc-status", "grpc-message"].into_iter()
        .map(|h| h.parse().unwrap())
        .collect::<Vec<_>>()
        .into());
```

### Headers CORS Essenciais para gRPC-Web

O navegador requer que estes headers sejam explicitamente expostos:

```rust
use http::HeaderName;

let cors = CorsLayer::permissive()
    .expose_headers(
        vec![
            HeaderName::from_static("content-type"),
            HeaderName::from_static("grpc-status"),     // Status code gRPC
            HeaderName::from_static("grpc-message"),    // Mensagem de erro
            HeaderName::from_static("grpc-encoding"),   // Codificação (gzip, etc)
        ]
        .into_iter()
        .collect()
    );
```

### Server Streaming via gRPC-Web

Server streaming É suportado em gRPC-Web. A implementação é idêntica à seção anterior; o `GrpcWebLayer` traduz automaticamente:

```rust
// No .proto
service RouteGuide {
    rpc ListFeatures(Rectangle) returns (stream Feature) {}  // ✅ Funciona em gRPC-Web
}

// No servidor (nenhuma mudança necessária)
type ListFeaturesStream = ReceiverStream<Result<Feature, Status>>;

async fn list_features(
    &self,
    request: Request<Rectangle>,
) -> Result<Response<Self::ListFeaturesStream>, Status> {
    // ... implementação igual
}
```

**Cliente Flutter Web (Dart + gRPC-Web):**

```dart
import 'package:grpc/grpc_web.dart';

final channel = GrpcWebClientChannel.xhr(Uri.parse('http://localhost:50051'));
final client = RouteGuideClient(channel);

// Iniciar stream
final stream = client.listFeatures(Rectangle(...));
await for (final feature in stream) {
    print('Feature: ${feature.name}');
}
```

### Exemplo Completo: Servidor com gRPC-Web + CORS

```rust
use tonic::{transport::Server, Request, Response, Status};
use tonic_web::GrpcWebLayer;
use tower_http::cors::CorsLayer;
use tower::ServiceBuilder;

// 1. Implementação do serviço (igual a qualquer servidor tonic)
#[derive(Default)]
pub struct MyGreeter;

#[tonic::async_trait]
impl greeter_server::Greeter for MyGreeter {
    async fn say_hello(
        &self,
        request: Request<HelloRequest>,
    ) -> Result<Response<HelloReply>, Status> {
        let name = request.into_inner().name;
        Ok(Response::new(HelloReply {
            message: format!("Hello {}", name),
        }))
    }
}

// 2. Main: servidor com gRPC-Web
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "0.0.0.0:50051".parse()?;
    
    let greeter = MyGreeter::default();
    let greeter_server = greeter_server::GreeterServer::new(greeter);
    
    // Configurar CORS para navegador
    let cors = CorsLayer::permissive();
    
    println!("Server listening on {}", addr);
    println!("gRPC-Web endpoint: http://localhost:50051");
    
    Server::builder()
        .accept_http1(true)  // HTTP/1.1 para gRPC-Web
        .layer(
            ServiceBuilder::new()
                .layer(cors)
                .layer(GrpcWebLayer::new())
                .into_inner()
        )
        .add_service(greeter_server)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

### Limitações de gRPC-Web

- ✅ **Server Streaming:** Suportado
- ✅ **Unary (RPC simples):** Suportado
- ❌ **Client Streaming:** Não suportado
- ❌ **Bidirectional Streaming:** Não suportado

Se você precisa de client streaming ou bidi, use WebSockets com tonic-web ou considere uma abordagem REST + WebSocket.

---

## Histórico de Atualizações

| Data | Versão | Mudanças |
|------|--------|----------|
| 2026-06-04 | 0.14.6 | Adicionadas seções "Server Streaming" (realtime — D7) com ReceiverStream/async_stream e integração Redis pub/sub; adicionada seção "gRPC-Web (tonic-web) para Flutter Web" com exemplos de accept_http1, GrpcWebLayer, CORS, e limitações. Library ID Context7: `/websites/rs_tonic_0_14_6_tonic` e `/hyperium/tonic`. |
| 2026-06-02 | 0.14.6 | Criação inicial com autenticação JWT, interceptors, extensões de Request e status codes. |

## Versão Verificada

- **Data:** 2026-06-04
- **Versão Tonic:** 0.14.6
- **Tokio:** 1.x (1.40+)
- **Prost:** 0.14
- **Tonic-Build:** 0.14.6
- **Tonic-Web:** 0.12 (compatível com tonic 0.14.6)
- **Library ID (Context7):** `/websites/rs_tonic_0_14_6_tonic`, `/hyperium/tonic`
