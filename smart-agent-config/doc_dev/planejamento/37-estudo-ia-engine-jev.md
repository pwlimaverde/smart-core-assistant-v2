# 37 — Estudo: `ia_engine` com o Jev (TypeSafe System One) na análise de mensagens

> **Status:** estudo + proposta de plano, aguardando decisão. Nada foi implementado.
> **Data:** 2026-09-27
> **Fontes:** documentação oficial da TypeSafe lida por completo (conceitos, primitivas,
> confiança, modelos, *jaggedness* do Jev 1.13, API HTTP, SDK Python e os cookbooks de
> roteamento de intenção, *fan-out*, classificação com confiança, sugestão de skill,
> extração por candidatos, cascata de extração, classificação de passagens de RAG,
> *guardrails* e auto-consistência) — resumo em `libs/python/typesafe_sdk.md`; código
> atual do `ia_engine`, do worker e do `data_postgres`; catálogo real do tenant Paulo
> Ecoprint (23 intenções, 10 tipos de entidade).

---

## 1. A pergunta

Criar um módulo novo, derivado do `ia_engine`, em que **toda a análise de mensagens**
passe a ser feita pelo Jev em vez de uma chamada de LLM, plugado no lugar do atual; e
verificar se o pydantic continua necessário, já que o Jev devolve as intenções tipadas.

## 2. Resposta curta

1. **Dá, e é o encaixe certo para intenção, sentimento e pedido de humano.** São
   exatamente decisões de "escolha uma opção de uma lista" ou "isto é verdade?", que é o
   que o Jev faz — com probabilidade calibrada, ~100 ms e custo de centavos por mil
   mensagens.
2. **Não dá para trocar "toda" a IA.** O Jev **não gera texto**: a resposta ao cliente,
   a transcrição de áudio, a leitura de imagem e os embeddings continuam onde estão. O
   módulo novo substitui as **decisões**; a **geração** segue com LLM (e fica mais
   simples, porque deixa de decidir).
3. **A transferência para atendente sai da LLM.** Hoje ela depende de uma nota que a
   própria LLM se dá, de um regex no texto gerado e de similaridade de embeddings. Passa a
   ser uma decisão do Jev, **antes** de gerar (pedido de humano, regras do tenant, setor,
   intenção que transfere) e conferida **depois** (a resposta se apoia na base?), com a
   regra em código e o motivo registrado. Quando transfere, a LLM nem roda (§5.4).
4. **Entidades são o ponto fraco.** Os 10 tipos do tenant são valores livres
   (dimensões, acabamento, prazo…). O Jev não extrai valor livre: ele **escolhe entre
   candidatos**. Metade dos tipos tem candidato por regex ou lista fechada; a outra
   metade precisa de um extrator (LLM pequena) com o Jev verificando.
5. **Pydantic fica, mas encolhe.** Somem os schemas de *structured output* (o schema
   dinâmico da análise, o da avaliação e, na J3, o da resposta, junto com a transferência). Fica onde ele é
   bom: settings, config do Redis e o próprio SDK da TypeSafe, que usa pydantic por dentro
   desde a v0.7.0 — não dá para removê-lo da árvore de dependências.
6. **O maior risco é o idioma.** A TypeSafe declara o inglês como idioma principal e diz
   que outros idiomas têm acurácia menor. Nosso tráfego é 100% português. Por isso o plano
   começa com um **conjunto de avaliação** e um **modo sombra**, antes de qualquer troca.

---

## 3. O que é o Jev (o que importa para esta decisão)

| Característica | Detalhe | Impacto aqui |
|---|---|---|
| Primitivas | `Choice` (uma de N, até 255), `Score` (nível ordenado, 2–10), `Noul` (P(sim)) | intenção = `Choice`; várias intenções = um `Noul` por intenção; satisfação = `Score` |
| Paralelismo | todas as perguntas de uma chamada rodam em paralelo e isoladas | a análise inteira de uma mensagem cabe em **uma** requisição |
| Saída | sempre dentro das opções dadas + probabilidades + `confidence` | não há parse de JSON, nem tag inventada |
| Calibração | treinado para probabilidade calibrada (RLCD) | a "confiança" passa a significar algo — hoje é o número que a LLM escreve, com padrão 1.0 |
| Latência | ~100 ms típico | cabe no caminho da mensagem sem atrasar a resposta |
| Preço | US$ 0,042 / Mtok de entrada; saída grátis | ver §7 |
| Limites | 1.200 req/min por **conta**, dinâmicos; 64k tokens/req | uma conta para todos os tenants é teto de escala |
| Idioma | inglês principal; demais "com acurácia menor" | **risco nº 1** |
| Não faz | gerar texto, contar, conta, datas, dados com muito lixo | define a fronteira do módulo |
| Modelo | `jev-latest` anda sozinho; `jev-1.13.0` é fixo | fixar a versão; mudar de propósito |
| Dados | não treina com as requisições; ZDR só enterprise | dado de cliente final sai para terceiro → DPA/LGPD |

Padrões da própria doc que usamos no desenho: **speculative fan-out** (perguntar tudo numa
chamada e o código usar só o que interessa), **intent routing**, **confidence-gated
routing** (limiar por risco da ação), **extração por candidatos** (regex acha, Jev escolhe),
**cascata** (extrator barato + Jev verificando + escalar só o que falhar) e **classificação
de passagens de RAG** (relevância / evidência / contradição / injeção por trecho).

---

## 4. Diagnóstico do `ia_engine` atual

| RPC | Hoje | Usa LLM para | Pydantic de structured output | Vai para o Jev? |
|---|---|---|---|---|
| `Analyse` | LLM + schema dinâmico (`build_dynamic_model`) | intenções e entidades | sim | **sim** — núcleo do módulo |
| `Sentimento` | LLM + `AnaliseAvaliacao` | nota 1–5, positivo/negativo, feedback | sim | **sim** (`Score` + `Choice`; o feedback é o próprio texto) |
| `Responder` | LLM + `RespostaBot` + embeddings (score triádico) + regex de transferência | gerar a resposta **e** decidir transferência, setor, confiança e campos extraídos | sim | **em parte**: as decisões sim, a geração não |
| `Embed` | embeddings | vetor do RAG | não | não |
| `Transcribe` | Whisper/API | áudio → texto | não | não |
| `InterpretMedia` | LLM de visão + `MediaAnalysis` | imagem/PDF → texto | sim | não (o Jev só lê texto) |
| `ExtrairTextoDocumento` | leitores locais | arquivo → texto | não | não |

Achados que o estudo trouxe e que valem mesmo sem o Jev:

1. **A análise recebe só os nomes das intenções.** O worker monta `valid_intent_types`
   como `"saudacao,despedida,…"` (`tipos_de_intencao`, `worker/src/main.rs`). A descrição
   e os exemplos que o tenant escreveu para cada intenção — 23 delas, com 120–550
   caracteres de descrição e 100–400 de exemplos — nunca chegam ao modelo. Metade do
   reconhecimento fraco que o relatório de migração viu vem daí.
2. **A confiança da intenção é decorativa.** É um campo que a LLM preenche (padrão 1.0);
   o piso `confianca_minima_automatica` (0,8) decide etiquetas e cadastro em cima de um
   número que não foi calibrado.
3. **Os tipos de entidade chegam sem descrição.** A config guarda um mapa
   `tipo → descrição com exemplos`; o worker lê `entity_types` como lista de nomes.
4. **A análise roda sem histórico** (`historico: Vec::new()`, comentário "por ora").

---

## 5. Desenho das perguntas

Um `state` por mensagem, pequeno de propósito (a doc é enfática sobre contexto com lixo):

```json
{
  "mensagem": "<texto que acabou de chegar>",
  "historico": [ "<até 4 falas anteriores, cliente e atendente, rotuladas>" ],
  "empresa": "<uma linha: o que a empresa faz>"
}
```

Instruções em **inglês** (idioma de treino); opções, descrições e exemplos do tenant em
português, como estão. O conjunto de avaliação (§8) decide se vale traduzir também os
`criteria`.

### 5.1 Intenções — uma chamada, dois tipos de pergunta

- **`intencao_principal` — `Choice`** sobre todas as intenções do tenant + a opção
  `nenhuma`. Cada opção leva `{"what": descricao, "examples": [exemplos]}` — o formato
  contrastivo que a doc recomenda para opções parecidas (e o catálogo da Ecoprint tem
  muitas: `panfletos_grade` × `impressos_comerciais` × `cartazes_promocionais`). Define o
  **assunto** do atendimento. Até ~240 intenções numa pergunta só; acima disso, dois
  estágios por grupo (o cookbook de classificação hierárquica).
- **`intencao::<tag>` — um `Noul` por intenção**: "a mensagem expressa esta intenção?".
  A doc é explícita: quando **várias** podem valer ao mesmo tempo (um cliente que
  cumprimenta e pede orçamento), é um `Noul` por rótulo, não a distribuição da `Choice`.
  Define as **etiquetas**.
- Regras em código, com limiares por risco (confidence-gated routing):
  - assunto só se `confidence ≥ confianca_minima_automatica` e a escolha ≠ `nenhuma`;
  - etiqueta para cada `Noul ≥` o mesmo piso;
  - faixa do meio (ex.: 0,35–0,8) vira "a revisar", não etiqueta — o filtro "A revisar"
    do quadro já existe.

`AnalyseResponse.intents` continua uma lista de `{tipo, confianca}`, agora com
**probabilidade de verdade** no lugar do 1.0 fixo.

### 5.2 Entidades — por tipo de dado, não um método só

| Tipo (Ecoprint) | Como |
|---|---|
| `quantidade_tiragem` | regex acha números com unidade; `Choice` escolhe qual é a tiragem (cookbook de extração por candidatos) |
| `dimensoes` | regex (`10x15`, `A4`, `3x5m`…); `Choice` entre os candidatos |
| `cores_impressao` | regex (`4x0`, `4x4`, `1x0`, `Pantone`) |
| `prazo_desejado` | partes da data com `Choice` (tipo absoluto/relativo, dia, mês, ano) e montagem em código (cookbook de datas) |
| `segmento_producao`, `tipo_produto` | `Choice` fechada — a própria descrição do tipo já lista as opções |
| `acabamento`, `substrato_material` | um `Noul` por opção conhecida (vários podem valer) |
| `formato_arte`, `local_entrega` | valor livre: **presença** por `Noul`; valor por extrator barato (LLM pequena, só quando presente) com um `Noul` de verificação "o valor aparece na mensagem?" (cascata) |

A regra da doc é: o Jev escolhe entre o que o código achou — por isso nunca inventa valor.
O custo disso é código de candidato por tipo. Proposta: o tenant marca, na config do tipo
de entidade, qual estratégia usar (`regex`, `lista`, `data`, `livre`), com a lista de
opções quando houver; o que não for marcado cai em `livre`.

### 5.3 Sentimento (pesquisa de satisfação)

- `nota` — `Score` com 5 níveis descritos ("muito insatisfeito" … "muito satisfeito");
  arredonda em código para 1–5. Se o cliente escreveu o número, o regex vence o modelo.
- `sentimento` — `Choice` `positivo` / `negativo`.
- `feedback` — o próprio texto da mensagem (o Jev não gera; hoje a LLM só "extraía" o
  texto que já estava lá).

### 5.4 Transferência para atendente — decidida pelo Jev, não pela LLM

**Como é hoje** (`resolve_resposta`, `features/responder/domain/usecases.py`). A mesma
chamada de LLM que escreve a resposta também decide se transfere, e a decisão junta quatro
sinais fracos:

| Sinal | O que é | Problema |
|---|---|---|
| `acao_transferencia` | nome do setor que a LLM escreve no *structured output* | texto livre casado por substring com os fluxos; sem casar, cai no **primeiro** fluxo |
| `confianca` | nota de 0 a 1 que a LLM **atribui a si mesma** (padrão 0,5) | não é calibrada — é o número que o modelo acha que deve escrever |
| regex `_TRANSFER_PATTERNS` | procura "vou transferir/encaminhar" no texto gerado | só pega depois de a resposta ser escrita, e só em português com essas palavras |
| score triádico | cosseno entre embeddings de pergunta, resposta e treinamento | mede **parecença de vocabulário**, não se a resposta está certa; resposta que repete a pergunta pontua alto |

Transfere se a LLM pediu, **ou** se o regex achou, **ou** se `score < piso do tenant`
(B4), **ou** se `score < similarity_threshold` **e** `confianca < 0,5`. As regras de
transferência do tenant (`PROMPT_REGRAS_TRANSFERENCIA`) e o comportamento das intenções
("se pedir orçamento, transfira") são texto dentro do prompt: a LLM as lê, e ninguém
consegue dizer depois **por que** transferiu. Foi o que o relatório de migração mostrou:
"Quero falar com o Paulo" não transferiu, e não havia um número para olhar.

**Como fica.** A transferência vira uma **decisão própria**, tomada pelo Jev **antes** de
gerar a resposta e conferida **depois**, com os sinais separados e a regra em código. A LLM
deixa de decidir: só escreve, e só quando não há transferência.

#### Antes de gerar — na mesma requisição da análise (fan-out)

Sobre `{mensagem, historico, fluxos, regras_do_tenant, intencao_do_catalogo}`:

| Pergunta | Primitiva | O que decide |
|---|---|---|
| `pede_humano` | `Noul` | o cliente pede para falar com uma pessoa, com o vendedor ou com alguém pelo nome ("quero falar com o Paulo") |
| `regra::<id>` | `Noul`, **uma por regra do tenant** | cada regra de transferência vira uma condição checável ("pede preço fechado", "quer negociar prazo", "reclama de pedido entregue") |
| `setor` | `Choice` sobre os fluxos disponíveis (`Setor - descrição`) + `nenhum` | para onde vai; substitui o casamento por substring e o "primeiro fluxo" |
| `insatisfacao` | `Score` (calmo → irritado → ameaça cancelar) | escalar cliente muito irritado, se o tenant ligar |
| intenção principal (§5.1) | `Choice` | intenção marcada no catálogo como **"transfere"** transfere, com o setor da própria intenção |

#### Com os trechos do RAG — a base responde isto?

Para cada trecho recuperado, `relevante`, `tem_resposta`, `contradiz_a_pergunta` e
`tenta_instruir_o_modelo` (cookbook de passagens de RAG). Se **nenhum** trecho passa como
evidência e a intenção é de conteúdo (não saudação/despedida), a resposta é a
`msg_sem_info` do tenant **e** a transferência — o mesmo desfecho de hoje, só que decidido
por evidência e não por cosseno. Os trechos aprovados vão para a LLM em blocos separados
de "evidência" e "conflito" (ataca o "inventou couchê" do relatório).

#### Depois de gerar — conferência da resposta

| Pergunta | Primitiva | O que decide |
|---|---|---|
| `resposta_apoiada` | `Noul` | a resposta se sustenta nos trechos aprovados? Substitui o **score triádico** e vira a `confiabilidade` gravada |
| `promete_o_que_nao_pode` | `Noul` | a resposta dá preço, prazo ou desconto que a persona proíbe? |
| `resposta_transfere` | `Noul` | o texto diz ao cliente que vai transferir? Substitui o **regex** (e funciona com qualquer redação) |

#### A regra, em código (limiares por tenant, calibrados no conjunto de avaliação)

```
transferir =
      pede_humano            ≥ limiar_humano           (padrão 0,8)
   ou alguma regra::<id>     ≥ limiar_regra            (padrão 0,8)
   ou intenção "transfere"   com confidence ≥ piso_intencao
   ou insatisfacao           ≥ 1,5                     (só se o tenant ligar)
   ou sem evidência na base  e intenção de conteúdo
   ou resposta_apoiada       < confianca_minima_transferencia   (o B4 de hoje)
   ou promete_o_que_nao_pode ≥ 0,8
   ou resposta_transfere     ≥ 0,8                      (a LLM prometeu; cumpra)

setor = setor da intenção "transfere", senão `setor` se confidence ≥ piso_setor,
        senão o fluxo padrão do departamento (não mais "o primeiro da lista")

faixa de dúvida (ex.: pede_humano entre 0,4 e 0,8) → responde normalmente e marca o
atendimento "a revisar" — não transfere no chute, não ignora
```

Três consequências práticas:

- **A LLM não roda quando vai transferir.** As decisões de antes da geração bastam: o
  cliente recebe a `msg_transferencia` e o cartão vai para o fluxo, em ~100–300 ms e sem
  custo de geração.
- **Toda transferência tem motivo.** O `ResponderResponse` ganha `motivo_transferencia`
  (qual sinal disparou) e os valores de cada sinal. O `testar_pergunta` mostra isso, a
  auditoria grava, e calibrar vira olhar números em vez de reescrever prompt.
- **As regras do tenant viram lista, não prosa.** `PROMPT_REGRAS_TRANSFERENCIA` passa a
  ser uma lista de condições (uma por linha na tela), cada uma um `Noul`. Na migração, as
  regras atuais são quebradas em condições; e o **comportamento** das intenções que manda
  transferir vira a marca "transfere" + setor no catálogo — dá para propor essa marca
  automaticamente perguntando ao próprio Jev, uma vez, se cada `comportamento` manda
  transferir.

`campos_extraidos` (C1) sai da chamada de geração e vai para o mesmo caminho das entidades
(§5.2). Com isso a LLM passa a devolver **só texto**: sem `with_structured_output`, sem
`acao_transferencia`, sem `confianca`.

---

## 6. Pydantic: veredito

| Uso hoje | Destino |
|---|---|
| `build_dynamic_model` (schema dinâmico da análise) | **remove** — o Jev devolve `choice`/`noul` tipados por construção |
| `AnaliseAvaliacao` (sentimento) | **remove** |
| `RespostaBot` (resposta + transferência + confiança + campos) | **remove na J3** — a transferência passa ao Jev e a LLM volta a devolver só texto |
| `MediaAnalysis` (visão) | fica — `InterpretMedia` não muda |
| `IntentItem`, `EntidadeItem`, `IntentsEntidades`, `RespostaFinal` (domínio) | viram `dataclass(frozen=True)`, como os `Parameters` do padrão RSOE — não há nada a validar, só a transportar |
| `config/models.py` (config do Redis) e `pydantic-settings` | fica — é validação de fronteira, onde o pydantic ganha o lugar |
| SDK `typesafe-sdk` | depende de pydantic desde a v0.7.0; `response_model=` aceita um modelo pydantic para tipar as respostas — opcional, útil nos testes |

Conclusão: o pydantic **não sai** do projeto (o SDK o traz), mas sai do **domínio** e de
toda chamada de modelo. A intuição está certa — a "chamada simplificada" existe —, só que
a simplificação é o fim do *structured output*, não o fim da dependência.

---

## 7. Custo e latência (estimativa com o catálogo real)

Por mensagem, uma requisição com: `Choice` de 23 opções com descrição e exemplos
(~3,9 mil tokens), 23 `Noul` de intenção (~3,9 mil), ~10 perguntas de entidade/presença
(~1 mil), `state` (~0,4 mil) → **~9 mil tokens de entrada ≈ US$ 0,0004 por mensagem**
(≈ US$ 0,40 por mil mensagens). Latência ~100–300 ms.

Não é, por si, uma economia grande frente a uma LLM pequena na análise — o ganho é
**qualidade e controle**: confiança calibrada, intenção descrita (não só o nome), nada fora
do catálogo, e latência que permite tirar a LLM do caminho quando a decisão já basta
(transferência, J3). O teto real é o **limite de 1.200 req/min por conta**, que é compartilhado por todos os
tenants — a partir daí, plano enterprise ou fila.

---

## 8. Como validar antes de trocar

1. **Conjunto de avaliação** (`ia_engine_jev/avaliacao/`): mensagens reais do
   `oraculo_mensagem` (anonimizadas), rotuladas com intenção, várias intenções, entidades
   e sentimento. Rótulo inicial pela LLM grande atual + revisão humana das divergências.
   Meta: 300 mensagens, incluindo as 6 perguntas do relatório de migração.
2. **Métricas:** acurácia da intenção principal; precisão/recall por etiqueta; acerto de
   entidade por tipo; **calibração** (a acurácia por faixa de confiança); latência p95;
   tokens por mensagem.
3. **Três variantes** medidas: instruções em inglês + criteria em português; tudo em
   português; tudo em inglês (tradução do catálogo, que é estático e barato de manter).
4. **Modo sombra em produção:** o worker chama o motor atual (que continua valendo) **e**
   o Jev, e grava as duas análises lado a lado por algumas semanas. Troca só quando o
   Jev empatar ou vencer na intenção principal e a calibração se sustentar.
5. **Limiares calibrados** nesse conjunto, por tenant — os da doc são exemplo, não padrão.

---

## 9. Arquitetura do módulo novo e plugagem

### 9.1 Onde mora

**Recomendado:** um serviço Python novo, `ia_engine_jev/`, no mesmo padrão do `ia_engine`
(RSOE: `domain` / `datasources` / `repositories` por feature, erros fechados, `servicer`
por `match`), que **implementa o mesmo contrato gRPC `IaEngineService`**. O worker e o
`runtime_api` já falam com `SMARTCORE_IA_ENGINE_ENDPOINT`: plugar é apontar o endpoint para
o container novo; voltar é apontar de volta. Nada no Rust precisa saber qual motor
respondeu.

- As features que **não** mudam (`Embed`, `Transcribe`, `InterpretMedia`,
  `ExtrairTextoDocumento` e a geração do `Responder`) entram por **cópia** na primeira
  versão — o objetivo é poder desligar o `ia_engine` antigo inteiro depois. Na fase final,
  o `ia_engine` antigo sai do repositório; não fica código duplicado para sempre.
- Alternativa considerada: uma feature nova dentro do `ia_engine` atual com chave por
  tenant (`motor_analise = llm | jev`). Menos código, mas mistura dois motores no mesmo
  serviço e não é o "módulo plugado no lugar" pedido. Fica como plano B se o modo sombra
  mostrar que só a análise vale a troca.

### 9.2 Estrutura

```
ia_engine_jev/
  src/ia_engine_jev/
    typesafe/            # cliente (AsyncTypeSafeClient), RetryPolicy, erros → domínio
    perguntas/           # funções PURAS que montam state e questions (100% testáveis)
      intencoes.py  entidades.py  sentimento.py  transferencia.py  rag.py
    candidatos/          # regex e listas por tipo de entidade (dimensões, tiragem, cores…)
    features/
      analyse/  sentimento/  responder/  embed/  transcribe/  interpret_media/  extrair_texto/
    servicer.py  server.py  config/  telemetry.py
  avaliacao/             # conjunto rotulado + script de métricas (roda na CI, não na máquina local)
  tests/
```

Regra do módulo: **perguntas e composição são funções puras** (entrada → `dict` de
perguntas; respostas → domínio), testadas sem rede com respostas gravadas; só o
`datasource` fala com a TypeSafe.

### 9.3 Mudanças de contrato e config

- `ai_engine.proto` — `AnalyseRequest` ganha `repeated IntentDef intents = 7`
  (`tag`, `grupo`, `descricao`, `exemplo`) e `repeated EntidadeDef entidades = 8`
  (`tipo`, `descricao`, `estrategia`, `opcoes`), sem `map` (o conversor proto→flatbuffers
  não aceita). Os campos antigos continuam, para o `ia_engine` atual seguir funcionando
  durante o modo sombra. `AnalyseResponse` ganha `intent_principal`, `confianca_principal`
  e `modelo` (versão que respondeu, para auditoria).
- Worker: manda as intenções completas (o `ListIntents` já devolve descrição e exemplo) e
  as últimas falas no `historico`; no modo sombra, grava as duas análises.
- Config do tenant: `typesafe_api_key` no mesmo cofre das outras chaves (cifrada, decifrada
  pelo Rust e publicada no Redis); `motor_analise` (`llm` | `jev` | `sombra`);
  `jev_modelo` (padrão `jev-1.13.0`); estratégia por tipo de entidade.
- `ResponderResponse` ganha `motivo_transferencia` e os sinais da decisão (`pede_humano`,
  regras disparadas, `setor` + confiança, `resposta_apoiada`); a `confiabilidade` passa a
  ser a `resposta_apoiada`. Aditivo: o worker atual ignora os campos novos.
- Catálogo de intenções: `acao` (`responder` | `transferir`) e `fluxo_destino`.
- Config do tenant: `regras_transferencia` como lista de condições (substitui o prompt em
  prosa) e os limiares `limiar_humano`, `limiar_regra`, `piso_setor`, `escalar_insatisfacao`.

### 9.4 Falhas

Best-effort como hoje: a TypeSafe fora (timeout, 429 além do retry, 5xx) → a mensagem
segue **sem análise** (o comportamento atual quando o `Analyse` falha), com métrica e log
sem conteúdo. Orçamento de retry total curto (`RetryPolicy(timeout=2s)`), porque a análise
está no caminho da conversa. No `Responder`, falha do Jev → volta ao caminho atual (LLM
decide), nunca deixa o cliente sem resposta.

---

## 10. Riscos

| Risco | Mitigação |
|---|---|
| Português com acurácia menor | conjunto de avaliação + variantes de idioma + modo sombra; só troca com números |
| Entidade de valor livre | candidatos por regex/lista; LLM pequena só para `livre`, verificada |
| Limite de 1.200 req/min por conta, dinâmico | uma requisição por mensagem (fan-out); métrica de 429; plano enterprise antes de escalar |
| Alias mudando a resposta | fixar `jev-1.13.0`; troca de versão = rodar a avaliação de novo |
| Mensagem do cliente sai para terceiro | DPA; campo no termo do tenant; ZDR se for exigência; nada de PII em log |
| Mensagem adversarial ("ignore as instruções…") | mensagem do cliente é dado; `Noul` de injeção no RAG; nada é executado a partir da análise |
| Dependência de um fornecedor novo | contrato gRPC igual → volta ao `ia_engine` atual trocando o endpoint |

---

## 11. Plano proposto (fases com critério de aceite)

| Fase | Entrega | Aceite |
|---|---|---|
| **J0 — Avaliação** | conjunto rotulado (300 msgs, com casos de transferência: pedido de humano, regra do tenant, sem resposta na base, cliente irritado), script de métricas, rodada das 3 variantes de idioma | relatório com acurácia, calibração, latência e custo; decisão go/no-go |
| **J1 — Esqueleto** | `ia_engine_jev` com o contrato gRPC completo; features inalteradas copiadas; `Analyse` e `Sentimento` pelo Jev; testes das funções de pergunta | CI verde; `Analyse` responde com intenção principal + multi-intenção + confiança real |
| **J2 — Contrato e modo sombra** | proto com `IntentDef`/`EntidadeDef` e os campos de motivo da transferência; worker mandando intenções completas e histórico; `motor_analise = sombra` gravando as duas análises **e as duas decisões de transferência** | 2–3 semanas de sombra num tenant; Jev ≥ atual na intenção principal |
| **J3 — Transferência pelo Jev** | decisão antes da geração (`pede_humano`, regras, `setor`, intenção "transfere"); filtro dos trechos do RAG; conferência depois (`resposta_apoiada`, `promete_o_que_nao_pode`, `resposta_transfere`); LLM só escreve; regras do tenant como lista; marca "transfere" no catálogo; motivo no `testar_pergunta` e na auditoria | as 6 perguntas do relatório com a transferência certa (incl. "quero falar com o Paulo"); nenhuma transferência sem motivo registrado; sombra mostra menos transferências indevidas que o motor atual |
| **J4 — Entidades** | candidatos por tipo (regex, lista, data), estratégia por tipo na config, cascata para `livre`, `campos_extraidos` pelo mesmo caminho | acerto por tipo medido no conjunto; nenhum valor fora do texto |
| **J5 — Troca** | `SMARTCORE_IA_ENGINE_ENDPOINT` → `ia_engine_jev` por tenant; depois para todos | uma semana sem regressão; `ia_engine` antigo removido do repositório |

A transferência sobe para antes das entidades: é a decisão com mais efeito na conversa
(um cliente preso no bot, ou um vendedor recebendo o que o bot resolveria) e a que mais
ganha com sinais separados e auditáveis. J0 continua barato e decide tudo.

---

## 12. Decisões que precisam do dono do produto

1. **Conta TypeSafe:** uma conta da plataforma para todos os tenants (mais simples, teto
   de 1.200 req/min compartilhado) ou chave por tenant (cada um com seu limite e sua conta)?
2. **Dados de cliente para terceiro:** ok enviar o texto das mensagens à TypeSafe (sem ZDR
   no plano comum)? Precisa entrar no termo do tenant?
3. **Módulo separado (recomendado) ou feature dentro do `ia_engine` atual?**
4. **Entidades de valor livre:** aceitar uma LLM pequena só para elas, ou deixar esses tipos
   sem extração automática até existir candidato?
5. **Começar pela J0 (avaliação) antes de escrever o serviço?** Recomendado.
6. **Quais sinais transferem por padrão?** Proposta: pedido de humano, regras do tenant,
   intenção marcada "transfere", sem resposta na base e resposta não apoiada; cliente
   irritado **desligado** até haver dado para calibrar.
7. **Faixa de dúvida:** responder e marcar "a revisar" (proposto) ou transferir por
   precaução?
