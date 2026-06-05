# 01 — Visão: Módulos como Serviços por Contrato

> **Status:** Planejamento (a revisar). Documento de visão da nova arquitetura.
> **Idioma:** pt-br na documentação; identificadores em inglês.
> **Pré-leitura:** [00-indice.md](./00-indice.md).

---

## 1. A ideia central

Cada **módulo** do sistema é um **serviço** (processo) com uma **fronteira de
contrato**. Ninguém chama ninguém por função direta cruzando a fronteira; todos
conversam por **mensagens tipadas** sobre um **transporte plugável**.

```
        ┌─────────────────────── FRONTEIRA = CONTRATO ───────────────────────┐
        │                                                                     │
  [ Módulo A ] ──(envelope tipado)──► [ Transporte ] ──► [ Módulo B ]         │
        │            FlatBuffers          UDS local              │            │
        │            (ou gRPC)            ou TCP/TLS              │            │
        └─────────────────────────────────────────────────────────────────────┘
```

Três eixos **independentes** compõem cada fronteira:

| Eixo | Opções | Quem decide |
|------|--------|-------------|
| **Padrão de interação** | Evento (escrita, assíncrono) · Request/Reply (leitura, síncrono) · Stream (push) | A natureza da operação (RA1). |
| **Codec** | **FlatBuffers** (padrão) · gRPC/Protobuf (fallback) | Por módulo; default FlatBuffers (RA3). |
| **Canal** | **UDS** (mesma máquina) · TCP/TLS (outra VM) · WebSocket (web) | Configuração de deploy (RA4). |

A combinação é livre: `{Evento|ReqReply|Stream} × {FlatBuffers|gRPC} × {UDS|TCP|WS}`.
Mudar de host = mudar **canal** (config). Contornar entrave = mudar **codec** (config + schema). **O padrão de interação e o código de aplicação não mudam.**

---

## 2. Topologia de serviços

### 2.1 Serviços de borda e domínio (já previstos, agora processos por contrato)

| Serviço | Papel | Interações típicas |
|---|---|---|
| `messaging_gateway` | Ingestão de webhooks Evolution | **publica eventos** (escrita bruta + `MessageReceived`) |
| `worker` | Orquestração de domínio | **consome eventos**; faz **leituras/escritas-com-ack** (RPC direto) e **escritas assíncronas** (bus); chama `ia_engine` |
| `runtime_api` | Borda do cliente Flutter | **req/reply** + **stream** para o app; read-queries; emite comandos |
| `control_plane` | Back office (tenants/planos) | req/reply + comandos síncronos |
| `ia_engine` | IA (Python) | **req/reply** (e stream) — candidato nº 1 a VM dedicada (GPU) |

### 2.2 Serviços de acesso a dados (novidade do RA2 — antes eram crates in-process)

| Serviço | Dono de | Plano síncrono (RPC direto) | Plano assíncrono (bus) |
|---|---|---|---|
| `data_postgres` | PostgreSQL (pool, RLS, migrations) | **leitura** + **escrita-com-ack** (resposta na hora) → transação ACID | **ingestão/rajada**, eventos de domínio (**outbox**), auditoria |
| `data_redis` | Redis como **cache/token/lock/presença** | get/set/exists/lock (rápido) | invalidações fire-and-forget |
| `data_storage` | R2/MinIO (mídia) | put/get/**presign** | **purge** (retenção) |

> **Centralização absoluta (RA1):** os `data_*` são os **únicos** a abrir conexão com o
> armazém — qualquer módulo, **inclusive em outra VM**, acessa **através** deles. O acesso
> segue **dois planos** (padrão de mercado): **RPC direto** para leitura e escrita-com-ack;
> **bus** para fire-and-forget/ingestão/eventos/auditoria. **Leitura nunca passa por
> fila** (Redis é buffer/cache, fica fora do caminho de leitura). Detalhe em
> [03](./03-acesso-dados-orientado-eventos.md) §1.

> **Ancoragem (RA2):** os `data_*` **não migram** — ficam colados ao seu armazém. O
> exemplo da VM com GPU (§4) move o **`ia_engine`**, não o `data_postgres`; a IA continua
> gravando/lendo **pelo** `data_postgres` (agora por TCP).

> O **event bus** (Redis Streams) **não** é um "serviço de dados": é o **substrato de
> transporte** do modo *Evento* do contrato (ver [02](./02-camada-contrato-transporte.md) §4).
> `data_redis` cuida do Redis no papel de **cache/sessão**, não do papel de bus.

### 2.3 Convenções transversais (NÃO são serviços — RA5)

`error_core`, `observability` e `contracts`/`transport` são **bibliotecas** compiladas
**dentro de cada serviço**. Elas definem a *linguagem comum* de erros, telemetria e
schemas. Detalhe e justificativa em [04-transversais-erro-observabilidade.md](./04-transversais-erro-observabilidade.md).

---

## 3. Foto grande (mesma máquina — fase atual)

```
                         Evolution Go ──webhook──►  messaging_gateway
                                                          │ publica evento
                                                          ▼
   Flutter ─FlatBuffers/TCP|WS─► runtime_api          [ EVENT BUS ]  (Redis Streams)
                  ▲  stream            │  req/reply         │  escritas assínc. / eventos
                  │                    │                    ▼
                  └─── eventos ◄───────┤               worker (orquestra domínio)
                                       │                 │      │
                  RPC direto (FlatBuffers / UDS)         │      │ RPC direto (FB|gRPC / UDS)
                  ┌────────────────────┼─────────────────┘      ▼
                  ▼                    ▼                      ia_engine (Python)
            data_redis           data_postgres ◄─ escritas assínc. (bus) ─┐
            (cache/token)        (RLS, outbox) ─ outbox→eventos ──────────┘
                  │                    │  req/reply
                  ▼                    ▼
               Redis             PostgreSQL              data_storage ──► R2 / MinIO
```

Tudo em **UDS** (`unix:///var/run/smartcore/<svc>.sock`). Cópia direta na RAM, sem TCP.

---

## 4. Foto grande (escala horizontal — quando precisar)

Promover um serviço a outra VM é **trocar o endpoint** dele de `unix://` para
`tcp://` (TLS) — nos **dois lados** que conversam com ele. Nada no código muda.

```
        VM 1 (app)                                  VM 2 (GPU)
  ┌───────────────────────┐                  ┌────────────────────┐
  │ runtime_api  worker   │  FlatBuffers     │   ia_engine        │
  │ data_postgres ...     │  /TCP/TLS  ◄────►│   (CUDA / modelo)  │
  └───────────────────────┘                  └────────────────────┘
   SMARTCORE_IA_ENGINE_ENDPOINT=tcp://ia.interno:7050   (antes: unix:///…/ia.sock)
```

### 4.1 Exemplo trabalhado — `ia_engine` numa VM com placa de vídeo

Cenário do dono: processar IA num servidor local com GPU. Passo a passo:

1. **Hoje (mesma VM):** `worker` fala com `ia_engine` por **FlatBuffers/UDS**.
   Config: `SMARTCORE_IA_ENGINE_ENDPOINT=unix:///var/run/smartcore/ia.sock`.
2. **Promove para VM com GPU:** sobe o `ia_engine` na VM 2, abre a porta, configura
   TLS. Muda **só a env** no `worker`:
   `SMARTCORE_IA_ENGINE_ENDPOINT=tcp://ia.interno:7050` + cert.
   **Código do `worker` e do `ia_engine`: zero alteração.**
3. **Codec:** mantém **FlatBuffers** (payloads de IA são grandes — embeddings,
   histórico — e o zero-copy brilha aqui). 
4. **Se houver entrave no FlatBuffers** (ex.: precisa de *client streaming*
   bidirecional maduro, reconexão automática, ou o time Python prefere stubs
   gerados): troca o **codec** desse serviço para **gRPC** —
   `SMARTCORE_IA_ENGINE_CODEC=grpc` — sem tocar nos demais serviços. O contrato
   (mensagens) é o mesmo; só a serialização/stub muda. Ver
   [02 §3](./02-camada-contrato-transporte.md) (fonte única de schema gera os dois).

> É exatamente o que o dono pediu: *"por padrão FlatBuffers; se tiver entrave, gRPC,
> sem mudar todo o padrão do projeto"*. O "padrão" (contrato + interação) é estável;
> codec e canal são parâmetros.

---

## 5. Regras de acoplamento (revisadas)

| Regra | Antes (monólito modular) | Agora (serviços por contrato) |
|---|---|---|
| Comunicação entre módulos | import de crate / chamada de função | **mensagem tipada pelo contrato** (evento ou req/reply) |
| Acesso ao banco | `application` chama repositório direto | **sempre via `data_postgres`** (centralizado, RA1); leitura e escrita-com-ack por **RPC direto**; assíncrono por **bus** |
| Quem abre conexão com o banco | qualquer crate via `infrastructure_postgres` | **só o `data_postgres`** — ninguém mais, nem de outra VM |
| Mover módulo de host | reescrever fronteira | **trocar endpoint na config** (exceto `data_*`, que são âncora e não movem) |
| Contornar limitação de transporte | — | **trocar codec na config** (FB→gRPC) |
| Erro/observabilidade | crate compartilhada | **continua crate compartilhada** (convenção, não serviço) |
| `tenant_id` em toda mensagem | envelope no Redis | **envelope do contrato** carrega `tenant_id` em **todo** transporte |

---

## 6. O que ganhamos e o que custamos

**Ganhos**
- Escala horizontal por **configuração**, não por reescrita.
- Isolamento de falha real (um serviço cai sem derrubar os outros).
- Escolha de codec por módulo (zero-copy onde importa; gRPC onde for prático).
- Fronteiras testáveis em isolamento (contrato é o teste de borda).

**Custos (assumidos conscientemente — projeto no início, RA7)**
- O FlatBuffers-sobre-socket **não traz de graça** o que o HTTP/2 do gRPC traz:
  reconexão, keepalive, multiplexação, controle de fluxo. Precisamos de uma
  **runtime de transporte** que entregue isso (ver [02 §5](./02-camada-contrato-transporte.md)).
  Quando esse custo superar o benefício para um módulo, **gRPC é o fallback**.
- Mais processos para operar/observar → exige o coletor OTLP central (já planejado)
  e supervisão (systemd/compose) desde cedo.
- Latência local sobe de "chamada de função" (~ns) para "IPC" (~µs–sub-ms). Para o
  domínio (mensagens, IA com 200–5000 ms) é irrelevante; documentar onde **não** for.

---

## 7. Próximo documento

A promessa "escala sem mudar o padrão" depende inteiramente da **camada de contrato e
transporte**. Ela é detalhada em
[02-camada-contrato-transporte.md](./02-camada-contrato-transporte.md).

---

*Visão da arquitetura modular por contrato. Sujeito a refinamento.*
