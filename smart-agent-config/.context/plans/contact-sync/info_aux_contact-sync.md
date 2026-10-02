# Documentação Auxiliar — Sincronização de Contatos

> Gerado em: 2026-10-01
> Plano canônico: `.context/plans/contact-sync.md`
> Plano completo: `.context/plans/contact-sync/plano_completo_contact-sync.md`

## Libs Python

### Pydantic (2.13.5)

**Status:** ✅ ATUALIZADA (verificada em 09-10-2026)
**Fonte:** `doc_dev/libs/python/pydantic.md`

- Validação de tipos em tempo de execução
- Parsing JSON + mapeamento de ambiente
- **API relevante para este plano:**
  - `BaseModel` para DTOs de eventos e contatos
  - `Field(validation_alias=...)` para mapeamento de payloads
  - `ConfigDict(ser_by_alias=True)` para serialização

**Uso:** Validar eventos do webhook, DTOs de Contact/ContactChange.

### gRPC (grpcio 1.83.1)

**Status:** ✅ ATUALIZADA (verificada em 09-06-2026)
**Fonte:** `doc_dev/libs/python/grpcio.md`

- Comunicação cliente-servidor via gRPC (Python ↔ Rust)
- Protobuf + compilação automática de stubs
- **API relevante:**
  - `grpcio` para client/stub
  - `grpcio-tools` para compilação proto
  - Interceptors para auditoria/logging

**Uso:** Cliente gRPC no Python para chamar runtime_api (RPC de contatos).

### httpx (2.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Cliente HTTP assíncrono para Evolution Go API
- Suporta HTTP/2
- Retry automático + timeout
- Headers customizados (auth, content-type)

**APIs a documentar:**
- `AsyncClient` + session management
- `post(url, json={...})` para requisições ao webhook
- Rate limiting / error handling
- SSL/TLS verification

---

## Libs Rust

### Tokio (1.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Async runtime para workers (contact_sync, contact_polling)
- `tokio::spawn` para tarefas de background
- `tokio::time::interval` para polling periódico
- `tokio::sync::mpsc` para canais de eventos

**APIs a documentar:**
- Runtime setup + executor
- Task spawning + cancellation
- Intervals + timeouts
- Error handling em async tasks

### Serde (1.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Serialização JSON de eventos
- Deserialização de payloads do webhook
- Custom serializers (ex.: mascarar telefone)

**APIs a documentar:**
- `#[serde(rename, skip_if)]` para contatos
- Custom `Serialize` + `Deserialize` impls
- De/encoding JSON

### SQLx (0.8.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Queries type-safe com `sqlx::query` + macros
- Migrations (create_contacts_table.sql etc.)
- Transações para conflito detection
- RLS (Row-Level Security) para tenant isolation

**APIs a documentar:**
- `sqlx::query!` vs `sqlx::query` (macros)
- `sqlx::migrate!` para versionamento
- Transaction management (`tx.begin()`)
- Named parameters (`$1`, `$2`)

### Tracing (0.1.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Logs estruturados com spans
- Campos de correlação (tenant_id, trace_id)
- Níveis (DEBUG, INFO, WARN, ERROR)
- Integração com observabilidade (Jaeger/Prometheus)

**APIs a documentar:**
- `#[tracing::instrument]` para funções
- `span!()` + `event!()`
- Field injection (telemetria)
- Sampling / filtering

### Tonic (0.12.x) — *Biblioteca não documentada localmente*

**Status:** Necessário levantamento (Context7)
**Uso esperado:**
- Servidor gRPC em Rust (AdminService)
- Reflection + health checking
- Interceptors para auth/auditoria
- Error codes (Code::InvalidArgument, Code::Internal)

**APIs a documentar:**
- `tonic::transport::Server` setup
- `#[tonic::async_trait]` para service impls
- gRPC error handling / status codes
- Metadata + headers

---

## Serviços Externos

### Evolution Go API (v2.3.x)

**URL Base:** `http://host:8080` (padrão)
**Documentação:** [evolution-foundation.github.io](https://evolution-foundation.github.io) (verificado 2026-10-01)

#### Autenticação
- **Header:** `Authorization: Bearer <apikey>`
  (ou header `apikey` dependendo da versão)
- **Instance:** Cada número de WhatsApp é uma "instance" com seu próprio apikey

#### Endpoints Principais

##### `GET /contacts`
- **Descrição:** Lista todos os contatos da instância
- **Headers:** `Authorization: Bearer {apikey}`
- **Response:**
  ```json
  {
    "data": [
      {
        "remoteJid": "5588987141275@s.whatsapp.net",
        "pushName": "João Silva",
        "name": null,
        "fullName": "João Silva (Celular)",
        "isBusiness": false,
        "isEnterprise": false,
        "businessName": null
      }
    ]
  }
  ```

##### `POST /webhook`
- **Descrição:** Registra um webhook para receber eventos
- **Headers:** `Authorization: Bearer {apikey}`, `Content-Type: application/json`
- **Body:**
  ```json
  {
    "url": "https://seu-dominio.com/webhook/evolution",
    "events": ["MESSAGES", "CONTACTS", "PRESENCE"]
  }
  ```
- **Response:** `{ "webhook": { "url": "...", "status": "connected" } }`

##### Webhook `CONTACT` Event
- **Disparado:** Quando contato é criado/atualizado
- **Payload:**
  ```json
  {
    "data": {
      "instanceId": "instance123",
      "number": "5588987141275",
      "event": "CONTACT",
      "payload": {
        "remoteJid": "5588987141275@s.whatsapp.net",
        "pushName": "João Silva",
        "name": null
      }
    }
  }
  ```

##### `PUT /contacts/{remoteJid}`
- **Descrição:** Atualiza nome/metadados de um contato
- **Headers:** `Authorization: Bearer {apikey}`, `Content-Type: application/json`
- **Body:**
  ```json
  {
    "name": "João Silva (Atualizado)"
  }
  ```

#### Rate Limiting / Limitações
- Rate limit: ~500 requisições/minuto por instância
- Timeout: 30 segundos
- Max payload: 10 MB
- Contatos em cache local (SQLite): max ~100k

#### Erros Comuns
- `401 Unauthorized` → apikey inválido/expirado
- `404 Not Found` → remoteJid não existe
- `429 Too Many Requests` → rate limit atingido (retry após 60s)
- `500 Internal Server Error` → Evolution offline (fallback para polling)

---

## Notas Gerais

### Breaking Changes (2026)
- Evolution Go **v2.2 → v2.3:** Alterou formato de `remoteJid` (agora inclui `@s.whatsapp.net` sempre)
- Pydantic **2.12 → 2.13:** Field validators compatíveis, sem breaking changes
- Tokio **1.39 → 1.40+:** `task::block_in_place` pode exigir ajustes em sync code

### Gotchas
1. **Webhook pode chegar fora de ordem:** Implementar idempotência com UUID do evento
2. **Contato sem telefone em eventos:** Alguns eventos trazem `null` no número; validar sempre
3. **Evolution offline:** Requer polling fallback (DB como source of truth)
4. **Conflito simultâneo:** BD precisa de transações isoladas (SERIALIZABLE)
5. **Sanitização:** Telefone e JID são dados pessoais; usar `SecretString` + mascaramento em logs

### Dependências Críticas
- **Python 3.13+** (conforme padrão RSOE do projeto)
- **PostgreSQL 14+** (transações, RLS)
- **Redis 7+** (para fila de events)
- **Rust 1.80+** (stable)

