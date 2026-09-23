---
type: plan
name: "Paridade com a v1 — fechamento do port no app Windows"
description: "Doze blocos (P1–P12) que fecham o que a v1 fazia e a v2 ainda não faz, com o app Windows como alvo. Fora de escopo: Trello e a camada multi-instância da Evolution."
planSlug: paridade-v1-fechamento
generated: "2026-09-15"
summary: "Fechar a paridade com a v1: busca e filtros da conversa; conversa fiel ao WhatsApp Web; quadro operável; ficha completa; SLA; whitelist e roteamento por conexão; mensageria fiel; backoffice do superusuário; tarefas do Celery; motor local do desktop."
agents:
  - type: "backend-specialist"
    role: "Contrato, data_postgres, runtime_api e worker"
  - type: "frontend-specialist"
    role: "App Windows (Flutter) — quadro, conversa e cadastros"
  - type: "test-writer"
    role: "Testes de unidade e de tela por bloco"
  - type: "security-auditor"
    role: "PII em log e auditoria; RBAC de cada rota nova"
docs:
  - "architecture.md"
  - "data-flow.md"
  - "security.md"
  - "testing-strategy.md"
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
    status: "completed"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "completed"
    required_sensors: [tests-passing]
    required_artifacts: [handoff-summary]
    steps:
      - order: 1
        description: "P1 — busca e filtros da conversa (q, atendente, não lidas, etiqueta, prioridade)"
        assignee: "backend-specialist"
      - order: 2
        description: "P2 — citação, ticks de entrega/leitura, separador de dia, paginação por before_id"
        assignee: "frontend-specialist"
      - order: 3
        description: "P3 — presença digitando/gravando, áudio PTT, galeria com lightbox e download"
        assignee: "frontend-specialist"
      - order: 4
        description: "P4 — atribuir, transferir de fluxo na borda, definir prioridade, exportar o quadro"
        assignee: "backend-specialist"
      - order: 5
        description: "P5 — timeline do atendimento, histórico do contato, remover nota, catálogo de etiquetas"
        assignee: "backend-specialist"
      - order: 6
        description: "P6 — gravar data_primeira_resposta e mostrar a mediana no painel"
        assignee: "backend-specialist"
      - order: 7
        description: "P7 — whitelist, departamento por conexão, detalhe e logout da sessão"
        assignee: "backend-specialist"
      - order: 8
        description: "P8 — normalizar enquete/lista/botões/reação e handler do evento CONTACTS"
        assignee: "backend-specialist"
      - order: 9
        description: "P9 — backoffice do superusuário: pagamento, usuários, dead-letter, settings, testar conexão"
        assignee: "backend-specialist"
      - order: 10
        description: "P10 — tarefas do Celery que faltavam: expiração de assinatura e campos automáticos"
        assignee: "backend-specialist"
      - order: 11
        description: "P11 — motor local no DI do app Windows e aviso de versão nova"
        assignee: "frontend-specialist"
      - order: 12
        description: "P12 — varredura das 115 rotas da v1, com destino ou decisão de não portar"
        assignee: "test-writer"
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "completed"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "completed"
status: done
progress: 0
scaffoldVersion: "2.0.0"
lastUpdated: "2026-09-19T21:54:19.938Z"
---

# Paridade com a v1 — fechamento do port no app Windows

> Levantado do **código** da v1 em `old/smart-core-assistant-painel`, não só dos
> documentos: 21 modelos do tenant-admin, 10 endpoints da conversa, 13 do
> quadro, 30 comportamentos do `chat_alpine.js` e 11 tarefas Celery não-Trello.

## O alvo

O produto é o **app Windows** do tenant. A web só será lançada se houver
necessidade. Cada bloco termina com a CI verde e o zip do app reempacotado.

## Fora de escopo, por decisão do usuário

- **Trello** — substituído pelo motor interno de fluxo;
- **camada multi-instância da Evolution** — hoje um servidor único
  (evolution-go), com sincronização própria.

## O gabarito da conversa (v1 `chat_alpine.js` + `selectors.py`)

| Comportamento | v1 | v2 hoje |
|---|---|---|
| Buscar conversa (nome, perfil, telefone, assunto) | `list_conversations(q=…)` | ❌ |
| Filtrar por fluxo, atendente, etiqueta, prioridade, não lidas | idem | ❌ |
| Ordenar pela última mensagem | `-data_ultima_mensagem` | ⚠️ ordena por início |
| Paginar histórico para trás | `get_messages(before_id=…)` | ❌ |
| Citar mensagem | `setReplyTo` | ⚠️ proto tem, UI não |
| Ticks de entrega/leitura | `statusEnvioIcon` | ⚠️ modelo tem, bolha não |
| Separador de dia e agrupamento | `enrichedMessages` | ❌ |
| Presença digitando/gravando | `_sendPresence` | ⚠️ evento existe, UI não |
| Áudio PTT | `startRecording` | ❌ |
| Galeria e lightbox | `medias/` | ⚠️ RPC existe, tela não |
| Marcar como lida | `mark-read/` | ✅ |
| Enviar mídia | `upload/` | ✅ |

## Critérios de aceite por bloco

- **P1** — numa conta com 500 conversas, achar por telefone em menos de 1 s;
  filtro "minhas" e "não lidas" combináveis; a lista ordena pela última mensagem.
- **P2** — citar responde ao trecho certo; os ticks mudam com o status real;
  o dia separa as bolhas; rolar para cima carrega o histórico sem pular.
- **P3** — "digitando" aparece para o outro lado; gravar e enviar áudio funciona
  no Windows; a galeria abre e baixa o arquivo.
- **P4** — atribuir muda o dono e avisa a pessoa (B5 já publica o evento);
  transferir de fluxo pela tela; prioridade visível no cartão; exportar gera CSV
  e é auditado.
- **P5** — a timeline mostra abertura, movimentos, transferência, atribuição e
  avaliação; nota pode ser excluída; etiqueta pode ser renomeada e desativada.
- **P6** — `data_primeira_resposta` é gravada uma vez, na primeira resposta.
- **P7** — número na whitelist não vira atendimento; conexão roteia para o
  departamento; a tela de detalhe mostra o telefone pareado e desconecta.
- **P8** — enquete, lista, botões e reação chegam com conteúdo legível; o nome e
  a foto do contato sincronizam.
- **P9** — pagamento manual registrado; usuários geríveis pelo superusuário;
  dead-letter reprocessável; settings exportáveis; testar conexão responde.
- **P10** — assinatura vencida suspende sozinha; campos automáticos extraídos.
- **P11** — o app roda offline com o motor local e avisa quando há versão nova.
- **P12** — as 115 rotas da v1 conferidas uma a uma, com destino ou decisão.

## Evidência

Cada bloco: commit próprio, CI verde, e o andamento no
`doc_dev/planejamento/37-cronograma-paridade-v1-fechamento.md`.

## Execution History

> Last updated: 2026-09-19T21:54:19.938Z | Progress: 0%

### phase-c [DONE]
- Started: 2026-09-19T21:54:19.938Z
- Completed: 2026-09-19T21:54:19.938Z

### phase-e [DONE]
- Started: 2026-09-19T21:54:19.906Z
- Completed: 2026-09-19T21:54:19.906Z

### phase-p [DONE]
- Started: 2026-09-19T21:54:19.846Z
- Completed: 2026-09-19T21:54:19.846Z

### phase-r [DONE]
- Started: 2026-09-19T21:54:19.885Z
- Completed: 2026-09-19T21:54:19.885Z

### phase-v [DONE]
- Started: 2026-09-19T21:54:19.921Z
- Completed: 2026-09-19T21:54:19.921Z
