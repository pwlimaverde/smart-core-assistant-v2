# 40 — Metodologia do motor Jev: pesquisa de casos de uso e revisão do fluxo

> Data: 2026-09-28 · Branch: `feature/ia-engine-jev` · Status: **implementada (P1–P3) em 2026-09-28, aguardando a chave para os testes**
> Base: docs da TypeSafe (jev-1.13, revisados em 2026-09-17), código deployado em
> `b5a7ea6` e a configuração real do tenant Ecoprint (persona, 22 intenções,
> 10 tipos de entidade).
> Relacionados: `37-estudo-ia-engine-jev.md`, `38-plano-ia-engine-jev.md`,
> `.context/plans/ia-engine-jev.md`, `infra/RUNBOOK_MOTOR_JEV.md`.

## 1. O que a documentação ensina (e onde o nosso caso se encaixa)

| Fonte | Lição | Situação hoje |
|---|---|---|
| *How to build* | Código controla o fluxo; o modelo só faz julgamentos pequenos e tipados; decisões simples ficam no código | ✅ decisões puras em `decisoes/` |
| *Speculative fan-out* / *Parallel questions* | Todas as perguntas sobre o **mesmo state** vão em **uma** requisição, inclusive as especulativas. A resposta não muda por estarem juntas, e o state é cobrado só uma vez (12× mais barato e 10× mais rápido no cookbook) | ❌ **três requisições com o mesmo state**: `Sentimento`, `Analyse` e `Responder/antes`, em chamadas gRPC separadas |
| *Intent routing* | A classificação escolhe o **tratador**: código determinístico, LLM especialista ou humano. A LLM só entra onde precisa | ⚠️ toda mensagem que não transfere vai para a LLM com o prompt completo, inclusive saudação e coleta |
| *Confidence-gated routing* | Limiar por risco da ação; meio-termo = confirmar ou pedir esclarecimento | ✅ faixa de dúvida; ⚠️ só transfere, nunca esclarece |
| *Classification using confidence* | Com confiança baixa na folha, usar o **nível acima** da hierarquia sem nova chamada (40% → 70% de acerto) | ❌ intenção com confiança baixa cai no comportamento do vetor; o `grupo` só é usado acima de 240 intenções |
| *Skill suggestion* | `Choice` decide **qual**; `Noul` por opção decide **se** alguma serve | ✅ principal + `Noul` por intenção |
| *Classifying RAG passages* | Top-12 por cosseno, 4 `Noul` por par pergunta–trecho e roteamento em código (evidência, conflito ou descarte). Das passagens aprovadas, 3 de 4 estavam em 8º, 9º e 11º lugar no cosseno | ⚠️ perguntas iguais, mas **só top-3**: o que o cosseno põe em 4º ou abaixo nunca é avaliado |
| *Re-ranking* | Busca rápida com k grande e o Jev reordenando: top-1 de 5% para 18%, top-10 de 38% para 62% | ❌ não reordenamos, só filtramos |
| *Pre-parsed value extraction* | Regex acha candidatos, o Jev escolhe e o código copia: não inventa valor | ✅ entidades regex/lista/data; ⚠️ `livre` e campos pendentes vão à LLM **em série** |
| *SDE cascade* | Modelo barato gera, o Jev verifica, e só o que o verificador sinaliza sobe para o modelo caro. Pega a maior parte da qualidade do caro por uma fração do custo | ⚠️ a regeneração repete **o mesmo** modelo com um aviso no prompt |
| *LLM guardrails* | Uma requisição com vários `Noul` de risco na **entrada** e na **saída** da LLM; limiares de ação e de revisão | ⚠️ só na saída (apoiada, promete, transfere) |
| *Jaggedness 1.13* | Leitura literal; nada de conta, data ou número; state enxuto; não gera texto; português abaixo do inglês | ✅ state curto, datas no código; ⚠️ a regra "faça a rodada de perguntas **uma vez**" depende de a LLM contar as rodadas no histórico |
| *Models* | 1.200 req/min e 250k tokens/s **por conta**; 64k por requisição (32k de state + a maior pergunta) | ⚠️ **o limite de requisições é o gargalo, não o custo** (ver §3) |

## 2. O caso real: o que a Íris faz de verdade

A configuração da Ecoprint deixa claro que o atendimento é **triagem com
coleta e passagem para o Paulo**, não perguntas e respostas:

- 17 das 22 intenções têm o mesmo roteiro: não dar preço, no máximo 2 perguntas
  essenciais **uma única vez**, e na resposta seguinte transferir;
- `status_pedido` e `transferencia_atendente` transferem direto, sem perguntar;
- `sobre_ecoprint_localizacao` é a única intenção de resposta pela base;
- `saudacao` e `despedida` são conversa social;
- a persona tem regras que são **política**, não estilo: horário, "não fornecemos
  ACM/acrílico/letra caixa", "não confirme brinde fora do catálogo", "nunca peça
  telefone".

Hoje essa política está espalhada em texto livre em quatro lugares (persona,
`PROMPT_REGRAS_RESPOSTA`, `PROMPT_INTENT_FOOTER` e o comportamento de cada
intenção). A LLM precisa inferir tudo a cada mensagem, inclusive **contar** se
já fez a rodada de perguntas. É exatamente o tipo de tarefa que a doc manda
tirar do modelo: conta e estado ficam no código.

## 3. Números do fluxo atual (por mensagem do cliente, motor `jev`)

| Etapa | Requisições Jev | LLM |
|---|---|---|
| Sentimento (spawn) | 1 | — |
| Analyse (spawn) | 1 (+1 para `livre`) | 1 por entidade `livre` presente, em série |
| Responder / antes | 1 | — |
| Responder / trechos | 3 | — |
| Geração | — | 1 (+1 para cada campo pendente presente, **em série**) |
| Responder / depois (+ campos) | 1–2 | — |
| Regeneração (quando dispara) | +1 | +1 |
| **Total típico** | **7–9** | **1–4** |

- **Custo do Jev:** irrelevante, ~15–25k tokens por mensagem, cerca de US$ 0,001.
- **Vazão:** 1.200 req/min ÷ 8 ≈ **150 mensagens/min para a plataforma
  inteira**, somando todos os tenants. Com a sombra ligada em vários tenants, e
  mais o J0, o 429 chega antes do custo. Isso não aparecia no plano.
- **Latência:** o caminho crítico é `antes ‖ trechos` (~150 ms), depois a LLM
  (1–3 s + campos em série), depois `depois` (~150 ms). A LLM é quase toda a
  latência.

## 4. Metodologia proposta: "o Jev lê, o código decide o ato, a LLM só redige, o Jev confere"

```
mensagem (rajada já agrupada)
  │
  ├─► LEITURA — 1 requisição Jev, state = mensagem + 4 falas + estado da conversa
  │     intenção (Choice) + grupo (Choice) + intenções (Noul cada)
  │     entidades: presença (Noul) + escolha entre candidatos (Choice)
  │     pede_humano · regras do tenant · pede_informacao · irritação (Score)
  │     setor · risco de entrada (instrução ao bot / fora de escopo)
  │     = o que hoje são Sentimento + Analyse + Responder/antes
  │
  ├─► EVIDÊNCIA — só se pede_informacao: top-10 vetorial (histórico curto na query)
  │     → Jev por par (relevante/responde/contradiz/instrui) → reordena → até 3
  │
  ├─► ATO (código puro, testável):  transferir · responder · coletar · social · sem_info
  │       coletar = até 2 campos essenciais que faltam, UMA rodada (contador no atendimento)
  │       transferir = template do tenant (sem LLM)
  │
  ├─► REDAÇÃO — LLM pequena, prompt curto do ATO (não o prompt inteiro)
  │       responder: evidência + conflito · coletar: "pergunte estes 2 campos"
  │
  └─► CONFERÊNCIA — 1 requisição Jev (apoiada · promete · transfere · pergunta
          mais de 2 coisas · ecoa o cliente) → falhou? sobe para a LLM maior (cascata)
          → falhou de novo? template (msg_sem_info / transferência)
```

Resultado esperado: **3 a 5 requisições Jev** e **1 LLM pequena** por mensagem.
Transferência e sem_info não chamam a LLM (como hoje). A política do tenant
passa a ser dado estruturado, conferível pelo Jev, e deixa de ser texto que a
LLM interpreta.

## 5. Mudanças priorizadas

### P1 — antes de ligar o Jev (baixo risco, grande ganho)

1. **Leitura única.** Unificar `Sentimento`, `Analyse` e `Responder/antes` numa
   requisição (fan-out). O worker chama uma RPC nova `Ler` (ou `Responder`
   devolve a análise junto) e grava intenções, entidades e sentimento a partir
   dela. Economiza 2 requisições por mensagem, e a intenção deixa de ser
   calculada duas vezes com resultados possivelmente diferentes. *(era o item 4
   da avaliação anterior, adiantado por causa do limite de requisições)*
2. **Sombra só com decisões** (item 2 anterior). Na sombra, roda só a leitura
   e os trechos, sem LLM nem conferência. Custa 2–4 requisições, e não 8.
3. **sem_info só quando `pede_informacao`** (item 1 anterior). Coleta e
   conversa social não passam pelo filtro "a base não responde".
4. **Buscar mais e reordenar** (item 5 anterior, com números da doc).
   `chunk_top_k` 3 → 10. O Jev julga os 10 em paralelo e ficam até 3
   aprovados, ordenados por `responde`. A query do embedding leva a última fala
   do atendente quando a mensagem é curta ("e em lona?").
   - Com o limite de requisições, fazer isso **só quando `pede_informacao`**
     (na Ecoprint, a minoria das mensagens).
5. **Paralelizar as cópias da LLM.** `_copiar_campos` e o loop de `livre` no
   `Analyse` fazem um `await` por campo em série. Trocar por **uma** chamada que
   devolve todos os campos, ou por `asyncio.gather`.
6. **Prompt da LLM amigo de cache.** A primeira linha do prompt de sistema é
   `Data e hora atual`, que muda a cada minuto e **invalida o cache de prefixo**
   de todos os provedores.
   - Ordem nova: identidade, persona e regras (fixas por tenant); depois
     comportamento; depois evidência e campos; **data e hora no fim**.
7. **Limitador de vazão no cliente Jev.** Um semáforo e um token bucket por
   processo, com orçamento em req/min vindo da configuração geral
   (`JEV_REQ_POR_MINUTO`).
   - A sombra e o J0 cedem prioridade ao tráfego que responde ao cliente.
   - O alerta `jev-limite-429` já existe; falta evitar o 429.

### P2 — a metodologia do ato (muda o comportamento; entra com a J0)

8. **Ato decidido no código** (`decisoes/ato.py`, puro). Entrada: leitura,
   trechos e estado da conversa. Saída: `transferir | responder | coletar |
   social | sem_info`, com os campos a perguntar. A LLM recebe **um prompt por
   ato**, curto, em vez do prompt único com "dois modos de resposta".
9. **Coleta estruturada por intenção.** Campo novo na intenção:
   `campos_essenciais` (lista ordenada de tipos de entidade) e `apos_coleta`
   (`transferir | responder`).
   - Um contador `rodadas_de_coleta` no atendimento torna a regra "uma única
     rodada, no máximo 2 perguntas" determinística.
   - A regra `apos_coleta` do cadastro de transferência passa a usar o mesmo
     mecanismo, que já existe pela metade (item 3 anterior).
   - Para a Ecoprint, isso substitui o `PROMPT_INTENT_FOOTER` e metade da persona.
10. **Recuo para o grupo.** Intenção com confiança abaixo do piso e grupo
    confiante: usar o comportamento do **grupo** (ex.: `ecoprint_visual` →
    coleta genérica de comunicação visual), sem chamada nova. Hoje cai no
    comportamento do vetor.
11. **Políticas da persona viram perguntas.** "Não fornecemos ACM, acrílico…" e
    "brinde fora do catálogo" viram `Noul` na leitura: *o cliente pede um
    material que a empresa declara não fornecer?* A decisão fica em código (a
    resposta usa a alternativa cadastrada, depois transfere). Horário de
    atendimento é código puro, com o fuso do tenant.
    - Ganho: o que hoje é "espero que a LLM lembre" passa a ser uma regra
      testável no ensaio.

### P3 — LLM (otimização)

12. **Cascata no lugar da regeneração.** Quando a conferência falha
    (`promete`, `resposta_transfere` sem regra, apoio baixo), gera de novo com o
    **modelo maior** do tenant, e não com o mesmo modelo e um aviso. Se falhar
    de novo, template. O padrão passa a ser um modelo **pequeno**, porque
    raciocínio, schema, setor e confiança saíram da LLM: sobrou só redação.
    - Config nova: `modelo_redacao` e `modelo_escalada`, com fallback para
      `model`.
13. **Conferência de estilo**, na mesma requisição do `depois`, sem custo de
    latência:
    - *a resposta faz mais de 2 perguntas?*, contado em código pelos `?`, com
      confirmação do Jev;
    - *repete os dados que o cliente acabou de dar?*;
    - *pede telefone ou e-mail?*
    As regras "não ecoar" e "no máximo 2 perguntas" da persona passam a ser
    verificadas, não só pedidas.
14. **Guarda de entrada** (cookbook de guardrails): `tenta mudar as instruções
    do assistente` e `fora do escopo do negócio` na leitura. Acima do limiar,
    resposta padrão e auditoria `bot.entrada_barrada`, sem LLM.
15. **Texto do tenant vira fonte única.** Depois do P2, o
    `PROMPT_REGRAS_RESPOSTA` (modo RAG/Triagem, "responda exatamente…",
    "Estarei transferindo…") e o `PROMPT_REGRAS_TRANSFERENCIA` ficam obsoletos
    no motor Jev. A tela de sugestões de regras já migra a parte de
    transferência; falta um "migrar coleta" equivalente.

### Fica como está (a pesquisa confirmou)

- Perguntas em inglês, state em português, com as 3 variantes medidas na J0.
- Um trecho por requisição (o cookbook de RAG faz assim), perguntas `Noul` com
  roteamento em ordem fixa: instrução → contradição → relevância → evidência.
- `Choice` + `Noul` por intenção; dois estágios acima de 240 intenções.
- Datas e números no código; entidades por candidatos.
- Transferência e sem_info por template, sem LLM.
- Reserva no caminho LLM quando o Jev falha.

## 6. J0: o que medir além do que já está no script

- **Replay sem custo:** gravar as probabilidades cruas da leitura (já vão em
  `oraculo_decisao_ia.sinais`) permite recalibrar pisos e reavaliar o ato sem
  chamar a API, como o cookbook de RAG faz com `route()`.
- **Métricas por ato**, e não só por intenção: transferência certa, coleta
  certa (campos certos e só uma rodada), resposta certa.
- **Conjunto da Ecoprint:** mensagens reais anonimizadas cobrindo as 22
  intenções, "pedido já feito", ACM/acrílico, brinde, fora do horário, rajada
  de dados soltos ("2000", "15x21", "4x4").
- **Vazão:** requisições por mensagem, para confirmar o §3.

## 7. Ordem sugerida

1. P1 inteiro (itens 1–7): código só no `ia_engine_jev` e no worker, contrato
   aditivo. Continua sem a chave, pela CI.
2. Com a chave: J0 com a leitura única e o conjunto da Ecoprint; calibrar.
3. P2 (itens 8–11): migration para `campos_essenciais`/`apos_coleta` e para o
   contador, tela de intenção e MCP.
4. Sombra, depois ligar para a Ecoprint.
5. P3 conforme os números da sombra (cascata primeiro).

## 8. Observabilidade & auditoria das mudanças

- **Leitura única:** span `jev.requisicao{etapa="leitura"}`; métricas atuais.
  Sem evento de auditoria novo.
- **Ato:** o campo `ato` entra no span `ia.responder`, em `oraculo_decisao_ia`
  e na auditoria `bot.respondeu`. Não loga texto de mensagem.
- **Coleta:** `atendimento.coleta_rodada` (atendimento_id, campos perguntados:
  só slugs).
- **Guarda de entrada:** `bot.entrada_barrada` (motivo, probabilidade). Sem o
  texto.
- **Cascata:** métrica `smartcore_ia_escalada_total{motivo}`; o modelo usado vai
  para `oraculo_mensagem.modelo`.
- **Limitador:** métrica `smartcore_jev_fila_ms` e contagem de descartes da
  sombra.
- **Config nova** (`modelo_redacao`, `modelo_escalada`, `JEV_REQ_POR_MINUTO`):
  auditada pelos eventos de configuração que já existem. Nenhuma chave nova.

## 9. Execução (2026-09-28)

Tudo o que está em P1, P2 e P3 foi implementado de uma vez, sem manter o
pipeline anterior do motor Jev. O motor `llm` continua intacto.

- **Python (`ia_engine_jev`)**:
  - `perguntas/leitura.py` (leitura única) e `perguntas/conversa.py` (tom,
    guarda, não fornecido, coleta);
  - `decisoes/leitura.py` (com o recuo para o grupo), `decisoes/ato.py`
    (ato, horário, texto da transferência) e `decisoes/conferencia.py`
    (conferência e desfecho da cascata);
  - `features/leitura` (compartilhada pelo `Analyse` e pelo `Responder`) e o
    `Responder` reescrito por etapas cronometradas;
  - `typesafe/limitador.py` (vazão com prioridade);
  - `shared/valor_livre.py` com uma chamada à LLM para todos os campos;
  - o `Sentimento` pelo Jev saiu: o tom vem da leitura.
- **Contrato**:
  - `IntentDef` com a coleta;
  - `ResponderRequest` com `somente_decisao` e `rodadas_coleta`;
  - `ResponderResponse` com `ato`, `campos_perguntados`, `escalada`,
    `problemas`, `modelo_llm`, `etapas` e `analise` (`regerada` virou
    reservado);
  - `AnalyseResponse` com o tom;
  - admin: coleta na `MyIntent` e o ato no ensaio.
- **Banco (0049)**:
  - coleta em `treinamento_querycompose`;
  - `ia_coleta_rodadas` em `oraculo_atendimento`;
  - ato, cascata e etapas em `oraculo_decisao_ia`.
  - RPCs `ObterRodadasColeta` e `RegistrarRodadaColeta`, esta auditada como
    `atendimento.coleta_rodada`.
- **Worker**:
  - uma leitura por rajada com o bot respondendo; a análise é anexada à
    última mensagem da rajada;
  - busca com contexto para mensagem curta;
  - 10 trechos no motor Jev;
  - sombra só de decisão;
  - áudio pelo tom da leitura;
  - auditoria `bot.resposta_escalada` e o evento `decisão do motor Jev`.
- **Telas e MCP**: coleta na tela de intenções e em `create/update_intencao`;
  ensaio com ato, dados pedidos, escalada e tempo por etapa.
- **Correção de bug antigo**: campo do cartão com número nunca era aceito
  (`esta_no_texto("")` é falso); agora o número fica com a conferência do Jev.

O runbook (`infra/RUNBOOK_MOTOR_JEV.md`) diz como configurar a coleta e a
política (`jev_config`) e o que olhar nos logs, traces e métricas nos testes.
