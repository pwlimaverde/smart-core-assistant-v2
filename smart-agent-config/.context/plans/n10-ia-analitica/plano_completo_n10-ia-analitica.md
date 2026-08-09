# N10 — IA analítica no fluxo

> **Origem:** auditoria v1 × v2, `26-levantamento-paridade-v1-v2.md` §3.9 e
> `27-mapa-telas-rotas-v2.md` §D.7.
> **Tese:** o `ia_engine` já sabe analisar — ninguém pede. Esta fase liga o
> `Analyse`, colhe o que ele produz, e completa o ciclo de treinamento (arquivo
> e feedback).
> **Escala:** MEDIUM · **Depende de:** N8.5 (pipeline estável). Paralelizável
> com N11.

---

## O ponto de partida

`IaEngineService.Analyse` está implementado dos dois lados: proto
(`ai_engine.proto:68-88`), datasource com **schema pydantic dinâmico** montado a
partir de `valid_intent_types`/`valid_entity_types`
(`features/analyse/datasources/analyse_datasource.py`), prompts com override por
tenant (chaves `PROMPT_SYSTEM_ANALISE_PREVIA_MENSAGEM`, `PROMPT_INTENT_SYSTEM`,
`PROMPT_INTENT_FOOTER` da migration 0026), e testes.

E `grep '\.analyse(' server/apps` **não retorna nada**. O worker chama
`embed`, `responder`, `transcribe`, `interpret_media` e `sentimento` — nunca
`analyse`. Consequência em cadeia:

- `oraculo_mensagem.intent_detectado` e `.entidades_extraidas`: sempre vazias
  desde a migration 0006;
- `tenants_tenantconfig.entity_types` (configurável no painel): sem efeito;
- quatro comportamentos da v1 que dependiam disso não existem.

---

## E1 — Ligar o `Analyse` ao pipeline

### O que fazer

No `processar_mensagem_recebida` do worker, depois da persistência e **dentro do
mesmo ramo** onde hoje o `Responder` é chamado (após o buffer da N8.5.2 drenar):

1. Resolver os tipos válidos: `valid_intent_types` sai das intents cadastradas
   (`ListIntents` do `data_postgres`, que já existe e alimenta a aba "Intenções");
   `valid_entity_types` sai de `tenants_tenantconfig.entity_types`, que já viaja
   no `RuntimeConfig` do Redis.
2. Chamar `Analyse` com a mensagem (ou o **texto agregado** do buffer) e o
   histórico — o mesmo `ChatHistory` que já é montado para o `Responder`.
3. Persistir via RPC novo `AnexarAnaliseMensagem` (espelho do
   `AnexarAnaliseMidia`, que já existe): grava `intent_detectado` e
   `entidades_extraidas` na mensagem.

**Ordem em relação ao `Responder`:** paralela, não sequencial. `Analyse` e
`Responder` são independentes (o `Responder` não recebe intents hoje e não vai
receber nesta fase) — rodar em `tokio::join!` não soma latência ao cliente.
Se o `Analyse` falhar, a resposta sai igual.

**Degradação graciosa** (padrão do `ia_client::resilient`): timeout, retry com
backoff e, na falha, seguir sem análise. Mensagem sem análise é aceitável;
mensagem sem resposta não é.

**Custo:** é uma chamada de LLM a mais por mensagem. Kill-switch por tenant
`analise_previa_habilitada` (mesmo padrão do `transcription_enabled`, migration
0024), default **ligado** — a v1 sempre analisava.

### Observabilidade & Auditoria

- **Logs/trace:** span `ia.analise` (irmão de `ia.sentimento`, `main.rs:1713`)
  com `tenant_id`, `atendimento_id`, `intents_count`, `entidades_count`,
  `duracao_ms`. `skip_all` — a mensagem é PII e não entra no span.
- **Auditoria:** **sem evento** — intencional. Anotar análise numa mensagem não
  é mutação de estado sensível; o `mensagem.persistida` já cobre o ciclo. Os
  efeitos derivados (E2/E3/E4) têm auditoria própria onde tocam cadastro.
- **Sanitização:** o **valor** da entidade pode ser PII (nome, e-mail, CPF).
  Nunca logar valores — só as **contagens** e os **tipos**. No `audit_log` dos
  efeitos, o mesmo: tipo sim, valor não.

### Testes

- Mensagem com intenção conhecida → `intent_detectado` gravado.
- `Analyse` fora do ar → mensagem persistida, resposta enviada, análise vazia.
- Tenant com kill-switch desligado → `Analyse` não é chamado.
- `entity_types` vazio no tenant → chamada sem tipos, sem erro.

---

## E2 — Assunto automático do atendimento

**v1:** `AttendanceOrchestrator._auto_fill_subject` (linha 1368).
**v2:** `oraculo_atendimento.assunto` só aparece em SELECT — sempre nulo, e o
cartão do kanban mostra "Sem assunto" para sempre.

### O que fazer

Na primeira análise de um atendimento **sem assunto**, derivar o assunto da
intenção de maior confiança (a v1 usa a intenção; não inventa um resumo por
LLM — mais barato e mais previsível). RPC novo `DefinirAssuntoAtendimento`, ou
campo aditivo no `AnexarAnaliseMensagem` (**preferir o segundo**: mesma
transação, menos round-trip).

Regras: só preenche se estiver vazio (nunca sobrescreve o que um humano
escreveu); trunca em 200 caracteres (limite da coluna); e nunca vira string
vazia.

### Observabilidade & Auditoria

- **Logs:** campo `assunto_definido=true` no span `ia.analise`.
- **Auditoria:** **sem evento** — é enriquecimento derivado, não decisão. Se um
  humano editar o assunto (N9), aí sim vale auditar a edição manual.
- **Sanitização:** o assunto vem de um rótulo de intenção (vocabulário fechado
  do tenant), não de texto livre do cliente — sem PII. Registrar essa premissa:
  se um dia o assunto virar resumo por LLM, ele passa a ser PII.

---

## E3 — Etiquetagem por intenção

**v1:** `_sync_intent_tags` (linha 1419) — sincroniza as etiquetas do
atendimento com as intenções detectadas.

### O que fazer

Para cada intenção detectada acima de um limiar de confiança, aplicar a etiqueta
de mesmo nome **se ela existir no catálogo** (`atu_etiqueta`). Reusar
`AlternarEtiqueta`, que já existe.

**Decisão:** não criar etiqueta automaticamente. O catálogo é curadoria do
tenant; um bot criando etiqueta a cada intenção nova enche a tela de lixo em uma
semana. Se a etiqueta não existe, a intenção fica só na mensagem.

**Marcar a origem:** a etiqueta aplicada pelo bot precisa ser distinguível da
aplicada por humano — coluna `origem` em `atu_etiqueta_atendimento`
(`bot` | `manual`), migration nova. Sem isso, remover uma etiqueta na mão e o
bot recolocá-la na mensagem seguinte vira briga silenciosa. **Regra:** etiqueta
removida por humano não volta pelo bot no mesmo atendimento.

### Observabilidade & Auditoria

- **Logs:** `etiquetas_aplicadas` (contagem) no span `ia.analise`.
- **Auditoria:** **sim** — `etiqueta.aplicada_por_ia`, com `atendimento_id`,
  `etiqueta_id` e a confiança. É mutação de estado visível ao operador, e a
  trilha é o que responde "quem colou isso aqui". `user_id` nulo (é o bot).
- **Sanitização:** nomes de etiqueta são do tenant, não PII.

---

## E4 — Enriquecimento do contato por entidades

**v1:** `MessageAnalyzer.process_contact_entities` (linha 105) — usa as entidades
para completar o cadastro do contato, com uma lista de tipos permitidos
(`_get_valid_metadata_entities`).

### O que fazer

Das entidades extraídas, promover a campos do contato apenas os tipos mapeados
(`nome`, `email`) e guardar o resto em `oraculo_contato.metadados` (JSONB que já
existe).

**Regras duras:**

- **Nunca sobrescrever** dado preenchido por humano. Só completa o que está
  vazio. O cliente que digita "meu nome é João" numa conversa não pode
  renomear o cadastro que o operador corrigiu ontem.
- Validar formato (e-mail com formato válido; nome com tamanho mínimo/máximo).
- Confiança mínima — entidade duvidosa não entra no cadastro.
- RPC: estender `UpsertContact` (existe) com semântica *fill-if-empty*, em vez de
  criar rota nova.

### Observabilidade & Auditoria

- **Logs:** `campos_contato_preenchidos` (contagem) — **nunca os valores**.
- **Auditoria:** **sim** — `contato.enriquecido_por_ia`, com `contato_id` e a
  **lista de campos** alterados (nomes, não valores). Mutação de cadastro por
  agente automático precisa de trilha: é o que permite desfazer.
- **Sanitização:** ponto mais sensível da fase — nome e e-mail são PII direta.
  Não vão para log, span, métrica nem descrição de auditoria.

---

## E5 — Treinamento por upload de arquivo

**v1:** `treinar_ia.html` aceita `documento` (campo file) e
`TreinamentoService.processar_arquivo_upload` → `load_document_file` com loaders
LangChain para **7 formatos**: `.pdf`, `.doc`, `.docx`, `.txt`, `.xls`, `.xlsx`,
`.csv`.
**v2:** `CreateMyTreinamentoRequest` tem só `tag`, `grupo`, `conteudo` — texto
colado.

### O que fazer

**Caminho do arquivo** (decisão de arquitetura): o binário **não** trafega no
gRPC junto com o texto. Fluxo em duas etapas, reusando o que existe:

1. Cliente pede uma URL de upload → `data_storage` devolve presign PUT
   (prefixo `treinamento/{tenant}/...`) — mesma mecânica da mídia da N9.1.
2. Cliente sobe o arquivo direto para o R2.
3. Cliente chama `CreateMyTreinamentoComArquivo` com `tag`, `grupo` e a chave do
   objeto. O servidor registra o treinamento como pendente de extração.
4. **Job no scheduler** (o quarto job, ao lado dos que já existem): busca
   treinamentos com arquivo e sem conteúdo, baixa do R2, chama o `ia_engine` para
   extrair o texto, grava em `conteudo`, e o job de vetorização existente segue
   dali.

**No `ia_engine`:** RPC novo `ExtrairTextoDocumento(MediaRef) -> texto`. Os
loaders já estão documentados na central (`doc_dev/libs/python/document_loaders.md`).
Dependências novas no `pyproject.toml`: `pypdf`, `docx2txt`, `openpyxl` (o
`langchain-community` traz os wrappers).

**Limites:** tamanho máximo por arquivo (config), tipos permitidos validados no
servidor **por conteúdo** (magic bytes), não só pela extensão. Contar o upload na
quota de storage do tenant (`RegisterStorageUsage`, já existe).

### Observabilidade & Auditoria

- **Logs:** span `treinamento.extracao` com `tenant_id`, `treinamento_id`,
  `formato`, `bytes`, `caracteres_extraidos`, `duracao_ms`.
- **Auditoria:** **sim** — `treinamento.arquivo_enviado` (quem subiu, nome do
  arquivo, tamanho, formato) e `treinamento.extracao_falhou` no erro. Material de
  treinamento vira comportamento do bot: a trilha responde "de onde saiu essa
  resposta".
- **Sanitização:** o **conteúdo** do documento pode ter dado sensível do
  negócio. Nunca logar o texto extraído — só a contagem de caracteres. O nome do
  arquivo pode ir para a auditoria (é escolha do usuário).

---

## E6 — Feedback do teste de resposta

**v1:** `testar_query.html` (573 linhas) tem campo **"Digite a resposta
correta..."** e grava em `treinamento_query_test_feedback`. Não é um joinha — é
correção supervisionada.
**v2:** `TestarPergunta` responde e não guarda nada; a tabela existe (migration
0007) sem RPC.

### O que fazer

1. RPC `RegistrarFeedbackTeste`: pergunta, resposta obtida, **resposta correta**
   (texto livre), avaliação (`boa`/`ruim`), e os trechos que foram usados.
2. Na aba "Testar", após a resposta: dois botões e um campo de correção.
3. Tela de revisão do acumulado (lista dos feedbacks) — permite ver o padrão do
   que a IA erra. **Fica fora desta fase** se o tempo apertar; o valor está em
   coletar primeiro.

**E6.1 — Testar com mídia:** a v1 aceita anexo no teste
(`placeholder="Digite uma mensagem ou anexe mídia..."`). Estender
`TestarPergunta` com um `MediaRef` opcional, reusando o presign da E5. Só faz
sentido depois que a N9.1 estabelecer o caminho de upload — **marcar como
opcional** nesta fase.

### Observabilidade & Auditoria

- **Logs:** span `treinamento.feedback` com `avaliacao` e se houve correção.
- **Auditoria:** **sim** — `treinamento.feedback_registrado`. É insumo de
  curadoria com efeito futuro no comportamento do bot.
- **Sanitização:** pergunta e resposta correta são texto livre do operador —
  podem conter exemplo com dado de cliente. Não vão para log.

---

## Sequência e dependências

```
E1 (ligar Analyse) ──► E2 (assunto)
                   ├─► E3 (etiquetas)   ← precisa de migration `origem`
                   └─► E4 (contato)     ← o mais sensível (PII)

E5 (arquivo) ──────────────────────────► independente; toca ia_engine + scheduler
E6 (feedback) ─────────────────────────► independente; menor esforço
```

**Ordem recomendada:** E1 → E2 → E3 → E4 (a cadeia da análise, em ordem crescente
de risco) e, em paralelo, E6 → E5 (E6 é barato e entrega valor sozinho; E5 é o
maior bloco desta fase).

## Riscos

| Risco | Mitigação |
|---|---|
| Custo de LLM por mensagem sobe | `Analyse` em paralelo ao `Responder`, kill-switch por tenant, métrica de chamadas por tenant |
| E4 corromper cadastro com dado inventado | fill-if-empty + validação de formato + confiança mínima + auditoria com campos alterados |
| E3 brigar com o operador por etiqueta | coluna `origem` + regra "removida por humano não volta" |
| E5 estourar quota/disco com arquivo grande | limite de tamanho, validação por magic bytes, contabilizar na quota |
| Extração devolver texto vazio (PDF escaneado) | detectar e marcar o treinamento como "extração vazia" com aviso na tela — não deixar o tenant achar que treinou |

## Definition of Done

- [ ] `intent_detectado`/`entidades_extraidas` deixam de ser sempre vazios.
- [ ] Conversa nova ganha assunto e etiqueta sem intervenção.
- [ ] Contato é completado sem sobrescrever o que humano preencheu.
- [ ] PDF de política vira material treinado e responde na aba de teste.
- [ ] Feedback do teste (com resposta correta) fica gravado.
- [ ] Nenhum valor de entidade, texto de documento ou PII em log/auditoria.
- [ ] `cargo` + `pytest` (`ruff`/`mypy`) verdes; cobertura do `ia_engine` mantida.
