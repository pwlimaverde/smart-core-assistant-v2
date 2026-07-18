---
type: plan
name: "Fase N6 — IA no fluxo vivo (mídia, campos de IA no chat, fluxos de transferência)"
planSlug: n6-ia-fluxo-vivo
description: "Primeira fase do port final (N6–N8): liga ao pipeline de mensagens real o que a N2 entregou pronto mas não cabeado — mídia no fluxo vivo (download via RPC no data_whatsapp, análise/transcrição, R2), campos gerado_por_ia/resumo_midia reais no chat, fluxos de transferência por tenant no Responder, transcrição via Groq (ogg nativo) com fallback OpenAI, e sentimento persistido."
summary: "Fechamento funcional do porte da IA: nenhuma arquitetura nova, só cabear o que a N2 deixou pronto — com degradação graciosa preservada em todos os pontos."
status: filled
progress: 0
generated: "2026-07-18"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "Pipeline de mídia no worker/data_whatsapp/data_storage, RPCs novos, evolução aditiva do proto"
  - type: "ai-specialist"
    role: "ApiTranscriber (Groq/OpenAI), providers langchain-groq/google-genai, fluxos no Responder (ia_engine)"
  - type: "mobile-specialist"
    role: "Stubs Dart regenerados, campos reais de IA no chat (web/desktop), badge de sentimento"
  - type: "architect-specialist"
    role: "Aprovar campos do proto, ponto de download da mídia e ciclo de campos do fluxo"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-2"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
lastUpdated: "2026-07-18T12:15:30.057Z"
---

# Fase N6 — IA no fluxo vivo (mídia, campos de IA no chat, fluxos de transferência)

> Primeira fase do cronograma de **port final** (N6–N8). **Nenhuma arquitetura
> nova** — é o cabeamento do que a N2 entregou pronto e testado mas deixou
> desconectado do pipeline real. **Invariante inegociável:** a degradação
> graciosa da N2 permanece em todos os pontos novos — falha de IA nunca trava o
> atendimento.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n6-ia-fluxo-vivo.md](./n6-ia-fluxo-vivo/plano_completo_n6-ia-fluxo-vivo.md)
- **Documentação auxiliar** (libs/serviços atuais): [info_aux_n6-ia-fluxo-vivo.md](./n6-ia-fluxo-vivo/info_aux_n6-ia-fluxo-vivo.md)
- **Origem:** `doc_dev/planejamento/21-fase-N6-ia-fluxo-vivo.md` (agora histórico)

## Escopo (etapas)
| # | Foco | Estado base |
|---|---|---|
| **N6.1** | Mídia no pipeline vivo: `NormalizedMessage.media_payload` → RPC `DownloadMediaMessage` (data_whatsapp, `MediaDownloader` **já existe**) → R2 + `Transcribe`/`InterpretMedia` → resumo/análise persistidos | URL do WhatsApp expira ~1h — download imediato pós-ingestão |
| **N6.2** | `MensagemThread.gerado_por_ia = 8` / `resumo_midia = 9` (aditivo) + persistência + UI real | colunas já existem; UI existe com dado fixo |
| **N6.3** | `ListarFluxosDoTenant` + ciclo `campos_coletados`/`campos_pendentes` no `Responder` | proto do Responder já tem os campos; sem DSL nova |
| **N6.4** | `ApiTranscriber` (primary Groq `whisper-large-v3-turbo`, ogg nativo; fallback OpenAI) + langchain-groq/google-genai instalados (`output_dimensionality=1536` obrigatório) | SDK `openai` direto; docs em `doc_dev/libs/python/` |
| **N6.5** | Sentimento chamado, persistido e exibido (best-effort) | RPC pronto desde a N2 |

## Sequenciamento
**N6.1 → (N6.2 ‖ N6.4) → N6.3 → N6.5.** Correções da reestruturação (reuso do
`MediaDownloader`, `media_payload` em vez de URL, Groq como primary de
transcrição, dimensão 1536) no [plano completo](./n6-ia-fluxo-vivo/plano_completo_n6-ia-fluxo-vivo.md).

## Fases (PREVC)
- **P:** confirmar campos do proto (8/9), flag de transcrição por tenant e limite de tamanho de mídia.
- **R:** aprovar ponto de download (worker pós-persistência, via data_whatsapp) e ciclo de campos do fluxo (mínimo da v1 portada).
- **E:** N6.1→N6.5 em incrementos, cada um com Observabilidade & Auditoria do plano completo.
- **V:** `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1` + `uv run task test` + mídia real em dev (áudio ogg via WhatsApp → R2 + transcrição + selo IA no chat).
- **C:** changelog, gate `prevc-final-review`, arquivamento.

## Execution History

> Last updated: 2026-07-18T12:15:30.057Z | Progress: 0%
