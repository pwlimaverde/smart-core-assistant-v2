# Evolution API — Quick Reference

Resumo rápido dos endpoints e payloads principais. Para detalhes completos, consultar `evolution-api-documentation.md`.

---

## URLs Base

```
Base URL: http://{server}:{port}
Padrão dev: http://localhost:3000
Produção: https://api.seuservidor.com
```

---

## Headers Padrão

```
Content-Type: application/json
apikey: {seu_token_aqui}
```

---

## 1️⃣ Criar Instância

```bash
POST /instance/create
Header: apikey={GLOBAL_TOKEN}

{
  "instanceName": "bot-vendas",
  "integration": "WHATSAPP-BAILEYS",
  "qrcode": true
}

# Resposta
{
  "response": {
    "instance": {
      "hash": "token_da_instancia",
      "qrCode": { "imageBase64": "data:image/png;base64,..." }
    }
  }
}
```

---

## 2️⃣ Obter QR Code

```bash
GET /instance/connect/bot-vendas
Header: apikey={GLOBAL_TOKEN}

# Resposta
{
  "response": {
    "qrCode": {
      "imageBase64": "data:image/png;base64,..."
    }
  }
}
```

---

## 3️⃣ Verificar Conexão

```bash
GET /instance/connectionState/bot-vendas
Header: apikey={GLOBAL_TOKEN}

# Resposta
{
  "response": {
    "instance": {
      "state": "open"  # open, close, connecting
    }
  }
}
```

---

## 4️⃣ Enviar Texto

```bash
POST /message/sendText/bot-vendas
Header: apikey={INSTANCE_TOKEN}

{
  "number": "5511999999999",
  "text": "Olá!",
  "delay": 0,
  "linkPreview": true
}

# Resposta
{
  "response": {
    "key": {
      "id": "msg_id_123"
    }
  }
}
```

---

## 5️⃣ Enviar Mídia (3 métodos)

### A) Upload arquivo:
```bash
POST /message/sendMedia/bot-vendas
Header: apikey={INSTANCE_TOKEN}

Form data:
  number=5511999999999
  mediatype=image
  media=@/caminho/foto.jpg
  caption=Veja isso!
```

### B) URL remota:
```bash
POST /message/sendMedia/bot-vendas
Header: apikey={INSTANCE_TOKEN}

{
  "number": "5511999999999",
  "mediatype": "image",
  "media": "https://exemplo.com/foto.jpg",
  "caption": "Veja isso!"
}
```

### C) Base64 (< 3MB):
```bash
POST /message/sendMedia/bot-vendas
Header: apikey={INSTANCE_TOKEN}

{
  "number": "5511999999999",
  "mediatype": "image",
  "media": "iVBORw0KGgo...",
  "caption": "Veja isso!"
}
```

---

## 6️⃣ Configurar Webhook

```bash
PUT /webhook/set/bot-vendas
Header: apikey={INSTANCE_TOKEN}

{
  "enabled": true,
  "url": "https://seu-servidor.com/webhooks",
  "events": [
    "MESSAGES_UPSERT",
    "CONNECTION_UPDATE",
    "QRCODE_UPDATED"
  ],
  "headers": {
    "Authorization": "Bearer seu_token"
  }
}
```

---

## 7️⃣ Listar Instâncias

```bash
GET /instance/fetchInstances
Header: apikey={GLOBAL_TOKEN}

# Resposta
{
  "response": {
    "instances": [
      {
        "instanceName": "bot-vendas",
        "hash": "token",
        "status": "open",
        "phoneConnected": true
      }
    ]
  }
}
```

---

## 8️⃣ Logout

```bash
POST /instance/logout/bot-vendas
Header: apikey={GLOBAL_TOKEN}
Body: {}
```

---

## 9️⃣ Deletar Instância

```bash
DELETE /instance/delete/bot-vendas
Header: apikey={GLOBAL_TOKEN}
```

---

## 🔟 Pairing Code (alternativa ao QR)

```bash
POST /instance/pairingCode/bot-vendas
Header: apikey={GLOBAL_TOKEN}

{
  "number": "5511999999999"
}

# Resposta
{
  "response": {
    "pairingCode": "ABC-DEFG"
  }
}
```

---

## Webhook Events (recebidos)

### MESSAGES_UPSERT
```json
{
  "event": "messages.upsert",
  "instance": "bot-vendas",
  "data": {
    "key": {
      "remoteJid": "5511999999999@s.whatsapp.net",
      "id": "msg_id_123",
      "fromMe": false
    },
    "message": {
      "conversation": "Olá!"
    }
  }
}
```

### CONNECTION_UPDATE
```json
{
  "event": "connection.update",
  "instance": "bot-vendas",
  "data": {
    "state": "open"  # open, close, connecting
  }
}
```

### QRCODE_UPDATED
```json
{
  "event": "qrcode.update",
  "instance": "bot-vendas",
  "data": {
    "qrCode": {
      "imageBase64": "data:image/png;base64,..."
    }
  }
}
```

---

## Erros HTTP

| Código | Significado | Motivo |
|--------|-------------|--------|
| 201 | Created | Instância/mensagem criada com sucesso |
| 200 | OK | Operação bem-sucedida |
| 400 | Bad Request | Parâmetro inválido (número mal formatado, campo obrigatório faltando) |
| 401 | Unauthorized | Token inválido ou faltando |
| 404 | Not Found | Instância não existe |
| 500 | Internal Error | Erro no servidor Evolution |

---

## Formatos Obrigatórios

### Número de telefone (DDI):
```
5511999999999  # 13 dígitos: 55 (Brasil) + 11 (área) + 999999999 (número)
```

### JID (Jabber ID):
```
5511999999999@s.whatsapp.net     # Contato
5511999999999-1234567890@g.us    # Grupo
```

### Base64 para mídia:
```
iVBORw0KGgo...  # SEM prefixo "data:image/png;base64,"
```

---

## Fluxo Típico

```
1. POST /instance/create
   ↓ recebe: hash (instance token)
   
2. GET /instance/connect/{name}
   ↓ usuário escaneia QR code
   
3. GET /instance/connectionState/{name} (polling)
   ↓ até state == "open"
   
4. PUT /webhook/set/{name}
   ↓ configurar recebimento de eventos
   
5. POST /message/sendText/{name}
   ↓ enviar mensagens
   
6. Receber webhooks em paralelo
   ↓ MESSAGES_UPSERT, CONNECTION_UPDATE, etc.
```

---

## Tokens: Qual usar?

| Operação | Token |
|----------|-------|
| POST /instance/create | **GLOBAL** |
| GET /instance/connect | **GLOBAL** |
| GET /instance/connectionState | **GLOBAL** |
| GET /instance/fetchInstances | **GLOBAL** |
| POST /instance/logout | **GLOBAL** |
| DELETE /instance/delete | **GLOBAL** |
| POST /message/sendText | **INSTANCE** |
| POST /message/sendMedia | **INSTANCE** |
| PUT /webhook/set | **INSTANCE** |
| POST /instance/pairingCode | **GLOBAL** |

---

## cURL Cheat Sheet

### Criar instância
```bash
curl -X POST http://localhost:3000/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: global_token" \
  -d '{
    "instanceName": "bot",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'
```

### Enviar mensagem
```bash
curl -X POST http://localhost:3000/message/sendText/bot \
  -H "Content-Type: application/json" \
  -H "apikey: instance_token" \
  -d '{
    "number": "5511999999999",
    "text": "Olá!"
  }'
```

### Enviar arquivo
```bash
curl -X POST http://localhost:3000/message/sendMedia/bot \
  -H "apikey: instance_token" \
  -F "number=5511999999999" \
  -F "mediatype=image" \
  -F "media=@foto.jpg"
```

### Verificar estado
```bash
curl http://localhost:3000/instance/connectionState/bot \
  -H "apikey: global_token"
```

### Listar instâncias
```bash
curl http://localhost:3000/instance/fetchInstances \
  -H "apikey: global_token"
```

---

## Tipos de Mídia

| Tipo | MIME | Máx Size | Método |
|------|------|----------|--------|
| image | image/jpeg | 16MB | URL ou base64 < 3MB |
| video | video/mp4 | 16MB | URL obrigatória se > 3MB |
| audio | audio/mpeg | 16MB | URL ou base64 < 3MB |
| document | application/pdf | 16MB | URL ou base64 < 3MB |

---

## Links Rápidos

- **Docs oficial:** https://docs.evolutionfoundation.com.br/
- **GitHub:** https://github.com/evolution-foundation/evolution-api
- **Manual integração:** https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a
- **Cliente Python:** https://github.com/EvolutionAPI/evolution-client-python
- **Evolution Go (versão em Go):** https://github.com/evolution-foundation/evolution-go

