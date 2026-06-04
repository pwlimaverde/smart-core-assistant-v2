# Tonic-Web (gRPC-Web)

- **Versão Recomendada:** 0.12
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-04
- **Propósito no Projeto:** Tradução gRPC-Web no runtime_api para o app Flutter Web (decisão D7). Permite clientes web/mobile acessarem serviços gRPC via HTTP/1.1.
- **Documentação Oficial:** https://github.com/hyperium/tonic/tree/master/tonic-web
- **Library ID (Context7):** `/hyperium/tonic`

---

## Compatibilidade com Tonic

| Crate | Versão | Notas |
|-------|--------|-------|
| `tonic-web` | `0.12` | Compatível com tonic 0.14.6 |
| `tonic` | `0.14.6` | Servidor base |
| `tower-http` | `0.5` | Para CorsLayer |
| `tower` | `0.4` | Middleware/layers |

---

## Guia de Uso Rápido

### 1. Instalação das Dependências

```toml
[dependencies]
tonic = "0.14"
tonic-web = "0.12"
tower = "0.4"
tower-http = { version = "0.5", features = ["cors", "trace"] }
http = "1.0"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }
```

### 2. Configuração Básica: accept_http1 + GrpcWebLayer

O servidor gRPC padrão usa HTTP/2. Para suportar gRPC-Web (que usa HTTP/1.1 desde o cliente navegador), você DEVE:

1. Ativar `accept_http1(true)` no builder do servidor
2. Adicionar `GrpcWebLayer` ao pipeline de layers

```rust
use tonic::transport::Server;
use tonic_web::GrpcWebLayer;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let greeter = GreeterServer::new(MyGreeter::default());
    
    Server::builder()
        .accept_http1(true)  // Essencial: permite HTTP/1.1
        .layer(GrpcWebLayer::new())  // Traduz gRPC-Web em gRPC nativo
        .add_service(greeter)
        .serve(addr)
        .await?;
    
    println!("Servidor gRPC-Web listening on {}", addr);
    Ok(())
}
```

**O que `accept_http1(true)` faz:**
- O servidor passa a ouvir tanto HTTP/2 (padrão gRPC) quanto HTTP/1.1 (gRPC-Web)
- Clientes gRPC tradicionais continuam funcionando normalmente
- Clientes web/mobile via gRPC-Web podem se conectar

**O que `GrpcWebLayer::new()` faz:**
- Intercepta requests HTTP/1.1 que chegam em formato gRPC-Web
- Traduz internamente para gRPC/HTTP/2
- Encapsula responses de volta em gRPC-Web

### 3. CORS: Configuração Obrigatória para Navegador

Clientes web (browsers, Flutter Web) são submetidos à política CORS. Sem configuração adequada, o navegador bloqueia requests.

**Instalação:**
```toml
tower-http = { version = "0.5", features = ["cors"] }
```

**Configuração Permissiva (Desenvolvimento):**

```rust
use tower_http::cors::CorsLayer;
use tower::ServiceBuilder;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    
    let greeter = GreeterServer::new(MyGreeter::default());
    
    // CORS permissivo: aceita qualquer origem
    let cors = CorsLayer::permissive();
    
    Server::builder()
        .accept_http1(true)
        .layer(
            ServiceBuilder::new()
                .layer(cors)
                .layer(GrpcWebLayer::new())
                .into_inner()
        )
        .add_service(greeter)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

**Configuração Restritiva (Produção):**

```rust
use tower_http::cors::CorsLayer;
use http::{Method, HeaderName};

let cors = CorsLayer::permissive()
    .allow_origin(
        "https://app.example.com"
            .parse()
            .expect("Origem inválida")
    )
    .allow_methods([
        Method::GET,
        Method::POST,
        Method::OPTIONS,
    ])
    .allow_headers(
        vec![
            HeaderName::from_static("content-type"),
            HeaderName::from_static("grpc-encoding"),
        ]
        .into_iter()
        .collect()
    )
    .expose_headers(
        vec![
            HeaderName::from_static("grpc-status"),
            HeaderName::from_static("grpc-message"),
            HeaderName::from_static("grpc-encoding"),
        ]
        .into_iter()
        .collect()
    );
```

### 4. Headers CORS Críticos

O navegador requer que estes headers sejam **explicitamente expostos** para gRPC-Web:

| Header | Propósito |
|--------|-----------|
| `content-type` | Tipo do payload (padrão HTTP) |
| `grpc-status` | Código de status gRPC (0 = OK, outros = erro) |
| `grpc-message` | Mensagem de erro legível (error message) |
| `grpc-encoding` | Codificação de compressão (gzip, deflate, etc) |

**Use `.expose_headers()` para declarar explicitamente:**

```rust
let cors = CorsLayer::permissive()
    .expose_headers(
        vec![
            HeaderName::from_static("content-type"),
            HeaderName::from_static("grpc-status"),
            HeaderName::from_static("grpc-message"),
            HeaderName::from_static("grpc-encoding"),
        ]
        .into_iter()
        .collect()
    );
```

### 5. Server Streaming em gRPC-Web

Server streaming É completamente suportado em gRPC-Web. Nenhuma mudança de código é necessária; o `GrpcWebLayer` traduz automaticamente.

**Definição .proto:**
```proto
service RealtimeEvents {
    rpc Subscribe(SubscriptionRequest) returns (stream EventMessage) {}
}
```

**Implementação Rust (idêntica a um servidor gRPC padrão):**
```rust
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

type SubscribeStream = ReceiverStream<Result<EventMessage, Status>>;

async fn subscribe(
    &self,
    request: Request<SubscriptionRequest>,
) -> Result<Response<Self::SubscribeStream>, Status> {
    let (tx, rx) = mpsc::channel(100);
    
    tokio::spawn(async move {
        for i in 0..10 {
            let event = EventMessage {
                id: i,
                data: format!("Event {}", i),
            };
            if let Err(_) = tx.send(Ok(event)).await {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    });
    
    Ok(Response::new(ReceiverStream::new(rx)))
}
```

**Cliente Flutter Web (Dart + gRPC-Web):**
```dart
import 'package:grpc/grpc_web.dart';

final channel = GrpcWebClientChannel.xhr(
    Uri.parse('http://localhost:50051')
);
final stub = RealtimeEventsClient(channel);

// Iniciar stream server
final stream = stub.subscribe(SubscriptionRequest());
await for (final event in stream) {
    print('Evento recebido: ${event.data}');
}
```

### 6. Exemplo Completo: Servidor gRPC-Web com Autenticação

```rust
use tonic::{transport::Server, Request, Response, Status, service::Interceptor};
use tonic_web::GrpcWebLayer;
use tower_http::cors::CorsLayer;
use tower::ServiceBuilder;

// 1. Interceptor JWT (validar token na abertura da conexão)
#[derive(Clone)]
pub struct AuthInterceptor;

impl Interceptor for AuthInterceptor {
    fn call(&mut self, request: Request<()>) -> Result<Request<()>, Status> {
        let metadata = request.metadata();
        
        let auth_header = metadata
            .get("authorization")
            .and_then(|h| h.to_str().ok())
            .ok_or_else(|| Status::unauthenticated("Token ausente"))?;
        
        let token = auth_header
            .strip_prefix("Bearer ")
            .ok_or_else(|| Status::unauthenticated("Formato Bearer esperado"))?;
        
        // Validar JWT aqui (usar jsonwebtoken crate)
        validate_token(token)?;
        
        Ok(request)
    }
}

fn validate_token(token: &str) -> Result<(), Status> {
    // Implementar validação JWT
    if token.len() < 20 {
        return Err(Status::unauthenticated("Token inválido"));
    }
    Ok(())
}

// 2. Implementação do serviço
#[derive(Default)]
pub struct MyService;

#[tonic::async_trait]
impl greeter_server::Greeter for MyService {
    async fn say_hello(
        &self,
        request: Request<HelloRequest>,
    ) -> Result<Response<HelloReply>, Status> {
        let name = request.into_inner().name;
        Ok(Response::new(HelloReply {
            message: format!("Olá, {}!", name),
        }))
    }
}

// 3. Main: servidor com gRPC-Web + CORS + Autenticação
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "0.0.0.0:50051".parse()?;
    
    let service = MyService::default();
    let service_server = greeter_server::GreeterServer::new(service)
        .with_interceptor(AuthInterceptor);  // Aplicar autenticação
    
    // Configurar CORS
    let cors = CorsLayer::permissive()
        .expose_headers(
            vec![
                http::HeaderName::from_static("grpc-status"),
                http::HeaderName::from_static("grpc-message"),
            ]
            .into_iter()
            .collect()
        );
    
    println!("Servidor gRPC-Web + Autenticação listening on {}", addr);
    
    Server::builder()
        .accept_http1(true)
        .layer(
            ServiceBuilder::new()
                .layer(cors)
                .layer(GrpcWebLayer::new())
                .into_inner()
        )
        .add_service(service_server)
        .serve(addr)
        .await?;
    
    Ok(())
}
```

---

## Limitações Conhecidas de gRPC-Web

| Tipo RPC | Suporte | Notas |
|----------|---------|-------|
| **Unary** | ✅ Sim | RPC simples (request → response) |
| **Server Streaming** | ✅ Sim | Stream de respostas do servidor |
| **Client Streaming** | ❌ Não | HTTP/1.1 não permite múltiplos frames de upload |
| **Bidirectional** | ❌ Não | Requer suporte bidi não disponível em HTTP/1.1 |

**Alternativa para Client Streaming/Bidi:** Se você precisar de duas vias de comunicação, considere:
- WebSocket + gRPC (usando bibliotecas como `tokio-tungstenite`)
- REST API com polling ou Server-Sent Events (SSE)
- GraphQL Subscriptions

---

## Troubleshooting

### Erro: "CORS policy blocked request"

**Causa:** Headers `grpc-status` e `grpc-message` não estão expostos.

**Solução:**
```rust
let cors = CorsLayer::permissive()
    .expose_headers(
        vec![
            HeaderName::from_static("grpc-status"),
            HeaderName::from_static("grpc-message"),
        ]
        .into_iter()
        .collect()
    );
```

### Cliente web não consegue se conectar

**Causa Comum:** `accept_http1(true)` não está ativado.

**Solução:**
```rust
Server::builder()
    .accept_http1(true)  // OBRIGATÓRIO
    .layer(GrpcWebLayer::new())
    .add_service(...)
```

### Erro: "Unary RPC succeeded, but no message received"

**Causa:** A resposta não foi formatada corretamente para gRPC-Web.

**Solução:** Certifique-se de que `GrpcWebLayer` está no pipeline de layers DEPOIS do `CorsLayer`:
```rust
ServiceBuilder::new()
    .layer(cors)           // Primeiro: CORS
    .layer(GrpcWebLayer::new())  // Segundo: gRPC-Web
    .into_inner()
```

---

## Histórico de Atualizações

| Data | Versão | Mudanças |
|------|--------|----------|
| 2026-06-04 | 0.12 | Criação inicial com guia completo: accept_http1, GrpcWebLayer, CORS configuration, server streaming, autenticação JWT, limitações de gRPC-Web, e troubleshooting. Library ID Context7: `/hyperium/tonic`. |

---

## Referências Adicionais

- **Documentação Oficial:** https://github.com/hyperium/tonic/tree/master/tonic-web
- **Tonic Documentation:** https://docs.rs/tonic/0.14.6
- **gRPC-Web Specification:** https://github.com/grpc/grpc-web
- **Flutter gRPC-Web:** https://pub.dev/packages/grpc
