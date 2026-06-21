# Evolution API — Setup Local (Docker)

Guia para rodar Evolution API localmente em desenvolvimento.

---

## Pré-requisitos

- Docker e Docker Compose
- Node.js 20+ (se rodar sem Docker)
- PostgreSQL (ou usar Docker)
- Redis (opcional, para fila de mensagens)

---

## Setup com Docker Compose (Recomendado)

### 1. Criar arquivo `docker-compose.yml`

```yaml
version: '3.8'

services:
  # Evolution API — Node.js/TypeScript
  evolution-api:
    image: evoapicloud/evolution-api:latest
    container_name: evolution-api
    environment:
      - SERVER_PORT=3000
      - SERVER_ENVIRONMENT=development
      - LOG_LEVEL=info
      
      # Database
      - DATABASE_CONNECTION_DB_HOST=postgres
      - DATABASE_CONNECTION_DB_PORT=5432
      - DATABASE_CONNECTION_DB_USER=evolution
      - DATABASE_CONNECTION_DB_PASSWORD=REDACTED_PGPASS
      - DATABASE_CONNECTION_DB_NAME=evolution_db
      - DATABASE_CONNECTION_DIALECT=postgres
      
      # Redis (opcional)
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      
      # API Keys
      - AUTHENTICATION_API_KEY=sua_global_api_key_aqui
      - AUTHENTICATION_JWT_SECRET=seu_jwt_secret_aqui
      
      # Webhook
      - WEBHOOK_DRIVER=http
      - WEBHOOK_URL=${WEBHOOK_BASE_URL:-http://localhost:3001/webhook}
      
      # CORS
      - CORS_ORIGIN=*
      
      # Manager UI
      - SERVER_ENABLE_DOCS=true
      
    ports:
      - "3000:3000"      # API
      - "3001:3001"      # Docs/Swagger
      
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
        
    volumes:
      # Persistir dados de instâncias
      - evolution-data:/home/node/app/instances
      
    networks:
      - evolution-network
      
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3

  # PostgreSQL
  postgres:
    image: postgres:15-alpine
    container_name: evolution-postgres
    environment:
      - POSTGRES_USER=evolution
      - POSTGRES_PASSWORD=REDACTED_PGPASS
      - POSTGRES_DB=evolution_db
      
    ports:
      - "5432:5432"
      
    volumes:
      - postgres-data:/var/lib/postgresql/data
      
    networks:
      - evolution-network
      
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U evolution"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis (para fila/cache)
  redis:
    image: redis:7-alpine
    container_name: evolution-redis
    command: redis-server --appendonly yes
    
    ports:
      - "6379:6379"
      
    volumes:
      - redis-data:/data
      
    networks:
      - evolution-network
      
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-data:
  redis-data:
  evolution-data:

networks:
  evolution-network:
    driver: bridge
```

### 2. Variáveis de ambiente (`.env`)

Criar arquivo `.env` na mesma pasta:

```env
# Evolution API
EVOLUTION_API_KEY=sua_global_api_key_muito_secreta_123456
EVOLUTION_JWT_SECRET=seu_jwt_secret_muito_secreto_abcdef

# Webhook (seu servidor)
WEBHOOK_BASE_URL=http://localhost:3001/webhook
# Em produção: https://seu-servidor.com/webhook

# Database
DB_HOST=localhost
DB_PORT=5432
DB_USER=evolution
DB_PASSWORD=REDACTED_PGPASS
DB_NAME=evolution_db

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# Node
NODE_ENV=development
```

### 3. Levantar os containers

```bash
# Navegar até pasta com docker-compose.yml
cd docker-setup/evolution

# Levantar containers
docker-compose up -d

# Verificar logs
docker-compose logs -f evolution-api

# Verificar se está saudável
docker-compose ps

# Expected output:
# NAME              COMMAND                  STATE           PORTS
# evolution-api     "docker-entrypoint.…"   Up (healthy)    0.0.0.0:3000->3000/tcp
# evolution-postgres "postgres"               Up (healthy)    0.0.0.0:5432->5432/tcp
# evolution-redis   "redis-server …"        Up (healthy)    0.0.0.0:6379->6379/tcp
```

### 4. Verificar API

```bash
# Health check
curl http://localhost:3000/

# Listar instâncias (vai estar vazio)
curl http://localhost:3000/instance/fetchInstances \
  -H "apikey: sua_global_api_key_muito_secreta_123456"

# Swagger/Docs UI
# Abrir: http://localhost:3001/api-docs
```

---

## Setup sem Docker (Node.js local)

### 1. Clonar repositório

```bash
git clone https://github.com/evolution-foundation/evolution-api.git
cd evolution-api
```

### 2. Instalar dependências

```bash
npm install
```

### 3. Configurar ambiente

Copiar `.env.example` e editar:

```bash
cp .env.example .env
```

Editar `.env`:

```env
SERVER_PORT=3000
SERVER_ENVIRONMENT=development
NODE_ENV=development

# Database
DATABASE_CONNECTION_DB_HOST=localhost
DATABASE_CONNECTION_DB_PORT=5432
DATABASE_CONNECTION_DB_USER=postgres
DATABASE_CONNECTION_DB_PASSWORD=postgres
DATABASE_CONNECTION_DB_NAME=evolution_db
DATABASE_CONNECTION_DIALECT=postgres

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# API
AUTHENTICATION_API_KEY=sua_global_api_key
AUTHENTICATION_JWT_SECRET=seu_jwt_secret

# Logs
LOG_LEVEL=info

# Manager UI
SERVER_ENABLE_DOCS=true
```

### 4. Setup do banco

```bash
# Criar banco PostgreSQL (assumindo servidor rodando)
createdb -U postgres evolution_db

# Migrations
npm run db:deploy
```

### 5. Rodar servidor

```bash
# Development
npm run dev:server

# Production
npm run build:server
npm run start:server
```

Servidor estará disponível em `http://localhost:3000`

---

## Testando Localmente

### 1. Criar instância (Get QR Code)

```bash
# Salvar global API key
API_KEY="sua_global_api_key_muito_secreta_123456"

# Criar instância
curl -X POST http://localhost:3000/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: $API_KEY" \
  -d '{
    "instanceName": "test-bot",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'

# Salvar o hash (instance token) da resposta
# {"response": {"instance": {"hash": "abc123def456...", ...}}}
INSTANCE_TOKEN="abc123def456..."
```

### 2. Obter QR Code novamente

```bash
# Se perdeu, recuperar QR
curl http://localhost:3000/instance/connect/test-bot \
  -H "apikey: $API_KEY"

# Salvar imagem base64
# {"response": {"qrCode": {"imageBase64": "data:image/png;base64,..."}}}
```

### 3. Escanear QR no WhatsApp

- Abrir WhatsApp no celular
- Configurações → Aparelhos Vinculados → Conectar aparelho
- Escanear QR code do terminal

### 4. Verificar conexão

```bash
# Fazer polling até conectar
for i in {1..30}; do
  curl -s http://localhost:3000/instance/connectionState/test-bot \
    -H "apikey: $API_KEY" | jq .response.instance.state
  echo "Tentativa $i/30..."
  sleep 2
done

# Expected output após escanear: "open"
```

### 5. Enviar primeira mensagem

```bash
# Após state == "open"
curl -X POST http://localhost:3000/message/sendText/test-bot \
  -H "Content-Type: application/json" \
  -H "apikey: $INSTANCE_TOKEN" \
  -d '{
    "number": "5511999999999",
    "text": "Olá! Primeira mensagem da Evolution API"
  }'

# Response:
# {"response": {"key": {"id": "3EB0ABC123DEF456", ...}}}
```

---

## Configurar Webhooks Localmente

### Opção A: Com ngrok (para testar webhook em local)

```bash
# Instalar ngrok: https://ngrok.com/download

# Terminal 1: Rodar seu servidor webhook (Rust/Axum)
cargo run --bin webhook-server  # porta 3001

# Terminal 2: Expor localmente via ngrok
ngrok http 3001
# Output: https://abc123.ngrok.io

# Agora configurar webhook na Evolution
curl -X PUT http://localhost:3000/webhook/set/test-bot \
  -H "Content-Type: application/json" \
  -H "apikey: $INSTANCE_TOKEN" \
  -d '{
    "enabled": true,
    "url": "https://abc123.ngrok.io/webhook",
    "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]
  }'

# Testar: Receber mensagem no WhatsApp
# Deve ver POST em http://localhost:3001/webhook
```

### Opção B: Usando socat (redirecionar porta local)

```bash
# Em produção ou em rede interna:
# Configurar webhook para http://localhost:3001/webhook
# não funciona se Evolution está em outro container

# Verificar IP da máquina host:
ipconfig getifaddr en0  # macOS
# ou
hostname -I  # Linux

# Usar esse IP ao configurar webhook
curl -X PUT http://localhost:3000/webhook/set/test-bot \
  -H "Content-Type: application/json" \
  -H "apikey: $INSTANCE_TOKEN" \
  -d '{
    "enabled": true,
    "url": "http://192.168.1.100:3001/webhook",
    "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]
  }'
```

---

## Debugging

### Ver logs da Evolution

```bash
# Se estiver no Docker
docker-compose logs -f evolution-api

# Se estiver rodando localmente
npm run dev:server

# Buscar erros específicos
docker-compose logs evolution-api | grep -i error
```

### Verificar conexão com banco

```bash
# Entrar no container postgres
docker exec -it evolution-postgres psql -U evolution -d evolution_db

# Listar tabelas
\dt

# Query instâncias
SELECT * FROM instances;

# Sair
\q
```

### Verificar Redis

```bash
# Entrar no container redis
docker exec -it evolution-redis redis-cli

# Ver todas as chaves
KEYS *

# Sair
exit
```

### Health checks

```bash
# Evolution API
curl -v http://localhost:3000/ 2>&1 | grep -E "^< HTTP"

# PostgreSQL
docker exec evolution-postgres pg_isready -U evolution

# Redis
docker exec evolution-redis redis-cli ping
```

---

## Limpar e Resetar

### Limpar tudo (⚠️ perderá dados)

```bash
# Parar e remover containers
docker-compose down

# Remover volumes (dados persistidos)
docker-compose down -v

# Remover imagens
docker-compose down --rmi all

# Recomeçar
docker-compose up -d
```

### Resetar só Evolution (manter PostgreSQL)

```bash
# Parar Evolution
docker-compose stop evolution-api

# Remover container
docker-compose rm -f evolution-api

# Remover volume de instâncias
docker volume rm evolution-data

# Recomeçar
docker-compose up -d evolution-api
```

### Rescan QR code (reconectar WhatsApp)

```bash
# Fazer logout
curl -X POST http://localhost:3000/instance/logout/test-bot \
  -H "apikey: $API_KEY"

# Obter novo QR
curl http://localhost:3000/instance/connect/test-bot \
  -H "apikey: $API_KEY" | jq .response.qrCode.imageBase64

# Escanear novamente
```

---

## Variáveis de Ambiente Importantes

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `SERVER_PORT` | 3000 | Porta HTTP |
| `AUTHENTICATION_API_KEY` | — | Global API key (OBRIGATÓRIO) |
| `DATABASE_CONNECTION_DB_HOST` | localhost | Host PostgreSQL |
| `DATABASE_CONNECTION_DB_NAME` | evolution_db | Nome do banco |
| `REDIS_HOST` | localhost | Host Redis (opcional) |
| `LOG_LEVEL` | info | Nível de log (debug, info, warn, error) |
| `SERVER_ENABLE_DOCS` | true | Ativar Swagger UI |
| `CORS_ORIGIN` | * | CORS (não usar * em prod!) |

---

## Troubleshooting Local

### "Connection refused" ao conectar no PostgreSQL

```bash
# Verificar se postgres está rodando
docker ps | grep postgres

# Se não estiver, iniciar
docker-compose up -d postgres

# Aguardar health check passar
docker-compose ps
```

### "Cannot find module" no npm start

```bash
# Limpar cache
rm -rf node_modules package-lock.json

# Reinstalar
npm install

# Build
npm run build:server

# Rodar
npm start
```

### "Port 3000 already in use"

```bash
# Encontrar processo usando porta 3000
lsof -i :3000  # macOS/Linux
netstat -ano | findstr :3000  # Windows

# Matar processo (substituir PID)
kill -9 <PID>  # macOS/Linux
taskkill /PID <PID> /F  # Windows

# Ou mudar porta no .env
SERVER_PORT=3001
```

### Webhook nunca é chamado

```bash
# Verificar se está configurado
curl http://localhost:3000/instance/connectionState/test-bot \
  -H "apikey: $API_KEY"
# state deve ser "open"

# Verificar se webhook está ativado
# (seria bom ter endpoint GET /webhook/get para isso)

# Testar recebendo mensagem
# Se não chegar, logs da Evolution:
docker-compose logs evolution-api | grep webhook
```

---

## Performance e Otimização (Local)

### Aumentar performance de polling

```bash
# Se usar muito polling, considerar usar server-sent events (SSE)
# ou WebSocket quando disponível na Evolution

# Por enquanto, máximo recomendado é 1 request a cada 2s
```

### Memory usage

```bash
# Ver uso de memória
docker stats

# Se Evolution consumir muito:
# - Verificar número de instâncias ativas
# - Revisar webhooks (podem estar acumulando)
# - Restart container
```

---

## Próximo Passo

Uma vez testado localmente:

1. Seguir **evolution-api-implementation-guide.md** para implementar em Rust
2. Configurar webhooks de verdade
3. Adicionar ao seu pipeline Docker de produção

