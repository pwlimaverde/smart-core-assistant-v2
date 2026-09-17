# 37 — Cronograma de paridade com a v1 (fechamento do port)

> **Origem:** varredura do código da v1 em `old/smart-core-assistant-painel`
> (não só dos documentos 26/29/30/31/32), do `admin.proto` da v2 e do banco de
> dev em 2026-09-15.
> **Branch:** `feat/paridade-v1`.
> **Fora de escopo, por decisão do usuário:** sincronização com o Trello
> (substituída pelo motor interno) e a camada de múltiplas instâncias da
> Evolution (hoje um servidor único, evolution-go).
> **Alvo:** o app **Windows** do tenant. A web só será lançada se houver
> necessidade — toda tela nova é validada no desktop.

---

## Método

Cada bloco fecha um assunto de ponta a ponta: contrato (`.proto`), servidor
(`data_postgres` → `runtime_api`), app Windows e testes. A CI precisa ficar
verde antes do próximo bloco, e o app Windows é reempacotado a cada deploy —
o usuário troca o zip para ver o resultado.

O inventário da v1 que serve de gabarito:

| Fonte | O que dá |
|---|---|
| `app/*/models.py` | 21 modelos do tenant-admin + 6 do admin do superusuário |
| `app/chat_evolution/api_urls.py` | 10 endpoints da conversa |
| `app/gestao_kanban/api_urls.py` | 13 endpoints do quadro |
| `modules/design_system/static/js/chat_alpine.js` | 30 comportamentos da conversa |
| `CELERY_BEAT_SCHEDULE` + `tasks.py` | 11 tarefas não-Trello |

---

## Blocos

| # | Bloco | Origem na v1 | Por que nesta posição | Estado |
|---|-------|--------------|-----------------------|--------|
| P1 | ✅ Busca e filtros da conversa | `conversations/?q=`, filtros do workspace | Sem busca, uma conta com 500 conversas é inoperável | ⬜ |
| P2 | ✅ Conversa fiel: citação, ticks, dia, paginação | `chat_alpine.js` (setReplyTo, statusEnvioIcon, enrichedMessages, onChatScroll) | É o que faz a tela "parecer WhatsApp" | ⬜ |
| P3 | ✅ Presença, áudio PTT e galeria | `presence/`, `startRecording`, `medias/`, lightbox | Fecha a conversa; depende de P2 (mesma tela) | ⬜ |
| P4 | ✅ Quadro: atribuir, transferir, prioridade, exportar | `board/assign`, `board/transfer-fluxo`, `export/` | Operação diária do supervisor | ⬜ |
| P5 | ✅ Ficha: timeline, excluir nota, catálogo de etiquetas | `timeline/`, `notas/<id>` DELETE, `etiquetas/` CRUD | Completa o CRM do cartão | ⬜ |
| P6 | ✅ SLA: `data_primeira_resposta` | Coluna da v1, viva | Coluna lida em 5 consultas e nunca escrita | ⬜ |
| P7 | Whitelist, conexão→departamento, detalhe da conexão | `WhiteList`, `AppInstance.departamento`, `logout/` | Três cadastros sem tela | ⬜ |
| P8 | Mensageria fiel: enquete, lista, botões, reação, contatos | Normalização da v1 + evento `CONTACTS` | Hoje cai tudo em "Other" | ⬜ |
| P9 | Admin do superusuário: pagamento, usuários, dead-letter, settings | `PaymentRecord`, `User`, `CoreSettings` export/import, `test-connection` | Backoffice incompleto | ⬜ |
| P10 | Celery: expiração de assinatura e campos automáticos | `check_subscription_expirations`, `extract_custom_fields_async` | Fecha o placar das 11 tarefas | ⬜ |
| P11 | App Windows: motor local no DI e atualização | `LocalEngineFfiDataSource` sem registro | O app é o produto; hoje não tem modo offline nem aviso de versão | ⬜ |
| P12 | Varredura final de paridade | 115 rotas da v1 | Fecha o port com evidência, não com memória | ⬜ |

---

## Detalhe por bloco

### P1 — Busca e filtros da conversa

A v1 filtrava a lista por texto (`q`), por fluxo, por etapa e por atendente, e
contava as não lidas na topbar. A v2 não tem **nenhum** RPC de busca.

- `ListAtendimentos` ganha `busca`, `atendente_id`, `somente_nao_lidos`.
- A busca casa nome do contato, telefone e o texto das mensagens recentes.
- No app: campo de busca no quadro e filtro por atendente.

### P2 — Conversa fiel ao WhatsApp Web

Da v1, comportamento a comportamento:

- **citação**: `setReplyTo`/`clearReplyTo`; o proto já tem `mensagem_citada_id`
  e `quoted_preview` — falta UI e escrita;
- **ticks**: `statusEnvioIcon` (enviado, entregue, lido) — o modelo Flutter já
  tem `statusEnvio`, a bolha não desenha;
- **separador de dia e agrupamento por autor**: `enrichedMessages`;
- **paginação para trás**: `onChatScroll` carrega o histórico antigo;
- **rolagem para o fim** ao abrir e ao chegar mensagem.

### P3 — Presença, áudio e galeria

- **presença**: `_sendPresence` (composing/recording) e `handlePresenceUpdate`;
  o evento `whatsapp.presenca` já existe no realtime — falta enviar e exibir;
- **áudio PTT**: gravar, cancelar, enviar (`_uploadAudioBlob`);
- **galeria**: `medias/` com lightbox e download — RPC já existe
  (`ListarMidiasAtendimento`), falta a tela.

### P4 — Quadro operável

- `AtribuirAtendimento` (a um atendente ou a mim);
- `TransferirAtendimentoParaFluxo` exposto na borda (hoje só a IA transfere);
- `DefinirPrioridade` — a coluna existe e ninguém escreve;
- `ExportarQuadro` (CSV), com auditoria por ser exportação de PII em massa.

### P5 — Ficha completa

- `ListarTimelineAtendimento` (eventos do atendimento: aberto, movido,
  transferido, atribuído, avaliado);
- `ListAtendimentosDoContato` (histórico do contato);
- `RemoverNota`;
- catálogo de etiquetas: `UpdateEtiqueta` e `DesativarEtiqueta`.

### P6 — SLA

`data_primeira_resposta` é gravada na primeira mensagem do atendente (ou do
bot) num atendimento que ainda não a tem, e o painel mostra a mediana do dia.

### P7 — Cadastros que faltam

- **Whitelist**: a regra já é aplicada na ingestão; faltam RPCs e tela;
- **conexão → departamento**: a v1 roteava por número;
- **detalhe da conexão**: estado, telefone pareado, e desconectar a sessão sem
  remover a conexão.

### P8 — Mensageria fiel

- normalizar `pollCreationMessage`, `listMessage`, `buttonsMessage`,
  `reactionMessage` e `contactMessage` — hoje caem em "Other" e chegam vazias;
- handler do evento `CONTACTS` da Evolution: nome e foto do contato;
- exibir reação na bolha.

### P9 — Backoffice do superusuário

- `PaymentRecord`: registrar pagamento manual (a tabela existe e está vazia);
- gestão global de usuários (a v1 tinha pelo Django admin);
- dead-letter: `ReprocessarDeadLetter` + tela;
- `CoreSettings`: exportar e importar;
- testar conexão dos provedores de IA.

### P10 — As tarefas da v1

- `check_subscription_expirations` → job do scheduler que suspende vencidos;
- `extract_custom_fields_async` → conferir o write-back do C1 com a ordem das
  cinco guardas e fechar o que faltar.

### P11 — O app Windows como produto

- registrar o `LocalEngineFfiDataSource` no DI (o modo offline existe e não é
  usado);
- aviso de versão nova e caminho de atualização — hoje o zip é trocado à mão.

### P12 — Varredura final

Reconferir as 115 rotas da v1 contra a v2, marcar o que é decisão de não
portar, e fechar o documento de paridade.

---

## Andamento

| Bloco | Commit | CI | O que entrou |
|---|---|---|---|
| P1 | `6448eb3` | ✅ 35040800069 | Busca (contato, telefone, assunto), "minhas", "não lidas", prioridade e etiqueta; ordenação pela última mensagem; dois índices; barra de busca no quadro. |
| P2 | `d947c55` | ✅ 35159979923 | `before_id` no `GetThread`; ticks de entrega/leitura na bolha; citar mensagem; separador de dia; a recarga deixou de apagar o histórico puxado. |
| P3 | `73a283c` | ✅ 35159979923 | `EnviarPresenca` na borda e presença do contato com `atendimento_id`; áudio de voz (PTT); anexo de arquivo (o gateway existia sem botão); galeria com imagem ampliada. |

| P4 | `e21458f` | ✅ 35282650965 | Atribuir/devolver à fila (auditado), prioridade com conjunto fechado, transferência de fluxo na borda e exportação CSV com `tenant:admin`. |
| P5 | `a8adf73` | ✅ 35284883697 | Timeline (UNION de movimentos, notas e etiquetas), histórico do contato, excluir nota e manutenção do catálogo de etiquetas. |
| P6 | `c7e2c3d` | ✅ 35285652733 | `data_primeira_resposta` gravada uma vez (atendente ou bot) e mediana de 24h no painel. |

### Achados fora do inventário inicial

- **`enviarMidia` existia no gateway desde a N9 e nenhuma tela o chamava**:
  anexar arquivo simplesmente não existia no app. Entrou no P3.
- **`statusEnvio` nos testes usava `'enviado'`**, valor que o servidor nunca
  produz — o teste media outra coisa. Corrigido para o vocabulário real
  (`sent`/`delivered`/`read`).
- **`dart:io` no módulo operacional quebra o smoke build web do painel admin**;
  o caminho do áudio usa `path_provider`.
- **`encaminhar_tenant` manda `flow_permissions` vazias**: toda rota operacional
  nova passa pelo `encaminhar_operacional`, senão um atendente comum não
  enxergaria os próprios cartões.
- **O piso de cobertura Flutter (78%) é um gate real**: um bloco com muita tela
  e pouco teste derruba a CI mesmo com tudo compilando.
