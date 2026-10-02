---
type: plan
name: "Correções do app Windows (smart-core-tenant)"
planSlug: correcoes-app-windows-flutter
description: "Corrige oito problemas do app Windows do tenant: a mensagem que pisca no topo e desce (id negativo da pendente local e 4–6 recargas da thread por mensagem), refeita com buffer de eventos no servidor (Redis, janela de 5 s, dedup por message_id) e agrupamento visual; mídias que não aparecem na bolha; gravação de áudio; Ctrl+V de imagem; transferência automática pela IA; rolagem vertical das colunas do kanban; e fotos dos contatos."
summary: "Ordem: P1.1-B, P1.1-A, P1, P1.1-D, P5, P2a, P2b, P6, P3; P4 em paralelo. Cada fase traz logs/traces, auditoria e sanitização (URL assinada, telefone, texto e mediaKey fora de log). Libs novas avaliadas: media_kit (vídeo/áudio no Windows) e super_clipboard ou pasteboard (imagem do clipboard). Nenhum teste roda na máquina local: CI e deploy da dev."
status: filled
progress: 0
generated: "2026-10-01"
scaffoldVersion: "2.0.0"
agents:
  - type: "architect-specialist"
    role: "Desenho do buffer de eventos (P1.1) e fronteiras: webhook sem regra pesada, dados só via RPC aos data_*"
  - type: "backend-specialist"
    role: "Buffer e coalescência no worker/data_redis, download e presign de mídia (data_whatsapp/data_storage), envio de áudio, avatar dos contatos"
  - type: "frontend-specialist"
    role: "Chat (id da pendente, recargas, agrupamento), bolhas de mídia, gravação, Ctrl+V, rolagem do kanban, avatar"
  - type: "ai-specialist"
    role: "P4 — transferência automática no worker/ia_engine, alinhada ao plano ia-engine-jev"
  - type: "security-auditor"
    role: "URL assinada, telefone, mediaKey e conteúdo de conversa fora de log, span e auditoria"
  - type: "devops-specialist"
    role: "Build Windows com as libs nativas novas e validação na dev"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "completed"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "frontend-specialist"
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
lastUpdated: "2026-10-01T00:00:00.000Z"
---

# Correções do app Windows (smart-core-tenant)

> **Branches:** uma `feature/*` por fase a partir da `dev` (gitflow).
> **Restrição:** nenhum teste na máquina local; `dart analyze`/`cargo check` e testes na CI, validação no deploy da dev.
> **Estado do MCP:** canônico escrito à mão em 2026-10-01 porque o servidor dotcontext não conectou.
> Pendentes: `scaffoldPlan` (só se for preciso registrar), `workflow-init`, `plan link`,
> `workflow-advance` até E e `plan syncMarkdown`.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_correcoes-app-windows-flutter.md](./correcoes-app-windows-flutter/plano_completo_correcoes-app-windows-flutter.md)
- **Documentação auxiliar**: [info_aux_correcoes-app-windows-flutter.md](./correcoes-app-windows-flutter/info_aux_correcoes-app-windows-flutter.md)
- **Libs na central**: `doc_dev/libs/flutter/{record,http,media_kit,super_clipboard,just_audio,video_player,connectivity_plus,path_provider,flutter_bloc}.md`, `doc_dev/libs/rust/{redis,tokio,sqlx,tracing,serde,aws_sdk_s3}.md`

## Origem
Plano elaborado em conversa (2026-10-01), sem arquivo em `doc_dev/`. A partir daqui este canônico
e o plano completo são a fonte da verdade.

## Fases de execução (dentro de E)

| Ordem | Fase | Entrega | Aceite |
|---|---|---|---|
| 1 | **P1.1-B** | coalescência dos eventos de thread por conexão no `runtime_api` (janela 300 ms, teto 1 s), `Lagged` vira recarga única | ≤ 2 eventos de thread por mensagem na conexão |
| 2 | **P1.1-A** | recarga single-flight no `ChatController`, status por patch, sem recarga própria após envio | 1 recarga por mensagem (hoje 4–6) |
| 3 | **P1** | ordem por (timestamp, id) com pendente no fim, chave estável pelo `action_id`, pendente antiga descartada | a mensagem enviada não aparece no topo nem pula |
| 4 | **P1.1-D** | agrupamento por remetente (≤ 2 min) e separador de dia | rajada vira bloco; teste da função na CI |
| — | P1.1-C | buffer persistente para replay após reconexão | fora do escopo (evolução futura) |
| 5 | **P5** | rolagem vertical dentro das colunas do kanban | coluna longa rola com roda e arrasto |
| 6 | **P2a** | imagem, áudio, vídeo e documento na bolha | os quatro tipos abrem no Windows |
| 7 | **P2b** | gravação de áudio ponta a ponta | áudio gravado chega no WhatsApp do contato |
| 8 | **P6** | fotos dos contatos | avatar aparece e se renova quando a URL expira |
| 9 | **P3** | Ctrl+V de imagem no campo de mensagem | imagem colada vira anexo; texto continua colando |
| — | **P4** (paralelo) | transferência automática pela IA | regra ativa transfere e grava `atendimento.transferido_por_ia` |

## Correções da reestruturação (resumo)
C1 a janela de 5 s do `buffer_mensagens` é da IA, não da tela — coalescência curta no `runtime_api`;
C2 dedup por `message_id` já existe no ingresso; C3 causa do pulo: ordenação por id + pendente
negativa que sobrevive à recarga; C4 a tela recarrega e reabre o stream depois de enviar;
C5 a bolha não desenha a mídia (só o resumo); C6 `video_player` não roda no Windows → `media_kit`;
C7 gravador em AAC enviado como PTT, sem tratamento de erro; C8 vazamento de URL assinada e
telefone no span do `send_media`; C9 roda do mouse sequestrada pelo quadro; C10 foto só via
`CONTACTS` e URL do CDN expira, quadro não renova; C11 colar imagem não existe;
C12 transferência por IA sai em silêncio sem campos; C13 exemplos dos relatórios descartados;
C14 central de libs atualizada. Detalhe no plano completo §2.

## Execution History

> Last updated: 2026-10-02 | Progress: E concluída (aguardando review e validação na dev)
> Branch única de implementação: `feature/correcoes-app-windows-flutter-impl` (fases integradas por cherry-pick;
> não foram criadas as `feature/*` por fase).

| Fase | Commits | Situação | Observações |
|---|---|---|---|
| P1.1-B | `60c0472`, `d6655ba`, `0f0981b`, `0845158`, `3098ae64` | CI verde | 4 commits de correção após a CI (assinatura do port, aridade, testes que não exercitavam o código). Eco `fromMe` já persistido não publica `mensagem.recebida` |
| P1.1-A | `5bfe076` | CI verde | `connectivity_plus` sem uso no código: item 7 sem ação. Nova dev_dependency `fake_async` |
| P1 | `d599d84` | CI verde | `ordenarParaExibir` no domínio; `ValueKey(id)` + `findChildIndexCallback` |
| P1.1-D | `4c338b8` | CI verde | Ticks somem no meio do bloco, exceto `falhou` |
| P5 | `0fe605b` | CI verde | Shift+roda move o quadro (registrar no changelog) |
| P2a | `35dc95ca` (servidor), `04d91846` (cliente), `66db8167` (sqlx), `395c6ad0` (fix) | CI verde | `media_kit` ^1.2.6, `media_kit_video` ^2.0.1, `media_kit_libs_windows_video` ^1.0.11, `url_launcher`. `is_ptt` em `metadados.ptt`. Backfill de `mimetype_midia` no corpo do commit (não executado) |
| P2b | `f11866b3` (servidor), `88e57dbb` (cliente), `395c6ad0` (fix) | CI verde (etapa 1) | Etapa 2 (PTT) **pendente**: confirmar flag de voz/rota de áudio e conversão ogg/opus na tag da evolution-go. Campo `filename` (minúsculo) não confirmado no código-fonte da tag |
| P6 | `a4af1299` (servidor), `5ae99e57` (cliente) | aguardando CI | Rota nova `DestinoDaFotoDoContato`; kanban agenda até 20 sincronizações por listagem. SQL de limpeza de `foto_perfil_url_origem` no corpo do commit (não executado) |
| P3 | `8459b3e8` | aguardando CI | Plano B `pasteboard` ^0.5.0 (`super_native_extensions` não é compatível com `--wasm`); BMP do Windows convertido para PNG |
| P4 | `643ce1f` | CI verde | Diagnóstico na dev: tenant no motor `jev`, 3 regras ativas, nenhuma decisão de transferir em `oraculo_decisao_ia` → a falha é do motor Jev (J3 do `ia-engine-jev`), não do worker. H1 improvável no Jev; H2/H3 a confirmar pelo span `ia.transferencia` após o deploy |

Pendências fora do código: a CI não tem build Windows — `media_kit_libs_windows_video` (download do libmpv no
CMake) e `pasteboard` só se validam no build do app Windows; executar na dev os SQLs de backfill (P2a) e limpeza (P6);
registrar no `ia-engine-jev` (J3) o achado da P4; avaliar `bot.silenciado` em sequência no audit_log da dev.
