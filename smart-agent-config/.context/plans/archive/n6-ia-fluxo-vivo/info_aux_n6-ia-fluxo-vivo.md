# Documentação Auxiliar — Fase N6: IA no fluxo vivo

> Gerado em: 2026-07-17
> Plano canônico: `.context/plans/n6-ia-fluxo-vivo.md`
> Plano completo: `.context/plans/n6-ia-fluxo-vivo/plano_completo_n6-ia-fluxo-vivo.md`
> Origem: `doc_dev/planejamento/21-fase-N6-ia-fluxo-vivo.md` (cronograma do port final, doc 02)

## Libs — reaproveitadas da central local (USAR LOCAL)

| Lib | Stack | Doc local | Verificação | Uso no N6 |
|---|---|---|---|---|
| langchain (≥1.0, LCEL) | python | `doc_dev/libs/python/langchain.md` | 2026-07-06 | `init_chat_model`/`init_embeddings`, structured output — padrão já usado na N2 |
| grpcio (≥1.68) | python | `doc_dev/libs/python/grpcio.md` | 2026-05-31 | servidor `grpc.aio` existente; nenhum uso novo |
| pydantic v2 | python | `doc_dev/libs/python/pydantic.md` | — | modelos das features (padrão N2) |
| tonic 0.14.6 | rust | `doc_dev/libs/rust/tonic.md` | 2026-06-04 | cliente worker→ia_engine existente (`TonicIaEngineClient`); nenhum uso novo |
| prost/tonic-build | rust | `doc_dev/libs/rust/prost.md`, `tonic-build.md` | — | regeneração dos stubs após evolução aditiva do proto |
| reqwest 0.12 | rust | `doc_dev/libs/rust/reqwest.md` | 2026-05-31 | cliente HTTP da `infrastructure_evolution` (já existente) |
| grpc dart ^5.1 | flutter | `doc_dev/libs/flutter/grpc.md` | 2026-06-18 | regeneração dos stubs Dart do proto do chat |

## Libs — coletadas via Context7 (docs locais criados/atualizados em 2026-07-17)

### langchain-groq (novo doc: `doc_dev/libs/python/langchain_groq.md`)
- Library ID: `/websites/langchain_oss`. Instalação: `uv add langchain-groq`; auth `GROQ_API_KEY` **ou chave explícita por tenant** (parâmetro `groq_api_key`).
- `ChatGroq(model=..., temperature=..., max_tokens=...)`; compatível com `init_chat_model("groq:<model>")` — encaixa direto na heurística de slug de provedor da N2.
- Structured output pydantic v2: `with_structured_output(Model, method="json_mode")`.
- Modelos chat atuais: `meta-llama/llama-4-scout-17b-16e-instruct` (visão/tools/structured), `mixtral-8x7b-32768`, `gemma-2-9b-it`.

### langchain-google-genai (novo doc: `doc_dev/libs/python/langchain_google_genai.md`)
- Library ID: `/langchain-ai/langchain-google`. Instalação: `uv add langchain-google-genai`; auth `GOOGLE_API_KEY` (fallback `GEMINI_API_KEY`) ou chave explícita.
- `ChatGoogleGenerativeAI(model="gemini-3.5-flash", ...)`; `init_chat_model("google_genai:<model>")`. Structured output `method="json_schema"`.
- **`GoogleGenerativeAIEmbeddings(output_dimensionality=1536)`** — CRÍTICO: o padrão é 768; sem esse parâmetro o vetor não bate com o pgvector 1536 do projeto (RAG quebraria silenciosamente).
- Ambas exigem pydantic v2 puro (sem shim `pydantic_v1`) e funcionam em langchain 1.x sem `langchain-classic`.

## Transcrição de áudio via API (doc atualizado: `doc_dev/libs/python/whisper.md` §3)

- **WhatsApp entrega voz em ogg/opus.** OpenAI Audio API (`POST /v1/audio/transcriptions`; modelos `whisper-1`, `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`) tem **incompatibilidade relatada com ogg/opus** mesmo constando como suportado. Limite 25 MB.
- **Groq Speech-to-Text** (`POST https://api.groq.com/openai/v1/audio/transcriptions`, API compatível com OpenAI — mesmo SDK `openai` trocando `base_url`): **suporte nativo a ogg** ✅; `whisper-large-v3-turbo` (~$0.04/h, WER ~12%, latência 0,5–5s) e `whisper-large-v3` (WER ~10,3%). Downsample 16 kHz mono automático. Limite 25 MB (free tier).
- **LangChain NÃO tem wrapper adequado** (o `OpenAIWhisperParser` é limitado a whisper-1): o caminho idiomático é o SDK `openai` direto (`AsyncOpenAI`, multipart), com `base_url` intercambiável OpenAI↔Groq.
- **Recomendação para o `Transcriber` real (N6.4):** primary Groq `whisper-large-v3-turbo` (ogg nativo, rápido, barato) → fallback OpenAI (`gpt-4o-transcribe`) → degradação graciosa (sem transcrição, resumo indisponível). Local (faster-whisper) fica fora do escopo do servidor.

## Serviço Externo — Evolution API GO 0.7.1 (download de mídia)

### Estado do código real (verdade primária)
**JÁ IMPLEMENTADO:** `infrastructure_evolution/src/provider.rs` (~linha 549) tem
`MediaDownloader::download_media(instance_name, token, message_json) -> MediaDownloadResult { base64, mime_type }`
chamando `POST {base}/message/downloadmedia` com header `apikey` e body `{"message": <mensagem completa do webhook>}`.
**O N6.1 não cria cliente novo — só o caminho worker→downloader (via `data_whatsapp`, respeitando a porta única) e o repasse ao `ia_engine`/`data_storage`.**

### Endpoint
- `POST /message/downloadmedia` — estável desde 0.7.0 ("base64 media support"); 0.7.1 sem quebra.
- Body: a mensagem completa do `messages.upsert` (com `key` + `message.{image,video,audio,document}Message` contendo `url`, `mediaKey`, `mimetype`, `fileSha256`, `fileSize`).
- Resposta: `{ "base64": "...", "mimetype": "image/jpeg" }`.

### Restrições operacionais (moldam o design do N6.1)
- **URL da CDN do WhatsApp expira em ~1 hora** → o download precisa acontecer logo após a ingestão (não pode esperar fila longa); o payload bruto persistido já carrega `mediaKey` etc.
- Base64 infla ~30% em memória; mídias grandes (vídeo) pedem timeout 30–60s e limite de tamanho configurável antes de enviar à IA.
- Erros comuns: 401 (token da instância), 400 (mediaKey malformado), 500 (URL/mediaKey expirados — tratar como transitório-terminal: não adianta retry tardio).
- Tipos com download: `imageMessage`, `videoMessage`, `audioMessage`, `documentMessage`.

## Notas Gerais / Gotchas

1. **Dimensão de embeddings**: qualquer provedor alternativo TEM de produzir vetor 1536 (Google: `output_dimensionality=1536`; validar equivalente em outros) — divergência quebra o RAG silenciosamente (mesma classe de bug que o final-review da N2 pegou).
2. **Proto do chat**: evolução **aditiva** (nunca renumerar campos) — precedente dos campos 14/15 do Envelope; regenerar stubs Rust (`tonic-build`/`flatc`) e Dart no mesmo ciclo.
3. **`flatc --proto` do crate `contracts` não suporta `map<>` nem imports cross-diretório** (aprendizado da N2 — usar `repeated KeyValuePair` local se precisar de mapa).
4. **Envelope da mídia**: o webhook não deve baixar mídia (princípio inviolável 1 — nada de regra pesada no webhook); o download é do worker, via RPC ao `data_whatsapp` (porta única para Evolution), nunca direto.
5. **Sanitização**: base64 de mídia e transcrições NUNCA em log; URLs pré-assinadas e `mediaKey` são credenciais temporárias — não persistir em claro além do payload bruto já protegido.
