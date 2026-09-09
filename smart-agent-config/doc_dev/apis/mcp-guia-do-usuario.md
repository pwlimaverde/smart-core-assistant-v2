# Conectar um assistente de IA ao seu Smart Core Assistant

Este guia é para quem usa o sistema, não para quem o desenvolve. Ele explica como
ligar um assistente de IA (Claude, ChatGPT, Cursor) à sua conta, o que ele passa a
poder fazer, e como cortar esse acesso quando quiser.

---

## O que isso faz

Depois de conectar, você pode pedir ao assistente coisas como:

> "Configure um funil de vendas com quatro etapas e um departamento comercial."
>
> "Quantos atendimentos estão parados hoje?"
>
> "Leia a conversa do atendimento 412 e me diga o que o cliente quer."

O assistente faz isso **na sua conta, com as suas permissões**. Ele não consegue
fazer nada que você mesmo não conseguiria fazer entrando no painel — essa é a
regra central do desenho, e ela não tem exceção.

## O que você precisa

Só a conta que já usa. Não há token, senha de aplicativo nem chave para gerar.

O endereço do servidor é:

```
https://mcp.smartcoreassistant.com.br/mcp
```

Ele não é segredo — é um endereço público. Quem autoriza o acesso é você, no
navegador, com a sua senha.

---

## Como conectar

### Claude (web, aplicativo de computador, celular)

1. Abra **Configurações → Conectores**.
2. Escolha **Adicionar conector personalizado**.
3. Cole o endereço acima e confirme.
4. O navegador abre na tela do Smart Core Assistant. Entre com o seu e-mail e
   senha.
5. A tela mostra o que o Claude está pedindo. **Leia a lista.** Desmarque o que
   não quiser conceder e clique em **Autorizar**.

Pronto. Volte à conversa e peça algo.

### ChatGPT

O caminho é o mesmo (**Configurações → Conectores → adicionar servidor MCP**),
mas o suporte a MCP no ChatGPT está em modo de desenvolvedor e muda com
frequência. Se a opção não aparecer no seu plano, é limitação dele, não da nossa
conexão — o servidor segue o padrão que a OpenAI publicou.

### Claude Code / Cursor

```bash
claude mcp add --transport http smartcore https://mcp.smartcoreassistant.com.br/mcp
```

Na primeira chamada ele abre o navegador para o login e o consentimento.

---

## A tela de autorização

Ela mostra três coisas, e todas as três importam:

**O nome do aplicativo.** Vem do próprio aplicativo — ou seja, ele escolhe como
se apresentar. Um aplicativo mal-intencionado pode se chamar "Smart Core
Oficial".

**O endereço para onde o acesso volta.** É este que você deve reconhecer. Se
você clicou em conectar dentro do Claude, esse endereço tem de ser do Claude. Se
apareceu outro nome, **cancele**.

**A lista de permissões.** Só aparecem as permissões que **você** tem. Se você não
é administrador, não existe caixa "administrar tudo" para marcar — não porque a
tela a esconde, mas porque você não pode concedê-la.

Você pode desmarcar itens. Conceder menos é sempre seguro: se o assistente
precisar de algo que não recebeu, ele vai dizer, e você reconecta concedendo.

---

## O que cada permissão libera

| Permissão | O assistente pode |
|---|---|
| Ver atendimentos e mensagens | Ler conversas e a fila de atendimento |
| Enviar mensagens e mover atendimentos | **Mandar mensagem para o WhatsApp dos seus clientes** |
| Ver contatos | Ver nome, telefone e histórico de contato |
| Criar e editar contatos | Cadastrar e alterar contatos |
| Ver departamentos e equipe | Ver a estrutura do negócio |
| Gerenciar departamentos, equipe e conexões | Criar/desativar departamentos, atendentes e conexões de WhatsApp |
| Gerenciar todos os fluxos | Criar, alterar e desativar fluxos e etapas do Kanban |
| Ver a base de conhecimento | Ler os treinamentos do assistente automático |
| Editar a base de conhecimento | Criar, alterar e **remover** treinamentos |
| Ver / registrar dados financeiros | Ver assinatura e lançamentos; registrar lançamentos |
| Ver configurações | Ver a persona do bot e as configurações do negócio |
| Alterar configurações e integrações | Trocar a persona, os modelos de IA e as integrações |
| Administrar tudo no negócio | Tudo acima |

A que merece mais atenção é **"Enviar mensagens"**: é o único acesso cujo efeito
sai do sistema e chega a uma pessoa. Não tem desfazer.

**Chaves de API nunca são entregues.** O assistente consegue ver *quais*
provedores estão configurados, nunca o valor das chaves.

---

## As proteções que existem mesmo depois de você autorizar

**O assistente precisa confirmar antes de agir de forma irreversível.** Para
enviar uma mensagem ou remover algo, ele tem de indicar exatamente qual é o alvo
— o nome do fluxo, a tag do treinamento. Um assistente que "achou" que era o
fluxo 3 sem ter olhado não passa.

**Ele pode simular antes de fazer.** Pergunte "o que aconteceria se…" e ele
consegue descrever o efeito sem executar nada. Vale o hábito, especialmente para
remoções.

**Existe limite de volume.** Envio de mensagem para no máximo 10 por minuto e 100
por dia; ações destrutivas, 5 por minuto e 30 por dia. Se um assistente entrar em
laço, ele bate no teto em vez de alcançar a sua base de clientes.

**Tudo fica registrado.** Cada ação de assistente entra na trilha de auditoria
identificada como tal, com o nome da operação e quem autorizou.

---

## Desconectar

**Configurações → Aplicativos conectados**. A lista mostra o que está conectado,
com quais permissões, quando foi conectado e quando foi usado por último. Os que
podem alterar dados aparecem primeiro e marcados.

Clique em **Desconectar**.

**Uma coisa importante e honesta:** a renovação do acesso é cortada na hora, mas
um acesso que esteja em andamento naquele instante pode continuar por **até 15
minutos**, até o crachá dele expirar. Se você está desconectando por suspeita de
algo errado, considere também trocar a sua senha — isso encerra tudo
imediatamente.

---

## Perguntas que costumam aparecer

**Preciso ser administrador?** Não. Qualquer pessoa com conta pode conectar um
assistente, e ele recebe as permissões *dessa* pessoa. Um atendente conecta e o
assistente atende; ele não passa a configurar o negócio.

**Se eu for promovido, o assistente ganha as permissões novas?** Não
automaticamente. O que você concedeu continua valendo; para ampliar, é preciso
conectar de novo e autorizar o que faltava.

**E se eu for rebaixado?** Aí sim, o acesso do assistente encolhe junto, na
renovação seguinte (em até 15 minutos). A permissão dele nunca é maior que a sua
no momento presente.

**Meu colega vê o assistente que eu conectei?** Não. A lista de aplicativos
conectados é pessoal — nem o administrador vê a sua.

**Algum aplicativo pediu uma "chave de API do Smart Core" para conectar. É
normal?** Não. Não existe chave para colar. Se pedirem, desconfie.

**Perdi o acesso ao computador onde o assistente estava instalado.** Desconecte o
aplicativo na tela de aplicativos conectados. Sem o consentimento, ele não
renova.
