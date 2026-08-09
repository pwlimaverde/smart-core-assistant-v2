# N8.5 — Defeitos de comportamento do pipeline de mensagem

> **Origem:** auditoria de código v1 × v2 (2026-08-08/09), documentos
> `doc_dev/planejamento/26-levantamento-paridade-v1-v2.md` §3.5b e
> `27-mapa-telas-rotas-v2.md`.
> **Natureza:** correção, não feature. Tudo aqui já roda em produção **fazendo
> coisa diferente do que a v1 fazia**. Nenhuma tela nova; nenhum RPC de borda.
> **Escala:** MEDIUM · **Risco:** alto em E2 (mexe no coração do pipeline).

---

## Por que esta fase vem antes de tudo

As fases N9–N11 acrescentam o que falta. Esta conserta o que está errado. Um
grupo de WhatsApp criando um atendimento por participante, ou um bot respondendo
só ao "oi" de uma rajada de três mensagens, não é lacuna de tela — é a v2
entregando pior do que o sistema que ela vai substituir. Enquanto isso existir,
o cutover (N12) não pode acontecer, e qualquer tela nova é construída sobre um
comportamento que vai mudar embaixo dela.

O custo é baixo: cinco etapas, todas em servidor, sem contrato novo com o
cliente.

---

## E1 — Descartar mensagem de grupo na ingestão

### O defeito

`domain_whatsapp::NormalizedMessage` tem o campo `is_group` (preenchido em
`lib.rs:83` a partir de `data.isGroup`, com o `participant` virando `sender_jid`)
e **nenhum consumidor o lê** — `grep is_group server/apps` não retorna nada.

A v1 descartava explicitamente, com dois níveis de proteção
(`webhook.py:158-191`):

```python
if self._is_group_message(envelope):      # envelope.contact.is_group()
    return ...                            # e fallback por JID:
if jid.endswith("@g.us"):                 # se is_group() falhar
    return ...
```

E o comentário da v1 diz o porquê: *"o `push_name` nesses eventos é do remetente
do grupo, não do contato"*. Na v2, cada participante que escrever num grupo abre
um atendimento individual com o nome errado, resolve um contato errado, e o bot
responde no grupo.

### O que fazer

**Onde:** `webhook_ingress`, não no worker. O princípio 1 do projeto diz que o
webhook não executa regra pesada — mas descartar evento que não é para ingerir
não é regra de negócio, é filtro de ingestão, e é onde a whitelist já vive
(`main.rs:470-530`). Descartar antes do bus evita gravar lixo no stream.

1. `NormalizedMessage` já expõe `is_group`. No fluxo de `is_msg_event`, após a
   normalização e **antes** do publish, checar:
   - `msg.is_group == true`, **ou**
   - o `remoteJid` termina em `@g.us` (fallback, igual à v1 — o campo `isGroup`
     depende da versão do Evolution Go e não é garantido).
2. Descartar com `200 OK` (nunca erro: devolver erro faz a Evolution reentregar
   o evento em loop — mesmo raciocínio já aplicado na whitelist, `main.rs:525`).
3. Contador Prometheus `smartcore_webhook_grupo_descartado_total{tenant}`.

**Decisão registrada:** não existe "atendimento de grupo" na v2 — nem agora nem
como opção de configuração. Se um dia houver, será um domínio próprio
(participantes, menções, quem respondeu), não um atendimento individual disfarçado.

### Observabilidade & Auditoria

- **Logs/trace:** `tracing::info!` no span já existente do webhook
  (`event_type` gravado em `main.rs:271`), com campos `motivo="grupo"`,
  `tenant_id`, `trace_id`. **Nível INFO, não WARN**: descartar grupo é o
  comportamento correto e esperado, não anomalia — WARN aqui poluiria o alerta.
- **Auditoria:** **sem evento de `audit_log`** — intencional. Não é acesso a
  dado sensível nem mutação de estado; é filtro de ingestão. A v1 também só
  logava. O contador de métrica cobre a necessidade de visibilidade.
- **Sanitização:** o JID do grupo é PII (identifica participantes). Logar
  **mascarado** (mesma função de máscara de telefone já usada no ingress) ou
  apenas o sufixo `@g.us`. Nunca logar o `push_name` nem o conteúdo.

### Testes

- Evento com `isGroup: true` → descartado, nada publicado no bus.
- Evento com `isGroup` ausente e `remoteJid` terminando em `@g.us` → descartado
  (prova o fallback).
- Evento normal → publicado (regressão: o filtro não pode comer mensagem boa).
- Grupo **não** incrementa o contador de rate-limit nem consome idempotência.

---

## E2 — Buffer de agregação por contato (substitui o lock "primeiro ganha")

### O defeito

`worker/src/main.rs:1067-1092`:

```rust
// 4. Aplica o debounce de 2 segundos para regras do Bot/Kanban
let lock_key = format!("tenant:{}:lock:debounce:{}", tenant_uuid, msg_normalized.sender);
let set_res: Result<bool, _> = redis::cmd("SET")
    .arg(&lock_key).arg("1").arg("NX").arg("EX").arg(2)  // 2 segundos, fixo
    .query_async(&mut conn).await;
// ...
if is_debounce_winner { /* só a PRIMEIRA mensagem responde */ }
```

A v1 faz o oposto (`message_buffer.py` + `_compile_message_content`): acumula os
envelopes do contato numa chave de cache, agenda uma task, dorme `TIME_CACHE`
(default 5 s, **configurável por tenant** via `SERVICEHUB`), e então compila:

```python
return {"content": "\n".join(texts), ...}   # todas as mensagens da janela
```

**Efeito prático da divergência:** o cliente que escreve "oi" → "quero saber o
preço" → "do produto X" recebe, na v1, uma resposta ao conjunto; na v2, uma
resposta ao "oi". As outras duas entram no histórico e só influenciam a
*próxima* pergunta.

### O que fazer

Trocar o lock por um **buffer com janela deslizante**, mantendo as duas
garantias que o lock dava de graça (e que um buffer ingênuo perde):

**Estrutura no Redis** (Redis de cache, `REDIS_URL` — não o de barramento;
`state.redis_conn` já é o certo, ver comentário em `main.rs:141`):

- `tenant:{t}:buf:{sender}` — **LIST** com os payloads normalizados da janela.
- `tenant:{t}:buf:{sender}:timer` — chave `SET NX EX <janela>` que marca "já há
  um processamento agendado". Quem consegue criá-la é o **agendador**.

**Fluxo por mensagem recebida:**

1. Persistir a mensagem (como hoje — persistência **não** entra no buffer;
   toda mensagem continua indo para o banco no ato, e o realtime do chat
   continua imediato).
2. `RPUSH` do payload no buffer + `EXPIRE` de segurança (janela × 10, teto de
   300 s como na v1 — buffer órfão não pode viver para sempre).
3. Tentar criar a chave `:timer`. **Se conseguiu**, este processamento é o
   agendador: aguarda a janela e então drena.
4. Ao drenar: `LRANGE` + `DEL` atômicos (script Lua ou `MULTI/EXEC` — a v1 usa
   lock explícito; aqui o Lua é mais barato e não precisa de segundo lock),
   compila `"\n".join` dos textos **na ordem de chegada**, e segue para a
   barreira de bot com o texto compilado.

**Garantias que precisam sobreviver:**

- **Idempotência**: o lock atual protegia por acaso; o buffer precisa dedupe
  explícito por `message_id` antes do `RPUSH` (a v1 faz exatamente isso em
  `set_buffer_contact`, varrendo o buffer). Como a lista é curta (uma rajada),
  varrer é aceitável.
- **Só o texto agrega**: mídia continua com o pipeline próprio
  (`processar_midia`), e `texto_para_ia()` (`main.rs:1109`) já resolve o caso de
  mídia sem legenda. O buffer junta apenas o que é fala do contato.
- **Nada de `sleep` bloqueante**: a v1 usa `time.sleep()` dentro da task Celery
  porque o `countdown` do Celery quebrava com `acks_late`. Em Rust é
  `tokio::time::sleep` dentro de uma task — **mas** o consumo do stream não pode
  ficar parado esperando. O drenador vai numa `tokio::spawn`, e o handler
  principal retorna (o `XACK` acontece pela persistência, que já ocorreu).
- **Crash durante a janela**: se o worker morrer com buffer cheio, a rajada fica
  no Redis com TTL. Aceitável (a v1 tem o mesmo comportamento), mas registrar:
  o próximo tick que encontrar buffer com `:timer` vencido drena.

**Configuração:** `SMARTCORE_BUFFER_JANELA_MS` (default 5000, para bater com o
`TIME_CACHE` da v1), com override por tenant lido do `RuntimeConfig` no Redis
(mesma cascata que já serve a config de IA — `time_cache` é uma das chaves de
`CoreSettings` da v1, então o ETL da N12 já traz o valor).

### Observabilidade & Auditoria

- **Logs/trace:** span novo `mensagem.buffer` com `tenant_id`, `sender`
  (mascarado), `mensagens_agregadas` (contagem), `janela_ms`. O `trace_id` da
  **primeira** mensagem da janela é o que segue para o `Responder` — e as demais
  registram `link` para ele (`traceparent` como span link), senão a cadeia
  webhook→resposta some para as mensagens 2..n. Nível DEBUG na agregação, INFO
  no drenar.
- **Auditoria:** **sem evento de `audit_log`** — intencional. Agregar mensagem
  não muda estado sensível; o que muda estado (`mensagem.persistida`,
  `bot.respondeu`) já é auditado nos pontos existentes.
- **Sanitização:** o buffer guarda **conteúdo de mensagem no Redis** — é PII em
  repouso. Mitigações: TTL curto (janela × 10), chave por tenant, e **nunca**
  logar o conteúdo agregado (só a contagem). Registrar no plano de segurança que
  o Redis de cache passa a conter PII transitória.

### Testes

- Três mensagens em 1 s → **uma** chamada ao `Responder` com os três textos
  unidos por `\n`, na ordem.
- Mensagem única → comportamento idêntico ao de hoje (regressão).
- Duas mensagens com o mesmo `message_id` → uma só no buffer (dedupe).
- Mensagem fora da janela (após o drain) → abre janela nova.
- Mídia no meio da rajada → não entra no texto agregado; pipeline de mídia roda.
- Falha do Redis → **degrada para o comportamento atual** (responde à primeira),
  nunca perde a mensagem.

---

## E3 — Pesquisa de satisfação (fechar o ciclo que só tem o expirador)

### O defeito

`oraculo_atendimento.avaliacao` e `.feedback` existem desde a migration 0006 e
**só aparecem em SELECT** (`atendimentos.rs`: linhas 273, 299, 327, 513, 628 —
todas listagens). O scheduler roda `processar_feedback_vencido`
(`scheduler.rs:141`) → `ListarAtendimentosFeedbackVencido` → `MarcarFeedbackExpirado`,
com a consulta filtrando `AND avaliacao IS NULL` (`atendimentos.rs:634`).

Ou seja: **a v2 expira um feedback que nunca foi solicitado**. O job roda, acha
todos os atendimentos resolvidos, e marca todos como expirados.

A v1 (`models.py:416-470`): ao finalizar, envia ao contato uma mensagem pedindo
nota de 1 a 5 e comentário; a resposta seguinte do contato é interpretada por
`_check_and_process_feedback` (que chama `analise_avaliacao`, hoje o RPC
`Sentimento`) e grava `avaliacao` + `feedback`.

### O que fazer

**E3.1 — Solicitar.** No caminho de finalização (`SetAtendimentoStatus` quando o
status resultante é terminal, e `MoveAtendimentoEtapa` para coluna de
`finalizacao` — os dois convergem em `status_do_tipo_etapa`), criar a mensagem
de solicitação **na mesma transação** do movimento, com `remetente="bot"` e
evento no outbox. É exatamente o padrão já usado pela saudação ao assumir
(commit `cf30905`) — reaproveitar a mecânica, que já está provada.

- Texto configurável por tenant: chave nova `msg_pesquisa_satisfacao` no
  `TenantConfig`/`CoreSettings` (a v1 tinha o texto **fixo no código**, com
  "Ecoprint" dentro — não repetir esse erro). Default no código, cascata igual
  à dos demais prompts (migration 0026).
- Marcar no atendimento que a pesquisa foi enviada — coluna nova
  `feedback_solicitado_em TIMESTAMPTZ`. Sem ela não há como distinguir "não
  respondeu" de "nunca foi perguntado", que é o bug de hoje.
- **Não solicitar** quando: o desfecho é `cancelado` ou `arquivado` (não se pede
  nota de atendimento que o cliente desistiu ou que foi arquivado
  administrativamente); o contato está fora da whitelist; ou o tenant desligou a
  pesquisa (flag `pesquisa_satisfacao_ativa`).

**E3.2 — Interpretar.** A próxima mensagem do contato num atendimento com
`feedback_solicitado_em` preenchido e `avaliacao IS NULL` é candidata a resposta
da pesquisa:

- Extrair nota 1–5: primeiro por regex simples (dígito isolado, "nota 4",
  "⭐⭐⭐⭐"); se não casar, chamar `Sentimento` do `ia_engine` (que já devolve
  `nota`, `sentimento` e `feedback`) e usar a nota dele.
- Gravar `avaliacao` + `feedback` (o texto do cliente, íntegro).
- Janela: só vale dentro do TTL do scheduler
  (`SMARTCORE_SCHEDULER_FEEDBACK_TTL_HORAS`, hoje 48). Fora dela, a mensagem é
  uma conversa nova, não resposta de pesquisa.

**E3.3 — Corrigir o expirador.** `ListarAtendimentosFeedbackVencido` passa a
exigir `feedback_solicitado_em IS NOT NULL` — sem isso continua expirando o que
não foi pedido. Migration nova para a coluna + ajuste da query e do `.sqlx`.

### Observabilidade & Auditoria

- **Logs/trace:** spans `atendimento.pesquisa_enviada` e
  `atendimento.feedback_recebido` com `tenant_id`, `atendimento_id`, `nota`
  (número), `origem` (`regex` | `ia`). Nunca o texto do feedback no span.
- **Auditoria:** **sim, dois eventos** — `atendimento.pesquisa_solicitada` e
  `atendimento.avaliado`. Justificativa: a avaliação vira métrica de operação e
  pode embasar decisão sobre atendente; alteração desse dado precisa de trilha.
  Metadados: timestamp UTC, `user_id` (nulo quando é o bot/scheduler),
  `ip_address`/`user_agent` do `RequestContext` quando houver, `event_type`,
  descrição **sem** o texto do cliente (só a nota). O evento de expiração
  (`atendimento.feedback_expirado`) já existe e permanece.
- **Sanitização:** o `feedback` é texto livre de cliente — **PII**. Não vai para
  log, span, métrica nem descrição de auditoria. Fica só na coluna.

### Testes

- Resolver atendimento → mensagem de pesquisa criada na mesma transação, com
  evento no outbox.
- Cancelar/arquivar → **não** solicita (dois testes).
- Tenant com pesquisa desligada → não solicita.
- Resposta "5" / "nota 5" / texto livre → grava `avaliacao` e `feedback`.
- Resposta após o TTL → não vira avaliação; abre conversa nova.
- Atendimento sem `feedback_solicitado_em` → **não** aparece no expirador
  (regressão do bug atual).

---

## E4 — `msg_fallback` e `msg_sem_info` passam a valer

### O defeito

`worker/src/main.rs:1118`:

```rust
const BOT_TEXT_FALLBACK: &str = "Olá! Sou o assistente virtual. Recebi sua mensagem e ela já está na nossa fila de atendimento. Em breve um atendente falará com você.";
```

Usado em três pontos (linhas 1148, 1168 e no caminho de resposta vazia). Enquanto
isso, `msg_fallback` e `msg_sem_info` são configuráveis pelo tenant, publicados
no `RuntimeConfig` do Redis (`config_publisher.rs:40-41`) e presentes no modelo
do `ia_engine` (`config/models.py:59-60`) — **sem nenhum uso**.

É a mesma classe de defeito corrigida em 28/07 para `persona_bot` e
`msg_transferencia`: o tenant configura no painel e o sistema ignora.

### O que fazer

1. **`msg_fallback`** (falha/indisponibilidade da IA) — usado pelo **worker**.
   O worker já lê config do Redis? Não: hoje ele só consulta `ResolverConfigIa`
   para o kill-switch de transcrição (`main.rs:1692`). Duas opções:
   - (a) worker lê o `RuntimeConfig` do Redis diretamente (mesma chave
     `tenant:config:<id>` que o `ia_engine` lê);
   - (b) estende `ResolverConfigIa` para devolver também as mensagens.

   **Escolher (a)**: o RPC existe só por causa do kill-switch e a direção do
   projeto (28/07) foi tirar config do caminho quente. Ler do Redis, com cache
   em RAM invalidado por `tenant:config:invalidate`, é o padrão já estabelecido.
2. **`msg_sem_info`** (RAG não encontrou nada) — é decisão do **`ia_engine`**,
   dentro do `responder_datasource`: quando `dados_treinamento` vem vazio e o
   modelo não tem em que se apoiar. A config já está no `RuntimeConfig` que ele
   lê; falta aplicar, no mesmo lugar onde `msg_transferencia` já é aplicada
   (`usecases.py:170`).
3. Em ambos, o texto do código continua sendo o **último elo** do fallback
   (config vazia → default versionado), como manda o comentário da migration 0026.

### Observabilidade & Auditoria

- **Logs/trace:** o span `bot.degradado` já existe (`main.rs:1141`, 1158);
  acrescentar o campo `origem_texto` = `tenant` | `default`, que é o que permite
  descobrir em produção se a config do tenant está sendo aplicada — foi
  justamente a falta disso que deixou o bug de 28/07 invisível por semanas.
- **Auditoria:** **sem evento** — intencional. Escolher texto de fallback não é
  mutação de estado; a alteração da config em si já é auditada em
  `UpdateTenantConfig`.
- **Sanitização:** as mensagens são texto de negócio, não segredo. Sem risco.

### Testes

- Tenant com `msg_fallback` configurada + IA fora → contato recebe o texto **do
  tenant**.
- Tenant sem `msg_fallback` + IA fora → recebe o default do código.
- `msg_sem_info`: teste no `ia_engine` inspecionando o prompt/resposta com
  `dados_treinamento` vazio — no mesmo padrão dos 9 testes de
  `test_config_no_fluxo.py`, que foi como os dois bugs anteriores apareceram.

---

## E5 — Consumir `CONNECTION` (e decidir sobre `PRESENCE`/`CONTACTS`)

### O defeito

`webhook_ingress` normaliza e publica quatro famílias de evento
(`canonical_event`, `main.rs:620-650`): `CONNECTION`, `MESSAGE_UPDATE`,
`PRESENCE`, `CONTACTS`. O worker roteia **duas**
(`despachar_evento`, `main.rs:710-720`): `message.received` e
`whatsapp.message.status`. As outras caem no `_ => Ok(())`.

Consequência: `whatsapp_instance.connection_state` só muda quando alguém
**consulta** o status (`data_whatsapp/main.rs:662`) ou no bulk disconnect
(linha 1002). Se a conexão cair às 2h da manhã, o painel só descobre quando um
humano abrir a tela — e o alerta de "conexão caída" que o painel do tenant
promete (`0 de 2 conexões`) chega tarde.

### O que fazer

1. **`CONNECTION`** → novo handler `processar_estado_conexao`: chama
   `AtualizarEstadoInstancia` (RPC que já existe) com o estado do payload,
   publica evento de realtime no canal do tenant (`tenant:{id}:events`) para o
   painel reagir sem refresh, e audita.
2. **`CONTACTS`** → atualizar `whatsapp_contact` (nome de perfil, foto). É a
   metade barata da lacuna de perfil; a outra metade (`GetWhatsappProfilePicture`
   sob demanda) fica na **N11.7**. Se o payload do Evolution Go não trouxer a
   foto — verificar no `info_aux` —, esta parte cai para a N11.7 inteira.
3. **`PRESENCE`** → é a presença **do contato** ("digitando"), que só tem valor
   com a UI da **N9.4**. Nesta fase: consumir e publicar no realtime, **sem
   persistir** (presença é efêmera; gravar seria lixo). Se a N9 ainda não
   existir, o evento é publicado e ninguém escuta — custo zero e o caminho fica
   pronto.

### Observabilidade & Auditoria

- **Logs/trace:** spans `whatsapp.conexao_mudou` (com `instance_id`,
  `estado_anterior`, `estado_novo`), `whatsapp.contato_atualizado`. Presença
  em DEBUG — é alto volume e não vale INFO.
- **Auditoria:** **sim** para conexão — `whatsapp_instance.state_updated` já
  existe como `event_type` (`data_postgres/main.rs:6452`) e passa a ser emitido
  também por este caminho. Queda de conexão é evento operacional crítico: é o
  que explica "por que paramos de receber mensagem às 2h". Metadados: instância,
  estado anterior e novo, origem (`webhook` vs `consulta`). **Sem auditoria**
  para presença (efêmero, alto volume) — intencional.
- **Sanitização:** payload de `CONTACTS` traz telefone e nome — mascarar o
  telefone no log; nome de perfil não vai para log.

### Testes

- Evento `CONNECTION` com `disconnected` → `connection_state` atualizado sem
  ninguém consultar + auditoria emitida.
- Evento de conexão para instância inexistente → ignora sem erro (não pode
  derrubar o consumo do stream).
- `PRESENCE` → publicado no realtime, nada persistido.
- Regressão: `message.received` e `whatsapp.message.status` seguem funcionando
  (o `match` novo não pode capturar o que já funciona).

---

## Sequência e dependências

```
E1 (grupo)      ──┐
E4 (msg_*)      ──┤  independentes, podem ir em qualquer ordem
E5 (CONNECTION) ──┘
                  │
E2 (buffer) ──────┴──► maior risco: fazer com E1 já mergeado
                       (menos ruído no pipeline durante o teste)
E3 (satisfação) ─────► depende de E2 apenas por conflito de área
                       (ambos tocam o fluxo de mensagem recebida)
```

**Ordem recomendada:** E1 → E4 → E5 → E2 → E3.
E1/E4/E5 são pequenas e destravam confiança no pipeline antes da mudança
grande. E2 é a que exige atenção total.

## Riscos

| Risco | Mitigação |
|---|---|
| **E2 quebrar a idempotência** que o lock garantia | dedupe explícito por `message_id` no `RPUSH` + teste de mensagem repetida |
| **E2 perder mensagem** em crash do worker | TTL no buffer + drenagem de buffer órfão no tick seguinte; persistência acontece **antes** do buffer |
| **E2 atrasar a resposta** (janela de 5 s vs 2 s de hoje) | é o comportamento da v1, intencional; janela configurável para ajustar em produção |
| E1 descartar mensagem legítima | fallback duplo (campo + sufixo do JID) e teste de regressão com mensagem normal |
| E3 interpretar conversa nova como nota | janela de TTL + exigir `feedback_solicitado_em` |
| E5 inundar o realtime com presença | presença em DEBUG, sem persistência, e sem retransmissão para quem não tem a conversa aberta |

## Definition of Done

- [ ] Grupo não gera atendimento (validado com evento real de grupo).
- [ ] Três mensagens seguidas geram **uma** resposta ao conjunto.
- [ ] Encerrar atendimento envia a pesquisa; a nota do cliente fica gravada.
- [ ] Atendimento não solicitado não é marcado como expirado.
- [ ] `msg_fallback`/`msg_sem_info` do tenant aparecem na conversa.
- [ ] Derrubar a conexão reflete no painel sem abrir a tela de conexões.
- [ ] `cargo fmt` + `clippy -D warnings` + `sqlx prepare --check` verdes.
- [ ] Suíte via `.\infra\test-local.ps1`; nenhum teste existente quebrado.
- [ ] Comentários em pt-br; nenhum segredo/PII em log.
