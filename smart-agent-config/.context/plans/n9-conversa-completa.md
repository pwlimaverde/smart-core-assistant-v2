---
type: plan
name: "Fase N9 — A conversa completa (mídia, leitura, presença, busca, ficha)"
planSlug: n9-conversa-completa
description: "Caminho crítico do port v1→v2. Hoje a v2 trata a mensagem como texto: o atendente não envia mídia e não vê a que recebe (só o resumo textual da IA), não marca lida, não sinaliza presença, não cita mensagem, não busca conversa e não vê campos personalizados, galeria ou linha do tempo. Quatro capacidades do servidor estão prontas e sem nenhum chamador (SendWhatsappMedia, MarkWhatsappMessageRead, SetWhatsappPresence, GetWhatsappProfilePicture), além de TransferirAtendimentoParaFluxo que só a IA usa. Quatro entregas: N9a mídia, N9b leitura/presença/citação, N9c busca e operação do quadro, N9d ficha completa."
summary: "É o que o atendente sente em toda conversa e o que hoje o legado faz melhor. Boa parte é ligar o que já existe e foi testado. Única incógnita técnica real: video_player não suporta Windows — spike de media_kit no início da N9a."
status: filled
progress: 0
generated: "2026-08-09"
scaffoldVersion: "2.0.0"
agents:
  - type: "backend-specialist"
    role: "RPCs de mídia/leitura/presença/citação/busca, presign R2, extensões aditivas do proto e métodos concretos no grpc_web.rs"
  - type: "frontend-specialist"
    role: "Composer com anexo e gravação, bolha com mídia e ticks, lightbox, busca e filtros, ficha completa"
  - type: "mobile-specialist"
    role: "Spike de media_kit (vídeo no Windows), codec de gravação por plataforma, file_picker Web × desktop"
  - type: "architect-specialist"
    role: "Aprovar o fluxo de upload em duas etapas (presign PUT) e a política de TTL das URLs assinadas"
  - type: "security-auditor"
    role: "URLs assinadas como credencial, auditoria de acesso a mídia e de exportação em massa"
  - type: "test-writer"
    role: "Cobertura das telas novas (ratchet do CI) e regressão do chat"
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
  - id: "phase-e"
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
---

# Fase N9 — A conversa completa

> **Caminho crítico** do backlog N8.5–N12. **Depende de N8.5** (o buffer de
> agregação muda o fluxo por onde a mídia passa). **Invariante:** binário nunca
> trafega no gRPC — upload e leitura por URL pré-assinada do R2, com TTL curto e
> tratada como credencial.
>
> ⚠️ **Antes de escrever qualquer chamada HTTP à Evolution, leia o aviso do
> `info_aux`**: o contrato da evolution-go **não** é o da Evolution API v2; a
> fonte da verdade é `infrastructure_evolution/src/provider.rs`.

## Artefatos detalhados
- **Plano completo** (verdade técnica): [plano_completo_n9-conversa-completa.md](./n9-conversa-completa/plano_completo_n9-conversa-completa.md)
- **Documentação auxiliar**: [info_aux_n9-conversa-completa.md](./n9-conversa-completa/info_aux_n9-conversa-completa.md)
- Referências brutas: [ref_evolution_go.md](./n9-conversa-completa/ref_evolution_go.md) · [ref_cloudflare_r2.md](./n9-conversa-completa/ref_cloudflare_r2.md)

## Origem
- [27-mapa-telas-rotas-v2.md](../../doc_dev/planejamento/27-mapa-telas-rotas-v2.md) §A.3 e §D.1
- [26-levantamento-paridade-v1-v2.md](../../doc_dev/planejamento/26-levantamento-paridade-v1-v2.md) §3.5

## Entregas

| Bloco | Etapas | Entregável |
|---|---|---|
| **N9a** mídia | E1–E3 | enviar anexo, ver/baixar mídia recebida, gravar áudio |
| **N9b** conversa real | E4–E8 | marcar lida + não lidas, presença, citação, ticks, separador de dia |
| **N9c** quadro operável | E9–E12 | busca e filtros, prioridade, atribuir, exportar, preview e foto no cartão, modos de foco |
| **N9d** ficha | E13–E15 | campos personalizados (catálogo + valor), galeria, linha do tempo, catálogo de etiquetas, excluir nota |

## Riscos principais
- 🚨 **`video_player` não suporta Windows** — spike de `media_kit` no início da
  E2; fallback: abrir no player do sistema via `url_launcher`. Imagem e áudio não
  dependem disso; **não travar a fase por vídeo**.
- Codec de gravação difere entre Web e Windows — decidir no spike.
- CORS do R2 (só via API, sem dashboard) com `Range` para seek de áudio.
- Quota de storage passa a morder de verdade — observar antes do enforce global (N12.3).

## Observabilidade & Auditoria (resumo)
Auditar: `mensagem.midia_enviada`, **`midia.acessada`** (acesso a dado
protegido), `atendimento.atribuido`, `.prioridade_alterada`, `.transferido`,
**`atendimento.exportado`** (exportação em massa de PII: autor, filtros e
contagem), `campo_personalizado.alterado` (campo, nunca o valor).
**Sem evento (intencional):** marcar lida e presença — alto volume, estado
operacional trivial.
**Nunca em log:** URL assinada (`SecretString`), termo de busca, valor de campo.

## Definition of Done
- [ ] Recebe áudio, ouve, responde com imagem, e o cliente recebe.
- [ ] Conversa some do contador ao ser lida; contato vê "digitando".
- [ ] Citação e ticks de entrega/leitura funcionando.
- [ ] Busca por telefone acha a conversa; filtros combinam.
- [ ] Ficha mostra campos personalizados (origem + confiança), galeria e timeline.
- [ ] `.\infra\test-local.ps1` e `.\infra\test-flutter.ps1` verdes; ratchet mantido.
