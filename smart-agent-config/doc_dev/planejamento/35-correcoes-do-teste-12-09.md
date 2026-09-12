# 35 — Correções do teste de 12/09/2026

Lista fechada do que o teste apontou, com a causa quando já apurada. A ordem é
de dependência e de dano: o que impede de usar o produto vem antes do que
incomoda.

| # | Item | Natureza | Estado |
|---|------|----------|--------|
| A | Tela de atendimento tomada pela faixa de aviso, sem cards | defeito de layout | **causa achada e corrigida** |
| B | Conexão desconectada no celular continua "conectada"; reconectar falha | defeito | **causa achada e corrigida** |
| C | IA não responde no teste de treinamento | **configuração** | causa achada |
| D1 | Convite: só 3 permissões de 13 | defeito | **corrigido** |
| D2 | Convite: o "link" era um caminho relativo | defeito | **corrigido** |
| D3 | Convite: não envia e-mail | **nunca existiu na v2** | **construído** |
| E | "Sessão expirada" o tempo todo | defeito | **causa achada e corrigida** |
| F | Ícone do MCP mostra "S" em vez da logo | defeito | **corrigido** |
| G | Chat do WhatsApp dentro do painel | em parte **consequência de A** | **entregue** |

## A — a faixa de aviso engoliu a página *(corrigido)*

`Size.fromHeight(48)` é `Size(double.infinity, 48)`: pede **largura** infinita.
O tema aplicava isso a todo `FilledButton` do app. Numa coluna não se nota — o
botão só fica largo. Numa `Row`, o botão toma a linha inteira e o `Expanded` ao
lado fica com zero: o texto quebra **uma letra por linha**, cresce para ~1.400px
de altura e empurra o quadro para fora da tela.

Medido no print: fundo `#F5ECDC`, que é exatamente `warningSoft` (10% de
#F59E0B) sobre `stone100` — o banner ocupava os 1911×988 inteiros.

Corrigido para `Size(64, 48)`: 48 de altura era a intenção (alvo de toque), 64
de largura é o mínimo do Material. Quem quer botão da largura toda continua
pedindo por `PrimaryButton(expand: true)`, que usa um `SizedBox` explícito.

O mesmo defeito afetava **toda** `Row` com botão no app — não só esta faixa.

## C — a IA não responde *(configuração, não código)*

Log do `ia_engine` em dev, 12/09 17:12 e 17:13:

    RPC Embed falhou: AuthenticationError: Error code: 401
    Incorrect API key provided: sk-proj-…mIYA
    invalid_api_key

A chave da OpenAI configurada em dev não é aceita. Nenhuma mudança de código
resolve; a chave precisa ser trocada no ambiente.

## G — chat do WhatsApp no painel *(entregue)*

Metade do problema era o item A: com a faixa ocupando a página, não havia
cartão para clicar. A outra metade era de apresentação — o chat existia
inteiro (`ChatPage`, `ChatController`, bolhas, badge de conexão, ficha), mas só
como página cheia empurrada por cima do quadro. Clicar num cartão fazia perder
de vista a fila que se estava trabalhando; na v1 a conversa abria à direita.

O miolo virou `PainelDeConversa`, sem moldura de tela, e passa a viver em dois
lugares: ao lado do quadro em janela larga (≥1100px) e como tela cheia no
estreito, onde espremer os dois deixaria ambos ilegíveis.

Um detalhe que merece nota: a `ValueKey` no id do atendimento. Sem ela o
Flutter reaproveita o `State` ao trocar de conversa, o `initState` — que é onde
o stream abre — não roda de novo, e o painel mudaria de título continuando a
mostrar a conversa anterior.

O que **falta** de N9: criar atendimento a partir de um cliente cadastrado e os
campos personalizados do cartão (documentos 33 e 34).

## B — "Reconectar" chamava a rota que não podia funcionar *(corrigido)*

Log do `data_whatsapp`, instância 181, a cada ciclo:

    instância exige novo pareamento (QR); reconexão não resolve

O servidor já sabia. Duas coisas impediam isso de chegar a quem usa:

1. O botão chamava `/instance/reconnect`, que responde *"no active session
   found"* quando o socket já caiu. A reconciliação periódica, no arquivo ao
   lado, usa `connect` — e o comentário dela **explica exatamente por quê**. O
   botão do usuário ficou com a chamada que só serve para uma sessão viva,
   que é justamente o caso em que ninguém aperta o botão.

2. O `runtime_api` devolvia `sucesso: true` fixo, sem olhar o resultado.

Agora o botão faz o que a reconciliação faz, e quando o aparelho foi
desvinculado responde com o motivo: *"O WhatsApp desvinculou este aparelho.
Reconectar não resolve: é preciso ler o QR code de novo."*

## E — nada renovava a sessão *(corrigido)*

`AuthService.refresh()` existia, estava implementado e tinha testes. Uma busca
por quem o chamava em todo o cliente devolveu **uma** ocorrência: a própria
declaração. O único gatilho era o boot (`checkCurrentUser`).

Depois disso o access token vencia e nada o renovava — toda ação seguinte
voltava `unauthenticated`, com o refresh token válido guardado ao lado. Era a
origem real dos "sessão expirada" repetidos, incluindo no fluxo do MCP. E
enquanto as 23 famílias de erro traduziam isso como "você não tem permissão",
o sintoma apontava para o lugar errado.

A renovação passa a acontecer no provider assíncrono que o interceptor já
executava antes de **cada** chamada — o único ponto do caminho que vê toda
chamada e pode esperar. Como `refresh()` é single-flight, uma tela que dispara
seis requisições renova uma vez só (há teste para isso: com rotação
obrigatória, seis rotações fariam o servidor tratar reuso como roubo e derrubar
o grant).

## F — o "S" no lugar da marca *(corrigido)*

Sem `icons` no `serverInfo`, o cliente desenha um avatar com a inicial do nome.
O servidor passa a declarar o ícone e a servi-lo em `/icon.png` — rota pública,
porque o cliente busca o ícone antes de haver token. O teste confere as duas
pontas: declarar apontando para um 404 dá no mesmo "S".

## D3 — o convite nunca mandou e-mail

Não é regressão de configuração: **não existe envio de e-mail no servidor da
v2**. Uma busca por SMTP, `send_mail` ou qualquer provedor em todo o `server/`
não devolve nada.

A v1 usava SMTP direto (Django), via Brevo:

    EMAIL_HOST = smtp-relay.brevo.com
    EMAIL_PORT = 587, TLS
    EMAIL_HOST_USER / EMAIL_HOST_PASSWORD

Construído no crate `infrastructure_email`, com os **mesmos nomes de variável
da v1** — as credenciais Brevo que já existem continuam servindo, sem ninguém
ter de descobrir um vocabulário novo para o mesmo relay.

Três decisões que valem registro:

**Falha aberta.** O convite já está gravado quando o e-mail sai. SMTP fora do
ar vira log; o link continua válido e visível na tela de quem convidou. Recusar
a criação por causa do e-mail trocaria um problema pequeno (avisar por outro
caminho) por um grande (não conseguir convidar ninguém).

**Sem SMTP configurado não é erro.** Desenvolvimento local e CI não têm relay,
e não devem quebrar nem encher o log de falha: o enviador entra em modo
desligado e registra o que teria mandado.

**O nome da empresa viaja junto do convite.** Quem manda o e-mail é a borda, e
ela não descobriria o nome sem outra volta ao banco — enquanto no
`data_postgres` ele está a uma consulta da transação já aberta. Sem o nome, o
convidado receberia "alguém criou um acesso para você", que é a cara de golpe.

Falta configurar no ambiente: `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`,
`EMAIL_FROM` (remetente de domínio verificado no Brevo) e `APP_PUBLIC_URL` — o
servidor não tem como adivinhar o endereço público, com um proxy na frente e
domínios diferentes por ambiente.

---

## C3 — atendimento a partir de um cliente cadastrado *(entregue)*

Fecha o pedido de usar a aplicação como CRM estruturado: até aqui um
atendimento só nascia de uma mensagem que chegou. Para procurar o cliente era
preciso sair do produto, escrever pelo WhatsApp e esperar a resposta cair no
quadro — e o histórico da conversa começava pela metade.

Ponta a ponta: `IniciarAtendimentoManual` no proto, handler no `data_postgres`,
método concreto no `runtime_api` (sem ele o Flutter não alcança o RPC, por mais
que a rota exista no roteador de envelope), RBAC (`atendimentos:write` e o mesmo
RBAC fino por fluxo do arrasto no quadro), e no cliente a cadeia RSOE completa
até o diálogo.

Três regras que o código explica no lugar:

**Fluxo e etapa são obrigatórios.** A ingestão cria sem etapa e encaixa depois;
um atendimento sem etapa não aparece em coluna nenhuma do quadro. Para uma
conversa que alguém acabou de abrir, nascer invisível é o pior desfecho.

**`bot_pode_atender = false`.** Alguém decidiu falar com esse cliente; o robô
não entra no meio de uma conversa que uma pessoa começou. O caminho de volta já
existe e é um clique (D3).

**A invariante de um ativo por contato vale aqui também**, e é verificada
dentro da mesma transação. Se já há conversa aberta, o servidor devolve a que
existe com `ja_existia = true` e a tela **abre** aquela, dizendo isso. Duas
pessoas clicando ao mesmo tempo não criam dois cartões, e o operador não sai
procurando um cartão novo que não existe.

A busca de clientes entra por injeção (`buscarContatos`), como o menu e os
avisos: cadastro de contato é do `tenant_module`, e o `operacional_module` não
o conhece — a dependência corre nessa direção. Sem a busca injetada, o botão
não aparece.

### O risco que não é técnico

A evolution-go é whatsmeow: aceita qualquer JID, sem a janela de 24 h da Cloud
API. Iniciar conversa é tecnicamente trivial — e é o caminho mais curto para o
número do tenant ser denunciado. **Ainda falta**: teto diário por tenant e
recusa clara quando a instância não está conectada. A auditoria
(`atendimento.iniciado_manualmente`, com autor e contato, sem o texto) já está.

---

## Segunda rodada de teste (12/09, tarde)

### O treinamento que a IA não via

Três bloqueios em série, e cada um escondia o seguinte:

1. **A chave da OpenAI** (`…mIYA`) fazia o `Embed` falhar com 401. Isso
   travava as **intenções** — que a partir da chave nova passaram a vetorizar.
2. **O material estava em Rascunho.** A fila de vetorização só pega
   `treinamento_finalizado = true`, e a busca RAG exige isso **e** embedding.
   O texto ficou cadastrado desde as 13:48 sem nunca entrar na fila.
3. **A tela não contava isso.** Rascunho era um selo cinza de 10px com a
   explicação num tooltip. Cinza lê como "tudo certo"; o estado é o oposto.

Corrigido: selo em cor de aviso, a frase "A IA ainda não usa este material" na
linha, e a ação rotulada ("Enviar para a IA") no lugar de um ícone de revisar.

**E o cartão não saía de "Processando"**: quem vetoriza é o worker, minutos
depois. A lista passa a se reler a cada 15s enquanto houver pendência, e para
quando não houver.

### O link do convite ia para fora do app

O e-mail chegou e a página deu HTTP 400. O link era montado sobre o
`apiEndpoint` — mas o gRPC atende no domínio raiz e o app do tenant é servido
sob `/v2/tenant/`. Corrigido nos dois lugares onde o link nasce (servidor e
cliente), com `appPublicUrl` por flavor e verificação dentro do binário no
script de build.

### Conexões

O QR só era oferecido ao **criar** a conexão; agora o cartão traz "Ler QR code"
sempre que ela não está no ar. "Conectando" virou "Aguardando QR" — o provedor
não está tentando nada, ele espera uma ação humana.

**Uma regressão registrada**: fazer o servidor recusar a reconexão de aparelho
desvinculado tirou a tela do caminho que resolve (o sucesso já abria o QR, de
propósito). O desfecho voltou para o corpo da resposta. A tentativa de
distinguir por `failedPrecondition` foi barrada por um teste existente — no
reconectar essa condição também cobre "instância já está conectada".

**Editar conexão**: decidido não construir. O nome é o identificador da
instância no provedor; renomear desfaria o vínculo. A tela passa a explicar.

---

## Revisão: abrir conversa não exige WhatsApp no ar

Eu havia barrado o `IniciarAtendimentoManual` quando nenhuma instância estava
conectada, com o argumento de que a mensagem não sairia. O argumento vale para
**enviar**, não para **abrir**: o produto separa os dois atos de propósito, e o
operador prepara o cartão hoje para falar amanhã, ou registra um contato que
chegou por telefone. Barrar o primeiro por causa do segundo tirava um uso
legítimo por um risco que só existe no outro.

O aviso continua existindo, e num lugar melhor: a faixa no topo do quadro, que
diz que nada está chegando enquanto a conexão está fora. Duplicá-lo no diálogo
seria repetir no detalhe o que já está dito no geral.

O teto diário por tenant fica: ele protege contra disparo em massa, que é outro
problema e continua real.

---

## C4 — o cadastro de contato deixa de depender de alguém escrever *(entregue)*

O C3 abriu a conversa a partir de um cliente cadastrado. Faltava a metade que
o torna utilizável: **até aqui um contato só existia porque mandou mensagem**.
Quem conhecia o cliente pelo telefone não tinha como registrá-lo, e a busca do
diálogo de "iniciar atendimento" não achava ninguém para escolher.

Ponta a ponta, na ordem de sempre: `CreateMyContato` / `UpdateMyContato` /
`DefinirMyContatoAtivo` no proto, repositório (`criar_manual`, `atualizar`,
`desativar`, `contar_atendimentos`), port, adapter, handler com auditoria,
método concreto no `grpc_web.rs`, stubs Dart, cadeia RSOE e diálogo.

Três decisões que o código explica no lugar:

**O servidor normaliza o telefone, e o cliente não.** O webhook deriva o número
do JID (`5511999998888@s.whatsapp.net`): só dígitos, com DDI, sem `+`. Um
contato cadastrado à mão como "(11) 99999-8888" ficaria numa linha diferente do
mesmo telefone que chega pelo WhatsApp — duas pessoas para uma, e a conversa
aberta à mão nunca receberia as respostas dela. Sem DDI, assume 55, como a v1.
A resposta devolve o número **já normalizado**, e é ele que a tela mostra: quem
digitou precisa ver em que número o cadastro ficou.

**Telefone repetido é recusa, não upsert.** O `salvar` que a ingestão usa é
upsert de propósito — reencontrar o contato é o caso normal dela. No cadastro à
mão, telefone repetido é engano de quem digita, e devolver em silêncio a ficha
de outra pessoa seria pior que a recusa.

**O número trava quando há histórico.** A troca só passa enquanto o contato não
teve nenhum atendimento, e a contagem roda na mesma transação do UPDATE: fora
dela, duas edições simultâneas concluiriam ambas que "ainda não havia
conversa". Com histórico, a mensagem manda cadastrar o número novo à parte —
trocá-lo passaria as mensagens de uma pessoa para outra.

Desativar é *tirar da lista*, não apagar: as conversas continuam
referenciando o contato, e se ele escrever de novo o cadastro volta a aparecer.

## O teto diário do C3 *(entregue)*

Ficou registrado como pendente e agora existe: 50 conversas abertas por dia,
por tenant. A contagem é de **conversas abertas hoje sem nenhuma mensagem
trocada** — que é o retrato do disparo em massa e só dele: conversa vinda de
mensagem recebida já nasce com `data_ultima_mensagem`, e assumir uma também
não conta.

Fora da transação de propósito: uma corrida deixaria passar a 51ª de 50, e
ninguém está protegido de disparo em massa por uma unidade. Falha ao contar
não barra ninguém — o teto protege de abuso, e transformá-lo em ponto único de
falha impediria o uso legítimo por um problema que não é do usuário.

## Teto de campos por tenant *(entregue)*

O último item que o doc 33 listava como risco sem dono: 30 campos ativos.
Cada campo com extração automática entra no prompt de **toda** mensagem — a
ficha cresce e o custo por conversa sobe junto, sem nada na tela dizendo isso.
Conta os ativos, porque desativar um o tira do prompt, e essa é a saída de
quem esbarra no limite.

## O que fica de fora, e por quê

**Vínculo contato ↔ cliente** (a segunda metade do C4 no doc 33). A tabela
`oraculo_cliente` existe desde a migration 0004 — com CNPJ, CPF e razão
social —, e a associativa `oraculo_cliente_contatos` também. Não existe nem
RPC nem tela para nenhuma das duas.

Não é uma correção do teste: é uma entidade nova no produto, com tela
própria, e o cadastro de contato entregue aqui já resolve o que travava o C3
(não havia quem escolher no diálogo). Fica registrado como o próximo bloco,
não como pendência desta rodada.
