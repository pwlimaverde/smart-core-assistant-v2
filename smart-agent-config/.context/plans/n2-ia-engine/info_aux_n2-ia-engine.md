# Documentação Auxiliar — Fase N2: `ia_engine` (serviço Python de IA via gRPC)

> Gerado em: 2026-07-06
> Plano canônico: `.context/plans/n2-ia-engine.md`
> Plano completo: `.context/plans/n2-ia-engine/plano_completo_n2-ia-engine.md`
> Origem do plano-base: `doc_dev/planejamento/17-fase-N2-ia-engine.md`

## Libs Python (central `doc_dev/libs/python/`)

| Lib | Versão | Estado na triagem | Uso na N2 |
|---|---|---|---|
| **langchain** | **1.x** (atualizada de 0.1.20 em 2026-07-06 via Context7) | **ATUALIZADA** | LCEL, chat models, prompts, structured output, embeddings |
| grpcio | 1.62.1+ | USAR LOCAL (2026-05-31) | servidor `grpc.aio` + cliente outbound ao `data_postgres` |
| pydantic | 2.7.1+ | USAR LOCAL (2026-05-31) | schemas/validação + Pydantic Settings para config |
| loguru | 0.7.2 | USAR LOCAL (2026-05-31) | log estruturado do serviço Python |
| pgvector (py) | 0.2.5 | USAR LOCAL (2026-05-31) | **não** conecta ao banco — referência de dimensão/formato apenas; a busca vetorial é RPC no `data_postgres` |
| whisper / faster-whisper | 20231117 / 1.0.1 | USAR LOCAL (2026-05-31) | transcribe (áudio→texto) |
| document_loaders | — | USAR LOCAL (2026-05-31) | interpretação de documentos |
| **opentelemetry** | 1.x (api/sdk/exporter-otlp-grpc + instrumentation-grpc) | **CRIADA** em 2026-07-06 | continuidade do `traceparent` W3C através do processo Python |

### LangChain 1.x — o que muda no porte da `FeaturesCompose` (v1 usava 0.1.x)
Fonte: doc atualizado `doc_dev/libs/python/langchain.md` (Context7 `/langchain-ai/docs`, 2026-07-06).

- **`LLMChain` e `langchain.chains.*` legadas saíram** do pacote `langchain` (foram para `langchain-classic`). **Não usar classic**: reescrever as chains da facade em **LCEL** (`prompt | llm | parser`).
- **Pydantic v2 nativo** — o shim `langchain_core.pydantic_v1` foi removido; usar `pydantic.BaseModel` direto (inclusive em `with_structured_output` para intents/entidades/sentimento).
- Namespace 1.x: `langchain.chat_models.init_chat_model` (inicialização unificada por provedor — casa com a config por tenant), `langchain.messages`, `langchain.tools`, `langchain.embeddings`.
- Integrações em pacotes próprios: `langchain_openai` (`ChatOpenAI`, `OpenAIEmbeddings`), `langchain_core.prompts` (`ChatPromptTemplate`, `MessagesPlaceholder`), `langchain_core.output_parsers`.
- Embeddings 1536: `text-embedding-3-small` (ou compatível) — dimensão precisa bater com o schema pgvector `0007` (vector(1536)).
- Padrões do projeto (do doc local): LLM **injetada** por construtor (nunca hardcoded), api key do tenant chega por request (nunca em global/log), prompts em português via `ChatPromptTemplate`.

### OpenTelemetry Python — propagação do trace
Fonte: doc novo `doc_dev/libs/python/opentelemetry.md` (readthedocs + contrib, 2026-07-06).

- Setup: `TracerProvider(resource=Resource.create({"service.name": "ia_engine"}))` + `BatchSpanProcessor(OTLPSpanExporter())`; endpoint via `OTEL_EXPORTER_OTLP_ENDPOINT` (mesmo collector da malha Rust).
- Inbound: `propagate.get_global_textmap().extract(carrier={k: v for k, v in context.invocation_metadata()})` → `tracer.start_as_current_span("ia.responder", context=ctx)`.
- Outbound: `inject(carrier)` → `metadata=tuple(carrier.items())` na chamada gRPC ao `data_postgres`.
- Alternativa: `opentelemetry-instrumentation-grpc` com instrumentors asyncio (`GrpcAioInstrumentor*` — confirmar nomes exatos no README do pacote na implementação); recomendação: instrumentação automática para a propagação + spans de negócio `ia.*` manuais com `tenant_id`.
- `BatchSpanProcessor` não é fork-safe (irrelevante para servidor `grpc.aio` single-process).

## Libs Rust (USAR LOCAL)

| Lib | Versão | Uso na N2 |
|---|---|---|
| tonic | 0.14.6 (2026-06-04) | cliente `IaEngineClient` no worker + decorator `ResilientIaEngine` (timeout/retry/fallback) |
| tonic-prost-build / prost | 0.14.6 / 0.14.3 (2026-06-18) | geração dos stubs Rust dos novos RPCs de IA no crate `contracts` |
| secrecy | 0.10.3 (2026-06-01) | api keys de provedor descriptografadas no worker (`SecretString`) antes de ir no request |

## Serviços Externos
- **Provedores de LLM (OpenAI etc.):** acessados **pelo LangChain** com a api key do tenant vinda no request — sem integração HTTP própria. Sem doc adicional necessária.
- **R2 (mídia):** o `ia_engine` baixa mídia por **URL pré-assinada** gerada pelo `data_storage` — consumo HTTP simples (httpx), sem SDK S3 no Python.

## Grupo C — Observabilidade e Auditoria (por etapa)

| Etapa | Logs/trace | Auditoria | Sanitização |
|---|---|---|---|
| N2.1 skeleton | log de boot + healthcheck; provider OTel configurado | sem evento de auditoria (intencional) | config com segredos via Pydantic Settings, nunca logada |
| N2.2 contratos/facade | spans por feature (`ia.*`) | sem evento (o worker audita) | requests carregam ponteiro de mídia, não binário |
| N2.3 análise | `ia.transcribe`/`ia.interpret`/`ia.analyse`/`ia.embed` com `tenant_id` | sem evento | nunca logar transcrição/conteúdo |
| N2.4 resposta+RAG | `ia.responder`/`ia.rag`; o RPC `QueryCompose` roda sob RLS no `data_postgres` | sem evento no Python; acesso a dados do tenant é auditado no `data_postgres` | proibido logar prompt completo/api key |
| N2.5 integração worker | span da chamada com timeout/retry; `traceparent` contínuo | `ia.resposta_gerada` (INFO), `ia.degradada` (WARN) — emitidos pelo **worker** | payload nunca em log |
| N2.6 UI chat | logs de UI sem PII | sem evento (só exibição) | indicador "gerado por IA" sem metadado sensível |

## Notas Gerais
- **Decisão travada:** worker ↔ ia_engine é **gRPC, não FFI** (memória `ia-engine-grpc-decision`).
- **Banco de porta única:** o RAG busca via RPC `QueryCompose` no `data_postgres` (memória `banco-unica-porta-via-infra-rpc`) — o Python **não** abre Postgres.
- Windows dev: transporte TCP (`SMARTCORE_IA_ENGINE_ENDPOINT=tcp://...`, memória `transport-windows-tcp`).
- Gestão de deps Python com `uv` (`pyproject.toml` + lock), ruff para lint.
