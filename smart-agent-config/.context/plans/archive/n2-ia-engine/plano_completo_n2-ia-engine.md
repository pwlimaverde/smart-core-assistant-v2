# Plano Completo — Fase N2: `ia_engine` (serviço Python de IA via gRPC)

> **Reestruturado em 2026-07-06** a partir de `doc_dev/planejamento/17-fase-N2-ia-engine.md`,
> validado contra a central de libs (langchain **atualizado para 1.x**, opentelemetry **criado**).
> **Canônico:** `.context/plans/n2-ia-engine.md` · **Docs auxiliares:** [info_aux](./info_aux_n2-ia-engine.md)
> **Objetivo:** camada de IA como serviço Python separado, exposto por **gRPC** (decisão travada:
> memória `ia-engine-grpc-decision` — gRPC, **não FFI**), consumido pelo `worker` com
> timeout/retry e **degradação graciosa**: mídia→texto, intents/entidades, **RAG** (pgvector 1536),
> resposta e sentimento.

## Correções aplicadas (reestruturação)

| # | O quê | Por quê | Fonte |
|---|---|---|---|
| 1 | **O porte da `FeaturesCompose` é reescrita em LCEL 1.x, não cópia**: a v1 usa langchain 0.1.x cujas chains legadas (`LLMChain`, `langchain.chains.*`) **saíram do pacote** (foram para `langchain-classic`, não recomendado) | Plano base dizia "portar com paridade funcional"; sem esta correção o porte importaria APIs removidas | Context7 `/langchain-ai/docs` (2026-07-06) |
| 2 | **Pydantic v2 nativo**: shim `langchain_core.pydantic_v1` removido no 1.x — schemas de intents/entidades/sentimento com `pydantic.BaseModel` v2 + `with_structured_output` | Código da v1 que usar o shim quebra | idem |
| 3 | Inicialização de modelo por tenant via `init_chat_model` (`langchain.chat_models`) | API unificada atual para trocar provedor por config — casa com a config por tenant | idem |
| 4 | N2.1/N2.5 detalhados com o **setup OTel Python confirmado** (TracerProvider+BatchSpanProcessor+OTLPSpanExporter; extract/inject via `propagate.get_global_textmap()` sobre metadata gRPC; instrumentors aio do `opentelemetry-instrumentation-grpc`) | O plano base citava "OpenTelemetry Python" sem forma concreta | readthedocs + contrib (2026-07-06), doc novo `doc_dev/libs/python/opentelemetry.md` |
| 5 | Embeddings fixados em modelo de dimensão **1536** (ex. `text-embedding-3-small`) — validar contra `vector(1536)` do schema `0007` no boot da feature | Dimensão errada falha silenciosamente só na gravação | schema 0007 + doc langchain |

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Pasta `ia_engine/` | raiz do monorepo | **Ausente** | N2.1 cria o skeleton |
| Facade v1 | `old/.../modules/ai_engine/features/features_compose.py` | Núcleo provado na v1 (langchain 0.1.x) | N2.2 **reescreve em LCEL 1.x** |
| Barreira de bot | `worker/src/main.rs` (`bot_pode_atender` → texto fixo) | Resposta temporária | N2.5 troca pela IA (fallback = texto atual) |
| RAG/embeddings | `0007_treinamento_rag.sql` (pgvector **1536**) | Tabelas prontas | N2.4 consome via RPC |
| Mídia | `infrastructure_storage` (R2) + `MediaPointer` | Presign pronto | N2.3/N2.5 usam URL pré-assinada |
| Contratos | `contracts/schemas/` | Toolchain Rust pronta | N2.2 gera stubs Python (grpcio-tools) |

## 1. Escopo

**Dentro:** N2.1 skeleton · N2.2 contratos/stubs + facade · N2.3 análise · N2.4 resposta+RAG · N2.5 integração worker · N2.6 UI chat.
**Fora:** painel de treinamento/ingestão pelo tenant; custo de tokens (→ N4/backlog).

## 2. Etapas

### N2.1 — Skeleton do serviço

1. `ia_engine/` com **uv** (`pyproject.toml` + lock), `server.py` (servidor **`grpc.aio`**), layout `features/`, `llm/`, `contracts/`, `rag/`.
2. Config por ambiente (Pydantic Settings + `.env`; `SMARTCORE_IA_ENGINE_ENDPOINT` — TCP no Windows, memória `transport-windows-tcp`); healthcheck gRPC.
3. Telemetria no boot (doc `opentelemetry.md`): `TracerProvider(Resource{service.name: "ia_engine"})` + `BatchSpanProcessor(OTLPSpanExporter())` (endpoint `OTEL_EXPORTER_OTLP_ENDPOINT` — mesmo collector da malha Rust); instrumentors gRPC aio (`GrpcAioInstrumentor*`, confirmar nomes no README do pacote).
4. Padrões da stack (`doc_dev/planejamento/padroes_linguagens/python.md`): ruff, tipagem, async sem bloquear o event loop em I/O de LLM.
5. Compose/systemd: `ia_engine` na malha dos demais serviços (`docker/` + units).

**Observabilidade & Auditoria:** log de boot estruturado (loguru); provider OTel ativo; **sem evento de auditoria** (intencional). Segredos via Settings, nunca logados.

**DoD:** sobe, healthcheck responde, `ruff` limpo, integrado ao compose, spans chegam ao Tempo.

### N2.2 — Contratos/stubs + reescrita da facade

1. RPCs no `.proto` canônico (crate `contracts`): `Transcribe`, `InterpretMedia`, `Analyse`, `Embed`, `Responder` (com contexto RAG), `Sentimento`. Requests/replies com `tenant_id`, `traceparent` implícito no metadata, e **ponteiros de mídia** (nunca binário inline).
2. Stubs nos dois lados: Rust (build do `contracts`) e Python (grpcio-tools no build do `ia_engine`).
3. **Reescrever** a `FeaturesCompose` em langchain 1.x/LCEL (correções #1–#3): cada chain legada vira `prompt | llm | parser`; structured output com pydantic v2; `init_chat_model` recebendo provedor/modelo/api key do request (config do tenant resolvida no worker). Testes de característica reproduzindo os casos da v1.

**Observabilidade & Auditoria:** spans por feature; **sem evento de auditoria** no Python (o worker audita — a `infra` fica desacoplada). Requests não carregam binário; api key trafega no request via canal interno e nunca é logada.

**DoD:** contratos compilando nos dois lados; facade reescrita com paridade funcional demonstrada por testes de característica.

### N2.3 — Features de análise

- **Transcribe** (whisper/faster-whisper) e **InterpretMedia** a partir do ponteiro (download via URL pré-assinada do `data_storage`/R2 com httpx — nunca binário inline).
- **Analyse** (intents/entidades via `with_structured_output` + pydantic v2) e **Embed** (**1536** — validar dimensão contra o schema no primeiro uso).
- Cada feature: timeout próprio, erro tipado, degradação (retorno vazio/plausível em vez de exceção estourada).

**Observabilidade & Auditoria:** spans `ia.transcribe`/`ia.interpret`/`ia.analyse`/`ia.embed` com `tenant_id` e duração; **sem evento de auditoria**; proibido logar transcrição/conteúdo/URL assinada.

**DoD:** cada feature responde contra insumo real de teste; embeddings com 1536 dims; falha de provedor não derruba o serviço.

### N2.4 — Resposta + RAG + sentimento

1. **RAG por RPC:** `QueryCompose { tenant_id, embedding }` no `data_postgres` faz a busca pgvector **sob RLS** e devolve trechos. O banco mantém **porta única** (memória `banco-unica-porta-via-infra-rpc`) — o Python não abre Postgres. O `ia_engine` injeta o `traceparent` nessa chamada outbound (`propagate.inject` → metadata).
2. **Responder:** compõe prompt (persona/config do tenant + contexto RAG + histórico recente) via `ChatPromptTemplate`/`MessagesPlaceholder` (prompts em português) e gera resposta + **sentimento** + metadados.
3. Config do tenant (persona/prompts/provider/api key) chega **do worker** no request (descriptografada via `SecretString` no Rust) — a IA não resolve config nem guarda segredo.

**Observabilidade & Auditoria:** spans `ia.responder`/`ia.rag`; o acesso a dados do tenant é auditado no `data_postgres` (lado Rust); **sem auditoria direta no Python**. Nunca logar prompt completo nem api key.

**DoD:** resposta usa contexto do pgvector do tenant correto (isolamento validado por teste); sentimento retornado; sem vazamento cross-tenant.

### N2.5 — Integração `worker` → IA (resiliência) + mídia

1. Na barreira de bot (`worker/src/main.rs`), chamar o `ia_engine` quando `bot_pode_atender` e sem atendente humano.
2. **Resiliência:** port `Arc<dyn IaEngineClient>` + decorator `ResilientIaEngine` (timeout + retry/backoff + fallback para a resposta temporária atual — nunca travar o fluxo).
3. **Mídia:** worker aciona transcribe/interpret; grava `resumo`/`analise` + `MediaPointer` via RPC; binário fica no R2. Envio da resposta reusa o caminho outbound (N1.3 / `main.rs:389`).

**Observabilidade & Auditoria:**
- *Logs/trace:* span da chamada à IA com timeout/tentativas; `traceparent` W3C contínuo webhook→worker→ia_engine→data_postgres (validável no Tempo).
- *Auditoria:* `ia.resposta_gerada` (INFO), `ia.degradada` (WARN no fallback) — emitidos pelo worker via bus.
- *Sanitização:* conteúdo de mensagem nunca em log; só ids, durações e flags.

**DoD:** mensagem entra → IA responde com RAG → resposta sai no WhatsApp; falha da IA degrada para o texto fixo sem erro ao usuário; resumo de mídia persistido; trace contínuo no Tempo.

### N2.6 — UI: resposta da IA e resumo de mídia no chat

- No `operacional_module` (chat), renderizar resposta gerada e resumo/análise de mídia, com indicador "gerado por IA". Sem lógica de IA no cliente.

**Observabilidade & Auditoria:** logs de UI sem PII; **sem evento de auditoria** (só exibição).

**DoD:** `.\infra\test-flutter.ps1` limpo; resumo e resposta aparecem no chat contra o runtime real.

## 3. SOLID / Ports & Adapters

- **Rust:** `worker` → `Arc<dyn IaEngineClient>` (port) + adapter gRPC; degradação como decorator (OCP).
- **Python:** facade `FeaturesCompose`; cada feature um caso de uso isolado (SRP); provedores LLM atrás de abstração (`init_chat_model` facilita trocar provedor sem tocar a feature).
- **RAG:** adapter que fala **só via RPC** ao `data_postgres` (DIP; sem acesso a banco).

## 4. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Serviço Python novo — esforço subestimado (maior incógnita do backlog) | Atraso | Timebox por feature; MVP da IA = resposta+RAG; análise de mídia pode vir em sub-sprint; N2 não bloqueia N3/N4 |
| Porte 0.1.x→1.x mais profundo que o esperado | Atraso | Correções #1–#3 já mapeiam o gap; testes de característica antes de refinar |
| Latência da IA no caminho quente | Chat trava | Chamada assíncrona + timeout curto + degradação best-effort |
| Vazamento cross-tenant no RAG | Segurança | RAG sempre sob RLS via RPC; teste de isolamento pgvector |
| Chave de provedor em log | Segredo vazado | `SecretString` no Rust; regra "nunca logar api key" no Python; revisão de logs |
| `traceparent` não cruza o Python | Trace quebrado | Setup confirmado no doc novo; validar no Tempo já na N2.1 |

## 5. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N2** | Skeleton + contratos IA | Aprovar RPCs IA + `IaEngineClient` + estratégia de degradação | Skeleton→facade→features→RAG→integração→UI | `test-local.ps1` (RAG isolado, degradação) + `test-flutter.ps1` (chat) | Resposta IA ponta-a-ponta; trace contínuo; sem PII/segredo |
