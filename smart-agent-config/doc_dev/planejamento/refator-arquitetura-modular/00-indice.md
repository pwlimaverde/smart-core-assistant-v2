# Refator de Arquitetura — Módulos por Contrato (IPC) + Acesso a Dados Orientado a Eventos

> **Status:** Planejamento (a revisar). Conjunto de documentos que define a **nova
> abordagem arquitetural** da v2 e o **plano de refator** do que já está implementado.
> **Data:** 2026-06-05.
> **Idioma:** pt-br na documentação/comentários; identificadores em inglês.
> **Origem:** Decisão do dono do projeto de migrar de *monólito modular in-process*
> para *módulos como serviços comunicando por contrato (IPC)*, com escritas
> orientadas a eventos e transporte plugável (FlatBuffers padrão / gRPC fallback).
> Baseado nos estudos conceituais em
> [../../arquitetura/arquitetura-comunicacao-microsservicos.md](../../arquitetura/arquitetura-comunicacao-microsservicos.md)
> e [../../arquitetura/arquitetura-dados-ingestao-eventos.md](../../arquitetura/arquitetura-dados-ingestao-eventos.md).

---

## 1. Por que este refator

A arquitetura planejada até aqui (docs `00`–`10`) é um **monólito modular**: crates
isoladas por domínio, mas **chamadas por função direta, no mesmo processo**. O gRPC
só aparecia em duas bordas (Flutter e `ia_engine`). Isso é ótimo para começar, mas
amarra a evolução: para mover um módulo para outra VM (ex.: IA numa máquina com GPU)
seria preciso reescrever a fronteira.

A nova abordagem inverte o princípio: **toda fronteira entre módulos é um contrato
formal**, com **transporte plugável**. Localmente o transporte é **Unix Domain
Socket (IPC)**; para escalar horizontalmente, troca-se o *endpoint* para **TCP/TLS**
— **sem mudar o código de aplicação**. O codec padrão é **FlatBuffers** (zero-copy);
**gRPC** é o fallback documentado para quando o FlatBuffers tiver entrave (streaming
complexo, reconexão, navegador, codegen). As **escritas** passam a fluir por
**eventos** (bus durável); as **leituras** continuam **request/reply síncrono**.

> **Princípio-guia:** *o padrão do projeto não muda quando um módulo migra de host.*
> O que muda é **configuração de endpoint** (`unix://…` → `tcp://…`) e, no limite,
> a escolha de **codec** (FlatBuffers → gRPC). Aplicação e contrato permanecem.

---

## 2. Decisões que fundamentam o conjunto (travadas com o dono)

| # | Eixo | Decisão |
|---|------|---------|
| **RA1** | Acesso a dados | **Centralização absoluta + dois planos (padrão de mercado)**: só os módulos `data_*` tocam o armazém — todo acesso passa por eles, **inclusive de outra VM**. **Plano síncrono = RPC direto** (UDS/FlatBuffers/gRPC) para **leitura** e **escrita-com-ack**. **Plano assíncrono = barramento** (Redis Streams) para **fire-and-forget/ingestão/eventos de domínio/auditoria/outbox**. **Leitura nunca passa por fila** — Redis é buffer/cache e fica fora do caminho de leitura. O `data_*` é **servidor RPC e consumidor do bus** ao mesmo tempo, caindo nos mesmos processadores. Contrato/envelope **único** nos dois planos. |
| **RA2** | Granularidade e ancoragem | **Apps + módulos de acesso a dados** viram **serviços** (processos): `data_postgres`, `data_redis`, `data_storage`, além de `gateway`/`worker`/`runtime_api`/`control_plane`/`ia_engine`. **Os `data_*` são âncora** — ficam sempre colados ao seu armazém e **não migram**; quem migra são os outros módulos, que continuam alcançando os `data_*` pelo endpoint deles. |
| **RA3** | Transporte/codec | **FlatBuffers padrão** (zero-copy), **construído primeiro** na fundação; **gRPC fallback** quando houver entrave. Codec **plugável**, desacoplado do canal. **Todo módulo preparado também para gRPC** desde o início. |
| **RA4** | Canal | **UDS (IPC) é o padrão** de comunicação; **TCP/TLS** ao promover para outra VM; **WebSocket** na borda web. **Todo módulo já nasce preparado para os três canais** — o split em VMs é só **configuração**, não código. |
| **RA5** | Transversais | **`error_core` e `observability` NÃO viram serviços** — são **convenções** (bibliotecas) compiladas em cada módulo. Só o **envelope** (erro + trace context) cruza o fio. |
| **RA6** | Borda Flutter | **FlatBuffers também no cliente** — desktop sobre TCP/TLS; web sobre **WebSocket binário**; **gRPC só como exceção** pontual. |
| **RA7** | Migração | **Refator duro** (projeto no início), porém **planejado e revisado primeiro** — este conjunto é esse plano. |

---

## 3. Mapa dos documentos deste conjunto

| Doc | Conteúdo |
|-----|----------|
| [01-visao-arquitetura-modular-contrato.md](./01-visao-arquitetura-modular-contrato.md) | A nova topologia: serviços como processos, contrato na fronteira, transporte plugável, UDS→TCP, **exemplo `ia_engine` na VM com GPU**. |
| [02-camada-contrato-transporte.md](./02-camada-contrato-transporte.md) | A crate de contrato/transporte: envelope, codec (FlatBuffers/gRPC), canal (UDS/TCP/WebSocket), framing RPC, streaming, reconexão, *endpoint* por config, fonte única de schema. |
| [03-acesso-dados-orientado-eventos.md](./03-acesso-dados-orientado-eventos.md) | **Dois planos (padrão de mercado)**: síncrono = RPC direto (leitura/escrita-com-ack); assíncrono = bus (ingestão/eventos/auditoria/outbox). Anatomia do `data_*` como servidor RPC **e** consumidor do bus; Redis como buffer/cache fora do caminho de leitura; transação/RLS/outbox dentro do serviço. |
| [04-transversais-erro-observabilidade.md](./04-transversais-erro-observabilidade.md) | **Padrão agnóstico de erro e observabilidade** — `ErrorEnvelope`/`ErrorCode` canônicos, os 3 sinks (log/auditoria/propagação), schema de log, `traceparent`/OTLP, e os dois exemplos do dono (erro da IA; senha errada). |
| [05-refator-estado-atual.md](./05-refator-estado-atual.md) | Plano do **refator duro** do que já está implementado (`infrastructure_postgres/redis`, `observability`, `error_core`, `contracts`, auth em andamento): inventário → alvo → passos → riscos → DoD. |

---

## 4. Impacto nos documentos existentes (`00`–`10`)

Este conjunto **emenda** o planejamento atual. Após a revisão e o aval do dono, os
docs abaixo serão atualizados (ou marcados como *superseded* onde o conflito é total):

| Doc existente | Impacto |
|---|---|
| `00-planejamento-inicial.md` | **Alto.** D2 (modular monolith) passa a *serviços por contrato*; §8 (gRPC único no Flutter) vira *FlatBuffers-primeiro no cliente*; §13.1 (gRPC ↔ IA) vira *codec plugável FlatBuffers/gRPC*. Visão geral (§3) ganha a camada de contrato. |
| `01-estrutura-do-projeto.md` | **Alto.** Acrescenta serviços `data_*` e a crate de transporte; regras de acoplamento passam a falar de **fronteira por contrato**, não import direto. |
| `02-fases-desenvolvimento.md` | **Alto.** Reordena fases: camada de contrato/transporte vira **fundação F0**; cada app/serviço entra já como processo por contrato. |
| `07-crate-contracts.md` | **Alto.** `contracts` deixa de ser só DTOs/eventos serde e passa a hospedar **schemas `.fbs`/`.proto` + tipos gerados + abstração de transporte** (ou divide-se em `contracts` + `transport`). |
| `09-comunicacao-e-autenticacao.md` | **Alto.** Transporte do auth passa por **RPC direto (escrita-com-ack) via contrato** (FlatBuffers/UDS); realtime continua streaming, agora **FlatBuffers sobre socket** (gRPC fallback). |
| `03-infraestrutura-postgres.md` | **Médio.** A crate vira **biblioteca interna do serviço `data_postgres`**; o app ganha **servidor RPC** (leitura/escrita-com-ack) + **consumidor do bus** (assíncrono) + relay outbox. RLS/migrations/crypto intactos. |
| `04-infraestrutura-redis.md` | **Médio.** Separa os dois papéis: **bus** (transporte de eventos) × **serviço `data_redis`** (cache/token/lock). |
| `05-observabilidade.md` | **Médio.** Acrescenta **propagação de `traceparent` no envelope** e coletor OTLP central para trace distribuído entre VMs. |
| `06-tratamento-de-erros.md` | **Médio.** Acrescenta o **envelope de erro de fronteira** (código + trace) e o mapa "lib em ambos os lados / dado no fio". |
| `08-infraestrutura-storage.md` | **Baixo.** Vira **biblioteca interna do serviço `data_storage`**; presign por req/reply, purga por evento. |
| `10-plano-cicd-devops.md` | **Médio.** Deploy passa a orquestrar N processos com *endpoints* configuráveis (UDS local / TCP entre VMs) + coletor OTLP. |

> A revisão dos `00`–`10` **não** está feita ainda — é trabalho de execução do plano.
> Este conjunto existe para o dono **ver e aprovar a direção antes** de mexer no código
> ou nos docs canônicos.

---

## 5. Como ler

1. Comece pelo **[01](./01-visao-arquitetura-modular-contrato.md)** (a foto grande).
2. Desça para **[02](./02-camada-contrato-transporte.md)** (o coração técnico — a abstração que entrega a promessa "escala sem mudar o padrão").
3. **[03](./03-acesso-dados-orientado-eventos.md)** e **[04](./04-transversais-erro-observabilidade.md)** detalham os dois pontos mais sensíveis (eventos no banco; convenções entre VMs).
4. **[05](./05-refator-estado-atual.md)** é o caminho concreto para sair de onde estamos.

---

*Índice do conjunto de refator. Sujeito a refinamento e, ao final, canonização via
`plan-restructuring` para `.context/plans`.*
