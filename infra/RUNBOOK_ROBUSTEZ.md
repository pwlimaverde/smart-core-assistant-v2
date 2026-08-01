# Robustez do servidor: backup, sondas, watchdog e auditoria

Quem lê isto quer uma de três coisas: **entender o que acontece quando um
serviço trava**, **restaurar o banco**, ou **saber onde os alertas caem**.

## O problema que isto resolve

`restart: unless-stopped` só reage a processo que **morre**. Serviço travado —
deadlock, pool de conexões esgotado, loop de consumo parado — ficava `running`
para sempre. A stack de pé, sem funcionar, e nada acusando.

Pior: a queda de um serviço era **invisível para o alerting**. As métricas chegam
por push (OTLP), então quando um serviço morre a série dele *some* em vez de ir a
zero — e alerta sobre série ausente não dispara.

Três peças fecham isso:

```
  sonda por serviço  →  watchdog reinicia + audita  →  alerta chega em alguém
  (healthcheck)         (e publica service_up)         (webhook/e-mail)
```

## As sondas

Cada serviço tem a sonda que faz sentido para o que ele é:

| Serviço | Como é sondado | Por quê |
|---|---|---|
| `data_postgres`, `data_redis`, `data_storage`, `data_whatsapp`, `control_plane`, `runtime_api` | `healthcheck rpc <SERVICO>` — PING→PONG no `transport` | Testa o caminho inteiro (aceitar, ler frame, responder), não só a porta aberta |
| `worker` | `healthcheck batimento` — idade do arquivo que o loop de consumo toca | Não atende ninguém; "porta respondendo" não existe para ele |
| `webhook_ingress` | `curl /health` | HTTP puro (axum), fora do `transport` |
| `ia_engine` | `grpc.health.v1` | Já existia — foi o modelo para os demais |
| `pg_backup` | idade do último backup **bem-sucedido** | Passa o dia dormindo; "processo vivo" não diz nada |
| `postgres`, `redis`, `redis-bus` | `pg_isready` / `redis-cli ping` | — |
| `web`, `web-tenant`, `minio` | só o estado do container | Servem estático e não dependem de nada; uma sonda cujo comando não exista na imagem seria pior que nenhuma — deixaria o container `unhealthy` para sempre e o watchdog reiniciando à toa |

**Por que o PING e não um TCP simples:** um processo travado ainda deixa o
listener do sistema operacional aceitando conexões. Um teste de porta passaria e
o serviço continuaria marcado como saudável. O PING exige que a aplicação
responda.

**Por que o batimento do worker fica dentro do loop:** ele é registrado logo
depois do read do Redis retornar. Um batimento disparado por um timer paralelo
continuaria fresco com o consumo travado — que é exatamente a falha a enxergar.

## O watchdog

O compose **marca** um container como `unhealthy` e não faz nada com isso —
reiniciar não saudável é comportamento de Swarm/Kubernetes, não de compose. O
watchdog fecha esse laço.

A cada 30 segundos ele inspeciona os containers do próprio projeto e:

1. reinicia o que está `unhealthy` ou parado, e **audita** (`service.reiniciado`,
   com o motivo e a última saída da sonda);
2. registra a volta ao normal (`service.recuperado`);
3. depois de **3 tentativas em 15 minutos**, desiste, emite
   `service.restart_desistido` e silencia. Reinício infinito consome o host e
   disfarça de instabilidade o que é defeito permanente;
4. publica `smartcore_service_up{servico}` — a métrica que dá ao alerting um zero
   concreto, já que ele está vivo para publicá-lo.

Ele também registra **crash-loop** (`service.reiniciou_sozinho`) sem intervir: o
container sobe, morre e o Docker reergue por conta própria. Intervir ali
atropelaria o backoff do Docker, mas o ciclo precisa aparecer em algum lugar —
antes, sumia assim que o deploy terminava.

Eventos na auditoria: `watchdog.iniciado`, `service.nao_saudavel`,
`service.reiniciado`, `service.restart_falhou`, `service.recuperado`,
`service.restart_desistido`, `service.reiniciou_sozinho`, `watchdog.encerrado`.

**Escopo.** `SMARTCORE_WATCHDOG_PROJETO` define de quem ele cuida. É essencial:
dev, prod, evolution e observabilidade convivem no mesmo host, e sem o recorte
ele mexeria em containers de outras stacks. Ele roda como `root` porque falar com
`/var/run/docker.sock` exige — a contenção real é o escopo, não o usuário.

## Tarefas críticas e panics

Um panic dentro de `tokio::spawn` mata só aquela task: o processo segue vivo e a
funcionalidade some sem deixar rastro. Duas mudanças:

- **Hook global de panic** em todos os serviços: o panic vira log estruturado
  (antes saía como texto solto no stderr, que no Loki é uma linha sem campos).
  Ele **não** aborta o processo — abortar em qualquer panic transformaria um
  panic num handler de requisição em queda do serviço inteiro.
- **`observability::supervisionar`** para as tasks cujo término é falha por
  definição: `outbox_relay`, `consumidor_auditoria` e `reprocessamento_pel` no
  `data_postgres`. Se uma delas cai, o evento é auditado
  (`service.tarefa_critica_encerrada`) e o processo sai com **código 1** — o
  container morre, o Docker reinicia, e o serviço volta com todos os loops.

Antes, o `data_postgres` saía com código **0** quando o relay terminava:
indistinguível de parada limpa.

## Parada limpa

Nenhum dos serviços escutava SIGTERM — todo deploy matava conexões em voo e
perdia os spans ainda não exportados, justamente os do encerramento. Agora todos
tratam SIGTERM e chamam `shutdown_telemetry()`. O `webhook_ingress` usa
`with_graceful_shutdown`: um webhook do WhatsApp cortado no meio é mensagem de
cliente perdida.

## Backup do banco

O serviço `pg_backup` roda dentro do compose — e não como cron do host — para ser
instalado pelo deploy junto com a stack. Cron do host é passo manual, e passo
manual é o que não existe no servidor novo.

- Um dump na subida (ponto de restauração a cada release) e depois a cada
  `BACKUP_INTERVALO_SEGUNDOS` (dev: 24h; prod: 12h).
- Formato custom (`-Fc`): comprimido, restaurável por tabela e **verificável**.
  Todo dump passa por `pg_restore --list` antes de ser aceito.
- Grava em `.parcial` e só renomeia no fim: dump interrompido nunca aparece com
  nome de backup bom.
- Retenção por idade **e** por quantidade.

### Restaurar

```bash
./infra/restore-postgres.sh dev                          # lista os backups
./infra/restore-postgres.sh dev smartcore-<data>.dump     # ensaio, não altera nada
./infra/restore-postgres.sh dev smartcore-<data>.dump --confirmo
```

Sem `--confirmo` o script só mostra o que faria. A restauração é destrutiva:
recria o schema `public`.

> **Restaure em dev de tempos em tempos.** É o único jeito de descobrir que o
> dump presta antes de precisar dele.

### O que ainda falta

O backup é **local ao host**. Ele cobre erro de aplicação, migration ruim e
exclusão acidental — não cobre perda do servidor inteiro. Cópia off-site
(R2/S3) é o próximo passo e não está implementada.

## Alertas

Regras em `docker/observability/provisioning/alerting/rules.yml`:

| Alerta | Dispara quando |
|---|---|
| Serviço fora do ar | `smartcore_service_up < 1` por 2 min — **ou** sem dado nenhum (aí o próprio watchdog caiu) |
| Backup do banco atrasado | o `pg_backup` não conclui backup na janela |
| Backlog de outbox alto | > 100 eventos por 5 min |
| Lag do bus (PEL) alto | > 500 pendentes por 5 min |
| Taxa de erro RPC alta | > 5% em 5 min |

**Configure o destino, senão nada disso chega em ninguém.** O contact point
apontava para `ops@smartcore.local` — endereço inexistente, sem SMTP. Agora:

```bash
cd docker/observability
cp .env.example .env
# preencha SMARTCORE_ALERTA_WEBHOOK_URL (Discord/Slack/n8n) ou o SMTP
docker compose --env-file .env up -d
```

## Rotação de log e limites de memória

Duas linhas que faltavam nos composes e derrubam VPS com regularidade:

- **`logging`**: o default do Docker é ilimitado. Disco cheio derruba a stack
  inteira, não só quem escreveu demais.
- **`mem_limit`**: sem teto, um vazamento em qualquer serviço mata o **host** por
  OOM em vez de só o processo culpado.

Ambos parametrizados no `.env` (`LOG_MAX_*`, `MEM_*`). Ajuste os `MEM_*` à RAM da
VPS: a soma dos limites precisa caber com folga.

## Cobertura de auditoria

Rotas que passaram a auditar nesta rodada:

| Evento | Por quê |
|---|---|
| `audit_log_consultado` | Ler o log de auditoria é evento auditável de primeira ordem — é o que denuncia alguém vasculhando dados de tenant. O registro de acesso não registrava o próprio acesso. |
| `contato_gravado` | Grava dado pessoal de terceiro. O telefone **não** vai no evento: registra-se que houve gravação, não se republica o dado protegido. |
| `signup_plan_selected` | `StartSignup` e `ActivateSignup` já auditavam; o passo do meio, onde se decide o que o cliente paga, não. |
| `dead_letter_reprocessada` | Reinjeta mensagem que já falhou, podendo gerar envio ao cliente. |
| `vouchers_listed`, `voucher_redemptions_listed` | O código do voucher fica em claro; a defesa é rate limit + revogação + rastro de quem leu, e a terceira perna faltava. |

### O bug de barramento que apareceu no caminho

O `worker` era o **único** serviço que usava `REDIS_URL` para o barramento —
todos os outros usam `REDIS_BUS_URL`, e dev e prod sobem duas instâncias
separadas (`redis` e `redis-bus`). Consequência, com as duas distintas:

- consumia `events:stream` de um Redis onde ninguém publica;
- publicava auditoria num Redis que ninguém lê — **todos os eventos do worker**
  (`bot.respondeu`, `atendimento.transferido_por_ia`, `mensagem.*`, `midia.*`)
  nunca chegavam ao `audit_log`;
- publicava o realtime (`tenant:<id>:events`) onde o `RealtimeManager` do
  `runtime_api` não escuta — o painel não atualizava sozinho.

Corrigido: o worker agora abre as duas conexões, cache (`REDIS_URL`, só o lock de
debounce) e barramento (`REDIS_BUS_URL`, consumo + auditoria + realtime), com
fallback para uma instância só em ambientes de teste.

> **Vale confirmar em dev**: se o `dev.env` do servidor já apontava as duas
> variáveis para o mesmo Redis, nada disso se manifestava e a correção é
> preventiva. Se apontava para instâncias distintas, o bot não respondia e o
> painel não atualizava — e isso passa a funcionar agora.

## O que continua em aberto

- **Backup off-site.** O dump vive no mesmo host do banco.
- **Métricas de host.** Sem `node_exporter`/`cAdvisor`: CPU, RAM e **espaço em
  disco** não são observados. Disco cheio é a causa mais comum de queda em VPS e
  hoje só é percebido pelo efeito.
- **Verificação de e-mail no cadastro** e **job de limpeza de cadastros
  abandonados** (ver `RUNBOOK_CADASTRO_TENANT.md`).
