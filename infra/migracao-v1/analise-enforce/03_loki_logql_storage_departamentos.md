# LogQL — sinal log-only de `storage`/`departamentos` no Loki

> Confiança: **menor** que os scripts SQL desta pasta. As queries abaixo assumem
> o layout padrão do formatador JSON do `tracing_subscriber` (`fmt::layer().json()`,
> configurado em `server/crates/observability/src/telemetry.rs`) tal como sai no
> stdout do container e é reencaminhado pelo Promtail
> (`docker/observability/promtail-config.yml`) para o Loki
> (`docker/observability/loki-config.yml`). **Confirme os nomes exatos dos campos
> com uma consulta exploratória (`| json` sem filtro de campo) antes de
> automatizar** — o parsing de dois níveis de JSON (o wrapper do log do Docker +
> o JSON emitido pelo tracing) é sensível a detalhes de versão da lib.

## Por que Loki e não SQL aqui

Ao contrário do recurso `instancias` (auditado incondicionalmente em
`audit_log` — ver `02_janela_log_only_audit.sql`), os guards de
`departamentos` (`data_postgres`) e `storage` (`data_storage`) só publicam em
`audit_log` quando `auditar` acompanha a própria flag `SMARTCORE_QUOTA_ENFORCE`
— ou seja, nunca em produção até hoje (log-only = `false` em todo lugar). O
único sinal que existe hoje para esses dois recursos em modo log-only é a linha
`tracing::warn!` estruturada, que só chega ao Grafana LGTM via Loki (não há
contador Prometheus `quota_excedida_total` implementado no código atual — ver
`README.md` desta pasta).

## Gap conhecido: `storage` não carrega `tenant_id`

A linha de log do guard de storage
(`server/apps/data_storage/src/main.rs::aplicar_quota_guard_storage`) é:

```rust
tracing::warn!("quota de storage excedida (log-only; SMARTCORE_QUOTA_ENFORCE=false)");
```

Sem nenhum campo estruturado — nem `tenant_id`, nem `recurso` explícitos no
evento — e a função (nem o handler `handler_put_file` que a chama) está sob
`#[tracing::instrument]`, então não há span ambiente carregando `tenant_id`
para essa linha aparecer nos campos de span do JSON. **Na prática, hoje é
impossível recuperar via log qual tenant excedeu a quota de storage, ou
quantas vezes por tenant** — só dá pra contar quantas vezes o guard disparou no
serviço inteiro, correlacionando por timestamp/proximidade com outras métricas
se necessário. Isso não é um problema de sintaxe de LogQL, é ausência do dado
na fonte. Recomendação: use `01_estado_atual_quotas.sql` (snapshot de hoje,
por tenant, com valores exatos) como fonte primária para `storage` — o log só
serve para contar "quantas vezes o guard disparou no total" como confirmação
de ordem de grandeza. Se quiser recuperar o detalhe por tenant retroativamente,
é necessário adicionar `tenant_id`/`recurso` como campos do evento (mudança de
uma linha, fora do escopo desta tarefa — sinalizar para decisão humana).

O guard de `departamentos`
(`server/apps/data_postgres/src/main.rs`, dentro do handler de criação de
departamento) já inclui `tenant_id` explicitamente no evento:

```rust
tracing::warn!(
    tenant_id = %env.tenant_id,
    "quota de departamentos excedida (log-only; SMARTCORE_QUOTA_ENFORCE=false)"
);
```

então esse recurso É recuperável por tenant via Loki.

## Queries (Grafana Explore, datasource Loki)

Exploratória — confirmar o formato antes de tudo:

```logql
{container=~"smart-core-v2-(dev|prod)-data_storage-1"} | json
```

Contagem de disparos do guard de storage (sem quebra por tenant — gap acima):

```logql
sum(count_over_time(
  {container=~"smart-core-v2-(dev|prod)-data_storage-1"}
  |= "quota de storage excedida"
  [30d]
))
```

Departamentos, com quebra por tenant (ajuste o caminho do campo conforme a
exploratória acima confirmar — o exemplo assume que o `tracing_subscriber`
expõe os campos do evento sob `fields.*`):

```logql
sum by (fields_tenant_id) (count_over_time(
  {container=~"smart-core-v2-(dev|prod)-data_postgres-1"}
  |= "quota de departamentos excedida"
  | json
  [30d]
))
```

Se o parsing automático de `fields_tenant_id` não funcionar de primeira, uma
alternativa mais robusta (não depende do parser JSON aninhado) é usar
`| pattern` ou simplesmente ler a mensagem com `line_format` — mas o caminho
mais confiável continua sendo o `audit_log`/estado atual via SQL sempre que
disponível.

## Recomendação geral

Trate estas queries como **confirmação de ordem de grandeza / frequência**,
não como fonte primária de "por quanto o tenant X excedeu". Para a decisão de
calibração de limite por plano (o objetivo do N8.3), use
`01_estado_atual_quotas.sql` como fonte de verdade — é exato, por tenant, e
não depende de nenhuma lacuna de instrumentação.
