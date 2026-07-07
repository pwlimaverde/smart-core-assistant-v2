# Fase N2 — `ia_engine` (serviço Python de IA via gRPC)

> **Status:** Plano de execução — criado em **2026-07-06**. Segunda fase do backlog
> pós-MVP (N1–N5) — ver [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Corresponde à Fase 5 (F5)** do mapa de fases.
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** entregar a camada de IA como **serviço Python separado**, exposto
> por **gRPC** e consumido pelo `worker` com timeout/retry e **degradação graciosa**
> — mídia→texto, intents/entidades, **RAG** (pgvector 1536), resposta e sentimento.
> **Decisão travada (memória `ia-engine-grpc-decision`):** a comunicação worker ↔
> `ia_engine` é **gRPC, não FFI**; a facade **`FeaturesCompose` da v1 é reaproveitada**.
> **Regra inegociável:** observabilidade transversal — `traceparent` cruza o processo
> Python; **nunca** logar conteúdo de mensagem/PII nem chaves de provedor.

---

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Pasta `ia_engine/` | raiz do monorepo | **Ausente** (decisão D3: processo Python separado). | N2.1 cria o skeleton. |
| Facade de IA v1 | `old/smart-core-assistant-painel/src/.../modules/ai_engine/features/features_compose.py` | Núcleo de IA (LangChain) da v1 **quase intacto** — transcribe/interpret/analyse/resposta. | N2.2 porta a facade. |
| Barreira de bot atual | `worker/src/main.rs` (`bot_pode_atender` → resposta temporária) | Responde texto fixo quando não há atendente humano. | N2.5 substitui a resposta fixa pela IA (com fallback para o texto atual). |
| RAG / embeddings | `treinamento/` + `0007_treinamento_rag.sql` (pgvector **1536**) | Tabelas de documento/embedding **já existem** no Postgres. | N2.4 consome via RPC `query_compose` ao `data_postgres`. |
| Mídia | `infrastructure_storage` (R2) + `MediaPointer` | Storage pronto; ponteiro de mídia. | N2.5 grava resumo/análise + ponteiro; binário no R2. |
| Contratos | `contracts/schemas/` (proto→fbs) | Toolchain de geração já existe (Rust). | N2.2 gera stubs **também no lado Python**. |

> **Conclusão:** o **núcleo de IA já foi provado na v1**; o trabalho é (a) empacotar
> como serviço gRPC Python idiomático, (b) integrá-lo ao `worker` com resiliência,
> e (c) fechar o RAG contra o pgvector já existente. **Maior incógnita de esforço**
> do backlog — não bloqueia N3/N4.

---

## 1. Escopo

### Dentro do escopo
- **N2.1** Skeleton do serviço (`uv`, `server.py` gRPC, layout de features).
- **N2.2** Contratos/stubs Python + porte da facade `FeaturesCompose`.
- **N2.3** Features de análise (transcribe / interpret / analyse / embeddings 1536).
- **N2.4** Resposta + **RAG** (pgvector via `data_postgres` RPC) + sentimento.
- **N2.5** Integração `worker` → IA (timeout/retry/degradação) + mídia (resumo/análise + `MediaPointer`).
- **N2.6** UI: exibição da resposta da IA e do resumo de mídia no chat.

### Fora do escopo
- Treino/ingestão de documentos pelo tenant (painel de treinamento) — backlog posterior.
- Fine-tuning/observabilidade de custo de tokens — entra no endurecimento (N4).

---

## 2. Contrato de observabilidade (DoD transversal)

- **Telemetria:** o `worker` injeta `traceparent` W3C no metadata gRPC da chamada à
  IA; o `ia_engine` **extrai e continua o trace** (OpenTelemetry Python) e o
  re-injeta nas chamadas de volta ao `data_postgres`. Spans por feature
  (`ia.transcribe`, `ia.interpret`, `ia.responder`, `ia.rag`) com `tenant_id`.
- **Auditoria:** eventos server-side no `worker`/`data_postgres` — `ia.resposta_gerada`
  (INFO), `ia.degradada` (WARN, quando cai no fallback). O `ia_engine` **não** grava
  auditoria direto no Postgres (mantém `infra` desacoplada); reporta ao `worker`.
- **Sanitização:** **proibido** logar conteúdo de mensagem, transcrição, prompt
  completo, ou **chave de provedor** (as api keys chegam descriptografadas via
  `SecretString` no Rust; a IA as recebe por canal seguro e **nunca** as loga).

---

## 3. N2.1 — Skeleton do serviço

**Tarefas**
1. Criar `ia_engine/` com `uv` (`pyproject.toml`, lock), `server.py` (servidor gRPC
   assíncrono — `grpc.aio`), e layout `features/`, `llm/`, `contracts/`, `rag/`.
2. Config por ambiente (`.env` + `SMARTCORE_IA_ENGINE_ENDPOINT`); healthcheck gRPC.
3. Padrões da stack Python (ver [padroes_linguagens/python.md]) — ruff, tipagem,
   `spawn`/async, sem bloqueio do event loop em I/O de LLM.
4. Unit compose/systemd: adicionar `ia_engine` ao `docker/` e às units do servidor
   (mesma malha dos demais serviços), transport TCP em Windows (memória `transport-windows-tcp`).

**DoD:** `ia_engine` sobe, responde healthcheck gRPC, `ruff` limpo, integrado ao compose.

---

## 4. N2.2 — Contratos/stubs + porte da facade

**Tarefas**
1. Definir os RPCs no `.proto` canônico (crate `contracts`): `Transcribe`,
   `InterpretMedia`, `Analyse`, `Embed`, `Responder` (com contexto RAG), `Sentimento`.
   Requests/replies com `tenant_id`, `traceparent`, e ponteiros de mídia (não binário inline).
2. Gerar stubs **nos dois lados**: Rust (já automático no build de `contracts`) e
   **Python** (grpcio-tools) no build do `ia_engine`.
3. Portar `FeaturesCompose` da v1 (`old/.../ai_engine/features/features_compose.py`)
   para o layout novo, adaptando as fronteiras: entrada/saída via os contratos gRPC,
   segredos via config injetada, sem acesso direto ao banco (RAG vai por RPC — N2.4).

**DoD:** contratos gerados e compilando nos dois lados; facade portada com paridade
funcional das features da v1 (testes de característica onde a v1 já tinha).

---

## 5. N2.3 — Features de análise

**Tarefas**
- **Transcribe** (áudio→texto) e **InterpretMedia** (imagem/doc→resumo) a partir do
  **ponteiro de mídia** (baixa via URL pré-assinada do `data_storage`/R2 — nunca
  recebe o binário inline).
- **Analyse** (intents/entidades) e **Embed** (embeddings **1536**, dimensão fixada
  pelo schema pgvector `0007`).
- Cada feature: timeout próprio, tratamento de erro tipado, degradação (retorna
  vazio/plausível em vez de estourar).

**DoD:** cada feature responde contra um insumo real de teste; embeddings com 1536
dimensões; falha de provedor não derruba o serviço.

---

## 6. N2.4 — Resposta + RAG + sentimento

**Tarefas**
1. **RAG:** a resposta busca documentos de treinamento similares — o `ia_engine`
   chama um RPC de leitura no `data_postgres` (`QueryCompose { tenant_id, embedding }`)
   que faz a busca **pgvector** sob RLS e devolve os trechos de contexto. **O banco
   continua tendo uma única porta** (memória `banco-unica-porta-via-infra-rpc`): a IA
   **não** abre Postgres direto.
2. **Responder:** compõe o prompt (persona/config do tenant + contexto RAG + histórico
   recente) e gera a resposta; retorna também **sentimento** e metadados.
3. Config do tenant (persona/prompts/provider/api key) chega do `worker`
   (descriptografada via `SecretString` no Rust) no request — a IA não resolve config.

**DoD:** resposta usa contexto recuperado do pgvector do tenant correto (isolamento
validado); sentimento retornado; nenhum vazamento cross-tenant no RAG.

---

## 7. N2.5 — Integração `worker` → IA (resiliência) + mídia

**Tarefas**
1. No ponto da barreira de bot (`worker/src/main.rs`, onde hoje há resposta fixa),
   chamar o `ia_engine` via gRPC quando `bot_pode_atender` e sem atendente humano.
2. **Resiliência:** timeout + retry/backoff; **degradação graciosa** → se a IA
   falhar/estourar, cair na **resposta temporária atual** (nunca travar o fluxo);
   auditar `ia.degradada` (WARN).
3. **Mídia:** para mensagens com mídia, o worker aciona transcribe/interpret; grava
   `resumo`/`analise` + **`MediaPointer`** via `data_postgres` RPC; o binário vive no
   `data_storage` (R2). O envio da resposta reusa o caminho outbound (N1.3/`main.rs:389`).

**DoD:** mensagem entra → IA gera resposta com RAG → resposta sai pelo WhatsApp;
falha da IA degrada para o texto fixo sem erro ao usuário; mídia gera resumo
persistido; `traceparent` contínuo do webhook à resposta (validável no Tempo).

---

## 8. N2.6 — UI: resposta da IA e resumo de mídia no chat

**Tarefas**
- No `operacional_module` (chat), renderizar a resposta gerada e o **resumo/análise
  de mídia** (o atendente vê o resumo em vez de baixar o binário). Indicador visual
  de "gerado por IA". Sem lógica de IA no cliente (só exibição).

**DoD:** `flutter analyze` limpo via `.\infra\test-flutter.ps1`; resumo e resposta
aparecem no chat contra o `runtime_api` real.

---

## 9. SOLID / Ports & Adapters

- **Rust:** `worker` depende de `Arc<dyn IaEngineClient>` (port), adapter gRPC; a
  degradação é um **decorator** (`ResilientIaEngine`) que encapsula timeout/retry/fallback.
- **Python:** `FeaturesCompose` é a fachada; cada feature é um caso de uso isolado
  (SRP), provedores de LLM atrás de uma abstração (trocar OpenAI/local sem tocar a feature).
- **RAG** é um adapter que fala **só via RPC** ao `data_postgres` (DIP; sem acesso a banco).

---

## 10. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Serviço Python novo — esforço subestimado | Atrasa a fase | Timebox por feature; N2.3/N2.4 independentes; MVP da IA = resposta+RAG, análise de mídia pode vir em sub-sprint |
| Latência da IA no caminho quente | Chat "trava" | Chamada assíncrona + timeout curto + degradação; resposta do bot é best-effort |
| Vazamento cross-tenant no RAG | Falha de segurança | RAG sempre sob RLS via RPC; teste de isolamento pgvector |
| Chave de provedor em log | Vazamento de segredo | `SecretString` no Rust; regra "nunca logar api key" no Python; revisão de logs |
| `traceparent` não cruza o Python | Trace quebrado | OpenTelemetry Python extrai/injeta no metadata gRPC; validar no Tempo |

---

## 11. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N2** | Skeleton + contratos IA | Aprovar RPCs IA + `IaEngineClient` + estratégia de degradação | Skeleton→facade→features→RAG→integração→UI | `test-local.ps1` (RAG isolado, degradação) + `test-flutter.ps1` (chat) | Resposta IA ponta-a-ponta; trace contínuo; sem PII/segredo |

*Plano aterrado na v1 (`old/.../features_compose.py`), no schema pgvector 0007, na
decisão gRPC (memória) e no doc de fases 02. Pronto para `/plan-restructuring`.*
