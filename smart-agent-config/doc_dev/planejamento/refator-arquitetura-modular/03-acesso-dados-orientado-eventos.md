# 03 — Acesso a Dados: Dois Planos (RPC direto + eventos)

> **Status:** Planejamento (a revisar).
> **Idioma:** pt-br na documentação; identificadores em inglês.
> **Pré-leitura:** [02-camada-contrato-transporte.md](./02-camada-contrato-transporte.md).
> **Base conceitual:** [../../arquitetura/arquitetura-dados-ingestao-eventos.md](../../arquitetura/arquitetura-dados-ingestao-eventos.md).

---

## 1. O padrão (RA1) — dois planos, um contrato

O acesso a dados segue o **padrão de mercado** para um módulo central de dados:
**separar o plano síncrono do assíncrono** e **nunca** rotear leitura por fila.

| Plano | Para quê | Transporte | Codec |
|---|---|---|---|
| **Síncrono — RPC direto** (request/reply) | **leituras** e **escritas com ack imediato** | **UDS** (local) / **TCP/TLS** (VM) — conexão direta | FlatBuffers padrão, gRPC fallback |
| **Assíncrono — barramento** (pub/sub + log durável) | **fire-and-forget**, ingestão em rajada, **eventos de domínio** (fan-out), auditoria, outbox | **Redis Streams** (consumer groups) | FlatBuffers padrão, gRPC n/a |

Três invariantes:

1. **Centralização absoluta.** Só os módulos de infra (`data_postgres`, `data_redis`,
   `data_storage`) tocam o armazém. **Nenhum** outro módulo abre conexão — nem de outra VM.
2. **Redis é buffer/cache — fica fora do caminho de leitura.** Streams é o broker **do
   plano assíncrono**; key/value é cache. Os dois precisam ser rápidos, então **leitura
   nunca passa por fila** (anti-padrão: RPC-sobre-queue adiciona latência e bloqueio).
3. **Contrato único nos dois planos.** Mesmo `Envelope`, mesmos codecs, mesma taxonomia
   de erro. A padronização mora **no contrato**, não em "forçar tudo pela fila".

> **Por que não "tudo como evento":** rotear leitura por Redis Streams paga round-trip e
> head-of-line blocking sem ganho — o mercado não faz isso. O que se padroniza é o
> **contrato**; o **plano** (direto vs bus) é escolhido pela natureza da operação.

---

## 2. Anatomia de um módulo de infra (ex.: `data_postgres`)

Duas portas de entrada, **mesmos processadores**:

```
        ┌─────────────────────────── data_postgres ───────────────────────────┐
 SÍNCRONO (RPC direto)                                                          │
 req ──►│ Server UDS    ┐                                                       │
 req ──►│ Server FlatB  ├─► decode → Envelope ─► HANDLER ─► resposta ──► origem │
 req ──►│ Server gRPC   ┘   (leitura / escrita-com-ack)   │                     │
        │                                                 ▼                     │
        │                                        ┌────────────────┐            │
 ASSÍNCRONO (bus)                                │ PROCESSADORES  │  RLS        │
 evt ──►│ Consumer (Redis Streams) ─► Envelope ─►│ run_in_tenant_ │            │
        │   (ingestão, fire-and-forget)          │ transaction:   │            │
        │                                        │ SELECT/INSERT  │  outbox     │
        │                                        │ + outbox       │            │
        │                                        └───────┬────────┘            │
        │   Relay outbox (LISTEN/NOTIFY) ─► publica eventos de domínio no bus ──┘
        └───────────────────────────────────────────────────────────────────────┘
```

| Estágio | Plano | Responsabilidade |
|---|---|---|
| **Server (×3 protocolos)** | síncrono | Aceita UDS/FlatBuffers/gRPC; decodifica para o `Envelope`; chama o handler; **responde no mesmo protocolo**. Baixa latência (sem fila no meio). |
| **Consumer** | assíncrono | Consome o bus (consumer group); processa fire-and-forget/ingestão; sem resposta direta (efeitos via outbox/eventos). |
| **Processadores** | ambos | Acesso ao banco (repos existentes) em `run_in_tenant_transaction` (RLS); outbox quando muda estado. Plano não muda a regra. |
| **Relay outbox** | assíncrono | `LISTEN/NOTIFY` → publica eventos de domínio (`TicketUpdated`, …) no bus. **Inalterado**. |

> O `data_postgres` é, ao mesmo tempo, **servidor RPC** (plano síncrono) e **consumidor
> do bus** (plano assíncrono). As duas portas caem nos **mesmos** processadores — então a
> regra de negócio/persistência é escrita **uma vez**.

---

## 3. Qual plano para qual operação

| Operação | Plano | Por quê |
|---|---|---|
| **Leitura** (UI pede thread; monitoramento pede auditoria) | **Síncrono (RPC direto)** | precisa de resposta rápida; fila só atrapalha |
| **Escrita com ack** (login, registro de tenant, "salva e me dá o id") | **Síncrono (RPC direto)** | o chamador precisa do resultado na hora |
| **Ingestão em rajada** (mensagens do WhatsApp) | **Assíncrono (bus)** | absorve pico, desacopla, replay, zero-perda |
| **Auditoria / log de segurança** | **Assíncrono (bus)** | fire-and-forget — não pode atrasar a ação auditada |
| **Evento de domínio** (`TicketUpdated` p/ realtime) | **Assíncrono (bus, via outbox)** | fan-out para N consumidores |

> Regra prática: **precisa de resposta? → síncrono direto.** **É efeito colateral
> desacoplado / pode esperar? → bus.** Simples e alinhado ao mercado.

---

## 4. Exemplo (os quatro fluxos do dono, no modelo certo)

```
SÍNCRONO (RPC direto, com resposta)
  monitoring   ─(ler auditoria)──── UDS ───► data_postgres ─► resposta (UDS)
  ia_engine    ─(salvar + ack)───── FlatB ─► data_postgres ─► resposta (FlatB)   [TCP se VM]
  ui/runtime_api─(ler dados)─────── gRPC ──► data_postgres ─► resposta (gRPC)

ASSÍNCRONO (bus, fire-and-forget)
  observability ─(auditoria)─► Redis Streams ─► data_postgres consome ─► grava (durável)
```

- **Monitoramento (leitura)** e **UI (leitura)** → **RPC direto**, resposta no protocolo
  de origem.
- **IA salvando** → **RPC direto** se precisa confirmar a persistência (recebe o id);
  por FlatBuffers (payload grande), TCP se estiver noutra VM — **sempre via `data_postgres`**.
- **Auditoria** → **bus** (fire-and-forget): quem audita **não espera**; o `data_postgres`
  consome e grava durável. (Se um caso específico precisar de confirmação, vira síncrono.)
- Todos **passam pelo `data_postgres`**; ninguém abre conexão própria com o banco.

---

## 5. Contrato único nos dois planos

O mesmo `Envelope` (doc 02 §2) atravessa síncrono e assíncrono — `tenant_id`,
`traceparent`, `message_id`, `error`. O handler/consumer **não muda a regra** conforme o
plano; muda só **de onde a mensagem veio** e **se há resposta**. Os codecs (FlatBuffers
padrão, gRPC fallback) valem para o plano síncrono; o bus usa FlatBuffers no payload do
envelope.

---

## 6. Redis: dois chapéis, governados diferente

| Papel do Redis | Uso | Fora de |
|---|---|---|
| **Streams (broker)** | plano assíncrono: ingestão, eventos de domínio, auditoria, outbox-relay | caminho de leitura síncrona |
| **Key/Value (cache)** | sessão, token, `flow_permissions` (TTL), lock de debounce, rate-limit | persistência durável |

Leitura quente: o `runtime_api` pode consultar o **cache** (`data_redis`, RPC direto)
antes do `data_postgres` (cache-aside) — **isso continua síncrono e direto**, nunca fila.

### 6.1 Quem conecta ao Redis (centralização aplicada por papel)

A regra "só o módulo de infra toca o armazém" vale para o **cache/dados**, mas **não**
para o **bus** — porque o bus é *canal de transporte*, não um dado que se consulta.

| Papel | Quem abre conexão | Como | Centralizado por |
|---|---|---|---|
| **Bus (Streams)** | qualquer módulo | **biblioteca de bus** (`transport`), conexão direta ao Streams | é transporte — como abrir um socket; proxiar um broker mata fan-out/consumer-group |
| **Cache / dados** (key-value, token, lock, rate-limit, presença) | **só o `data_redis`** | os demais chamam o `data_redis` por **RPC direto (UDS)** | `data_redis` (normaliza, namespace por tenant, observabilidade num lugar só) |

**Aplicado à IA:**
- A IA é **request/reply** (o `worker` chama, ela responde). No caso comum **só abre o
  canal RPC** — nada de cache nem bus diretos.
- Se a IA precisar de **cache** (ex.: dedup, embeddings), chama o `data_redis` por
  transporte (UDS), que **normaliza e grava** — **sem** conexão de cache própria, mesmo
  co-localizada (o salto UDS local custa dezenas de µs).
- **Topologia/segurança:** com o cache centralizado, o Redis fica acessível **só pelo
  `data_redis`**. Se a IA for para uma **VM com GPU**, ela **não enxerga o Redis** — só
  abre o canal RPC para a VM do app. Acesso direto exporia o Redis pela rede.

> **Escape hatch (documentado):** se um caminho for tão quente que nem o salto UDS ao
> `data_redis` caiba, libera-se — **com medição** — um cliente de cache **somente-leitura**
> direto, como exceção registrada. O padrão é sempre via `data_redis`.

---

## 7. Os outros módulos de infra

### 7.1 `data_redis` (cache / token / lock / presença)
Servidor RPC (3 protocolos) para get/set/exists/lock — **plano síncrono**. Reaproveita a
`infrastructure_redis` (papel cache). O papel **bus** (Streams) é do `transport`.

### 7.2 `data_storage` (mídia R2/MinIO)
Servidor RPC para `put`/`get`/`presign` (síncrono); `purge` por **evento** (assíncrono).
Reaproveita a `infrastructure_storage`.

---

## 8. O que muda na prática

| Aspecto | Antes (chamada direta) | Agora (dois planos, centralizado) |
|---|---|---|
| Quem toca o banco | qualquer crate | **só o `data_postgres`** (RA1) |
| Leitura | função de repositório | **RPC direto** ao `data_postgres` (UDS/FlatB/gRPC) |
| Escrita com ack | função síncrona | **RPC direto** (escrita + resposta) |
| Ingestão/efeito desacoplado | task Celery | **bus** (Redis Streams) → `data_postgres` consome |
| Eventos de domínio | — | **outbox → bus** (fan-out) |
| Redis no caminho de leitura | — | **nunca** (buffer/cache, rápido) |
| Isolamento de tenant / outbox | RLS no repo | **igual** — dentro do `data_postgres` |

---

## 9. Decisões em aberto (para a revisão)

1. **Auditoria sempre assíncrona (bus)** (recomendado) vs permitir auditoria síncrona em
   casos que exijam confirmação. — relaciona com [04 §9](./04-transversais-erro-observabilidade.md).
2. **Granularidade dos `method`**: por agregado (`GetThread`, `PersistMessage`,
   `UpsertContact`), nomes de domínio. Recomendo **por agregado**.
3. **Cache-aside no `runtime_api`** (consulta `data_redis` antes do `data_postgres`):
   padronizar já ou só onde medir gargalo. Recomendo **só onde medir**.
4. **Read-model/projeções (CQRS completo)** — fora de escopo agora.

---

## 10. Próximo documento

O padrão **agnóstico de erro e observabilidade** (envelope canônico, 3 sinks, os dois
exemplos do dono): [04-transversais-erro-observabilidade.md](./04-transversais-erro-observabilidade.md).

---

*Acesso a dados em dois planos. Sujeito a refinamento.*
