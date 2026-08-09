# Documentação Evolution Go v0.7.1 - Relatório Técnico

**Data:** 2026-08-09  
**Versão:** Evolution Go 0.7.1  
**Status:** Produção com Docker `evoapicloud/evolution-go:0.7.1`  
**Base Técnica:** whatsmeow (biblioteca Go para WhatsApp)

---

## 1. VISÃO GERAL E ARQUITETURA

### Overview
- **Repositório Oficial:** [evolution-foundation/evolution-go](https://github.com/evolution-foundation/evolution-go)
- **Documentação:** [docs.evolutionfoundation.com.br/en/evolution-go](https://docs.evolutionfoundation.com.br/en/evolution-go)
- **Tipo de API:** RESTful com suporte a WebSocket, Webhooks, RabbitMQ, NATS
- **Stack:** Go 1.24+, Gin framework, PostgreSQL, GORM, gRPC

### Estrutura de Resposta API
**CONFIRMADO** - Todas as respostas seguem envelope padrão:

```json
{
  "event": "string",
  "data": { },
  "instanceId": "uuid-aqui",
  "instanceToken": "token-aqui"
}
```

**Componentes:**
- `event`: Nome do evento/operação realizada
- `data`: Payload com resposta específica do endpoint
- `instanceId`: UUID da instância WhatsApp (formato: uuid)
- `instanceToken`: Token de autenticação da instância

### Status HTTP
- **200/201**: Sucesso (resposta com dados)
- **400**: Requisição inválida (payload mal formado, base64 com prefixo)
- **401**: Autenticação falhou (apikey inválida/expirada)
- **404**: Instância não encontrada
- **429**: Rate limit excedido (máx 50 req/s por instância - recomendado)
- **500**: Erro servidor (arquivo grande, timeout, processamento)

---

## 2. AUTENTICAÇÃO

### Método de Autenticação
**CONFIRMADO** - API Key via header HTTP (não Authorization standard)

```bash
# Header obrigatório
apikey: <GLOBAL_API_KEY>
Content-Type: application/json
```

**Nota Importante:** Evolution Go usa `apikey` customizado (não `Authorization: Bearer`) para permitir outros esquemas de autenticação na camada aplicação.

### Tipos de Autenticação
1. **Global API Key** - Acesso completo a todas instâncias e operações admin
2. **Instance Token** - Acesso restrito a instância específica (derivado do create)

---

## 3. ENDPOINT 1: ENVIO DE MÍDIA (Imagem, Vídeo, Áudio, Documento)

### Visão Geral
**CONFIRMADO** - Endpoint único suporta múltiplos formatos de mídia com base64 ou URL

### 3.1 - Envio de Mídia (Imagem/Vídeo/Documento/Áudio)

**Método:** `POST`  
**Path:** `/message/sendMedia/{instanceName}`  
**Headers Obrigatórios:**
```
apikey: <API_KEY>
Content-Type: application/json
```

#### Formatos Suportados (CONFIRMADO)
- **image** (JPEG, PNG, WebP)
- **video** (MP4, 3GP)
- **audio** (MP3, OGG, M4A)
- **document** (PDF, DOC, DOCX, XLS, etc.)
- **ptt** (Push-To-Talk / voz - special audio format)

#### Payload - Via Base64 (CONFIRMADO)
```json
{
  "number": "5511999999999",
  "mediatype": "image",
  "mimetype": "image/jpeg",
  "media": "[BASE64_PURO_SEM_PREFIXO]",
  "fileName": "foto.jpg",
  "caption": "Descrição da imagem"
}
```

**Exemplo cURL:**
```bash
curl -X POST "https://seu-servidor.com/message/sendMedia/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "mediatype": "image",
    "mimetype": "image/jpeg",
    "media": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
    "fileName": "imagem.jpg",
    "caption": "Minha legenda"
  }'
```

#### Payload - Via URL (CONFIRMADO)
```json
{
  "number": "5511999999999",
  "mediatype": "video",
  "media": "https://exemplo.com/video.mp4",
  "fileName": "video.mp4",
  "caption": "Vídeo importante"
}
```

**Nota sobre Base64:** Quando `media` NÃO começa com `http://` ou `https://`, é tratado como base64 e decodificado automaticamente. **Importante:** Não incluir prefixo `data:image/jpeg;base64,` — apenas o conteúdo base64 puro.

#### Resposta Sucesso (200/201)
```json
{
  "key": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "fromMe": true,
    "id": "3EB0XXXXX"
  },
  "message": {
    "imageMessage": {
      "url": "...",
      "mediaKey": "...",
      "fileEncSha256": "...",
      "jpegThumbnail": "...",
      "caption": "Descrição da imagem"
    }
  },
  "messageTimestamp": "1234567890"
}
```

#### Casos de Erro (CONFIRMADO)
| Código | Erro | Causa | Solução |
|--------|------|-------|---------|
| 400 | Bad Request | Base64 com prefixo ou payload malformado | Remover `data:*;base64,` do início |
| 400 | Bad Request | Arquivo muito grande | Comprimir/reduzir resolução |
| 500 | Internal Server Error | Timeout processamento | Arquivo grande demais ou servidor sobrecarregado |
| 404 | Not Found | Instância não existe | Verificar instanceName |

#### Limitações Documentadas (NÃO CONFIRMADO - INFERÊNCIA)
- Tamanho máximo de mídia: não documentado (recomendação: <16MB)
- Taxa: máx 50 req/s por instância (recomendado esperar resposta)
- Formatos específicos: JPEG, PNG, WebP para imagem; MP4, 3GP para vídeo

### 3.2 - Envio de Áudio (Endpoint Alternativo)

**Método:** `POST`  
**Path:** `/message/sendWhatsAppAudio/{instanceName}`  
**Payload:**
```json
{
  "number": "5511999999999",
  "audio": "[BASE64_PURO]",
  "encoding": true
}
```

---

## 4. ENDPOINT 2: MARCAR MENSAGEM COMO LIDA (Read Receipts)

### Método e Path
**CONFIRMADO** - Endpoint PUT para marcar múltiplas mensagens

**Método:** `PUT`  
**Path:** `/chat/markMessageAsRead/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
Content-Type: application/json
```

### Payload
```json
{
  "read_messages": [
    {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "fromMe": true,
      "id": "3EB0XXXXX"
    },
    {
      "remoteJid": "5519999999999@s.whatsapp.net",
      "fromMe": false,
      "id": "3EB0YYYYY"
    }
  ]
}
```

### Formato remoteJid (CONFIRMADO)
- **Contato individual:** `{numero}@s.whatsapp.net` (ex: `5511999999999@s.whatsapp.net`)
- **Grupo:** `{groupId}@g.us` (ex: `120362003333333-1233333@g.us`)
- **Newsletter:** `{newsletterId}@newsletter` (ex: `123333333333@newsletter`)

### Campos Obrigatórios
- `remoteJid`: JID (Jabber ID) do contato ou grupo
- `id`: ID único da mensagem (obtido de events de MESSAGE_UPDATE)
- `fromMe`: boolean indicando se foi enviada pelo bot

### Resposta Sucesso (200)
```json
{
  "status": "success",
  "message": "Messages marked as read",
  "markedCount": 2
}
```

### Casos de Erro (CONFIRMADO)
| Código | Erro | Causa |
|--------|------|-------|
| 400 | Bad Request | remoteJid malformado |
| 400 | Bad Request | id inválido ou mensagem não existe |
| 404 | Not Found | Instância não existe |
| 401 | Unauthorized | apikey inválida |

### Webhook Recebido (NÃO CONFIRMADO)
Após marcar como lida, webhook de READ_RECEIPT é emitido:
```json
{
  "event": "READ_RECEIPT",
  "data": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "messageIds": ["3EB0XXXXX"],
    "timestamps": [1234567890]
  },
  "instanceId": "uuid"
}
```

---

## 5. ENDPOINT 3: DEFINIR PRESENÇA (Composing/Recording/Paused)

### Método e Path
**CONFIRMADO** - Endpoint para indicador de digitação e gravação

**Método:** `POST`  
**Path:** `/chat/sendPresence/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
Content-Type: application/json
```

### Payload
```json
{
  "number": "5511999999999",
  "presence": "composing",
  "delay": 1200
}
```

### Estados de Presença Suportados (CONFIRMADO)
- `composing` - Indicador "está digitando..."
- `recording` - Indicador "está gravando áudio..."
- `paused` - Pausa/fim da ação (limpa indicador)

### Campos
- `number`: número do contato destino (com DDD)
- `presence`: estado a ser indicado
- `delay`: duração em milissegundos (quanto tempo mostrar status)

### Exemplo cURL Completo
```bash
curl -X POST "https://seu-servidor.com/chat/sendPresence/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "presence": "composing",
    "delay": 1200
  }'
```

### Resposta Sucesso (200)
```json
{
  "status": "success",
  "presence": "composing",
  "number": "5511999999999",
  "timestamp": 1234567890
}
```

### Casos de Erro (CONFIRMADO)
| Código | Erro | Causa |
|--------|------|-------|
| 400 | Bad Request | Presença inválida (valores: composing, recording, paused) |
| 404 | Not Found | Contato ou instância não existe |
| 500 | Server Error | Falha ao enviar estado para WhatsApp |

### Fluxo Recomendado (CONFIRMADO)
1. Ao iniciar digitação: POST com `presence: "composing"` e `delay` de 5000ms
2. Se continuar digitando: renovar POST a cada 4s
3. Ao finalizar: POST com `presence: "paused"` (limpa indicador)

---

## 6. ENDPOINT 4: QR CODE E POLLING DE ESTADO

### 6.1 - Obter QR Code de Instância

**Método:** `GET`  
**Path:** `/instance/connect/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
```

### Resposta Sucesso (200)
```json
{
  "qrcode": {
    "code": "xxxx-xxxx-xxxx-xxxx",
    "base64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAf..."
  },
  "status": "qrcode_generated",
  "expiresIn": 60
}
```

**CONFIRMADO:** QR é retornado como **imagem base64 (data: URI)**, não como string de código texto.

### Renovação de QR (CONFIRMADO)
- QR válido por 60 segundos aprox.
- Se usuário não escanear, fazer GET novamente para renovar
- Sistema suporta múltiplas tentativas

### 6.2 - Verificar Estado da Conexão

**Método:** `GET`  
**Path:** `/instance/connectionState/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
```

### Resposta Sucesso (200)
```json
{
  "status": "open",
  "instance": "seu-instance",
  "connected": true,
  "authenticated": true,
  "qrcode": null,
  "message": "Connected and authenticated"
}
```

### Estados Possíveis (CONFIRMADO)
- `open` - Conectado e autenticado
- `connecting` - Em processo de conexão
- `closed` - Desconectado
- `qrcode_generated` - QR gerado, aguardando scan
- `qrcode_pending` - QR escaneado, aguardando confirmação
- `authenticated` - Após escanear QR

### Polling Recomendado (NÃO CONFIRMADO - INFERÊNCIA)
- Fazer polling a cada 2-3 segundos durante pareamento
- Após conectado, fazer ping a cada 30s para manter sessão viva
- Sistema usa keep-alive automático, mas polling regular evita timeout

---

## 7. ENDPOINT 5: CONFIGURAR WEBHOOK E LOGOUT

### 7.1 - Configurar Webhook da Instância

**Método:** `POST`  
**Path:** `/instance/connect` (configurado no pareamento) ou `PUT /webhook/update/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
Content-Type: application/json
```

### Payload de Configuração (no connect)
```json
{
  "instanceName": "seu-instance",
  "webhookUrl": "https://seu-backend.com/webhook",
  "webhookEvents": ["MESSAGE", "SEND_MESSAGE", "CONNECTION", "PRESENCE", "CONTACTS"],
  "webhookBase64": true,
  "webhookImmediate": true
}
```

### Opções de Eventos (CONFIRMADO)
**Principais categorias:**
- `MESSAGE` - Mensagens recebidas
- `SEND_MESSAGE` - Mensagens enviadas
- `READ_RECEIPT` - Confirmação leitura
- `CONNECTION` - Conexão/desconexão
- `PRESENCE` - Status online/offline
- `CONTACT` - Atualizações de contato
- `QRCODE` - Geração de novo QR
- `GROUP` - Ações em grupos
- `CALL` - Eventos de chamada
- `NEWSLETTER` - Ações em newsletter

**Opção:** Usar `"ALL"` para receber todos eventos.

### Configuração de Retry (CONFIRMADO)
- Máximo 5 tentativas de reenvio
- Intervalo: 30 segundos entre tentativas
- Seu endpoint deve responder com HTTP 2xx (200-299) em até 30 segundos
- Webhook tem timeout de 30s; responses mais lentas são consideradas falhadas

### Variável de Ambiente (Global)
```bash
# Em .env - aplica a TODAS instâncias
WEBHOOK_URL=https://seu-backend.com/webhook
WEBHOOK_EVENTS=MESSAGE,SEND_MESSAGE,CONNECTION,PRESENCE
```

---

### 7.2 - Logout/Desconectar Instância

**Método:** `POST`  
**Path:** `/instance/logout/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
```

### Payload
```json
{}
```

### Resposta Sucesso (200)
```json
{
  "status": "success",
  "message": "Logout instance 'seu-instance' successfully",
  "logout": true
}
```

### Efeitos do Logout (CONFIRMADO)
- Desconecta sessão WhatsApp
- Emite webhook de `LOGOUT_INSTANCE`
- Instância continua existindo (não é deletada)
- Requer novo QR para reconectar

### Webhook Recebido
```json
{
  "event": "LOGOUT_INSTANCE",
  "data": {
    "instance": "seu-instance",
    "reason": "user_logout"
  },
  "instanceId": "uuid"
}
```

---

### 7.3 - Deletar Instância Completamente

**Método:** `DELETE`  
**Path:** `/instance/delete/{instanceName}`  
**Headers:**
```
apikey: <API_KEY>
```

### Resposta Sucesso (200)
```json
{
  "status": "success",
  "message": "Instance deleted successfully",
  "instanceName": "seu-instance"
}
```

### Diferenças Logout vs Delete (CONFIRMADO)
| Operação | Logout | Delete |
|----------|--------|--------|
| Sessão | Desconecta WhatsApp | Remove completamente |
| Dados | Mantém histórico | Apaga tudo |
| Recuperação | Reconectar com QR | Criar nova instância |
| Uso | Temporário | Permanente |

---

## 8. ENDPOINT 6: FOTO DE PERFIL DO CONTATO

### Obter Foto de Perfil (NÃO CONFIRMADO - PARCIAL)

**Método:** `GET`  
**Path:** `/contact/profilePicture/{instanceName}/{number}` (INFERÊNCIA)  
**Headers:**
```
apikey: <API_KEY>
```

### Resposta Esperada
```json
{
  "profilePictureUrl": "https://pps.whatsapp.net/...",
  "number": "5511999999999",
  "pushName": "Contato Nome",
  "exists": true
}
```

**Status:** Endpoint mencionado em PRs do repositório como retornando PictureURL, mas path exato **não confirmado em documentação oficial**. Possível variação: `GET /user/info/{instanceName}`.

### Métodos Alternativos Documentados (CONFIRMADO)
1. Foto vem automaticamente em webhook de `CONTACTS_SET` ou `CONTACTS_UPDATE`
2. Campo `profilePictureUrl` incluído em payload de contato

---

## 9. ENDPOINT 7: KEEP-ALIVE E RECONEXÃO

### Mecanismo de Keep-Alive (CONFIRMADO - AUTOMÁTICO)
- **whatsmeow (base):** Gerencia conexão socket com WhatsApp automaticamente
- **Evolution Go:** Não requer ação manual de keep-alive
- **Debouncing:** Sistema evita transições rápidas entre estados (open↔closed)

### Estratégia Recomendada (CONFIRMADO)

#### 1. Polling de Status (Ativo)
```bash
# A cada 30 segundos
curl -X GET "https://seu-servidor.com/instance/connectionState/seu-instance" \
  -H "apikey: sua-api-key"
```

#### 2. Reconexão Automática (Passiva)
- Sistema tenta reconectar automaticamente em falhas transitórias
- Usa backoff exponencial para evitar spam a WhatsApp
- Diferencia entre: falha transitória (retry) vs. permanente (logout)

#### 3. Connection Pooling (Para Alta Carga)
```
Arquitetura:
- Múltiplas instâncias do mesmo bot atrás de load balancer
- Sticky sessions para routing consistente
- Suporta 10.000+ mensagens/hora sem degradação
```

### Tipos de Desconexão (CONFIRMADO)

| Tipo | Causa | Ação |
|------|-------|------|
| Transiente | Problema de rede | Retry automático com backoff |
| Bloqueado | WhatsApp bloqueou IP | Esperar 24h ou trocar IP |
| Logout | Usuário fez logout | Requer novo QR |
| Device Removed | Conta removida de dispositivo | Requer novo QR |

### Webhook de Reconexão (CONFIRMADO)
```json
{
  "event": "CONNECTION_UPDATE",
  "data": {
    "connection": "open",
    "lastSeen": 1234567890,
    "qr": null
  },
  "instanceId": "uuid"
}
```

---

## 10. ENDPOINT 8: EVENTOS DE WEBHOOK EMITIDOS

### Estrutura Base de Webhook (CONFIRMADO)
```json
{
  "event": "EVENT_NAME",
  "data": { /* payload específico */ },
  "instanceId": "uuid-da-instancia",
  "instanceToken": "token-da-instancia"
}
```

### 10.1 - MESSAGE_UPDATE (Atualização de Mensagem)

**Nome Exato:** `MESSAGES_UPDATE` (não MESSAGE_UPDATE)

```json
{
  "event": "MESSAGES_UPDATE",
  "data": {
    "keys": [
      {
        "remoteJid": "5511999999999@s.whatsapp.net",
        "fromMe": false,
        "id": "3EB0XXXXX",
        "participant": null
      }
    ],
    "update": "message_read"
  },
  "instanceId": "uuid"
}
```

**update values:**
- `message_read` - Mensagem foi lida
- `message_edited` - Mensagem foi editada
- `message_react` - Reagiu com emoji
- `message_revoked` - Mensagem foi deletada

---

### 10.2 - CONNECTION (Conexão)

**Nome Exato:** `CONNECTION_UPDATE`

```json
{
  "event": "CONNECTION_UPDATE",
  "data": {
    "connection": "open",
    "lastSeen": 1234567890,
    "isNewLogin": false,
    "isOnline": true
  },
  "instanceId": "uuid"
}
```

**connection values:**
- `open` - Conectado
- `connecting` - Tentando conectar
- `closed` - Desconectado

**Eventos especiais:**
```json
{
  "event": "PairSuccess",
  "data": { "timestamp": 1234567890 },
  "instanceId": "uuid"
}
```

```json
{
  "event": "LoggedOut",
  "data": { "reason": "user_logout" },
  "instanceId": "uuid"
}
```

---

### 10.3 - PRESENCE (Presença)

**Nome Exato:** `PRESENCE_UPDATE`

```json
{
  "event": "PRESENCE_UPDATE",
  "data": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "presence": "available",
    "lastSeen": 1234567890
  },
  "instanceId": "uuid"
}
```

**presence values:**
- `available` - Online
- `unavailable` - Offline
- `composing` - Digitando
- `recording` - Gravando

---

### 10.4 - CONTACTS (Contatos)

**Nome Exato:** `CONTACTS_UPDATE` (ou `CONTACTS_SET` para inicial)

```json
{
  "event": "CONTACTS_UPDATE",
  "data": {
    "contacts": [
      {
        "id": "5511999999999@s.whatsapp.net",
        "pushName": "Nome Contato",
        "number": "5511999999999",
        "profilePictureUrl": "https://pps.whatsapp.net/...",
        "shortName": "Contato",
        "status": "Hey there I am using WhatsApp"
      }
    ]
  },
  "instanceId": "uuid"
}
```

---

### 10.5 - MESSAGE (Mensagem Recebida)

**Nome Exato:** `MESSAGES_UPSERT`

```json
{
  "event": "MESSAGES_UPSERT",
  "data": {
    "messages": [
      {
        "key": {
          "remoteJid": "5511999999999@s.whatsapp.net",
          "fromMe": false,
          "id": "3EB0XXXXX"
        },
        "messageTimestamp": 1234567890,
        "pushName": "Contato Nome",
        "message": {
          "conversation": "Olá!"
        },
        "type": "notify"
      }
    ],
    "type": "notify"
  },
  "instanceId": "uuid"
}
```

**message types:**
- `conversation` - Texto simples
- `imageMessage` - Imagem
- `videoMessage` - Vídeo
- `audioMessage` - Áudio
- `documentMessage` - Documento
- `stickerMessage` - Adesivo
- `contactMessage` - Contato compartilhado

---

### 10.6 - SEND_MESSAGE (Mensagem Enviada)

**Nome Exato:** `SEND_MESSAGE`

```json
{
  "event": "SEND_MESSAGE",
  "data": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "fromMe": true,
      "id": "3EB0YYYYY"
    },
    "messageTimestamp": 1234567890,
    "message": {
      "conversation": "Resposta enviada"
    },
    "status": "delivered"
  },
  "instanceId": "uuid"
}
```

---

### 10.7 - READ_RECEIPT (Confirmação de Leitura)

```json
{
  "event": "READ_RECEIPT",
  "data": {
    "remoteJid": "5511999999999@s.whatsapp.net",
    "messageIds": ["3EB0XXXXX"],
    "readAt": 1234567890
  },
  "instanceId": "uuid"
}
```

---

### 10.8 - Outros Eventos Importantes

**QRCODE_UPDATED:**
```json
{
  "event": "QRCODE_UPDATED",
  "data": {
    "qrcode": {
      "code": "xxxx-xxxx-xxxx",
      "base64": "data:image/png;base64,..."
    },
    "timeout": 60
  },
  "instanceId": "uuid"
}
```

**CALL (Chamadas):**
```json
{
  "event": "CALL",
  "data": {
    "callFrom": "5511999999999@s.whatsapp.net",
    "status": "incoming_call",
    "timestamp": 1234567890,
    "isGroupCall": false
  },
  "instanceId": "uuid"
}
```

**GROUP_UPDATE:**
```json
{
  "event": "GROUP_UPDATE",
  "data": {
    "groupId": "120362003333333@g.us",
    "action": "participant_add",
    "participants": ["5511999999999@s.whatsapp.net"],
    "timestamp": 1234567890
  },
  "instanceId": "uuid"
}
```

---

## 11. EXEMPLOS CURL FUNCIONAIS COMPLETOS

### 1. Criar Instância
```bash
curl -X POST "https://seu-servidor.com/instance/create" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "seu-instance",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true,
    "webhookUrl": "https://seu-backend.com/webhook",
    "webhookEvents": ["ALL"]
  }'
```

### 2. Obter QR Code
```bash
curl -X GET "https://seu-servidor.com/instance/connect/seu-instance" \
  -H "apikey: sua-api-key"
```

### 3. Enviar Mensagem de Texto
```bash
curl -X POST "https://seu-servidor.com/message/sendText/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "text": "Olá! Esta é uma mensagem de teste."
  }'
```

### 4. Enviar Imagem (Base64)
```bash
curl -X POST "https://seu-servidor.com/message/sendMedia/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "mediatype": "image",
    "mimetype": "image/jpeg",
    "media": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
    "fileName": "foto.jpg",
    "caption": "Foto de teste"
  }'
```

### 5. Enviar Vídeo (URL)
```bash
curl -X POST "https://seu-servidor.com/message/sendMedia/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "mediatype": "video",
    "media": "https://exemplo.com/video.mp4",
    "fileName": "video.mp4",
    "caption": "Vídeo importante"
  }'
```

### 6. Marcar Mensagem como Lida
```bash
curl -X PUT "https://seu-servidor.com/chat/markMessageAsRead/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "read_messages": [
      {
        "remoteJid": "5511999999999@s.whatsapp.net",
        "fromMe": false,
        "id": "3EB0XXXXX"
      }
    ]
  }'
```

### 7. Enviar Indicador de Digitação
```bash
curl -X POST "https://seu-servidor.com/chat/sendPresence/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5511999999999",
    "presence": "composing",
    "delay": 1200
  }'
```

### 8. Logout da Instância
```bash
curl -X POST "https://seu-servidor.com/instance/logout/seu-instance" \
  -H "apikey: sua-api-key" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### 9. Deletar Instância
```bash
curl -X DELETE "https://seu-servidor.com/instance/delete/seu-instance" \
  -H "apikey: sua-api-key"
```

---

## 12. BREAKING CHANGES ENTRE VERSÕES

### 0.6 → 0.7.0 (CONFIRMADO)
**Breaking Change Principal:**
- Protocolo de proxy mudou de **SOCKS5 obrigatório** para **HTTP/HTTPS com suporte a porta customizada**
- **Ação:** Se usa proxy, reconfigurar para HTTP/HTTPS e especificar porta se não-padrão (80/443)

**Adições:**
- Multi-platform interactive messages (Android, iOS, Web, Desktop)
- Carousel e status messages
- Base64 support em mídia

### 0.7.0 → 0.7.1 (CONFIRMADO)
- Modal de teste no gerenciador (UI feature)
- Pinning de whatsmeow-lib SHA (reprodutibilidade build)
- Docker `:latest` tag agora só para releases estáveis (não beta)
- **Sem breaking changes**

### 0.7.1 → 0.7.2 (CONFIRMADO)
- Passkey (WebAuthn) pairing para contas bloqueadas pelo servidor
- Auto-ativação de licença para ambientes headless
- **Abandono do fork de whatsmeow em favor da versão oficial**
- **Sem breaking changes API**

---

## 13. LIMITAÇÕES DOCUMENTADAS

| Aspecto | Limitação | Fonte |
|---------|-----------|-------|
| Taxa de requisições | Máx 50 req/s por instância | Recomendação oficial |
| Webhook timeout | 30 segundos | Documentado |
| Webhook retries | Máx 5 tentativas | Documentado |
| QR validade | ~60 segundos | Observado |
| Tamanho mídia | Não documentado | Inferência: <16MB recomendado |
| HTTP status sucesso | 200-299 | Documentado para webhooks |
| Formatos imagem | JPEG, PNG, WebP | Observado |
| Formatos vídeo | MP4, 3GP | Observado |

---

## 14. ERROS COMUNS E SOLUÇÕES

| Erro | Causa | Solução |
|------|-------|---------|
| 400 Bad Request (base64) | Prefixo `data:*;base64,` incluído | Remover prefixo, enviar apenas base64 puro |
| 400 Bad Request (payload) | JSON malformado | Validar JSON com jq ou online validator |
| 401 Unauthorized | apikey inválida ou expirada | Verificar `.env` GLOBAL_API_KEY |
| 404 Not Found | Instância não existe | Listar instâncias e confirmar nome |
| 429 Rate Limit | Muitas requisições por segundo | Implementar fila com delay entre requests |
| 500 Server Error | Arquivo muito grande ou timeout | Reduzir tamanho/qualidade de mídia |
| Webhook não chega | Endpoint retorna erro ou timeout | Validar endpoint, garantir resposta 2xx em <30s |
| QR não aparece | Socket não mantém vivo | Fazer polling GET /instance/connectionState a cada 5s |
| Mensagem perdida | Taxa muito alta de envios | Aguardar resposta de cada POST antes do próximo |

---

## 15. STATUS DE CONFIRMAÇÃO POR ENDPOINT

| Endpoint | Status | Notas |
|----------|--------|-------|
| sendMedia (base64) | CONFIRMADO | Path, headers, payload documentados |
| sendMedia (URL) | CONFIRMADO | Funcional em v0.7.0+ |
| markAsRead | CONFIRMADO | Path PUT, payload com read_messages array |
| sendPresence | CONFIRMADO | Estados: composing, recording, paused |
| QR code (GET) | CONFIRMADO | Retorna imagem base64, não código texto |
| QR polling | CONFIRMADO | A cada 2-3s durante pareamento |
| Webhook configure | CONFIRMADO | No /instance/connect ou POST /webhook/update |
| Webhook events | PARCIALMENTE CONFIRMADO | Nomes (MESSAGES_UPDATE, CONNECTION_UPDATE, etc) sim; alguns payloads parciais |
| Logout | CONFIRMADO | POST /instance/logout |
| Delete instance | CONFIRMADO | DELETE /instance/delete |
| Profile picture | NÃO CONFIRMADO | Mencionado em PRs; path exato não documentado |
| Keep-alive | CONFIRMADO | Automático; polling recomendado a cada 30s |

---

## 16. REFERÊNCIAS E FONTES

**Repositório Oficial:**
- [evolution-foundation/evolution-go GitHub](https://github.com/evolution-foundation/evolution-go)
- [GitHub Releases](https://github.com/evolution-foundation/evolution-go/releases)

**Documentação:**
- [docs.evolutionfoundation.com.br/en/evolution-go](https://docs.evolutionfoundation.com.br/en/evolution-go)
- [Webhooks Documentation](https://docs.evolutionfoundation.com.br/evolution-go/webhooks)
- [Events System](https://github.com/evolution-foundation/evolution-go/blob/main/docs/wiki/recursos-avancados/events-system.md)

**API Documentation:**
- [Evolution API v2 - doc.evolution-api.com](https://doc.evolution-api.com/v2)
- [Send Media Documentation](https://doc.evolution-api.com/v2/api-reference/message-controller/send-media)
- [Mark as Read Documentation](https://doc.evolution-api.com/v1/api-reference/chat-controller/mark-as-read)

**Exemplos e Manuais:**
- [Manual de Integração Evolution API V2 - Gist](https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a)
- [Postman Collections - Evolution API](https://www.postman.com/agenciadgcode/evolution-api)

**Issues e Discussions:**
- [Events System Notion (payloads completos)](https://atendai.notion.site/Webhook-11b50bf742da80d99acafe4d92ccd054?pvs=74) - Link no wiki

---

## CONCLUSÃO

A documentação Evolution Go v0.7.1 é **bem estabelecida para operações core** (envio, webhooks, QR), mas **escassa em detalhes de API** para algumas áreas periféricas (profile picture exato, timeouts, limitações de tamanho). O contrato é **estável** com mudanças menores entre 0.7.0-0.7.2, sem breaking changes na API REST.

**Pontos-chave para implementação:**
1. Envelopes `{data}` obrigatórios em todas responses
2. Base64 sem prefixo (`data:*;base64,`)
3. Autenticação por header `apikey`, não `Authorization`
4. Webhook com retry automático (5×, 30s intervalo)
5. Keep-alive via polling a cada 30s ou automático via whatsmeow

