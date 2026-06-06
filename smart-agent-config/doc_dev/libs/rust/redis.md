# Redis

- **Versão Recomendada:** 0.25.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-05-31
- **Propósito no Projeto:** Barramento de eventos assíncronos (Redis Streams), gerenciamento de cache, controle de presença e pub/sub de realtime (WebSocket).
- **Documentação Oficial:** [https://docs.rs/redis/latest/redis/](https://docs.rs/redis/latest/redis/)

---

## 1. Contexto e Uso no Projeto

O Redis atua como o **coração de sincronização assíncrona** da v2.
1. **Event Bus (Redis Streams):** O `messaging_gateway` recebe mensagens brutas do webhook do WhatsApp e as despacha em um stream. O `worker` consome esses eventos usando Consumer Groups para processar a lógica do domínio.
2. **WebSocket Pub/Sub:** Permite que nós do `runtime_api` distribuam eventos de WebSocket em tempo real entre servidores concorrentes caso o sistema seja escalado na VM.
3. **Cache de Sessão/Presença:** Rastreamento do status do atendente ("Online", "Ausente") e status de digitação ("typing...").

---

## 2. Padrões de Implementação e Boas Práticas

### 2.1 Envelopamento Obrigatório de Eventos
Qualquer evento publicado no barramento de mensageria (Redis Streams) deve seguir rigorosamente a estrutura de envelope, onde o `tenant_id` reside na raiz do payload. Isso garante idempotência e permite que consumidores assíncronos configurem o contexto RLS de banco antes de rodar os Use Cases.

```rust
use serde::{Serialize, Deserialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Serialize, Deserialize)]
pub struct TenantEnvelope<T> {
    pub tenant_id: Uuid,
    pub event_id: Uuid,         // UUID v7 para garantir ordenamento natural e idempotência
    pub event_type: String,     // Ex: "message.received"
    pub timestamp: DateTime<Utc>,
    pub payload: T,
}
```

### 2.2 Divisão em Namespaces de Chaves por Tenant
Por ser uma infraestrutura única compartilhada, toda chave de cache gravada no Redis deve pertencer a um namespace delimitado pelo UUID do inquilino.

*   **Padrão de nomenclatura das chaves:** `tenant:<uuid>:<recurso>:<chave>`
*   Exemplos:
    *   `tenant:f47ac10b-58cc-4372-a567-0e02b2c3d479:presence:agent_123`
    *   `tenant:f47ac10b-58cc-4372-a567-0e02b2c3d479:session:lock:contact_999`

```rust
pub fn make_presence_key(tenant_id: Uuid, agent_id: &str) -> String {
    format!("tenant:{}:presence:{}", tenant_id, agent_id)
}
```

### 2.3 Publicando no Redis Streams
Ao postar no Stream, use conexões assíncronas do Redis e trate falhas de publicação redirecionando logs sem travar a resposta HTTP inicial do webhook.

```rust
use redis::{AsyncCommands, streams::StreamMaxlen};

pub async fn publish_event_to_bus<T: serde::Serialize>(
    con: &mut redis::aio::Connection,
    event: &TenantEnvelope<T>,
) -> Result<String, redis::RedisError> {
    let serialized_payload = serde_json::to_string(&event.payload)
        .map_err(|e| redis::RedisError::from((redis::ErrorKind::TypeError, "Erro de serialização JSON", e.to_string())))?;

    // Publica no stream limitando o tamanho máximo para evitar vazamento de memória (ex: max 10.000 itens)
    let stream_key = "events:stream";
    let event_id_str = event.event_id.to_string();

    con.xadd_maxlen(
        stream_key,
        StreamMaxlen::Approx(10000),
        event_id_str,
        &[
            ("tenant_id", event.tenant_id.to_string()),
            ("event_type", event.event_type.clone()),
            ("timestamp", event.timestamp.to_rfc3339()),
            ("payload", serialized_payload),
        ],
    )
    .await
}
```

### 2.4 Bloqueio Distribuído (Mutex) para Debounce
Para o **Debounce por Contato** (evitar disparos de múltiplas IAs quando o cliente envia frases fragmentadas em rajadas curtas), utilize chaves temporárias com TTL do Redis para coordenar o lock temporário de processamento:

```rust
pub async fn acquire_lock_with_ttl(
    con: &mut redis::aio::Connection,
    tenant_id: Uuid,
    contact_id: &str,
    ttl_seconds: usize,
) -> bool {
    let lock_key = format!("tenant:{}:lock:debounce:{}", tenant_id, contact_id);
    // SET lock_key "1" NX EX ttl_seconds
    let res: Result<String, _> = redis::cmd("SET")
        .arg(&lock_key)
        .arg("1")
        .arg("NX")
        .arg("EX")
        .arg(ttl_seconds)
        .query_async(con)
        .await;

    res.is_ok()
}
```
