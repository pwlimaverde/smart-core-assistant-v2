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
| P7 | ✅ Whitelist, conexão→departamento, detalhe da conexão | `WhiteList`, `AppInstance.departamento`, `logout/` | Três cadastros sem tela | ⬜ |
| P8 | ✅ Mensageria fiel: enquete, lista, botões, reação, contatos | Normalização da v1 + evento `CONTACTS` | Hoje cai tudo em "Other" | ⬜ |
| P9 | ✅ Admin do superusuário: pagamento, usuários, dead-letter, settings | `PaymentRecord`, `User`, `CoreSettings` export/import, `test-connection` | Backoffice incompleto | ⬜ |
| P10 | ✅ Celery: expiração de assinatura e campos automáticos | `check_subscription_expirations`, `extract_custom_fields_async` | Fecha o placar das 11 tarefas | ⬜ |
| P11 | ✅ App Windows: motor local no DI e atualização | `LocalEngineFfiDataSource` sem registro | O app é o produto; hoje não tem modo offline nem aviso de versão | ⬜ |
| P12 | ✅ Varredura final de paridade | 115 rotas da v1 | Fecha o port com evidência, não com memória | ⬜ |

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
| P7 | `0511a17` | ✅ Rust 35458880967 | Números ignorados (a "whitelist", renomeada pelo que faz) com tela própria; conexão → departamento no roteamento da ingestão; detalhe da conexão; encerrar a sessão sem remover a conexão. |
| P8 | `a10c373` | ✅ Rust 35458880967 | Enquete, lista, botões e vários contatos normalizados com `metadados`; reação aplicada na mensagem alvo (não vira bolha); consumidor do evento `CONTACTS` que só atualiza quem já existe. |
| P9 | `6bb4b36` | ⏳ | Mensagens não entregues (dead-letter) na tela de conexões; testar provedor de IA; exportar/importar CoreSettings sem vazar valor cifrado. |
| P10 | `9e7a376` | ✅ Rust 35458880967 | Guarda de confiança no write-back de campos (a IA rebaixava valores) e evento `atendimento.campos_atualizados` para a ficha aberta. |
| P11 | `2258530` | ⏳ | Carimbo de build no binário Windows, `GetVersaoDoApp` sobre três chaves fechadas das CoreSettings e faixa de versão nova no quadro. |
| P12 | — | — | Varredura abaixo. |

### P12 — Varredura final das rotas da v1

Refeita contra a lista fechada do doc 31 §5 (as rotas da v1 sem equivalente
na v2 em 2026-09-06) e contra o código de hoje. Toda linha tem destino.

| Rota v1 | Destino na v2 |
|---|---|
| `tenant-admin/**` (20 modelos) | Todos com tela: `CampoPersonalizado`/`ValorCampo` (N9 E13 + ficha), `Cliente` (B10), `WhiteList` (P7), `AppInstance.departamento` (P7). |
| `configuracoes/whitelist*` (6 rotas) | P7 — `ListMyNumerosIgnorados` e CRUD, tela `/tenant/ignorados`. |
| `usuarios/password-reset*` (4 rotas) | `SolicitarRedefinicaoSenha` / `RedefinirSenha` (`auth.proto`). |
| `apps/tenants/users/<id>/permissions/` | `UpdateTenantUser` (papel, módulos e fluxos). |
| `apps/tenants/users/invite/<id>/resend/` | `ReenviarConvite`. |
| `apps/tenants/bo/tenant/<id>/register-payment/` | `RegisterPayment` + tela de cobrança do admin. |
| `apps/tenants/config/test-connection/<tipo>/` | `TestEvolutionConnection` e, no P9, `TestarProvedorIa`. |
| `workspace/kanban/api/export/` | P4 — `ExportarQuadro`. |
| `workspace/kanban/api/conversations/<id>/timeline/` | P5 — `ListarTimelineAtendimento`. |
| `workspace/kanban/api/conversations/<id>/custom-fields/<slug>/` | `SetMyValorCampo` + write-back da IA (C1, guardas no P10). |
| `workspace/chat/api/conversations/<id>/upload/` | `SolicitarUploadMidia` + `EnviarMidiaAtendimento` (tela no P3). |
| `workspace/chat/api/conversations/<id>/medias/` | `ListarMidiasAtendimento` (galeria no P3). |
| `workspace/chat/api/messages/<id>/media/` | URL assinada em `MidiaMensagem`. |
| `workspace/chat/api/conversations/<id>/mark-read/` | `MarcarAtendimentoLido`. |
| `workspace/chat/api/notifications/unread-count/` | `nao_lidas` por atendimento no quadro + filtro "não lidas" (P1). |
| `workspace/chat/api/conversations/<id>/presence/` | P3 — `EnviarPresenca` e evento `whatsapp.presenca`. |
| `treinamento/feedback-resposta/` | `RegistrarFeedbackTeste`. |
| `sync/evolution/instances/<pk>/toggle-bot/` | `DefinirRespostaBotInstancia` (D3). |
| `sync/evolution/instances/<pk>/logout/` | P7 — `DesconectarMyWhatsappInstance`. |
| `sync/evolution/instances/departments/` | P7 — `DefinirDepartamentoDaConexao`. |

**Decisões de não portar**, registradas para não voltarem como lacuna:

- **Trello** (14 tarefas e as rotas de `trello_sync`) — substituído pelo motor
  interno de fluxos, por decisão do usuário.
- **Várias instâncias da Evolution** — um servidor evolution-go único.
- **`notify_expiring_subscriptions`** — era stub na v1 (só log, com um
  "implementar envio de e-mail futuramente"). O aviso de assinatura da v2 é a
  faixa do quadro (`AvisoAssinatura`); portar o stub seria portar uma ilusão.

As 11 tarefas não-Trello do Celery ficam todas com equivalente: as nove do doc
31 §3 já estavam, `check_subscription_expirations` é o
`suspender_assinaturas_vencidas` do scheduler, e `extract_custom_fields_async`
é o write-back do C1 com a guarda de confiança que faltava (P10).

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
- **A IA rebaixava valores de campo** (P10): a v1 só trocava por confiança
  maior; a v2 trocava sempre. Um e-mail lido com 0,95 virava o palpite de 0,6
  da décima mensagem.
- **Reação virava bolha solta no chat** (P8), e enquete/lista/botões chegavam
  vazias — o ramo genérico da normalização procurava `url`/`caption`.
- **O reprocessamento de dead-letter existia desde a N7.2 sem tela** (P9): a
  mensagem do atendente ficava parada e ninguém sabia que não tinha chegado.
- **Duas premissas do cronograma estavam velhas**: pagamento manual e gestão
  global de usuários já existiam (P9), e o motor local já era o gateway do
  desktop (P11). Registrado para o inventário não ser reaberto por memória.
- **Nome gerado do contrato colide com modelo de domínio** no Dart: o
  `dependencies_module` reexporta o `api_client`, e um `MensagemNaoEntregue`
  do domínio ficou ambíguo com o gerado. O modelo virou `MensagemParada`.
