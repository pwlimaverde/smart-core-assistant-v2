# Smart Core Assistant v2 — Estrutura do Projeto

> **Status:** Documento de referência para desenvolvimento.
> **Idioma:** Português (comunicação e documentação). Código e identificadores em inglês.
> **Origem:** Definição da organização de pastas e diretrizes de desenvolvimento do monorepo.

---

## Sumário

1. [Filosofia e princípios](#1-filosofia-e-princípios)
2. [Estrutura de diretórios](#2-estrutura-de-diretórios)
3. [Responsabilidades por stack](#3-responsabilidades-por-stack)
4. [Regras de acoplamento](#4-regras-de-acoplamento)
5. [Contratos de comunicação entre stacks](#5-contratos-de-comunicação-entre-stacks)
6. [Convenções de desenvolvimento](#6-convenções-de-desenvolvimento)

---

## 1. Filosofia e princípios

O projeto é um **monorepo monolítico** com stacks tecnológicas distintas, cada uma em seu próprio diretório raiz. O objetivo é máximo desacoplamento entre stacks, mantendo um único repositório para facilitar versionamento coordenado.

**Princípios-chave:**

- **Uma stack, um diretório:** cada stack tem sua pasta raiz, seu toolchain próprio e suas responsabilidades bem delimitadas. Nenhuma stack importa diretamente código de outra.
- **Contratos explícitos na fronteira:** a comunicação entre stacks é feita exclusivamente por contratos formais (gRPC/protobuf, eventos no Redis Streams com envelope padronizado). Nunca por import direto de código. O canal Flutter ↔ servidor é **gRPC único** — unário (comandos/consultas) + **Server Streaming** (realtime); sem WebSocket.
- **Apps Flutter distintos por plataforma:** o app Windows e o app Web são projetos Flutter separados. Não há build multi-plataforma num mesmo `pubspec.yaml`. O código em comum fica em pacotes Dart compartilhados dentro de `clients/packages/`.
- **UI incremental, colada à feature:** a interface não é uma fase final — cada feature de backend entrega, no mesmo ciclo, a tela que a valida (ex.: auth → telas de login/cadastro). As telas nascem no `flutter_windows` (RemoteOnly) e falam só com o `api_client`.
- **Smart-agent-config é meta-código:** não contém código de produto. É a camada de planejamento, documentação e orquestração de agentes do projeto inteiro.

---

## 2. Estrutura de diretórios

```
smart-core-assistant-v2/                    # raiz do monorepo / git root
│
├── server/                                 # STACK: Backend Rust (Cargo workspace)
│   ├── Cargo.toml                          # workspace manifest
│   ├── Cargo.lock                          # versionado
│   ├── apps/
│   │   ├── control_plane/                  # binário: gestão administrativa de tenants/planos
│   │   ├── messaging_gateway/              # binário: ingestão de webhooks Evolution Go
│   │   ├── runtime_api/                    # binário: API gRPC + Server Streaming para clientes
│   │   ├── worker/                         # binário: processamento assíncrono de eventos do bus
│   │   ├── data_postgres/                  # binário: servidor RPC de dados PostgreSQL + outbox
│   │   ├── data_redis/                     # binário: servidor RPC de cache/tokens/locks síncrono
│   │   └── data_storage/                   # binário: servidor RPC de storage de mídia
│   └── crates/
│       ├── application/                    # orquestração de casos de uso (depende de contracts/transport)
│       ├── contracts/                      # schemas .proto canônicos + .fbs gerados + Envelope
│       ├── transport/                      # canais (UDS/TCP/WS), codecs (FB/gRPC) e event bus
│       ├── error_core/                     # taxonomia de erros, ErrorEnvelope (convenção)
│       ├── observability/                  # tracing distribuído e contexto traceparent (convenção)
│       ├── infrastructure_postgres/        # sqlx + migrations + crypto (lib de data_postgres)
│       ├── infrastructure_redis/           # conexões Redis, tokens, cache (lib de data_redis)
│       ├── infrastructure_storage/         # Cloudflare R2 / S3 client (lib de data_storage)
│       └── test_support/                   # utilitários e fixtures para testes
│
├── evolution/                              # STACK: Evolution Go — gateway WhatsApp
│   ├── docker/                             # docker-compose + volumes para Evolution Go
│   ├── config/                             # configurações de instâncias e webhooks
│   └── scripts/                            # scripts de provisionamento de instâncias
│
├── clients/                                # STACK: Aplicações Flutter
│   ├── packages/                           # pacotes Dart compartilhados entre apps
│   │   ├── core_ui/                        # design system: tema dark padrão + widgets (kanban, chat, inputs)
│   │   ├── domain_models/                  # modelos de domínio em Dart (DTOs gerados do .proto)
│   │   ├── api_client/                     # cliente RPC único + factory kIsWeb
│   │   └── local_engine_ffi/               # bridge flutter_rust_bridge (wrapper do crate local_engine)
│   │
│   ├── flutter_windows/                    # App Flutter Windows — FASE 1 (desktop)
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   └── ...                         # usa DataSource: LocalEngineFFI (via local_engine_ffi)
│   │   └── pubspec.yaml                    # depende de core_ui, domain_models, api_client, local_engine_ffi
│   │
│   └── flutter_web/                        # App Flutter Web — FASE 2 (sem FFI)
│       ├── lib/
│       │   ├── main.dart
│       │   └── ...                         # usa DataSource: RemoteOnly (sem local_engine_ffi)
│       └── pubspec.yaml                    # depende de core_ui, domain_models, api_client
│
├── ia_engine/                              # STACK: Motor de IA — Python
│   ├── src/
│   │   ├── features/                       # features isoladas por responsabilidade
│   │   │   ├── transcribe_audio/           # transcrição de áudio
│   │   │   ├── interpret_media/            # descrição de imagem/vídeo/documento
│   │   │   ├── analyse_message/            # classificação de intents e entidades
│   │   │   ├── generate_response/          # geração de resposta multi-turn + RAG
│   │   │   ├── analyse_sentiment/          # análise de sentimento/avaliação
│   │   │   └── generate_embeddings/        # geração de embeddings para pgvector
│   │   ├── llm/                            # abstração de provedores (OpenAI, Groq, Ollama)
│   │   ├── contracts/                      # DTOs Pydantic espelhando o .proto
│   │   ├── features_compose.py             # facade (núcleo de IA herdado da v1)
│   │   └── server.py                       # servidor RPC (ponto de entrada; handlers)
│   ├── proto/                              # .proto do serviço (gerado do contracts)
│   ├── tests/
│   ├── pyproject.toml                      # gerenciado com uv
│   └── uv.lock                             # versionado
│
├── docker/                                 # Infra local de desenvolvimento
│   ├── compose/
│   │   └── data.yml                        # PostgreSQL + pgvector, Redis (MinIO legado, sem uso)
│   └── Dockerfile                          # Dockerfile principal (server Rust)
│
├── smart-agent-config/                     # META: Planejamento e orquestração de agentes
│   ├── CLAUDE.md                           # guia exportado para Claude Code
│   ├── .context/                           # dotcontext: docs, agentes, skills
│   ├── .claude/                            # Claude Code: agents (symlinks), skills
│   ├── .agents/                            # Antigravity: rules, workflows
│   └── doc_dev/                            # documentação técnica de desenvolvimento
│       └── planejamento/
│           ├── 00-planejamento-inicial.md   # visão arquitetural completa da v2
│           ├── 01-estrutura-do-projeto.md   # este documento
│           ├── 02-fases-desenvolvimento.md  # fases/etapas (com status real)
│           ├── 03-infraestrutura-postgres.md # crate Postgres + RLS (canonizado)
│           ├── 04-infraestrutura-redis.md   # crate Redis (canonizado)
│           ├── 05-observabilidade.md        # logs/métricas/traces + stack LGTM
│           ├── 06-tratamento-de-erros.md    # crate error_core (erros rastreáveis)
│           ├── 07-crate-contracts.md        # contratos/eventos/envelope
│           ├── 08-infraestrutura-storage.md # ponte S3/R2 (mídia multi-tenant)
│           ├── 09-comunicacao-e-autenticacao.md # transporte + auth (canonizado)
│           └── 10-plano-cicd-devops.md      # plano-mãe CI/CD + DevOps
│
├── .gitignore
└── .env.example                            # template de variáveis de ambiente
```

---

## 3. Responsabilidades por stack

### 3.1 `server/` — Backend Rust

**Responsabilidade:** núcleo da aplicação multi-tenant. Toda regra de negócio, persistência, event bus e API para os clientes.

| Binário/App | Responsabilidade |
|-------------|------------------|
| `control_plane` | Cadastro de tenants, planos, quotas, feature flags, credenciais e configuração de instâncias Evolution |
| `messaging_gateway` | Recebe webhooks do Evolution Go, valida assinatura/origem, resolve `tenant_id`, persiste bruto no `data_postgres` (RPC) e publica no Redis Streams (bus). **Nunca executa regra de negócio** |
| `worker` | Consome eventos do bus e executa a orquestração do domínio: debounce, conversa, política de ticket, kanban, chamada ao `ia_engine`, envio outbound via Evolution. Salva alterações via RPC no `data_postgres` |
| `runtime_api` | API RPC/gRPC e Server Streaming para realtime (nova mensagem, typing, kanban, presença); gRPC-Web para Flutter Web. Fan-out de eventos por tenant via Redis pub/sub |
| `data_postgres` | Servidor RPC (UDS/FlatBuffers/gRPC) exclusivo do PostgreSQL. Executa migrações, gerencia RLS pool e comandos de escrita ACID / consultas unárias de leitura |
| `data_redis` | Servidor RPC exclusivo para controle síncrono de caches de permissões, locks distribuídos e tokens JWT/refresh |
| `data_storage` | Servidor RPC exclusivo do storage de mídias no Cloudflare R2 |

**Crates compartilhadas principais:**
- **`application`**: Camada que abriga os casos de uso orquestrando a lógica de negócio (ex.: auth, fluxos de atendimento), dependendo apenas das interfaces de transporte/contratos.
- **`contracts`**: Contém os arquivos `.proto` canônicos, transpilação para `.fbs` e os tipos Rust resultantes da geração de build (flatc / tonic-build), além de expor o `Envelope` de tráfego.
- **`transport`**: Implementa o codec FlatBuffers/gRPC, a runtime de transmissão UDS/TCP/WS, e o barramento Redis Streams (`transport::bus`).
- **`error_core` / `observability`**: Convenções transversais compiladas em todos os serviços.

**Crate especial — `local_engine`:** compilável tanto como dependência de servidor quanto como `cdylib` / `staticlib` para FFI do app Flutter Windows. Contém apenas lógica válida offline/cache — nada multi-tenant sensível.

**Deploy:** Hostinger KVM2 (uma VM). Proxy reverso (Nginx/Caddy) na frente com TLS, HTTP/2 e `proxy_buffering off` para o realtime (e tradução gRPC-Web para o app Web).

---

### 3.2 `evolution/` — Evolution Go

**Responsabilidade:** gateway de WhatsApp multi-instância. Um único cluster Evolution Go gerencia N instâncias (uma por tenant/departamento/atendente), em vez de um container Evolution por tenant (modelo da v1).

- Configuração de docker-compose e volumes para deploy do Evolution Go.
- Scripts de provisionamento de instâncias WhatsApp.
- **Não contém código Rust, Python ou Dart.** É um serviço externo configurado e orquestrado por esta pasta.
- O `server/crates/infrastructure_evolution/` contém o cliente que consome a API HTTP do Evolution Go.

---

### 3.3 `clients/` — Flutter

**Responsabilidade:** interfaces de usuário. Duas aplicações Flutter **completamente separadas**, com código em comum extraído para pacotes Dart reutilizáveis.

#### `clients/packages/` — Pacotes compartilhados

| Pacote | Responsabilidade |
|--------|-----------------|
| `core_ui` | **Design system do projeto:** tema dark padrão (tokens abaixo), widgets e componentes visuais reutilizáveis entre os dois apps (card de Kanban, painel de chat, input de mensagem, badges de status) |
| `domain_models` | Modelos de domínio em Dart (DTOs gerados do `.proto`): Ticket, Mensagem, Contato, Kanban etc. |
| `api_client` | **Cliente gRPC único** para o `runtime_api`: unário (comandos/consultas) + Server Streaming (realtime). Factory de canal por `kIsWeb` (`ClientChannel` no desktop, `GrpcWebClientChannel` na web). Injeta o JWT no metadata. **Única dependência de rede dos apps** |
| `local_engine_ffi` | Wrapper do `flutter_rust_bridge` sobre o crate `local_engine`. **Usado somente pelo `flutter_windows`** |

#### Design system padrão (`core_ui`)

Baseline visual do produto — tema dark corporativo, herdado do estudo de
arquitetura Kanban/chat. Tokens:

| Token | Cor | Uso |
|-------|-----|-----|
| Fundo base | `slate-950 #020617` / `slate-900 #0F172A` | Background da aplicação e do chat |
| Superfície | `slate-800 #1E293B` | Cards, inputs, painéis |
| Texto primário | `#FFFFFF` / `slate-300 #CBD5E1` | Títulos e corpo |
| Texto secundário | `slate-400 #94A3B8` | Metadados, IDs, hints |
| Acento | `emerald-400 #34D399` / `emerald-600 #059669` | Destaques, nomes, ações primárias |

Engine **Impeller** (60fps). Componentes-base: coluna de Kanban (horizontal, card
~280px), painel lateral de chat (~384px), input de mensagem com ação primária,
badge de status (`novo` / `em_atendimento` / `finalizado`).

#### `clients/flutter_windows/` — App Windows (Fase 1)

- App desktop Flutter para Windows. **É onde a UI nasce de forma incremental:**
  cada feature de backend entrega aqui a tela que a valida (auth → login/cadastro;
  worker/kanban → fila + chat; etc.).
- **Começa em `DataSource: RemoteOnly`** (só `api_client`, sem FFI). Ganha
  `DataSource: LocalEngineFFI` (via `local_engine_ffi`) na Fase 8 para cache local
  de conversas e mídia em disco.
- Depende dos packages compartilhados; o `local_engine_ffi` só entra na Fase 8.
- Build: `flutter build windows --release`

#### `clients/flutter_web/` — App Web (Fase 2)

- App web Flutter separado, criado quando o Windows estiver concluído.
- Usa `DataSource: RemoteOnly` — sem FFI, sem cache local.
- **Não depende de `local_engine_ffi`.**
- Mesma lógica de negócio e UI dos packages compartilhados, só a implementação de `DataSource` muda.
- Build: `flutter build web --release`

**Princípio de separação:** os dois apps nunca são buildados a partir do mesmo `pubspec.yaml`. O isolamento evita mistura de dependências nativas (Windows) com limitações do ambiente Web.

---

### 3.4 `ia_engine/` — Motor de IA (Python)

**Responsabilidade:** todas as operações de inteligência artificial — transcrição, análise de mídia, classificação de intents, geração de resposta, RAG e análise de sentimento.

- Exposto como **serviço gRPC** (processo separado) chamado pelo
  `server/apps/worker`. Transporte gRPC escolhido sobre FFI/PyO3 — ver
  [00-planejamento-inicial.md §13.1](./00-planejamento-inicial.md#131-decisão-de-transporte-grpc-vs-ffipyo3).
- **Núcleo herdado da v1:** a facade `FeaturesCompose` (toda a IA pura da v1) é
  reaproveitada quase intacta; só o ponto de entrada muda (task Celery → handler
  gRPC). A orquestração de domínio (ex.: `AttendanceOrchestrator`) **não** vem
  para cá — vai para o `worker` + `domain_*`/`application` em Rust.
- **Escala:** stateless quanto a tenant (recebe `tenant_id` em cada request);
  escalável por N réplicas atrás de balanceamento gRPC (vence o GIL com
  processos, não threads).
- Contratos de interface definidos em `server/crates/domain_ai/` (Rust) e espelhados aqui como protobuf/pydantic.
- Provedores de LLM (OpenAI, Groq, Ollama) abstraídos via LangChain. Tokens isolados em variáveis de ambiente.
- Cada feature em `src/features/<nome>/` é independente — pode ser testada e evoluída isoladamente.
- Gerenciado com `uv`; `uv.lock` versionado.

---

### 3.5 `smart-agent-config/` — Planejamento e Agentes

**Responsabilidade:** meta-camada do projeto. Não contém código de produto.

- `CLAUDE.md` — guia exportado para o Claude Code.
- `.context/` — dotcontext: documentação, agentes e skills.
- `.claude/` — agentes e skills sincronizados para o Claude Code.
- `.agents/` — rules e workflows sincronizados para o Antigravity.
- `doc_dev/` — documentação técnica de desenvolvimento (planejamento, estrutura, decisões).

---

## 4. Regras de acoplamento

| Regra | Descrição |
|-------|-----------|
| **Sem imports cruzados entre stacks** | `server/` não importa código de `ia_engine/`, `clients/` ou `evolution/`. A comunicação é por contrato (RPC/Redis). |
| **Isolamento de Infraestrutura de Banco** | Apenas `apps/data_postgres` pode importar `crates/infrastructure_postgres`. Nenhuma outra crate ou app pode interagir com o Postgres diretamente. |
| **Isolamento de Cache/Tokens** | Apenas `apps/data_redis` pode importar `crates/infrastructure_redis` (para fins de persistência de tokens, cache, etc.). O tráfego do barramento Streams é gerenciado por `crates/transport`. |
| **Isolamento de Storage** | Apenas `apps/data_storage` pode importar `crates/infrastructure_storage`. |
| **Acesso via Contrato e RPC** | Módulos como `apps/worker`, `apps/runtime_api` e `apps/control_plane` importam `crates/contracts` e `crates/transport` e realizam chamadas RPC em IPC/UDS para acessar dados. |
| **`local_engine` sem multi-tenant sensível** | O crate `local_engine` não pode conter lógica que exija dados de múltiplos tenants ou processamento de webhook. |
| **`flutter_web` sem `local_engine_ffi`** | O app Web nunca depende do pacote `local_engine_ffi`. |
| **`tenant_id` em toda query** | Toda query ao PostgreSQL (gerida internamente pelo `data_postgres`) inclui obrigatoriamente o filtro por `tenant_id` na aplicação + Row-Level Security (RLS) via `RequestContext`. |

---

## 5. Contratos de comunicação entre stacks

```
Flutter Windows/Web Client
      │
      │  FlatBuffers / IPC (UDS ou TCP/TLS) · gRPC / HTTP2 fallback
      │  WebSocket binário para realtime na Web
      ▼
server/runtime_api ──(RPC direto UDS/FlatBuffers)──► data_redis (Cache/Tokens)
      │                                            │
      │──(RPC direto UDS/FlatBuffers)──► data_postgres (PostgreSQL unificado)
      │                                            │
      │──(RPC direto UDS/FlatBuffers)──► data_storage (R2 storage)
      ▼
[ EVENT BUS ] (Redis Streams - transport::bus) ◄── messaging_gateway ◄── Evolution Go
      │
      ▼
server/worker ──(RPC direto UDS/FlatBuffers/gRPC)──► ia_engine (Python, GPU)
```

| Fronteira | Protocolo | Definição do contrato |
|-----------|-----------|----------------------|
| Flutter → server/runtime_api | FlatBuffers / gRPC | `server/crates/contracts/` (schemas `.proto` + `.fbs` gerados) |
| server/worker → ia_engine | FlatBuffers / gRPC | `ia_engine/proto/` e `contracts` (.proto + stubs) |
| Evolution Go → server | Webhook HTTP | normalizado por `contracts` (eventos) |
| server ↔ data_* (acesso a dados) | FlatBuffers sobre UDS (gRPC fallback) | `contracts` (schemas RPC síncronos) |
| Flutter Windows → local_engine | FFI nativo | `clients/packages/local_engine_ffi/` (flutter_rust_bridge) |

---

## 6. Convenções de desenvolvimento

### Idioma
- **Código e identificadores:** inglês.
- **Comentários no código** (inline, `///`, docstrings): português pt-br com acentuação correta.
- **Documentação, comunicação e planejamento:** português pt-br.

### Git e branches (gitflow)
- `main` — produção
- `dev` — desenvolvimento ("next release")
- `feature/<nome>` — novas funcionalidades (base: `dev`)
- `bugfix/<nome>` — correções em desenvolvimento
- `release/<versão>` — preparação de release
- `hotfix/<nome>` — correções urgentes em produção (base: `main`)

Commits em inglês, sem `Co-Authored-By` nem rodapés de ferramenta de IA.

### Por stack

| Stack | Build | Lint/Format | Testes |
|-------|-------|-------------|--------|
| `server/` | `cargo build` | `cargo clippy -- -D warnings` + `cargo fmt --check` | `cargo test` (banco real para infra) |
| `ia_engine/` | `uv run python` | `ruff check` + `pyright` | `uv run pytest` |
| `clients/flutter_windows/` | `flutter build windows` | `flutter analyze` | `flutter test` |
| `clients/flutter_web/` | `flutter build web` | `flutter analyze` | `flutter test` |
| `clients/packages/*` | (biblioteca) | `flutter analyze` | `flutter test` |

### Infra local
```bash
# Sobe PostgreSQL e Redis (storage é Cloudflare R2 direto)
docker compose -f docker/compose/data.yml up -d
```

### Variáveis de ambiente
Todas as credenciais em `.env` (git-ignored). Template em `.env.example` na raiz.

---

*Documento criado como referência de estrutura e diretrizes. Sujeito a refinamento durante o desenvolvimento.*
