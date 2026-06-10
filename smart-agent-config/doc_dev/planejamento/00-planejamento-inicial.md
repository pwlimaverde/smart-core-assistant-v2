# Smart Core Assistant v2 — Planejamento Inicial de Arquitetura

> **Status:** Documento de visão / planejamento inicial (greenfield).
> **Idioma:** Português (comunicação e planos). Código e métodos em Inglês.
> **Origem:** Consolidação da análise de viabilidade da migração do SaaS atual
> (Django/Python) para uma nova plataforma em **Rust (backend)** + **Flutter
> (frontend, Windows → Web)**, com unificação do banco multi-tenant e Evolution
> Go multi-instância.
> **Importante:** Este é um **projeto novo, do zero**. O sistema atual em
> Django serve apenas como **referência de domínio** — nada será migrado
> incrementalmente nem alterado no código legado.

---

## Sumário

1. [Objetivo e contexto](#1-objetivo-e-contexto)
2. [Decisões já travadas](#2-decisões-já-travadas)
3. [Visão geral da arquitetura](#3-visão-geral-da-arquitetura)
4. [Blocos da arquitetura](#4-blocos-da-arquitetura)
5. [Estrutura de código (Cargo workspace)](#5-estrutura-de-código-cargo-workspace)
6. [Estratégia multi-tenant (banco único + RLS)](#6-estratégia-multi-tenant-banco-único--rls)
7. [Integração WhatsApp — Evolution Go multi-instância](#7-integração-whatsapp--evolution-go-multi-instância)
8. [Comunicação com o Flutter (cliente fino + FFI híbrido)](#8-comunicação-com-o-flutter-cliente-fino--ffi-híbrido)
9. [Modelo de mídia local + sincronização](#9-modelo-de-mídia-local--sincronização)
10. [Regras de domínio (extraídas do sistema atual)](#10-regras-de-domínio-extraídas-do-sistema-atual)
11. [Fluxo da mensagem recebida (orientado a eventos)](#11-fluxo-da-mensagem-recebida-orientado-a-eventos)
12. [Modelo de dados-alvo](#12-modelo-de-dados-alvo)
13. [Camada de IA](#13-camada-de-ia)
14. [Infraestrutura](#14-infraestrutura)
15. [Stack tecnológica](#15-stack-tecnológica)
16. [Roadmap de construção](#16-roadmap-de-construção)
17. [Riscos e decisões em aberto](#17-riscos-e-decisões-em-aberto)
18. [Glossário](#18-glossário)

---

## 1. Objetivo e contexto

Construir a **v2** de uma plataforma SaaS multi-tenant de atendimento
inteligente ao cliente via WhatsApp, com:

- **Backend em Rust** — mais robusto, performático e com binários
  independentes (orientado a eventos).
- **Frontend em Flutter** — começando pela **versão Windows (desktop)** e,
  quando concluída, **portada para Web**.
- **Banco de dados unificado** — um único PostgreSQL com isolamento por
  `tenant_id` (substituindo o modelo atual de **um banco por tenant**).
- **Evolution Go multi-instância** — um único cluster Evolution gerenciando
  N instâncias de WhatsApp, em vez de uma aplicação Evolution por tenant.
- **Mídias armazenadas localmente** nas máquinas dos atendentes (cache),
  mantendo no servidor apenas mensagens e resumos.

### Por que reescrever (e não migrar)

A v1 (Django) entregou o MVP e validou o domínio (atendimento, IA, Kanban,
Evolution). A v2 nasce do zero para:

- Eliminar a complexidade operacional do **banco-por-tenant** (provisionamento,
  migrations por tenant, custo de infra).
- Substituir **uma instância Evolution por tenant** por um cluster
  multi-instância.
- Ter um núcleo **orientado a eventos** desde o início, com regras de negócio
  em casos de uso explícitos (não espalhadas em handlers de webhook).
- Entregar um cliente desktop nativo (Flutter/Windows) com cache local de alto
  desempenho.

---

## 2. Decisões já travadas

| # | Decisão | Escolha | Racional |
|---|---------|---------|----------|
| D1 | Conexão Flutter ↔ Rust | **Híbrida** (servidor de rede + FFI local) | Servidor Rust é a fonte da verdade multi-tenant; FFI local dá desempenho/offline e cache de mídia no Windows |
| D2 | Granularidade dos serviços | **Serviços por Contrato IPC/RPC** (microsserviços locais) | Módulos executados como processos isolados (`data_*`, `worker`, `runtime_api`, etc.) comunicando-se por contrato formal. Garante desacoplamento de rede e escala horizontal sem alterar o código de aplicação. |
| D3 | Camada de IA | **Serviço Python separado** (LangChain/RAG) exposto por **FlatBuffers/gRPC** | Ecossistema de IA maduro em Python; isola o interpretador. FlatBuffers sobre IPC/UDS como padrão (gRPC como fallback). Dá contrato forte e permite mover a IA para VM dedicada com GPU (ver §13.1) |
| D4 | Isolamento do banco | **`tenant_id` + Row-Level Security (RLS)** do PostgreSQL | Melhor custo/segurança; banco recusa query sem `tenant_id` no contexto |
| D5 | Modelo de projeto | **Greenfield** (v1 como referência de domínio) | Sem migração incremental nem big-bang sobre o legado |
| D6 | Ordem de entrega | **Windows primeiro**, depois **Web** | Foco em uma plataforma; abstração de dados garante port limpo |
| D7 | Transporte Flutter ↔ servidor | **Contrato Unificado com Transporte Flexível** (FlatBuffers/UDS local; gRPC/TCP/WS fallback) | Canal padrão local é UDS/FlatBuffers (RPC de baixíssima latência); gRPC-Web e WebSocket binário para Web. Unifica comandos, consultas e realtime sob a mesma interface contratual, trocável por configuração. |
| D8 | Construção da UI | **Incremental, junto de cada feature** (após as fundações) | A UI nasce colada à feature que valida — ex.: ao entregar o auth, criam-se as telas de login/cadastro para conferir o uso ponta-a-ponta. Continua em **2 apps Flutter** separados (Windows → Web), começando pelo `flutter_windows` em modo `RemoteOnly` (ver §8.3) |

### Princípio arquitetural central (herdado do estudo de viabilidade)

> **O webhook nunca executa regra pesada.** Ele apenas autentica, identifica o
> tenant, persiste o evento bruto e encaminha para processamento assíncrono.
> Isso reduz perda de eventos, melhora observabilidade e evita gargalos sob
> rajada de mensagens.

> **Conversa ≠ Ticket (conceitualmente).** A unidade operacional de atendimento
> é tratada como fluxo de comunicação + estado operacional. (Ver §10 para como
> o sistema atual unifica isso em `Atendimento` e a recomendação para a v2.)

---

## 3. Visão geral da arquitetura

A topologia da v2 é baseada em **serviços isolados por contrato** rodando localmente como processos separados que se comunicam através de **Unix Domain Sockets (UDS)** como transporte IPC padrão de baixíssima latência (FlatBuffers como codec padrão, com suporte comutável a gRPC/TCP por configuração).

```
                         ┌──────────────────────────────┐
   WhatsApp ──webhook──► │  Evolution Go (1 cluster,     │
                         │  multi-instância)             │
                         └───────────────┬──────────────┘
                                         │ webhook
┌────────────────────────────────────────▼────────────────────────┐
│  MESSAGING GATEWAY (App / Processo)                             │
│  → valida assinatura/origem                                     │
│  → resolve tenant_id pela instância Evolution                   │
│  → persiste bruto via RPC em data_postgres e envia p/ bus       │
└────────────────────────┬────────────────────────────────────────┘
                         │ evento (envelope com tenant_id e traceparent)
                         ▼
            [ EVENT BUS ]  (Redis Streams - transport::bus)
                         │
                         ▼
           ┌───────────────────────────┐
           │   WORKER (App / Processo) │ ◄──── debounce por contato
           │   → orquestra domínio     │       chamando ia_engine
           └──────┬──────────────┬─────┘
                  │              │
                  │ RPC (IPC)    │ RPC (IPC)
                  ▼              ▼
    ┌──────────────────┐   ┌───────────┐
    │ ia_engine        │   │data_redis │ ──► Redis (Cache/Tokens/Locks)
    │ (Python, GPU)    │   └───────────┘
    └──────────────────┘
                  │
                  │ RPC (IPC)
                  ▼
    ┌───────────────────────────┐
    │ data_postgres (App)       │ ──► PostgreSQL (banco unificado + RLS)
    └───────────────────────────┘
                  ▲
                  │ RPC (IPC)
    ┌─────────────┴─────────────┐
    │ RUNTIME API (App)         │ ◄─── gRPC/WS ─── Flutter Client
    └───────────────────────────┘
```

---

## 4. Blocos da arquitetura

A solução se divide em **processos (serviços) independentes** que interagem por contratos IPC síncronos (RPC direto) ou assíncronos (event bus), eliminando acoplamentos diretos com os bancos de dados:

### 4.1 Control Plane
Cadastro de tenants, planos, quotas, branding, feature flags, credenciais e configuração das integrações (indo o registro das instâncias Evolution por tenant). É o "back office" administrativo da plataforma. Falará com os bancos unicamente via contratos de RPC dos serviços de dados.

### 4.2 Messaging Gateway
Recebe webhooks do Evolution Go, **valida origem/assinatura**, **resolve o tenant pela instância**, **persiste o payload bruto** via RPC em `data_postgres` e **publica o evento interno** (`message.received`, `message.update`, etc.) no barramento de eventos. **Não executa regra de negócio.** É a única porta de entrada do fluxo externo de mensagens.

### 4.3 Worker (Support Core)
Consome eventos do bus e executa a orquestração do domínio:
- **Debounce por contato** (junta rajadas de mensagens) via `application::DebounceByContact` (buffer + lock no Redis).
- Resolve/cria a conversa/atendimento.
- Aplica **política de ticket** (reaproveita ativo, reabre, cria).
- Atualiza **Kanban** (etapa/fluxo/departamento), **automações**.
- Chama o **`ia_engine`** (via RPC) para mídias, intents, resposta e sentimento.
- Registra a resposta do bot via RPC em `data_postgres` e dispara o envio outbound via Evolution.

O `worker` centraliza também os agendamentos temporais (timeout de feedback, purga de mídias) via Redis Streams/sorted-sets, substituindo o Celery da v1.

### 4.4 Runtime API + Realtime (App Delivery)
- **RPC/gRPC** para comandos e consultas (abrir ticket, listar colunas, buscar histórico, configurar, enviar mensagem).
- **Server Streaming** para realtime (nova mensagem, typing, presença, leitura, mudança de etapa, resposta da IA, atualização do Kanban) — o cliente abre uma inscrição e o servidor empurra atualizações em tempo real.
- **Fan-out por tenant via Redis pub/sub:** eventos produzidos pelo `worker` são publicados no Redis; cada réplica do `runtime_api` assina os canais dos clientes conectados a ela e os propaga pelos streams ativos. Habilita gRPC-Web para compatibilidade com o Flutter Web.

### 4.5 Serviços de Acesso a Dados (data_*) - Âncoras do Sistema
- **`data_postgres`**: Responsável único por gerenciar o pool `sqlx`, rodar migrations, validar Row-Level Security (RLS) através do `RequestContext`, e executar queries ACID. Oferece planos de escrita-com-ack/leitura (RPC síncrono) e escrita assíncrona baseada em eventos do bus.
- **`data_redis`**: Responsável único por mediar as operações síncronas de cache, locks de debounce, presença de atendentes e tokens de autenticação (refresh tokens). O barramento de eventos (Streams) fica a cargo da biblioteca `transport`.
- **`data_storage`**: Responsável por encapsular as operações de escrita, leitura e pré-assinatura de URLs no Cloudflare R2. Realiza limpezas e purgas de mídias acionadas de forma assíncrona por eventos.

---

## 5. Estrutura de código (Cargo workspace)

Monorepo Rust com isolamento por processos e bibliotecas de apoio:

```
apps/
  control_plane/            # binário: back office / gestão de tenants
  runtime_api/              # binário: API gRPC + Server Streaming para clientes
  worker/                   # binário: processamento de eventos do bus
  messaging_gateway/        # binário: ingestão de webhooks do WhatsApp
  data_postgres/            # binário: servidor RPC de dados PostgreSQL + outbox
  data_redis/               # binário: servidor RPC de cache/tokens/locks síncrono
  data_storage/             # binário: servidor RPC de storage de mídia
crates/
  application/              # casos de uso (orquestração e regras de negócio)
  contracts/                # schemas .proto canônicos + .fbs gerados + Envelope
  transport/                # canais (UDS/TCP/WS), codecs (FB/gRPC) e event bus
  error_core/               # taxonomia de erros, ErrorEnvelope (convenção)
  observability/            # tracing distribuído e contexto traceparent (convenção)
  infrastructure_postgres/  # repositórios SQLx, migrations e crypto (lib de data_postgres)
  infrastructure_redis/     # persistência de cache/tokens/locks (lib de data_redis)
  infrastructure_storage/   # integração com Cloudflare R2 (lib de data_storage)
  test_support/             # infraestrutura para testes integrados
  local_engine/             # FFI compilável para o motor local do Flutter Windows
```

> A estrutura completa do monorepo (todas as stacks, não só o workspace Rust)
> está detalhada em [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md).
> O frontend são **dois apps Flutter** (`clients/flutter_windows` e
> `clients/flutter_web`) + pacotes compartilhados em `clients/packages/`. A IA é
> o serviço Python independente **`ia_engine/`** (na raiz do monorepo, fora do
> workspace Rust), comunicando-se por **RPC (FlatBuffers/gRPC)** (ver §13).

**Camadas:**
- `apps/*`: executáveis independentes (processos) que sobem em portas/sockets específicos.
- `application`: orquestra os casos de uso de negócio.
- `contracts`: define os formatos dos dados transmitidos nas fronteiras de rede (schemas).
- `transport`: lida com o empacotamento, enquadramento e transmissão de rede nos sockets.
- `infrastructure_*`: bibliotecas internas que implementam as APIs dos armazéns físicos (SQLx, Redis, S3).
- `error_core`/`observability`: convenções de telemetria e falhas compiladas em todos os serviços.
- `local_engine`: compilável como `cdylib` / `staticlib` para FFI do Flutter Desktop Windows.

---

## 6. Estratégia multi-tenant (banco único + RLS)

Substitui o modelo atual de **banco-por-tenant** (cada tenant com host/porta/db
próprios e roteador dinâmico) por **um único PostgreSQL**.

**Regras:**
- `tenant_id` (UUID) em **todas** as tabelas de domínio.
- **Row-Level Security (RLS)** do PostgreSQL como defesa-em-profundidade: o
  banco recusa leitura/escrita sem o `tenant_id` no contexto da sessão (ex.:
  `SET app.current_tenant = '<uuid>'` + policies por tabela).
- **Filtro obrigatório por tenant** em toda consulta na aplicação (a RLS é a
  segunda barreira, não a única).
- **Storage de mídia segregado por tenant** (prefixo/bucket por tenant).
- **Redis com namespace por tenant** (cache, presença, realtime).
- **Event bus compartilhado**, mas com `tenant_id` no envelope da mensagem.

**Evolução futura:** se algum cliente exigir isolamento maior, migrar para
**schema-por-tenant** ou **banco-por-tenant** apenas para ele — o domínio já
nasce desacoplado dos detalhes de persistência, então a mudança fica contida na
camada `infrastructure_postgres`.

**Vantagens vs. v1:** sem provisionamento de banco por tenant, migrations
únicas, custo de infra muito menor, onboarding instantâneo.

---

## 7. Integração WhatsApp — Evolution Go multi-instância

- **Um cluster Evolution Go** gerencia N instâncias (em vez de um container
  Evolution por tenant).
- Cada instância pertence a um tenant (e, opcionalmente, a um
  departamento/atendente — equivalente ao `AppInstance` atual).
- O **Messaging Gateway** resolve o `tenant_id` a partir da instância
  (`apikey`/`instance`) que recebeu o webhook.
- Mídia: **a config de referência da v1 (`old/paulo-ecoprint-server`) NÃO usa
  storage S3-compatible** e roda com `DATABASE_SAVE_MESSAGES=false`. Logo, o webhook tende a
  trazer apenas a referência cifrada do CDN do WhatsApp: o worker reconstrói o
  objeto e baixa/descriptografa via Evolution (precisa de `mediaKey`,
  `directPath`, etc.), com **retry/backoff** (o Go às vezes retorna 403/500
  transitório logo após o recebimento). **Decisão em aberto:** habilitar o storage S3-compatible (R2)
  no Evolution Go (entrega `mediaUrl` direto, sem custo de CPU) **ou** manter o
  download/descriptografia no worker. Ver §17.
- **Gerência de instâncias via API REST do Evolution Go** (não por container por
  tenant): `POST /instance/create` (com `name` + `token`), `POST
  /instance/connect` (define webhook + eventos), `GET /instance/qr` ou `POST
  /instance/pair`, `GET /instance/status`. O **Control Plane** orquestra isso.
- **Envio outbound:** `POST /message/sendText` e `POST /message/sendMedia`,
  autenticados com o **token da instância** (não a global key).
- **Autenticação dupla:** *global API key* (admin: criar/listar/deletar
  instâncias) × *token por instância* (enviar, conectar, status, webhook).
- O Evolution Go **não precisa de Redis** e usa **dois bancos PostgreSQL
  próprios** (`evogo_auth`, `evogo_users`), separados do banco da aplicação.

**Eventos relevantes do webhook (nomes reais do Evolution Go):**
`MESSAGES_UPSERT` (mensagem recebida — payload `event: "messages.upsert"`),
`MESSAGES_UPDATE` (read receipts: sent/delivered/read), `MESSAGES_DELETE`,
`CONNECTION_UPDATE`, `QRCODE_UPDATED`, `CONTACTS_UPSERT`, `GROUP_UPDATE`.
> A v1 normalizava o tipo de mídia por chave JSON (`conversation`,
> `extendedTextMessage`, `imageMessage`, `audioMessage`, `documentMessage`,
> `videoMessage`, `stickerMessage`, `locationMessage`, etc.) — manter esse
> mapeamento em `domain_whatsapp`.

---

## 8. Comunicação com o Flutter (cliente fino + FFI híbrido)

### 8.1 Transporte flexível: FlatBuffers padrão e gRPC fallback — decisão D7
Toda a comunicação Flutter ↔ `runtime_api` usa uma interface contratual unificada gerada a partir dos schemas canônicos `.proto` transpiletados para `.fbs` no build, suportando transporte de rede flexível:

- **FlatBuffers padrão (zero-copy)**: Utilizado por padrão para as operações locais. As leituras e escritas com ack (req/reply) usam socket UDS ou conexões TCP/TLS diretas. Transmite envelopes e payloads leves com baixíssima latência.
- **gRPC fallback comutável**: Usado como alternativa quando houver entraves estruturais de rede ou se for conveniente aproveitar o ecossistema gRPC (Tonic/HTTP2).
- **WebSocket binário**: Usado para o tráfego realtime na Web, transportando payloads FlatBuffers.
- **Server Streaming**: Para realtime (typing, presença, novas mensagens), onde o servidor empurra dados de forma assíncrona.

Esta flexibilidade permite comutar o transporte e a codificação apenas alterando configurações de ambiente (`SMARTCORE_API_CODEC`), mantendo os handlers e o código da UI intactos.

### 8.2 Transporte por plataforma (Desktop × Web)
O canal de transporte é abstraído na factory do cliente Dart (`api_client`), selecionando o canal com base em `kIsWeb`:

| Plataforma | Canal Primário (FlatBuffers) | Canal Fallback (gRPC) | Observação |
|---|---|---|---|
| **Windows Desktop** | TCP/TLS com FlatBuffers binário | `ClientChannel` gRPC nativo HTTP/2 | Canal nativo de altíssima performance |
| **Web** | WebSocket binário com FlatBuffers | `GrpcWebClientChannel` (gRPC-Web) | Habilitado pelo middleware `tonic-web` no servidor |

No servidor, o `runtime_api` atende e despacha as requisições no mesmo socket mapeando os payloads opacos baseados em `Envelope`. Para a Web, são fornecidos os headers de segurança CORS e COOP/COEP para suporte a multi-threading (`SharedArrayBuffer` com renderer `skwasm`).

### 8.3 Construção incremental da UI + design system — decisão D8
A UI **não** é uma fase tardia e monolítica: cada feature de backend entrega, no
mesmo ciclo, a **tela que a valida** (ex.: ao concluir o auth, criam-se as telas
de **login e cadastro** no `flutter_windows` para conferir o uso ponta-a-ponta).
Detalhe operacional (trilha de UI por feature) em
[02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).

- **Onde nasce:** sempre no `flutter_windows` (Fase 1), em modo `RemoteOnly`
  (sem FFI), consumindo o `runtime_api` via `api_client`. O port Web (`flutter_web`)
  reaproveita os mesmos packages depois (ver §1/D6).
- **Design system padrão (pacote `core_ui`):** tema dark corporativo como baseline
  do projeto — fundo `slate-950 #020617` / `slate-900 #0F172A`, superfícies
  `slate-800 #1E293B`, texto `slate-300 #CBD5E1` / `slate-400 #94A3B8`, acento
  `emerald-400 #34D399` / `emerald-600 #059669`. Engine **Impeller** a 60fps.
  Componentes-base reutilizados pelos dois apps: card de Kanban (coluna horizontal,
  card ~280px), painel lateral de chat (~384px), input de mensagem, badges de
  status. Esses componentes são a referência visual herdada do estudo de
  arquitetura Kanban/chat (absorvido aqui).
- **Princípio:** a tela é instrumento de verificação da feature — entra junto,
  não depois. Toda tela fala só com o `api_client` (gRPC), nunca com infraestrutura.

### 8.4 Motor local via FFI (decisão D1 — híbrido)
O crate `local_engine` é compilado como **biblioteca nativa** e embarcado no app
Windows via **`flutter_rust_bridge`**. Responsável por:
- Cache local de conversas/tickets/kanban (leitura otimista, baixa latência).
- **Cache de mídia em disco** (ver §9).
- Fila local de envios pendentes (resiliência offline).
- Índice local (**SQLite**) do que está em cache.

**Restrições de design (obrigatórias para o port Web futuro):**
1. **Lógica compartilhada mora no crate `local_engine`**, compilável de dois
   jeitos: dependência dos binários-servidor **e** `cdylib`/`staticlib` para o
   FFI. Só entra no motor local lógica que faz sentido **offline/cache**.
   **Nada multi-tenant sensível ou de webhook** vai para o cliente.
2. **A camada de dados do Flutter é abstraída** atrás de uma interface
   (`DataSource`): implementação `LocalEngineFFI` no Windows; `RemoteOnly` na
   Web (onde FFI não existe). Isso garante port limpo.
3. **Sincronização:** a verdade vive no servidor; o motor local é cache. O
   **stream gRPC de realtime** reconcilia. Definir estratégia de conflito (sugestão inicial:
   *last-write-wins* por timestamp do servidor + versionamento por evento para
   casos sensíveis).

> **Princípio:** o FFI é **camada de desempenho/experiência**, não a fonte da
> verdade. O servidor permanece autoritativo e multi-tenant.

---

## 9. Modelo de mídia local + sincronização

O sistema atual já separa três artefatos por mídia, e isso encaixa
perfeitamente no modelo local:
- **binário** (`arquivo_midia`) — o arquivo em si;
- **resumo para o atendente** (`resumo_midia`) — texto curto e amigável exibido
  no chat;
- **contexto do bot** (`analise_midia`) — transcrição/descrição completa usada
  internamente pela IA.

### 9.1 Camadas de armazenamento

| Camada | O que guarda | Permanência |
|--------|--------------|-------------|
| **Servidor (fonte da verdade)** | Linha da mensagem + `analise_midia` + `resumo_midia` + ponteiro da mídia (chave de storage, mimetype, tamanho, **hash**) | Permanente (leve) |
| **Storage de objetos transitório** | O binário decifrado (Evolution Go S3-compatible/R2 ou cache do servidor) | TTL/retenção curta |
| **Motor Rust local (FFI, Windows)** | Cache permanente do binário em disco + índice SQLite | Permanente local |

### 9.2 Fluxo de sincronização
1. Webhook traz a mídia → `worker` decifra (tem `mediaKey`), chama o AI
   Orchestrator para gerar `resumo_midia`/`analise_midia`, e grava **só o
   resumo + ponteiro** no banco. O binário vai para o storage transitório.
2. O Flutter recebe via realtime a mensagem **com o resumo já pronto** — texto
   sempre disponível, **sem baixar binário**.
3. Quando o atendente abre a conversa, o motor FFI verifica o cache local pelo
   `hash`; se ausente, baixa **uma única vez** do storage e persiste no disco
   local. Próximas visualizações são instantâneas e **não tocam o servidor**.
4. O servidor aplica **retenção**: após X dias (ou após confirmação de cache),
   pode **expirar o binário** do storage. O resumo permanece para sempre.

### 9.3 Cuidado arquitetural (decisivo)
> O disco local é **cache de performance, não a única cópia**. Se a mídia
> existir só na máquina do atendente A, o atendente B não a vê — e o **port Web**
> (sem FFI) ficaria sem mídia. Portanto o servidor/storage precisa conseguir
> **reentregar o binário pelo menos transitoriamente**. O ganho de "não encher o
> servidor" vem da **retenção curta no servidor + cache permanente no cliente**,
> não da eliminação da cópia do servidor.

**Resultado:** texto e resumo sempre no banco do servidor (leve, multi-operador,
pronto para Web); binários pesados vivem no disco dos atendentes após o primeiro
acesso; o servidor hospeda mídia apenas por uma janela curta.

---

## 10. Regras de domínio (extraídas do sistema atual)

Estas regras vêm do comportamento **real em produção** da v1 e devem ser
preservadas como **casos de uso explícitos** nos crates `domain_*`/`application`
(não como lógica espalhada em handlers).

### 10.1 Respostas às perguntas-chave de domínio

| Pergunta | Regra atual (a manter na v2) |
|----------|------------------------------|
| **Mensagem = ticket?** | **Não.** `Atendimento` é a unidade (ticket + conversa unidos na v1). `Mensagem` pertence a um `Atendimento` |
| **Vários tickets abertos por contato?** | **Não.** Reaproveita o `Atendimento` ativo (status `FILA`/`EM_ATENDIMENTO`/`PENDENCIA`); só cria novo se não houver ativo |
| **Ticket pertence à conversa ou ao contato?** | Ao **contato** (FK `Atendimento.contato`). Atendimentos anteriores alimentam o contexto da IA |
| **Reabertura** | Janela de **feedback configurável** após `RESOLVIDO`/`ARQUIVADO` (na v1, o timeout agendado é de **5 min** — `verificar_feedback_atendimento`): nova mensagem dentro da janela vira feedback do atendimento anterior (com análise de sentimento); fora da janela, abre novo atendimento |
| **IA × humano no mesmo thread** | Qualquer mensagem de `ATENDENTE_HUMANO` **bloqueia o bot permanentemente** naquele atendimento. Controle por flag `bot_pode_atender` + `AppInstance.resposta_bot` (por instância) |
| **Distribuição** | Por **departamento → fluxo → etapa** (Kanban via `EtapaFluxo`). A instância Evolution define departamento/fluxo/atendente. Transferência por intenção detectada ou decisão da LLM |
| **Responder "por fora"** | Sim — `from_me=True` cria `Mensagem` como `ATENDENTE_HUMANO` e sincroniza (e isso bloqueia o bot). Read receipts via `MESSAGE_UPDATE` |

### 10.2 Ciclo de vida do atendimento (status)
`FILA` → `EM_ATENDIMENTO` → `PENDENCIA` → `RESOLVIDO` / `CANCELADO` / `ARQUIVADO`.
- Estados "ativos" (reaproveitáveis): `FILA`, `EM_ATENDIMENTO`, `PENDENCIA`.
- Estados finalizadores marcam `data_fim` e podem disparar solicitação de
  feedback.
- Todo movimento entre etapas é auditado (`MovimentoFluxo`, com duração por
  etapa para SLA).

### 10.3 Tratamento de mensagens (regras operacionais)
- **Debounce por contato:** mensagens em rajada são acumuladas num buffer com
  lock de agendamento antes de processar (evita resposta fragmentada).
- **Mídia = mensagem própria; texto = concatenado:** cada mídia vira uma
  `Mensagem` (arquivo + análise individual); textos rápidos são concatenados
  numa única `Mensagem`. Define-se uma "mensagem primária" (texto, ou última
  mídia) que dirige a análise e a resposta.
- **Idempotência:** mensagem com `message_id_whatsapp` já existente no
  atendimento não é reprocessada.
- **Auto-assunto e tags:** a cada análise, o assunto e as tags do atendimento
  são reavaliados a partir de intents/entidades (tags `intent:<x>`,
  `sentimento:<y>`).
- **RAG no momento da resposta:** embeddings da mensagem buscam documentos de
  treinamento similares (pgvector) para compor o contexto da resposta; os
  `rag_sources` ficam rastreáveis nos metadados da mensagem.
- **Mensagem citada/reply:** resolve `mensagem_citada` por `stanzaId`; quando a
  original não está no banco, guarda `quoted_preview`.

### 10.4 Regras do bot (quem responde)
O bot responde **somente se todas** forem verdadeiras:
1. A instância permite resposta automática (`AppInstance.resposta_bot = True`);
2. **Não houve** interação humana no atendimento (qualquer mensagem de
   atendente bloqueia permanentemente);
3. A flag `bot_pode_atender` está `True`.

Transferência para departamento/humano desabilita o bot. Intents de
transferência (`falar_com_humano`, `transferir_atendimento`, etc.) podem
disparar transferência direta (sem LLM) quando há fluxo único.

### 10.5 Entidades de domínio principais (v1, como referência)
- `Tenant`, `TenantDatabase`/`TenantEvolution` → na v2 viram `tenant` + config
  de Evolution no Control Plane.
- `Contato` (cliente/número, perfil WhatsApp, metadados, última interação).
- `Atendimento` (ticket/conversa), `Mensagem`, `MovimentoFluxo`.
- `Departamento`, `FluxoAtendimento`, `EtapaFluxo`, `Atendente`, `AppInstance`.
- `Documento` (treinamento/RAG, com embeddings pgvector), `QueryCompose`
  (comportamento por intent).

### 10.6 Recomendação para a v2 (conversa × ticket)
A v1 unifica conversa e ticket em `Atendimento`. Para a v2, recomenda-se
**separar conceitualmente** (crates `domain_conversation` e `domain_ticket`):
- **Conversa** = fluxo contínuo de comunicação com o contato (mensagens).
- **Ticket** = unidade operacional de atendimento (status, SLA, etapa, dono).
- Uma conversa pode existir sem ticket; um ticket nasce de uma conversa quando
  a política do tenant exigir.

Isso dá liberdade para automação, SLA, reabertura, IA assistiva e análise
futura — **sem** quebrar as regras atuais (a v1 vira o caso particular "1 ticket
ativo por contato").

---

## 11. Fluxo da mensagem recebida (orientado a eventos)

```
1. Evolution Go envia webhook → Messaging Gateway.
2. Gateway valida origem, resolve tenant_id (pela instância) e salva o payload bruto.
3. Gateway publica evento interno (ex.: message.received) no bus, com tenant_id no envelope.
4. Worker aplica DEBOUNCE por contato (acumula rajada).
5. Worker (domain_conversation) normaliza e atualiza a thread da conversa.
6. Worker (domain_ticket) aplica POLÍTICA: reaproveita ativo / reabre / cria novo / só registra.
7. Worker chama o `ia_engine` (gRPC): converte mídia (resumo/análise), classifica intents,
   extrai entidades, gera resposta sugerida, detecta sentimento (feedback).
8. Worker (domain_kanban) aplica etapa/fluxo/transferência; registra MovimentoFluxo.
9. BotRulesEngine decide se o bot responde; se sim, registra resposta e dispara envio
   outbound via Evolution.
10. Runtime/Realtime publica atualizações ao Flutter (nova mensagem, status, etapa, não-lido).
```

O webhook vira **apenas a porta de entrada**; o domínio interno depende de
**eventos padronizados**, não do formato específico do Evolution.

---

## 12. Modelo de dados-alvo

> Esboço inicial — todas as tabelas de domínio carregam `tenant_id UUID NOT NULL`
> e policies RLS.

- **tenant** (Control Plane): id (UUID), name, slug, api_key, owner_user_id,
  email, phone, active, setup_completed, onboarding_step, access_code.
- **tenant_config** (config de IA/branding por tenant — herdado de `TenantConfig`
  da v1): tenant_id, dados_empresa, persona_bot, bot_agent_name, msg_fallback,
  msg_sem_info, msg_transferencia, entity_types (json), llm_class, model,
  transcription_provider/model, vision_provider/model, api_keys (cifradas:
  groq/openai/huggingface), brand_name, primary_color, secondary_color,
  timezone, language_code. **As API keys de provedores e credenciais ficam
  cifradas em repouso** (a v1 usa `encrypt_value`/`decrypt_value`).
- **plan / subscription / payment_record** (billing — herdado de `Plan`,
  `Subscription`, `PaymentRecord`): planos com limites (`max_instances`,
  `max_departments`), assinatura com status/período, pagamentos manuais
  (PIX/boleto/transferência) e gateway externo (asaas/stripe).
- **tenant_user / tenant_invite** (RBAC por tenant — herdado de `TenantUser`,
  `TenantInvite`): role (admin/manager/staff/viewer), `module_permissions`
  (json) e `flow_permissions` (lista de IDs de fluxo liberados no workspace),
  token de convite com validade.
- **evolution_instance** (≈ `AppInstance` + credenciais Evolution da v1): id,
  tenant_id, name/instance_token, api_key, base_url, channel, department_id?,
  owner_agent_id?, resposta_bot (bool — permite resposta automática), active,
  status, metadata (json).
- **contact**: id, tenant_id, phone, profile_name, display_name, metadata,
  last_interaction.
- **conversation**: id, tenant_id, contact_id, channel, state, last_message_at,
  context (json).
- **ticket**: id, tenant_id, conversation_id, contact_id, department_id?,
  flow_id?, stage_id?, status, priority, assigned_agent_id?, bot_enabled,
  subject, tags (json), rating?, feedback?, opened_at, closed_at,
  first_response_at, sla fields.
- **message**: id, tenant_id, conversation_id, ticket_id?, type, content, sender
  (contact/bot/agent), wa_message_id, status_envio (pending/sent/delivered/read),
  quoted_message_id?, quoted_preview (json), intents (json), entities (json),
  media_pointer (json: storage_key, mimetype, size, hash), media_summary,
  media_analysis, rag_sources (json), confidence?, created_at, delivered_at,
  read_at.
- **flow_movement**: id, tenant_id, ticket_id, from_stage_id?, to_stage_id,
  from_agent_id?, to_agent_id?, reason, automatic (bool), duration_seconds,
  moved_at.
- **department / flow / stage / agent**: estrutura de Kanban e distribuição.
- **training_document**: id, tenant_id, content, embedding (pgvector), metadata.
- **intent_behavior** (≈ `QueryCompose`): id, tenant_id, tag, behavior,
  embedding.

---

## 13. Camada de IA

O motor de IA é o serviço Python **`ia_engine`** (decisão D3), **processo
separado** exposto por **gRPC** e consumido pelo `worker` (Rust).

- Responsabilidades: conversão de mídia (transcrição de áudio, descrição de
  imagem/vídeo, leitura de documento → `resumo_midia` + `analise_midia`),
  classificação de intents, extração de entidades, geração de resposta
  (multi-turn com histórico), RAG (pgvector), análise de sentimento/avaliação.
- Provedores: OpenAI / Groq / Ollama (abstraídos via LangChain). Tokens globais
  isolados em variáveis de ambiente (`.env`), nunca no código. **Override por
  tenant** via `tenant_config.api_keys` (cifradas) e campos `llm_class`/`model`/
  `transcription_*`/`vision_*` — quando preenchidos, têm prioridade sobre o
  global (comportamento herdado da v1).
- **Embeddings:** dimensão **1536** (OpenAI `text-embedding`) na v1 — fixar a
  dimensão da coluna `pgvector` desde a primeira migration. Busca por
  `CosineDistance` com `distance_threshold` configurável (RAG de documentos e
  de `intent_behavior`/`QueryCompose`).
- **Fronteira limpa:** o Rust nunca depende de detalhes do LangChain; conversa
  por contratos (`domain_ai` define as interfaces; `contracts` os DTOs; o
  `.proto` é a fonte única de tipos).
- Possível evolução: portar partes simples (chamada direta de LLM via `reqwest`
  + pgvector) para Rust quando fizer sentido, mantendo o serviço Python para o
  que for complexo.

### 13.1 Decisão de transporte: gRPC vs FFI/PyO3

Avaliamos duas formas de o `worker` (Rust) invocar a IA (Python): **gRPC**
(processos separados falando por rede local) e **FFI via PyO3** (interpretador
Python embarcado no processo Rust, "chamada direta de função"). **Escolha:
gRPC.**

> **Princípio que decide:** FFI ("chamada direta") só existe **no mesmo
> processo**. "Serviço separado" significa **outro processo**, e entre processos
> a comunicação é sempre por rede. Os dois desejos — *serviço Python isolado* e
> *FFI direto* — são mutuamente exclusivos. Uma "ponte Rust+PyO3 que serve as
> funções Python" **não agrega valor**: ou o Python roda dentro do worker (aí não
> há serviço separado), ou a ponte vira uma indireção que ainda paga rede **e**
> carrega o custo do PyO3.

| Critério | gRPC (escolhido) | FFI / PyO3 |
|----------|------------------|------------|
| Latência de transporte | ~0,1–1 ms (loopback) | ~0 (microsegundos) |
| **Relevância da latência** | Irrelevante: a chamada à LLM domina (200–5000 ms; mídia 1–10 s). O transporte é < 0,5% do tempo total | — |
| Concorrência / workers | ✅ Escala por **N processos/réplicas** do `ia_engine` | ❌ Limitada pelo **GIL** (1 thread Python por vez serializa a orquestração) |
| Isolamento de falha | ✅ Crash no Python não derruba o worker Rust | ❌ Segfault em lib nativa derruba o worker inteiro |
| Isolamento de memória | ✅ Espaços separados (dado sensível protegido) | ❌ Memória compartilhada no mesmo processo |
| `unsafe` em Rust | ✅ 100% safe | ❌ Introduz fronteira `unsafe` (proibida fora do `local_engine`) |
| Deploy / escala | ✅ Container Python isolado; atualiza/reinicia/escala sozinho; pode ir para host com GPU | ❌ Binário Rust precisa do venv Python exato embarcado |
| Contrato poliglota | ✅ `.proto` gera stubs Rust/Python (e Dart) — erro de schema pega em build | ⚠️ Acoplamento no mesmo binário |

**Nota de mercado:** o uso idiomático e atual do PyO3 é o **inverso** desta
proposta — escrever uma **lib Rust consumida por Python** para acelerar trechos
quentes (ex.: `pydantic-core`, `polars`, `tokenizers`, `orjson`). Embutir um app
Python inteiro (LangChain + dezenas de libs nativas) dentro de um serviço Rust é
um antipadrão. Para **servir IA entre serviços**, o padrão de mercado é rede
(gRPC/HTTP — Ray Serve, BentoML, Triton, FastAPI). PyO3 fica **reservado** para o
caso legítimo: se um trecho de pré/pós-processamento virar gargalo de CPU,
escreve-se uma extensão Rust chamada **de dentro** do Python — sem inverter a
arquitetura.

### 13.2 Núcleo reaproveitado: a facade `FeaturesCompose`

A v1 já concentra **toda** a lógica de IA na facade estática
`FeaturesCompose` (`modules/ia_engine/features/features_compose.py`), com cada
feature em clean architecture (`usecase → datasource → LangChain`). Esse código é
**reaproveitado quase integralmente** no `ia_engine` da v2 — muda apenas o
**ponto de entrada**: do que hoje é chamado por uma task Celery, passa a ser
chamado por um **handler gRPC**.

Métodos da facade (v1) → RPCs do `ia_engine` (v2):

| `FeaturesCompose` (v1) | RPC gRPC (v2) | Feature em `src/features/` |
|------------------------|---------------|----------------------------|
| `analise_previa_mensagem` | `AnalisePreviaMensagem` | `analyse_message` |
| `analise_mensage` | `AnaliseMensage` | `generate_response` |
| `converter_contexto` / `_transcribe_audio` | `TranscribeAudio` | `transcribe_audio` |
| `converter_contexto` / `_interpret_media` | `InterpretMedia` | `interpret_media` |
| `analise_avaliacao` | `AnaliseSentimento` | `analyse_sentiment` |
| `generate_embeddings` | `GenerateEmbeddings` | `generate_embeddings` |
| `extracao_campos` | `ExtracaoCampos` | `analyse_message` (campos) |
| `generate_chunks` / `load_document_*` | `LoadDocument` | (treinamento/RAG) |

> A lógica de domínio que na v1 vivia **junto** da IA (o
> `AttendanceOrchestrator`, política de ticket, transferência) **não** vai para o
> `ia_engine`. Ela migra para o `worker` + crates `domain_*`/`application` em
> Rust (ver §10 e §11). O `ia_engine` fica com **IA pura** (in → LLM → out), sem
> regra de negócio nem acesso ao banco multi-tenant.

### 13.3 Esboço do contrato e da implementação

**Contrato (`.proto` — fonte única de tipos, espelhado em Pydantic):**
```protobuf
service AiEngine {
  rpc AnalisePreviaMensagem(AnalisePreviaRequest) returns (AnalisePreviaResponse);
  rpc AnaliseMensage(AnaliseMensageRequest)       returns (AnaliseMensageResponse);
  rpc TranscribeAudio(TranscribeRequest)          returns (MediaAnalysis);
  rpc InterpretMedia(InterpretMediaRequest)       returns (MediaAnalysis);
  rpc GenerateEmbeddings(EmbeddingsRequest)       returns (EmbeddingsResponse);
}

message AnalisePreviaRequest {
  string tenant_id      = 1;   // sempre presente; isola contexto e escolhe a key
  string historico_json = 2;
  string context        = 3;
  string valid_intents  = 4;
}
```

**Servidor Python (`ia_engine`) — reusa a facade quase intacta:**
```python
class AiEngineServicer(ai_pb2_grpc.AiEngineServicer):
    async def AnalisePreviaMensagem(self, request, context):
        # FeaturesCompose praticamente como na v1 — só muda o ponto de entrada
        result = FeaturesCompose.analise_previa_mensagem(
            json.loads(request.historico_json),
            request.context,
            request.valid_intents,
        )
        return ai_pb2.AnalisePreviaResponse(
            intents=result.intents, entities=result.entities
        )
```

**Cliente Rust (`worker`) — async nativo, sem GIL, sem unsafe:**
```rust
let mut client = AiEngineClient::connect("http://127.0.0.1:50051").await?;
let resp = client
    .analise_previa_mensagem(AnalisePreviaRequest {
        tenant_id,
        historico_json,
        context,
        valid_intents,
    })
    .await?;
```

### 13.4 Configuração, segurança e resiliência

- **`tenant_id` em todo request** — o `ia_engine` é stateless quanto a tenant: o
  `worker` envia o `tenant_id` (e a config/credenciais já resolvidas) em cada
  chamada. A key do tenant A nunca é usada para o tenant B.
- **Segredos:** as API keys de provedor são decifradas pelo lado que detém a
  master key e passadas no request; o `ia_engine` não acessa o banco
  multi-tenant. Conteúdo do cliente é **input não confiável** (anti prompt
  injection). Ver diretrizes em
  [padroes_linguagens/seguranca.md](../padroes_linguagens/seguranca.md).| IA ↔ Backend | RPC sobre IPC/UDS ou TCP/TLS (FlatBuffers padrão; gRPC fallback) |
| Flutter ↔ Backend | **Contrato Flexível**: FlatBuffers binário local (UDS/TCP); gRPC/TCP/WebSocket fallback e Web |
| WhatsApp | Evolution Go (multi-instância) + R2 para mídia |
| Frontend | Flutter (Windows → Web), 2 apps + packages; design system `core_ui` (tema dark) |
| FFI | flutter_rust_bridge + SQLite local |
| Storage mídia | Cloudflare R2 (dev e produção, transitório) + disco local (cache permanente) |
| Observabilidade | tracing + métricas + logs estruturados via OTLP gRPC central |

---

## 16. Roadmap de construção

> Sem migração. Ordem por dependência técnica. Os serviços de base e de acesso a dados já foram concluídos.

1. **Fundação e Acesso a Dados (Concluído ✅)**
   - Cargo workspace reestruturado em `apps/` e `crates/`.
   - Crate `contracts` (schemas `.proto` canônicos, transpilação `.fbs`, stubs gerados, `Envelope` unificado).
   - Crate `transport` (canais UDS/TCP/WS, codecs FlatBuffers/gRPC e `transport::bus` sobre Redis Streams).
   - Apps `data_postgres`, `data_redis`, `data_storage` atuando como servidores RPC e controlando os armazéns físicos.
   - Convenções transversais de observabilidade (OTLP, `traceparent`) e erros (`ErrorEnvelope`).
2. **Messaging Gateway + Evolution multi-instância (🚧 em andamento)**
   - Gateway de webhook do Evolution Go (`messaging_gateway`) → persiste via RPC em `data_postgres` → publica eventos de domínio em `transport::bus`.
3. **Runtime API + Auth + Realtime + UI (🚧 em andamento)**
   - Autenticação por JWT + refresh opaco + RBAC.
   - Primeiro fechamento ponta-a-ponta: auth no servidor `runtime_api` **e** telas de login/cadastro no `flutter_windows` (RemoteOnly).
4. **Worker + `ia_engine` (Python, gRPC/FlatBuffers)**
   - Worker consome barramento, debounce por contato, política de ticket, kanban, IA, envio outbound.
   - `ia_engine` Python com a facade `FeaturesCompose` exposto em RPC.
5. **Local Engine (FFI) + mídia local**
   - `local_engine` dual-target (cache local + SQLite + sincronização).
6. **Endurecimento + observabilidade completa + billing/usage**
7. **Port para Web** (troca `DataSource` para `RemoteOnly` usando WebSocket binário / gRPC-Web).

---

## 17. Riscos e decisões em aberto

**Riscos:**
- **Complexidade do IPC/FlatBuffers personalizado:** Mitigado pelo gRPC estruturado como fallback de configuração imediato em caso de entrave.
- **FFI dual-target** (`local_engine`) é a parte de maior complexidade; exige a abstração `DataSource` desde o dia 1 para não comprometer o port Web.
- **Sincronização de cache local** (conflitos, invalidação) precisa de estratégia explícita.
- **Maturidade de IA em Rust** — mitigado mantendo o serviço Python `ia_engine` isolado, falando por RPC.
- **Retenção de mídia** — política de expiração precisa equilibrar custo de storage × disponibilidade.
- **Auditoria distribuída** — mitigado pelo redirecionamento da auditoria para o bus assíncrono.

**Decisões já fechadas (antes em aberto):**
- ✅ **Transporte interno backend ↔ IA**: RPC sobre FlatBuffers/UDS padrão local (ou gRPC/TCP fallback para VM dedicada com GPU).
- ✅ **Bus de eventos**: Redis Streams (implementado na crate `transport::bus`).
- ✅ **Cifragem de credenciais/tokens**: CipherManager AES-256-GCM.
- ✅ **Realtime Flutter**: Stream gRPC unificado, WebSocket descartado para desktop nativo. gRPC-Web e WebSocket binário com FlatBuffers para Web.
- ✅ **Auditoria**: Redis Streams de forma assíncrona, eliminando o acoplamento direto com o Postgres em `observability`.
- ✅ **Provisionamento de instâncias Evolution**: Control Plane chama a API REST do Evolution Go, com token de instância e global key.
- ✅ **Mídia no Evolution Go**: Usar Cloudflare R2 como storage compatível com S3 integrado ao Evolution, com o gateway gerando URLs pré-assinadas.

- Estratégia detalhada de **conflito de sync** (last-write-wins vs versionamento por evento).
- Janela de **retenção de mídia** no servidor (TTL de 30 dias recomendado).
- Separação total de `conversa` × `ticket` na camada do Rust.

---

## 18. Glossário

- **Tenant:** cliente da plataforma (empresa) com dados isolados.
- **RLS (Row-Level Security):** mecanismo do PostgreSQL que filtra linhas por
  política, garantindo isolamento por `tenant_id` no nível do banco.
- **Messaging Gateway:** serviço que recebe webhooks do Evolution e publica
  eventos internos.
- **Worker / Support Core:** serviço Rust que executa o domínio (conversa,
  ticket, kanban, IA) + agendamento. Substitui o Celery da v1.
- **Runtime API:** API + realtime que serve o app Flutter.
- **Control Plane:** gestão de tenants, planos, credenciais, instâncias.
- **ia_engine:** serviço Python independente de IA (LangChain/RAG), consumido
  pelo `worker` via **gRPC**. Tem como núcleo a facade `FeaturesCompose`.
- **FeaturesCompose:** facade da v1 que concentra toda a lógica de IA pura
  (`analise_mensage`, `transcribe_audio`, `generate_embeddings`, etc.);
  reaproveitada no `ia_engine` da v2 trocando o ponto de entrada (Celery → gRPC).
- **gRPC:** protocolo de RPC com contrato `.proto` e payload binário (Protobuf),
  usado no canal `worker` ↔ `ia_engine` (e candidato para Flutter ↔ servidor).
- **FFI (Foreign Function Interface):** ponte que embarca o Rust como biblioteca
  nativa no app Flutter (via flutter_rust_bridge). Usada **apenas** entre Flutter
  e `local_engine` — **não** entre o backend e o `ia_engine` (ver §13.1).
- **PyO3:** crate que embarca o interpretador Python no Rust (FFI). **Descartado**
  para o canal backend ↔ IA; reservado para eventuais extensões Rust chamadas de
  dentro do Python.
- **Local Engine:** crate Rust de cache/offline embarcado no app Windows.
- **Atendimento:** unidade operacional de atendimento (ticket) na v1.
- **EtapaFluxo:** coluna/etapa do Kanban dentro de um fluxo de um departamento.
- **AppInstance / EvolutionInstance:** instância de WhatsApp vinculada a um
  tenant (e a depto/atendente), com controle de `resposta_bot`.
- **RAG:** Retrieval-Augmented Generation — busca de documentos similares
  (pgvector) para enriquecer a resposta da IA.
- **Debounce por contato:** acumular mensagens em rajada antes de processá-las
  como um lote.

---

*Documento gerado como planejamento inicial da v2. Sujeito a refinamento no
fluxo de planejamento (PREVC) antes da implementação.*
