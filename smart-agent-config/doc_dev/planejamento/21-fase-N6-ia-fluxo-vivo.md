# Fase N6 — IA no fluxo vivo (mídia, campos de IA no chat, fluxos de transferência)

> **Status:** Plano de execução — criado em **2026-07-17**. Primeira fase do
> cronograma de **port final** (N6–N8) — ver
> [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md).
> **Idioma:** Português (comunicação/documentação). Código e identificadores em inglês.
> **Objetivo:** ligar ao pipeline de mensagens **real** o que a fase N2 entregou
> pronto e testado mas deixou desconectado (pendências registradas no changelog da
> N2). Nenhuma arquitetura nova: é cabeamento do que já existe.

---

## 0. Estado real (aterramento)

| Área | Estado | Impacto |
|---|---|---|
| `ia_engine` (6 RPCs) | ✅ `Transcribe`/`InterpretMedia`/`Analyse`/`Embed`/`Responder`/`Sentimento` implementados e testados (35 testes) | N6 só liga os 4 primeiros ao fluxo — nenhum RPC novo |
| Barreira de bot | ✅ `Embed` → `QueryCompose` (RAG) → `Responder` com degradação graciosa | Padrão de resiliência (`ResilientIaEngine`) a reaproveitar nas novas chamadas |
| `NormalizedMessage` | ⚠️ Sem URL de mídia — mensagens de mídia não chegam com o ponteiro ao worker | Bloqueia N6.1 — é o primeiro passo |
| Proto do chat (`operacional`) | ⚠️ Sem `gerado_por_ia`/`resumo_midia` — UI Flutter já exibe, mas recebe dado fixo | Evolução **aditiva** do proto (nunca renumerar campos) |
| `Responder` | ⚠️ `fluxos_disponiveis`/`campos_coletados`/`campos_pendentes` chegam vazios | Bot não consegue transferir para fluxo correto |
| Transcrição de áudio | ⚠️ `PendingTranscriber` (interface completa, provedor ausente); só `langchain-openai` instalado | Groq/Google degradam graciosamente mas não funcionam |

## 1. Escopo

### Dentro do escopo
- **N6.1** Mídia no pipeline vivo: URL de mídia no `NormalizedMessage`
  (`domain_whatsapp`), worker baixa/encaminha para `Transcribe`/`InterpretMedia`/
  `Analyse` via `ResilientIaEngine`, persiste `resumo`/`analise` + `MediaPointer`
  via RPC `data_postgres`; binário no `data_storage` (R2) como já desenhado na F5.5.
- **N6.2** Campos `gerado_por_ia` e `resumo_midia` no proto do chat (aditivo),
  persistidos pelo backend e mapeados no `api_client`/UI (o widget já existe).
- **N6.3** Resolução de fluxos de transferência por tenant no `Responder`:
  preencher `fluxos_disponiveis` (RPC ao `data_postgres` — fluxos do tenant) e o
  ciclo `campos_coletados`/`campos_pendentes`.
- **N6.4** Transcrição de áudio real (provedor de voz no lugar do
  `PendingTranscriber`) + dependências Groq/Google GenAI instaladas de fato no
  `pyproject.toml` (hoje degradam sempre).
- **N6.5** Sentimento ligado ao fluxo: persistência do score e exibição.

### Fora do escopo
- Novos modelos/provedores além dos já previstos; mudanças na arquitetura de
  degradação graciosa (ela permanece a rede de segurança).

## 2. Contrato de observabilidade (DoD transversal)

- `traceparent` cruza worker → ia_engine → data_* em todas as chamadas novas.
- Nenhum conteúdo de mensagem/mídia em log (só ids/hashes/durations).
- Falha de IA em qualquer ponto degrada graciosamente (`bot.degradado`, WARN) —
  nunca trava o atendimento (invariante da N2 preservada).
- Persistência de resumo/análise audita `midia.analisada` (sem o conteúdo).

## 3. SOLID / Ports & Adapters

- Worker continua chamando a IA só via o port `IaEngineClient` (nenhum `tonic`
  direto em handler).
- `domain_whatsapp` permanece sem I/O — a URL de mídia é dado, o download é do
  orquestrador.
- Python: features seguem o padrão RSOE (`py-return-success-or-error`), erro
  fechado por feature (memória `ia-engine-padrao-rsoe`).

## 4. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Download de mídia no caminho quente do worker | Latência/backlog no bus | Download assíncrono pós-persistência do bruto; timeout curto; a mensagem nunca espera a análise para aparecer no chat |
| Evolução do proto do chat quebrar clients | Web/desktop dessincronizados | Evolução aditiva comprovada (campos 14/15 do Envelope); regerar stubs nos dois lados no mesmo ciclo |
| Provedor de voz (custo/latência) | Transcrição cara ou lenta | Feature flag por tenant (`CoreSettings` já suporta); transcrição off por padrão |
| Ciclo de campos do fluxo (estado conversacional) | Complexidade de máquina de estados | Começar pelo mínimo da v1 portada (`FeaturesCompose` já modela); não inventar DSL nova |

## 5. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N6** | Mapear campos exatos do proto + pontos de persistência | Aprovar evolução do proto e ponto de download da mídia | N6.1→N6.5 em incrementos | `.\infra\test-local.ps1` + testes Python (`uv run task test`) + mídia real em dev | changelog + gate `prevc-final-review` |

**DoD da fase:** mensagem de áudio/imagem recebida gera transcrição/resumo
persistidos e visíveis no chat com o selo "gerado por IA" real; bot transfere
para o fluxo correto do tenant; falha de qualquer provedor degrada sem travar.

*Plano aterrado nas pendências registradas do ciclo N2 (changelog 2026-07-10).
Pronto para `/plan-restructuring` quando a fase for iniciada.*
