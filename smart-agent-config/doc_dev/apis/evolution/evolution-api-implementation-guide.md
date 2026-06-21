# Evolution API — Guia de Implementação e Troubleshooting

Este documento complementa a documentação REST principal com **snippets de código práticos**, **padrões de erro comuns** e **estratégias de debug**.

---

## Fluxo Completo: Do Setup ao Envio de Mensagens

```
┌─────────────────────────────────────────┐
│ 1. Criar Instância (POST /instance/create)
│    └─> Retorna QR code + instance token
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│ 2. Escanear QR / Aceitar Pairing
│    └─> Usuário escaneia no WhatsApp
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│ 3. Aguardar Conexão (polling state)
│    └─> GET /instance/connectionState
│       até state == "open"
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│ 4. Configurar Webhooks (PUT /webhook/set)
│    └─> Receber MESSAGES_UPSERT, etc.
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│ 5. Enviar Mensagens (POST /message/...)
│    └─> sendText, sendMedia, etc.
└─────────────────────────────────────────┘
```

---

## Exemplos de Código Rust (Produção)

### Estrutura Base — Client Wrapper

```rust
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::time::sleep;

#[derive(Clone)]
pub struct EvolutionClient {
    base_url: String,
    global_token: String,
    client: Client,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Instance {
    pub instance_name: String,
    pub hash: String,
    pub status: String,
    pub qr_code: Option<String>,
    pub phone_connected: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub remote_jid: String,
    pub from_me: bool,
    pub text: String,
    pub timestamp: u64,
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

    fn error_header(&self) -> (String, String) {
        ("apikey".to_string(), self.global_token.clone())
    }

    /// Criar nova instância com QR code
    pub async fn create_instance(
        &self,
        instance_name: &str,
    ) -> Result<Instance, Box<dyn std::error::Error>> {
        let url = format!("{}/instance/create", self.base_url);

        let payload = json!({
            "instanceName": instance_name,
            "integration": "WHATSAPP-BAILEYS",
            "qrcode": true
        });

        let (key, val) = self.error_header();
        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/json")
            .header(&key, &val)
            .json(&payload)
            .send()
            .await?;

        if response.status() != StatusCode::CREATED {
            return Err(format!("Failed to create instance: {}", response.status()).into());
        }

        let body: Value = response.json().await?;
        let instance = body["response"]["instance"].clone();

        Ok(Instance {
            instance_name: instance["instanceName"].as_str().unwrap_or("").to_string(),
            hash: instance["hash"].as_str().unwrap_or("").to_string(),
            status: instance["status"].as_str().unwrap_or("").to_string(),
            qr_code: instance["qrCode"]["imageBase64"].as_str().map(|s| s.to_string()),
            phone_connected: instance["phoneConnected"].as_bool().unwrap_or(false),
        })
    }

    /// Aguardar até instância estar conectada (polling)
    pub async fn wait_for_connection(
        &self,
        instance_name: &str,
        max_retries: u32,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let mut retries = 0;

        loop {
            let state = self.get_connection_state(instance_name).await?;

            if state == "open" {
                println!("✓ Instância {} conectada", instance_name);
                return Ok(());
            }

            if retries >= max_retries {
                return Err(format!(
                    "Timeout aguardando conexão. Estado final: {}",
                    state
                )
                .into());
            }

            println!(
                "⏳ Aguardando conexão... (tentativa {}/{})",
                retries + 1,
                max_retries
            );
            sleep(Duration::from_secs(3)).await;
            retries += 1;
        }
    }

    /// Obter estado atual de conexão
    pub async fn get_connection_state(
        &self,
        instance_name: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let url = format!(
            "{}/instance/connectionState/{}",
            self.base_url, instance_name
        );

        let (key, val) = self.error_header();
        let response = self
            .client
            .get(&url)
            .header(&key, &val)
            .send()
            .await?;

        let body: Value = response.json().await?;
        Ok(body["response"]["instance"]["state"]
            .as_str()
            .unwrap_or("unknown")
            .to_string())
    }

    /// Enviar mensagem de texto
    pub async fn send_text(
        &self,
        instance_name: &str,
        instance_token: &str,
        number: &str,
        text: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
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
            .await?;

        if !response.status().is_success() {
            let error_body: Value = response.json().await?;
            let msg = error_body["response"]["message"]
                .as_array()
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown error");
            return Err(format!("Failed to send text: {}", msg).into());
        }

        let body: Value = response.json().await?;
        Ok(body["response"]["key"]["id"]
            .as_str()
            .unwrap_or("")
            .to_string())
    }

    /// Enviar mídia por URL
    pub async fn send_media_url(
        &self,
        instance_name: &str,
        instance_token: &str,
        number: &str,
        media_url: &str,
        media_type: &str, // "image", "video", "audio", "document"
        caption: Option<&str>,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let url = format!("{}/message/sendMedia/{}", self.base_url, instance_name);

        let mut payload = json!({
            "number": number,
            "mediatype": media_type,
            "media": media_url,
            "mimetype": self.guess_mimetype(media_type)
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
            .await?;

        if !response.status().is_success() {
            let error_body: Value = response.json().await?;
            return Err(
                format!("Failed to send media: {:?}", error_body["response"]).into()
            );
        }

        let body: Value = response.json().await?;
        Ok(body["response"]["key"]["id"]
            .as_str()
            .unwrap_or("")
            .to_string())
    }

    /// Configurar webhook
    pub async fn setup_webhook(
        &self,
        instance_name: &str,
        instance_token: &str,
        webhook_url: &str,
        events: Vec<&str>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let url = format!("{}/webhook/set/{}", self.base_url, instance_name);

        let payload = json!({
            "enabled": true,
            "url": webhook_url,
            "webhookByEvents": false,
            "webhookBase64": false,
            "events": events,
            "headers": {
                "Authorization": "Bearer seu_token_secreto"
            }
        });

        let response = self
            .client
            .put(&url)
            .header("Content-Type", "application/json")
            .header("apikey", instance_token)
            .json(&payload)
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err("Failed to setup webhook".into())
        }
    }

    /// Listar todas as instâncias
    pub async fn list_instances(&self) -> Result<Vec<Instance>, Box<dyn std::error::Error>> {
        let url = format!("{}/instance/fetchInstances", self.base_url);

        let (key, val) = self.error_header();
        let response = self
            .client
            .get(&url)
            .header(&key, &val)
            .send()
            .await?;

        let body: Value = response.json().await?;
        let instances_json = &body["response"]["instances"];

        let instances = instances_json
            .as_array()
            .ok_or("Invalid response")?
            .iter()
            .map(|i| Instance {
                instance_name: i["instanceName"].as_str().unwrap_or("").to_string(),
                hash: i["hash"].as_str().unwrap_or("").to_string(),
                status: i["status"].as_str().unwrap_or("").to_string(),
                qr_code: i["qrCode"].as_object().and_then(|q| {
                    q.get("imageBase64")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                }),
                phone_connected: i["phoneConnected"].as_bool().unwrap_or(false),
            })
            .collect();

        Ok(instances)
    }

    fn guess_mimetype(&self, media_type: &str) -> &'static str {
        match media_type {
            "image" => "image/jpeg",
            "video" => "video/mp4",
            "audio" => "audio/mpeg",
            "document" => "application/pdf",
            _ => "application/octet-stream",
        }
    }
}

// Exemplo de uso
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = EvolutionClient::new(
        "http://localhost:3000".to_string(),
        "sua_global_api_key".to_string(),
    );

    // Criar instância
    println!("Criando instância...");
    let instance = client.create_instance("meu-bot").await?;
    println!(
        "Instância criada: {} (Status: {})",
        instance.instance_name, instance.status
    );

    if let Some(qr) = &instance.qr_code {
        println!("QR Code disponível ({}... chars)", qr.len());
        // Aqui você poderia gerar uma imagem PNG a partir do base64
    }

    // Aguardar conexão
    println!("Aguardando escanear QR code...");
    client.wait_for_connection(&instance.instance_name, 60).await?;

    // Enviar mensagem
    println!("Enviando mensagem...");
    let msg_id = client
        .send_text(
            &instance.instance_name,
            &instance.hash,
            "5511999999999",
            "Olá! Teste da Evolution API",
        )
        .await?;
    println!("Mensagem enviada: {}", msg_id);

    // Enviar mídia por URL
    println!("Enviando imagem...");
    let media_id = client
        .send_media_url(
            &instance.instance_name,
            &instance.hash,
            "5511999999999",
            "https://exemplo.com/imagem.jpg",
            "image",
            Some("Veja esta foto!"),
        )
        .await?;
    println!("Mídia enviada: {}", media_id);

    Ok(())
}
```

---

## Tratamento de Webhooks em Axum

```rust
use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::post,
    Router,
};
use serde_json::Value;
use std::sync::Arc;

#[derive(Clone)]
pub struct WebhookState {
    pub webhook_secret: String,
}

pub fn webhook_routes(state: Arc<WebhookState>) -> Router {
    Router::new()
        .route("/webhook", post(handle_webhook))
        .with_state(state)
}

pub async fn handle_webhook(
    State(state): State<Arc<WebhookState>>,
    Json(payload): Json<Value>,
) -> Result<StatusCode, (StatusCode, String)> {
    // Validar token de segurança (opcional)
    if let Some(auth) = payload.get("headers").and_then(|h| h.get("Authorization")) {
        if auth != "Bearer seu_token_secreto" {
            return Err((StatusCode::UNAUTHORIZED, "Invalid token".to_string()));
        }
    }

    let event = payload["event"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing event".to_string()))?;
    let instance = payload["instance"]
        .as_str()
        .ok_or((StatusCode::BAD_REQUEST, "Missing instance".to_string()))?;
    let data = &payload["data"];

    match event {
        "messages.upsert" => handle_message_upsert(instance, data).await,
        "connection.update" => handle_connection_update(instance, data).await,
        "qrcode.update" => handle_qrcode_update(instance, data).await,
        "messages.update" => handle_messages_update(instance, data).await,
        _ => {
            println!("⚠️  Evento desconhecido: {}", event);
            Ok(StatusCode::OK)
        }
    }
}

async fn handle_message_upsert(
    instance: &str,
    data: &Value,
) -> Result<StatusCode, (StatusCode, String)> {
    let remote_jid = data["key"]["remoteJid"]
        .as_str()
        .unwrap_or("unknown");
    let from_me = data["key"]["fromMe"].as_bool().unwrap_or(false);
    let msg_id = data["key"]["id"].as_str().unwrap_or("unknown");

    // Extrair texto — pode ser "conversation" ou "extendedTextMessage.text"
    let text = if let Some(conv) = data["message"]["conversation"].as_str() {
        conv.to_string()
    } else if let Some(ext_text) = data["message"]["extendedTextMessage"]["text"].as_str() {
        ext_text.to_string()
    } else {
        "[Tipo de mensagem não suportado]".to_string()
    };

    println!(
        "📨 [{}] {} → {}: {}",
        instance,
        if from_me { "📤 Enviado" } else { "📥 Recebido" },
        remote_jid,
        text
    );

    // Aqui: salvar em banco, processar com IA, responder, etc.

    Ok(StatusCode::OK)
}

async fn handle_connection_update(
    instance: &str,
    data: &Value,
) -> Result<StatusCode, (StatusCode, String)> {
    let state = data["state"]
        .as_str()
        .unwrap_or("unknown");

    println!("🔌 [{}] Conexão: {}", instance, state);

    match state {
        "open" => println!("✅ Instância {} conectada", instance),
        "close" => println!("❌ Instância {} desconectada", instance),
        "connecting" => println!("⏳ Instância {} conectando", instance),
        _ => {}
    }

    Ok(StatusCode::OK)
}

async fn handle_qrcode_update(
    instance: &str,
    data: &Value,
) -> Result<StatusCode, (StatusCode, String)> {
    if let Some(qr) = data["qrCode"]["imageBase64"].as_str() {
        println!(
            "🔐 [{}] Novo QR code gerado ({}... chars)",
            instance,
            qr.chars().take(30).collect::<String>()
        );
        // Aqui: atualizar interface, enviar para cliente, etc.
    }

    Ok(StatusCode::OK)
}

async fn handle_messages_update(
    instance: &str,
    data: &Value,
) -> Result<StatusCode, (StatusCode, String)> {
    if let Some(updates) = data.as_array() {
        for update in updates {
            let msg_id = update["key"]["id"].as_str().unwrap_or("unknown");
            let status = update["status"].as_str().unwrap_or("unknown");
            println!("📍 [{}] Mensagem {} → {}", instance, msg_id, status);
        }
    }

    Ok(StatusCode::OK)
}
```

---

## Erros Comuns e Soluções

### Erro: "Maximum call stack size exceeded" ao enviar vídeo

**Causa:** Base64 muito grande (vídeo > 3MB)

**Solução:**
```rust
// ❌ ERRADO
let video_base64 = std::fs::read("video.mp4")
    .map(|b| base64::encode(&b))?;

client.send_media_url(
    instance, token, number,
    &video_base64,  // Base64 gigante!
    "video",
    None
).await?;

// ✅ CORRETO
// Fazer upload para S3/CDN primeiro
let s3_url = upload_to_s3("video.mp4").await?;

client.send_media_url(
    instance, token, number,
    &s3_url,  // URL remota
    "video",
    Some("Veja o vídeo!")
).await?;
```

---

### Erro: "Invalid API key or Instance token" (401)

**Causa comum:** Usar global token onde precisa instância token (ou vice-versa)

**Verificação:**
```rust
// Criar instância = usa GLOBAL_TOKEN
let instance = client.create_instance("bot").await?;
println!("Hash (instance token): {}", instance.hash);

// Enviar mensagem = usa INSTANCE_TOKEN (hash)
client.send_text(
    "bot",
    &instance.hash,  // ✅ Instance token aqui!
    "5511999999999",
    "Olá"
).await?;
```

---

### Erro: "number must be a valid phone number"

**Causa:** Formato de telefone inválido

**Verificação:**
```rust
fn validate_phone(number: &str) -> bool {
    // Deve ter 13 dígitos (55 + area + numero)
    // Apenas dígitos, sem espaços, hífens, parênteses
    number.len() == 13 && number.chars().all(|c| c.is_ascii_digit())
}

assert!(validate_phone("5511999999999")); // ✅
assert!(!validate_phone("11 99999-9999")); // ❌
assert!(!validate_phone("+55 11 99999-9999")); // ❌
```

---

### Erro: "Instance not found" (404)

**Causa:** Nome da instância incorreto ou foi deletada

**Debug:**
```rust
// Listar instâncias para verificar nomes
let instances = client.list_instances().await?;
println!("Instâncias disponíveis:");
for inst in instances {
    println!("  - {} (status: {})", inst.instance_name, inst.status);
}
```

---

### Webhook não recebendo eventos

**Verificação de checklist:**

```rust
// 1. Webhook URL está acessível externamente?
// Testar: curl https://seu-servidor.com/webhook -X POST

// 2. Webhook configurado corretamente?
client.setup_webhook(
    "meu-bot",
    &instance_token,
    "https://seu-servidor.com/webhook",  // HTTPS, acessível
    vec!["MESSAGES_UPSERT", "CONNECTION_UPDATE"],
).await?;

// 3. Firewall permite porta?
// curl -v https://seu-servidor.com/webhook

// 4. Logs do servidor Evolution?
// docker logs evolution-api | grep webhook

// 5. Status da instância é "open"?
let state = client.get_connection_state("meu-bot").await?;
assert_eq!(state, "open");  // Só recebe webhooks se conectado!
```

---

### Duplicação de mensagens no webhook

**Causa:** Cada mensagem gera dois eventos (enviada + entregue)

**Solução:**
```rust
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct MessageDeduplicator {
    seen_ids: Arc<Mutex<HashSet<String>>>,
}

impl MessageDeduplicator {
    pub fn new() -> Self {
        Self {
            seen_ids: Arc::new(Mutex::new(HashSet::new())),
        }
    }

    pub async fn should_process(&self, msg_id: &str) -> bool {
        let mut seen = self.seen_ids.lock().await;
        seen.insert(msg_id.to_string())  // Retorna false se já existia
    }
}

// Uso no webhook
let dedup = MessageDeduplicator::new();

pub async fn handle_message_upsert(
    dedup: &MessageDeduplicator,
    msg_id: &str,
    text: &str,
) -> Result<StatusCode, (StatusCode, String)> {
    if !dedup.should_process(msg_id).await {
        println!("⏭️  Mensagem {} já processada", msg_id);
        return Ok(StatusCode::OK);
    }

    println!("✅ Processando mensagem {} pela primeira vez", msg_id);
    // Processar, salvar em BD, etc.

    Ok(StatusCode::OK)
}
```

---

## Padrão: Integração com Banco de Dados

```rust
use sqlx::{PgPool, FromRow};

#[derive(FromRow)]
pub struct WhatsappInstance {
    pub id: i32,
    pub instance_name: String,
    pub instance_token: String,
    pub status: String,
    pub phone: Option<String>,
}

#[derive(FromRow)]
pub struct WhatsappMessage {
    pub id: i32,
    pub instance_id: i32,
    pub remote_jid: String,
    pub message_id: String,
    pub text: String,
    pub from_me: bool,
    pub timestamp: i64,
}

pub struct WhatsappRepo {
    db: PgPool,
}

impl WhatsappRepo {
    pub async fn save_instance(
        &self,
        instance_name: &str,
        instance_token: &str,
    ) -> Result<WhatsappInstance, sqlx::Error> {
        sqlx::query_as::<_, WhatsappInstance>(
            "INSERT INTO whatsapp_instances (instance_name, instance_token, status)
             VALUES ($1, $2, 'connecting')
             RETURNING *"
        )
        .bind(instance_name)
        .bind(instance_token)
        .fetch_one(&self.db)
        .await
    }

    pub async fn save_message(
        &self,
        instance_id: i32,
        remote_jid: &str,
        message_id: &str,
        text: &str,
        from_me: bool,
        timestamp: i64,
    ) -> Result<WhatsappMessage, sqlx::Error> {
        sqlx::query_as::<_, WhatsappMessage>(
            "INSERT INTO whatsapp_messages 
             (instance_id, remote_jid, message_id, text, from_me, timestamp)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING *"
        )
        .bind(instance_id)
        .bind(remote_jid)
        .bind(message_id)
        .bind(text)
        .bind(from_me)
        .bind(timestamp)
        .fetch_one(&self.db)
        .await
    }

    pub async fn get_instance_by_name(
        &self,
        instance_name: &str,
    ) -> Result<Option<WhatsappInstance>, sqlx::Error> {
        sqlx::query_as::<_, WhatsappInstance>(
            "SELECT * FROM whatsapp_instances WHERE instance_name = $1"
        )
        .bind(instance_name)
        .fetch_optional(&self.db)
        .await
    }
}
```

---

## Checklist: Antes de Deployar em Produção

- [ ] Usar HTTPS para webhook (não HTTP)
- [ ] Configurar JWT/Bearer token no webhook para validar origem
- [ ] Implementar deduplicação de mensagens (mesmo msg_id pode vir 2x)
- [ ] Aguardar state == "open" antes de enviar mensagens
- [ ] Usar URLs para vídeos > 3MB (não base64)
- [ ] Configurar timeout de 180s para uploads de mídia
- [ ] Armazenar instance tokens em variáveis de ambiente (não hardcoded)
- [ ] Implementar retry logic para chamadas à API
- [ ] Configurar logging estruturado (Sentry, DataDog, etc.)
- [ ] Fazer backup de instance tokens (para recuperação)
- [ ] Testar failover e reconexão automática
- [ ] Monitorar webhooks com health checks
- [ ] Usar rate limiting (respeitar limites da API)
- [ ] Implementar circuit breaker para Evolution API

---

## Monitoramento e Observabilidade

```rust
use prometheus::{Counter, Gauge, Histogram};
use lazy_static::lazy_static;

lazy_static! {
    pub static ref MESSAGES_SENT: Counter =
        Counter::new("evolution_messages_sent", "Total messages sent").unwrap();
    
    pub static ref MESSAGES_RECEIVED: Counter =
        Counter::new("evolution_messages_received", "Total messages received").unwrap();
    
    pub static ref API_REQUEST_DURATION: Histogram =
        Histogram::new("evolution_api_duration_seconds", "Evolution API request duration").unwrap();
    
    pub static ref ACTIVE_INSTANCES: Gauge =
        Gauge::new("evolution_active_instances", "Number of active instances").unwrap();
    
    pub static ref WEBHOOK_ERRORS: Counter =
        Counter::new("evolution_webhook_errors", "Total webhook errors").unwrap();
}

// Usar em handlers
pub async fn send_text_with_metrics(
    client: &EvolutionClient,
    instance_name: &str,
    instance_token: &str,
    number: &str,
    text: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let timer = API_REQUEST_DURATION.start_timer();
    
    let msg_id = client
        .send_text(instance_name, instance_token, number, text)
        .await?;
    
    timer.observe_duration();
    MESSAGES_SENT.inc();
    
    Ok(msg_id)
}
```

