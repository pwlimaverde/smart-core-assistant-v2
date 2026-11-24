# Arquitetura Final — Adapters + gRPC (Comunicação Eficiente)

**Data**: 18 de Novembro de 2026  
**Status**: Planejamento — **não implementado**; a entrada de webhooks por gRPC foi substituída pelo intermediário HTTP por provedor (ver `smart-agent-config/doc_dev/arquitetura/adr-intermediario-webhooks-provedores.md`, 2026-11-24)  
**Versão**: 1.0

## Índice

1. [Visão Geral](#visão-geral)
2. [Princípios Fundamentais](#princípios-fundamentais)
3. [Topologia de Servidores](#topologia-de-servidores)
4. [Comunicação Bidirecional](#comunicação-bidirecional)
5. [Protocol Buffers](#protocol-buffers)
6. [Implementação do Adapter](#implementação-do-adapter)
7. [Deployment](#deployment)
8. [Roadmap de Crescimento](#roadmap-de-crescimento)

---

## Visão Geral

O sistema Smart Core Assistant v2 é composto por **3 servidores independentes** com comunicação eficiente via **gRPC**:

```
┌─────────────────────────────────────────────────────────────────┐
│ SERVIDOR 1: EVOLUTION ADAPTER (VPS/VM Dedicada)               │
│ ├─ Evolution GO (recebe WhatsApp)                              │
│ ├─ Postgres próprio                                            │
│ ├─ Redis próprio                                               │
│ └─ Adaptador Rust (normaliza/desnormaliza via gRPC)            │
│                                                                 │
│ SERVIDOR 2: SMART CORE CENTRAL (VPS Principal)                │
│ ├─ Backend Rust (core, gateway, worker, ia_engine)             │
│ ├─ Postgres (8 tenants)                                        │
│ ├─ Redis (cache + bus)                                         │
│ ├─ Gateway gRPC:50053 (recebe eventos via gRPC)                │
│ ├─ Frontend Caddy (home, admin, download)                      │
│ ├─ MCP Server (profile: mcp, desligado)                        │
│ └─ Windows Distributor (auto-update)                           │
│                                                                 │
│ SERVIDOR 3: OBSERVABILIDADE (VPS Separada)                    │
│ ├─ Prometheus (métricas)                                       │
│ ├─ Loki (logs)                                                 │
│ ├─ Tempo (traces)                                              │
│ ├─ Grafana (visualização)                                      │
│ ├─ Alloy (coleta)                                              │
│ └─ Docker-proxy (socket read-only)                             │
└─────────────────────────────────────────────────────────────────┘
```

**Total**: 22-23 containers por ambiente (dev + prod = 44-46)

---

## Princípios Fundamentais

### 1. **Isolamento Total**
- Cada servidor é independente
- Evolution cai? Core funciona
- Core cai? Adapter reconecta automaticamente
- Observabilidade cai? Logs vão para stderr

### 2. **Comunicação Exclusiva via Adapter**
```
Evolution → Adapter → Gateway (nunca direto)
Gateway → Adapter → Evolution (nunca direto)
```

### 3. **Stack Rust Consistente**
- Backend: Rust + Tokio
- Adapter: Rust + Tokio
- Comunicação: gRPC (Protocol Buffers)

### 4. **gRPC em vez de Webhooks**
- Webhooks = HTTP (overhead, polling)
- gRPC = Binary RPC (40x mais rápido, bidirecional)
- Stream bidirecional = Eficiência máxima

### 5. **Agnóstico a Provedor**
- Adaptador encapsula lógica de um provedor
- Sistema central não conhece detalhes do provedor
- Fácil adicionar Telegram, WhatsApp Official, SMS, etc

---

## Topologia de Servidores

### Servidor 1: Evolution Adapter

**Localização**: VPS Dedicada (ou co-hospedada inicialmente)  
**Recursos**:
- DEV: 2vCPU, 4GB RAM
- PROD: 4vCPU, 8GB RAM

**Containers**:
```yaml
1. postgres:15-alpine
   - DB: evolution (config, números, histórico)
   - Mem: 512 MB
   - Volume: evolution_postgres_data

2. redis:7-alpine
   - Cache/Buffer local
   - Mem: 256 MB
   - Volume: evolution_redis_data

3. evolution-go:latest
   - Recebe webhooks WhatsApp
   - Publica em Redis Streams
   - Mem: 2 GB (DEV) / 2-4 GB (PROD)
   - Ports: 3333 (HTTP, internal)

4. adapter-evolution:v1.0.0 (Rust)
   - Normaliza eventos de Evolution
   - gRPC client para gateway:50053
   - gRPC server:50054 (recebe replies)
   - HTTP server:5000 (webhooks de Evolution)
   - Mem: 512 MB
   - Restart: unless-stopped
```

**Redes**:
- Rede: evolution-internal (172.30.0.0/16)
- Gateway não consegue acessar (rede separada)
- Apenas adapter-evolution→gateway (outbound gRPC)

**Dados**:
- Backup: R2 `smartcore-evolution-backups/`
- Interval: Nightly
- Retenção: 30 dias

---

### Servidor 2: Smart Core Central

**Localização**: VPS Principal  
**Recursos**:
- DEV: 4vCPU, 8GB RAM
- PROD: 4vCPU, 16GB RAM (upgrade para 8vCPU/32GB em phase 2)

**Containers**:
```
DATABASE:
├─ postgres:17-alpine
│  ├─ DB: smartcore (8 tenants)
│  ├─ Mem: 1 GB (DEV) / 2 GB (PROD)
│  └─ Volume: postgres_data
│
└─ redis:7-alpine
   ├─ DB 0: app cache
   ├─ DB 1: message bus
   ├─ Mem: 512 MB
   └─ Volume: redis_data

BACKEND:
├─ core:v1.0.0 (Rust)
│  ├─ --target data,api,control
│  ├─ gRPC:50051
│  ├─ Mem: 512 MB
│  └─ UDS: /run/smartcore/core.sock
│
├─ gateway:v1.0.0 (Rust)
│  ├─ --target webhook_gateway
│  ├─ gRPC:50053 (server - recebe eventos)
│  ├─ Mem: 256 MB
│  └─ Restart: always (crítico)
│
├─ worker:v1.0.0 (Rust)
│  ├─ --target worker,media
│  ├─ CPU: 1.0
│  ├─ Mem: 1.5 GB
│  ├─ Ffmpeg para transcoding
│  └─ Restart: always
│
└─ ia_engine:v1.0.0 (Python)
   ├─ gRPC:50052
   ├─ Mem: 800 MB
   └─ Modelo: Claude Opus (via API)

FRONTEND:
├─ edge:latest (Caddy)
│  ├─ Porta: 80, 443
│  ├─ Serve: home, admin, download
│  ├─ Proxy: api.* → core:50051
│  ├─ Proxy: hooks.* → gateway:50053
│  ├─ Proxy: releases.* → windows-distributor:9000
│  └─ Mem: 256 MB
│
├─ windows-distributor:v1.0.0 (Rust)
│  ├─ Porta: 9000
│  ├─ Protocolo: Velopack
│  ├─ Mem: 256 MB
│  └─ Healthcheck: GET /health
│
└─ mcp_server:v1.0.0 (Rust)
   ├─ Profile: mcp (desligado por padrão)
   ├─ Porta: 3000
   ├─ Mem: 512 MB
   └─ Acesso: Claude AI + Developers (dev only)

OBSERVABILIDADE (Integrada ou Remota):
├─ prometheus:latest (512 MB)
├─ loki:latest (256 MB)
├─ tempo:latest (256 MB)
├─ grafana:latest (512 MB)
├─ alloy:latest (256 MB)
└─ docker-proxy:latest (64 MB)
```

**Redes**:
- Rede: smartcore-internal (172.20.0.0/16)
- Evolution não consegue acessar (rede separada)
- Apenas gateway:50053 escuta (inbound de adapter)

**Dados**:
- Postgres: 8 tenants reais
- Redis: Message bus persistido (AOF)
- Backup: Nightly + WAL contínuo (PROD)
- R2: `smartcore-prod-backups/`

---

### Servidor 3: Observabilidade (Opcional)

**Localização**: VPS Separada OU Local (Phase 2+)  
**Recursos**:
- 2vCPU, 4-8GB RAM

**Containers**:
```
├─ prometheus (1 GB)
├─ loki (1 GB)
├─ tempo (1 GB)
├─ grafana (512 MB)
├─ alloy (256 MB)
└─ docker-proxy (64 MB)
```

**Acesso**:
- OTLP:4317 (recebe de apps)
- Prometheus HTTP (scrapa de apps)
- Grafana UI (admin, alertas)

---

## Comunicação Bidirecional

### Fluxo de Entrada (Evolution → Core)

```
1. WhatsApp envia mensagem
   ↓
2. Evolution-GO recebe via HTTPS
   ↓ (Webhook nativo)
3. Adapter-Evolution:5000 (HTTP POST /webhook)
   ├─ Valida signature
   ├─ Normaliza payload
   └─ Extrai: origin, channel, contact, message
   ↓ (gRPC:50053)
4. Gateway recebe (ReceiveInboundMessage)
   ├─ Valida tenant_id
   ├─ Persiste em Postgres
   ├─ Publica em Redis Streams
   └─ Retorna: processing_id
   ↓
5. Worker consome Redis Streams
   ↓ (gRPC:50051)
6. Core processa
   ├─ Lógica de negócio
   ├─ Pode chamar IA Engine
   └─ Gera resposta
   ↓ (Publica em Redis Streams)
7. Pronto para enviar resposta
```

### Fluxo de Saída (Core → Evolution)

```
1. Gateway abre stream bidirecional (OutboundMessageStream)
   ├─ Adapter escuta continuamente
   └─ gRPC:50054 (server streaming)

2. Gateway publica resposta no stream
   ├─ processing_id (correlação com entrada)
   ├─ recipient_id (destinatário)
   ├─ message_content
   └─ metadata

3. Adapter recebe no stream
   ├─ Correlaciona com msg original
   ├─ Desnormaliza para formato Evolution
   └─ Monta payload nativo de Evolution

4. Adapter envia para Evolution
   ↓ (HTTP POST :3333/api/v1/send)
   
5. Evolution envia via WhatsApp
   ├─ Publica para cliente
   └─ Coleta delivery status

6. Adapter confirma ao Gateway
   ↓ (gRPC — AcknowledgeOutbound)
   ├─ processing_id
   ├─ success (true/false)
   └─ external_message_id (wamid.xxx)

7. Gateway persiste confirmação
```

### Diagrama UML (Sequência)

```
WhatsApp      Evolution     Adapter         Gateway       Worker
   │               │           │              │             │
   │─── msg ───→│               │              │             │
   │            │─ webhook ────→│              │             │
   │            │            │              │             │
   │            │            │─ gRPC ─────→│              │
   │            │            │   (inbound) │              │
   │            │            │←─ response ─│              │
   │            │            │             │─ stream ────→│
   │            │            │             │              │
   │            │            │←─ gRPC stream reply ────────│
   │            │            │   (outbound)              │
   │            │            │              │             │
   │            │←─ send ────│              │             │
   │            │            │              │             │
   │←─ reply ──│            │              │             │
   │           │            │─ ack ──────→│              │
   │           │            │  (gRPC)     │              │
```

---

## Protocol Buffers

### protos/adapter_gateway.proto

Ver arquivo separado: `docker/adapters/protos/adapter_gateway.proto`

**Serviços**:
- `ReceiveInboundMessage()` → Adapter envia evento
- `OutboundMessageStream()` → Gateway envia replies (stream)
- `AcknowledgeOutbound()` → Adapter confirma envio

---

## Implementação do Adapter

### Linguagem: Rust + Tokio

**Crate**: `smartcore-adapter-evolution`

**Dependências**:
```toml
[dependencies]
tokio = { version = "1.35", features = ["full"] }
tonic = "0.11"
prost = "0.12"
axum = "0.7"
hyper = "1.1"
serde_json = "1.0"
tracing = "0.1"
tracing-subscriber = "0.3"
```

**Estrutura de Código**:
```
smartcore-adapter-evolution/
├─ src/
│  ├─ main.rs (entry point)
│  ├─ http_server.rs (recebe webhooks de Evolution)
│  ├─ grpc_client.rs (envia para Gateway)
│  ├─ grpc_server.rs (escuta replies)
│  ├─ normalizer.rs (Evolution → padrão)
│  ├─ denormalizer.rs (padrão → Evolution)
│  ├─ evolution_client.rs (HTTP client para Evolution API)
│  └─ health.rs (healthcheck)
│
├─ proto/
│  └─ adapter_gateway.proto
│
└─ Dockerfile
```

**Healthcheck**:
- HTTP: `GET localhost:5000/health`
- Status: `{ status, connected_to_gateway, connected_to_evolution }`

---

## Deployment

### DEV Environment

```bash
# 1. Criar env files
cat > /opt/smartcore/dev/env/smartcore.env << EOF
DATABASE_URL=postgres://smartcore:dev_pass@postgres:5432/smartcore
REDIS_PASSWORD=dev_redis_pass
POSTGRES_PASSWORD=dev_postgres_pass
IMAGE_TAG=dev-latest
RUST_LOG=debug
ANTHROPIC_API_KEY=sk-...
OBSERVABILITY_HOST=observability.dev.internal
GF_SECURITY_ADMIN_PASSWORD=dev_admin_pass
EOF

cat > /opt/smartcore/dev/env/evolution.env << EOF
EVOLUTION_POSTGRES_PASSWORD=evolution_dev_pass
EVOLUTION_REDIS_PASSWORD=evolution_dev_redis
EVOLUTION_WEBHOOK_SECRET=webhook_secret_dev
EVOLUTION_INSTANCES=2
SMARTCORE_GATEWAY_HOST=smartcore.dev.internal
SMARTCORE_GATEWAY_PORT=50053
OBSERVABILITY_HOST=observability.dev.internal
IMAGE_TAG=dev-latest
RUST_LOG=debug
EOF

# 2. Start Stack (ordem importante)
cd docker
docker compose --env-file /opt/smartcore/dev/env/smartcore.env up -d

# Aguardar postgres, redis, core saudáveis
docker compose logs core | grep "healthy"

# 3. Start Evolution (outro terminal ou server)
cd docker/evolution
docker compose --env-file /opt/smartcore/dev/env/evolution.env up -d

# Aguardar adapter conectar
docker compose logs adapter | grep "connected to gateway"

# 4. Validar
grpcurl -plaintext localhost:50053 list
curl http://localhost:5000/health
```

### PROD Environment

Similar ao DEV, mas com credenciais reais e recursos maiores.

---

## Roadmap de Crescimento

### Fase 1 (Hoje — 8 clientes)
- ✅ Servidor Evolution (pode ser co-hospedado)
- ✅ Servidor Smart Core (principal)
- ✅ Observabilidade (integrada ou remota)
- 📊 Total: 2-3 servidores, 32 GB RAM

### Fase 2 (50 clientes, 10k+ msgs/dia)
- ✅ Servidor Evolution (separado em VPS 4vCPU, 8GB)
- ✅ Servidor Smart Core (upgrade 8vCPU, 32GB)
- ✅ Servidor Observabilidade (separado)
- ✅ Worker réplicas (CPU-bound separado)
- ✅ Adapters adicionais (Telegram, WhatsApp Official)
- 📊 Total: 4+ servidores, 100+ GB RAM

### Fase 3 (100+ clientes)
- ✅ Postgres gerenciado (Neon, Supabase)
- ✅ Redis gerenciado (Upstash)
- ✅ Gateway+Core réplicas com load balancer
- ✅ Adapters distribuídos (cada um em seu servidor)
- ✅ Kubernetes (ou similar)
- 📊 Total: 10+ servidores distribuídos

---

## Checklist Final

- ✅ Isolamento total entre servidores
- ✅ Comunicação exclusiva via adapter
- ✅ gRPC bidirecional (eficiência)
- ✅ Stack Rust consistente
- ✅ Agnóstico a provedor
- ✅ Tolerância a falhas
- ✅ Escalabilidade horizontal
- ✅ Observabilidade separada
- ✅ Dev e Prod espelhados
- ✅ Pronto para produção

---

**Data**: 18 de Novembro de 2026  
**Versão**: 1.0 (Final)
