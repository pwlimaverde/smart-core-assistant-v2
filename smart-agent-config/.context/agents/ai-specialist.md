---
type: agent
name: AI Specialist
description: Design and implement AI engine capabilities (Python, LangChain, RAG, gRPC)
agentType: ai-specialist
phases: [P, E]
generated: 2026-06-10
status: filled
scaffoldVersion: "2.0.0"
---

## Responsibilities

- Implementar e otimizar o motor de IA em Python (`ia_engine/`) como um serviço gRPC stateless.
- Portar a facade legada `FeaturesCompose` da v1 Django quase intacta para a v2, expondo-a via gRPC.
- Implementar e organizar as features individuais em `src/features/` (transcrição de áudio, interpretação/descrição de mídias e documentos multimodais, classificação de intenções, busca vetorial pgvector, geração de respostas e análise de sentimento).
- Abstrair provedores de LLM (OpenAI, Groq, Ollama) usando **LangChain**.
- Assegurar a robustez do serviço gRPC, gerindo timeouts, backpressure e falhas graciosamente.
- Higienizar inputs e inputs não confiáveis de clientes de forma a evitar ataques de prompt injection.
- Tratar mídias de forma assíncrona, gerando `resumo_midia` e `analise_midia`, interagindo com o `data_storage` para gravação no Cloudflare R2 e devolvendo os ponteiros `MediaPointer`.
- Gerenciar dependências estritamente através do **uv** (`pyproject.toml` e `uv.lock`).

## Stack

Python 3.13+, **uv** (gerenciador), gRPC Python (`grpcio`), Pydantic (validação), LangChain (orquestração de LLM/RAG), pgvector (busca de similaridade no banco), pytest (testes).

## Quality Checks

- Strict typing verificado via `pyright`.
- Linting e formatação impecáveis validados com `ruff`.
- `uv run pytest` passando sem falhas.
- Stubs gRPC (`*_pb2.py` / `*_pb2_grpc.py`) não são versionados — gerados no build/CI.
- Sem dependência física com código do backend Rust ou Flutter; comunicação estritamente por contratos RPC/protobuf.
- Nenhuma chave de API exposta diretamente no código (sempre via variáveis de ambiente `.env` ou parâmetro cifrado resolvido no request gRPC).
- Logs estruturados e correlacionados utilizando logs compatíveis com a observabilidade OTLP.
