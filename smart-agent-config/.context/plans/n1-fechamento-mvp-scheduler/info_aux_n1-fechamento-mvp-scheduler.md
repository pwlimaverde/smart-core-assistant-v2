# Documentação Auxiliar — Fase N1: Fechamento do MVP + Scheduler do Worker

> Gerado em: 2026-07-06
> Plano canônico: `.context/plans/n1-fechamento-mvp-scheduler.md`
> Plano completo: `.context/plans/n1-fechamento-mvp-scheduler/plano_completo_n1-fechamento-mvp-scheduler.md`
> Origem do plano-base: `doc_dev/planejamento/16-fase-N1-fechamento-mvp-e-scheduler.md`

## Libs Rust (todas USAR LOCAL — central `doc_dev/libs/rust/`, versões batem com `server/Cargo.toml`)

| Lib | Versão | Verificação | Uso na N1 |
|---|---|---|---|
| `tokio` | 1.38 (full) | 2026-05-31 | `tokio::spawn` do loop do scheduler + `tokio::time::interval` para o tick |
| `redis` | 0.25.0 (aio, streams) | 2026-06-10 | lock distribuído por tarefa (`SET NX PX`, padrão do debounce já no worker) + bus |
| `sqlx` | 0.9 | 2026-06-10 | queries dos RPCs de varredura (`ListarAtendimentosFeedbackVencido`, `ListarMidiasExpiradas`) — sempre via `data_postgres` (porta única do banco) |
| `tracing` | 0.1.40 | 2026-05-31 | span `scheduler.tick`; política: `#[instrument(skip_all)]` em repositórios de tenant |
| `chrono` | 0.4 (serde) | 2026-05-31 | cálculo de idade/TTL (`Utc::now() - Duration`) |
| `tonic` | 0.14.6 | 2026-06-04 | novos RPCs no `data_postgres` (handlers sobre repositórios existentes) |

Padrões relevantes já documentados na central:
- `tokio.md`: preferir `interval.tick().await` em loop dedicado a `sleep` encadeado (drift).
- `redis.md`: conexões `multiplexed` para comandos; a regra do projeto de conexão dedicada para pub/sub não se aplica ao lock (comando simples).

## Serviços Externos

### Grafana — provisionamento como código (N1.4)
Fonte: [grafana.com/docs — provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) e [alerting file provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/), coletado em 2026-07-06.

**Dashboards** — YAML em `provisioning/dashboards/`:

```yaml
apiVersion: 1
providers:
  - name: 'smartcore'
    type: file
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

- `uid` **fixo** em cada JSON de dashboard (URLs estáveis e referências de alerta).
- `allowUiUpdates: false` → dashboards são código; edição só via arquivo.

**Datasources** — YAML com `uid` fixo (obrigatório para os alertas referenciarem):

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    uid: prometheus
    editable: false
  # idem loki (uid: loki) e tempo (uid: tempo)
```

**Alerting** — YAML em `/etc/grafana/provisioning/alerting/`:

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: smartcore-core
    folder: smartcore
    interval: 60s
    rules:
      - uid: outbox-backlog-alto
        title: Backlog de outbox alto
        condition: A
        for: 5m
        noDataState: NoData
        execErrState: Alerting
        labels: { severidade: critica }
        annotations: { resumo: "Outbox acumulando eventos" }
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: 'smartcore_outbox_backlog > 100'
```

- Recursos provisionados **não são editáveis pela UI**; recarga via restart ou Admin API.
- Notification policies provisionadas **sobrescrevem a árvore inteira** — versionar completa.
- p95 de latência: `histogram_quantile(0.95, sum(rate(<histograma>_bucket[5m])) by (le, rpc))`.

### Evolution API (envio outbound — N1.3)
Já coletada em ciclos anteriores — ver `.context/plans/archive/camada-mensageria-whatsapp-evolution-go/info_aux_camada-mensageria-whatsapp-evolution-go.md`. O envio reusa `data_whatsapp::SendWhatsappMessage` (nenhuma chamada HTTP nova é criada na N1).

## Grupo C — Observabilidade e Auditoria (por tarefa)

| Tarefa | Logs/trace | Auditoria | Sanitização |
|---|---|---|---|
| N1.1 merge/validação | — (sem código novo) | — | — |
| N1.2 scheduler | span `scheduler.tick` (trace_id novo por tick; contadores de vencidos/purgados); spans nos RPCs de varredura | `atendimento.feedback_expirado` (INFO); `midia.purgada` (INFO, gravada pelo consumidor no `data_storage`); varredura vazia **não** audita | só ids/contadores; nunca conteúdo/telefone |
| N1.3 outbound atendente | span no consumidor do evento de envio; `status_envio` como campo estruturado | `mensagem.envio_falhou` (WARN, sem conteúdo) | nunca logar payload/telefone completo/token de instância |
| N1.4 dashboards | n/a (consome telemetria existente) | sem evento de auditoria (intencional — só leitura de métricas) | dashboards não exibem PII (labels só com ids) |

## Notas Gerais
- O consumidor de purga (`data_storage`, `processar_purga_midia`) **já existe** — N1.2 apenas publica o evento.
- Lock Redis por tarefa evita disparo duplo com múltiplas réplicas do worker.
- Idempotência: marcação `purge_requested_at`/estado + `LIMIT` por lote.
