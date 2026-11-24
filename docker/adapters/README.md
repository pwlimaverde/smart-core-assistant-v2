# Adapters Layer — Architecture Documentation

> **Status (2026-11-24): planejado, não implementado.** Não existe código, Dockerfile
> nem compose desta camada no repositório. A entrada de webhooks por gRPC descrita
> abaixo foi substituída pelo intermediário HTTP por provedor, em
> `smart-agent-config/doc_dev/arquitetura/adr-intermediario-webhooks-provedores.md`.

## Overview

The adapters layer is the **exclusive communication bridge** between external providers (Evolution, Telegram, WhatsApp Official, etc) and the Smart Core backend.

**Principle**: All communication flows through the adapter, never directly to the gateway.

```
Provider (Evolution, Telegram, etc)
         ↓↑
    Adapter (Rust)
         ↓↑ gRPC
      Gateway (Smart Core)
```

## Architecture

### Directory Structure

```
docker/adapters/
├─ README.md (this file)
├─ Dockerfile
├─ Cargo.toml
├─ src/
│  ├─ main.rs
│  ├─ http_server.rs
│  ├─ grpc_client.rs
│  ├─ grpc_server.rs
│  ├─ normalizer.rs
│  ├─ denormalizer.rs
│  └─ health.rs
├─ proto/
│  └─ adapter_gateway.proto
└─ compose.example.yml

docker/evolution/
├─ README.md
├─ compose.yml
├─ Dockerfile (if custom Evolution image)
└─ .env.example

docker/telegram/ (future)
docker/whatsapp/ (future)
docker/sms/ (future)
```

## Communication Protocol

### gRPC Services

Three main services:

#### 1. ReceiveInboundMessage (Unary)
- **Direction**: Adapter → Gateway
- **Purpose**: Send normalized event from provider
- **Payload**: InboundMessageRequest
- **Response**: InboundMessageResponse (processing_id)

#### 2. OutboundMessageStream (Bidirectional Stream)
- **Direction**: Gateway → Adapter (server push)
- **Purpose**: Send replies to be sent back to provider
- **Payload**: OutboundMessageResponse (stream)
- **Connection**: Always open, adapter listens continuously

#### 3. AcknowledgeOutbound (Unary)
- **Direction**: Adapter → Gateway
- **Purpose**: Confirm that message was sent to provider
- **Payload**: AcknowledgeRequest
- **Response**: AcknowledgeResponse

### Message Flow

```
INBOUND (Provider → Core)
Provider (WhatsApp)
    ↓ (native webhook)
Adapter HTTP:5000 (/webhook)
    ↓ (normalize)
Adapter gRPC:50053 (ReceiveInboundMessage)
    ↓ (gRPC)
Gateway gRPC:50053
    ↓ (validate, persist)
Core (business logic)

OUTBOUND (Core → Provider)
Gateway opens stream: OutboundMessageStream
    ↓ (continuous listening)
Adapter gRPC:50054 (receives via stream)
    ↓ (denormalize)
Adapter HTTP POST (send to provider API)
    ↓ (send)
Provider sends to WhatsApp/Telegram/etc
    ↓
Adapter gRPC (AcknowledgeOutbound)
    ↓ (confirm to Gateway)
Gateway persists receipt
```

## Implementation

### Adapter Structure (Pseudocode)

```rust
pub struct Adapter {
    // HTTP server (recebe webhooks do provider)
    http_server: HttpServer,
    
    // gRPC client (envia para gateway)
    gateway_client: WebhookGatewayClient,
    
    // gRPC server (recebe replies do gateway)
    grpc_server: GrpcServer,
    
    // Provider client (Evolution, Telegram, etc)
    provider_client: ProviderClient,
}

impl Adapter {
    // Recebe webhook do provider em HTTP
    async fn handle_webhook(&self, payload: String) {
        let event = parse_provider_payload(&payload);
        let inbound = self.normalize(&event);
        let response = self.gateway_client.receive_inbound_message(inbound).await;
        println!("Processing ID: {}", response.processing_id);
    }
    
    // Escuta respostas do gateway via gRPC stream
    async fn listen_outbound_stream(&self) {
        let mut stream = self.gateway_client.outbound_message_stream().await;
        while let Some(outbound) = stream.next().await {
            let denormalized = self.denormalize(&outbound);
            self.provider_client.send_message(&denormalized).await;
            self.gateway_client.acknowledge_outbound(ack).await;
        }
    }
}
```

## Deployment

### Docker Compose (Evolution Example)

```yaml
version: '3.9'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: evolution
      POSTGRES_PASSWORD: ${EVOLUTION_POSTGRES_PASSWORD}
    volumes:
      - evolution_postgres_data:/var/lib/postgresql/data
    networks:
      - evolution-internal
    mem_limit: 512m
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass ${EVOLUTION_REDIS_PASSWORD}
    volumes:
      - evolution_redis_data:/data
    networks:
      - evolution-internal
    mem_limit: 256m
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]

  evolution-go:
    image: evolution-api:v1.4.0
    environment:
      DATABASE_URL: postgres://evolution:${EVOLUTION_POSTGRES_PASSWORD}@postgres:5432/evolution
      REDIS_URL: redis://:${EVOLUTION_REDIS_PASSWORD}@redis:6379
      PORT: 3333
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - evolution-internal
    mem_limit: 2g
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3333/health"]

  adapter:
    image: smartcore-adapter-evolution:${IMAGE_TAG}
    environment:
      RUST_LOG: ${RUST_LOG:-info}
      EVOLUTION_API_URL: http://evolution-go:3333
      EVOLUTION_WEBHOOK_SECRET: ${EVOLUTION_WEBHOOK_SECRET}
      ADAPTER_PORT: 5000
      ADAPTER_GRPC_PORT: 50053
      SMARTCORE_GATEWAY_URL: grpc://${SMARTCORE_GATEWAY_HOST}:50053
      OTEL_EXPORTER_OTLP_ENDPOINT: http://${OBSERVABILITY_HOST}:4317
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      evolution-go:
        condition: service_started
    networks:
      - evolution-internal
    mem_limit: 512m
    ports:
      - "5000:5000"   # HTTP (webhooks)
      - "50053:50053" # gRPC server
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]

volumes:
  evolution_postgres_data:
  evolution_redis_data:

networks:
  evolution-internal:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/16
```

## Monitoring

### Prometheus Metrics

Each adapter exports:
- `adapter_inbound_messages_received_total` (counter)
- `adapter_outbound_messages_sent_total` (counter)
- `adapter_grpc_latency_ms` (histogram)
- `adapter_errors_total` (counter)

### Grafana Dashboards

Dashboard: `adapter_overview.json` shows:
- Messages in/out per minute
- Error rates
- Latency percentiles (p50, p99)
- Gateway connection status

## Extending to New Providers

### Add Telegram Adapter

```bash
cp -r docker/adapters docker/telegram-adapter

# Modify:
# 1. src/normalizer.rs → telegram_normalizer.rs
# 2. src/denormalizer.rs → telegram_denormalizer.rs
# 3. Add telegram_client.rs
# 4. Update docker-compose.yml

docker-compose -f docker/telegram-adapter/compose.yml up -d
```

### Protocol

Each new adapter follows the same gRPC protocol:
- Same `adapter_gateway.proto`
- Same `InboundMessageRequest` structure
- Same `OutboundMessageResponse` structure
- Only the normalizer/denormalizer changes

## Troubleshooting

### Adapter not connecting to Gateway

```bash
# Check connectivity
grpcurl -plaintext ${SMARTCORE_GATEWAY_HOST}:50053 list

# Check adapter logs
docker logs evolution-adapter

# Verify network
docker network ls | grep evolution-internal
```

### Messages not being delivered

```bash
# Check adapter healthcheck
curl http://localhost:5000/health

# Monitor metrics
curl http://prometheus:9090/api/v1/query?query=adapter_outbound_messages_sent_total

# Check provider API
curl http://evolution-go:3333/health
```

### High latency

Monitor:
- `adapter_grpc_latency_ms` (gRPC latency to gateway)
- Provider API latency
- Network latency between servers

---

**Last Updated**: 2026-11-18
