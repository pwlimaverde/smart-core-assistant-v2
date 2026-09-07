---
type: plan
name: "Regras do bot e permissões"
planSlug: regras-do-bot-e-permissoes
description: "As sete lacunas que N9, N10, N11 e N12 não cobrem. Três decidem o produto: a confiança da IA é descartada e quem decide o transbordo é a auto-avaliação do LLM; não há como calar o bot de um número nem religá-lo numa conversa; e a fila não se distribui sozinha. Uma é segurança: qualquer usuário sem escopo explícito nasce podendo escrever, e não existe papel somente-leitura. As outras três são operação: conversa abandonada nunca encerra, ninguém é avisado de uma atribuição, e o superusuário não registra pagamento nem gere usuários."
summary: "Delta verificado contra os quatro planos existentes por busca textual: confianca, rodizio, resposta_bot, bot_pode_atender, inatividade, derivar_escopos, viewer e PaymentRecord não aparecem em nenhum deles. Levantado em 2026-09-06 a partir dos docs 29, 30, 31 e 32."
status: filled
progress: 0
generated: "2026-09-06"
scaffoldVersion: "2.0.0"
agents:
  - type: "security-auditor"
    role: "Fallback de escopos, papel somente-leitura e quem pode calar o bot"
  - type: "backend-specialist"
    role: "Faixas de confiança com veto, rodízio de atendentes e encerramento por inatividade"
  - type: "frontend-specialist"
    role: "Controles de bot na conexão e na ficha; telas do superusuário"
  - type: "architect-specialist"
    role: "Contrato de realtime com destinatário — hoje o evento não tem para quem ir"
  - type: "test-writer"
    role: "Regressão de autorização e de decisão do bot"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "security-auditor"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [rust-rapido, flutter-analise-testes]
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

# Regras do bot e permissões

> **Este plano é só o delta.** N9, N10, N11 e N12 já cobrem mídia, chat, quadro,
> ficha, IA analítica, conexões, whitelist, clientes, e-mail e cutover. O que
> sobrou são sete itens — e três deles decidem o comportamento do produto.

## Artefatos detalhados

- **Plano completo** (verdade técnica, com arquivo:linha):
  [plano_completo_regras-do-bot-e-permissoes.md](./regras-do-bot-e-permissoes/plano_completo_regras-do-bot-e-permissoes.md)
- **Documentação auxiliar**:
  [info_aux_regras-do-bot-e-permissoes.md](./regras-do-bot-e-permissoes/info_aux_regras-do-bot-e-permissoes.md)

## Fontes de requisito

- [32 — Cobertura de N9–N12 e o delta real](../../doc_dev/planejamento/32-cobertura-n9-n12-e-o-delta-real.md) — **por que estes sete e não outros**
- [30 — Fluxo ponta a ponta v1 × v2](../../doc_dev/planejamento/30-fluxo-atendimento-ponta-a-ponta-v1-x-v2.md) — F1, F2, F3, F6, F7
- [29 — Lacunas: usuários e configuração](../../doc_dev/planejamento/29-mapeamento-lacunas-v1-v2-usuarios-e-config.md) — L3 revisada, L7
- [31 — Superfície da v1](../../doc_dev/planejamento/31-superficie-completa-v1-rotas-celery-admin.md) — N3, N4 (reclassificações)

## Decisões de produto já tomadas — não reabrir

| Tema | Decisão |
|---|---|
| Faixas de confiança | 0.5 / 0.8 como padrão, **configuráveis por tenant** |
| Quem manda no transbordo | A faixa numérica tem **veto** sobre o `transferir_atendimento` do LLM |
| Baixa confiança | **Atribui** a um atendente (rodízio), não só enfileira |
| Desligar o bot | **Dois níveis**: instância e conversa, **com caminho de volta** |
| Inatividade | Encerra por inatividade, **padrão 30 min, por tenant** |

## Entregas

| Bloco | Lacuna | O que fazer |
|---|---|---|
| **D4** | L3 🚨 | **Fallback de escopos**, em 3 passos: medir → migrar → fechar. Criar papel somente-leitura. *Vai primeiro: é a única com risco de segurança ativo* |
| **D1** | F1 | Gravar `confianca_resposta` (deploy 1) → **veto por faixa** sobre o `transferir_atendimento` do LLM (deploy 2) |
| **D2** | F3 | **Rodízio** por `data_ultima_atribuicao`, respeitando `disponivel` e `max_atendimentos_simultaneos` |
| **D3** | F2 / L7 | `resposta_bot` na instância + caminho para **religar** o `bot_pode_atender` da conversa |
| **D5** | F6 | Encerramento por inatividade no scheduler (**construção nova** — a v1 não tinha) |
| **D6** | F7 | Notificar o atendente (**construção nova**; exige decisão de contrato de realtime) |
| **D7** | doc 31 | `PaymentRecord` (registro manual) e gestão global de usuários pelo superusuário |

## Sequência

```
D4                       (segurança primeiro; e mexer em permissão depois que a equipe cresce é mais caro)
D1 → D2                  (transbordar para fila que ninguém puxa é trocar resposta ruim por silêncio)
D3, D5, D7               (independentes)
D6                       (por último: depende de D2 e do realtime do desktop, que é da N9)
```

## Riscos principais

- 🚨 **D4 mexe em quem já trabalha.** Apertar o fallback sem medir antes derruba
  acesso em produção. Os três passos não são zelo — são a ordem correta.
- 🚨 **D1 muda o comportamento visível da IA.** Ligar o veto sem histórico de
  confiança é calibrar no escuro; o deploy de medição é obrigatório.
- **D6 exige decisão de contrato.** `AtendimentoEvent` não tem destinatário e o
  canal é um só por tenant: filtrar no cliente vaza atribuição alheia.
- **D3 tem uma tranca deliberada.** `desatribuir` não religa o bot **de
  propósito** (documentado no trait). A entrega acrescenta a porta, não remove a
  tranca.
- **D5 não pode disparar a pesquisa de satisfação** — conversa abandonada e
  conversa resolvida são desfechos diferentes.

## Definition of Done

- [ ] Existe papel somente-leitura, e ele **não** consegue escrever — provado por teste.
- [ ] Nenhum usuário nasce com escopo de escrita por omissão.
- [ ] `confianca_resposta` gravada em toda resposta do bot.
- [ ] Confiança abaixo do piso transfere **e atribui**, mesmo com o LLM dizendo o contrário.
- [ ] Limiares editáveis por tenant.
- [ ] Bot silenciável por instância e por conversa, **com caminho de volta**.
- [ ] Atendimento parado encerra sozinho, sem disparar pesquisa de satisfação.
- [ ] O atendente é avisado do atendimento que recebeu, sem ver os dos outros.
- [ ] Superusuário registra pagamento manual e gere usuários.
- [ ] Sensores `rust-rapido` e `flutter-analise-testes` verdes.

## Fora de escopo

Tudo o que já tem plano: **N9** (mídia, chat, quadro, ficha, realtime no
desktop), **N10** (`Analyse`, assunto, tags, entidades, upload, feedback),
**N11** (conexões, departamento, whitelist, clientes PJ, e-mail, senha, convite,
dead-letter, `CoreSettings`, expiração de assinatura, enquete/lista/botões),
**N12** (cutover) e **`cadastro-retomavel-e-pagamento`**.
