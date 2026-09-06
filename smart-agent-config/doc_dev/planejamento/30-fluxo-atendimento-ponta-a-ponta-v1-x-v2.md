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

A v2 **grava** `oraculo_mensagem.confianca_resposta`, mas nenhuma busca no
`worker` encontra leitura desse valor para decidir. Não há transferência
automática por baixa confiança.

**Consequência:** o bot da v2 responde com a mesma autoridade tendo 0.2 ou 0.9 de
confiança. O mecanismo que impedia resposta ruim de chegar ao cliente
desapareceu — e o campo continua lá, dando impressão de que funciona.

### F2 — Sem desligar o bot por instância 🔴

Detalhado no doc 29 (L7). A v1 tinha três níveis; a v2 tem dois:

| Nível | v1 | v2 |
|---|---|---|
| Instância inteira | `AppInstance.resposta_bot` + toggle na tela | ❌ **não existe** |
| Conversa | `Atendimento.bot_pode_atender` | ✅ existe no banco e é respeitado no worker |
| Após intervenção humana | bloqueio permanente | ✅ `atendente_humano_id.is_some()` |

**Consequência:** não há como calar a IA de um número inteiro. E, mesmo o
`bot_pode_atender`, que existe, **a confirmar** se tem controle na interface.

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

### F6 — Timeout de inatividade 🟡 **a confirmar**

A v1 encerrava atendimento parado (30 min, configurável). A v2 tem scheduler
com `feedback_expirado_em` e purga de mídia; **não foi confirmado** se há
encerramento por inatividade. Se não houver, a fila acumula conversas mortas.

### F7 — Notificação ao atendente 🟡 **a confirmar**

A v1 notificava o atendente da transferência, *"repetida até resposta"*. A v2
tem realtime (`publicar_realtime`), mas **não foi verificado** se há notificação
dirigida a quem recebeu o atendimento — e, no desktop, o realtime do servidor
sequer chega ao cliente (ver F8).

### F8 — Realtime não chega ao desktop 🔴

Já diagnosticado nesta sessão: o `LocalEngineGateway` emite **apenas mutações
locais**; o comentário do próprio código diz que *"o merge com o realtime do
servidor é da camada acima"* — camada que nunca foi escrita. O
`AtendimentoRemoteGateway` (Web) assina `StreamAtendimentos`; o desktop, não.

**Consequência:** o Kanban do app instalado não se move sozinho. É o sintoma
relatado no teste.

### F9 — Whitelist sem tela 🟢

`whatsapp_whitelist` existe no banco; a v1 tinha CRUD
(`configuracoes/whitelist*`). **A confirmar** se a v2 aplica a whitelist na
ingestão — se aplicar sem tela, é regra invisível; se não aplicar, é tabela
morta.

---

## 4. O que muda no plano de correção

O doc 29 tratava de usuários e configuração. Este acrescenta o **núcleo do
produto** — e reordena a prioridade:

| Prioridade | Item | Por quê |
|---|---|---|
| 1 | **F1** faixas de confiança | Qualidade da resposta ao cliente final; hoje o bot responde igual com 0.2 e 0.9 |
| 2 | **F8** realtime no desktop | O produto entregue é o desktop, e o quadro não atualiza |
| 3 | **F2** desligar o bot (instância + conversa) | Operação não consegue assumir o atendimento manualmente |
| 4 | **F3** atribuição automática | Infra pronta e ociosa; fila não distribui |
| 5 | **F4/F5** enriquecimento e roteamento | Qualidade da triagem no quadro |
| 6 | **F6/F7/F9** | Confirmar antes de planejar |

**F1 e F2 juntos** explicam por que a v2 "parece" funcionar e ainda assim
incomoda: o bot responde sempre, com qualquer confiança, e não há como silenciá-lo.

## 5. Perguntas que precisam de resposta antes do plano

1. As faixas de confiança da v1 (0.5 / 0.8) continuam valendo como regra de
   produto, ou o número muda? Devem ser **configuráveis por tenant** (a v2 já
   tem `similarity_threshold` e `vector_distance_threshold` na config)?
2. Transferência por baixa confiança deve **atribuir** a alguém (F3) ou só
   marcar como "aguardando humano" e deixar na fila?
3. O desligamento do bot é por instância, por conversa, ou os dois? A v1 tinha
   os dois.
4. Encerramento por inatividade: manter os 30 min da v1? Por tenant?
5. Trello (5 models na v1) entra na v2 ou foi descontinuado?

---

## 6. Nota de método

O que foi verificado por leitura direta de código e schema está afirmado; o que
dependeria de executar o fluxo está marcado **a confirmar** — F6, F7, F9 e o
controle de `bot_pode_atender` na interface. Não os afirmei como ausentes porque
ausência de resultado em busca textual não é prova de ausência de comportamento.
