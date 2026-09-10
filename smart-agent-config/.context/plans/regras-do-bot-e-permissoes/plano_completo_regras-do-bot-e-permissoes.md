# Plano completo — Regras do bot e permissões

> **Verdade técnica**, levantada direto do código em 2026-09-06. Cada afirmação
> aponta arquivo e linha. O que não pôde ser verificado está marcado.
>
> Escopo: os **sete itens** que N9–N12 não cobrem (ver doc 32 §2).

---

## D4 — Fechar o fallback de escopos 🚨 *vai primeiro*

> ⚠️ **Correção ao doc 29.** A primeira redação dizia que `module_permissions`
> era inerte. **É lido** — é a fonte primária dos escopos do JWT.

**Estado real.** `derivar_escopos` (`application/src/auth/login.rs:244`, gêmeo em
`refresh.rs:133`):

```
1. is_superuser                    → ["*"]
2. module_permissions como array   → a própria lista
3. module_permissions como objeto  → chaves com valor true
4. FALLBACK pelo role              → admin|owner: [atendimentos:read,
                                      atendimentos:write, clientes:write,
                                      tenant:admin]
                                     demais:      [atendimentos:read,
                                      atendimentos:write, clientes:write]
```

Os escopos são exigidos de verdade no `data_postgres`
(`ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])`).

🚨 **O problema é o passo 4:** qualquer não-admin sem `module_permissions` nasce
**podendo escrever**. Não existe papel somente-leitura — o `viewer` da v1 é
impossível hoje.

**Referência da v1:** `TenantModule` tinha 8 módulos com `view`/`edit`/`delete`;
`TenantRoleType` tinha 4 papéis (`admin`, `manager`, `staff`, `viewer`); e
`has_module_permission` autorizava o tenant-admin inteiro.

### Três passos, nesta ordem

1. **Medir.** Acrescentar `origem_escopos` (`module_permissions` ×
   `fallback_role`) ao span de login. Rodar alguns dias e **contar quem depende
   do fallback**.
2. **Migrar.** Gravar explicitamente, para esses usuários, os escopos que já
   usavam.
3. **Fechar.** Fallback passa a ser o conjunto mínimo (só leitura); criar
   `viewer`. Decidir o destino do `manager` — provavelmente `staff` + escopos,
   sem papel novo.

> **Não voltar à matriz módulo × ação da v1.** A lista plana funciona; o que
> falta é cobertura de papéis.

### Observabilidade & Auditoria

- **Logs/trace:** `origem_escopos` no span de login — é o instrumento que torna
  o passo 1 possível. Sem ele, o passo 3 é um chute.
- **Auditoria:** **obrigatória** (08 §4.2 — mudança de permissão é evento
  crítico). **Novo** `permissao.alterada`, com **antes e depois** — sem o
  "antes" não se investiga escalonamento de privilégio.
- **Sanitização:** escopos não são segredo e podem ser logados.

---

## D1 — Confiança com veto

**Estado real, verificado linha a linha:**

- `responder_via_ia` (`worker/src/main.rs:543`) devolve **só**
  `resposta.resposta_texto`. A palavra `confiabilidade` **não aparece uma única
  vez** em `worker/src/main.rs`;
- `registrar_resposta_bot` (`mensagens.rs:348`), único `UPDATE` que grava
  `confianca_resposta`, é chamado **apenas** por
  `tests/atendimentos/mod.rs:161`;
- logo, `oraculo_mensagem.confianca_resposta` é **sempre nulo** em produção — e
  `resposta_bot`/`respondida` também não são preenchidos por esse caminho.

**A decisão não ficou órfã — mudou de dono.** O `ia_engine` devolve
`transferir_atendimento` + `fluxo_transferencia`, aplicados por
`aplicar_transferencia_ia` (`main.rs:222`), com auditoria em
`atendimento.transferido_por_ia`. O código chama isso de *"safety-net de
transferência"*.

**Consequência:** quem decide o transbordo é a **auto-avaliação do modelo**. Não
há piso, e não fica registro do quanto ele sabia — um sistema sem termômetro e
sem histórico para calibrar.

### Dois deploys, não um

**Deploy 1 — medir.** `responder_via_ia` passa a devolver a confiança junto do
texto; o worker chama `registrar_resposta_bot`. **Zero mudança de
comportamento.**

**Deploy 2 — decidir.** Só com histórico:
- `confianca_minima_transferencia` (0.5) e `confianca_minima_automatica` (0.8) na
  config do tenant, ao lado de `similarity_threshold` e
  `vector_distance_threshold`;
- **veto**: abaixo do piso, transfere, mesmo com o LLM dizendo que sabe
  responder;
- acima do piso, o `transferir_atendimento` do LLM continua valendo — ele conhece
  o roteamento por fluxo, que o número não conhece;
- faixa intermediária: responde e marca para revisão.

> Ligar o veto sem histórico é calibrar no escuro. **Não pular o deploy 1.**

### Observabilidade & Auditoria

- **Logs/trace:** o span da resposta ganha `confianca` (numérico) e `decisao`
  (`automatica` / `revisao` / `transferida`). É o que permite calibrar depois.
- **Auditoria:** reusar `bot.respondeu`, acrescentando a confiança e a decisão.
- **Sanitização:** a confiança é número e pode ser logada. **A pergunta e a
  resposta, não** — vão para o banco, nunca para o log.

---

## D2 — Rodízio de atendentes

`oraculo_atendente` tem `disponivel`, `max_atendimentos_simultaneos` e
`data_ultima_atribuicao`; o repositório tem `atualizar_ultima_atribuicao`. A
atribuição só acontece quando **alguém arrasta o cartão**
(`assumir_atendimento`, `atendimento.rs:905`).

> A N11-E9 menciona *"capacidade do atendente (`max_conversas`) aplicada na
> elegibilidade"* — uma linha, sem mecanismo de distribuição. O rodízio em si
> não está em plano nenhum.

**Seleção:** menor `data_ultima_atribuicao` entre os disponíveis que não
estouraram o limite, **no departamento do fluxo**.

**Concorrência.** Dois transbordos simultâneos não podem escolher o mesmo
atendente e estourar o limite. Usar `UPDATE ... WHERE` com a condição de carga no
próprio `WHERE` e `RETURNING` — o mesmo padrão já usado e justificado no resgate
de voucher (`vouchers.rs:159`).

**Ninguém disponível** → o atendimento fica na fila **sem dono**, e isso precisa
aparecer na tela. Silêncio aqui é pior que a fila cheia.

**D1 sem D2 não entrega valor:** transbordar para uma fila que ninguém puxa é
trocar resposta ruim por silêncio.

### Observabilidade & Auditoria

- **Logs/trace:** span da atribuição com `atendente_id` e `motivo`.
- **Auditoria:** **novo** `atendimento.atribuido_automaticamente`, com autor
  sistema, `atendente_id`, `motivo: "baixa_confianca"` e a confiança. Distinto de
  `atendimento.transferido_por_ia`, que é quando o LLM decidiu — os dois motivos
  precisam ser separáveis depois.
- **Sanitização:** só ids; sem conteúdo de conversa.

---

## D3 — Desligar o bot nos dois níveis, com volta

| Nível | v1 | v2 hoje |
|---|---|---|
| Instância | `AppInstance.resposta_bot` + rota `instances/<pk>/toggle-bot/` | ❌ não existe |
| Conversa | `Atendimento.bot_pode_atender` | ⚠️ existe e é respeitado, **sem controle na interface** |
| Após intervenção humana | bloqueio permanente | ✅ `assumir_atendimento` grava `false` |

**Verificado:** `assumir_atendimento` (`atendimentos.rs:461`) grava
`bot_pode_atender = false`; `desatribuir` **não** religa, por decisão documentada
no trait (`atendimentos.rs:148`) — *"quem desligou o bot foi uma pessoa; religá-lo
por conta própria faria o robô voltar a responder um cliente que pediu para falar
com gente"*. E **não existe nenhum `UPDATE`** que devolva `true` no servidor
inteiro. `bot_pode_atender`/`botPodeAtender` **não aparece em nenhum arquivo
Dart**.

**Duas metades:**

1. **Instância** — migração com `resposta_bot BOOLEAN NOT NULL DEFAULT TRUE` em
   `whatsapp_instance`; leitura no worker **antes** de acionar a IA, no mesmo
   ponto onde `bot_pode_atender` já é checado (`main.rs:1318`); toggle na tela de
   conexões.
2. **Conversa** — RPC para religar e o controle na ficha.

**Regra de produto que não pode ser violada:** religar é **ação deliberada** de
quem assumiu, nunca efeito colateral de devolver o cartão. A tranca documentada
no trait continua; esta entrega acrescenta a **porta**.

### Observabilidade & Auditoria

- **Logs/trace:** **reusar `bot.silenciado`**, que já existe e já é emitido pela
  barreira (`main.rs:1246` e `:1818`). Acrescentar o motivo: `instancia`,
  `conversa`, `humano_ativo`.
- **Auditoria:** **novos** `instancia.bot_alterado` e `atendimento.bot_alterado`,
  com autor e valor. *"Por que o bot parou de responder?"* precisa ter resposta.
- **Sanitização:** sem segredo envolvido.

---

## D5 — Encerramento por inatividade

> ⚠️ **Construção nova.** O doc 31 (N3) mostrou que a v1 **não** encerrava por
> inatividade: o único timeout de lá é o da pesquisa de satisfação (5 min,
> `verificar_feedback_atendimento`). A afirmação dos 30 min vinha de
> `RESUMO_FLUXO_RECEBIMENTO_MENSAGEM.md:140` — descrição do fluxo desejado — e o
> próprio `CHECKLIST_IMPLEMENTACAO.md:158` da v1 marca "Timeout de atendente"
> como ❌. **Não há código para copiar.**

Rotina no `scheduler.rs`, no molde das cinco existentes (`processar_*`): lote por
variável de ambiente, lock com TTL, `chamar_rpc` para um handler no
`data_postgres`. Limite na config do tenant, padrão 30 min.

**Cuidado de produto:** encerrar por abandono **não** pode disparar a pesquisa de
satisfação. `solicitar_pesquisa_satisfacao` (`atendimento.rs:85`) é chamada na
transição de status — o novo status precisa ser distinguível de "resolvido".

**Armadilha de nome:** `feedback_timeout` e `feedback_expirado_em` são da
pesquisa, não do abandono. Não reaproveitar.

### Observabilidade & Auditoria

- **Logs/trace:** um log com o **total do lote**, não um por atendimento.
- **Auditoria:** **novo** `atendimento.encerrado_por_inatividade`, com o limite
  aplicado — sem ele ninguém explica o encerramento ao cliente.

---

## D6 — Notificar o atendente

> ⚠️ **Construção nova** (doc 31, N4): o checklist da v1 marca ❌ para
> "Notificações push para novos atendimentos", "Dashboard em tempo real para
> atendentes", "Sistema de retry para busca de atendente" e "Escalação
> automática". Também nunca existiu.

**Problema de contrato.** O canal é `tenant:{id}:events` (`worker/main.rs:896`,
`realtime.rs:60`) — **um para a empresa toda** — e `AtendimentoEvent`
(`admin.proto:1289`) tem três campos: `event_type`, `tenant_id`, `payload`.
**Não há destinatário.** Os tipos publicados são `whatsapp.conexao`,
`whatsapp.presenca`, `kanban.movido`, `mensagem.recebida`, `mensagem.enviada`,
`mensagem.status_atualizado` — **nenhum de atribuição**.

| Opção | Custo | Risco |
|---|---|---|
| Campo `destinatario_id` no evento, filtro no cliente | baixo | **vaza atribuição alheia** — todo cliente recebe todos os eventos |
| Canal por atendente (`tenant:{id}:atendente:{id}`) | médio | mais assinaturas no Redis; muda o `RealtimeManager` |

A segunda é a correta se a informação for sensível. **Pergunta que decide, na
fase P:** um atendente pode saber a quem os outros atendimentos foram
atribuídos?

**Depende de D2** (só há o que notificar quando houver atribuição) e do
**realtime do desktop**, que é entrega da **N9** — sem ele a notificação não
chega ao app instalado.

**Observabilidade:** span de publicação com `atendente_id`. Sem auditoria
(*ausência intencional* — o evento auditável é a atribuição, na D2). O payload
não carrega conteúdo de mensagem.

---

## D7 — `PaymentRecord` e usuários globais

Duas lacunas do lado do superusuário (doc 31 §1):

- **`PaymentRecord`**: a tabela `tenants_paymentrecord` existe e está **vazia**;
  a v1 tinha `bo/tenant/<uuid>/register-payment/`. Sem tela na v2.
- **`User`**: a v1 registrava `User` no Django admin. A v2 não tem gestão global
  de usuários pelo superusuário.

**Auditoria: obrigatória** (08 §4.2 — `PaymentRecord` é evento crítico):
`pagamento.registrado_manualmente` e `usuario.alterado_pelo_superusuario`.

---

## Correções aplicadas nesta reestruturação

| # | O que mudou | Por quê | Fonte |
|---|---|---|---|
| 1 | **O plano encolheu de 35 entregas para 7** | N9–N12 já cobrem o resto; dois planos meus duplicavam trabalho de 2026-08-09 | doc 32 §1 |
| 2 | **D4 promovida a primeira** | É a única com risco de segurança ativo, e permissão fica mais cara de mexer depois | — |
| 3 | **D4 dividida em 3 passos** (medir → migrar → fechar) | Apertar direto derruba acesso de quem já trabalha | — |
| 4 | **D1 dividida em 2 deploys** | Ligar o veto sem histórico é calibrar no escuro | — |
| 5 | **D1 reescrita**: a v2 **não grava** a confiança | O doc 30 dizia que gravava sem ler; `registrar_resposta_bot` só é chamado por teste | `mensagens.rs:348`, `tests/atendimentos/mod.rs:161` |
| 6 | **Acrescentado que o transbordo migrou para o LLM** | Muda o que "veto" significa: é veto sobre o flag do modelo, não sobre o nada | `main.rs:222` |
| 7 | **D3 reusa `bot.silenciado`** em vez de criar evento | O vocabulário de auditoria já tem o evento certo | `main.rs:1246`, `:1818` |
| 8 | **D5 reclassificada como construção nova** | A v1 não encerrava por inatividade | doc 31 §4 (N3) |
| 9 | **D6 reclassificada e adiada** | A v1 também nunca notificou; e o contrato não tem destinatário | doc 31 §4 (N4); `admin.proto:1289` |
| 10 | **D2 ganhou a guarda de concorrência** | Dois transbordos simultâneos estourariam o limite do atendente | padrão de `vouchers.rs:159` |
| 11 | **D5 não pode disparar a pesquisa de satisfação** | `solicitar_pesquisa_satisfacao` dispara na transição de status | `atendimento.rs:85` |

---

## Riscos

- 🚨 **D4 mexe em quem já trabalha.** Os três passos são a ordem correta, não
  excesso de cuidado.
- 🚨 **D1 muda o comportamento visível da IA.** Um piso mal calibrado transfere
  tudo para humano e afoga a fila.
- **D6 exige decisão de contrato** antes de qualquer código.
- **D3 tem uma tranca deliberada** que não pode ser removida por descuido.
- **D5 e D6 não têm referência na v1** — especificar o comportamento antes de
  escrever, porque não há código para consultar.
- **Dependência externa:** D6 precisa do realtime do desktop, que é da **N9**.
  Se a N9 não andar, D6 fica meio entregue.

## Fora de escopo

Tudo o que já tem plano: **N9** (mídia, chat, quadro, ficha, realtime no
desktop), **N10** (`Analyse`, assunto, tags, entidades, upload de treinamento,
feedback do ensaio), **N11** (sonda de conexões, departamento por conexão,
whitelist, contatos e clientes PJ, e-mail transacional, recuperação de senha,
reenvio de convite, dead-letter, `CoreSettings`, expiração de assinatura,
enquete/lista/botões), **N12** (ETL, quotas, cutover) e
**`cadastro-retomavel-e-pagamento`**.
