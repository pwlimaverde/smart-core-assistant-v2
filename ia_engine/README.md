# ia_engine

Serviço gRPC (Python, `grpc.aio`) de IA do Smart Core Assistant v2. Fornece
respostas de IA (RAG textual já resolvido pelo worker), análise de mídia
(transcrição de áudio, interpretação de imagem/vídeo/documento), classificação
de intenções/entidades, embeddings e análise de sentimento para o bot de
atendimento WhatsApp.

## Decisões de arquitetura

- gRPC real (`grpc.aio`, HTTP/2), nunca FFI.
- Serviço **stateless**: nunca abre conexão Postgres. O RAG (busca vetorial) é
  feito pelo `worker` (Rust) via `data_postgres.QueryCompose` **antes** de
  chamar `Responder`; o texto já resolvido chega em `dados_treinamento`.
- A `api_key` do provedor LLM chega **sempre por request** (`LlmProviderConfig`),
  nunca fica em env/config global e nunca é logada.
- Mídia sempre por `MediaRef.url` (URL pré-assinada R2), baixada via `httpx` —
  nunca binário inline.
- `traceparent` (W3C TraceContext) viaja só via metadata gRPC.

## Contrato

O `.proto` canônico é compartilhado com o lado Rust e vive em
`../server/crates/contracts/schemas/ai/ai_engine.proto`. **Não** editar/duplicar
aqui — os stubs Python são gerados a partir dele.

## Desenvolvimento

```bash
uv sync                       # instala deps (runtime + dev)
uv run python scripts/gen_proto.py   # gera stubs em src/ia_engine/contracts/
uv run pytest                 # testes (LLM fake, sem rede/chave real)
uv run ruff check .           # lint
uv run python -m ia_engine.server    # sobe o servidor gRPC (porta 50060)
```
