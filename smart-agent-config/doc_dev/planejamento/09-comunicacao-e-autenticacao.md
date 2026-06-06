# 09 — Comunicação Front↔Back, IPC e Encaixe da Autenticação

> **Status:** ✅ Concluída (Fase 0 e Fase 1). Arquitetura de transporte unificada (IPC por UDS/FlatBuffers + gRPC fallback) e autenticação de sessão distribuída implementada.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Consolidação pós-refatoração modular.

---

## 1. Topologia de Transporte de Dados

Na arquitetura modular reestruturada, a comunicação de dados ocorre em dois níveis distintos:

### 1.1 Comunicação Interna (IPC/RPC Local) — UDS & FlatBuffers
* **Protocolo**: Unix Domain Sockets (UDS) como transporte de baixíssima latência na máquina Hostinger.
* **Codec**: FlatBuffers como formato de serialização padrão para chamadas RPC aos microsserviços `data_*`.
* **Fallback**: gRPC sobre TCP configurável em tempo de execução para ambientes distribuídos ou depuração.
* **Mecanismo**: A crate `crates/transport` gerencia os clientes e servidores tipados que se comunicam através da serialização automatizada provida por `contracts`.

### 1.2 Comunicação Externa (Front↔Back) — gRPC & Streaming Realtime
* **Request-Response**: O cliente (Flutter) consome a `runtime_api` via HTTP/2 (gRPC padrão/Tonic). O gRPC-Web é suportado com proxy reverso (Nginx/Caddy) traduzindo chamadas para suporte do Flutter Web.
* **Realtime**: Padronizado em **gRPC Server Streaming**, onde o cliente abre canais persistentes (ex: `StreamAtendimentos`) e o servidor envia eventos em tempo real propagados internamente via Redis Streams (`transport::bus`).

---

## 2. JWT & Gerenciamento de Sessão

O sistema de autenticação opera de forma distribuída, desacoplando o servidor de APIs (`runtime_api`) e os serviços de armazenamento de dados síncronos (`data_redis`).

### 2.1 Estrutura de Metadados e o `Envelope`
Em vez de trafegar claims de segurança abertamente entre as APIs locais, o contexto de segurança validado no middleware da `runtime_api` é injetado no **`Envelope`** de transporte unificado:

O `Envelope` é definido em `contracts/schemas/envelope.proto` (gRPC + FlatBuffers). Campos
relevantes para o transporte do contexto de segurança:

```text
Envelope {
  tenant_id:      string   // UUID do tenant validado no interceptor
  schema_version: uint32   // versão do schema (evolução aditiva)
  message_id:     string   // UUIDv7 — ordenável e idempotente
  causation_id:   string   // id da mensagem que causou esta
  traceparent:    string   // W3C TraceContext (trace distribuído)
  occurred_at:    int64    // epoch em milissegundos
  kind:           MessageKind  // REQUEST | REPLY | EVENT | STREAM_ITEM | ERROR
  method:         string   // nome lógico do RPC (ex.: "GetThread")
  payload:        bytes    // corpo FlatBuffers (opaco ao transporte)
  error:          ErrorEnvelope  // só quando kind = ERROR
}
```

O `tenant_id` e as permissões de escopo (`scopes`) e fluxo (`flow_permissions`) são cacheados no Redis local via RPC ao `data_redis` com TTL curto (60 segundos).

### 2.2 Rotação de Refresh Tokens e Blocklist (via `data_redis`)
1. **Access Token (JWT)**: Vida útil de 15 minutos, stateless, verificado localmente.
2. **Refresh Token (Opaque)**: Token randômico de 32 bytes validado exclusivamente via RPC contra o microserviço `data_redis`. O `data_redis` gerencia de forma atômica a rotação de família de tokens e a detecção de reuso fraudulento.
3. **Logout & Invalidação**: O JWT correspondente tem seu identificador (`jti`) inserido na blocklist do Redis pelo tempo de expiração restante, e a família de refresh tokens é expurgada do `data_redis`.

---

## 3. Defesa em 3 Camadas e RLS

A segurança e o isolamento de dados são reforçados a cada chamada de banco:

```
[Cliente] --> |JWT gRPC Metadata| 1. Middleware Runtime API (Valida JWT e extrai Tenant)
                                   v
[Contratos UDS] ----------------> 2. Injeta RequestContext no Envelope (UDS / RPC)
                                   v
[PostgreSQL] -------------------> 3. SET LOCAL app.current_tenant = tenant_id (RLS PostgreSQL)
```

1. **Camada 1 (Interceptor gRPC)**: Valida a assinatura do token, checa a blocklist no `data_redis`, carrega escopos e monta o `RequestContext`.
2. **Camada 2 (Contratos IPC)**: Ao invocar os serviços de persistência (`data_postgres`), a `runtime_api` ou o `worker` envelopa a requisição com o `tenant_id` validado e o `traceparent`.
3. **Camada 3 (Postgres RLS)**: O microsserviço `data_postgres`, ao receber a chamada e abrir uma transação no pool de conexões SQLx, define obrigatoriamente a variável de sessão `app.current_tenant`, forçando o PostgreSQL a filtrar todas as queries via Row-Level Security.

---

## 4. Variáveis de Ambiente de Segurança

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `JWT_SECRET` | ✅ | — | Chave de assinatura criptográfica HMAC-SHA256. |
| `S3_ACCESS_KEY_ID` | ✅ | — | Credenciais S3 (R2/MinIO) consumidas pelo `data_storage`. |
| `DATABASE_ADMIN_URL` | ✅ | — | Conexão com privilégios de bypass RLS para autenticação inicial. |
| `REDIS_URL` | ✅ | — | String de conexão com o Redis de cache e barramento. |

---

## 5. Próximos Passos

A infraestrutura de transporte local (IPC UDS FlatBuffers), serialização e a segurança por RLS com contexto integrado no `Envelope` estão concluídas e validadas. A implementação do frontend Flutter deve configurar interceptores gRPC compatíveis com o formato do `Envelope` para autenticação.


