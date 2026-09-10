# 30 — Fluxo de atendimento ponta a ponta: v1 × v2

> Análise dos dois fluxos completos, do webhook ao encerramento, para descobrir
> o que a v2 herdou, o que melhorou e o que **ficou pelo caminho sem ninguém
> notar**. Levantado em 2026-09-06.
>
> **Fontes da v1:** `docs_dev/diagramas/oraculo/` (o fluxo documentado),
> `attendance_orchestrator.py` (1583 linhas — o coração), `bot_rules_engine.py`,
> `message_analyzer.py`, `attendance_structure_manager.py` e os models.
> **Fontes da v2:** `worker/src/main.rs`, `data_postgres`, schema em execução.
>
> Complementa o doc [29](./29-mapeamento-lacunas-v1-v2-usuarios-e-config.md),
> que cobriu usuários, permissões e configuração.

---

## 1. O fluxo da v1, como documentado e implementado

```
mensagem WhatsApp
  → normaliza telefone (+55)
  → converte mídia em texto (áudio, imagem, vídeo, documento)
  → acha/cria contato e cliente
  → atendimento ativo? não: cria (EM_ANDAMENTO) | sim: continua (mantém contexto)
  → BOT PODE RESPONDER?
       AppInstance.resposta_bot  → desliga o bot da instância inteira
       Atendimento.bot_pode_atender → desliga o bot desta conversa
       houve mensagem de ATENDENTE_HUMANO → bloqueia o bot PERMANENTEMENTE
  → classifica INTENT: pergunta × expressão de satisfação
       satisfação → encerra o atendimento
       pergunta   → gera resposta com IA e mede CONFIANÇA (0–1)
            < 0.5  → transfere para humano
            0.5–0.8 → responde, marcado como "requer revisão"
            ≥ 0.8  → responde automaticamente
  → enriquece: preenche assunto automaticamente, sincroniza tags do intent
  → transferência: busca atendente disponível com round-robin
       (data_ultima_atribuicao, max_atendimentos_simultaneos, disponivel)
  → notifica o atendente
  → aguarda; timeout de inatividade (30 min, configurável) encerra
  → encerramento: mensagem final + pesquisa de satisfação → RESOLVIDO
```

## 2. O que a v2 herdou e **melhorou**

O schema da v2 é mais rico em quase toda a cadeia. Não é regressão — é avanço:

| Entidade | v1 | v2 acrescenta |
|---|---|---|
| `Atendimento` | 12 campos | `departamento_id`, `fluxo_atendimento_id`, `etapa_atual_id`, `atendente_humano_id`, `historico_status`, `data_primeira_resposta`, `sentimento_nota`, `sentimento_label`, `feedback_solicitado_em`, `feedback_expirado_em` |
| `Mensagem` | 18 campos | `intent_detectado`, `entidades_extraidas`, `data_entregue`, `data_lida`, `gerado_por_ia`, `mimetype_midia`, `nome_arquivo_midia`, `tamanho_midia`, `midia_purgada_em` |
| Config do tenant | 12 campos | 33 (prompts, RAG, visão, marca, fuso, idioma, pesquisa de satisfação) |
| Convite | sem revogação | `revoked`, `revoked_at` |
| Estrutura | — | Kanban com fluxos e etapas, campos personalizados, etiquetas, notas |

A v2 também tem o que a v1 não tinha: **RLS por tenant**, auditoria, quotas por
plano, buffer de agregação por contato, outbox, e o motor local offline.

## 3. Lacunas do fluxo — o que **não** foi portado

### F1 — Faixas de confiança não decidem nada 🔴

A v1 fazia da confiança o **eixo da automação**: `< 0.5` transferia para humano,
`0.5–0.8` respondia marcando revisão, `≥ 0.8` respondia direto.

> ⚠️ **Corrigido em 2026-09-06.** A primeira versão dizia que a v2 *grava* a
> confiança sem ler. **É pior:** ela não grava. Ver a auditoria no doc
> [00-0609](./00-0609-analise_critica_old_vs_v2.md#6-auditoria-deste-relatório-2026-09-06).

O que o código faz de fato:

- `responder_via_ia` (`worker/src/main.rs:543`) retorna **apenas**
  `resposta.resposta_texto`. O `confiabilidade` que vem do `ia_engine` é
  descartado na mesma linha — a palavra não aparece nenhuma vez em
  `worker/src/main.rs`;
- `registrar_resposta_bot`, único `UPDATE` que preenche `confianca_resposta`
  (`mensagens.rs:357`), é chamado **só por um teste de integração**
  (`tests/atendimentos/mod.rs:161`). Nenhum caminho de produção o invoca;
- portanto `oraculo_mensagem.confianca_resposta` é **sempre nulo** em produção —
  e `resposta_bot`/`respondida` não são preenchidos por esse caminho.

**Mas a decisão não ficou órfã — ela mudou de dono.** A v2 moveu o transbordo
para dentro do LLM: o `ia_engine` devolve `transferir_atendimento` +
`fluxo_transferencia`, e `aplicar_transferencia_ia` (N6.3, `main.rs:222`)
executa a transferência com auditoria. O código chama isso de *"safety-net de
transferência"*.

**Consequência:** quem decide o transbordo hoje é a **auto-avaliação do
modelo**, não um número calibrável. Não há piso: se o LLM disser "sei
responder" com 0.2 de confiança, ninguém contesta — e não fica registro do
quanto ele sabia, porque o campo nunca é escrito. É um sistema sem termômetro e
sem histórico para calibrar.

### F2 — Sem desligar o bot por instância 🔴

Detalhado no doc 29 (L7). A v1 tinha três níveis; a v2 tem dois:

| Nível | v1 | v2 |
|---|---|---|
| Instância inteira | `AppInstance.resposta_bot` + toggle na tela | ❌ **não existe** |
| Conversa | `Atendimento.bot_pode_atender` | ✅ existe no banco e é respeitado no worker |
| Após intervenção humana | bloqueio permanente | ✅ `atendente_humano_id.is_some()` |

**Consequência:** não há como calar a IA de um número inteiro.

**Confirmado (2026-09-06):** o `bot_pode_atender` **não tem controle nenhum na
interface** — `bot_pode_atender`/`botPodeAtender` não aparece em um único arquivo
Dart do repositório. E o interruptor é **de mão única**:

- `assumir_atendimento` grava `bot_pode_atender = false`
  (`atendimentos.rs:461`) — a v2 **silencia** o bot ao assumir, como a v1;
- `desatribuir` **não** religa, por decisão documentada no trait
  (`atendimentos.rs:148`);
- **não existe nenhum `UPDATE` que devolva o valor para `true`** em todo o
  servidor.

Ou seja: uma conversa que passou por um humano fica sem bot para sempre, e não
há tela para reverter. Na v1 o mesmo bloqueio existia, mas o `resposta_bot` da
instância dava a saída pela porta de cima.

### F3 — Sem atribuição automática com balanceamento 🟡

A v1 buscava atendente disponível respeitando `max_atendimentos_simultaneos`,
`disponivel` e `data_ultima_atribuicao` (round-robin, comentado no código como
*"fairness"*).

Na v2 os três campos **existem** em `oraculo_atendente`, e há
`atualizar_ultima_atribuicao` no repositório — mas a atribuição só acontece
quando **alguém arrasta o cartão** no Kanban (`assumir_atendimento`, em
`atendimento.rs:905`). Não há distribuição automática ao transferir.

**Consequência:** a fila não se distribui sozinha; depende de alguém puxar.
A infraestrutura para automatizar já está pronta e ociosa.

### F4 — Sem enriquecimento automático do atendimento 🟡

A v1 tinha `_auto_fill_subject` (assunto a partir da conversa) e
`_sync_intent_tags` (tags derivadas do intent). Nenhum equivalente aparece no
worker da v2 — os campos `assunto`, `tags` e `intent_detectado` existem e ficam
por conta de preenchimento manual.

**Consequência:** o quadro nasce com cartões sem assunto e sem etiqueta, o que
piora a triagem justamente na tela em que ela acontece.

### F5 — Departamento não vem da instância 🟡

A v1 tinha `_configure_department_from_app_instance`: a instância de WhatsApp
carregava o departamento, e todo atendimento nascia roteado. Na v2 não há
equivalente — `whatsapp_instance` sequer tem `departamento_id`.

**Consequência:** com mais de um número (o plano Básico permite 3), não há como
dizer "o número do suporte cai no departamento de suporte".

### F6 — Timeout de inatividade 🟡 **confirmado ausente**

A v1 encerrava atendimento parado (30 min, configurável). O scheduler da v2 tem
exatamente quatro rotinas — `processar_feedback_vencido`,
`processar_midia_expirada`, `processar_vetorizacao_pendente`,
`processar_intents_sem_embedding` — mais a `reconciliar_conexoes_whatsapp`
acrescentada nesta sessão. **Nenhuma encerra atendimento por inatividade.**

Atenção à armadilha de nome: `feedback_timeout` / `feedback_expirado_em` são da
**pesquisa de satisfação**, não do abandono da conversa. A fila acumula conversas
mortas indefinidamente.

### F7 — Notificação ao atendente 🔴 **confirmado ausente**

A v1 notificava o atendente da transferência, *"repetida até resposta"*.

Na v2 o realtime é **difusão por tenant, sem destinatário**:

- o canal é `tenant:{tenant_id}:events` (`worker/src/main.rs:896`,
  `realtime.rs:60`) — um só para toda a empresa;
- `AtendimentoEvent` (`admin.proto:1289`) tem três campos: `event_type`,
  `tenant_id`, `payload`. **Não há campo de destinatário**;
- os tipos realmente publicados são `whatsapp.conexao`, `whatsapp.presenca`,
  `kanban.movido`, `mensagem.recebida`, `mensagem.enviada`,
  `mensagem.status_atualizado`. **Não existe evento de atribuição de
  atendimento** — nem `atendimento.atribuido`, nem `atendimento.transferido`.

**Consequência:** ninguém é avisado de que um atendimento é seu. No máximo o
cartão se move no quadro de todo mundo — e no desktop nem isso (F8).

### F8 — Realtime não chega ao desktop 🔴

Já diagnosticado nesta sessão: o `LocalEngineGateway` emite **apenas mutações
locais**; o comentário do próprio código diz que *"o merge com o realtime do
servidor é da camada acima"* — camada que nunca foi escrita. O
`AtendimentoRemoteGateway` (Web) assina `StreamAtendimentos`; o desktop, não.

**Consequência:** o Kanban do app instalado não se move sozinho. É o sintoma
relatado no teste.

### F9 — Whitelist sem tela 🟢 **confirmado: regra invisível**

`whatsapp_whitelist` existe no banco e **é aplicada de verdade** na ingestão:
`remetente_deve_ser_ignorado` (`webhook_ingress/src/main.rs:268`), chamada no
passo *"3. Whitelist de remetentes IGNORADOS"* (linha 527). A v1 tinha CRUD
(`configuracoes/whitelist*`); a v2 não tem tela nenhuma.

**Consequência:** a regra existe, funciona e é invisível — um número silenciado
por engano só sai da lista por `psql`. É a lacuna mais barata de fechar: só
falta superfície.

### F10 — Anexo do atendente não chega ao cliente 🔴 **o mais grave da lista**

Origem: doc [00-0609](./00-0609-analise_critica_old_vs_v2.md), item D1 — verificado.

O `data_postgres` grava no outbox um evento com o objeto `midia` completo
(`chave`, `mimetype`, `categoria`, `nome_arquivo`, `is_ptt`) e um comentário que
não deixa dúvida sobre a intenção: *"O worker precisa saber que é mídia para
chamar SendWhatsappMedia em vez de SendWhatsappMessage"* (`atendimento.rs:562`).

O worker **ignora esse objeto**. Monta `{"id", "to_number", "text": conteudo}` e
chama `SendWhatsappMessage`, sempre (`main.rs:2584`). `SendWhatsappMedia` existe,
tem rota no `data_whatsapp` — e **não é chamado em lugar nenhum**.

**Consequência:** o boleto, o comprovante e a arte que o atendente anexa não
chegam ao cliente. Metade do trabalho já está feita e ligada nas duas pontas; o
fio está solto no meio.

### F11 — Chat sem mídia: nem enviar, nem ver 🔴

Duas metades do mesmo buraco, ambas verificadas:

- **Enviar:** `enviarMidia` existe no `AtendimentoGateway`, no
  `AtendimentoRemoteGateway` e no `LocalEngineGateway` — e **nenhum controller ou
  página chama**. Não há botão de anexo no chat.
- **Ver:** `chat_message_bubble.dart:51` renderiza **só** `mensagem.resumoMidia`,
  o texto que a IA gerou. Nenhuma imagem, nenhum player de áudio, nenhum PDF.

**Consequência:** o atendente não confere comprovante de pagamento nem escuta o
áudio do cliente — lê o que a IA achou que era. E, mesmo que houvesse botão, o
F10 impediria a entrega.

### F12 — Marcar como lida e contador de não lidas 🟡

`MarkWhatsappMessageRead` está implementado no `data_whatsapp` (rota e handler) e
**não tem um único chamador** no Flutter. Não há badge de não lidas na lista.

**Consequência:** os ticks azuis nunca sobem no WhatsApp do cliente, e a
operação não distingue o que já foi visto do que não foi.

### F13 — Módulo de Clientes: schema completo, código nenhum 🟡

`oraculo_cliente` existe desde a migração `0004_clientes_contatos.sql`, com RLS
ativa, `FORCE ROW LEVEL SECURITY` e índice único por CNPJ dentro do tenant.
Junto vem `oraculo_cliente_contatos`.

**Zero RPCs** com "Cliente" no `admin.proto`. **Zero referência** a
`oraculo_cliente` no `data_postgres`. **Zero telas.** A v1 tinha o app
`clientes` inteiro: PJ com razão social, validação de CNPJ/CPF/CEP, múltiplos
contatos por empresa, endereços.

**Consequência:** não há CRM. A `ContatosPage` lista telefones soltos; não há
como saber que três números são da mesma empresa. É a maior tabela morta do
banco.

### F14 — `IaEngineService.Analyse` nunca é chamado 🟡

É a **causa raiz do F4**. O método existe no `ai_engine.proto`, está implementado
no Python e tem cliente no Rust — e o worker não o invoca uma vez. Sem ele não há
intenção extraída, nem sentimento, nem entidades, e portanto não há assunto
automático nem tag sugerida. Os campos personalizados também não recebem
write-back: a IA lê `campos_pendentes` e nunca devolve valor extraído.

**Consequência:** F4 e o preenchimento da ficha não são dois trabalhos, são um
só — ligar o `Analyse` no pipeline e escrever o resultado.

### F15 — Treinamento RAG só aceita texto digitado 🟢

A v1 aceitava PDF, DOCX, XLS e CSV com extração automática. Na v2, `file_picker`
está declarado **apenas** no `operacional_module` — e lá nem é usado (F11). O
módulo de treinamento não o declara.

**Consequência:** para carregar um catálogo, o cliente copia e cola por partes.

---

## 4. O que muda no plano de correção

Três levantamentos convergiram: o doc 29 (usuários e configuração), este (núcleo
do atendimento) e o relatório [00-0609](./00-0609-analise_critica_old_vs_v2.md),
feito por outra ferramenta e **reauditado item a item** aqui. A prioridade
consolidada:

| # | Item | Por que nesta posição |
|---|---|---|
| 1 | **F10** anexo do atendente não chega | Perda de dado do cliente, silenciosa. As duas pontas já existem; falta ligar o fio. Menor esforço do topo da lista |
| 2 | **F11** chat sem mídia (enviar e ver) | O atendente não confere comprovante nem escuta áudio. Sem F10, enviar não adianta — vão juntos |
| 3 | **F8** realtime no desktop | O produto entregue é o desktop, e o quadro não se move |
| 4 | **F1 + F3** confiança com veto + rodízio | A decisão 2 amarrou as duas: transbordar para uma fila que ninguém puxa é trocar resposta ruim por silêncio |
| 5 | **F2** desligar o bot (instância + conversa, com volta) | A operação não consegue calar a IA para assumir |
| 6 | **F14 (+F4)** ligar o `Analyse` | Uma entrega só: assunto, tags, entidades e write-back dos campos personalizados |
| 7 | **F5** departamento pela instância | Sem isso, dois números caem no mesmo fluxo |
| 8 | **F6** encerramento por inatividade | A fila acumula conversa morta |
| 9 | **F12** marcar como lida e não lidas | Backend pronto, sem chamador |
| 10 | **F7** notificar o atendente | Depende de F3 (só faz sentido quando houver atribuição) e de F8 |
| 11 | **F13** módulo de Clientes (PJ/CNPJ) | Maior tabela morta do banco; escopo de feature inteira, não de correção |
| 12 | **F9** tela da whitelist / **F15** upload no treinamento | Baratos, sem urgência |

### O fio que costura tudo

**F10 e F11 explicam o incômodo diário**; **F1, F2 e F14 explicam por que a IA
parece "burra e teimosa"**: ela responde sempre, sem termômetro, sem poder ser
calada e sem extrair nada da conversa. Nenhum desses três é falta de
infraestrutura — os campos, os RPCs e os métodos existem e estão ociosos.

### Divisão em dois planos

- **Núcleo do atendimento** — F10, F11, F8, F1+F3, F2, F14+F4, F5, F6, F12, F7.
  Risco técnico no worker e no chat; revisores naturais: backend e frontend.
- **Equipe e configuração** — L1–L7 do doc 29, mais F9 e F13. Risco de segurança
  e de produto; revisor natural: `security-auditor`.

## 5. Decisões de produto — tomadas em 2026-09-06

As cinco perguntas foram respondidas. Elas são a **entrada dos planos** e não
devem ser reabertas na execução:

| # | Pergunta | Decisão |
|---|---|---|
| 1 | Faixas de confiança | **Manter 0.5 / 0.8** como padrão **e torná-las configuráveis por tenant** (junto de `similarity_threshold` e `vector_distance_threshold`, que já vivem na config) |
| 2 | Baixa confiança: atribuir ou só enfileirar? | **Atribuir a um atendente**, com rodízio que respeite `max_atendimentos_simultaneos`, `disponivel` e `data_ultima_atribuicao` — ou seja, F1 e F3 são uma entrega só |
| 3 | Desligar o bot: instância ou conversa? | **Os dois níveis**, como na v1 |
| 4 | Encerramento por inatividade | **Configurável por tenant, padrão 30 min** |
| 5 | Trello | **Descontinuado.** Não portar; remover das telas de comparação |

### Ajuste à decisão 1, depois da auditoria do F1

Quando a decisão foi tomada, o entendimento era que a v2 gravava a confiança sem
usá-la. A verificação mostrou outra coisa: a v2 **entregou o transbordo ao
próprio LLM** (`transferir_atendimento`), e a confiança é descartada.

Isso não invalida a decisão — **especifica** o que ela significa na prática:

- a faixa numérica tem **poder de veto** sobre o flag do modelo. Se a confiança
  ficar abaixo do piso, transfere, ainda que o LLM diga que sabe responder;
- acima do piso, o `transferir_atendimento` do LLM continua valendo — ele conhece
  o roteamento por fluxo, que a faixa numérica não conhece;
- e `confianca_resposta` **passa a ser gravada sempre**. Sem histórico não há
  como calibrar os limiares depois, e é justamente isso que torna um número
  melhor que uma auto-avaliação: ele é auditável.

Consequência direta da decisão 2: **F1 sem F3 não entrega valor**. Transferir por
baixa confiança para uma fila que ninguém puxa é trocar uma resposta ruim por
silêncio. As duas andam juntas.

Consequência da decisão 3: além do `resposta_bot` por instância (que não existe),
é preciso um caminho para **religar** o `bot_pode_atender` da conversa — hoje ele
só desliga (ver F2).

---

## 6. Nota de método

Tudo aqui foi verificado por leitura direta de código, schema e contrato. Os
quatro itens que estavam **a confirmar** na primeira versão deste documento foram
fechados em 2026-09-06 e as conclusões estão no corpo de F2, F6, F7 e F9 — três
confirmaram ausência, um (F9) confirmou presença sem superfície.

**Uma correção ao doc 29 saiu desta rodada:** a afirmação de que
`module_permissions` seria inerte estava **errada**. Ver a revisão da L3 lá.
