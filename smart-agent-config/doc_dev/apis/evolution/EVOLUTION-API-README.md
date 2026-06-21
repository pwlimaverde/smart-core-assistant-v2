# Evolution API — Documentação de Integração

**Versão:** 1.0  
**Data:** Junho 2026  
**Stack:** Rust (backend), gRPC, Flutter (clients)

---

## O que é Evolution API?

Evolution API é um **servidor WhatsApp multi-tenant open-source** que fornece uma **REST API pura** para automação de mensagens. Construído em Node.js/TypeScript ou Go, permite:

- Criar múltiplas instâncias de WhatsApp (1 por usuário)
- Enviar/receber mensagens de texto e mídia
- Configurar webhooks para eventos em tempo real
- Integração nativa com plataformas (Typebot, Chatwoot, etc.)
- Autenticação baseada em API Key
- Suporte a QR code ou pairing code

**Repositório oficial:** https://github.com/evolution-foundation/evolution-api

---

## 📚 Documentação Incluída

Esta pasta contém **6 documentos** estruturados por propósito:

### 1. **EVOLUTION-API-INDEX.md** ← Comece aqui!
- Índice de todos os documentos
- Quick start (primeiros passos)
- Fluxos comuns e cenários
- Checklist de implementação
- Troubleshooting rápido

### 2. **evolution-api-documentation.md** — Referência Técnica Completa
- Autenticação (Global Token + Instance Token)
- 10 endpoints principais com schemas JSON
- Webhooks (MESSAGES_UPSERT, CONNECTION_UPDATE, etc.)
- Tratamento de erros
- Formatação obrigatória (DDI, JID, base64)
- Exemplo funcional em Rust
- **~30KB — 2000+ linhas**

### 3. **evolution-api-quick-reference.md** — Consulta Rápida
- URLs e headers padrão
- Payloads resumidos de cada endpoint
- Exemplos cURL prontos para copiar/colar
- Tabela de qual token usar
- Tipos de mídia suportados
- **~7KB — 300+ linhas**

### 4. **evolution-api-implementation-guide.md** — Guia Prático
- Fluxo completo visual
- Implementação Rust production-ready
- Tratamento de webhooks em Axum
- **20 erros comuns com soluções**
- Padrão de integração com banco de dados
- Checklist pré-deploy
- Observabilidade (Prometheus)
- **~25KB — 1500+ linhas**

### 5. **evolution-api-grpc-bridge.md** — Padrão gRPC
- Arquitetura (Flutter ↔ gRPC ↔ Evolution)
- Proto definition completo (whatsapp.proto)
- Serviço gRPC em Rust
- Cliente em Dart (Flutter)
- Schema SQL para armazenar tokens
- **~26KB — 1200+ linhas**

### 6. **evolution-api-local-setup.md** — Setup Local
- Docker Compose (recomendado)
- Setup sem Docker (Node.js local)
- Testando localmente
- Configurar webhooks com ngrok
- Debugging e troubleshooting
- **~13KB — 600+ linhas**

**Total:** ~127KB de documentação estruturada

---

## 🚀 Começar Agora (3 min)

### Passo 1: Entender Autenticação
```
Global Token: criar/deletar/listar instâncias
Instance Token: enviar mensagens, configurar webhooks
```

### Passo 2: Setup Local (Docker)
```bash
# Lê: evolution-api-local-setup.md
docker-compose up -d

# Aguardar ~30s para estabilizar
docker-compose ps
```

### Passo 3: Teste Rápido
```bash
# Criar instância
curl -X POST http://localhost:3000/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: sua_global_api_key" \
  -d '{"instanceName": "bot", "integration": "WHATSAPP-BAILEYS", "qrcode": true}'

# Escanear QR no WhatsApp
# Aguardar estado "open"

# Enviar mensagem
curl -X POST http://localhost:3000/message/sendText/bot \
  -H "Content-Type: application/json" \
  -H "apikey: instance_token" \
  -d '{"number": "5511999999999", "text": "Olá!"}'
```

---

## 📖 Guia de Leitura por Caso de Uso

### Cenário A: Entender a API
1. Lê **EVOLUTION-API-INDEX.md** (15 min)
2. Lê **evolution-api-documentation.md** (1h)
3. Testa com **evolution-api-quick-reference.md** (cURL)

### Cenário B: Implementar em Rust
1. Lê **evolution-api-local-setup.md** (setup)
2. Lê **evolution-api-implementation-guide.md** (implementação)
3. Copia código e adapta para seu projeto
4. Segue checklist pré-deploy

### Cenário C: Integrar com gRPC
1. Lê **EVOLUTION-API-INDEX.md** → seção "Padrão gRPC"
2. Lê **evolution-api-grpc-bridge.md**
3. Copia whatsapp.proto e colas no seu projeto
4. Implementa WhatsappService conforme exemplo

### Cenário D: Debugar Problema
1. Lê **EVOLUTION-API-INDEX.md** → "Troubleshooting Rápido"
2. Consulta **evolution-api-implementation-guide.md** → "Erros Comuns"
3. Testa com cURL de **evolution-api-quick-reference.md**
4. Verifica logs em **evolution-api-local-setup.md** → "Debugging"

---

## ⚡ Checklist de Implementação

### Fase 1: Aprendizado (1-2 dias)
- [ ] Ler EVOLUTION-API-INDEX.md completo
- [ ] Ler evolution-api-documentation.md
- [ ] Rodar localmente com docker-compose
- [ ] Criar instância e enviar 1ª mensagem via cURL

### Fase 2: Implementação Rust (2-3 dias)
- [ ] Copiar EvolutionClient do guide
- [ ] Integrar no seu projeto
- [ ] Testar create_instance() e send_text()
- [ ] Implementar webhook handler

### Fase 3: gRPC (1-2 dias, se aplicável)
- [ ] Criar whatsapp.proto
- [ ] Implementar WhatsappService
- [ ] Expor para Flutter/clients
- [ ] Testar integração end-to-end

### Fase 4: Produção (1-2 dias)
- [ ] Configurar HTTPS para webhooks
- [ ] Armazenar tokens em .env
- [ ] Implementar logging/monitoring
- [ ] Passar checklist pré-deploy

---

## 🔑 Conceitos-Chave

### Autenticação
```
POST /instance/create               → usa GLOBAL_TOKEN
POST /message/sendText/{instance}   → usa INSTANCE_TOKEN (hash)
PUT /webhook/set/{instance}         → usa INSTANCE_TOKEN

Nunca misture! Erro 401 = token errado
```

### Formato de Telefone (DDI — obrigatório)
```
5511999999999  ← 13 dígitos (55=Brasil, 11=SP, 999999999=número)
❌ 11 99999-9999
❌ +55 11 9 9999-9999
❌ (11) 99999-9999
```

### Webhooks
```
Instância conectada (state = "open") → começa a receber webhooks
MESSAGES_UPSERT → mensagem recebida/enviada
CONNECTION_UPDATE → mudança no estado (conectado/desconectado)
QRCODE_UPDATED → novo QR code gerado (após logout)
```

### Mídia
```
< 3MB → base64 OK
> 3MB → obrigatoriamente URL remota (S3/CDN)
Vídeos tendemos usar URL
```

---

## 📊 Arquitetura de Referência

```
┌─────────────────────────────────────┐
│  Flutter / Rust Client              │
│  (gRPC)                             │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  WhatsApp Service (gRPC)            │
│  - whatsapp.proto                   │
│  - CreateInstance()                 │
│  - SendMessage()                    │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  Rust Backend (evolution_client.rs) │
│  - REST wrapper                     │
│  - Webhook handler                  │
│  - Database (tokens, msgs)          │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  Evolution API (REST)               │
│  - POST /instance/create            │
│  - POST /message/sendText           │
│  - PUT /webhook/set                 │
│  - Webhooks ← porta 3001/webhook    │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│  WhatsApp (via Baileys)             │
│  - Conexão com WhatsApp Web         │
│  - Envio/recebimento de msgs        │
└─────────────────────────────────────┘
```

---

## 🛠️ Stack Mínimo

### Desenvolvimento
- Docker + Docker Compose (para Evolution)
- Rust 1.70+ (backend)
- PostgreSQL 15+ (banco de dados)
- Redis 7+ (opcional, cache/fila)

### Produção
- Docker (Evolution + PostgreSQL)
- Rust (seu backend)
- HTTPS (para webhooks)
- .env com tokens secretos
- CI/CD (GitHub Actions, etc.)

---

## 📝 Padrões e Boas Práticas

✅ **Fazer:**
- Usar Global Token apenas para operações de instância
- Armazenar Instance Tokens em banco de dados criptografado
- Implementar deduplicação de mensagens (por message_id)
- Usar URLs para mídia > 3MB
- Ativar HTTPS em produção
- Validar DDI dos números antes de enviar

❌ **NÃO Fazer:**
- Misturar Global e Instance tokens
- Hardcoder tokens no código
- Confiar que webhook não vai duplicar
- Enviar base64 de vídeos grandes (stack overflow)
- Usar HTTP em produção
- Fazer polling sem limite (rate limiting)

---

## 🐛 Debug Rápido

| Problema | Primeiro Passo |
|----------|----------------|
| "Invalid API key" | Verificar qual token está usando |
| "Instance not found" | Listar instâncias com GET /instance/fetchInstances |
| "Invalid phone number" | Formatar como DDI: 5511999999999 |
| "Maximum call stack" | Usar URL para vídeo, não base64 |
| Webhook não recebe | Verificar state = "open" e URL acessível |
| Mensagem duplicada | Implementar dedup por message_id |

---

## 📚 Referências Externas

| Recurso | Link |
|---------|------|
| GitHub oficial | https://github.com/evolution-foundation/evolution-api |
| Docs oficial | https://docs.evolutionfoundation.com.br/ |
| Manual de integração | https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a |
| Cliente Python | https://github.com/EvolutionAPI/evolution-client-python |
| Evolution Go | https://github.com/evolution-foundation/evolution-go |
| Postman v2.2.2 | https://www.postman.com/agenciadgcode/evolution-api/documentation/jn0bbzv/evolution-api-v2-2-2 |

---

## 📞 Suporte

**Problemas com Evolution API?**
- Verificar logs: `docker-compose logs evolution-api | grep -i error`
- Consultar GitHub issues: https://github.com/evolution-foundation/evolution-api/issues
- Ler manual de integração: gist.github.com (link acima)

**Problemas com esta documentação?**
- Abrir issue no repositório do smart-core
- Consultar doc_dev/planejamento para contexto maior

---

## 📋 Estrutura de Arquivos

```
smart-agent-config/
├── EVOLUTION-API-README.md                    ← Este arquivo
├── EVOLUTION-API-INDEX.md                     ← Índice (comece aqui)
├── evolution-api-documentation.md             ← Referência técnica
├── evolution-api-quick-reference.md           ← Consulta rápida
├── evolution-api-implementation-guide.md      ← Guia prático
├── evolution-api-grpc-bridge.md               ← Padrão gRPC
└── evolution-api-local-setup.md               ← Setup local
```

---

## 🎯 Próximas Ações

1. **Agora:** Abrir `EVOLUTION-API-INDEX.md`
2. **Em 5 min:** Entender fluxo de autenticação
3. **Em 30 min:** Rodar Evolution localmente
4. **Amanhã:** Implementar em Rust
5. **Fim da semana:** Deploy em produção

---

**Versão:** 1.0 (Junho 2026)  
**Compatível com:** Evolution API v2.2.2+, Rust 1.70+, Dart 3.0+

---

Sucesso na implementação! 🚀

