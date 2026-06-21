# Evolution API — Documentação Completa (Índice)

Esta pasta contém documentação abrangente sobre a integração com **Evolution API (Evolution Go)** — servidor WhatsApp multi-tenant open-source.

---

## Arquivos de Referência

### 1. **evolution-api-documentation.md** — Documentação Completa
**Para:** Detalhes técnicos e referência oficial dos endpoints

Contém:
- Visão geral da Evolution API
- Modelo de autenticação (Global Token + Instance Token)
- 10 endpoints principais com schemas JSON completos
- Formato de webhooks (MESSAGES_UPSERT, CONNECTION_UPDATE, etc.)
- Tratamento de erros (400, 401, 404, 500)
- Formatação obrigatória de números (DDI)
- Integração prática em Rust com exemplo funcional
- Referências e recursos oficiais

**Quando usar:**
- Entender como funciona cada endpoint
- Referenciar exatamente qual token usar
- Consultar estrutura exata de requisição/resposta
- Debugar erros específicos

---

### 2. **evolution-api-quick-reference.md** — Resumo Rápido
**Para:** Consulta rápida de URLs, payloads e comandos cURL

Contém:
- URLs base e headers padrão
- Endpoint resumido com exemplos de payload
- Webhook events (estrutura JSON concisa)
- Códigos de erro e significados
- Formatos obrigatórios (número, JID, base64)
- Fluxo típico de integração
- Tabela: qual token usar em cada operação
- Cheat sheet cURL
- Tipos de mídia suportados

**Quando usar:**
- Precisa de um comando cURL rápido
- Quer confirmar qual é o payload correto
- Consultando em terminal ou mobile
- Copiar/colar exemplos

---

### 3. **evolution-api-implementation-guide.md** — Guia Prático e Troubleshooting
**Para:** Implementação real, padrões de código e solução de problemas

Contém:
- Fluxo completo visual (setup → webhooks → envio)
- Implementação completa em Rust (cliente wrapper production-ready)
- Tratamento de webhooks em Axum
- Erros comuns com soluções:
  - "Maximum call stack size exceeded" (vídeo > 3MB)
  - "Invalid API key" (confundindo tokens)
  - "Invalid phone number" (validação DDI)
  - Webhooks não recebendo eventos
  - Duplicação de mensagens
- Padrão: integração com banco de dados
- Checklist pré-deploy
- Observabilidade com Prometheus

**Quando usar:**
- Implementando em Rust pela primeira vez
- Debugando problema específico em produção
- Precisa padrão de código real
- Configurar monitoramento

---

### 4. **evolution-api-grpc-bridge.md** — Integração gRPC
**Para:** Abstrair Evolution API através de gRPC (padrão do smart-core)

Contém:
- Arquitetura visual (Flutter/Rust ↔ gRPC ↔ Evolution REST)
- Proto definition completo (whatsapp.proto)
- Implementação do serviço gRPC em Rust
- Tratamento de webhooks em Axum
- Exemplo de uso no Rust backend
- Cliente gRPC em Dart (Flutter)
- Schema SQL para armazenar tokens
- Padrão: recuperar instance token em requisição gRPC

**Quando usar:**
- Precisa expor Evolution API via gRPC
- Integrando com Flutter/clients existentes
- Configurar padrão de wrapper RPC
- Definir contratos (proto)

---

## Quick Start: Primeiros Passos

### Passo 1: Entender Autenticação
Leia: **evolution-api-documentation.md** → seção "Autenticação"

**Resumo:**
- Global Token = gerenciar instâncias (criar, deletar, listar)
- Instance Token = enviar mensagens, configurar webhooks

Nunca misture!

### Passo 2: Criar Primeira Instância
Use: **evolution-api-quick-reference.md** → "1️⃣ Criar Instância"

```bash
curl -X POST http://localhost:3000/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: seu_global_token" \
  -d '{
    "instanceName": "meu-bot",
    "integration": "WHATSAPP-BAILEYS",
    "qrcode": true
  }'
```

### Passo 3: Verificar Conexão
Use: **evolution-api-quick-reference.md** → "3️⃣ Verificar Conexão"

```bash
curl http://localhost:3000/instance/connectionState/meu-bot \
  -H "apikey: seu_global_token"
```

Aguarde resposta `"state": "open"`

### Passo 4: Enviar Mensagem
Use: **evolution-api-quick-reference.md** → "4️⃣ Enviar Texto"

```bash
curl -X POST http://localhost:3000/message/sendText/meu-bot \
  -H "Content-Type: application/json" \
  -H "apikey: instance_token_aqui" \
  -d '{
    "number": "5511999999999",
    "text": "Olá da Evolution API!"
  }'
```

### Passo 5: Implementar em Rust
Copia: **evolution-api-implementation-guide.md** → "Estrutura Base — Client Wrapper"

Colas na tua aplicação e adapta para seu contexto.

---

## Fluxos Comuns

### Cenário A: Criar bot WhatsApp com Rust puro
1. Lê: **evolution-api-documentation.md** (overview)
2. Implementa: **evolution-api-implementation-guide.md** (Client wrapper)
3. Testa: **evolution-api-quick-reference.md** (comandos cURL)

### Cenário B: Integrar com gRPC (smart-core pattern)
1. Define proto: **evolution-api-grpc-bridge.md** (whatsapp.proto)
2. Implementa serviço: **evolution-api-grpc-bridge.md** (grpc_service.rs)
3. Cliente Flutter: **evolution-api-grpc-bridge.md** (Dart client)

### Cenário C: Debugar problema em produção
1. Verifica autenticação: **evolution-api-documentation.md** → "Autenticação"
2. Consulta erro: **evolution-api-implementation-guide.md** → "Erros Comuns"
3. Procura comando: **evolution-api-quick-reference.md** → "cURL Cheat Sheet"

### Cenário D: Receber webhooks e responder
1. Handler: **evolution-api-implementation-guide.md** → "Tratamento de Webhooks em Axum"
2. Schema BD: **evolution-api-grpc-bridge.md** → "Armazenamento de Tokens em BD"
3. Loop de processamento: **evolution-api-documentation.md** → "Webhooks — Eventos Recebidos"

---

## Checklist de Implementação

### Fase 1: Setup inicial
- [ ] Ler "evolution-api-documentation.md" (30 min)
- [ ] Configurar Evolution API localmente (docker-compose)
- [ ] Testar criar instância via cURL
- [ ] Testar enviar mensagem via cURL
- [ ] Capturar QR code e escanear

### Fase 2: Integração Rust
- [ ] Copiar EvolutionClient do guide
- [ ] Adaptar para seu project (paths, types)
- [ ] Testar create_instance()
- [ ] Testar send_text()

### Fase 3: Webhooks
- [ ] Implementar webhook handler (Axum)
- [ ] Configurar PUT /webhook/set
- [ ] Testar recebimento de MESSAGES_UPSERT
- [ ] Armazenar mensagens em BD

### Fase 4: gRPC (se aplicável)
- [ ] Criar whatsapp.proto
- [ ] Implementar WhatsappService
- [ ] Testar com cliente gRPC local
- [ ] Expor para Flutter

### Fase 5: Produção
- [ ] Configurar HTTPS para webhook
- [ ] Implementar deduplicação
- [ ] Armazenar tokens em .env
- [ ] Configurar logging/monitoring
- [ ] Testar failover
- [ ] Passar checklist pré-deploy

---

## Links Rápidos

| Recurso | URL |
|---------|-----|
| **Repositório oficial** | https://github.com/evolution-foundation/evolution-api |
| **Documentação oficial** | https://docs.evolutionfoundation.com.br/ |
| **Manual de integração** | https://gist.github.com/dantetesta/b8b7e7e2d6196beae968c8b0a61afb7a |
| **Cliente Python** | https://github.com/EvolutionAPI/evolution-client-python |
| **Evolution Go (Go version)** | https://github.com/evolution-foundation/evolution-go |
| **Postman Collection v2.2.2** | https://www.postman.com/agenciadgcode/evolution-api/documentation/jn0bbzv/evolution-api-v2-2-2 |

---

## Estrutura de Arquivos Recomendada no Projeto

```
crates/
├── whatsapp-service/           # Nova crate para Evolution
│   ├── Cargo.toml
│   ├── build.rs                # gRPC build script
│   ├── proto/
│   │   └── whatsapp.proto      # Definição gRPC
│   └── src/
│       ├── lib.rs
│       ├── evolution_client.rs # REST client wrapper
│       ├── grpc_service.rs     # gRPC service impl
│       ├── webhook_handler.rs  # Webhook receiver
│       └── types.rs            # Shared types
│
├── runtime-api/                # Existente
│   └── ... (add WhatsappServiceServer a routes)
│
└── docs/
    └── evolution-api/          # Esta documentação
        ├── EVOLUTION-API-INDEX.md
        ├── evolution-api-documentation.md
        ├── evolution-api-quick-reference.md
        ├── evolution-api-implementation-guide.md
        └── evolution-api-grpc-bridge.md
```

---

## Troubleshooting Rápido

| Problema | Solução |
|----------|---------|
| "Invalid API key" | Verificar qual token está usando (global vs instance) |
| "Instance not found" | Criar instância primeiro com POST /instance/create |
| "Invalid phone number" | Usar formato DDI (5511999999999 — 13 dígitos) |
| "Maximum call stack" | Vídeo > 3MB — usar URL, não base64 |
| Webhook não recebe | Verificar se estado é "open" (GET /instance/connectionState) |
| Duplicação mensagens | Implementar deduplicação por message_id |

---

## Versão e Data

- **Data de documentação:** Junho 2026
- **Evolution API versão:** v2.2.2 e superiores
- **Stack testado:** Node.js 20+, Rust 1.70+, Dart 3.0+

---

## Próximos Passos

1. **Comece aqui:** evolution-api-documentation.md
2. **Implemente:** evolution-api-implementation-guide.md
3. **Reference:** evolution-api-quick-reference.md
4. **Se usar gRPC:** evolution-api-grpc-bridge.md

Sucesso na implementação!

