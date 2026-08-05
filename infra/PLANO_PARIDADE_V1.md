# Plano — paridade funcional com a v1 e Kanban próprio

Levantado em 03/08/2026 varrendo `old/smart-core-assistant-painel/` (urls, views,
models) e comparando com as telas e tabelas do v2. Tudo aqui foi **verificado no
código**, não inferido.

## Correção já feita nesta rodada

**O laço da configuração.** Ao concluir o roteiro, a tela gravava
`setup_completed` no servidor e navegava para `/atendimentos`, mas o
`PortaoConfiguracao` — que é quem o guard consulta — continuava dizendo
"pendente". O guard devolvia a tela para a configuração, e não havia como sair.
Defeito meu, introduzido junto com a retomada. Corrigido e coberto por teste.

O segundo sintoma relatado — "fila de atendimento vazia, sem menus" — **não é
bug**: é a lacuna que este plano endereça. O workspace do v2 tem duas telas
(chat e kanban); o tenant-admin da v1 tem quinze.

---

## O que a v1 tem e o v2 não

Levantado das `urls.py` de cada app. Marcado com ⚠️ o que impede operar.

### Tenant-admin (`app/tenants/urls.py` — 23 rotas)

| v1 | v2 | falta |
|---|---|---|
| `dashboard` | — | ⚠️ painel do tenant: volume, filas, instâncias |
| `config_ai` | parcial (`tenant_own_config`) | conferir paridade de campos |
| `config_evolution` | — | ⚠️ gestão das conexões de WhatsApp |
| `config_trello` | — | substituído pelo Kanban próprio (ver adiante) |
| `config_database` | — | **não migra**: base unificada (ver "Decisão de arquitetura") |
| `config_debug` | — | baixa prioridade |
| `user_list`, `user_invite`, `user_permissions` | ✅ `tenant_users`, `invites` | — |
| `backoffice_dashboard`, `backoffice_register_payment` | ✅ `admin_module/billing` | — |
| `signup`, `activate_account` | ✅ `onboarding_module` | — |

### Evolution / WhatsApp (`app/evolution_sync/urls.py` — 19 rotas)

⚠️ **Nada disso existe no v2 fora do onboarding.** Depois de conectado, o tenant
não tem como ver, reconectar ou trocar a instância.

`instance_list`, `instance_detail`, `instance_create`, `instance_update`,
`instance_delete`, `instance_qrcode`, `instance_status`, `instance_logout`,
`instance_refresh_all`, `instance_toggle_bot`, `instance_webhook`,
`department_list`, `department_create`, `attendant_list`.

O servidor já tem os RPCs de instância (`data_whatsapp`); falta expor
departamento/atendente e construir as telas.

### Treinamento (`app/treinamento/urls.py` — 6 telas)

| v1 | v2 |
|---|---|
| `treinar_ia`, `pre_processamento`, `verificar_treinamentos` | ✅ unificados em `treinamento_page` |
| `cadastrar_query_compose`, `verificar_query_compose` | ⚠️ falta |
| `testar_query` + `feedback_resposta` | ⚠️ falta |

### Operação (`app/operacional/models.py`, `app/clientes/models.py`)

Tabelas existem no v2 (`operacional/`, `clientes/` em `infrastructure_postgres`),
telas não:

- ⚠️ **Departamentos** — CRUD (hoje só o primeiro, no onboarding);
- ⚠️ **Atendentes** — vincular usuário a departamento;
- ⚠️ **Fluxos de atendimento + etapas** — `FluxoAtendimento`/`EtapaFluxo`. Sem
  CRUD, o limite `max_fluxos` do plano não morde em nada;
- ⚠️ **Clientes e contatos** — `Cliente`/`Contato`;
- ⚠️ **Campos personalizados, etiquetas, notas** — `CampoPersonalizado`,
  `atu_etiqueta`, `atu_nota`. A v1 tem painéis para os três no detalhe do
  atendimento.

---

## Decisão de arquitetura: base unificada

Na v1 **cada tenant tinha seu banco** (`config_database`, `run_migrations`,
`test_connection` são disso). O v2 é **base única com RLS por tenant** — já é o
desenho vigente, provado pelos testes de isolamento.

Consequência para este plano: as rotas de gestão de banco por tenant **não são
portadas**. Some `config_database`, `run_migrations`, `test_connection`.

## Decisão de produto: Kanban próprio, não sincronização

A v1 sincronizava com o Trello (`app/trello_sync/`: `TrelloBoard`, `TrelloList`,
`TrelloCard`, `TrelloMember`, `TrelloWebhookEvent` + webhooks). O v2 terá
**quadro próprio integrado ao WhatsApp** — o cartão nasce do atendimento, e não
de um espelho de um serviço externo.

Isso **elimina** `config_trello`, `register_trello_webhook`,
`delete_trello_webhook` e todo o `trello_sync`, e **acrescenta** o domínio do
quadro. O v2 já tem `kanban_page`; falta o modelo por trás.

---

## Etapas de execução

Ordem por dependência e por dano ao usuário. Cada etapa é entregável sozinha:
contrato → servidor → cliente → testes, e fecha com as duas suítes verdes.

### Etapa 1 — Operar o WhatsApp depois de conectado — FEITO (parcial)

Entregue: **lista de conexões com estado, reconectar e remover** — o essencial
para uma conexão que cai não deixar o tenant sem saída. Rota
`/tenant/conexoes`, no menu.

3 RPCs novos na fachada (`ListMyWhatsappInstances`,
`ReconnectMyWhatsappInstance`, `DeleteMyWhatsappInstance`); os handlers já
existiam no `data_whatsapp`, faltava só expor. 7 testes.

`unknown` é tratado como situação própria ("sem resposta"), não como
desconectada: não saber pede espera, estar fora pede ação — confundir os dois
mandaria o tenant reconectar uma conexão que talvez esteja boa.

**Falta desta etapa**, para uma segunda passada: ver o QR de uma conexão já
existente (hoje só no onboarding), ligar/desligar o bot por conexão, editar o
webhook, e renomear.

### Etapa 2 — Departamentos e atendentes — FEITO (parcial)

Rota `/tenant/equipe`, duas abas. Departamentos: listar, criar, editar e
desativar. Atendentes: listar, com o departamento de cada um.

As duas listas na mesma tela de propósito — departamento sem atendente e
atendente sem departamento são os dois problemas que travam a fila, e separá-los
esconderia a relação.

**Desativar, não apagar**: atendimentos e atendentes apontam para o
departamento, e remover a linha levaria histórico junto. O `slug` também não
muda ao renomear: é referência estável.

`ativo` e `disponivel` são estados distintos do atendente e ambos aparecem —
quem está de férias fica ativo e indisponível, e confundir os dois esconde por
que uma fila parou.

**Fechado depois da Etapa 5**: criar, editar e desativar atendente, com fluxo e
departamento. O `oraculo_atendente` exige `fluxo_id` NOT NULL — o que travava
isto era não haver fluxo para apontar.

O e-mail não aparece na edição: é a chave única da pessoa dentro do tenant, e
oferecer o campo seria oferecer um caminho que só termina em erro de unicidade.
Inativo nunca sai como disponível (seguiria elegível no rodízio sem ninguém
trabalhando), e o teto de conversas simultâneas fica em 1..100 — zero deixaria
a pessoa cadastrada e nunca elegível, inativa por acidente sem parecer inativa.

### Etapa 3 — Painel do tenant — FEITO

Rota `/tenant/painel`. Números do que exige ação agora (fila, em atendimento,
mensagens em 24h) e da estrutura (conexões ativas/total, departamentos,
material treinado).

Uma consulta só, com `FILTER`: cinco contagens do mesmo instante. Cinco
SELECTs mostrariam uma soma que nunca existiu.

Os avisos **levam à tela que resolve** — dizer o problema sem oferecer o
caminho deixaria a pessoa procurando no menu. E distinguem os dois casos que
parecem iguais nos números: `0 de 0` conexões é conta nova (convite a
conectar), `1 de 2` é queda (alerta vermelho).

Os status vieram do banco, não de palpite: o `oraculo_atendimento` usa o
vocabulário da v1 (`fila`, `em_atendimento`, `pendencia`, `resolvido`,
`cancelado`, `arquivado`) e a coluna de data da mensagem é `timestamp`. Escrevi
`data_envio` de memória e o `sqlx` recusou na compilação — é para isso que a
validação contra o banco real serve.

### Etapa 4 — Clientes e contatos — FEITO (parcial)

Rota `/tenant/contatos`. Lista com busca do servidor (ILIKE em nome, telefone e
nome de perfil do WhatsApp), ordenada pela última interação.

A busca é do servidor, não da lista carregada: há teto de linhas (limite travado
em 1..200 no adapter, para que um cliente pedindo 10 mil não varra a tabela), e
filtrar no cliente esconderia quem ficou além dele.

O nome exibido cai em cascata — cadastro → perfil do WhatsApp → telefone — e
nunca fica vazio. Quem só tem número é marcado como "sem cadastro": é
exatamente esse contato que o operador precisa completar, e sem a marca ele se
perde na lista.

De passagem, o menu do tenant virou rolável: passou de oito itens e a `Column`
rígida estourava em janela baixa, escondendo o fim da lista sem sinalizar que
havia mais.

**Falta desta etapa**: editar contato (nome, e-mail, tags) e o histórico de
atendimentos de cada um — o histórico depende do detalhe do atendimento
(etapa 8).

### Etapa 5 — Fluxos de atendimento — FEITO

Rotas `/tenant/fluxos` e `/tenant/fluxos/:id/etapas`. CRUD de fluxo e de etapa,
com reordenação. **Fecha o enforce de `max_fluxos`**, que até aqui era medido e
não aplicado por não existir RPC de criação para chamá-lo.

**O fluxo nasce com as quatro etapas padrão** (fila, trabalho, espera,
finalização), na mesma transação da criação. Um fluxo sem etapa de entrada não
recebe conversa nenhuma — o roteamento procura a coluna `fila` e não acha —, e o
tenant só descobriria isso quando a primeira conversa sumisse.

Três regras que o servidor aplica e explica, em vez de deixar o banco recusar
com mensagem de constraint:

- etapa com atendimento parado nela não sai (os cartões ficariam órfãos);
- a **última** etapa do tipo `fila` não sai (conversa nova não teria onde cair);
- fluxo com atendimento em aberto não é desativado.

Cada recusa volta como `{sucesso, motivo}` e vira `Validation` com o texto
inteiro: o motivo é para ser lido por quem opera, não virar "algo deu errado".
Na lista, o botão de desativar já vem desabilitado quando há conversa em aberto
— o motivo é conhecido no cliente, e deixar clicar para o servidor recusar seria
pedir um erro que se sabe de antemão.

**Reordenar passa por uma posição negativa temporária**: a `UNIQUE (fluxo_id,
ordem)` recusa o instante em que as duas etapas ocupariam a mesma posição. E a
vizinha é a etapa ativa mais próxima, não `ordem ± 1`: desativar deixa buracos
na numeração, e mover para um buraco não moveria nada aos olhos de quem vê.

`tipo_etapa` é vocabulário fechado validado no handler. A coluna é `VARCHAR(20)`
e aceitaria qualquer coisa — um tipo inventado passaria e sumiria da lógica de
roteamento sem erro nenhum. No cliente, o inverso: tipo desconhecido cai em
`trabalho` em vez de estourar a tela.

**Falta desta etapa**: criar e editar atendente vinculando a fluxo — agora
possível, já que `oraculo_atendente.fluxo_id` tem para onde apontar.

### Etapa 6 — Kanban próprio integrado ao WhatsApp — FEITO (parcial)

**Decisão tomada:** o cartão se move pela mão do atendente **e** pelo estado do
atendimento — e o gatilho do bot fica pronto para quando existir (ver abaixo).

Não precisou de modelo novo: `oraculo_atendimento.etapa_atual_id` já era o
cartão, e `oraculo_movimento_fluxo` já era o histórico. O que faltava era a
coerência entre as duas leituras.

**O defeito que motivava tudo:** as colunas vinham dos atendimentos existentes,
não do fluxo. Coluna sem conversa sumia (não havia para onde arrastar), e uma
conta nova abria o quadro em branco — foi o "fila de atendimento vazia" do
teste. Agora as colunas vêm de `ListMyEtapasFluxo`, com nome e ordem do
cadastro, e um seletor troca de quadro quando há mais de um.

**A tela também não tinha menu.** O quadro é a primeira coisa depois do login, e
sem menu a pessoa ficava presa nele. O `TenantDrawer` mora no `tenant_module`, e
o `operacional_module` não pode depender dele — então entra por parâmetro
(`OperacionalModule(drawerBuilder: TenantDrawer.new)`), decidido no `bootstrap`.

**Sincronia nos dois sentidos**, com uma única tabela de correspondência
(`status_do_tipo_etapa` / `tipo_etapa_do_status`, em `atendimentos.rs`):

- arrastar → o status segue o tipo da coluna destino;
- mudar o status (`SetAtendimentoStatus`) → o cartão vai para a coluna daquele
  tipo, e o movimento é registrado como **automático**, para o histórico
  distinguir o que uma pessoa arrastou do que o sistema mexeu.

Dois cuidados que a leitura ingênua erraria: um `cancelado` **não** vira
`resolvido` só porque o cartão andou dentro da finalização (os dois encerram,
por motivos diferentes, e o relatório distingue); e voltar para a fila
**desatribui** o atendente e religa o bot — mantê-lo preso a quem o largou faria
o rodízio pular quem está livre.

O cliente aplica a mesma tabela no movimento otimista, para o cartão não
aparecer na coluna de finalização ainda marcado como "na fila". Não é
divergência de regra: é o que evita uma ida ao servidor só para reler o que já
se sabe.

Conversa fora de qualquer coluna conhecida (chegou antes do fluxo existir, ou
aponta para coluna removida) ganha uma coluna "Sem coluna". Escondê-la faria
sumir atendimento de verdade.

**Falta desta etapa:**

- **O gatilho do bot não existe ainda.** A infraestrutura está pronta — qualquer
  caminho que passe por `definir_status_atendimento` move o cartão —, mas o
  worker nunca encerra um atendimento hoje. *Quando* a IA deve considerar a
  conversa encerrada é decisão de produto, não detalhe de implementação.
- Etiquetas, notas e campos personalizados no cartão (tabelas existem) — é a
  Etapa 8.

### Etapa 7 — Treinamento: intents e teste de resposta — FEITO

**A lacuna que apareceu ao começar esta etapa: nada vetorizava o material
treinado.** O `finalizar` marcava o treinamento como pendente e nenhum app
consumia a fila — `listar_pendentes_vetorizacao` não era chamado em lugar
nenhum, e `DocumentoRepository` só aparecia em leitura. Na prática o RAG
consultava uma tabela sempre vazia: a tela de treinamento gravava texto que a IA
nunca lia. Sem fechar isso, a curadoria de intenções seria outra tela sem
efeito, porque `buscar_comportamento_similar` filtra por `embedding IS NOT NULL`.

**Vetorização** — um job no scheduler do worker, no mesmo padrão dos dois que já
existiam (lock no Redis, lote configurável, varredura cross-tenant com
`admin_pool`). Consome treinamentos finalizados e intenções sem vetor, chama
`ia_engine.Embed` e grava.

O corte em trechos é por parágrafo, não por número de caracteres: um vetor é a
média semântica do que está dentro dele, e um corte no meio da frase produz um
trecho que não responde a pergunta nenhuma. Parágrafo maior que o teto não é
partido — melhor um trecho grande e íntegro que dois pedaços sem sentido.

Falha do provedor **deixa o item na fila** em vez de marcá-lo processado: marcar
sem gravar perderia o material para sempre. E gravar os trechos e marcar como
vetorizado acontecem na mesma transação — gravar sem marcar reprocessaria a cada
tick, duplicando os trechos.

**Curadoria de intenções** — aba "Intenções" na tela de treinamento, ao lado do
material. As duas juntas de propósito: o material diz o que a IA **sabe**, a
intenção diz o que ela **faz**, e uma resposta ruim pode vir de qualquer uma —
separá-las em telas esconderia isso de quem está tentando corrigir.

Editar uma intenção **zera o embedding**: o vetor foi gerado do texto antigo, e
mantê-lo faria a busca casar pelo que a intenção era. A tela avisa que ela sai
do ar até reprocessar, e a lista marca "Processando" — sem isso, alguém cadastra,
testa e conclui que o sistema não funciona.

De passagem, esta tela também não tinha menu (mesmo defeito do quadro).

**Testar pergunta** — terceira aba. A pergunta percorre o **mesmo caminho** de
uma mensagem real (embed → `QueryCompose` → `Responder`), e nada é gravado: não
cria atendimento, contato nem mensagem. Reimplementar um caminho mais curto
faria o ensaio responder diferente do que o cliente receberia, e um ensaio que
mente é pior que não ter ensaio.

A tela mostra o material consultado com a **semelhança em porcentagem** — é o
que explica por que um trecho entrou e outro não; sem isso, "respondeu errado"
não tem por onde ser investigado. E avisa quando **nada casou**: a resposta pode
parecer boa (o modelo inventa), e é justamente aí que quem treina precisa saber
que o que veio não saiu do treinamento.

O cliente de IA saiu de `apps/worker/src/ia_engine/` para `crates/ia_client`.
O worker foi o primeiro consumidor, não o único: duplicar o adapter criaria dois
lugares para configurar timeout, retry e degradação — que é o que o
`resilient.rs` existe para centralizar. O `runtime_api` já carregava o mesmo
`.env` e está na mesma rede do `ia_engine`, então **nada muda no deploy**. O
dublê do cliente virou feature `mock` da crate, para os consumidores não
reescreverem seis métodos que envelhecem em silêncio.

**Decisão tomada:** paridade completa — CRUD de intents **e** a tela de testar
pergunta. O RAG consulta `treinamento_querycompose` na composição de contexto, e
a curadoria manual continua sendo o jeito de corrigir uma resposta errada sem
esperar retreinamento.

### Etapa 8 — Detalhe do atendimento

Painéis de campos personalizados, etiquetas e notas (a v1 tem os três em
`gestao_kanban/partials/`). Depende das etapas 4 e 6.

---

## Como cada etapa é executada

Sempre nesta ordem, porque foi o que evitou retrabalho nas rodadas anteriores:

1. **contrato** — mensagens e RPCs no `.proto`;
2. **servidor** — repositório (queries validadas contra o banco real; regenerar
   o cache com `cargo sqlx prepare --workspace -- --all-targets`, conferindo que
   `git status server/.sqlx` não mostra deletados), port, adapter, handler com
   auditoria;
3. **fachada** — método concreto no `grpc_web.rs`. Sem ele o Flutter não alcança
   a rota, ainda que o `data_postgres` responda;
4. **stubs** — `server/bin/protoc.exe --dart_out=grpc:...`;
5. **cliente** — módulo no padrão RSOE, registrado no workspace, no bootstrap e
   no `test-flutter.ps1` (a lista de pacotes é fixa: módulo fora dela não é
   testado);
6. **testes** — domínio, tradução de erro e regressão do que já quebrou antes.

Armadilhas já pagas neste projeto, para não repetir: controllers de diálogo
pertencem ao `DialogoComCampos`; erro aparece dentro da janela, nunca em
SnackBar atrás do barrier; o `BuildContext` do item de lista não abre diálogo.

## Estimativa honesta

Oito etapas, cada uma com contrato+servidor+cliente+testes. **Não cabe numa
sessão** — nem em duas. A ordem acima é para que cada entrega deixe o sistema
mais usável que antes, e para que parar entre etapas não deixe nada pela metade.
