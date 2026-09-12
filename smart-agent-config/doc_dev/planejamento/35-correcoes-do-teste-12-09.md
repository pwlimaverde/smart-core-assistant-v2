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
| D3 | Convite: não envia e-mail | **nunca existiu na v2** | a construir |
| E | "Sessão expirada" o tempo todo | defeito | **causa achada e corrigida** |
| F | Ícone do MCP mostra "S" em vez da logo | defeito | **corrigido** |
| G | Chat do WhatsApp dentro do painel | **funcionalidade nova** (N9) | planejada, não feita |

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

## G — chat do WhatsApp no painel

Não é regressão: é a paridade v1→v2 já planejada em N9 (documento 33/34 desta
pasta). O painel hoje lista atendimentos; o cartão de conversa à direita, com a
troca de mensagens sem sair do app, é trabalho a fazer.

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

Construir isso na v2 é trabalho de verdade — cliente SMTP, template, ponto de
envio no `CreateInvite`, e a regra de que **falha no e-mail não invalida o
convite** (o link continua valendo). Depende também das credenciais Brevo no
ambiente.
