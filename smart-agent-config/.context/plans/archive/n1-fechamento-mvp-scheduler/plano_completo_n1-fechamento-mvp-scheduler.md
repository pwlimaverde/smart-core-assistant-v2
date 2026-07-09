# Plano Completo — Fase N1: Fechamento do MVP + Scheduler do Worker

> **Reestruturado em 2026-07-06** a partir de `doc_dev/planejamento/16-fase-N1-fechamento-mvp-e-scheduler.md`,
> validado contra a central de libs (`doc_dev/libs/`) e docs atuais do Grafana.
> **Canônico:** `.context/plans/n1-fechamento-mvp-scheduler.md` · **Docs auxiliares:** [info_aux](./info_aux_n1-fechamento-mvp-scheduler.md)
> **Objetivo:** consolidar o MVP em dev/produção e fechar a única lacuna estrutural da F4 —
> o **scheduler temporal do `worker`** (timeout de feedback + disparo de purga de mídia).

## Correções aplicadas (reestruturação)

| # | O quê | Por quê | Fonte |
|---|---|---|---|
| 1 | N1.4 detalhado com o **schema atual de provisioning do Grafana** (dashboards YAML + datasources com `uid` fixo + alerting em `provisioning/alerting/` com `apiVersion: 1`/`groups`) | O plano base citava "dashboards como código" sem o formato; alerting provisionado sobrescreve a árvore de notificação inteira e não é editável pela UI — precisa estar no desenho | grafana.com/docs (2026-07-06), ver info_aux |
| 2 | Datasources Prometheus/Loki/Tempo devem ser **re-provisionados com `uid` fixo** antes dos alertas | Regras de alerta YAML referenciam `datasourceUid`; sem uid fixo o provisionamento quebra entre ambientes | idem |
| 3 | Loop do scheduler especificado com `tokio::time::interval` (não `sleep` encadeado) | Evita drift acumulado do tick | `doc_dev/libs/rust/tokio.md` |
| 4 | Nenhuma correção de API nas demais libs | tokio 1.38 / redis 0.25 / sqlx 0.9 / tonic 0.14.6 conferidos com `server/Cargo.toml` e central ✅ | triagem 2026-07-06 |

## 0. Estado real (aterramento — verificado no código em 2026-07-06)

| Área | Arquivo | Estado | Impacto |
|---|---|---|---|
| Loop do `worker` | `worker/src/main.rs:41` | Só consome o bus; **não há tarefa temporal** | N1.2 adiciona loop em `tokio::spawn` |
| Consumidor de purga | `data_storage/src/main.rs:50` (`processar_purga_midia`) | **JÁ consome** purga do bus e remove do R2 | N1.2 só **publica** o evento |
| Outbox relay | `data_postgres/src/outbox_relay.rs:157` | Drena `outbox` (0011) e publica no bus | N1.3 confirma o elo até o envio |
| Envio outbound | `worker/src/main.rs:389` (`SendWhatsappMessage`) | Worker já envia a resposta do bot | N1.3 estende ao atendente |
| Estado do atendimento | `0006_atendimentos.sql` | `status`, `feedback`, `historico_status`, `data_ultima_mensagem` | N1.2 varre feedback vencido |
| Stack Grafana | `docker/observability/compose.yml` | LGTM no ar, **sem dashboards curados** | N1.4 provisiona como código |

## 1. Escopo

**Dentro:** N1.1 merge+validação dev · N1.2 scheduler (F4.3b) · N1.3 elo outbox→outbound do atendente · N1.4 dashboards/alertas.
**Fora:** retenção por política de plano (→ N4); `ia_engine` (→ N2).

## 2. Etapas

### N1.1 — Merge e validação do MVP em dev

1. PR `feature/mvp-telas-e-endurecimento` → `dev` (gate `prevc-final-review` já passou); deploy automático (runner self-hosted).
2. Smoke ponta-a-ponta: login no `/v2/admin`, fila carrega, mover card persiste, chat recebe evento em tempo real, mensagem do atendente sai.
3. Suítes canônicas: `.\infra\test-local.ps1` e `.\infra\test-flutter.ps1` (nunca `cargo test`/`flutter test` direto).

**Observabilidade & Auditoria:** sem código novo — sem spans nem eventos novos (intencional). Smoke valida a telemetria existente (um `trace_id` do webhook ao `audit_log`).

**DoD:** merge feito; smoke verde; suítes verdes.

### N1.2 — Scheduler temporal do `worker` (F4.3b)

Substitui o Celery beat da v1 por um loop temporal no próprio worker.

1. **Loop:** `tokio::spawn` no boot, paralelo ao consumidor do bus:

   ```rust
   // intervalo configurável; interval (não sleep) evita drift do tick
   let mut tick = tokio::time::interval(Duration::from_secs(config.scheduler_tick_secs)); // default 60
   loop {
       tick.tick().await;
       executar_tick(&estado).await; // span scheduler.tick, contadores por ação
   }
   ```

2. **Timeout de feedback:** novo RPC de leitura no `data_postgres` — `ListarAtendimentosFeedbackVencido { limite }` — seleciona atendimentos em espera de feedback com `data_ultima_mensagem` além do TTL do tenant (`TenantConfigCache`; default global documentado). Para cada um: RPC de transição de estado (encerrar/registrar).
3. **Disparo de purga:** novo RPC `ListarMidiasExpiradas { limite, idade_max }` (default 30 dias). Para cada `MediaPointer` vencido, o worker **publica o evento de purga no bus** — o `data_storage` já consome (`processar_purga_midia`).
4. **Idempotência/concorrência:** lotes com `LIMIT`; marcação `purge_requested_at`/estado para não reprocessar; lock Redis por tarefa (`tenant:{id}:lock:scheduler:<tarefa>`, `SET NX PX` — padrão do debounce já no worker) contra réplicas concorrentes.

**SOLID/Ports:** port `SchedulerClock` (fonte de tempo injetável para teste); RPCs de varredura como handlers novos sobre repositórios existentes (`atendimentos/`, `MediaPointer`); o loop depende de `Arc<dyn ...>` dos clientes RPC já no estado — sem `conectar_cliente` por tick.

**Observabilidade & Auditoria:**
- *Logs/trace:* span `scheduler.tick` por ciclo (`trace_id` novo por tick, contagem de vencidos/purgados); repositórios via `run_in_tenant_transaction` + `#[instrument(skip_all)]`.
- *Auditoria:* `atendimento.feedback_expirado` (INFO) por transição; `midia.purgada` (INFO) gravada pelo consumidor no `data_storage`. Varredura vazia **não** audita (não inundar a trilha). Trilha assíncrona via bus → `data_postgres`.
- *Sanitização:* só ids e contadores — nunca conteúdo, telefone ou payload.

**DoD:** feedback vencido transicionado no próximo tick e auditado; mídia vencida removida do R2 via evento; 2 ticks seguidos não duplicam efeito; `clippy -D warnings` + `.\infra\test-local.ps1` verde.

### N1.3 — Elo outbox → outbound do atendente

`SendOutboundMessage` (WS-6.3) já persiste via padrão outbox; `OutboxRelay` drena. Falta fechar o consumo do evento drenado.

1. Auditar o fluxo: `SendOutboundMessage` → linha na `outbox` → relay publica no bus → **consumidor** chama `data_whatsapp::SendWhatsappMessage`. Se o consumidor não existir, criá-lo no worker (mesmo caminho de `main.rs:389`), com retry/backoff e atualização de `status_envio` (`pending`→`sent`/`failed`) na `oraculo_mensagem`.
2. Confirmação de entrega: `processar_status_mensagem` (já existe) atualiza pelo webhook de status do Evolution.
3. Idempotência do retry por `message_id`/`stanzaId`.

**Observabilidade & Auditoria:**
- *Logs/trace:* span no consumidor de envio propagando o `traceparent` que veio na linha da outbox; `status_envio` como campo estruturado.
- *Auditoria:* `mensagem.envio_falhou` (WARN, sem conteúdo) em falha definitiva; envio com sucesso não audita (evento operacional, já rastreado por trace/status).
- *Sanitização:* nunca logar payload, telefone completo (mascarar) ou token de instância.

**DoD:** mensagem do atendente chega ao WhatsApp do contato; `status_envio` reflete `sent`/`failed`; retry com backoff auditado; sem PII em log.

### N1.4 — Dashboards e alertas Grafana (como código)

1. **Datasources** re-provisionados com `uid` fixo (`prometheus`, `loki`, `tempo`) em `provisioning/datasources/` — pré-requisito dos alertas (`datasourceUid`).
2. **Dashboards** versionados em `docker/observability/` (provider `type: file`, `allowUiUpdates: false`, `foldersFromFilesStructure: true`; `uid` fixo em cada JSON):
   - Saúde de serviços (`GetServiceHealth`/uptime por binário);
   - Latência gRPC (p95 via `histogram_quantile(0.95, sum(rate(..._bucket[5m])) by (le, rpc))`) e taxa de erro (`error_code`);
   - Backlog de outbox (`smartcore_outbox_backlog`) e lag de consumer groups;
   - Cadeia de trace (Tempo) — seguir um `trace_id` do webhook à resposta.
3. **Alertas** em `provisioning/alerting/` (`apiVersion: 1`, `groups` com `folder`/`interval`/`rules`; schema no info_aux): backlog de outbox acima de limiar, taxa de erro gRPC, serviço down. Contact point básico; a árvore de notification policies é sobrescrita por inteiro — versionar completa.

**Observabilidade & Auditoria:** consome telemetria existente; **sem evento de auditoria** (intencional — leitura de métricas). Dashboards sem PII (labels só com ids/serviço).

**DoD:** tráfego real em dev aparece nos dashboards; `trace_id` seguível no Tempo; ≥1 alerta dispara em cenário simulado; YAMLs versionados aplicam num container limpo.

## 3. Sequenciamento e riscos

**Ordem:** N1.1 → (N1.2 ‖ N1.3) → N1.4.

| Risco | Mitigação |
|---|---|
| Scheduler dispara em múltiplas réplicas | Lock Redis por tarefa/tenant (padrão existente) |
| Purga remove mídia referenciada | Idade conservadora + só purgar `MediaPointer` com resumo/análise gravados; o resumo permanece |
| TTL de feedback sem config do tenant | Default global no `TenantConfigCache`; chave documentada |
| Envio duplicado no retry | Idempotência por `message_id`/`stanzaId` |
| Alerta YAML com `datasourceUid` errado | UIDs fixos provisionados junto; teste em container limpo |

## 4. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N1** | Aterrar scheduler + elo outbox | Aprovar ports RPC de varredura + `SchedulerClock` | Merge; scheduler; outbound atendente; dashboards | `test-local.ps1`: timeout+purga idempotentes; outbound entregue | Dashboards com dados reais; eventos auditados |
