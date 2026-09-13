# 36 — Cronograma: pendências dos planos, de ponta a ponta

> Nasce do levantamento de 12/09 (doc 35, "Levantamento de pendências dos
> planos"). Execução em ordem, um bloco por vez. Este arquivo é a fonte de
> verdade do andamento: cada bloco só vira ✅ com o CI verde no `dev`.

## Regras de execução

1. **Confirmar antes de construir.** O levantamento foi por marcadores no
   código; cada bloco começa conferindo o que já existe, para não refazer.
2. **Ponta a ponta:** contrato → banco/sqlx → `data_postgres` → `runtime_api`
   (método concreto no `grpc_web.rs` + `rbac::MAPA`) → stubs → Flutter (RSOE) →
   testes → doc.
3. **Testes rodam no CI**, não nesta máquina. CI vermelho = corrigir e reenviar
   antes de abrir o bloco seguinte.
4. **Um commit por bloco** no `dev`, e este cronograma atualizado no mesmo
   commit.

## Blocos

| # | Bloco | Origem | Por que nesta posição | Estado |
|---|-------|--------|-----------------------|--------|
| B1 | Recuperação de senha e reenvio de convite | N11 E8 | Convidado ou usuário que perde o e-mail/senha hoje não tem saída | ✅ CI verde (`0a5ac1d`) |
| B2 | Menu por escopo, não por `isTenantAdmin` | doc 35-agentes F2 | O papel somente-leitura (D4) existe no servidor e não na tela; pré-requisito do B3 | ✅ CI verde (`e853e19`) |
| B3 | "O que o agente fez" — auditoria do próprio tenant | doc 35-agentes F1 | Fecha o DoD da N13: agente só é aceitável se auditável por quem o autorizou | ✅ CI verde (`a2de364`) |
| B4 | Limiar de confiança com veto, por tenant | regras D1 | Hoje o C1 usa 0,8 fixo; um número por tenant para "quando confio na IA" | ✅ CI verde (`79bdecf`) |
| B5 | Notificar o atendente da atribuição | regras D6 | Rodízio (D2) atribui em silêncio | ✅ CI verde (`8757195`) |
| B6 | Marcar como lida e contador de não lidas | N9 E4 | Sem isso o quadro não diz o que falta responder | ⏳ no CI |
| B7 | Ajustar permissões de um agente sem desconectar | doc 35-agentes F4 | Hoje a única saída é revogar e reconectar | ⏳ no CI |
| B8 | Descoberta dos aplicativos conectados | doc 35-agentes F5 | Recurso que precisa ser explicado por fora não foi entregue | ⬜ |
| B9 | IA analítica: assunto automático, feedback do teste, treinamento por arquivo | N10 E2, E6, E5 | Maior e mais caro; depende de nada acima | ⬜ |
| B10 | Clientes PJ e vínculo contato ↔ cliente | N11 E5 / doc 34 C4 | Entidade nova com tela própria | ⬜ |

**Fora deste cronograma:** N12 (cutover de produção) — é operação com janela
combinada, dump de produção e go/no-go; não é código a executar sozinho.

## Andamento

<!-- Cada bloco concluído ganha aqui: commit, run de CI e o que ficou de fora. -->

### B1 — Recuperação de senha e reenvio de convite

**Confirmado antes de construir:** o e-mail transacional (N11 E7) já existia
(`infrastructure_email`, SMTP/Brevo, usado pelo convite); recuperação de senha e
reenvio de convite não existiam em lugar nenhum.

**Entregue:**

- **Pedir o link** (`AuthService.SolicitarRedefinicaoSenha`, pública): responde
  "aceito" exista a conta ou não, e o e-mail sai em segundo plano para o tempo
  de resposta também não contar. Rate limit por IP (dito ao cliente) e por
  conta (silencioso). O token nasce na borda; o banco recebe só o SHA-256
  (`auth_password_reset`, migration 0033). Um pedido novo aposenta os
  anteriores. Validade de 1 hora. Conta desativada não recebe link.
- **Trocar a senha** (`AuthService.RedefinirSenha`, pública): consome o token e
  grava o hash argon2 numa transação só — dois cliques não gastam o link duas
  vezes. Link que não vale é `failedPrecondition` e senha fraca é
  `invalidArgument`, para a tela dizer "peça outro link" num caso e "escolha
  outra senha" no outro. Depois de trocar, **todas as sessões do usuário
  caem**: o Redis ganhou o índice de famílias de refresh por usuário
  (`auth:refresh_user:<id>`) e a rota `RevokeUserSessions`.
- **Reenviar convite** (`AdminService.ReenviarConvite`, `tenant:admin`): renova a
  validade e manda o mesmo link. Vencido pode; aceito ou revogado, não. Três
  reenvios por hora por convite.
- **Telas:** `/recuperar-senha` e `/redefinir-senha` no `login_module` (os dois
  apps), "Esqueci minha senha" no login, públicas nos dois guards; o link do
  e-mail sobrevive ao boot pelo `?retomar=` da rodada anterior. Botão
  "Reenviar" na tela de convites.
- **Auditoria:** `password_reset_requested`, `password_reset_completed`,
  `tenant_invite_resent`. Nem token, nem senha, nem e-mail em log.

**Fica de fora:** sessões abertas antes deste deploy não estão no índice por
usuário — expiram sozinhas no TTL do refresh. O access token já emitido segue
válido até expirar (minutos), como no logout.

### B2 — Menu por escopo, não por `isTenantAdmin`

**Confirmado antes de construir:** `tenant_drawer.dart` ainda envolvia nove itens
num `if (isTenantAdmin)`, e o guard devolvia qualquer `/tenant/*` ao quadro sem
`tenant:admin`. Cruzar tela a tela com as chamadas de abertura achou **duas
divergências no próprio servidor**, que entraram no bloco:

- **Fluxos:** a borda exigia `kanban:admin` para escrever em fluxo e coluna, e o
  banco exigia `operacional:admin`. Um `manager` com `kanban:admin` passava na
  borda e era recusado no banco — exatamente o caso que a N13.3 quis liberar.
  O banco passou a aceitar `kanban:admin` também.
- **Contatos:** a borda exigia `clientes:read` para listar, e o banco já aceitava
  `atendimentos:read`. Um `staff` convidado com os escopos padrão
  (`atendimentos:*`, `clientes:write`) não achava ninguém no "iniciar
  atendimento". A borda passou a aceitar `atendimentos:read`.

**Entregue:**

- `tenant_module/lib/permissoes_de_tela.dart`: o mapa tela → escopos para abrir
  e para alterar, espelho do `rbac::MAPA`, sem import nenhum (o guard o importa
  e continua testável na VM). Lista vazia é só admin; `/tenant/*` não declarado
  é só admin (fail-closed, como no servidor); subtela herda a seção.
- Menu montado pelo mapa; guard do app usando o mesmo mapa — nada visível leva a
  redirect, nada escondido abre pela URL.
- Botões de escrita escondidos sem o escopo de escrita em contatos, equipe,
  fluxos, colunas, campos, conexões, configuração e treinamento (material e
  intenções). O interruptor da IA por conexão fica visível e só o admin muda.
  O treinamento, que mora noutro módulo e não conhece a sessão, recebe a
  pergunta pronta do app.
- Testes: um por papel no menu (manager, staff, viewer, sem sessão), regras do
  mapa, guard por escopo, e `permissoes_de_tela_test.dart`, que **lê o
  `rbac.rs`** e falha se a tela e o servidor divergirem.

**Fica de fora:** o quadro de atendimento (`operacional_module`) continua
oferecendo enviar/mover para um `viewer` — o servidor recusa (N13.3), mas a tela
não esconde. É do quadro, não do menu, e fica anotado para quando o quadro for
revisto.

### B3 — "O que o agente fez": auditoria do próprio tenant

**Confirmado antes de construir:** `QueryAuditLog` exigia superusuário, e o
painel do tenant não tinha tela de auditoria. E um achado que o plano não previa:
**a trilha não sabia qual aplicativo agiu.** O `user_agent`
`SmartCoreAssistant-MCP/<tool>` distinguia agente de pessoa, mas o token interno
com que o agente chama o runtime não carrega o grant — "o que o Claude fez"
era impossível de responder, só "o que algum agente fez".

**Entregue:**

- `mcp_server`: o `user-agent` passa a levar o grant —
  `SmartCoreAssistant-MCP/<tool> (grant <uuid>)`. Sem migration, sem campo novo
  no contrato: o `user_agent` já chegava ao `audit_log` desde a N13.7. Linhas
  antigas continuam sendo de agente, só sem o nome do aplicativo.
- `AdminService.ListMyAuditLog`: tenant da sessão; `tenant:admin` vê o tenant
  inteiro e escolhe a origem (agentes, pessoas, tudo); **qualquer outra sessão
  vê só o que os próprios agentes fizeram** — origem e usuário forçados no
  `data_postgres`, seja qual for o pedido. Filtros por aplicativo e período;
  teto de 200 por página; `grant_id` validado como UUID antes do `LIKE`.
- **Sem a mensagem do evento no contrato.** Alguns eventos guardam nome ou
  e-mail na mensagem (o de convite, por exemplo); a aba mostra operação,
  aplicativo, quem autorizou e quando — nunca o conteúdo. A garantia é
  estrutural: o dado não chega à tela.
- Ler a trilha é auditado (`audit_log_consultado`), e essa própria linha não
  volta na lista.
- Tela: aba **Atividade** dentro de Aplicativos conectados (não item de menu):
  filtro de aplicativo, período e — só para o admin — "Só agentes" como um
  controle. Operações em linguagem de negócio ("Cadastrou um contato", "Enviou
  uma mensagem a um cliente"), com o código humanizado como última saída.
- Testes: recorte forçado para não-admin, admin escolhendo a origem, teto,
  filtros malformados recusados, derivação de origem/tool do `user_agent`,
  formato do `user-agent` no `mcp_server`, e a aba (vazio sem parecer erro,
  linha de agente, linha de painel, filtro).

### B4 — Limiar de confiança com veto, por tenant (D1, passo 2)

**Confirmado antes de construir:** o passo 1 (medir) já estava no ar — o worker
grava a confiança de cada resposta. Faltava decidir com ela: o único veto era um
`0.5` fixo no `ia_engine`, e o C1 usava `0.8` fixo para a ficha.

**Decisão de produto registrada:** o plano manda não ligar o veto sem histórico,
e o histórico só começa a existir agora. Por isso o veto nasce **desligado** —
quem não mexer na configuração continua com o comportamento de antes.

**Entregue:**

- Migration 0034: `confianca_minima_transferencia` e
  `confianca_minima_automatica` em `tenants_tenantconfig`, na cascata Tenant >
  CoreSettings (`CONFIANCA_MINIMA_TRANSFERENCIA` vazio = desligado;
  `CONFIANCA_MINIMA_AUTOMATICA` = 0.8).
- `RuntimeConfig` e o DTO publicado no Redis levam os dois; a cascata não usa o
  `fallback_dec`, que cairia em 0.0 — veto desligado estaria certo, mas piso zero
  aceitaria qualquer palpite.
- `ia_engine`: **veto** — abaixo do piso do tenant, transfere mesmo com o LLM
  confiante; acima, a transferência pedida pelo LLM continua valendo (ele conhece
  o roteamento por fluxo). O número comparado é o `final_score`, o mesmo que o
  worker grava: calibrar e decidir olham a mesma medida.
- Worker: cada resposta ganha **decisão** — `automatica`, `revisao` (entre o veto
  e a confiança automática), `transferida` ou `degradada` (fallback, não veio da
  IA) —, no evento `bot.respondeu` e no log, ao lado da confiança. Número, nunca
  conteúdo.
- C1: o piso para gravar valor extraído na ficha passa a ser a
  `confianca_minima_automatica` do tenant — um número só para "quando confio na
  IA". Sem config legível, vale o 0.8 de antes.
- Tela de configuração do tenant: seção **Confiança da IA**, com os dois campos
  explicados. Valor fora de 0..1 é descartado, não gravado cortado.
- Testes: veto abaixo/acima do piso, veto desligado preserva a regra antiga, veto
  não duplica aviso quando o LLM já transferiu; decisão por faixa no worker;
  limiares no request da tela.

**Fica de fora:** a marca visual de "revisar" no quadro. A decisão fica
registrada na trilha (`bot.respondeu`), que é o que a calibração precisa; mostrar
no cartão é do quadro, junto do resto que o B2 anotou para ele.

### B5 — Notificar o atendente da atribuição (D6)

**Confirmado antes de construir:** a atribuição acontece no rodízio da
transferência por IA (`transferir_atendimento_para_fluxo`), e o worker já
publicava `kanban.movido` com o atendente — o quadro recarregava para todos, mas
ninguém era avisado de que a conversa passou a ser sua. A sessão do Flutter não
sabia nem quem era o usuário: o JWT trazia `sub` e o cliente o descartava.

**Decisão registrada:** o aviso vai no canal realtime **do tenant**, e o cliente
filtra pelo `usuario_id`. O cartão do quadro já mostra a todos quem atende cada
conversa; um canal por atendente mudaria o `RealtimeManager` inteiro para
proteger o que já é público. O evento não leva conteúdo da conversa e não é
auditado — a atribuição em si já está em `atendimento.transferido_por_ia`.

**Entregue:**

- `data_postgres`: o resultado da transferência leva `atendente_usuario_id` (o
  login de quem recebeu; nulo quando o atendente não tem login).
- Worker: depois do `kanban.movido`, publica `atendimento.atribuido` com
  `atendimento_id`, `atendente_id`, `usuario_id` e `fluxo_nome` — só quando houve
  atribuição a alguém com login.
- Flutter: `Session.userId` vem do `sub` do JWT; o `OperacionalModule` recebe
  `usuarioAtual` por parâmetro (o módulo não conhece a sessão), e o
  `KanbanController` expõe `atribuicoes` só com as conversas de quem está
  logado. O quadro mostra um aviso com **Abrir**, que leva direto à conversa.
- Testes: payload do evento (com e sem atribuição/login) no worker; `sub` → id na
  sessão; o controller avisa quem recebeu e ignora a do colega e a sessão sem id.

**Fica de fora:** aviso fora do quadro (notificação do sistema operacional, som,
e-mail). Quem está com o app aberto em outra tela vê o aviso ao voltar para o
quadro; a conversa já estará na coluna dela.

### B6 — Marcar como lida e contador de não lidas (N9 E4)

**Confirmado antes de construir:** o banco já tinha `lido`/`data_lida` em
`oraculo_mensagem`, e o `data_whatsapp` já sabia espelhar a leitura
(`MarkWhatsappMessageRead` → `POST /message/markread`). Faltavam a rota, o
número por conversa e o gatilho na tela.

**Decisões registradas:**

- **"Do contato" = nem `atendente` nem `bot`** — a mesma regra com que o balão
  da conversa escolhe o lado. Não depende do valor exato gravado na entrada.
- **Sem `GetNaoLidas` separado.** O quadro já lista todas as conversas visíveis,
  com o RBAC por fluxo aplicado; um contador global em outra rota teria de
  repetir esse filtro, e divergir dele mostraria número de conversa que a pessoa
  não pode abrir. O sino da topbar fica para quando houver topbar fora do quadro.
- **Gatilho:** a lista da conversa é invertida, então o fim (a mensagem mais
  nova) é o início da rolagem. Marca quando o fim está à vista — ao abrir, ao
  chegar mensagem e ao parar de rolar perto dele. Aberta rolada para cima, não
  marca. Só vai ao servidor quando há mensagem do contato mais nova que a última
  marcada.
- **Sem auditoria** (plano N9): estado trivial e de alto volume; `data_lida` é o
  registro, e guarda o primeiro momento da leitura.

**Entregue:**

- `infrastructure_postgres`: contagem de não lidas por atendimento e marcação
  (com RBAC por fluxo), devolvendo os ids do WhatsApp das mensagens marcadas
  agora e a instância/telefone da conversa.
- `data_postgres`: rota `MarcarAtendimentoLido`; `ListAtendimentos` leva
  `nao_lidas` em cada item (falhar a contagem não esconde o quadro).
- `runtime_api`: `MarcarAtendimentoLido` com as permissões de fluxo resolvidas
  (não passa por `encaminhar_tenant`, que as mandaria vazias) e espelho
  best-effort no WhatsApp; `AtendimentoResumo.nao_lidas`.
- Flutter: número no cartão do quadro (some ao abrir a conversa, sem esperar a
  recarga); cadeia `MarcarAtendimentoLido` completa, também no gateway do desktop
  (direto ao servidor, fora da fila offline).
- Testes: não lidas na listagem; espelho só quando há o que espelhar; payload
  inválido; controller marca uma vez e ignora conversa só de atendente/bot.

**CI:** a primeira rodada (`2453141`) quebrou em testes de tela do quadro: a
conversa pedia o usecase de leitura ao GetIt, e esses testes não o registram.
O usecase já era opcional no controller; a tela passou a pedi-lo só quando
registrado.

**Fica de fora:** os ticks de leitura das mensagens **enviadas** (N9 E7) e a
presença "digitando" (E5) — são os próximos passos da mesma fase, não deste
bloco.

### B7 — Ajustar permissões de um agente sem desconectar (doc 35-agentes F4)

**O plano estava errado num ponto, e o bloco corrige:** ele dizia que o backend
não precisava de nada — bastava um link do painel para `/oauth/authorize` com o
`client_id` e o `redirect_uri` do grant. Não funciona. O código novo iria para o
`redirect_uri` do aplicativo de IA sem o `state` e o PKCE que ele espera, então
ninguém o trocaria por token; e `registrar_consentimento` já teria revogado o
grant antigo. Resultado: o agente **desconectado** — o defeito que o F4 existe
para eliminar.

**O que foi feito no lugar:** o grant é ajustado **no próprio registro**, sem
tocar no refresh token. O `control_plane` já reintersecta os escopos do grant a
cada renovação (é o que faz rebaixar alguém no painel encolher o agente), então a
redução vale na renovação seguinte — até 15 minutos, o mesmo número da
revogação, vindo do servidor.

**Só reduz.** Pedido com permissão que o grant não tem é recusado (`Conflict`), e
a tela nem oferece a caixa: dar mais acesso continua exigindo reconectar e
aprovar na tela de consentimento, onde quem aprova vê o que concede.

**Entregue:**

- `infrastructure_postgres`: regra pura `escopos_reduzidos` (mantém a ordem do
  grant, recusa ampliar) e `reduzir_escopos` com `FOR UPDATE`, filtrando pelo
  próprio usuário como a revogação.
- `data_postgres`: rota `AjustarEscoposMcpGrant`; lista vazia recusada (tirar
  tudo é desconectar); auditada como `oauth.escopos_reduzidos`.
- `runtime_api` e proto: `AjustarEscoposMcpGrant` devolve os escopos que ficaram
  e a janela em minutos.
- Flutter: **Ajustar permissões** no cartão do aplicativo (só com mais de uma
  permissão), diálogo com as que ele tem hoje, aviso honesto do prazo; recusa de
  ampliar vira "desconecte e conecte de novo".
- Testes: regra pura; handler reduz, recusa ampliar e lista vazia; cadeia do
  Flutter com pedido, janela e os dois erros.

**DoD do F4:** reduzir sem tocar no cliente de IA ✅; a tela diz o prazo real ✅;
ampliar passa pelo consentimento, nunca em silêncio ✅.
