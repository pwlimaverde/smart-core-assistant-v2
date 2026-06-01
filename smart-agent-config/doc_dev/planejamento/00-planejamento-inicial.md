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
| D2 | Granularidade dos serviços | **Modular monolith** (crates por domínio + poucos binários) | Isolamento lógico agora; promoção a microserviço depois sem reescrever; barato para 1 VM |
| D3 | Camada de IA | **Serviço Python separado** (LangChain/RAG) exposto por **gRPC** | Ecossistema de IA maduro em Python; isola a parte imatura em Rust. gRPC dá contrato forte poliglota com isolamento de processo (FFI/PyO3 **descartado** — ver §13.1) |
| D4 | Isolamento do banco | **`tenant_id` + Row-Level Security (RLS)** do PostgreSQL | Melhor custo/segurança; banco recusa query sem `tenant_id` no contexto |
| D5 | Modelo de projeto | **Greenfield** (v1 como referência de domínio) | Sem migração incremental nem big-bang sobre o legado |
| D6 | Ordem de entrega | **Windows primeiro**, depois **Web** | Foco em uma plataforma; abstração de dados garante port limpo |

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

```
                         ┌──────────────────────────────┐
   WhatsApp ──webhook──► │  Evolution Go (1 cluster,     │
                         │  multi-instância)             │
                         └───────────────┬──────────────┘
                                         │ webhook
┌─────────────────────────────────────────────────────────────────┐
│  MESSAGING GATEWAY (Rust)                                         │
│  → valida assinatura/origem                                       │
│  → resolve tenant_id pela instância Evolution                     │
│  → persiste evento bruto (raw)                                    │
│  → publica evento interno no bus     (NUNCA roda regra pesada)    │
└───────────────┬───────────────────────────────────────────────────┘
                │ evento (envelope com tenant_id)
        ┌───────▼─────────┐        Event Bus (Redis Streams)
        │     WORKER      │  ◄──── debounce por contato →
        │  (Rust)         │        conversa → política de ticket →
        │                 │        kanban → automação → IA
        └───┬────────┬────┘
            │        │ gRPC
            │        ▼
            │   ┌──────────────────────┐
            │   │ ia_engine            │  (Python: LangChain, RAG,
            │   │ (Python, serviço     │   transcrição, sentimento).
            │   │  gRPC separado)      │   Núcleo = FeaturesCompose
            │   └──────────────────────┘
            ▼
   ┌────────────────────────┐         ┌────────────────────────┐
   │  PostgreSQL (UNIFICADO) │         │  Redis                 │
   │  tenant_id + RLS        │         │  (Streams, cache,      │
   │  + pgvector (RAG)       │         │   presença, pub/sub)   │
   └────────────────────────┘         └────────────────────────┘
                ▲
                │ gRPC/HTTP (comandos/consultas) + WebSocket (realtime)
        ┌───────┴─────────┐
        │  RUNTIME API    │ ◄──── Flutter (Windows → depois Web)
        │  (Rust)         │           │
        └─────────────────┘           │ FFI (flutter_rust_bridge)
                                      ▼
                            ┌────────────────────────┐
                            │ LOCAL ENGINE (Rust FFI)│
                            │ cache + mídia em disco │
                            │ + índice SQLite local  │
                            └────────────────────────┘

  + CONTROL PLANE (Rust): tenants, planos, credenciais, feature flags,
    billing/usage, instâncias Evolution
```

---

## 4. Blocos da arquitetura

A solução se divide em quatro blocos lógicos (executados como 4 binários Rust):

### 4.1 Control Plane
Cadastro de tenants, planos, quotas, branding, feature flags, credenciais e
configuração das integrações (incluindo o registro das instâncias Evolution
por tenant). É o "back office" da plataforma.

### 4.2 Messaging Gateway
Recebe webhooks do Evolution Go, **valida origem/assinatura**, **resolve o
tenant pela instância**, **persiste o payload bruto** e **publica o evento
interno** (`message.received`, `message.update`, `connection.update`, etc.) no
event bus. **Não executa regra de negócio.** É a única porta de entrada do
mundo externo de mensagens.

### 4.3 Worker (Support Core)
Consome eventos do bus e executa o domínio:
- **Debounce por contato** (junta rajadas de mensagens).
- Resolve/cria a conversa/atendimento.
- Aplica **política de ticket** (reaproveita ativo, reabre, cria).
- Atualiza **Kanban** (etapa/fluxo/departamento), **automações**.
- Chama o **`ia_engine`** (Python, via gRPC) para mídia, intents, resposta e
  sentimento.
- Registra a resposta do bot e dispara o envio outbound via Evolution.

**Substitui o Celery da v1.** Na v1, o Celery acumulava dois papéis: (a) fila de
trabalho + worker assíncrono (`process_contact_response_task`) e (b) agendamento
temporal (`verificar_feedback_atendimento` após `RESOLVIDO`,
`purge_old_media_all_tenants` periódico). Na v2 ambos vivem no `worker` Rust:
- **Fila + processamento assíncrono** → consumo de **Redis Streams** (consumer
  groups) pelo `worker`.
- **Agendamento temporal** → scheduler interno do `worker` (tarefas com atraso
  via stream com `ETA`/sorted-set no Redis, ou `tokio` timers para o processo
  vivo) para timeout de feedback e jobs de retenção/manutenção.
- **Debounce** → `application::DebounceByContact` (buffer + lock no Redis,
  herdando a lógica do `message_buffer` da v1), em vez do `time.sleep()` dentro
  da task Celery.

### 4.4 Runtime API + Realtime (App Delivery)
- **gRPC/HTTP** para comandos e consultas (abrir ticket, listar colunas, buscar
  histórico, configurar, enviar mensagem).
- **WebSocket** para realtime (nova mensagem, typing, presença, leitura,
  mudança de etapa, resposta da IA, atualização do Kanban).
- Fan-out de eventos por tenant.

---

## 5. Estrutura de código (Cargo workspace)

Monorepo Rust com isolamento lógico por domínio (DDD) e poucos binários:

```
apps/
  control_plane/        # binário: back office / gestão de tenants
  runtime_api/          # binário: API + realtime para o Flutter
  worker/               # binário: processamento de eventos + IA
  messaging_gateway/    # binário: ingestão de webhooks do Evolution
crates/
  domain_tenant/        # regras puras: tenant, plano, quota, feature flags
  domain_contact/       # contatos, números, tags, histórico
  domain_conversation/  # conversa: thread, participantes, mensagens, anexos
  domain_ticket/        # atendimento: abertura, vínculo, prioridade, SLA, status
  domain_kanban/        # colunas/etapas, regras de transição, automações de etapa
  domain_whatsapp/      # instâncias Evolution, sessões, normalização de webhook
  domain_ai/            # contratos de classificação/resumo/sugestão/handoff
  application/          # orquestração dos casos de uso (use cases)
  contracts/            # DTOs, eventos, contratos gRPC, envelopes (tenant_id)
  infrastructure_postgres/
  infrastructure_redis/
  infrastructure_evolution/
  infrastructure_storage/   # mídia (storage transitório)
  realtime/             # subscriptions, sessões conectadas, fan-out
  observability/        # logs estruturados, métricas, tracing
  local_engine/         # crate dual-target: lib server + cdylib FFI (cache local)
```

> A estrutura completa do monorepo (todas as stacks, não só o workspace Rust)
> está detalhada em [01-estrutura-do-projeto.md](./01-estrutura-do-projeto.md).
> O frontend são **dois apps Flutter** (`clients/flutter_windows` e
> `clients/flutter_web`) + pacotes compartilhados em `clients/packages/`. A IA é
> o serviço Python independente **`ia_engine/`** (na raiz do monorepo, fora do
> workspace Rust), comunicando-se por **gRPC** (ver §13).

**Camadas:**
- `domain_*`: regras puras de negócio (sem I/O).
- `application`: orquestra casos de uso (ex.: `ReceiveMessage`,
  `DecideTicketPolicy`, `CanBotRespond`, `TransferFlow`).
- `contracts`: DTOs, eventos, contratos RPC e envelopes (todos carregam
  `tenant_id`).
- `infrastructure_*`: integração com banco, Redis, Evolution e storage.
- `apps/*`: executáveis independentes.
- `local_engine`: **crate especial** compilável tanto como dependência dos
  binários-servidor quanto como `cdylib`/`staticlib` para o FFI do Flutter
  (ver §8).

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
  S3/MinIO** e roda com `DATABASE_SAVE_MESSAGES=false`. Logo, o webhook tende a
  trazer apenas a referência cifrada do CDN do WhatsApp: o worker reconstrói o
  objeto e baixa/descriptografa via Evolution (precisa de `mediaKey`,
  `directPath`, etc.), com **retry/backoff** (o Go às vezes retorna 403/500
  transitório logo após o recebimento). **Decisão em aberto:** habilitar S3/MinIO
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

### 8.1 Duas camadas de comunicação com o servidor
- **gRPC/HTTP** para comandos e consultas (abrir ticket, listar colunas, buscar
  histórico, alterar configurações, enviar mensagem).
- **WebSocket** para realtime (nova mensagem, typing, presença, leitura,
  mudança de etapa, resposta da IA, atualização do Kanban).

Essa combinação supera o polling e permite stores locais no Flutter reagindo a
eventos em tempo real.

### 8.2 Motor local via FFI (decisão D1 — híbrido)
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
   WebSocket reconcilia. Definir estratégia de conflito (sugestão inicial:
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
| **Storage de objetos transitório** | O binário decifrado (Evolution Go S3/MinIO ou cache do servidor) | TTL/retenção curta |
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
`FeaturesCompose` (`modules/ai_engine/features/features_compose.py`), com cada
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
  [padroes_linguagens/seguranca.md](../padroes_linguagens/seguranca.md).
- **Resiliência (no `worker`):** `tokio::time::timeout` em toda chamada gRPC +
  retry/backoff para erros transitórios; o worker degrada graciosamente (ex.:
  fallback fixo) se a IA estiver indisponível.
- **Escala:** sob carga, sobem-se **N réplicas** do `ia_engine` (cada uma com seu
  GIL) atrás de balanceamento gRPC — é assim que se escala Python em produção
  (processos, não threads).

---

## 14. Infraestrutura

Início em **Hostinger KVM2** (uma VM), com separação **lógica** de serviços para
facilitar futura distribuição sem reescrever:

- **Proxy reverso** (Nginx/Caddy/Traefik) com TLS e `proxy_buffering off` para
  WebSocket/SSE.
- **runtime_api** (Rust) — API + realtime.
- **worker** (Rust) — processamento assíncrono + agendamento (substitui o Celery
  da v1).
- **messaging_gateway** (Rust) — ingestão de webhooks.
- **control_plane** (Rust) — gestão.
- **ia_engine** (Python) — IA (serviço gRPC separado; escalável por réplicas).
- **PostgreSQL** (+ pgvector) — banco unificado.
- **Redis** — Streams (bus), cache, presença, pub/sub.
- **Evolution Go** — gateway de WhatsApp (multi-instância) + S3/MinIO para mídia.
- **Storage de objetos** (MinIO/S3) — mídia transitória.
- **Observabilidade** — logs estruturados, métricas, tracing.

---

## 15. Stack tecnológica

| Camada | Tecnologia |
|--------|------------|
| Backend | Rust (tokio, axum, tonic/gRPC, sqlx) |
| Event bus | Redis Streams (consumer groups) |
| Agendamento | `worker` Rust (tokio timers + Redis delayed) — substitui Celery |
| Banco | PostgreSQL + pgvector, RLS |
| Cache/Realtime | Redis (namespace por tenant), WebSocket |
| IA/NLP | `ia_engine` Python (serviço gRPC; LangChain), OpenAI/Groq/Ollama |
| IA ↔ Backend | gRPC (tonic no Rust, grpcio no Python); FFI/PyO3 descartado (§13.1) |
| WhatsApp | Evolution Go (multi-instância) + S3/MinIO |
| Frontend | Flutter (Windows → Web) |
| FFI | flutter_rust_bridge + SQLite local |
| Storage mídia | MinIO/S3 (transitório) + disco local (cache permanente) |
| Observabilidade | tracing + métricas + logs estruturados |

---

## 16. Roadmap de construção

> Greenfield, sem migração. Ordem por dependência técnica.

1. **Fundação**
   - Cargo workspace + crate `contracts` (eventos, DTOs, gRPC).
   - Schema PostgreSQL com `tenant_id` + policies RLS + contexto de tenant.
   - Esqueleto de observabilidade.
2. **Messaging Gateway + Evolution multi-instância**
   - Ingestão de webhook → resolve tenant → persiste bruto → publica no bus.
3. **Runtime API + Realtime + shell Flutter (Windows)**
   - gRPC/HTTP + WebSocket. Camada `DataSource` abstrata (modo `RemoteOnly`).
   - Primeiros casos de uso de leitura + realtime.
4. **Worker + `ia_engine` (Python, gRPC)**
   - Debounce, conversa, política de ticket, kanban, IA, envio outbound.
   - Worker assume também o agendamento que era do Celery (feedback, retenção).
5. **Regras de domínio explícitas**
   - Casos de uso das §10.1–10.4 nos crates `domain_*`.
6. **Local Engine (FFI) + mídia local**
   - `local_engine` dual-target; cache de mídia + SQLite; sync §9.
7. **Endurecimento + observabilidade + billing/usage**
8. **Port para Web** (troca `DataSource` para `RemoteOnly`; sem FFI).

*(Importação de dados da v1, se desejada um dia, é um script único e opcional —
fora do caminho crítico.)*

---

## 17. Riscos e decisões em aberto

**Riscos:**
- **FFI dual-target** (`local_engine`) é a parte de maior complexidade; exige a
  abstração `DataSource` desde o dia 1 para não comprometer o port Web.
- **Sincronização de cache local** (conflitos, invalidação) precisa de
  estratégia explícita.
- **Maturidade de IA em Rust** — mitigado mantendo o serviço Python `ia_engine`
  isolado, falando por gRPC (decisão D3/§13.1).
- **Reaproveitamento do `FeaturesCompose`** — risco baixo: o código de IA da v1 é
  portado quase intacto; o esforço está em trocar o ponto de entrada (Celery →
  handler gRPC) e extrair a orquestração para o `worker` Rust.
- **Agendamento sem Celery** — o `worker` Rust precisa cobrir os jobs temporais
  que eram do Celery (timeout de feedback, purga de mídia); validar a estratégia
  de delayed tasks no Redis para não perder agendamentos.
- **Retenção de mídia** — política de expiração precisa equilibrar custo de
  storage × disponibilidade multi-operador/Web.
- **Migração mental DB-por-tenant → único** — RLS precisa ser testada
  rigorosamente para garantir isolamento.

**Decisões já fechadas (antes em aberto):**
- ✅ **Transporte `worker` (Rust) ↔ `ia_engine` (Python): gRPC** (não FFI/PyO3).
  Racional completo em §13.1. Garante isolamento de processo, escala por réplicas
  (sem teto do GIL) e mantém o Rust 100% safe.

**Decisões em aberto (a definir antes/durante o planejamento):**
- Protocolo final: **gRPC vs REST+WS** para o Runtime API (Flutter ↔ servidor; e
  codegen Dart). *Atenção:* gRPC não roda nativo no navegador — o `flutter_web`
  exigiria gRPC-Web + proxy. Isto é independente da decisão §13.1 (que trata só
  do canal interno backend ↔ IA).
- **Redis Streams vs NATS JetStream** para o bus (recomendação atual: Redis
  Streams para começar simples).
- Estratégia de **conflito de sync** (last-write-wins vs versionamento por
  evento).
- Política de **retenção de mídia** no servidor (TTL, gatilho de expiração).
- Manter `Atendimento` unificado (como v1) **ou** separar conversa × ticket
  (recomendado) na v2.
- Modelo de **autenticação/autorização** do Flutter (tokens, refresh, RBAC por
  tenant) — reaproveitar o modelo da v1: `TenantUser`/`TenantInvite` com
  `role` + `module_permissions` + `flow_permissions`.
- **Mídia no Evolution Go:** habilitar S3/MinIO (entrega `mediaUrl` direta) ou
  manter download + descriptografia no worker (`mediaKey`/`directPath`). A config
  de referência da v1 não tem S3 e usa `DATABASE_SAVE_MESSAGES=false`.
- **Cifragem em repouso** de credenciais/tokens (api keys de provedores,
  Evolution, etc.): definir o mecanismo (a v1 usa Fernet via
  `encrypt_value`/`decrypt_value`).
- **Provisionamento de instâncias Evolution:** o Control Plane chama a API REST
  (`/instance/create`, `/connect`, `/qr`, `/pair`, `/status`) — definir guarda de
  quota por plano (`max_instances`).

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
