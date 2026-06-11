# Redis

- **Versão Recomendada:** 0.25.0
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-06-10
- **Library ID Context7:** `/redis-rs/redis-rs`
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

---

## 3. Timeouts do ConnectionManager (versão 0.25.5 fixada no projeto)

> ⚠️ **Atenção de versão (validado no fonte vendorizado `redis-0.25.5`):** nesta
> versão **NÃO existe** `ConnectionManagerConfig` nem `AsyncConnectionConfig` (esses
> são da redis-rs **≥1.0**). Não use `get_multiplexed_async_connection_with_config`.
> O caminho correto em 0.25.5 é o construtor com timeouts embutidos.

### Configuração de Timeouts em 0.25.5 — `new_with_backoff_and_timeouts`

```rust
use redis::{Client, aio::ConnectionManager};
use std::time::Duration;

let client = Client::open("redis://127.0.0.1/")?;

// Em 0.25.5 os timeouts entram no construtor (não há struct de config).
let manager = ConnectionManager::new_with_backoff_and_timeouts(
    client,
    2,                       // exponent_base do backoff de reconexão
    100,                     // factor (ms)
    6,                       // number_of_retries
    Duration::from_secs(2),  // response_timeout  (aguardando resposta)
    Duration::from_secs(2),  // connection_timeout (ao (re)conectar)
).await?;
```

**Assinatura (confirmada em `redis-0.25.5/.../aio/connection_manager.rs:147`):**
```rust
pub async fn new_with_backoff_and_timeouts(
    client: Client,
    exponent_base: u64,
    factor: u64,
    number_of_retries: usize,
    response_timeout: Duration,
    connection_timeout: Duration,
) -> RedisResult<ConnectionManager>
```
- Construtor mais simples sem timeout: `ConnectionManager::new(client)`.
- A partir da redis-rs 1.0 isso vira `ConnectionManagerConfig` + `new_with_config`;
  ao atualizar a lib, migrar este trecho.

---

## 4. Conexão Dedicada para Loops Bloqueantes (BLOCK)

Comandos de **Redis Streams** com `BLOCK` (ex.: `XREADGROUP ... BLOCK 0`) devem usar uma **conexão dedicada e não-multiplexada** porque bloqueiam o protocolo RESP. A multiplexação não funciona com bloqueios.

### Padrão: Uma Conexão Exclusiva para BLOCK

```rust
use redis::{Client, aio::Connection};
use std::time::Duration;

let client = Client::open("redis://127.0.0.1/")?;

// Para comandos que fazem BLOCK, obter conexão dedicada (não multiplexada).
// Em 0.25.5 use `get_async_connection()` (não há variante `_with_config`).
let mut blocking_con: Connection = client.get_async_connection().await?;

// Agora safe para XREADGROUP com BLOCK
use redis::AsyncCommands;

let result: Option<redis::streams::StreamReadReply> = blocking_con
    .xread_options(
        &["events:stream"],
        &[">"],
        &redis::streams::StreamReadOptions::default()
            .block(Some(0))  // 0 = bloqueia indefinidamente até nova mensagem
            .count(Some(10))
            .group("my_group", "my_consumer"),
    )
    .await?;
```

**Diferença:**
- `get_multiplexed_async_connection()` → retorna `MultiplexedConnection` (cheap clone, pipeline/multiplex, mas **NÃO** suporta BLOCK)
- `get_async_connection()` → retorna `Connection` (dedicada, suporta BLOCK)

---

## 5. Streams: XPENDING e XCLAIM (Monitoramento e Retry)

> ⚠️ **Atenção de versão (validado no fonte vendorizado `redis-0.25.5`):**
> `xautoclaim`/`xautoclaim_options` **NÃO existem** em 0.25.5. Para monitorar e
> reprocessar a PEL use os helpers tipados **`xpending`/`xpending_count`** + **`xclaim`**.

### 5.1 XPENDING — Medir Profundidade da PEL (Pending Entry List)

Helper tipado (existe em 0.25.5): `xpending` devolve `StreamPendingReply` com o
resumo do grupo. O `.count()` é o total da PEL — gauge de lag (`smartcore_bus_pending`).

```rust
use redis::AsyncCommands;
use redis::streams::StreamPendingReply;

let pending: StreamPendingReply = con.xpending("events:stream", "my_group").await?;
let total_pendente: usize = pending.count(); // gauge de profundidade da PEL
```

### 5.2 XPENDING COUNT — Contar tentativas por mensagem (base do DLQ)

`xpending_count` devolve `Vec<StreamPendingId>`, cada um com o campo
**`times_delivered`** — o contador de entregas usado para decidir a quarentena (DLQ).

```rust
use redis::streams::StreamPendingCountReply;

let detalhes: StreamPendingCountReply = con
    .xpending_count("events:stream", "my_group", "-", "+", 100)
    .await?;

for id in &detalhes.ids {
    // id.id: String (stream id), id.times_delivered: usize, id.last_delivered_ms: u64
    if id.times_delivered > 5 {
        // veneno: mover para DLQ (ver 5.3)
    }
}
```

### 5.3 XCLAIM — Reivindicar mensagem específica (retry / mover p/ DLQ)

```rust
use redis::streams::{StreamClaimOptions, StreamClaimReply};

// Reivindica para um consumer de quarentena as mensagens já identificadas como veneno
let reivindicadas: StreamClaimReply = con
    .xclaim_options(
        "events:stream",
        "my_group",
        "dlq_worker",                 // consumer que vai drená-las
        60_000,                       // min_idle_time_ms
        &["1700000000000-0"],         // ids vindos do xpending_count
        StreamClaimOptions::default(),
    )
    .await?;

// Política de DLQ: re-publica em `security:dlq` (XADD) e dá XACK no original
for entry in &reivindicadas.ids {
    // con.xadd("security:dlq", "*", &[("payload", ...)]).await?;
    // con.xack("events:stream", "my_group", &[&entry.id]).await?;
}
```

**Assinaturas (0.25.5):**
```rust
fn xpending<K, G>(key: K, group: G) -> RedisResult<StreamPendingReply>;
fn xpending_count<K, G, S, E, C>(key: K, group: G, start: S, end: E, count: C)
    -> RedisResult<StreamPendingCountReply>;     // ids: Vec<StreamPendingId>{ id, times_delivered, .. }
fn xclaim_options<...>(key, group, consumer, min_idle_time, ids, options: StreamClaimOptions)
    -> RedisResult<StreamClaimReply>;
```

> Em redis-rs ≥1.0 o `xautoclaim` passa a existir e simplifica este fluxo; ao
> atualizar a lib, considerar migrar 5.2+5.3 para `xautoclaim`.

---

## 6. DEL Variádico (Deletar Múltiplas Chaves)

```rust
use redis::Commands;  // sync ou
use redis::AsyncCommands;  // async

// Deletar múltiplas chaves em uma única chamada
let keys = vec!["key1", "key2", "key3"];
let deleted_count: usize = con.del(&keys)?;

// Ou com slice
let deleted_count: usize = con.del(&["key1", "key2", "key3"])?;

// Ou uma única chave
let deleted_count: usize = con.del("single_key")?;
```

**Assinatura:**
```rust
pub fn del<K: ToRedisArgs>(key: K) -> RedisResult<usize>
```

**Retorno:** Número de chaves efetivamente deletadas.

**Suporta:**
- Slice: `&[&str]`
- Vec: `Vec<String>`
- Single value: `&str`
- Qualquer tipo implementando `ToRedisArgs`

---

## 7. XREADGROUP, XACK e Consumer Groups

### XREADGROUP com Timeout

```rust
use redis::AsyncCommands;
use redis::streams::StreamReadOptions;

let mut con = client.get_async_connection().await?;

let result: Option<redis::streams::StreamReadReply> = con
    .xread_options(
        &["events:stream"],
        &[">"],  // ">" = ler apenas novas mensagens (não entregues)
        &StreamReadOptions::default()
            .block(Some(5000))      // block 5 segundos (milliseconds)
            .count(Some(10))        // max 10 mensagens
            .group("my_group", "my_consumer"),  // consumer group
    )
    .await?;

if let Some(reply) = result {
    for stream_key in reply.keys {
        for stream_id in stream_key.ids {
            println!("Message: {:?}", stream_id);
            // Processar mensagem...
            // Fazer ACK
            con.xack(
                "events:stream",
                "my_group",
                &[&stream_id.id],
            ).await?;
        }
    }
}
```

### XACK (Acknowledge)

```rust
// Confirmar (ACK) que a mensagem foi processada com sucesso
let acked_count: usize = con
    .xack("events:stream", "my_group", &["1234567890-0"])
    .await?;
```

**Assinatura:**
```rust
pub fn xack<K, G, I>(
    key: K,
    group: G,
    ids: &[I],
) -> RedisFuture<usize>
```

**Retorno:** Número de IDs efetivamente reconhecidos.

---

## Histórico de Atualizações

| Data | Motivo | Mudanças |
| --- | --- | --- |
| 2026-06-10 | Plan `otimizacao-pools-observabilidade` | Adicionadas seções 3–7 (timeouts, conexão dedicada BLOCK, XPENDING/XCLAIM, DEL variádico, XREADGROUP/XACK). **Correção pós-validação no fonte vendorizado 0.25.5:** removidas APIs inexistentes nesta versão — `ConnectionManagerConfig`/`AsyncConnectionConfig` → `new_with_backoff_and_timeouts`; `xautoclaim`/`xautoclaim_options` → `xpending_count.times_delivered` + `xclaim`. (Context7 só indexa redis ≥1.0.) |
| 2026-05-31 | Inicial | Contexto, namespaces, publicação no Streams, debounce lock |
```
