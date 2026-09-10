# Plano completo — Painel CRM e campos do cartão

> **Verdade técnica** deste plano. O canônico é leve e aponta para cá.
> Documentação de apoio: [info_aux](./info_aux_painel-crm-e-campos-do-cartao.md).
> Fonte de requisito: [doc 33](../../../doc_dev/planejamento/33-painel-como-crm-atendimento-ativo-e-campos-do-cartao.md).

> **Este plano é só o delta.** Dos três pedidos de produto que o originaram,
> **dois já estavam planejados**: a conversa em painel ao lado do quadro é
> **N9 E12** e o catálogo de campos personalizados é **N9 E13** — ambos
> precisados no plano da N9 em 2026-09-07, no mesmo levantamento que gerou este.
> O que resta são quatro blocos que nenhum plano cobria.

---

## O ponto de partida

Três pedidos. O levantamento mediu cada um contra o código:

| Pedido | Já existe | Já planejado | Delta real |
|---|---|---|---|
| Atendimento a partir de um cliente | contatos, clientes, invariante de ativo | — | **tudo** → C3 + C4 |
| Conversa no painel | chat, ficha, envio, mídia, realtime | N9 E12 | só o enquadramento |
| Campos personalizados | tabelas, repositório, entrega ao prompt | N9 E13 | tipos e opções (na E13) + **C1** e **C2** |

E um quarto item, que ninguém pediu porque ninguém sabia: **o laço da IA está
aberto**. É o de maior valor do conjunto.

---

# C1 — Fechar o laço: a IA preenche o campo

## O defeito, em três linhas de contrato

`ResponderRequest` leva `campos_pendentes` com `slug`, `nome`, `descricao` e
`hint` — a IA **já é instruída** sobre qual campo falta e como extraí-lo
(`ai_engine.proto:110`). `ResponderResponse` tem quatro campos e **nenhum deles
carrega valor extraído** (`ai_engine.proto:131`).

O port documenta a ausência como se fosse dado da natureza:

> *"o contrato do Responder não devolve campos extraídos, então não há
> write-back aqui"* — `ports/atendimento.rs:435`

O efeito em produção não é um recurso faltando. É um comportamento errado: a IA
pergunta o número do pedido, o cliente responde, o valor é descartado, o campo
continua pendente, e **na mensagem seguinte a IA pergunta de novo**. O cliente é
interrogado em laço, e a conversa fica pior quanto mais campos o tenant criar.

## Contrato — aditivo

```proto
message CampoExtraido {
  string slug = 1;
  string valor_json = 2;  // já na forma tipada do campo
  double confianca = 3;
}

message ResponderResponse {
  string resposta_texto = 1;
  bool   transferir_atendimento = 2;
  string fluxo_transferencia = 3;
  double confiabilidade = 4;
  repeated CampoExtraido campos_extraidos = 5;  // novo
}
```

Campo aditivo em mensagem existente: `ia_engine` antigo devolve lista vazia e
segue funcionando. Sem `reserved` a queimar, sem migração de contrato.

## No `ia_engine`

Saída estruturada via `with_structured_output` com `pydantic.BaseModel` v2
direto — o shim `langchain_core.pydantic_v1` **foi removido** na LangChain 1.x
(ver info_aux):

```python
class CampoExtraido(BaseModel):
    slug: str = Field(description="slug exato de um campo pendente; nunca invente")
    valor_json: str = Field(description="valor na forma tipada do campo")
    confianca: float = Field(ge=0.0, le=1.0)

class RespostaDoResponder(BaseModel):
    resposta_texto: str
    transferir_atendimento: bool = False
    fluxo_transferencia: str = ""
    confiabilidade: float = Field(ge=0.0, le=1.0)
    campos_extraidos: list[CampoExtraido] = Field(default_factory=list)
```

O prompt instrui a **devolver só o que o cliente disse** e a **omitir quando não
souber**. Lista vazia é o resultado esperado na maioria das mensagens — e
precisa ser dito no prompt, senão o modelo preenche para agradar.

> ⚠️ **O schema restringe a forma, não a verdade.** Um `slug` inexistente com
> um valor inventado é JSON perfeitamente válido para o Pydantic. Por isso a
> validação semântica **não** fica aqui.

## Gravação — as cinco guardas, nesta ordem

RPC interno novo no `data_postgres`:
`GravarCamposExtraidos(atendimento_id, [{slug, valor, confianca}], mensagem_origem_id)`,
chamado pelo worker depois da resposta, no mesmo caminho que já chama
`ResolverCamposAtendimento` (`worker/src/main.rs:472`).

1. **O slug existe no catálogo aplicável e está ativo.** Slug alucinado é
   descartado. O LLM não define o esquema — só preenche o que o tenant declarou.
2. **`extrair_automaticamente = true`.** Campo marcado para não ser extraído não
   é gravado nem que a IA insista.
3. **O valor é válido para o `tipo`** — e, em `lista`, cada id existe em
   `opcoes`. Inválido é descartado com contagem, nunca coagido a texto: gravar
   `"quinze"` num campo `numero` envenena todo relatório futuro.
4. **`confianca >= limiar do tenant`** — o **mesmo** limiar do D1 de
   `regras-do-bot-e-permissoes`. Um número por tenant para "quando confio na
   IA"; dois seriam duas verdades sobre a mesma pergunta. Enquanto o D1
   (deploy 2) não entrega o limiar configurável, C1 usa **0.8** como constante.
5. **Não sobrescreve humano, nem repreenche o que humano apagou:**

```sql
INSERT INTO atu_valor_campo
    (tenant_id, atendimento_id, campo_id, valor, origem, confianca, mensagem_origem_id)
VALUES ($1, $2, $3, $4, 'IA', $5, $6)
ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
   SET valor = EXCLUDED.valor,
       origem = 'IA',
       confianca = EXCLUDED.confianca,
       mensagem_origem_id = EXCLUDED.mensagem_origem_id,
       data_atualizacao = NOW()
 WHERE atu_valor_campo.editado_por_id IS NULL
   AND atu_valor_campo.valor <> 'null'::jsonb
RETURNING id
```

Quando a condição do `WHERE` é falsa, a linha existente fica intacta e
`RETURNING` devolve **zero linhas** — o chamador sabe que não gravou sem uma
consulta extra.

`editado_por_id` existe na tabela desde a 0006 e **nunca é gravado**; passa a
ser, na edição manual da N9 E13. `valor = 'null'::jsonb` é o valor apagado de
propósito — quem apagou leu a conversa e discordou da IA. Numa coluna
`JSONB NOT NULL`, o literal JSON `null` é gravável e distinguível de linha
ausente; é o que separa *nunca preenchido* de *apagado* sem coluna nova.

## Observabilidade & Auditoria

**a) Logs/traces.** Span `ia.campos_extraidos` com `service`, `env`,
`tenant_id`, `trace_id` e as contagens: `recebidos`, `gravados`, e
`descartados` **quebrado por motivo** (slug desconhecido, tipo inválido, abaixo
do piso, humano no caminho). Esse detalhamento não é enfeite — é o instrumento
de calibração: sem ele, "a IA não preenche nada" é indistinguível de "a IA
preenche tudo errado e o piso está barrando".
`#[instrument(skip_all)]` no repositório, dentro de `run_in_tenant_transaction`.
**Não** usar `instrument(err)`: descartar um campo é resultado normal do
caminho, não falha de infraestrutura.

**b) Auditoria.** `campo_personalizado.preenchido_pela_ia`, com `user_id` do
`RequestContext` (o worker, neste caso), `ip_address`, `user_agent`, timestamp
UTC, e na descrição **o slug do campo e a confiança — nunca o valor**.
Publicada assíncrona pelo `transport::bus` → `data_postgres`.

**c) Sanitização.** 🚨 **Risco alto.** `valor_json` é conteúdo livre definido
pelo tenant: pode ser CPF, endereço, diagnóstico médico. Ele **não entra** em
span, log, mensagem de erro nem descrição de auditoria. `skip_all` obrigatório
em todo o caminho.

## Testes

Slug inexistente descartado · valor de tipo errado descartado · opção fora de
`opcoes` descartada · abaixo do piso descartado · valor humano preservado ·
valor apagado por humano não repreenchido · campo com
`extrair_automaticamente = false` ignorado · **nenhum valor em log ou
auditoria** (asserção sobre o registro emitido, não inspeção visual).

---

# C2 — `extrair_automaticamente` decide o que vai ao prompt

## O defeito

Em `resolver_campos_atendimento` (`adapters/atendimento.rs:1469`), o filtro do
que vira pendente é:

```rust
None if def.obrigatorio => pendentes.push(...),   // hoje
None => {}
```

A coluna que existe para dizer *"a IA deve extrair este campo"* — 
`extrair_automaticamente` — **não é lida em lugar nenhum**. Quem decide é
`obrigatorio`, que é outra coisa.

São conceitos distintos, e confundi-los erra nos dois sentidos: *número do
pedido* pode ser obrigatório e vir do ERP (a IA não deve inventá-lo), e *tipo de
produto* pode ser opcional e ser justamente o que mais se quer extrair da
conversa. Hoje o campo opcional nunca chega ao prompt e o obrigatório sempre
chega, mesmo marcado para não ser extraído.

## O que fazer

```rust
None if def.extrair_automaticamente => pendentes.push(...),
```

`obrigatorio` volta a ser o que o nome diz: **regra de tela** — impede concluir
o atendimento sem o campo — e nada mais.

**Sem risco de migração.** Nenhum tenant tem campo personalizado, porque não
existe caminho para criar um (doc 33 §4.3). A troca não muda o comportamento de
ninguém hoje; muda o de todo mundo depois da N9 E13. É exatamente por isso que
precisa entrar **antes** dela — depois seria mudança de comportamento em cima
de configuração que os tenants já fizeram.

Entra junto com C1: os dois mexem no que a IA vê.

## Observabilidade & Auditoria

**a) Logs.** Campo `pendentes_por_extracao` no span já emitido pela resolução,
ao lado da contagem de coletados. Nível `debug` — é caminho quente, roda a cada
mensagem.

**b) Auditoria.** **Sem evento de auditoria**, intencionalmente: é mudança de
filtro de leitura, não acesso nem alteração de estado sensível.

**c) Sanitização.** Nada novo trafega. `descricao` e `hint` já vão para o prompt
hoje; são texto do tenant, não do cliente.

## Nota de oportunidade

Enquanto o catálogo estiver vazio, `ResolverCamposAtendimento` abre uma
transação e faz três consultas por mensagem para devolver duas listas vazias
(doc 33 §4.3). Vale medir se compensa um curto-circuito quando o tenant não tem
campo algum — **medir antes de otimizar**; fica registrado, não é entrega.

---

# C3 — Atendimento ativo: falar primeiro

## RPC

```proto
message IniciarAtendimentoRequest {
  // Um dos dois: contato existente, ou telefone (+ nome) para criar na hora.
  optional int32  contato_id = 1;
  optional string telefone = 2;
  optional string nome = 3;

  int32 fluxo_id = 4;                  // obrigatório
  optional int32 etapa_id = 5;         // omitido = etapa inicial do fluxo
  optional int32 departamento_id = 6;
  optional string assunto = 7;
  optional string primeira_mensagem = 8;
}

message IniciarAtendimentoResponse {
  int32 atendimento_id = 1;
  bool  ja_existia = 2;
}
```

Escopo: `atendimentos:write`.

## Regras

**Reusa a invariante de um ativo por contato.** `buscar_ou_criar`
(`adapters/atendimento.rs:660`) já procura o atendimento ativo antes de criar.
Se já existe conversa aberta com aquele contato, o RPC devolve a existente com
`ja_existia = true` e a tela **abre** em vez de criar um segundo cartão. Criar o
segundo quebraria a invariante e daria à mesma pessoa dois lugares na fila.

**Define fluxo e etapa explicitamente.** A ingestão cria com `(None, None, None)`
e o fluxo é preenchido depois por `COALESCE` (`atendimentos.rs:624`). Um
atendimento sem `etapa_atual_id` **não aparece em nenhuma coluna do quadro** —
nasceria invisível, e ninguém procuraria por ele. `fluxo_id` é obrigatório no
request e validado no servidor; `etapa_id` omitido resolve para a etapa inicial
do fluxo.

**`bot_pode_atender = false` na criação manual.** Alguém decidiu falar com esse
cliente; o robô não entra no meio de uma conversa que uma pessoa começou. O
caminho de volta já existe e já está entregue: `DefinirBotDaConversa` (D3).

**`atendente_humano_id` = quem criou.** Quem inicia, atende.

**`primeira_mensagem`**, quando vier, encadeia `SendOutboundMessage` na mesma
ação — senão o cartão nasce mudo e depende de alguém lembrar de escrever.

## O contrato real do envio

> 🚨 **Não seguir o `ref_evolution_go.md` da N9 neste ponto.** A linha 874
> daquele arquivo mostra `POST /message/sendText/{instance}`, que é o formato da
> **Evolution API v2** — e não existe aqui.

Contrato real, lido em `provider.rs:446`:

```
POST {base_url}/send/text
Header: apikey: <token da instância>     # SecretString, nunca logar
Body:   {"number": "<telefone>", "text": "<texto>"}
```

Retry já implementado no provider: até 3 tentativas, backoff a partir de 500 ms,
só para 5xx e `429`.

## O risco que não é técnico

A evolution-go é whatsmeow: `POST /send/text` aceita qualquer JID, **sem a
janela de 24 h nem o template obrigatório** da WhatsApp Cloud API. Iniciar
conversa com quem nunca escreveu é trivial de implementar e é o caminho mais
curto para o número do tenant ser denunciado e bloqueado. O provider não vai
impedir — a mitigação é de produto:

- **Teto diário por tenant** de atendimentos iniciados manualmente.
- **Auditoria por autor**, para que o abuso tenha nome.
- **Recusa clara quando a instância não está conectada**, em vez de enfileirar
  um envio que nunca sai (o cartão existiria, a mensagem não).

## Cliente

Botão "Iniciar atendimento" no quadro e na tela de contatos. Seletor de contato
com busca (a busca de contatos já é server-side, com debounce — reusar, não
reescrever), seletor de fluxo e etapa inicial, campo opcional de primeira
mensagem. Quando `ja_existia = true`, abrir a conversa e dizer que já havia uma
aberta — sem tratar como erro, porque não é.

## Observabilidade & Auditoria

**a) Logs.** Span `atendimento.iniciado` com `tenant_id`, `trace_id`,
`contato_id`, `fluxo_id` e `ja_existia`. **Não** o telefone: PII.

**b) Auditoria.** `atendimento.iniciado_manualmente` — autor (`user_id` do
`RequestContext`), `ip_address`, `user_agent`, timestamp UTC, contato e fluxo.
**Não o texto da primeira mensagem.** É o evento que dá nome ao disparo ativo, e
é o que se consulta quando um número é denunciado.

**c) Sanitização.** Telefone é PII e o texto da primeira mensagem é conteúdo
destinado ao cliente — nenhum dos dois em log. O `apikey` da instância é
`SecretString` e já é tratado assim pelo provider; não desembrulhar fora do
ponto de envio.

---

# C4 — Contato deixa de ser somente-leitura

`CriarMeuContato`, `AtualizarMeuContato`, `VincularContatoCliente`,
`DesvincularContatoCliente`. A tela `contatos_page.dart` ganha criar e editar; o
M2M `oraculo_cliente_contatos` existe desde a migração 0004 e nunca teve
escrita exposta.

**Normalizar o telefone antes de gravar.** A chave é
`UNIQUE (tenant_id, telefone)` (migração 0004): sem normalização, `+55 11 9…` e
`5511 9…` viram dois contatos, e a mesma pessoa ganha dois atendimentos que
nunca se encontram — inclusive furando a invariante de C3, que confia nessa
chave. **Reusar a normalização já usada na ingestão**, nunca escrever a segunda:
duas normalizações divergentes produzem exatamente o bug que ambas existem para
evitar.

## Observabilidade & Auditoria

**a) Logs.** Spans `contato.cadastrado` e `contato.atualizado` com `tenant_id`
e `contato_id`. Nunca o telefone.

**b) Auditoria.** `contato.criado`, `contato.atualizado`,
`contato.vinculado_cliente` — com autor e metadados padrão. Na descrição,
**quais campos mudaram**, não os valores.

**c) Sanitização.** Telefone, e-mail e documento são PII. Auditar a mudança, não
o dado.

---

# Sequência

```
C2 → C1        (os dois mexem no prompt; C2 é barato e precede a N9 E13)
C4 → C3        (iniciar conversa com quem não está cadastrado exige cadastrar)
```

C1/C2 e C3/C4 são independentes entre si e podem correr em paralelo.

**Dependências para fora deste plano:**

| De | Para | Natureza |
|---|---|---|
| C1 | **D1** (`regras-do-bot-e-permissoes`) | Usa o limiar de confiança por tenant. Enquanto não existir, 0.8 constante — não bloqueia |
| C3 | **D3** | Usa `DefinirBotDaConversa` para religar o bot. **Já entregue** |
| **N9 E13** | **C1** | E13 exibe origem `IA` e barra de confiança. Sem C1, exibe um estado que nada sabe produzir |

Essa última é a que importa no sequenciamento geral: **C1 antes da N9 E13**, ou
a E13 constrói uma barra que nunca aparece.

---

# Riscos

| Risco | Mitigação |
|---|---|
| 🚨 **Alucinação grava dado errado na ficha do cliente** | As cinco guardas de C1, nesta ordem; piso de confiança; prompt instruído a **omitir**, não a inferir. O schema Pydantic não protege disto — ele valida forma, não verdade |
| 🚨 **Disparo ativo derruba o número do tenant** | Teto diário, auditoria por autor, recusa se a instância não estiver conectada. Sem janela de 24 h para nos proteger |
| 🚨 **Valor de campo vazar em log ou auditoria** | `skip_all` em todo o caminho de C1; teste que assere sobre o registro emitido |
| Seguir o `ref_evolution_go.md` no envio | O contrato real é `POST /send/text` (`provider.rs:446`); o ref traz o formato da Evolution v2, que não existe aqui |
| Prompt cresce sem limite com muitos campos | Teto de 50 campos por escopo (N9 E13) — todo pendente entra em toda mensagem |
| Duplicidade de contato por telefone não normalizado | Reusar a normalização da ingestão; nunca escrever a segunda |
| Atendimento manual nasce fora de qualquer coluna | `fluxo_id` obrigatório e etapa resolvida no servidor |

---

# Definition of Done

- [ ] A IA extrai um campo declarado na conversa e ele aparece na ficha com
      origem `IA` e a confiança.
- [ ] A IA **para** de perguntar um campo depois que ele foi preenchido.
- [ ] Valor corrigido por humano não é sobrescrito na mensagem seguinte.
- [ ] Valor apagado por humano não é repreenchido.
- [ ] Campo com `extrair_automaticamente = false` nunca chega ao prompt.
- [ ] Valor de tipo inválido é descartado, nunca coagido a texto.
- [ ] Nenhum valor de campo em log ou auditoria — provado por teste.
- [ ] Atendimento criado a partir de um contato cai numa coluna do quadro, com
      o bot desligado e atribuído a quem criou.
- [ ] Contato já em conversa aberta reaproveita o atendimento, não duplica.
- [ ] Disparo ativo é auditado com autor e respeita o teto diário.
- [ ] Contato pode ser cadastrado, editado e vinculado a um cliente.
- [ ] Sensores `rust-rapido` e `flutter-analise-testes` verdes.

---

# Fora de escopo

- **Conversa em painel ao lado do quadro** → N9 **E12** (precisada em 2026-09-07).
- **Catálogo de campos, tipos, opções, ficha e cartão** → N9 **E13** (idem).
- **Preview e foto no cartão** → N9 E11.
- Demais frentes: N10, N11, N12, `cadastro-retomavel-e-pagamento` e
  `regras-do-bot-e-permissoes`.

---

# Correções aplicadas na reestruturação

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 1 | **Endpoint de envio corrigido** de `POST /message/sendText/{instance}` para `POST {base_url}/send/text`, com body `{number, text}` e header `apikey` | O `ref_evolution_go.md` da N9 (linha 874) traz o formato da **Evolution API v2**, que não existe nesta instalação. Seguir o ref teria produzido 404 em C3 | `infrastructure_evolution/src/provider.rs:446` |
| 2 | **Pydantic: 2.7.1 → 2.13.4** na central local | O doc local apontava versão **anterior à do próprio projeto** (`pyproject.toml` exige `>=2.9`). Verificado: entre 2.7 e 2.13 nada quebra em `BaseModel`, `Field`, `model_validate`, `model_json_schema` | Changelog oficial, 2026-09-07 |
| 3 | **Shim `langchain_core.pydantic_v1` descartado** do desenho de C1 | Removido na LangChain 1.x; usar `pydantic.BaseModel` v2 direto em `with_structured_output` | `doc_dev/libs/python/langchain.md` (2026-07-06) |
| 4 | **`sqlx` não foi ao Context7** apesar do doc não cobrir `JSONB`/`ON CONFLICT` | Nenhum dos dois é API do sqlx: o `WHERE` no `DO UPDATE` é PostgreSQL, e a ligação `serde_json::Value` ↔ `JSONB` já está provada no repositório | `campos.rs:165` |
| 5 | **Guarda anti-sobrescrita movida para o banco** (`WHERE` no `DO UPDATE`) em vez de ler-antes-de-escrever na aplicação | Ler e depois escrever abre janela de corrida entre a IA e a edição humana simultânea. A cláusula resolve na mesma instrução, e `RETURNING` vazio já sinaliza "não gravei" | PostgreSQL |
| 6 | **Sequência invertida:** C2 passa a preceder a N9 E13 | Trocar o filtro de extração hoje não afeta ninguém (não há campo criado); depois da E13 seria mudança de comportamento sobre configuração já feita pelos tenants | doc 33 §4.3 |
| 7 | **Piso de confiança amarrado ao D1** em vez de constante própria | Dois números para "quando confio na IA" seriam duas verdades sobre a mesma pergunta. Constante 0.8 é ponte, não destino | `regras-do-bot-e-permissoes` D1 |
| 8 | **Risco de log elevado a 🚨 em C1** | `valor_json` é conteúdo livre do tenant — pode ser CPF ou diagnóstico. O plano original tratava sanitização como nota de rodapé | doc 33 §6, `08_diretrizes_seguranca.md` §4.2 |
