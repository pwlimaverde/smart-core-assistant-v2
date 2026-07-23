# Plano Completo — Fase N7: Endurecimento residual + operação validada

> Gerado em: 2026-07-18 · Reestruturado contra o código real e docs atuais (ver
> [info_aux_n7-endurecimento-residual.md](./info_aux_n7-endurecimento-residual.md)).
> Origem: `doc_dev/planejamento/22-fase-N7-endurecimento-residual.md` (histórico).
> **Idioma:** Português (comunicação/documentação); código e identificadores em inglês.
> **Objetivo:** quitar as pendências técnicas registradas em N1/N3/N4/N5 e validar a
> operação com tráfego real — pré-condição dura do cutover (N8). Sem isto, o enforce
> de produção (N8.3) seria ligado às cegas.

## Correções aplicadas (vs. plano base)

| # | Correção | Motivo / Fonte |
|---|---|---|
| 1 | **N7.3 não constrói RPC de rate-limit** — `RegisterRateLimitAttempt` (+ port `RateLimiter` + `RedisRateLimiter`) **já existe** no `data_redis` e é usado pelo `runtime_api`. A tarefa é o `webhook_ingress` **passar a chamá-lo** no lugar dos contadores próprios do `redis-bus`. | `data_redis/src/main.rs:129,404` |
| 2 | **N7.1 `"departamentos"` já é recurso reconhecido** por `QuotaStore::verificar_quota`; falta só o **caller** no CRUD. O trabalho novo real é o recurso **`"storage"`** (migration `max_storage_bytes` + guard no `data_storage`). | `data_postgres/src/ports/quota.rs:13-22` |
| 3 | **N7.2 `action_id` já viaja client-side** (uuid v7 em `OfflineAction.id`, passado ao `SyncTransport` e aos callbacks Dart). A lacuna é **server-side**: campo no proto + dedupe. Campo **opcional/aditivo** (clientes antigos seguem). | `local_engine/src/lib.rs:129-197`; `admin.proto` |
| 4 | **N7.4 atomicidade é single-statement no SQLite**, não lock distribuído — SQLite serializa escritas; `INSERT ... SELECT COALESCE(MAX(version),0)+1` numa transação elimina a corrida entre conexões do pool. | `offline_queue.rs:145-150`; `doc_dev/libs/rust/sqlx.md` |
| 5 | **N7.4 stream FFI**: o encerramento silencioso é no `broadcast::Receiver` ao receber `RecvError::Lagged`; solução é log + **resubscribe**, não aumentar buffer indefinidamente. | `lib.rs:71,202`; `doc_dev/libs/rust/tokio.md` |
| 6 | Todo enforcement novo **nasce log-only atrás de flag** com auditoria **só no ponto de enforce real** (nunca no caminho quente de leitura). | Lição registrada da N4 (final-review) |

---

## N7.1 — Quotas restantes (storage + caller de departamentos)

**Objetivo:** fechar as duas quotas que a N4 deixou medindo mas sem enforcement:
storage (falta limite+guard) e departamentos (falta caller).

**Áreas:** `infrastructure_postgres` (migration), `data_postgres`
(`ports/quota.rs`, adapter, caller no CRUD de departamento), `data_storage`
(guard no `PutFile`).

**Passos:**
1. Migration aditiva `max_storage_bytes BIGINT` em `tenants_plan` (segue o padrão
   de `0017_plan_retention_days.sql`; default conservador ou `NULL` = ilimitado no
   log-only). Regenerar `.sqlx` (SQLX_OFFLINE).
2. `verificar_quota`: reconhecer o recurso `"storage"` — comparar o uso agregado
   (soma de `usage_metrics`/tamanho de objetos do tenant) contra `max_storage_bytes`.
   Mesma transação de tenant (RLS), mesmo shape de `CheckQuotaReply`.
3. `data_storage` (`PutFile`): decorar com o mesmo `QuotaGuard` da N4.2 — verifica
   `"storage"` **log-only** (flag `SMARTCORE_QUOTA_ENFORCE`, já existente) antes de
   subir ao R2; excedido em modo enforce → erro de quota, senão só conta a métrica.
4. Caller de `"departamentos"`: no RPC de criação de departamento (`data_postgres`),
   chamar `verificar_quota(tenant, "departamentos")` antes do INSERT (log-only/enforce
   pela mesma flag).

**DoD:** criar departamento/subir arquivo além do limite gera contador
`quota_excedida_total{recurso}` (e bloqueia quando `SMARTCORE_QUOTA_ENFORCE=true`);
`.\infra\test-local.ps1` verde.

**Observabilidade & Auditoria:**
- (a) Span do guard com `tenant_id`/`recurso`/`error_code`; contador Prometheus
  `quota_excedida_total{recurso}`. Instrumentação da infra respeitada
  (`run_in_tenant_transaction` + `#[instrument(skip_all)]` no repositório).
- (b) Auditoria **só quando o enforce real bloquear** (evento `quota.excedida` com
  `tenant_id`/`recurso`/limite — **sem** valor de uso bruto sensível). Em log-only
  puro não há evento de auditoria (intencional — é medição, não mutação sensível).
- (c) Sem PII: só ids, recurso e contagens; nome de arquivo/telefone nunca no log.

---

## N7.2 — Idempotência do sync + dead-letter de outbound

**Objetivo:** reenviar uma ação offline (após retry/reconexão) **não duplica** o
efeito no servidor; outbound sem destino resolvível vira dead-letter reprocessável.

**Áreas:** `contracts` (admin.proto), `runtime_api`/`data_postgres` (dedupe +
dead-letter), callbacks Dart (`operacional_module`), `local_engine_ffi` (mapeamento).

**Passos:**
1. `admin.proto`: `MoveAtendimentoEtapaRequest` e `SendOutboundMessageRequest`
   ganham `optional string action_id` (**campo novo no fim** — aditivo; nunca
   renumerar). Regenerar stubs Rust (`flatc`/`tonic`) e Dart (`api_client`).
2. Dedupe server-side: tabela `applied_actions(action_id UUID PRIMARY KEY,
   tenant_id, applied_at)` **ou** índice único parcial `WHERE action_id IS NOT NULL`
   na entidade afetada. Ao aplicar, `INSERT ... ON CONFLICT DO NOTHING`: se já
   existia, devolver o resultado idempotente (mesmo id definitivo) sem reaplicar.
3. Mapear `action_id` nos callbacks Dart já preparados (o `DartSyncTransport`
   recebe `action_id` — só repassar no request). Clientes antigos mandam vazio →
   servidor aplica sem dedupe (comportamento atual preservado).
4. Dead-letter: quando a resolução de destino falha (sem `whatsapp_contact` ativo),
   gravar em tabela/fila de dead-letter (auditável, com ponteiro ao atendimento),
   em vez de descartar; expor reprocessamento manual (RPC administrativo simples).

**DoD:** reenviar a mesma ação (mesmo `action_id`) duas vezes aplica **uma vez**
(provado em teste de integração via túnel); outbound sem destino aparece na
dead-letter e é reprocessável; `.\infra\test-local.ps1` + `.\infra\test-flutter.ps1` verdes.

**Observabilidade & Auditoria:**
- (a) INFO ao rejeitar duplicata (`action_id`, `atendimento_id` — sem conteúdo);
  span do handler com `error_code` em falha real de infra.
- (b) `mensagem.dead_letter` no audit_log (**sem** conteúdo/PII — só `atendimento_id`
  e motivo). Rejeição de duplicata registrada (INFO, só ids).
- (c) `action_id` é uuid (não sensível); conteúdo/telefone da mensagem nunca logado.

---

## N7.3 — Contadores de rate-limit do webhook unificados

**Objetivo:** o `webhook_ingress` para de manter contadores de rate-limit no
`redis-bus` e passa a usar o RPC `RegisterRateLimitAttempt` do `data_redis` — mesma
fonte do `runtime_api`, independente da eviction do bus.

**Áreas:** `webhook_ingress` (substituir a contagem local pela chamada RPC),
`transport` (cliente do `data_redis`, se ainda não injetado no webhook).

**Passos:**
1. No caminho de ingestão do `webhook_ingress`, trocar a lógica de contador própria
   por uma chamada `RegisterRateLimitAttempt` (`recurso` = chave do webhook, `id` =
   instância/tenant, `window_s` configurável) ao `data_redis`.
2. Interpretar a `RegisterRateLimitAttemptReply` (permitido/estourado) e aplicar a
   política **log-only → enforce por flag**, coerente com o restante.
3. Remover o contador redundante do `redis-bus` (evitar dupla contagem).

**DoD:** rajada no webhook incrementa o **mesmo** contador visto pelo `runtime_api`;
sem contador órfão no bus; `.\infra\test-local.ps1` verde (inclui Redis integração).

**Observabilidade & Auditoria:**
- (a) O contador já é emitido pelo RPC do `data_redis`; o webhook loga o veredito
  (permitido/estourado) com `recurso`/`id`. Sem span novo pesado no caminho quente.
- (b) Sem evento de auditoria (métrica operacional, não estado sensível).
- (c) Chave de rate-limit não carrega PII bruta (usar id/instância, não telefone).

---

## N7.4 — Sync offline robusto no desktop

**Objetivo:** o sync dispara sozinho ao reconectar (e por timer), e as arestas de
concorrência do `local_engine` são fechadas.

**Áreas:** `local_engine` (`offline_queue.rs`, `lib.rs`), `local_engine_ffi`
(stream + expor trigger), `operacional_module` (listener de conectividade).

**Passos:**
1. **Atomicidade** (`offline_queue.rs`): tornar a atribuição de `version`
   single-statement — `INSERT INTO offline_actions (..., version) SELECT ...,
   COALESCE(MAX(version),0)+1 FROM offline_actions` dentro de uma transação; idem
   para o id pendente negativo em `insert_pending_mensagem` (menor id − 1 num único
   statement). SQLite serializa escritas → corrida entre conexões do pool eliminada.
2. **Stream `Lagged`** (`lib.rs`/FFI): no laço de `recv()` do `broadcast::Receiver`,
   tratar `Err(RecvError::Lagged(n))` com `tracing::warn!(perdidos = n, ...)` +
   **continuar** (resubscribe implícito do próprio receiver), nunca `break`. Em
   `RecvError::Closed`, encerrar limpo.
3. **Trigger por reconexão** (`operacional_module`): assinar
   `Connectivity().onConnectivityChanged`; ao voltar a rede (`!= none`), disparar
   `sincronizar()` com **debounce (~3s)** e reuso da guarda `_sincronizando`
   (não empilhar). Ver `doc_dev/libs/flutter/connectivity_plus.md` (caveat: evento
   é oportunista, não garante internet — falha do transporte só deixa na fila).
4. **Timer periódico**: além do trigger, um timer de fundo (ex.: 60s) chama
   `sincronizar()` best-effort, cobrindo o caso de a conectividade não mudar mas o
   servidor ter voltado.

**DoD:** com o app aberto, reconectar a rede sincroniza sozinho sem duplicar; duas
ações concorrentes recebem versões distintas; stream sobrevive a `Lagged`;
`.\infra\test-flutter.ps1` + testes do crate `local_engine` verdes.

**Observabilidade & Auditoria:**
- (a) Span de sync já existente ganha `disparo` (reconexao|timer|manual); `Lagged`
  vira WARN com contagem de eventos perdidos.
- (b) Sem evento de auditoria client-side (a auditoria das ações é server-side, no
  momento do sync, com o ator real — invariante da N5).
- (c) Payload/PII das ações nunca logado (regra já vigente no `sincronizar`).

---

## N7.5 — Validação operacional manual (evidência de prontidão)

**Objetivo:** provar, com tráfego real, que o que N1–N7 construiu aguenta operação
— gerando o **relatório** que autoriza o cutover (N8).

**Passos (documentados em relatório, sem harness automatizado — regra do projeto):**
1. **Rajada** no webhook/bus via túnel `test_support`: carga progressiva, observar
   backlog e latência no Grafana **antes** de subir carga (dev compartilhado).
2. **Dashboards/alertas** (provisionados na N1.4, nunca validados): confirmar que
   painéis populam com tráfego real e que ao menos um alerta dispara/reseta.
3. **E2E manual das UIs do tenant** (aceito por decisão do dono na N3 com base nos
   testes, nunca clicado): roteiro convite → aceite → RBAC fino → chat, contra o
   runtime real.

**DoD:** relatório de rajada + evidência de dashboards/alertas + checklist E2E
arquivado em `.context/workflow/docs/` como prontidão para o N8.

**Observabilidade & Auditoria:**
- (a) A própria etapa **consome** a observabilidade existente (é o teste dela).
- (b) N/A (não altera estado de produto).
- (c) Telefones/PII mascarados no relatório; nenhuma credencial anexada.

---

## Sequenciamento

**N7.1 ‖ N7.3 → N7.2 → N7.4 → N7.5.** N7.1 (quotas) e N7.3 (rate-limit) são
independentes e paralelizáveis (áreas distintas). N7.2 (dedupe/proto) precede N7.4
(que depende do `action_id` fechado no fluxo). N7.5 valida tudo por último e produz
a evidência para o N8.

## Validação (fase V)
- `.\infra\test-local.ps1` (Rust completo via túnel: unit + Postgres/RLS + Redis).
- `.\infra\test-flutter.ps1` (inclui crate `local_engine` e o `operacional_module`).
- Relatório da validação manual (N7.5) arquivado.

## DoD da fase
Storage/departamentos com guard log-only funcionando; reenvio de ação offline não
duplica efeito no servidor (provado por `action_id`); contadores de rate-limit
unificados no `data_redis`; sync dispara sozinho ao reconectar sem corrida de
versão; relatório de rajada/dashboards/E2E manual arquivado — **pré-condição do N8
satisfeita**.
