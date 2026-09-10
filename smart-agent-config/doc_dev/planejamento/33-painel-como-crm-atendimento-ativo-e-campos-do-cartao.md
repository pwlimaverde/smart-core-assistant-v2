# 33 — O painel como CRM: atendimento ativo, conversa no quadro e campos do cartão

> Levantado em 2026-09-07, a partir de três pedidos de produto. Cada afirmação
> sobre o estado atual foi medida no código e vem com `arquivo:linha`.
> **Conclusão que muda a forma de agir:** dois dos três pedidos já estão
> planejados (N9 E12 e E13) e parcialmente construídos; o que sobra é menor do
> que parece, mas contém um defeito de projeto que nenhum plano viu.

---

## 1. O que foi pedido

| # | Pedido | Em uma frase |
|---|---|---|
| **P1** | Criar atendimento a partir de um cliente cadastrado | O atendimento hoje só nasce de fora para dentro; falta o caminho de dentro para fora |
| **P2** | Conversa integrada ao painel, em cartão à direita | Não abrir o WhatsApp Web para falar com o cliente |
| **P3** | Campos personalizados por tenant, estilo Trello | Nome, tipo, descrição que orienta a IA, e lista de opções |

---

## 2. O que já existe (medido)

### A conversa (P2) — existe quase inteira

| Peça | Onde | Estado |
|---|---|---|
| Tela de chat com histórico, realtime e envio | `chat_page.dart` (177 linhas) | **pronta** |
| Ficha lateral (etiquetas + notas) | `painel_ficha.dart` (457 linhas) | **pronta**, 320 px à direita |
| Reconexão com backoff + selo de conexão | `chat_controller.dart`, `chat_connection_badge.dart` | **pronta** |
| `SendOutboundMessage`, `GetThread`, `StreamAtendimentos` | `admin.proto:946,956,941` | **prontos** |
| Mídia: solicitar upload, enviar, listar | `admin.proto:960–962` | **prontos** |

O que **não** está como pedido é o enquadramento: o quadro abre o chat com
`Navigator.push` em tela cheia (`kanban_page.dart:234`), e não como painel à
direita com o quadro visível ao lado. É layout, não capacidade — e já está
planejado como **N9 E12** ("quadro / dividido / conversa, com `Alt+1/2/3`").

### Os campos personalizados (P3) — o banco já foi desenhado para isto

As tabelas existem desde a migração **0006**, e as colunas antecipam
exatamente o que foi pedido:

```
atu_campo_personalizado
  slug, nome, descricao, escopo (GLOBAL|FLUXO), fluxo_id,
  tipo, opcoes JSONB, obrigatorio,
  extrair_automaticamente, extrair_hint,     <- a parte "a IA preenche"
  mostrar_no_card, ordem, ativo

atu_valor_campo
  valor JSONB, origem (MANUAL|IA), confianca,
  mensagem_origem_id, editado_por_id
  UNIQUE (tenant_id, atendimento_id, campo_id)
```

E há código em cima delas:

- `infrastructure_postgres/src/atendimentos/campos.rs` — `criar`,
  `listar_por_escopo`, `upsert`, `listar_por_atendimento`.
- `data_postgres/src/adapters/atendimento.rs:1469` — `resolver_campos_atendimento`
  monta o catálogo aplicável (globais + os do fluxo) e separa **coletados** de
  **pendentes**.
- `worker/src/main.rs:472` — o worker chama `ResolverCamposAtendimento` a cada
  mensagem e injeta o resultado no prompt.
- `ai_engine.proto:110–125` — `ResponderRequest` carrega
  `campos_coletados` e `campos_pendentes`, este último **com a `hint`**.

Ou seja: a IA **já recebe** a instrução de que campo falta e como extraí-lo.

### O cadastro (P1)

- `ListMyContatos` (`admin.proto:1022`) e a tela `contatos_page.dart` — **só leitura**.
- `oraculo_cliente`, `oraculo_contato` e o M2M `oraculo_cliente_contatos`
  existem desde a migração 0004, com dados fiscais e endereço.
- `buscar_ou_criar` (`adapters/atendimento.rs:660`) sustenta a invariante
  **um atendimento ativo por contato** — busca o ativo antes de criar.

---

## 3. O que N9 já planeja

| Etapa | Cobre |
|---|---|
| **E12** | Modos de foco: quadro / **dividido** / conversa, com atalhos |
| **E13** | Catálogo de campos por fluxo (`List/Create/Update/DesativarMyCampoPersonalizado`), ficha com **origem** e **barra de confiança**, edição inline via `SetValorCampoAtendimento` |
| **E11** | Preview da última mensagem e foto do contato no cartão |
| **E9/E10** | Busca, filtros, prioridade, atribuição, transferência manual |

**P2 é E12. P3 é E13.** Nenhum dos dois precisa de plano novo — precisam de
precisão, porque E13 descreve *que* telas existir sem dizer *o que* um campo é.

---

## 4. As cinco lacunas reais

### 4.1 🚨 O laço da IA está aberto

`ResponderRequest` leva `campos_pendentes` com `slug`, `nome`, `descricao` e
`hint`. `ResponderResponse` (`ai_engine.proto:131–136`) tem quatro campos:

```proto
string resposta_texto = 1;
bool   transferir_atendimento = 2;
string fluxo_transferencia = 3;
double confiabilidade = 4;
```

**Não há por onde devolver o valor extraído.** O próprio contrato do port já
admite isso, em comentário: *"o contrato do Responder não devolve campos
extraídos, então não há write-back aqui"* (`ports/atendimento.rs:435`).

A consequência não é um recurso ausente — é um comportamento errado em
produção: a IA é instruída a perguntar o número do pedido, o cliente responde,
o valor é descartado, o campo segue pendente, e **na mensagem seguinte a IA
pergunta de novo**. O cliente é interrogado em laço.

E há um segundo efeito, dentro do próprio planejamento: **N9 E13 planeja exibir
a origem BOT com barra de confiança** — uma origem que nada no sistema é capaz
de gravar. A tela seria construída para um estado inalcançável.

### 4.2 `extrair_automaticamente` não é consultado

Em `resolver_campos_atendimento`, o filtro do que vira pendente é:

```rust
None if def.obrigatorio => pendentes.push(...),
None => {}
```

A coluna que existe para dizer *"a IA deve extrair este campo"* é ignorada;
quem decide é `obrigatorio`. São conceitos diferentes: *número do pedido* pode
ser obrigatório e vir do ERP (a IA não deve inventá-lo), e *tipo de produto*
pode ser opcional e ser justamente o que mais se quer extrair da conversa.
Hoje um campo opcional nunca chega ao prompt, e um campo obrigatório sempre
chega, mesmo marcado para não ser extraído.

### 4.3 O catálogo é somente-leitura — e por isso está sempre vazio

Fora dos testes, **as únicas chamadas em produção aos repositórios de campo são
de leitura**, dentro de `resolver_campos_atendimento`:

```
adapters/atendimento.rs:1475   PostgresCampoPersonalizadoRepository   (listar)
adapters/atendimento.rs:1476   PostgresValorCampoRepository           (listar)
```

`criar` e `upsert` existem, compilam, são testados — e **nunca são chamados por
nada que um usuário possa alcançar**. Não há RPC, não há tela, não há caminho.

A consequência é literal: **nenhum tenant tem, ou pode ter, um campo
personalizado**. E o worker chama `ResolverCamposAtendimento` a cada mensagem
(`worker/src/main.rs:472`), o que abre uma transação e faz três consultas para,
invariavelmente, devolver duas listas vazias.

Isso tem um lado bom, e ele decide o sequenciamento: **não há dado legado.**
Nenhuma decisão desta análise precisa de migração de dados ou janela de
compatibilidade — nem a troca do filtro de extração (§4.2), nem o `CHECK` de
tipo, nem a forma tipada do valor. É a hora mais barata que existirá para
acertar o formato.

### 4.4 O catálogo não é editável de verdade

`campos.rs::criar` aceita seis argumentos — `slug`, `nome`, `escopo`, `tipo`,
`fluxo_id` — e **nenhum** deles é `descricao`, `opcoes`, `obrigatorio`,
`extrair_hint`, `mostrar_no_card` ou `ordem`. Não existe `atualizar`, nem
`desativar`, nem reordenar. Um campo criado hoje nasce sem descrição, sem
opções e sem dica — sem exatamente as três coisas que o pedido descreve.

Além disso, `tipo` é `VARCHAR(20)` **sem `CHECK`**, e o repositório o recebe
como `&str` cru: nada impede gravar `tipo = 'banana'`.

E a rota planejada na E13 é `/tenant/fluxos/:id/campos` — só o escopo `FLUXO`.
O escopo `GLOBAL` existe na tabela e não tem por onde ser criado. O pedido
("um menu de personalização de cartão") é o escopo global.

### 4.5 O atendimento só nasce de fora

Não existe RPC de criação de atendimento na borda —
`SendOutboundMessage` exige `atendimento_id` (`admin.proto:562`), e o único
caminho de nascimento é o `buscar_ou_criar` disparado pelo webhook. Um cliente
cadastrado no CRM, com telefone conhecido, não tem como virar conversa.

---

## 5. O que o Trello ensina — e onde discordar dele

Fontes: [Getting Started With Custom Fields](https://developer.atlassian.com/cloud/trello/guides/rest-api/getting-started-with-custom-fields/)
e [Custom Fields REST API](https://developer.atlassian.com/cloud/trello/rest/api-group-customfields/).

### O modelo do Trello

| Aspecto | Trello |
|---|---|
| Tipos | `text`, `number`, `date`, `checkbox`, `list` — cinco, fechados |
| Definição | `name`, `type`, `pos`, `options[]` (só para `list`), `idModel` + `modelType: "board"` |
| Opção de lista | `{ "id": "...", "value": {"text": "High"}, "color": "red", "pos": 16384 }` |
| Valor no cartão | tipado pelo campo: `{"text":...}`, `{"number":"42"}`, `{"date": ISO}`, `{"checked":"true"}`; e **`{"idValue": "<id da opção>"}`** para lista |
| Limpar | `PUT` vazio; **não há endpoint de exclusão de valor** |
| Teto | 50 definições por quadro |

### O que copiar

1. **Cinco tipos, fechados.** Cobrem o que foi pedido (texto, data, número,
   lista) mais `booleano`. Tipo aberto vira lixo em produção e impede validar.
2. **Valor tipado pela definição**, não texto livre. Sem isso não há como
   ordenar por data nem somar número.
3. **A lista guarda o `id` da opção, nunca o rótulo.** É a decisão silenciosa
   mais importante do Trello: renomear "Camiseta" para "Camiseta Premium" não
   reescreve nenhum cartão. Guardar o rótulo faria a renomeação corromper o
   histórico inteiro.
4. **Ordem explícita** (`pos` / `ordem`) — já temos a coluna.
5. **Um teto por tenant.** No Trello é ergonomia de tela. Para nós é custo
   direto: **todo campo pendente entra no prompt**. Cinquenta campos sem valor
   são cinquenta instruções por mensagem.

### Onde discordar

| Trello | Nós | Por quê |
|---|---|---|
| Sem `descrição` no campo | `descricao` é peça central | No Trello a descrição seria enfeite; aqui ela **é a instrução da IA**. É o que faz "Agendamento de novo contato" virar extração |
| Lista é seleção **única** | Lista **múltipla** | Foi pedido explicitamente: *"se o cliente declarar interesse em um ou mais produtos"*. Interesse não é excludente |
| Escopo único (quadro) | `GLOBAL` + `FLUXO` | Já modelado. "Número do pedido" vale para todo mundo; "tipo de exame" só vale no fluxo da clínica |
| Limpar = `PUT` vazio, por ergonomia | Limpar = **estado semântico** | Aqui a distinção tem consequência: se um humano apagar um valor que a IA errou, a IA **não pode** repreenchê-lo na mensagem seguinte. "Nunca preenchido" e "apagado por gente" precisam ser estados diferentes |

**Como representar o valor apagado sem coluna nova:** `valor` é `JSONB NOT NULL`,
e `'null'::jsonb` é um valor válido e não-nulo. Linha ausente = nunca
preenchido; linha com `valor = 'null'::jsonb` = deliberadamente vazio. O guarda
de sobrescrita usa `editado_por_id IS NOT NULL` — que hoje nunca é preenchido e
passa a ser.

### Forma proposta do valor

```jsonc
// tipo = texto      -> {"texto": "Rua das Flores, 120"}
// tipo = numero     -> {"numero": 42.5}
// tipo = data       -> {"data": "2026-09-15T09:00:00Z"}
// tipo = booleano   -> {"marcado": true}
// tipo = lista      -> {"opcao_ids": ["opt_7f3a", "opt_91bc"]}
```

E a opção, dentro de `opcoes`:

```jsonc
{"id": "opt_7f3a", "rotulo": "Camiseta", "cor": "#a98f71", "ordem": 0}
```

---

## 6. O delta a construir

### O que vai para N9 (precisão, não plano novo)

- **E12** ganha o requisito explícito: clicar no cartão abre a conversa **no
  painel à direita, com o quadro visível**; tela cheia vira um dos modos, não o
  único. A `ChatPage` já existe e é reaproveitada como widget.
- **E13** ganha a especificação que falta: os cinco tipos com `CHECK`, opções
  com id estável, escopo `GLOBAL` com rota própria, `mostrar_no_card` refletido
  no cartão, teto por tenant, e a semântica de valor apagado.

### O que é plano novo

| Bloco | Entrega |
|---|---|
| **C1** | Fechar o laço da IA: `campos_extraidos` na `ResponderResponse`, com validação por tipo, piso de confiança e guarda contra sobrescrever humano |
| **C2** | `extrair_automaticamente` passa a ser o filtro do que vai ao prompt, no lugar de `obrigatorio` |
| **C3** | Atendimento ativo: `IniciarAtendimento` a partir de contato ou cliente, reusando a invariante de um ativo por contato |
| **C4** | Cadastro e edição de contato, e vínculo contato ↔ cliente (a tela é só leitura hoje) |

### Decisões de produto que o novo plano assume

| Tema | Decisão | Por quê |
|---|---|---|
| Piso de confiança para gravar campo | **Reusa o limiar do D1** (`regras-do-bot-e-permissoes`) | Um só número por tenant para "quando confio na IA"; dois seriam duas verdades |
| IA sobrescreve valor humano | **Nunca** | Quem corrigiu já viu a conversa |
| Bot na conversa iniciada à mão | Nasce **desligado** | Alguém decidiu falar com esse cliente; o robô não entra no meio. O caminho de volta é o D3, já construído |
| Atendimento ativo com conversa já aberta | **Reaproveita a existente** | Criar um segundo cartão para o mesmo contato quebra a invariante e duplica a fila |
| Valor de campo em log ou auditoria | **Nunca** | É livre: pode ser CPF, endereço, diagnóstico. Auditar qual campo mudou, não o quê |

### Riscos

- 🚨 **C1 muda o contrato da IA e o `ia_engine` junto.** O `ResponderResponse`
  é aditivo, mas o `ia_engine` precisa aprender a devolver o campo — e a
  devolver **nada** quando não souber, em vez de inventar. Alucinação aqui
  grava dado errado na ficha do cliente.
- 🚨 **C3 dispara mensagem para quem não escreveu primeiro.** A evolution-go é
  whatsmeow: `POST /message/text` aceita qualquer JID, sem a janela de 24 h da
  Cloud API. Tecnicamente possível; operacionalmente é o caminho mais curto
  para o número ser denunciado. O plano precisa de um limite e de auditoria
  por autor.
- **C2 muda o que a IA vê sem mudar nenhuma tela.** Um tenant que hoje tem
  campos obrigatórios não-extraíveis verá a IA parar de perguntá-los. É a
  correção certa, mas é mudança de comportamento visível.
- **Teto de campos.** Sem ele, o prompt cresce sem limite e o custo por
  mensagem sobe silenciosamente.

---

## 7. Resumo em uma tabela

| Pedido | Já existe | Já planejado | Falta de verdade |
|---|---|---|---|
| **P1** atendimento a partir do cliente | contatos, clientes, invariante de ativo | — | **tudo**: C3 + C4 |
| **P2** conversa no painel | chat, ficha, envio, mídia, realtime | N9 E12 (modo dividido) | só o enquadramento — precisar melhor a E12 |
| **P3** campos personalizados | tabelas, repositório, entrega ao prompt | N9 E13 (catálogo + ficha) | tipos e opções (E13 precisada) + **C1** e **C2** |

O item de maior valor não é nenhum dos três como enunciados: é **C1**. Sem ele,
os campos personalizados existem, aparecem na tela, e continuam sendo
preenchidos à mão — enquanto a IA pergunta pela mesma informação em toda
mensagem, sem nunca ouvir a resposta.
