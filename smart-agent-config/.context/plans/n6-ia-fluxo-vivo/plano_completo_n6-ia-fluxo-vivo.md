# Plano Completo — Fase N6: IA no fluxo vivo

> Gerado em: 2026-07-18 · Reestruturado contra docs atuais (ver
> [info_aux_n6-ia-fluxo-vivo.md](./info_aux_n6-ia-fluxo-vivo.md)) e o código real.
> Origem: `doc_dev/planejamento/21-fase-N6-ia-fluxo-vivo.md` (histórico).
> **Idioma:** Português (comunicação/documentação); código e identificadores em inglês.

## Correções aplicadas (vs. plano base)

| # | Correção | Motivo / Fonte |
|---|---|---|
| 1 | N6.1 **não cria cliente de download de mídia** — `MediaDownloader::download_media` já existe em `infrastructure_evolution/src/provider.rs` (`POST /message/downloadmedia`, base64+mimetype, estável desde Evolution GO 0.7.0) | Código real + doc do serviço (info_aux §Evolution) |
| 2 | O worker obtém a mídia via **RPC novo no `data_whatsapp`** (`DownloadMediaMessage`), nunca chamando `infrastructure_evolution` direto | Princípio "uma porta por sistema externo" (arquitetura) |
| 3 | Em vez de "URL de mídia no NormalizedMessage" (a URL da CDN expira em ~1h e o download exige `mediaKey`), o `NormalizedMessage` ganha **`media_payload: Option<serde_json::Value>`** (o sub-objeto `*Message` bruto) + `media_mime`/`media_file_size` — é o que o endpoint de download consome | Restrição real do WhatsApp/Evolution (info_aux §Restrições) |
| 4 | Transcrição via **SDK `openai` direto (`AsyncOpenAI`)** com `base_url` intercambiável, primary **Groq `whisper-large-v3-turbo`** (único com ogg/opus nativo — formato de voz do WhatsApp) e fallback OpenAI | LangChain não tem wrapper adequado; incompatibilidade ogg na OpenAI (info_aux §Transcrição) |
| 5 | Embeddings alternativos: `GoogleGenerativeAIEmbeddings` **exige `output_dimensionality=1536`** (padrão 768 quebraria o RAG silenciosamente) | Doc Context7 (info_aux §langchain-google-genai) |
| 6 | Campos novos do proto do chat definidos concretamente: `MensagemThread.gerado_por_ia = 8` e `resumo_midia = 9` (aditivo; hoje o message vai até o campo 7) | Leitura do `admin.proto:404-412` |
| 7 | Sem `map<>` em protos do crate `contracts` (pipeline `flatc --proto` não suporta) — usar `repeated KeyValuePair` se precisar de mapa | Aprendizado registrado da N2 |

---

## N6.1 — Mídia no pipeline vivo (download → análise → persistência)

**Objetivo:** mensagem de mídia recebida gera análise/transcrição persistida, com
binário no R2 — sem tocar o webhook (princípio 1: nada de regra pesada lá).

**Áreas:** `domain_whatsapp`, `data_whatsapp`, `worker`, `data_storage` (consumo),
`data_postgres` (persistência de resumo/análise), `contracts` (payload RPC interno).

**Passos:**
1. `domain_whatsapp::NormalizedMessage`: adicionar `media_payload: Option<serde_json::Value>`
   (sub-objeto `imageMessage`/`audioMessage`/`videoMessage`/`documentMessage` bruto),
   `media_mime: Option<String>`, `media_file_size: Option<i64>`; preencher no `parse`
   (sem I/O — `domain_*` continua puro).
2. `data_whatsapp`: rota RPC nova `DownloadMediaMessage` (payload: `instance_id`,
   `message` bruto) → `MediaDownloader::download_media` já existente → devolve
   base64+mime. Limite de tamanho configurável (`SMARTCORE_MEDIA_MAX_BYTES`,
   default ~20 MB — abaixo do teto de 25 MB das APIs de transcrição).
3. `worker`: no consumo de mensagem com `media_payload`, **após** persistir o bruto
   e resolver o atendimento (fluxo atual intocado): (a) `DownloadMediaMessage`
   (imediato — URL expira em ~1h); (b) `data_storage::PutFile` (chave
   `media/{tenant}/{instance}/{type}/{hash}`); (c) `ia_engine::Transcribe` (áudio)
   ou `InterpretMedia` (imagem) via `ResilientIaEngine` (timeout/retry bounded já
   existentes); (d) persistir `resumo`/`analise` + `MediaPointer` via RPC
   `data_postgres` (rota existente da N2). Falha em (c)/(d) degrada graciosamente
   (mensagem já está no chat; análise fica ausente) — nunca trava o fluxo.
4. A mensagem **nunca espera** a análise para aparecer no chat: o pipeline de
   mídia roda depois da persistência, no mesmo handler assíncrono.

**DoD:** áudio/imagem real recebido em dev gera arquivo no R2 + transcrição/resumo
persistidos; falha da IA não impede a mensagem de chegar; `.\infra\test-local.ps1` verde.

**Observabilidade & Auditoria:**
- (a) Span `midia.pipeline` no worker com `tenant_id`/`trace_id`/`message_id`/`media_type`/`error_code`;
  `traceparent` propagado ao `ia_engine` (interceptor OTel já existente) e aos `data_*`.
- (b) Evento `midia.analisada` no audit_log (INFO; metadados: `mensagem_id`, tipo,
  duração — **sem conteúdo/transcrição**). Download em si: sem evento de auditoria
  (intencional — é dado operacional, o acesso fica rastreado pelo span).
- (c) Base64/transcrição **nunca** em log; `mediaKey` não persistida fora do
  payload bruto já protegido; token da instância segue em `SecretString`.

---

## N6.2 — Campos de IA no proto do chat (`gerado_por_ia`, `resumo_midia`)

**Objetivo:** o chat exibe o selo "gerado por IA" e o resumo de mídia com dado
real (hoje a UI existe mas recebe `false`/`null` fixo).

**Áreas:** `contracts` (admin.proto), `data_postgres` (SELECT do thread),
`runtime_api` (mapeamento), `api_client` (stubs Dart), `operacional_module` +
`local_engine`/`local_engine_ffi` (modelos espelho).

**Passos:**
1. `admin.proto`: `MensagemThread` ganha `bool gerado_por_ia = 8` e
   `optional string resumo_midia = 9` (**aditivo** — nunca renumerar 1–7).
2. `data_postgres`: `GetThread` passa a selecionar os campos (colunas já existem
   desde a N2 na `oraculo_mensagem`); `runtime_api` mapeia no reply gRPC-Web.
3. Regenerar stubs: Rust (`tonic-prost-build`/`flatc` via build do `contracts`) e
   Dart (`api_client`). Remover o default fixo no
   `atendimento_remote_data_source.dart` (comentário-lembrete já aponta o local).
4. Cadeia FFI: `local_engine` (`MensagemThread` Rust) e `local_engine_ffi`
   (`MensagemThreadFfi`) já têm os campos (`gerado_por_ia`/`resumo_midia`) — só
   conferir o preenchimento na ingestão pós-N6.1.

**DoD:** mensagem do bot exibe selo real; resumo de mídia aparece no chat (web e
desktop); `.\infra\test-flutter.ps1` e `.\infra\test-local.ps1` verdes.

**Observabilidade & Auditoria:**
- (a) Sem span novo (leitura existente); campos entram no payload já rastreado.
- (b) Sem evento de auditoria (intencional — leitura de thread já coberta pelo RBAC/RLS).
- (c) `resumo_midia` pode conter texto derivado de PII: não logar; só trafega no corpo RPC.

---

## N6.3 — Fluxos de transferência por tenant no `Responder`

**Objetivo:** o bot transfere para o fluxo correto do tenant — hoje
`fluxos_disponiveis`/`campos_coletados`/`campos_pendentes` chegam vazios.

**Áreas:** `data_postgres` (RPC), `worker` (montagem do request), `ia_engine`
(consumo — a lógica da `FeaturesCompose` portada já os modela).

**Passos:**
1. RPC `ListarFluxosDoTenant` no `data_postgres` (id, nome, descrição, campos
   requeridos do fluxo — repositórios de `departamento_and_fluxo` já existem),
   sob `run_in_tenant_transaction`.
2. `worker`: montar `fluxos_disponiveis` no request do `Responder` (cachear por
   tenant com TTL curto — padrão do cache de `flow_permissions`, 30s).
3. Ciclo `campos_coletados`/`campos_pendentes`: estado conversacional mínimo da
   v1 portada — persistir os campos já coletados no atendimento
   (`campos_personalizados` já existe no schema) e reenviar no request seguinte.
   **Não inventar DSL nova** (risco registrado no plano base).
4. `ia_engine`: nenhum contrato novo — o `.proto` do `Responder` já tem os campos.

**DoD:** conversa real em dev com dois fluxos cadastrados: o bot coleta campos,
transfere para o fluxo certo e o Kanban reflete; degradação graciosa preservada.

**Observabilidade & Auditoria:**
- (a) Span `bot.responder` ganha `fluxos_count`/`campos_pendentes_count` (números,
  nunca valores); `error_code` em falha.
- (b) Transferência efetivada audita `atendimento.transferido_por_ia` (INFO;
  `atendimento_id`, fluxo destino — sem conteúdo da conversa).
- (c) Valores de campos coletados são PII → nunca em log; só ids/contagens.

---

## N6.4 — Transcrição real + providers Groq/Google de fato

**Objetivo:** substituir o `PendingTranscriber` por transcrição via API e tornar
Groq/Google funcionais (hoje degradam sempre por falta das libs).

**Áreas:** `ia_engine` (pyproject, feature transcribe, llm providers),
`data_postgres` (`ResolverConfigIa` — sem mudança estrutural, só slugs novos).

**Passos:**
1. `uv add openai langchain-groq langchain-google-genai` (docs locais criados:
   `doc_dev/libs/python/langchain_groq.md` / `langchain_google_genai.md`).
2. `ApiTranscriber` (RSOE, substitui `PendingTranscriber`): SDK `openai`
   (`AsyncOpenAI`) com `base_url` por provedor — primary Groq
   `whisper-large-v3-turbo` (`https://api.groq.com/openai/v1`, ogg/opus nativo),
   fallback OpenAI (`gpt-4o-mini-transcribe`; atenção à incompatibilidade ogg —
   se ambos falharem, degrada com transcrição ausente). Chave por tenant via
   `ResolverConfigIa` (mesmo caminho da N2, api_key nunca logada).
   ```python
   client = AsyncOpenAI(api_key=key, base_url="https://api.groq.com/openai/v1")
   result = await client.audio.transcriptions.create(
       model="whisper-large-v3-turbo",
       file=("voz.ogg", audio_bytes, "audio/ogg"),
       language="pt",
   )
   ```
3. Providers de chat/embeddings: heurística de slug da N2 passa a resolver
   `groq:`/`google_genai:` de verdade (`init_chat_model`); embeddings Google com
   `GoogleGenerativeAIEmbeddings(output_dimensionality=1536)` — **1536 é
   obrigatório** (pgvector).
4. Feature flag por tenant para transcrição (`CoreSettings`) — off por padrão
   (custo/latência), o pipeline N6.1 respeita a flag.

**DoD:** áudio ogg real transcrito via Groq em dev; tenant com provider Google
responde e gera embeddings 1536; `uv run task test` + ruff/mypy limpos; falha de
qualquer provedor degrada graciosamente.

**Observabilidade & Auditoria:**
- (a) Span `ia.transcribe` com provedor/duração/`error_code` (retry/fallback
  visível no trace); OTel já propaga W3C.
- (b) Sem evento de auditoria novo (a análise persistida já audita `midia.analisada` na N6.1).
- (c) Áudio e transcrição nunca em log; api_keys em `SecretStr`/`Debug` redigido
  (padrão endurecido no final-review da N2).

---

## N6.5 — Sentimento ligado ao fluxo

**Objetivo:** o RPC `Sentimento` (pronto desde a N2) passa a ser chamado e o
score persistido/exibido.

**Passos:**
1. `worker`: após persistir mensagem inbound de texto (e transcrição de áudio),
   chamar `Sentimento` (mesmo `ResilientIaEngine`, best-effort — nunca bloqueia).
2. Persistir score no atendimento/mensagem via RPC `data_postgres` (coluna nova
   se necessário — migration aditiva).
3. Exibição mínima: indicador no chat/fila (design system já tem badge) — sem
   dashboard novo (fica para ciclo futuro se o dono quiser).

**DoD:** conversa em dev mostra sentimento atualizado; falha da IA não afeta o fluxo.

**Observabilidade & Auditoria:**
- (a) Span `ia.sentimento` (score é número — pode logar; o texto não).
- (b) Sem evento de auditoria (intencional — métrica derivada, não estado sensível).
- (c) Conteúdo da mensagem nunca em log.

---

## Sequenciamento

**N6.1 → N6.2 ‖ N6.4 → N6.3 → N6.5.** N6.1 é a espinha (mídia fluindo);
N6.2 (proto/UI) e N6.4 (transcriber/providers) são paralelizáveis após ela;
N6.3 é o mais sujeito a decisão de produto (ciclo de campos); N6.5 é o menor.

## Validação (fase V)

- `.\infra\test-local.ps1` (Rust completo via túnel) e `.\infra\test-flutter.ps1`.
- `ia_engine`: `uv run task test` (+ ruff/mypy limpos).
- Manual em dev: enviar áudio/imagem reais por WhatsApp e verificar R2 + chat
  (selo IA/resumo) + transferência de fluxo + sentimento.
