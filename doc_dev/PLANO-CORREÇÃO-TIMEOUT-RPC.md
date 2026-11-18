# Plano de correção — incidente de timeout RPC de 2026-11-16

Branch: `fix/incidente-16nov-resiliencia-bus` · Revisão do diagnóstico em
[`DIAGNÓSTICO-INCIDENTE-16NOV.md`](./DIAGNÓSTICO-INCIDENTE-16NOV.md) (ver a errata no topo)

## 1. Resumo executivo

**O que aconteceu.** Às 05:00:39 de 16/11 o worker ficou ~6s sem emitir nenhum log.
Duas RPCs ao `data_postgres` (`UpdateMessageStatus` e o registro da decisão da IA)
estouraram o prazo de 5s. As respostas chegaram 1 ms depois do prazo ("Resposta
recebida sem chamada pendente"). Um evento `whatsapp.message.status` voltou para a
PEL e às 05:03:18 o reprocessador periódico o reclamou e concluiu. O worker seguiu
processando normalmente antes, durante e depois.

**O que os dados descartam:**

| Hipótese do diagnóstico anterior | Evidência | Fonte |
|---|---|---|
| Pool PG esgotado (5 conexões) | Pico de `smartcore_pg_pool_in_use` em 7 dias: **2** | Prometheus |
| Query lenta (~2,8s) | `UpdateMessageStatus` p99 no servidor: **24 ms**, 754 chamadas, 0 erros em 2 dias | Prometheus |
| Cascata de retries | **5** linhas de timeout em 4 dias (3 delas do storage, em 15/11) | Loki |
| 10.003 mensagens acumuladas | É o `MAXLEN ~10000` do `events:stream`, que retém eventos já confirmados | `transport::bus::MAXLEN_APROX` |
| Loop infinito na PEL | O desenho limita em 5 entregas e depois manda para a DLQ (`varrer_dlq_pendentes`) | código |
| 22 dias sem alerta | O intervalo foi de 16/11 a 18/11 | datas |

**O que estava errado de fato** e é o que este plano corrige:

1. **A PEL do worker não era medida.** `smartcore_bus_pending` lia apenas
   `security:stream / data_postgres_audit_group`. O alerta `bus-pending-alto` vigiava
   o grupo errado: um worker travado acumularia mensagens de cliente sem nenhum sinal.
2. **Timeout no cliente era invisível.** `smartcore_rpc_total` é medido no servidor,
   que registrou essas chamadas como sucesso. Nada contava o lado de quem chamou.
3. **Sem proteção contra dependência fora do ar.** Com o `data_postgres` caído, cada
   evento queimaria as 5 entregas e iria para a DLQ: perda silenciosa de mensagem.
4. **Sem lag, idade de pendente, DLQ nem utilização do pool** como métrica alertável.

A causa do travamento de ~6s segue em aberto. Não foi o backup (que roda às 23:05),
e nenhum outro serviço registrou nada na janela. Hipótese: pausa no host (2 vCPU
compartilhadas). Ver §7.

## 2. Mudanças no código (Rust)

Os caminhos pedidos originalmente (`crates/data_postgres/src/client.rs`,
`crates/data_postgres/src/pool.rs`, `crates/resilience/`, `crates/observability/src/metrics.rs`)
não existem no repositório. As mudanças foram feitas onde o código de fato mora,
**sem dependência nova e sem crate nova**. Crate nova exigiria mexer no `Cargo.lock`
sem poder rodar `cargo` no servidor.

| Arquivo | Mudança | Racional |
|---|---|---|
| `server/crates/transport/src/disjuntor.rs` (novo) | `Disjuntor` com 3 estados. 5 falhas em 60s abrem; após 60s passa a meio-aberto; 2 sucessos fecham; uma falha no meio-aberto reabre. `LIMIAR=0` desliga. Exporta `smartcore_disjuntor_estado{dependencia}` (0/1/2) e `smartcore_disjuntor_aberturas_total`. 9 testes unitários com relógio injetado. | Só falha de **transporte** conta (timeout, conexão). Erro de negócio prova que a dependência respondeu. |
| `server/crates/transport/src/runtime.rs` | `MuxClient::com_disjuntor`. `call` passa a contar `smartcore_rpc_cliente_falha_total{method,motivo}` e a alimentar o disjuntor. Teste de ponta a ponta: servidor real lento, 5 prazos expirados abrem o disjuntor, e o cliente continua aceitando chamadas. | Fecha a lacuna 2. O cliente **não** rejeita chamadas com o disjuntor aberto (ver a linha abaixo). |
| `server/crates/transport/src/bus.rs` | `Consumer::com_disjuntor`: antes de cada `XREADGROUP`, se o disjuntor estiver aberto, espera. Enquanto espera, continua batendo o liveness. | **Decisão central:** num consumidor de stream, *fail-fast* devolve o evento à PEL e acelera a ida para a DLQ. Segurando a leitura, o evento fica no stream e aparece como lag, que tem alerta. O liveness continua batendo porque reiniciar o worker não traz o Postgres de volta. |
| `server/apps/worker/src/main.rs` | Cria o disjuntor `data_postgres` (`SMARTCORE_WORKER_DISJUNTOR_*`), liga ao `pg_client` e ao consumidor, e **adia o reprocessamento da PEL** enquanto ele estiver aberto. Prazo padrão das RPCs vira `SMARTCORE_WORKER_RPC_TIMEOUT_MS` (default **5000**, igual ao atual). | Lacuna 3. Ver §2.1 sobre o prazo. |
| `server/apps/data_postgres/src/lag_filas.rs` (novo) + `main.rs` | O amostrador (30s) passa a cobrir `events:stream/worker_group` **e** `security:stream/data_postgres_audit_group`. Exporta `smartcore_bus_pending{stream,grupo}`, `smartcore_bus_lag{stream,grupo}` (via `XINFO GROUPS`), `smartcore_bus_pendente_mais_antigo_segundos{stream,grupo}` e `smartcore_bus_dlq_tamanho`. `smartcore_outbox_backlog` não muda. Em falha de leitura mantém o último valor (antes zerava). | Lacunas 1 e 4. Mesmo nome de métrica para a PEL, agora com labels: os painéis antigos continuam funcionando. |
| `server/crates/observability/src/pool_metrics.rs` | Novo gauge `smartcore_pg_pool_max`. | Denominador da utilização do pool. Sem ele, nenhum alerta de pool era possível. |

Nomes pedidos × nomes adotados (padrão `smartcore_bus_*` já em uso):
`smartcore_consumer_lag` → `smartcore_bus_lag` · `smartcore_pel_size` → `smartcore_bus_pending` ·
`smartcore_rpc_timeout_total` → `smartcore_rpc_cliente_falha_total{motivo="timeout"}` ·
`smartcore_pool_utilization` → `smartcore_pg_pool_in_use / smartcore_pg_pool_max` ·
`smartcore_last_processed_age_secs` → `smartcore_bus_pendente_mais_antigo_segundos`.
"Tempo desde a última mensagem processada" **não** foi criado: com tráfego baixo ele
cresce toda madrugada e viraria ruído. A idade do pendente mais antigo mede a mesma
falha sem esse defeito.

### 2.1 Por que o prazo e o pool NÃO mudaram de valor

- **Prazo RPC 5s → 10s: não aplicado como default, só tornado configurável.** O p99 no
  servidor é 24 ms; 5s já é 200 vezes isso. O que estourou foi uma pausa de ~6s do
  processo, e o próprio sistema se recuperou em 2,5 min. Subir para 10s tem custo
  real: um handler faz várias RPCs em sequência, e o pior caso precisa ficar abaixo do
  piso de reprocessamento da PEL (`MIN_IDLE_REPROCESSAMENTO_MS` = 120s). Acima disso o
  reprocessador pega um evento ainda em voo e o bot responde duas vezes ao cliente.
  Para subir, defina `SMARTCORE_WORKER_RPC_TIMEOUT_MS` no `dev.env` depois de conferir
  essa conta.
- **Pool 5 → 15: não aplicado.** A utilização máxima foi 40%. O pool já é configurável
  (`SMARTCORE_PG_POOL_MAX`, `_MIN`, `_ACQUIRE_TIMEOUT_MS`), e agora existe o alerta
  `pg-pool-utilizacao-alta` para dizer *quando* subir, com base em dado.

## 3. Infraestrutura

| Arquivo | Mudança |
|---|---|
| `docker/observability/provisioning/alerting/rules.yml` | `bus-pending-alto` agora agrupa por `stream, grupo`. 6 regras novas (abaixo). |
| `docker/observability/provisioning/dashboards/json/barramento_saude.json` (novo) | Dashboard **"Smart Core v2 - Saúde do Barramento"** (uid `redis-streams-health`), com 20 painéis: lag, PEL, pendente mais antigo, DLQ, disjuntor, pool, mensagens/min, erro RPC no servidor, falhas RPC no cliente e p99 do `data_postgres`. |
| `docker/obs/prometheus-alerts.yml` | **Removido.** Nenhum componente carregava o arquivo (o `prometheus.yml` não tem `rule_files` e a stack não tem Alertmanager), e ele citava métricas inexistentes. Os alertas que chegam ao e-mail são os do Grafana. |
| `.env.example`, `docker/dev/.env.example`, `docker/prod/.env.example` | Variáveis `SMARTCORE_WORKER_RPC_TIMEOUT_MS` e `SMARTCORE_WORKER_DISJUNTOR_{LIMIAR,JANELA_SECS,ESPERA_SECS,SUCESSOS}`, com os defaults. O compose não muda: o worker já recebe o `.env` inteiro via `env_file`. |

### 3.1 Regras novas e limiares

O desenho do sistema define o que é "anormal": o reprocessador reclama da PEL eventos
parados há 120s (tick de 60s) e manda para a DLQ depois de 5 entregas.

| uid | Expressão | Dispara | Sev. |
|---|---|---|---|
| `bus-lag-alto` | `max by (stream, grupo) (smartcore_bus_lag)` | > 100 por 5 min | crítica |
| `bus-pendente-antigo` | `max by (stream, grupo) (smartcore_bus_pendente_mais_antigo_segundos)` | > 900s por 5 min | crítica |
| `disjuntor-aberto` | `max by (dependencia) (max_over_time(smartcore_disjuntor_estado[3m]))` | > 1, imediato | crítica |
| `rpc-cliente-timeout` | `sum by (service_name, method, motivo) (increase(smartcore_rpc_cliente_falha_total[10m]))` | > 10, imediato | alta |
| `dlq-recebendo-eventos` | `max(delta(smartcore_bus_dlq_tamanho[15m]))` | > 0, imediato | alta |
| `pg-pool-utilizacao-alta` | `max(smartcore_pg_pool_in_use / smartcore_pg_pool_max)` | > 0,8 por 5 min | alta |

As regras novas usam `noDataState: OK`: a série só existe depois do deploy, e a
ausência de um serviço inteiro já é coberta por `servico-fora-do-ar`. O incidente de
16/11 (2 timeouts, 1 reprocesso) **não** dispararia nenhuma delas, e isso é o
correto: o sistema se recuperou sozinho em 2,5 min.

## 4. Como testar

**Restrição do servidor:** nada de `cargo build`/`cargo test` no VPS (2 vCPU, 7,8 GB).
Neste servidor só rodou o `rustfmt` (formatação, sem compilação), dentro de um
container limitado. Compilação, clippy e testes ficam com o CI (`.github/workflows/ci.yml`:
`cargo fmt --check`, `clippy --all-targets --all-features -D warnings`,
`cargo test --workspace --lib --bins`).

Testes que o CI vai rodar (todos locais, sem Redis nem Postgres):

- `transport::disjuntor::tests` (9): abre no limiar, não abre com falhas espalhadas,
  passa a meio-aberto após a espera, fecha com 2 sucessos, reabre com falha no
  meio-aberto, sucesso com o disjuntor aberto não o fecha, `LIMIAR=0` desliga,
  leitura do ambiente e `aguardar_liberacao`.
- `transport::runtime::tests::cinco_prazos_expirados_abrem_o_disjuntor_do_cliente`:
  servidor TCP real com handler de 300 ms e prazo de 50 ms. Cinco timeouts abrem o
  disjuntor, e o cliente continua aceitando a 6ª chamada. Reproduz o incidente em escala.
- `data_postgres lag_filas::tests` (4): parse do `XINFO GROUPS` (grupo certo, lag nulo)
  e idade a partir do id do stream.

Na máquina de desenvolvimento:

```bash
cd server
cargo test -p transport disjuntor
cargo test -p transport cinco_prazos_expirados
cargo test -p data_postgres --bin data_postgres lag_filas
cargo clippy --all-targets --all-features -- -D warnings -A clippy::double_must_use
```

Simulação manual do disjuntor no ambiente dev (depois do deploy):

```bash
# 1. derrubar o data_postgres por 2 minutos
docker stop smart-core-v2-dev-data_postgres-1
# 2. no log do worker deve aparecer, em até ~1 min de tráfego:
#    "disjuntor ABERTO" e depois "consumo pausado: disjuntor aberto"
docker logs -f smart-core-v2-dev-worker-1 2>&1 | grep -i disjuntor
# 3. o alerta disjuntor-aberto chega por e-mail; smartcore_bus_lag sobe
docker start smart-core-v2-dev-data_postgres-1
# 4. "disjuntor MEIO-ABERTO" -> "disjuntor FECHADO" -> "consumo retomado"
```

Validar as regras sem esperar incidente (as expressões já foram aceitas pelo
Prometheus em 2026-11-18):

```bash
docker exec smart-core-v2-observability-grafana-1 wget -qO- \
  'http://prometheus:9090/api/v1/query?query=max%20by%20(stream,grupo)%20(smartcore_bus_lag)'
```

## 5. Deploy

| Fase | O quê | Risco | Rollback |
|---|---|---|---|
| 1 | Merge em `dev` → CI → deploy automático. Entram métricas novas (data_postgres, pool, cliente RPC) e o disjuntor (worker). | Baixo: o prazo e o pool não mudam. | Revert do merge. |
| 2 | Disjuntor ativo com o default (5/60s/60s/2). Para desligar sem rebuild: `SMARTCORE_WORKER_DISJUNTOR_LIMIAR=0` no `/opt/smartcore/dev/env/dev.env` e redeploy, ou recriar só o worker depois de conferir o `REDIS_PASSWORD` do `.env`. | Médio: um falso positivo pausa o consumo por 60s. O pior caso é atraso, não perda. | `LIMIAR=0`. |
| 3 | Alertas e dashboard: o `deploy-dev.yml` detecta mudança em `docker/observability/**` e roda `docker compose up -d --force-recreate` na stack. O Grafana relê o provisionamento ao subir. | Nulo. | Revert do YAML. |

Se for aplicar à mão, lembre que o provisionamento entra por bind mount: `up -d`
sozinho **não** recria o container. Use `docker compose up -d --force-recreate grafana`.

### Validação pós-deploy (15 min)

1. `smartcore_bus_lag`, `smartcore_bus_pending` e `smartcore_bus_pendente_mais_antigo_segundos`
   aparecem com `grupo="worker_group"`. Em operação normal: lag ≈ 0, PEL < 10, idade < 5s.
2. `smartcore_pg_pool_max` = 5 e `smartcore_disjuntor_estado{dependencia="data_postgres"}` = 0.
3. Dashboard "Smart Core v2 - Saúde do Barramento" sem painel vazio, exceto o de
   falhas de RPC no cliente: essa série só nasce na primeira falha.
4. Grafana → Alerting: as 6 regras novas aparecem como Normal.
5. Log do worker no boot: `prazo_rpc_ms=5000`, e nenhum "disjuntor desligado".

## 6. Runbook de plantão

**Primeiro passo, sempre:** abra o dashboard "Saúde do Barramento". **Não** rode
`XTRIM` nem `XGROUP DESTROY`: o primeiro apaga histórico, e o segundo faz o grupo
pular eventos que ainda não foram lidos.

| Alerta | Leitura | Ação |
|---|---|---|
| `disjuntor-aberto` | O worker não fala com o `data_postgres` e pausou o consumo. Nenhuma mensagem se perde. | `docker logs smart-core-v2-dev-data_postgres-1 --tail 100`; conferir o Postgres (`docker exec smart-core-v2-dev-postgres-1 pg_isready`). Quando a dependência volta, o worker retoma sozinho. |
| `bus-lag-alto` | O consumidor não está lendo. | Disjuntor aberto? Veja a linha acima. Worker de pé? `docker ps`, `docker logs smart-core-v2-dev-worker-1 --tail 200`. Se travou sem o disjuntor, reinicie o worker: os eventos continuam no stream. |
| `bus-pendente-antigo` | Evento parado fora do ciclo de reprocessamento. | Procure "reprocessador" no log do worker. Inspecione com `XPENDING events:stream worker_group - + 10`. |
| `dlq-recebendo-eventos` | O sistema desistiu de eventos depois de 5 tentativas. | `XRANGE security:dlq - + COUNT 20`: o payload vai junto. Corrija a causa e reenvie manualmente o que for mensagem de cliente. |
| `rpc-cliente-timeout` | Degradação sustentada (> 10 em 10 min). | Veja o `method` no alerta e o painel p99. Pool alto? Veja a linha abaixo. |
| `pg-pool-utilizacao-alta` | O pool está perto do teto. | Queries lentas (`pg_stat_activity`) antes de subir `SMARTCORE_PG_POOL_MAX`. |

Para ler o Redis do bus sem expor a senha:

```bash
C=smart-core-v2-dev-redis-bus-1
P=$(docker inspect $C --format '{{range $i,$a := .Config.Cmd}}{{if eq $i 2}}{{$a}}{{end}}{{end}}')
docker exec -e REDISCLI_AUTH="$P" $C redis-cli XINFO GROUPS events:stream
```

## 7. Checklist pré-deploy

- [ ] CI verde na branch (fmt, clippy `-D warnings`, testes): nada disso foi compilado no servidor.
- [ ] Revisão do `transport::bus::Consumer` (portão) e do `MuxClient::call` (contagem).
- [ ] Conferir no log do deploy que a etapa de observabilidade rodou (`--force-recreate`).
- [ ] E-mail de alerta chegando (SMTP Brevo ativo; o webhook ainda é o valor de exemplo).
- [ ] Simulação do §4 executada no dev, numa janela combinada.

## 8. Riscos residuais e próximos passos

- **Causa do travamento de ~6s indeterminada.** Próximo passo: coletar `node_exporter`
  ou cAdvisor (CPU steal, pressão de memória) para correlacionar a próxima ocorrência.
- **Primeira falha de cada série de contador não entra no `increase()`.** O limiar de
  10 em `rpc-cliente-timeout` absorve isso. `disjuntor-aberto` usa o gauge de estado
  e não sofre do problema.
- **Disjuntor só no caminho worker → `data_postgres`.** `data_whatsapp`, `data_storage`
  e `ia_engine` não têm disjuntor; o `ia_client` já tem retry próprio. Estender quando
  houver evidência.
- **No meio-aberto, todo o tráfego passa**, não só uma sonda. Como o worker processa
  em série, na prática é um evento por vez.
- **Lag nulo** (o Redis não consegue calcular, ex.: após `XDEL` no meio do stream) vira 0.
  O alerta de pendente antigo cobre esse ponto cego.
- **Redis 7+ é requisito** para o campo `lag` (o bus roda 7.4.12).
