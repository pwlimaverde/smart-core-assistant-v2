# Evolution API — gRPC Bridge Pattern

Para integrar Evolution API em um projeto que usa gRPC (como smart-core), este documento descreve o padrão de wrapper gRPC para abstrair a comunicação REST com Evolution.

---

## Visão Geral da Arquitetura

```
┌─────────────────────────────────────────┐
│  Flutter App / Rust Client              │
│  (usa gRPC)                             │
└────────────┬────────────────────────────┘
             │ gRPC
             ▼
┌─────────────────────────────────────────┐
│  WhatsApp Service (gRPC)                │
│  - whatsapp.proto                       │
│  - WhatsappService::sendMessage()       │
│  - WhatsappService::createInstance()    │
└────────────┬────────────────────────────┘
             │ HTTP (REST)
             ▼
┌─────────────────────────────────────────┐
│  Evolution API                          │
│  POST /message/sendText                 │
│  GET /instance/connectionState          │
│  PUT /webhook/set                       │
└─────────────────────────────────────────┘
```

---

## Proto Definition

Criar arquivo `proto/whatsapp.proto`:

```protobuf
syntax = "proto3";

package whatsapp;

option java_multiple_files = true;
option java_package = "com.smartcore.whatsapp";
option csharp_namespace = "SmartCore.Whatsapp";

// Serviço WhatsApp — interface gRPC
service WhatsappService {
  // Instâncias
  rpc CreateInstance (CreateInstanceRequest) returns (CreateInstanceResponse);
  rpc GetConnectionState (GetConnectionStateRequest) returns (GetConnectionStateResponse);
  rpc ListInstances (ListInstancesRequest) returns (ListInstancesResponse);
  rpc LogoutInstance (LogoutInstanceRequest) returns (LogoutInstanceResponse);
  rpc DeleteInstance (DeleteInstanceRequest) returns (DeleteInstanceResponse);

  // Mensagens
  rpc SendTextMessage (SendTextMessageRequest) returns (SendTextMessageResponse);
  rpc SendMediaMessage (SendMediaMessageRequest) returns (SendMediaMessageResponse);

  // Webhooks
  rpc ConfigureWebhook (ConfigureWebhookRequest) returns (ConfigureWebhookResponse);
  
  // Stream para webhook events
  rpc SubscribeToEvents (SubscribeToEventsRequest) returns (stream WebhookEvent);
}

// ========== Requests ==========

message CreateInstanceRequest {
  string instance_name = 1;
  string integration = 2;  // WHATSAPP-BAILEYS (padrão)
  bool qrcode = 3;
  string phone = 4;  // Alternativa ao QR code
}

message GetConnectionStateRequest {
  string instance_name = 1;
}

message ListInstancesRequest {
  int32 page = 1;
  int32 offset = 2;
}

message LogoutInstanceRequest {
  string instance_name = 1;
}

message DeleteInstanceRequest {
  string instance_name = 1;
}

message SendTextMessageRequest {
  string instance_name = 1;
  string number = 2;  // Formato DDI: 5511999999999
  string text = 3;
  int32 delay_ms = 4;
  bool link_preview = 5;
  repeated string mentioned = 6;  // JIDs para mencionar
  
  // Opcional: responder a mensagem anterior
  message QuotedMessage {
    string message_id = 1;
    string remote_jid = 2;
    bool from_me = 3;
  }
  QuotedMessage quoted = 7;
}

message SendMediaMessageRequest {
  string instance_name = 1;
  string number = 2;
  string media_type = 3;  // image, video, audio, document
  string media = 4;       // URL, caminho local, ou base64
  string caption = 5;
  string mime_type = 6;   // image/jpeg, video/mp4, etc.
  int32 delay_ms = 7;
}

message ConfigureWebhookRequest {
  string instance_name = 1;
  string webhook_url = 2;
  repeated string events = 3;  // MESSAGES_UPSERT, CONNECTION_UPDATE, etc.
  bool enabled = 4;
  map<string, string> headers = 5;  // Headers customizados
}

message SubscribeToEventsRequest {
  string instance_name = 1;
  repeated string events = 2;
}

// ========== Responses ==========

message CreateInstanceResponse {
  bool success = 1;
  string instance_token = 2;  // hash para futuras operações
  string qr_code_base64 = 3;  // Se qrcode=true
  string error = 4;
}

message GetConnectionStateResponse {
  bool success = 1;
  string state = 2;  // open, close, connecting
  string error = 3;
}

message ListInstancesResponse {
  message Instance {
    string instance_name = 1;
    string instance_token = 2;
    string status = 3;
    string qr_code_base64 = 4;
    bool phone_connected = 5;
  }
  
  bool success = 1;
  repeated Instance instances = 2;
  int32 total = 3;
  int32 page = 4;
  string error = 5;
}

message LogoutInstanceResponse {
  bool success = 1;
  string message = 2;
  string error = 3;
}

message DeleteInstanceResponse {
  bool success = 1;
  string error = 2;
}

message SendTextMessageResponse {
  bool success = 1;
  string message_id = 2;
  int64 timestamp = 3;
  string error = 4;
}

message SendMediaMessageResponse {
  bool success = 1;
  string message_id = 2;
  int64 timestamp = 3;
  string media_url = 4;  // URL pública da mídia
  string error = 5;
}

message ConfigureWebhookResponse {
  bool success = 1;
  string error = 2;
}

// ========== Webhook Events (Stream) ==========

message WebhookEvent {
  string event_type = 1;  // messages.upsert, connection.update, etc.
  string instance_name = 2;
  int64 timestamp = 3;
  bytes payload_json = 4;  // Raw JSON payload da Evolution
}

message MessageEvent {
  string message_id = 1;
  string remote_jid = 2;
  bool from_me = 3;
  string text = 4;
  int64 timestamp = 5;
  string sender_name = 6;
}

message ConnectionEvent {
  string state = 1;  // open, close, connecting
  int32 reason = 2;
}

message QRCodeEvent {
  string qr_code_base64 = 1;
  string code = 2;
}
```

---

## Implementação em Rust

### Estrutura de Projeto

```
crates/
├── whatsapp-service/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs
│   │   ├── evolution_client.rs      # Cliente REST para Evolution
│   │   ├── grpc_service.rs          # Implementação do serviço gRPC
│   │   ├── webhook_handler.rs       # Handler de webhooks
│   │   └── types.rs                 # Tipos compartilhados
│   └── proto/
│       └── whatsapp.proto
```

### Arquivo: `src/evolution_client.rs`

```rust
use reqwest::Client;
use serde_json::{json, Value};
use std::time::Duration;

#[derive(Clone)]
pub struct EvolutionClient {
    base_url: String,
    global_token: String,
    client: Client,
}

impl EvolutionClient {
    pub fn new(base_url: String, global_token: String) -> Self {
        Self {
            base_url,
            global_token,
            client: Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .unwrap(),
        }
    }

    pub async fn create_instance(
        &self,
        instance_name: &str,
    ) -> Result<(String, Option<String>), String> {
        let url = format!("{}/instance/create", self.base_url);
        let payload = json!({
            "instanceName": instance_name,
            "integration": "WHATSAPP-BAILEYS",
            "qrcode": true
        });

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("apikey", &self.global_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("Parse failed: {}", e))?;

        let hash = body["response"]["instance"]["hash"]
            .as_str()
            .ok_or("Missing hash")?
            .to_string();

        let qr_code = body["response"]["instance"]["qrCode"]["imageBase64"]
            .as_str()
            .map(|s| s.to_string());

        Ok((hash, qr_code))
    }

    pub async fn get_connection_state(&self, instance_name: &str) -> Result<String, String> {
        let url = format!(
            "{}/instance/connectionState/{}",
            self.base_url, instance_name
        );

        let response = self
            .client
            .get(&url)
            .header("apikey", &self.global_token)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("Parse failed: {}", e))?;

        Ok(body["response"]["instance"]["state"]
            .as_str()
            .unwrap_or("unknown")
            .to_string())
    }

    pub async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &str,
        number: &str,
        text: &str,
    ) -> Result<(String, i64), String> {
        let url = format!("{}/message/sendText/{}", self.base_url, instance_name);

        let payload = json!({
            "number": number,
            "text": text,
            "delay": 0,
            "linkPreview": true
        });

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("apikey", instance_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("HTTP {}", response.status()));
        }

        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("Parse failed: {}", e))?;

        let msg_id = body["response"]["key"]["id"]
            .as_str()
            .ok_or("Missing message id")?
            .to_string();

        let timestamp = body["response"]["messageTimestamp"]
            .as_i64()
            .unwrap_or(0);

        Ok((msg_id, timestamp))
    }

    pub async fn send_media_url(
        &self,
        instance_name: &str,
        instance_token: &str,
        number: &str,
        media_url: &str,
        media_type: &str,
        caption: Option<&str>,
        mime_type: &str,
    ) -> Result<(String, i64), String> {
        let url = format!("{}/message/sendMedia/{}", self.base_url, instance_name);

        let mut payload = json!({
            "number": number,
            "mediatype": media_type,
            "media": media_url,
            "mimetype": mime_type
        });

        if let Some(cap) = caption {
            payload["caption"] = json!(cap);
        }

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("apikey", instance_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        if !response.status().is_success() {
            let err_body: Value = response.json().await.unwrap_or(json!({}));
            return Err(format!("HTTP error: {:?}", err_body["response"]));
        }

        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("Parse failed: {}", e))?;

        let msg_id = body["response"]["key"]["id"]
            .as_str()
            .ok_or("Missing message id")?
            .to_string();

        let timestamp = body["response"]["messageTimestamp"]
            .as_i64()
            .unwrap_or(0);

        Ok((msg_id, timestamp))
    }

    pub async fn list_instances(&self) -> Result<Vec<(String, String, String)>, String> {
        let url = format!("{}/instance/fetchInstances", self.base_url);

        let response = self
            .client
            .get(&url)
            .header("apikey", &self.global_token)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let body: Value = response
            .json()
            .await
            .map_err(|e| format!("Parse failed: {}", e))?;

        let instances = body["response"]["instances"]
            .as_array()
            .ok_or("Invalid response")?
            .iter()
            .filter_map(|i| {
                let name = i["instanceName"].as_str()?;
                let hash = i["hash"].as_str()?;
                let status = i["status"].as_str()?;
                Some((
                    name.to_string(),
                    hash.to_string(),
                    status.to_string(),
                ))
            })
            .collect();

        Ok(instances)
    }

    pub async fn configure_webhook(
        &self,
        instance_name: &str,
        instance_token: &str,
        webhook_url: &str,
        events: Vec<&str>,
    ) -> Result<(), String> {
        let url = format!("{}/webhook/set/{}", self.base_url, instance_name);

        let payload = json!({
            "enabled": true,
            "url": webhook_url,
            "webhookByEvents": false,
            "webhookBase64": false,
            "events": events
        });

        let response = self
            .client
            .put(&url)
            .header("Content-Type", "application/json")
            .header("apikey", instance_token)
            .json(&payload)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err(format!("HTTP {}", response.status()))
        }
    }
}
```

### Arquivo: `src/grpc_service.rs`

```rust
use crate::evolution_client::EvolutionClient;
use tonic::{Request, Response, Status};

pub mod whatsapp {
    tonic::include_proto!("whatsapp");
}

use whatsapp::{
    whatsapp_service_server::WhatsappService,
    CreateInstanceRequest, CreateInstanceResponse, GetConnectionStateRequest,
    GetConnectionStateResponse, ListInstancesRequest, ListInstancesResponse,
    SendTextMessageRequest, SendTextMessageResponse, SendMediaMessageRequest,
    SendMediaMessageResponse, ConfigureWebhookRequest, ConfigureWebhookResponse,
};

pub struct WhatsappServiceImpl {
    evolution_client: EvolutionClient,
}

impl WhatsappServiceImpl {
    pub fn new(evolution_client: EvolutionClient) -> Self {
        Self { evolution_client }
    }
}

#[tonic::async_trait]
impl WhatsappService for WhatsappServiceImpl {
    async fn create_instance(
        &self,
        request: Request<CreateInstanceRequest>,
    ) -> Result<Response<CreateInstanceResponse>, Status> {
        let req = request.into_inner();

        let (token, qr_code) = self
            .evolution_client
            .create_instance(&req.instance_name)
            .await
            .map_err(|e| Status::internal(e))?;

        Ok(Response::new(CreateInstanceResponse {
            success: true,
            instance_token: token,
            qr_code_base64: qr_code.unwrap_or_default(),
            error: String::new(),
        }))
    }

    async fn get_connection_state(
        &self,
        request: Request<GetConnectionStateRequest>,
    ) -> Result<Response<GetConnectionStateResponse>, Status> {
        let req = request.into_inner();

        let state = self
            .evolution_client
            .get_connection_state(&req.instance_name)
            .await
            .map_err(|e| Status::internal(e))?;

        Ok(Response::new(GetConnectionStateResponse {
            success: true,
            state,
            error: String::new(),
        }))
    }

    async fn list_instances(
        &self,
        request: Request<ListInstancesRequest>,
    ) -> Result<Response<ListInstancesResponse>, Status> {
        let _req = request.into_inner();

        let instances_data = self
            .evolution_client
            .list_instances()
            .await
            .map_err(|e| Status::internal(e))?;

        let instances = instances_data
            .into_iter()
            .map(|(name, token, status)| {
                whatsapp::list_instances_response::Instance {
                    instance_name: name,
                    instance_token: token,
                    status,
                    qr_code_base64: String::new(),
                    phone_connected: status == "open",
                }
            })
            .collect();

        Ok(Response::new(ListInstancesResponse {
            success: true,
            instances,
            total: 0,
            page: 1,
            error: String::new(),
        }))
    }

    async fn send_text_message(
        &self,
        request: Request<SendTextMessageRequest>,
    ) -> Result<Response<SendTextMessageResponse>, Status> {
        let req = request.into_inner();

        // Aqui seria necessário recuperar instance_token do banco de dados
        // usando req.instance_name
        let instance_token = ""; // TODO: fetch from DB

        let (msg_id, timestamp) = self
            .evolution_client
            .send_text(&req.instance_name, instance_token, &req.number, &req.text)
            .await
            .map_err(|e| Status::internal(e))?;

        Ok(Response::new(SendTextMessageResponse {
            success: true,
            message_id: msg_id,
            timestamp,
            error: String::new(),
        }))
    }

    async fn send_media_message(
        &self,
        request: Request<SendMediaMessageRequest>,
    ) -> Result<Response<SendMediaMessageResponse>, Status> {
        let req = request.into_inner();

        // TODO: fetch instance_token from DB
        let instance_token = "";

        let (msg_id, timestamp) = self
            .evolution_client
            .send_media_url(
                &req.instance_name,
                instance_token,
                &req.number,
                &req.media,
                &req.media_type,
                if req.caption.is_empty() {
                    None
                } else {
                    Some(&req.caption)
                },
                &req.mime_type,
            )
            .await
            .map_err(|e| Status::internal(e))?;

        Ok(Response::new(SendMediaMessageResponse {
            success: true,
            message_id: msg_id,
            timestamp,
            media_url: String::new(),
            error: String::new(),
        }))
    }

    async fn configure_webhook(
        &self,
        request: Request<ConfigureWebhookRequest>,
    ) -> Result<Response<ConfigureWebhookResponse>, Status> {
        let req = request.into_inner();

        // TODO: fetch instance_token from DB
        let instance_token = "";

        self
            .evolution_client
            .configure_webhook(
                &req.instance_name,
                instance_token,
                &req.webhook_url,
                req.events
                    .iter()
                    .map(|s| s.as_str())
                    .collect(),
            )
            .await
            .map_err(|e| Status::internal(e))?;

        Ok(Response::new(ConfigureWebhookResponse {
            success: true,
            error: String::new(),
        }))
    }

    // SubscribeToEvents seria implementado como um server streaming RPC
    // que mantém a conexão aberta e envia eventos em tempo real
}
```

### Arquivo: `src/webhook_handler.rs`

```rust
use axum::{
    extract::Json,
    http::StatusCode,
    routing::post,
    Router,
};
use serde_json::Value;

pub fn webhook_routes() -> Router {
    Router::new().route("/webhook", post(handle_evolution_webhook))
}

pub async fn handle_evolution_webhook(
    Json(payload): Json<Value>,
) -> Result<StatusCode, (StatusCode, String)> {
    let event = payload["event"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing event".to_string()))?;

    let instance = payload["instance"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing instance".to_string()))?;

    match event {
        "messages.upsert" => {
            let remote_jid = payload["data"]["key"]["remoteJid"].as_str().unwrap_or("");
            let text = payload["data"]["message"]["conversation"]
                .as_str()
                .or_else(|| payload["data"]["message"]["extendedTextMessage"]["text"].as_str())
                .unwrap_or("");
            
            println!("[{}] Mensagem recebida de {}: {}", instance, remote_jid, text);
            
            // Aqui: processar mensagem com IA, salvar em BD, etc.
        }
        "connection.update" => {
            let state = payload["data"]["state"].as_str().unwrap_or("unknown");
            println!("[{}] Conexão: {}", instance, state);
        }
        "qrcode.update" => {
            let qr = payload["data"]["qrCode"]["imageBase64"].as_str().unwrap_or("");
            println!("[{}] Novo QR code ({} chars)", instance, qr.len());
        }
        _ => println!("Evento desconhecido: {}", event),
    }

    Ok(StatusCode::OK)
}
```

---

## Uso no Rust Backend

```rust
// main.rs

use whatsapp_service::{
    EvolutionClient,
    grpc_service::{WhatsappServiceImpl, whatsapp::whatsapp_service_server::WhatsappServiceServer},
    webhook_handler::webhook_routes,
};
use tonic::transport::Server as TonicServer;
use axum::Router;
use std::net::SocketAddr;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Configurar Evolution client
    let evolution_client = EvolutionClient::new(
        "http://localhost:3000".to_string(),
        std::env::var("EVOLUTION_API_KEY").unwrap(),
    );

    // Serviço gRPC
    let whatsapp_service = WhatsappServiceImpl::new(evolution_client);

    // Server gRPC na porta 50051
    let grpc_handle = tokio::spawn(async move {
        let addr = "[::1]:50051".parse::<SocketAddr>()?;
        println!("gRPC listening on {}", addr);
        
        TonicServer::builder()
            .add_service(WhatsappServiceServer::new(whatsapp_service))
            .serve(addr)
            .await
    });

    // Server HTTP (Axum) para webhooks na porta 3001
    let webhook_router = webhook_routes();
    let http_handle = tokio::spawn(async move {
        let addr = "127.0.0.1:3001".parse::<SocketAddr>()?;
        println!("Webhooks listening on {}", addr);
        
        axum::Server::bind(&addr)
            .serve(webhook_router.into_make_service())
            .await
    });

    tokio::try_join!(grpc_handle, http_handle)?;
    
    Ok(())
}
```

---

## Integração com Flutter (Cliente gRPC)

```dart
import 'package:grpc/grpc.dart';
import 'package:whatsapp_service/whatsapp.pbgrpc.dart';

class WhatsappClient {
  late WhatsappServiceClient _client;

  WhatsappClient(String host, int port) {
    final channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    _client = WhatsappServiceClient(channel);
  }

  Future<void> createInstance(String instanceName) async {
    try {
      final response = await _client.createInstance(
        CreateInstanceRequest()..instanceName = instanceName,
      );
      
      if (response.success) {
        print('✅ Instância criada: ${response.instanceToken}');
        if (response.qrCodeBase64.isNotEmpty) {
          // Renderizar QR code
          showQRCode(response.qrCodeBase64);
        }
      }
    } catch (e) {
      print('❌ Erro: $e');
    }
  }

  Future<void> sendMessage(
    String instanceName,
    String number,
    String text,
  ) async {
    try {
      final response = await _client.sendTextMessage(
        SendTextMessageRequest()
          ..instanceName = instanceName
          ..number = number
          ..text = text,
      );

      if (response.success) {
        print('✅ Mensagem enviada: ${response.messageId}');
      } else {
        print('❌ Erro: ${response.error}');
      }
    } catch (e) {
      print('❌ Erro gRPC: $e');
    }
  }
}

// Uso
void main() async {
  final whatsappClient = WhatsappClient('localhost', 50051);
  
  await whatsappClient.createInstance('meu-bot');
  await whatsappClient.sendMessage('meu-bot', '5511999999999', 'Olá!');
}
```

---

## Armazenamento de Tokens em BD

Estrutura SQL recomendada:

```sql
CREATE TABLE whatsapp_instances (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  instance_name VARCHAR(255) NOT NULL UNIQUE,
  instance_token VARCHAR(255) NOT NULL,  -- hash/token da Evolution
  status VARCHAR(50) DEFAULT 'connecting',
  phone_number VARCHAR(20),
  qr_code_base64 TEXT,
  webhook_url VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE whatsapp_messages (
  id SERIAL PRIMARY KEY,
  instance_id INTEGER NOT NULL REFERENCES whatsapp_instances(id),
  message_id VARCHAR(255) NOT NULL UNIQUE,
  remote_jid VARCHAR(255) NOT NULL,
  direction VARCHAR(50),  -- inbound, outbound
  text TEXT,
  media_url VARCHAR(255),
  media_type VARCHAR(50),
  from_me BOOLEAN,
  timestamp BIGINT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_whatsapp_instances_user ON whatsapp_instances(user_id);
CREATE INDEX idx_whatsapp_messages_instance ON whatsapp_messages(instance_id);
CREATE INDEX idx_whatsapp_messages_jid ON whatsapp_messages(remote_jid);
```

---

## Padrão: Recuperar Instance Token em gRPC

```rust
// No serviço gRPC, recuperar token do banco

pub async fn get_instance_token(
    &self,
    db: &PgPool,
    instance_name: &str,
) -> Result<String, Status> {
    let row: (String,) = sqlx::query_as(
        "SELECT instance_token FROM whatsapp_instances WHERE instance_name = $1"
    )
    .bind(instance_name)
    .fetch_one(db)
    .await
    .map_err(|_| Status::not_found("Instance not found"))?;

    Ok(row.0)
}
```

