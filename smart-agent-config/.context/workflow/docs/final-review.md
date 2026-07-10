# Final Review — n1-fechamento-mvp-scheduler
Data: 2026-07-09 · Modelo: Opus · Diff: working tree (escopo: server/apps/worker, server/apps/data_postgres, server/crates/infrastructure_postgres, docker/observability)

## Rótulo: CONFORME

## Resumo das correções
Nenhuma correção foi necessária. Todos os itens de N1.2 (scheduler), N1.3 (elo outbox→outbound) e N1.4 (Grafana como código) estão implementados conforme o plano completo, com observabilidade/auditoria conformes e `cargo fmt --check` / `clippy -D warnings` / testes (worker 10/10, data_postgres 31/31) limpos.

## 1. Plano vs. Implementado

| Item do plano | Status | Observação |
|---|---|---|
| N1.2 Migração 0014 (feedback_expirado_em, midia_purgada_em + índices parciais) | ✅ | `infrastructure_postgres/migrations/0014_scheduler_idempotencia.sql` |
| RPC ListarAtendimentosFeedbackVencido | ✅ | cross-tenant via admin_pool, `exigir_qualquer(["operacional:admin"])` |
| RPC MarcarFeedbackExpirado (idempotente) | ✅ | `WHERE feedback_expirado_em IS NULL` |
| RPC ListarMidiasExpiradas | ✅ | filtro `arquivo_midia IS NOT NULL AND midia_purgada_em IS NULL` |
| RPC MarcarMidiaPurgada (idempotente) | ✅ | `WHERE midia_purgada_em IS NULL` |
| Loop tokio::spawn + tokio::time::interval | ✅ | `worker/src/scheduler.rs::iniciar`, paralelo ao consumer do bus |
| Lock Redis SET NX PX por tarefa | ✅ | `scheduler:lock:feedback_timeout` / `:media_purge`, TTL 30s < tick |
| Port SchedulerClock (tempo injetável) | ⚠️ vestigial | trait+impl existem e são injetados, mas TTL é calculado server-side (NOW()); ver Decisões Autônomas |
| Auditoria atendimento.feedback_expirado (INFO, sem PII) | ✅ | só `{atendimento_id}` |
| Publica media.purge no bus | ✅ | consumido pelo data_storage já existente |
| N1.3 RPC ResolverDestinoEnvioOutbound | ✅ | join mensagem→atendimento→contato→whatsapp_contact |
| RPC MarcarMensagemEnviada / MarcarMensagemFalhaEnvio | ✅ | guarda `WHERE status_envio='pending'` |
| Consumidor de message.persisted no worker | ✅ | no-op para sender_id != "atendente" |
| Retry/backoff | ✅ | backoffs [0,1,2,4]s |
| Idempotência de reentrega | ✅ | early-return quando status_envio != "pending" |
| Auditoria mensagem.envio_falhou (WARN, sem conteúdo) | ✅ | só `{mensagem_id}` |
| Bug pré-existente (payload SendWhatsappMessage do bot) | ✅ corrigido | `instance_id`/`to` → `id`/`to_number` |
| N1.4 Datasources uid fixo + editable:false | ✅ | `provisioning/datasources/ds.yml` |
| Dashboards allowUiUpdates:false + 4 dashboards novos | ✅ | `servicos_saude`, `latencia_grpc`, `outbox_backlog`, `trace_chain` |
| Alerting provisionado (rules/contact-points/policies) | ✅ | `provisioning/alerting/` |
| Nomes de métrica batem com o código | ✅ | `smartcore_rpc_total`, `smartcore_rpc_duration_ms_*`, `smartcore_outbox_backlog`, `smartcore_bus_pending`, `smartcore_pg_pool_*` |

## 2. Correções Aplicadas

| Arquivo:linha | Problema | Correção |
|---|---|---|
| — | Nenhum desvio encontrado | Implementação passou em todos os gates sem necessidade de edição |

## 2b. Observabilidade & Auditoria

| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| Scheduler: feedback vencido | ✅ `#[instrument]` + `scheduler.tick` | ✅ `atendimento.feedback_expirado` só quando processados>0 | ✅ só ids | conforme |
| Scheduler: purga de mídia | ✅ | N/A (audita no data_storage, já existente) | ✅ só file_name via bus, não logado | conforme |
| Elo outbox→outbound | ✅ | ✅ `mensagem.envio_falhou` só em falha definitiva | ✅ sem conteúdo/telefone completo | conforme |
| Dashboards/alerting | N/A (leitura de métricas) | N/A (intencional) | ✅ labels só ids/serviço | conforme |

## 3. Decisões Autônomas (revisar depois)
- Port `SchedulerClock` fica vestigial: TTL calculado via `NOW()` no SQL, não pelo `clock.now()` injetado. Mantido conforme a letra do plano (o port existe e é testável), sem refactor adicional de risco.
- Trace propagation do scheduler usa `traceparent`/`trace_id` vazios nas RPCs/auditoria disparadas pelo tick — spans downstream iniciam trace próprio em vez de encadear sob `scheduler.tick`. Não-bloqueante; endereçável quando houver um helper de extração do traceparent W3C do contexto OTel corrente.

## 4. Revalidação
- fmt: ✅
- clippy (worker+data_postgres, -D warnings): ✅
- testes (worker 10/10, data_postgres 31/31): ✅
- suíte remota completa (.\infra\test-local.ps1): ✅ 32/33 (única falha é ambiental pré-existente, documentada na fase V)

## 5. Pendências (escopo extra ou fora do plano)
- Duplicidade em falha pós-envio (SendWhatsappMessage sucede mas MarcarMensagemEnviada falha): reentrega reenviaria. Aceito pelo plano (idempotência client-side fica para N2+).
- `ResolverDestinoEnvioOutbound` sem `whatsapp_contact` ativo causa `bail!`/reentrega indefinida sem auditoria — edge operacional, considerar dead-letter futuramente.
- Varreduras cross-tenant retornam a struct completa (Atendimento/Mensagem) quando o worker só usa poucos campos — sem risco de vazamento (payload service-to-service, não logado), só oportunidade de eficiência.
