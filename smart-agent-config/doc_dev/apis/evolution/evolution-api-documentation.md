# Evolution API (Evolution Go) — Documentação REST Completa

## Visão Geral

**Evolution API** é um servidor WhatsApp multi-tenant open-source construído em **Go** (Evolution Go) ou **Node.js/TypeScript** (Evolution API tradicional). Fornece uma API REST pura para automação de WhatsApp com suporte a:

- Múltiplas conexões/instâncias simultâneas
- Webhooks em tempo real (WebSocket, HTTP, RabbitMQ, NATS, Apache Kafka, Amazon SQS)
- Autenticação baseada em API Key global + tokens por instância
- Gerenciamento completo de instâncias, mensagens, grupos, mídia
- Integração com plataformas: Typebot, Chatwoot, Dify, OpenAI, S3/MinIO

**Repositório oficial:** https://github.com/evolution-foundation/evolution-api  
**Licença:** Apache 2.0  
**Stack:** Node.js 20+, TypeScript 5+, Express.js (ou Go 1.24+ com Gin)

---

## Autenticação

Evolution API utiliza um modelo de autenticação **em dois níveis**:

### 1. Global Token (API Key)
- **Propósito:** Gerenciar instâncias (criar, deletar, listar)
- **Header:** `apikey: <YOUR_GLOBAL_API_KEY>`
- **Tipo:** String arbitrária configurada no `.env` ou dashboard
- **Operações:** POST /instance/create, DELETE /instance/delete/{name}, GET /instance/fetchInstances

### 2. Instance Token (Hash)
- **Propósito:** Enviar mensagens, configurar webhooks de uma instância específica
- **Retornado:** No campo `hash` da resposta de `/instance/create`
- **Header:** `apikey: <INSTANCE_TOKEN>` (mesmo header, valor diferente)
- **Operações:** POST /message/sendText/{name}, POST /webhook/set/{name}

### Importante: NUNCA misture os tokens!

**Exemplo de autenticação correta:**

```bash
# Criando instância (usa GLOBAL_TOKEN)
curl -X POST "http://api.local:3000/instance/create" \
  -H "Content-Type: application/json" \
  -H "apikey: seu_global_token_aqui" \
  -d '{
    "instanceName": "minha-instancia",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'

# Resposta inclui o instance token
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "instance": {
      "instanceName": "minha-instancia",
      "hash": "abc123def456xyz",  # <-- ESTE É O INSTANCE TOKEN
      "status": "connecting",
      ...
    }
  }
}

# Agora enviando mensagem (usa INSTANCE_TOKEN)
curl -X POST "http://api.local:3000/message/sendText/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: abc123def456xyz" \
  -d '{
    "number": "5511999999999",
    "text": "Olá, teste!"
  }'
```

---

## Endpoints Principais

### 1. POST /instance/create — Criar Instância

Cria uma nova instância de WhatsApp com opções de QR Code ou pairing por telefone.

**Método:** `POST`  
**URL:** `http://{server}:{port}/instance/create`  
**Headers obrigatórios:**
```
Content-Type: application/json
apikey: {GLOBAL_API_KEY}
```

**Body (JSON):**
```json
{
  "instanceName": "minha-instancia",
  "integration": "WHATSAPP-BAILEYS",
  "qrcode": true,
  "number": null,
  "settings": {
    "groupsIgnore": false,
    "presenceSubscriptions": true,
    "rejectCalls": false,
    "rejectCallMessage": null
  },
  "proxy": {
    "enabled": false,
    "host": null,
    "port": null,
    "username": null,
    "password": null
  },
  "webhookUrl": "https://seu-servidor.com/webhooks",
  "webhookByEvents": true,
  "events": [
    "MESSAGES_UPSERT",
    "CONNECTION_UPDATE",
    "QRCODE_UPDATED"
  ]
}
```

**Campos:**
- `instanceName` *(string, obrigatório):* Nome único da instância
- `integration` *(string):* Tipo de integração. Opções:
  - `WHATSAPP-BAILEYS` (padrão) — WhatsApp Web via Baileys
  - `WHATSAPP-BUSINESS` — WhatsApp Business API
  - `EVOLUTION` — Evolução integrada
- `qrcode` *(boolean):* Se `true`, retorna QR code na resposta para escanear
- `number` *(string):* Telefone no formato `55119999999999` (alternativa ao QR code)
- `settings` *(object):* Configurações opcionais (grupos, presença, rejeitar chamadas)
- `webhookUrl` *(string):* URL para receber eventos webhook
- `webhookByEvents` *(boolean):* Se `true`, cria URLs base para cada evento

**Resposta (201 Created):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "instance": {
      "instanceName": "minha-instancia",
      "hash": "abc123def456xyz",
      "status": "connecting",
      "qrCode": {
        "imageBase64": "data:image/png;base64,iVBORw0KGg...",
        "code": "2@...",
        "message": "Use o código acima para escanear"
      },
      "phoneConnected": false,
      "lastUpdate": "2026-06-20T10:30:00Z"
    }
  }
}
```

**cURL completo:**
```bash
curl -X POST "http://localhost:3000/instance/create" \
  -H "Content-Type: application/json" \
  -H "apikey: sua_global_api_key" \
  -d '{
    "instanceName": "bot-vendas",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'
```

---

### 2. GET /instance/connect/{instanceName} — Obter QR Code

Retorna o QR code atual de uma instância para escanear e conectar o WhatsApp.

**Método:** `GET`  
**URL:** `http://{server}:{port}/instance/connect/{instanceName}`  
**Query params:**
- `instanceName` *(path):* Nome da instância
- `number` *(opcional):* Se passado `?number=5511999999999`, retorna código de pareamento em vez de QR code

**Headers:**
```
apikey: {GLOBAL_API_KEY}
```

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "instanceName": "minha-instancia",
    "qrCode": {
      "imageBase64": "data:image/png;base64,iVBORw0KGg...",
      "code": "2@...",
      "timestamp": "2026-06-20T10:35:00Z"
    },
    "pairingCode": null
  }
}
```

**Alternativa com pairing code:**
```bash
# Obter código de pareamento por telefone (sem QR)
curl "http://localhost:3000/instance/connect/minha-instancia?number=5511999999999" \
  -H "apikey: seu_global_token"

# Resposta
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "pairingCode": "ABC-DEFG",
    "message": "Use este código no seu WhatsApp em Configurações > Aparelhos Vinculados"
  }
}
```

---

### 3. GET /instance/connectionState/{instanceName} — Verificar Estado de Conexão

Retorna o estado atual da conexão de uma instância.

**Método:** `GET`  
**URL:** `http://{server}:{port}/instance/connectionState/{instanceName}`  
**Headers:**
```
apikey: {GLOBAL_API_KEY}
```

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "instance": {
      "instanceName": "minha-instancia",
      "state": "open"
    }
  }
}
```

**Valores possíveis do `state`:**
- `open` — Conectado e pronto
- `close` — Desconectado
- `connecting` — Conectando (aguardando escanear QR ou aceitar pairing)

**cURL:**
```bash
curl "http://localhost:3000/instance/connectionState/minha-instancia" \
  -H "apikey: seu_global_token"
```

---

### 4. POST /instance/logout/{instanceName} — Fazer Logout

Desconecta uma instância (sem deletá-la).

**Método:** `POST`  
**URL:** `http://{server}:{port}/instance/logout/{instanceName}`  
**Headers:**
```
Content-Type: application/json
apikey: {GLOBAL_API_KEY}
```

**Body:** Vazio ou `{}`

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "message": "Instance logged out successfully"
  }
}
```

**cURL:**
```bash
curl -X POST "http://localhost:3000/instance/logout/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: seu_global_token"
```

---

### 5. DELETE /instance/delete/{instanceName} — Deletar Instância

Remove completamente uma instância.

**Método:** `DELETE`  
**URL:** `http://{server}:{port}/instance/delete/{instanceName}`  
**Headers:**
```
apikey: {GLOBAL_API_KEY}
```

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "message": "Instance deleted"
  }
}
```

**cURL:**
```bash
curl -X DELETE "http://localhost:3000/instance/delete/minha-instancia" \
  -H "apikey: seu_global_token"
```

---

### 6. GET /instance/fetchInstances — Listar Instâncias

Retorna todas as instâncias configuradas no servidor.

**Método:** `GET`  
**URL:** `http://{server}:{port}/instance/fetchInstances`  
**Headers:**
```
apikey: {GLOBAL_API_KEY}
```

**Query params (opcionais):**
- `page` *(number):* Página (padrão: 1)
- `offset` *(number):* Quantidade por página (padrão: 50)

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "instances": [
      {
        "instanceName": "minha-instancia",
        "hash": "abc123def456xyz",
        "status": "open",
        "phoneConnected": true,
        "qrCode": null,
        "profilePictureUrl": "https://...",
        "lastUpdate": "2026-06-20T10:40:00Z"
      },
      {
        "instanceName": "outra-instancia",
        "hash": "xyz789abc456def",
        "status": "close",
        "phoneConnected": false,
        "qrCode": { ... },
        "lastUpdate": "2026-06-20T09:15:00Z"
      }
    ],
    "pagination": {
      "page": 1,
      "total": 2,
      "totalPages": 1
    }
  }
}
```

**cURL:**
```bash
curl "http://localhost:3000/instance/fetchInstances?page=1&offset=50" \
  -H "apikey: seu_global_token"
```

---

### 7. POST /message/sendText/{instanceName} — Enviar Mensagem de Texto

Envia uma mensagem de texto para um contato ou grupo.

**Método:** `POST`  
**URL:** `http://{server}:{port}/message/sendText/{instanceName}`  
**Headers:**
```
Content-Type: application/json
apikey: {INSTANCE_TOKEN}
```

**Body (JSON):**
```json
{
  "number": "5511999999999",
  "text": "Olá! Esta é uma mensagem de teste.",
  "delay": 0,
  "linkPreview": true,
  "mentionsEveryOne": false,
  "mentioned": [],
  "quoted": null
}
```

**Campos:**
- `number` *(string, obrigatório):* Telefone em formato DDI: `5511999999999` ou JID: `5511999999999@s.whatsapp.net`
- `text` *(string, obrigatório):* Corpo da mensagem (suporta Markdown básico)
- `delay` *(number):* Atraso em ms antes de enviar (padrão: 0)
- `linkPreview` *(boolean):* Gerar preview de links (padrão: true)
- `mentionsEveryOne` *(boolean):* Mencionar todos em grupo (@todos)
- `mentioned` *(array):* Array de JIDs para mencionar: `["5511999999999@s.whatsapp.net"]`
- `quoted` *(object):* Objeto para responder a uma mensagem anterior

**Exemplo com quoted (resposta):**
```json
{
  "number": "5511999999999",
  "text": "Ótimo! Obrigado.",
  "quoted": {
    "key": {
      "id": "3EB0XXXXX",
      "fromMe": false,
      "remoteJid": "5511999999999@s.whatsapp.net"
    },
    "message": {
      "conversation": "Mensagem anterior"
    }
  }
}
```

**Resposta (201 Created):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "fromMe": true,
      "id": "3EB0ABC123DEF456"
    },
    "message": {
      "conversation": "Olá! Esta é uma mensagem de teste."
    },
    "messageTimestamp": 1718873400,
    "pushName": "Seu Bot"
  }
}
```

**cURL:**
```bash
curl -X POST "http://localhost:3000/message/sendText/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: abc123def456xyz" \
  -d '{
    "number": "5511999999999",
    "text": "Olá da Evolution API!"
  }'
```

---

### 8. POST /message/sendMedia/{instanceName} — Enviar Mídia (Imagem, Vídeo, Áudio, Documento)

Envia arquivos de mídia para um contato ou grupo. Suporta upload direto, URL remota ou base64.

**Método:** `POST`  
**URL:** `http://{server}:{port}/message/sendMedia/{instanceName}`  
**Headers:**
```
Content-Type: multipart/form-data
apikey: {INSTANCE_TOKEN}
```

**Form fields:**
```
number=5511999999999                           # Telefone obrigatório
mediatype=image                                # image, video, audio, document
caption=Descrição da imagem (opcional)
media=<arquivo ou URL ou base64>               # Conteúdo da mídia
mimetype=image/jpeg                            # MIME type do arquivo
fileName=foto.jpg                              # Nome do arquivo
delay=0                                        # Atraso em ms
```

**Métodos de envio de mídia:**

#### A) Upload de arquivo local:
```bash
curl -X POST "http://localhost:3000/message/sendMedia/minha-instancia" \
  -H "apikey: abc123def456xyz" \
  -F "number=5511999999999" \
  -F "mediatype=image" \
  -F "caption=Olá! Veja esta foto" \
  -F "media=@/caminho/para/foto.jpg" \
  -F "mimetype=image/jpeg"
```

#### B) Enviar por URL remota:
```bash
curl -X POST "http://localhost:3000/message/sendMedia/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: abc123def456xyz" \
  -d '{
    "number": "5511999999999",
    "mediatype": "image",
    "media": "https://exemplo.com/imagem.jpg",
    "caption": "Imagem de URL",
    "mimetype": "image/jpeg"
  }'
```

#### C) Enviar em base64 (para arquivos pequenos < 3MB):
```bash
curl -X POST "http://localhost:3000/message/sendMedia/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: abc123def456xyz" \
  -d '{
    "number": "5511999999999",
    "mediatype": "image",
    "media": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
    "caption": "Imagem em base64",
    "mimetype": "image/png"
  }'
```

**Tipos de mídia suportados:**
- `image` — JPEG, PNG, GIF, WebP
- `video` — MP4, 3GP (< 16MB recomendado; > 3MB usar URL)
- `audio` — MP3, OGG, M4A, WAV
- `document` — PDF, DOC, XLS, PPT, etc.

**Resposta (201 Created):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "fromMe": true,
      "id": "3EB0ABC123DEF456"
    },
    "message": {
      "imageMessage": {
        "url": "https://media-server.evolutionapi.com/...",
        "mimetype": "image/jpeg",
        "fileSize": 45678,
        "height": 800,
        "width": 600,
        "caption": "Olá! Veja esta foto",
        "jpegThumbnail": "...",
        "mediaKey": "...",
        "fileSha256": "..."
      }
    },
    "messageTimestamp": 1718873400
  }
}
```

**Importante para vídeos grandes:**
- Arquivos > 3MB: **use URL remota, não base64**
- Erro comum: "Maximum call stack size exceeded" → solução: enviar como URL
- Base64 deve estar **puro** (sem prefixo `data:image/jpeg;base64,`)

---

### 9. PUT /webhook/set/{instanceName} — Configurar Webhooks

Define a URL e eventos de webhook para uma instância.

**Método:** `PUT` ou `POST`  
**URL:** `http://{server}:{port}/webhook/set/{instanceName}`  
**Headers:**
```
Content-Type: application/json
apikey: {INSTANCE_TOKEN}
```

**Body (JSON):**
```json
{
  "enabled": true,
  "url": "https://seu-servidor.com/webhooks/evolution",
  "webhookByEvents": true,
  "webhookBase64": false,
  "events": [
    "MESSAGES_UPSERT",
    "CONNECTION_UPDATE",
    "QRCODE_UPDATED",
    "MESSAGES_UPDATE",
    "MESSAGES_DELETE",
    "SEND_MESSAGE"
  ],
  "headers": {
    "Authorization": "Bearer seu_token_secreto",
    "X-Custom-Header": "valor"
  }
}
```

**Campos:**
- `enabled` *(boolean):* Ativar/desativar webhooks
- `url` *(string):* URL do servidor que receberá os eventos
- `webhookByEvents` *(boolean):* Se `true`, cria URLs por evento: `{url}/MESSAGES_UPSERT`, `{url}/CONNECTION_UPDATE`, etc.
- `webhookBase64` *(boolean):* Se `true`, envia mídia em base64 nos payloads
- `events` *(array):* Lista de eventos a disparar
- `headers` *(object):* Headers customizados (autenticação, etc.)

**Eventos disponíveis:**
```
QRCODE_UPDATED      - Novo QR code gerado
MESSAGES_UPSERT     - Mensagem recebida ou enviada
MESSAGES_UPDATE     - Status de mensagem alterado (entregue, lida)
MESSAGES_DELETE     - Mensagem deletada
SEND_MESSAGE        - Mensagem enviada com sucesso
CONNECTION_UPDATE   - Mudança no estado de conexão
TYPEBOT_START       - Typebot iniciado (se integrado)
TYPEBOT_CHANGE_STATUS - Status do Typebot mudou
```

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "message": "Webhook configured successfully",
    "webhook": {
      "enabled": true,
      "url": "https://seu-servidor.com/webhooks/evolution",
      "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE", ...]
    }
  }
}
```

**cURL:**
```bash
curl -X PUT "http://localhost:3000/webhook/set/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: abc123def456xyz" \
  -d '{
    "enabled": true,
    "url": "https://seu-servidor.com/webhooks",
    "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]
  }'
```

---

### 10. POST /instance/pairingCode/{instanceName} — Gerar Código de Pareamento

Gera um código de pareamento para conectar via "Aparelhos Vinculados" do WhatsApp (alternativa ao QR code).

**Método:** `POST`  
**URL:** `http://{server}:{port}/instance/pairingCode/{instanceName}`  
**Headers:**
```
Content-Type: application/json
apikey: {GLOBAL_API_KEY}
```

**Body:**
```json
{
  "number": "5511999999999"
}
```

**Resposta (200 OK):**
```json
{
  "status": "SUCCESS",
  "error": false,
  "response": {
    "pairingCode": "ABC-DEFG",
    "expiresIn": 600,
    "message": "Use este código em Configurações > Aparelhos Vinculados do WhatsApp"
  }
}
```

**cURL:**
```bash
curl -X POST "http://localhost:3000/instance/pairingCode/minha-instancia" \
  -H "Content-Type: application/json" \
  -H "apikey: seu_global_token" \
  -d '{"number": "5511999999999"}'
```

---

## Webhooks — Eventos Recebidos

Quando um evento webhook é disparado, Evolution API envia um HTTP POST para a URL configurada com o seguinte formato:

### Estrutura Geral do Webhook

```json
{
  "event": "messages.upsert",
  "instance": "minha-instancia",
  "data": {
    "key": { ... },
    "message": { ... },
    "status": "PENDING"
  }
}
```

---

### MESSAGES_UPSERT — Mensagem Recebida ou Enviada

Disparado quando uma mensagem é recebida ou enviada pela instância.

```json
{
  "event": "messages.upsert",
  "instance": "minha-instancia",
  "data": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "id": "3EB0ABC123DEF456",
      "fromMe": false,
      "participant": null
    },
    "message": {
      "conversation": "Olá, tudo bem?"
    },
    "messageTimestamp": 1718873400,
    "pushName": "João Silva",
    "status": "PENDING"
  }
}
```

**Interpretação:**
- `fromMe: false` — Mensagem recebida de um contato
- `fromMe: true` — Mensagem enviada pela instância
- `conversation` — Texto simples
- `extendedTextMessage` — Texto com formatação, menções ou quoted

**Exemplo com mensagem complexa (com menções/quoted):**
```json
{
  "event": "messages.upsert",
  "instance": "minha-instancia",
  "data": {
    "key": {
      "remoteJid": "5511999999999-1234567890@g.us",
      "id": "3EB0ABC123DEF456",
      "fromMe": false,
      "participant": "5511888888888@s.whatsapp.net"
    },
    "message": {
      "extendedTextMessage": {
        "text": "Olá @bot como você está?",
        "contextInfo": {
          "mentionedJid": ["5511777777777@s.whatsapp.net"]
        }
      }
    },
    "messageTimestamp": 1718873400,
    "pushName": "João Silva",
    "status": "PENDING"
  }
}
```

---

### CONNECTION_UPDATE — Mudança de Status de Conexão

Disparado quando o estado da conexão muda (conectado, desconectado, conectando).

```json
{
  "event": "connection.update",
  "instance": "minha-instancia",
  "data": {
    "state": "open",
    "statusReason": 0,
    "lastDisconnect": null,
    "isNewLogin": false,
    "isChatsInitialized": true
  }
}
```

**Valores do `state`:**
- `open` — Conexão ativa
- `close` — Desconectado
- `connecting` — Conectando
- `legacy` — Sessão legada

**Exemplo ao desconectar:**
```json
{
  "event": "connection.update",
  "instance": "minha-instancia",
  "data": {
    "state": "close",
    "statusReason": 6,
    "lastDisconnect": {
      "output": null,
      "isExpected": false
    },
    "isNewLogin": false
  }
}
```

---

### QRCODE_UPDATED — Novo QR Code Gerado

Disparado quando um novo QR code é gerado (exemplo: após logout).

```json
{
  "event": "qrcode.update",
  "instance": "minha-instancia",
  "data": {
    "qrCode": {
      "imageBase64": "data:image/png;base64,iVBORw0KGg...",
      "code": "2@...",
      "timestamp": "2026-06-20T10:35:00Z"
    }
  }
}
```

---

### MESSAGES_UPDATE — Status de Mensagem Alterado

Disparado quando uma mensagem muda de status (entregue, lida, deletada).

```json
{
  "event": "messages.update",
  "instance": "minha-instancia",
  "data": [
    {
      "key": {
        "remoteJid": "5511999999999@s.whatsapp.net",
        "id": "3EB0ABC123DEF456",
        "fromMe": true,
        "participant": null
      },
      "status": "READ",
      "timestamp": 1718873450
    }
  ]
}
```

**Valores de status:**
- `PENDING` — Aguardando envio
- `SERVER` — Enviado para servidor
- `DELIVERED` — Entregue no dispositivo
- `READ` — Lida
- `PLAYED` — Reproduzida (áudio/vídeo)

---

## Tratamento de Erros

Evolution API retorna erros em formato JSON estruturado com status HTTP apropriado:

### 400 Bad Request — Parâmetro Inválido

```json
{
  "status": "BAD_REQUEST",
  "error": true,
  "response": {
    "message": [
      "number must be a valid phone number",
      "text must not be empty"
    ]
  }
}
```

**Causas comuns:**
- Número de telefone inválido (não no formato DDI)
- Mensagem vazia
- Campo obrigatório faltando
- Payload JSON malformado

---

### 401 Unauthorized — Token Inválido

```json
{
  "status": "UNAUTHORIZED",
  "error": true,
  "response": {
    "message": "Invalid API key or Instance token"
  }
}
```

**Causas comuns:**
- API key/token incorreto
- Usando global token onde precisa instância token (ou vice-versa)
- Token expirado

---

### 404 Not Found — Instância Não Existe

```json
{
  "status": "NOT_FOUND",
  "error": true,
  "response": {
    "message": "Instance 'minha-instancia' not found"
  }
}
```

**Causas comuns:**
- Nome da instância inválido
- Instância foi deletada
- URL malformada

---

### 500 Internal Server Error

```json
{
  "status": "INTERNAL_ERROR",
  "error": true,
  "response": {
    "message": "An unexpected error occurred"
  }
}
```

**Causa comum:**
- Problemas internos do servidor Evolution API (logs necessários para debug)

---

## Formatação de Telefone

**Formato obrigatório (DDI — Discagem Direta Internacional):**

```
5511999999999     # Brasil, São Paulo
5521988888888     # Brasil, Rio de Janeiro
5527987654321     # Brasil, outros estados
55999999999       # Formato curto (rejeita alguns casos)
```

**Estrutura:**
- Código do país (55 para Brasil)
- Código de área (2 dígitos)
- Número (8-9 dígitos)
- **Total: 13 dígitos (sem espaços, hífen, parênteses)**

**Formato alternativo (JID):**
```
5511999999999@s.whatsapp.net    # Contato individual
5511999999999-1234567890@g.us   # Grupo
```

---

## Integração Prática — Exemplo Completo em Rust

Aqui está um exemplo funcional para integração com Evolution API em Rust:

```rust
use reqwest;
use serde_json::{json, Value};

pub struct EvolutionAPI {
    base_url: String,
    global_token: String,
    instance_name: String,
    instance_token: Option<String>,
}

impl EvolutionAPI {
    pub fn new(
        base_url: String,
        global_token: String,
        instance_name: String,
    ) -> Self {
        Self {
            base_url,
            global_token,
            instance_name,
            instance_token: None,
        }
    }

    /// Criar instância com QR code
    pub async fn create_instance(&mut self) -> Result<String, Box<dyn std::error::Error>> {
        let url = format!("{}/instance/create", self.base_url);
        let payload = json!({
            "instanceName": self.instance_name,
            "integration": "WHATSAPP-BAILEYS",
            "qrcode": true
        });

        let client = reqwest::Client::new();
        let response = client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("apikey", &self.global_token)
            .json(&payload)
            .send()
            .await?;

        let body: Value = response.json().await?;
        
        // Extrair instance token
        if let Some(hash) = body["response"]["instance"]["hash"].as_str() {
            self.instance_token = Some(hash.to_string());
            
            // Extrair e retornar QR code base64
            if let Some(qr) = body["response"]["instance"]["qrCode"]["imageBase64"].as_str() {
                return Ok(qr.to_string());
            }
        }

        Err("Falha ao criar instância".into())
    }

    /// Verificar estado de conexão
    pub async fn check_connection_state(&self) -> Result<String, Box<dyn std::error::Error>> {
        let url = format!(
            "{}/instance/connectionState/{}",
            self.base_url, self.instance_name
        );

        let client = reqwest::Client::new();
        let response = client
            .get(&url)
            .header("apikey", &self.global_token)
            .send()
            .await?;

        let body: Value = response.json().await?;
        let state = body["response"]["instance"]["state"]
            .as_str()
            .unwrap_or("unknown");

        Ok(state.to_string())
    }

    /// Enviar mensagem de texto
    pub async fn send_text_message(
        &self,
        number: &str,
        text: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
        if self.instance_token.is_none() {
            return Err("Instance token não configurado".into());
        }

        let url = format!(
            "{}/message/sendText/{}",
            self.base_url, self.instance_name
        );

        let payload = json!({
            "number": number,
            "text": text,
            "delay": 0,
            "linkPreview": true
        });

        let client = reqwest::Client::new();
        let response = client
            .post(&url)
            .header("Content-Type", "application/json")
            .header("apikey", self.instance_token.as_ref().unwrap())
            .json(&payload)
            .send()
            .await?;

        let body: Value = response.json().await?;
        
        if let Some(msg_id) = body["response"]["key"]["id"].as_str() {
            Ok(msg_id.to_string())
        } else {
            Err("Falha ao enviar mensagem".into())
        }
    }

    /// Configurar webhook
    pub async fn setup_webhook(
        &self,
        webhook_url: &str,
        events: Vec<&str>,
    ) -> Result<(), Box<dyn std::error::Error>> {
        if self.instance_token.is_none() {
            return Err("Instance token não configurado".into());
        }

        let url = format!(
            "{}/webhook/set/{}",
            self.base_url, self.instance_name
        );

        let payload = json!({
            "enabled": true,
            "url": webhook_url,
            "webhookByEvents": true,
            "events": events
        });

        let client = reqwest::Client::new();
        let response = client
            .put(&url)
            .header("Content-Type", "application/json")
            .header("apikey", self.instance_token.as_ref().unwrap())
            .json(&payload)
            .send()
            .await?;

        if response.status().is_success() {
            Ok(())
        } else {
            Err("Falha ao configurar webhook".into())
        }
    }

    /// Processar webhook recebido
    pub fn parse_webhook_payload(payload: &Value) -> Option<(String, Value)> {
        let event = payload["event"].as_str()?;
        let data = payload["data"].clone();
        Some((event.to_string(), data))
    }
}

// Exemplo de uso
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut api = EvolutionAPI::new(
        "http://localhost:3000".to_string(),
        "sua_global_api_key".to_string(),
        "minha-instancia".to_string(),
    );

    // 1. Criar instância e obter QR code
    println!("Criando instância...");
    let qr_code = api.create_instance().await?;
    println!("QR Code (base64): {}", &qr_code[..50]); // Primeiros 50 chars

    // 2. Aguardar conexão
    std::thread::sleep(std::time::Duration::from_secs(5));
    
    // 3. Verificar estado
    let state = api.check_connection_state().await?;
    println!("Estado de conexão: {}", state);

    // 4. Configurar webhooks
    api.setup_webhook(
        "https://seu-servidor.com/webhooks",
        vec!["MESSAGES_UPSERT", "CONNECTION_UPDATE"],
    )
    .await?;
    println!("Webhooks configurados");

    // 5. Enviar mensagem (após conectado)
    if state == "open" {
        let msg_id = api.send_text_message(
            "5511999999999",
            "Olá da Evolution API em Rust!",
        )
        .await?;
        println!("Mensagem enviada: {}", msg_id);
    }

    Ok(())
}
```

---

## Referências e Recursos

- **Repositório oficial:** https://github.com/evolution-foundation/evolution-api
- **Documentação oficial:** https://docs.evolutionfoundation.com.br/
- **Manual de integração V2:** https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a
- **Postman Collections:**
  - [v2.2.2](https://www.postman.com/agenciadgcode/evolution-api/documentation/jn0bbzv/evolution-api-v2-2-2)
  - [v2.0](https://www.postman.com/agenciadgcode/evolution-api/documentation/gqr041s/evolution-api-v2-0)
- **Cliente Python:** https://github.com/EvolutionAPI/evolution-client-python
- **Evolution Go (versão em Go):** https://github.com/evolution-foundation/evolution-go
- **Documentação de autenticação:** https://docs.evolutionfoundation.com.br/api-reference/authentication
- **Webhook setup:** https://www.postman.com/agenciadgcode/evolution-api/request/jmbywky/set-webhook

---

## Dicas Práticas para Implementação

1. **Sempre teste primeiro com QR code** — Mais confiável que pairing code
2. **Use URLs para vídeos > 3MB** — Base64 vai dar "stack size exceeded"
3. **Polling de estado** — Aguarde conexão com GET /instance/connectionState antes de enviar mensagens
4. **Trate MESSAGES_UPSERT duplo** — Mensagens aparecem no webhook em "enviado" e "entregue" — deduplicar por ID
5. **Headers customizados** — Use `jwt_key` ou token no webhook para validar origem
6. **Instância por usuário** — Cada usuário = 1 instância (não compartilhe tokens)
7. **Erro 401** — Verifique qual token (global vs instance) está sendo usado
8. **Timeout para webhook** — Configure 180s para operações com média (uploads grandes)

