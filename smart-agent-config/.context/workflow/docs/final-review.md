# Final Review — n2-ia-engine
Data: 2026-07-10 · Modelo: Opus · Diff: working tree (escopo: contracts, worker, data_postgres, ia_engine/, clients/operacional_module, docker)

## Rótulo: CORRIGIDO

## Resumo das correções
Bug de correctness que quebrava o caminho de RAG em produção: o `embeddings_provider` era enviado como nome de classe LangChain cru (ex.: "OpenAIEmbeddings") em vez de slug de provedor, fazendo `init_embeddings` falhar sempre (mascarado pela degradação graciosa). Normalizado no `data_postgres`, com api_key de embeddings própria propagada ao worker. Reforço de sanitização (`Debug` redigido para os dois structs que carregam api_key em claro), span de observabilidade na chamada à IA, e o teste de vazamento de api_key estendido para cobrir o caminho de erro.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N2.1 Skeleton (uv, grpc.aio, healthcheck, OTel, compose, settings) | ✅ | `server.py` com graceful shutdown + health gRPC; `telemetry.py` com TracerProvider + `aio_server_interceptor` (propagação W3C); `settings.py` nunca guarda api_key; serviço nos dois compose (contexto=raiz p/ o `.proto` canônico). |
| N2.2 Contratos/stubs + reescrita da FeaturesCompose em LCEL 1.x | ✅ | `.proto` com 6 RPCs; stubs Rust (tonic build) + Python (`gen_proto.py`); facade reescrita em `prompt \| llm.with_structured_output` (pydantic v2), `init_chat_model`/`init_embeddings`; 35 testes com fakes determinísticos. |
| N2.3 Análise (transcribe/interpret/analyse/embed 1536) | ⚠️ | Todas implementadas e testadas nos 2 lados; `embed` valida dim 1536. **Não ligadas ao pipeline ao vivo** (simplificação #2, documentada em `ia_engine/mod.rs`); transcrição real = `PendingTranscriber` (#3, documentada em `transcribe.py`). |
| N2.4 Resposta + RAG (QueryCompose sob RLS) + sentimento | ✅ (após correção) | RAG via RPC `QueryCompose` no `data_postgres` sob `run_in_tenant_transaction` (RLS); Python nunca abre Postgres. **Provider de embeddings estava quebrado — corrigido** (item 2 abaixo). Score triádico + safety-net portados exatos. |
| N2.5 Integração worker→IA (timeout/retry/degradação) + mídia | ✅ (parcial) | `Arc<dyn IaEngineClient>` + `ResilientIaEngine` (timeout + retry [0,1,2]s, só erros transitórios) + degradação para texto fixo + auditoria `bot.respondeu`/`bot.degradado`. **Mídia no pipeline** (transcribe/interpret) fica para continuação (#2). |
| N2.6 UI: resposta da IA + resumo de mídia no chat | ⚠️ | Model + widget (`_IndicadorIa`, `_ResumoMidia`) + teste prontos. **Mas o datasource envia `geradoPorIa=false`/`resumoMidia=null` fixos** porque o proto do chat não foi regenerado (documentado em comentário) — o indicador nunca recebe dado real ainda. Ver Pendências. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `data_postgres/src/adapters/operacional.rs:675-693` | `resolver_config_ia` enviava `embeddings_provider: cfg.embeddings_class` **cru** (nome de classe, ex.: "OpenAIEmbeddings"). O Python `init_embeddings(provider="OpenAIEmbeddings")` falha sempre → RAG/IA nunca funcionava (mascarado pela degradação). | Normaliza via a mesma heurística `provider_e_api_key_de` (classe→slug) usada no LLM; resolve também a `embeddings_api_key` da família correta. |
| `data_postgres/src/ports/operacional.rs:33-35` · `main.rs:2373` · `worker/src/main.rs:134-155` | Faltava propagar a api_key de embeddings (LLM e embeddings podem ter provedores/keys distintos; antes reusava a do LLM). | Novo campo `ConfigIa.embeddings_api_key`, exposto no reply `ResolverConfigIa` e consumido no worker (LLM usa `api_key`, embeddings usa `embeddings_api_key`). |
| `worker/src/ia_engine/client.rs:11-33` · `data_postgres/src/ports/operacional.rs:23-56` | `LlmProviderConfigInput` e `ConfigIa` derivavam `Debug` com api_key em **texto puro**; um `{:?}` acidental (log/trace) vazaria o segredo (a proteção `SecretString` termina ali). | `Debug` manual redigido (`api_key`/`embeddings_api_key` → `[REDACTED]`); redação propaga para os structs que os contêm (ex.: `ResponderInput`). |
| `worker/src/main.rs:91-98` | `responder_via_ia` sem span (item de observabilidade do plano: "span da chamada à IA"). | `#[tracing::instrument(skip_all, name = "ia.responder", fields(tenant_id, atendimento_id))]` — correlação sem PII (mensagem do usuário fora do span). |
| `ia_engine/tests/integration/test_server_roundtrip.py:131-172` | `test_api_key_nunca_aparece_em_logs` só exercia o caminho de **sucesso**; o crítico (`servicer._abort`, que loga tipo/mensagem da exceção) ficava sem cobertura. | Estendido para também disparar um request inválido (`_abort` → WARNING) com a api_key presente e afirmar que o segredo não aparece nos logs capturados. |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| IA respondeu (sucesso) | span `ia.responder` (novo) + `tracing::info`; traceparent W3C via metadata gRPC (webhook→worker→ia_engine→data_postgres) | `bot.respondeu` (INFO) + `mensagem.enviada` (INFO) — **sem regressão** vs. pré-N2 | contexto só com `atendimento_id` + telefone mascarado | Continuidade de trace mantida; `QueryCompose`/`resolver_config_ia` com `#[tracing::instrument(skip_all)]`. |
| IA falhou/vazia (degradação) | `tracing::warn` por tentativa (`ResilientIaEngine`) + na barreira | `bot.degradado` (WARN) em ambos os caminhos (erro e resposta vazia) | `motivo = e.to_string()` — `IaEngineError`/`DbError` não contêm api_key | Fallback para texto fixo nunca trava o atendimento. |
| Sanitização api_key | Python: `_abort` loga só rpc/tenant/tipo; `ProviderConfigError` não inclui detalhes do provedor. Rust: `Debug` redigido (novo) | n/a | api_key só trafega na mensagem gRPC interna; nunca em log/trace/erro nos 2 lados | `settings.py`/`RuntimeConfig(SecretString)` confirmam que segredo não é persistido no Python. |

## 3. Decisões Autônomas (revisar depois)
- **api_key separada para embeddings** (`ConfigIa.embeddings_api_key`): decidi resolver a chave pela família do `embeddings_class` (não reusar a do LLM), tornando correto o caso multi-provedor (ex.: LLM Groq + embeddings OpenAI). Compatível com o caso comum (mesmo provedor).
- **`Debug` redigido** em vez de manter a garantia "por convenção" do comentário original: defesa estrutural alinhada ao requisito inviolável de sanitização. Nenhum log atual imprimia esses structs — é defesa em profundidade.
- **Fortalecimento do teste** `test_api_key_nunca_aparece_em_logs` (não é teste novo; passou a cobrir o caminho de erro que o nome já prometia). Contagem segue 35 testes.
- **Span `ia.responder`**: primeiro span explícito no pipeline de mensagens do worker (o resto usa eventos `tracing`); adicionado só onde o plano pede.

## 4. Revalidação
- fmt: ✅ (`cargo fmt --check` limpo)
- clippy: ✅ (`cargo clippy --workspace --all-targets --all-features -D warnings` limpo)
- testes Rust: ✅ `contracts` 2/2 · `data_postgres` 31/31 unit + integração (audit_consumer, e2e_trace, via túnel SSH) · `worker` 12/13 — a única falha (`scheduler::...midia_expirada`) é **ambiental pré-existente** (sem Redis fora do túnel), já documentada na fase V, **não é regressão N2**; os 3 testes do `ResilientIaEngine` e a barreira de bot passam.
- ruff/mypy/pytest (ia_engine): ✅ ruff limpo · mypy `Success: no issues found in 20 source files` · pytest 35/35
- flutter analyze: N/A — não alterei arquivos Flutter neste ciclo; a fase V já registrou `flutter analyze` limpo + operacional_module 20/20.

## 5. Pendências (escopo extra ou fora do plano)
- **N2.6 não fecha ponta-a-ponta**: `atendimento_remote_data_source.dart` mapeia `geradoPorIa`/`resumoMidia` como defaults fixos porque o proto do chat (`operacional`) não foi regenerado com esses campos. O widget existe e é testado, mas o indicador "Gerado por IA" e o resumo de mídia nunca recebem dado real do backend. Documentado em comentário no código; regenerar o proto + persistir/expor os campos no backend é um ciclo seguinte.
- **Provedores além de OpenAI**: `pyproject.toml` só declara `langchain-openai`. Provider `groq`/`google_genai` resolvido pelo `data_postgres` faria `init_chat_model`/`init_embeddings` cair em `ImportError` → `ProviderConfigError` (degrada graciosamente, mas não funciona). Adicionar `langchain-groq`/`langchain-google-genai` quando esses provedores forem suportados de fato.
- **Simplificações conhecidas confirmadas como documentadas** (não são desvios): #1 `fluxos_disponiveis`/`campos_*` vazios — comentário em `worker/src/main.rs:249-254`; #2 análise de mídia não ligada ao pipeline — comentário em `ia_engine/mod.rs:10-15`; #3 `PendingTranscriber` — docstring em `transcribe.py`. Todas presentes.
