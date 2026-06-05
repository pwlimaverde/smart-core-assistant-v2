# 05 — Plano de Refator do Estado Atual

> **Status:** Planejamento (a revisar). É o **"refator duro" planejado** que o dono pediu
> para ver **antes** de tocar no código (RA7).
> **Idioma:** pt-br na documentação; identificadores em inglês.
> **Pré-leitura:** docs [01](./01-visao-arquitetura-modular-contrato.md)–[04](./04-transversais-erro-observabilidade.md).

---

## 1. Inventário do que existe hoje (`server/`)

**Workspace real:** **5 crates**, **sem `apps/`** e **sem `contracts`/`application`**.
Migrations **0001–0010** (a `0010` é `audit_log`). `tonic 0.14.6` já no workspace; **sem
`flatbuffers`/`prost`/`tonic-build`** ainda.

| Componente | Estado real | Destino no refator |
|---|---|---|
| `infrastructure_postgres` | ✅ migr. **0001–0010** (incl. `audit_log`), RLS, `crypto`, `auth`, `security` (`RequestContext`), `config_cache`, domínios + módulo **`auditoria/`** (`inserir_audit_log`) | **lib interna do serviço `data_postgres`** |
| `infrastructure_redis` | ✅ **bus** (Streams + consumer groups + `TenantEnvelope`), **cache** (`CachePermissoes`), **auth_tokens** (refresh+blocklist), `keys` (namespacing). Já declara *"ÚNICA crate que usa Redis diretamente"* | **dividida**: cache/token → `data_redis`; bus → `transport::bus` |
| `observability` | ✅ tracing JSON, **OTLP** (grpc-tonic), **`propagation`** (W3C trace context), **`AuditLogger`**. **Depende de `infrastructure_postgres`** | **permanece convenção**; ganha `traceparent` no envelope; auditoria **rewired** p/ Redis Streams (RF1) |
| `error_core` | ✅ `ErrorCode`/`ErrorCategory`/`Severity`/`AppError`/`report`; **`transport::to_status` atrás da feature `grpc`** (codec plugável **já em prática**); `public_message()` | **permanece convenção**; ganha `ErrorEnvelope` serializável + campos novos |
| `test_support` | ✅ túnel SSH + reset DB nos testes | mantém; ganha fixtures de transporte (UDS em tmp) |
| `contracts` | ⬜ **não existe** | **criar**: schemas `.fbs` canônicos → `.proto` gerado; envelope; tipos gerados |
| `application` | ⬜ **não existe** | **criar**: casos de uso falando pelo contrato |
| `apps/*` (`data_*`, `runtime_api`, `worker`, …) | ⬜ **não existem** | **criar** como serviços por contrato |

> **Correção vs planos anteriores:** `contracts`/`application`/`runtime_api` apareciam como
> "🚧 em andamento" — **não há código** deles (o auth está só na fase P). Logo, **nascem já
> no padrão novo**; não há o que refatorar neles.

### 1.1 O que o refator REAPROVEITA (de-risk — é mais *rewire* que *rewrite*)

O estado atual **já antecipa** boa parte do alvo:

| Alvo | Já existe hoje | Falta |
|---|---|---|
| Convenção de erro como lib + **codec plugável** | `error_core` com taxonomia + `transport.rs` **atrás da feature `grpc`** | `ErrorEnvelope` serializável (cross-wire) + `user_message`/`fallback`/`retryable`/`source_svc`; estender categorias (Permission/RateLimit/Timeout/Dependency) com a **disciplina de deprecação já documentada** no `code.rs` |
| Trace distribuído | `observability::propagation` (W3C) + OTLP (grpc-tonic) | campo `traceparent` no envelope + coletor OTLP subindo cedo |
| Bus de eventos | `infrastructure_redis::event_bus` (Streams + `TenantEnvelope`) | mover para `transport::bus`; `TenantEnvelope` migra p/ `contracts` |
| Centralização do Redis | regra **já escrita** ("ÚNICA crate que usa Redis") | embrulhar em `data_redis` (serviço) |
| Auditoria durável | tabela `audit_log` (migr. 0010) + `inserir_audit_log` + `AuditLogger` | **rewire**: intake passa de "gravação direta async" → **Redis Streams → consolida** (decisão doc 04) |
| Persistência + RLS + crypto + auth | `infrastructure_postgres` completo | embrulhar em `data_postgres` (servidor RPC + consumidor) |

> **Implicação boa:** mover a auditoria para Redis Streams **remove** a dependência
> `observability → infrastructure_postgres` — o `AuditLogger` passa a **publicar no bus**
> (que `infrastructure_redis` já sabe fazer) em vez de gravar no banco, deixando a
> convenção `observability` mais limpa (sem I/O de banco). O consumidor de consolidação
> **reusa `inserir_audit_log`** + a tabela `audit_log` existente.

---

## 2. Alvo (depois do refator)

```
server/
├── crates/                      # CONVENÇÕES (bibliotecas, não processos)
│   ├── contracts/               # schemas .fbs/.proto + envelope + tipos gerados
│   ├── transport/               # codec (FB/gRPC) + canal (UDS/TCP/WS) + bus + runtime
│   ├── error_core/              # taxonomia + ErrorEnvelope (convenção)
│   ├── observability/           # tracing + traceparent (convenção)
│   ├── infrastructure_postgres/ # repos/RLS/migr — lib interna do serviço data_postgres
│   ├── infrastructure_redis/    # papel cache/token — lib interna do serviço data_redis
│   ├── infrastructure_storage/  # mídia — lib interna do serviço data_storage
│   ├── application/             # casos de uso (RPC direto + eventos pelo contrato)
│   └── test_support/
└── apps/                        # SERVIÇOS (processos por contrato)
    ├── data_postgres/           # servidor RPC (3 protocolos) + consumidor do bus → processa (RLS) + outbox relay
    ├── data_redis/              # cache/token/lock/presença (req/reply)
    ├── data_storage/            # put/get/presign (req/reply) + purga (evento)
    ├── messaging_gateway/       # ingestão → publica eventos
    ├── worker/                  # orquestra domínio
    ├── runtime_api/             # borda do cliente (FlatBuffers; gRPC fallback)
    └── control_plane/           # back office
```

> ✅ **Decisão — manter os nomes `infrastructure_*`.** Os nomes continuam precisos (são
> os adaptadores de infra) e evitam churn. O par fica claro: o **app `data_postgres`**
> depende da **lib `infrastructure_postgres`**; idem redis/storage.

---

## 3. Sequência do refator (faseada, de baixo risco para alto)

A ordem segue "fundação de transporte primeiro, depois embrulhar serviços, por fim
flipar a aplicação". Cada fase compila e tem testes verdes antes da próxima.

### RF0 — Camada de contrato/transporte (fundação) — **criar do zero**
- **Criar** a crate `contracts`: schemas `.fbs` canônicos (envelope, eventos, queries,
  `errors`) + **`build.rs`** que gera o `.proto` (subconjunto comum, `id:` explícito) e
  roda `flatc`/`tonic-build`. **Migrar o `TenantEnvelope`** de `infrastructure_redis` p/ cá.
- **Criar** a crate `transport`: codec **FlatBuffers** (padrão) + canal **UDS** +
  framing/runtime (mux/keepalive/reconexão/stream) + `transport::bus` **reaproveitando o
  `event_bus`** de `infrastructure_redis`. **gRPC plugável** desde já.
- **Dependências novas no workspace:** `flatbuffers`, `prost`, `tonic-build` (`tonic` já
  existe). 
- **DoD:** ping req/reply e um evento round-trip por UDS (envelope tenant+trace); `.proto`
  gerado do `.fbs` compila; codec comutável FlatBuffers↔gRPC no mesmo `method`.

### RF1 — Transversais ganham a fronteira — **estender/rewire, não criar**
- `error_core` (já tem taxonomia + `transport.rs`/feature `grpc`): adicionar
  `ErrorEnvelope` **serializável** + `to_error_envelope`/`from_envelope`; **estender**
  `ErrorCategory`/`ErrorCode` (Permission/RateLimit/Timeout/Dependency) e os campos
  `user_message` (chave i18n)/`user_message_fallback`/`retryable`/`source_svc` — gerados do
  schema (doc 02 §1), respeitando a disciplina de deprecação já no `code.rs`.
- `observability` (já tem `propagation` W3C + OTLP): ligar o `traceparent` ao `Envelope`
  do `contracts`; **subir o coletor OTLP cedo**; validar trace distribuído em 2 processos.
- **Auditoria — rewire (decisão doc 04):** o `AuditLogger` passa a **publicar no Redis
  Streams** (em vez de gravar direto); um **consumidor de consolidação** lê em batch e
  chama `inserir_audit_log` (tabela `0010` reusada). Isso **remove** a dependência
  `observability → infrastructure_postgres`.
- **DoD:** erro do processo B chega ao A como `ErrorEnvelope` → `AppError` equivalente; um
  trace cobre os 2 processos; `login_failed` percorre Redis Streams → `audit_log`.

### RF2 — `data_postgres` como serviço (dois planos)
- Novo app `apps/data_postgres` que **embrulha** a `infrastructure_postgres`
  com a anatomia do [doc 03 §2](./03-acesso-dados-orientado-eventos.md):
  - **Servidor RPC** nos 3 protocolos (UDS, FlatBuffers, gRPC) → decode em `Envelope` →
    handler → **resposta no mesmo protocolo**. Atende leitura e escrita-com-ack (síncrono).
  - **Consumidor do bus** (Redis Streams) → ingestão/fire-and-forget (assíncrono).
  - **Processadores** comuns aos dois planos (`run_in_tenant_transaction` → repos
    existentes → outbox).
  - **Relay** outbox (`LISTEN/NOTIFY`) → publica eventos de domínio no bus.
- **DoD:** ler e escrever um agregado simples (ex.: contato) por **RPC direto** nos três
  protocolos (RLS ativo, resposta na origem) **e** um fluxo assíncrono pelo bus;
  isolamento multi-tenant revalidado.

### RF3 — `data_redis` e `data_storage` como serviços
- `apps/data_redis` embrulha o papel cache/token da `infrastructure_redis` (req/reply).
- O papel **bus** sai da `infrastructure_redis` e passa para `transport::bus`.
- `apps/data_storage` embrulha a `infrastructure_storage` (put/get/presign; purga por evento).
- **DoD:** cache get/set e presign por req/reply; bus operando pelo `transport`.

### RF4 — Flipar a `application` para o contrato
- Casos de uso deixam de chamar repositórios direto; passam a falar com o `data_postgres`
  pelos clientes tipados do `transport`: **RPC direto** para leitura/escrita-com-ack,
  **bus** para efeitos assíncronos ([doc 03 §3](./03-acesso-dados-orientado-eventos.md)).
- Auth (Register/Login/Refresh/Accept) é **RPC direto (escrita-com-ack)** — a borda
  recebe a resposta (tokens/erro) na mesma chamada. Erros seguem o padrão do
  [doc 04](./04-transversais-erro-observabilidade.md) (log+auditoria+propagação).
- **DoD:** o fluxo de auth roda fim-a-fim via contrato (sem chamada direta a repo); senha
  errada gera log + auditoria + `user_message` na UI.

### RF5 — `runtime_api` no padrão FlatBuffers + borda do cliente
- `runtime_api` serve **FlatBuffers** (req/reply + stream) por TCP/TLS (desktop) e
  **WebSocket binário** (web), conforme RA6. gRPC fica como fallback comutável.
- Realtime (`StreamAtendimentos`) sobre o framing de stream do `transport`.
- **DoD:** login e um stream de realtime funcionam por FlatBuffers; fallback gRPC
  comutável por config sem mudar handlers.

### RF6 — Demais serviços de domínio
- `messaging_gateway`, `worker`, `control_plane` nascem/migram já como serviços por
  contrato. `ia_engine` (Python) entra com codec FlatBuffers (gRPC fallback) — pronto
  para a VM com GPU (doc 01 §4.1).
- **DoD:** mensagem do webhook → worker → data_postgres → realtime, tudo por contrato.

---

## 4. Tratamento especial das convenções (erro/observabilidade) no refator

Reafirmando o que o dono pediu, e como o plano honra isso:

- `error_core` e `observability` **não ganham app** em nenhuma fase. Continuam crates.
- O trabalho nelas (RF1) é **expor o formato de fronteira** (`ErrorEnvelope`,
  `traceparent`) — que é **dado**, compilado nos dois lados — e **rewire da auditoria**
  para o bus (o que ainda **remove** a dependência `observability → infrastructure_postgres`,
  deixando a convenção mais limpa).
- Quando qualquer serviço for para outra VM (RF5/RF6+), **nada** nessas convenções muda:
  a lib já está compilada no serviço; o coletor OTLP já junta os traces. Ver doc 04 §3.

---

## 5. Coordenação com o auth — ✅ RESOLVIDO: fundação antes

**Estado real:** o auth (`user-auth-module`) está só com a **fase de planejamento (P)** —
**não há código** (os crates `contracts`/`application`/`runtime_api` ainda não existem;
não há `apps/`). Logo, "pausar" não custa nada.

**Decisão:** fazer **RF0–RF1 (fundação de transporte + convenções de erro/observabilidade)
antes** de implementar o auth, que já nasce no padrão novo — **RPC direto (escrita-com-ack)
sobre FlatBuffers/UDS** + envelope de erro (log/auditoria/propagação). Evita escrever o
auth duas vezes. A opção de escrevê-lo no modelo antigo e refatorar depois fica
descartada (não há código a aproveitar).

---

## 6. Codec na fundação — ✅ RESOLVIDO: FlatBuffers-first sobre UDS

**Decisão do dono:** construir a **runtime de transporte própria** (framing, mux,
keepalive, reconexão, streaming — doc 02 §5) **desde o RF0**, com **UDS como canal
padrão** e **FlatBuffers como codec padrão**. Implicações para o plano:

- **RF0** entrega a runtime FlatBuffers-sobre-UDS **e já deixa o gRPC como codec
  alternativo plugável** (mesma abstração, trocável por config) — todo módulo nasce
  **preparado para os três protocolos** (UDS/FlatBuffers padrão; gRPC e TCP/WebSocket
  prontos para o split-VM), conforme RA3/RA4.
- **Custo assumido:** a parte pesada (reconexão/keepalive/mux/stream) é construída
  primeiro, antes das features. Mitigação: o gRPC fica disponível como **fallback** desde
  o RF0, então qualquer módulo que esbarre num entrave do FlatBuffers comuta por
  configuração sem refator.
- **Gatilho do fallback (doc 02 §5):** se um recurso da runtime ficar caro/instável para
  um módulo específico, vira o codec dele para **gRPC** (`…_CODEC=grpc`) — contrato e
  aplicação intactos.

---

## 7. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Construir a runtime de transporte (FlatBuffers-first) é trabalhoso | Atraso na fundação | gRPC disponível como **fallback** desde o RF0 (§6); FlatBuffers incremental nos quentes |
| Consistência eventual surpreende a UI | Bugs de "li antes de escrever" | **RPC direto (escrita-com-ack)** p/ leitura/auth (doc 03 §3); UI reage a eventos de domínio |
| Transpile `.fbs`→`.proto` falha em mensagem exótica | Build quebra | subconjunto comum + `id:` explícito (doc 02 §1); escape hatch: `.proto` à mão por mensagem |
| Overhead operacional de N processos | Complexidade de deploy | supervisão (compose/systemd) + OTLP cedo; doc 10 atualizado |
| Auth | (sem código ainda — risco baixo) | fundação antes do auth (§5); nasce já no padrão novo |

---

## 8. Definition of Done global do refator

- [ ] `transport` + `contracts` com envelope (tenant+traceparent+erro) e codec comutável.
- [ ] `error_core`/`observability` **permanecem libs**; fronteira por envelope; trace
      distribuído provado em 2 processos.
- [ ] `data_postgres`/`data_redis`/`data_storage` operando como serviços por contrato
      (RPC direto p/ leitura/escrita-com-ack; bus p/ assíncrono), RLS e outbox preservados.
- [ ] `application` sem chamada direta a repositório; auth via **RPC direto (escrita-com-ack)**.
- [ ] `runtime_api` FlatBuffers (desktop+web) com gRPC fallback comutável.
- [ ] Promoção de um serviço a `tcp://` validada só por config (ensaio com `ia_engine`).
- [ ] Lint/test por stack verdes; comentários pt-br; sem segredos.

---

## 9. O que falta para fechar o planejamento

As **decisões grandes e menores estão fechadas** (dois planos; FlatBuffers-first/UDS;
schema único `.fbs`→`.proto` no build; `ErrorCode` do schema; auditoria via Redis
Streams→consolida; `user_message` i18n; mTLS entre VMs; WebSocket; OTLP cedo; fundação
antes do auth; manter nomes `infrastructure_*`). O passo final é **canonizar** este
conjunto via `plan-restructuring` em `.context/plans/` e **atualizar os docs `00`–`10`**
conforme o mapa de impacto do [00-indice.md §4](./00-indice.md).

---

*Plano de refator do estado atual. Sujeito a refinamento e canonização.*
