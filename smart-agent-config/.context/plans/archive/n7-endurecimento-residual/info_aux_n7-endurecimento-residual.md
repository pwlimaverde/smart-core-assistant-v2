# Documentação Auxiliar — Fase N7: Endurecimento residual + operação validada

> Gerado em: 2026-07-18
> Plano canônico: `.context/plans/n7-endurecimento-residual.md`
> Plano completo: `.context/plans/n7-endurecimento-residual/plano_completo_n7-endurecimento-residual.md`
> Origem: `doc_dev/planejamento/22-fase-N7-endurecimento-residual.md` (histórico).

Este documento reúne (a) o **estado real do código** que a N7 vai tocar — levantado
por leitura direta do repositório, corrige premissas do plano-base — e (b) a
documentação atual das libs/serviços novos. A N7 é majoritariamente **reuso de
padrões já entregues** (QuotaGuard da N4, fila offline da N5), então o levantamento
de código pesa mais que docs de terceiros.

---

## Achados no código (aterramento — o que já existe)

### Rate-limit centralizado (N7.3) — RPC **já existe**
`server/apps/data_redis/src/main.rs` já expõe a rota RPC **`RegisterRateLimitAttempt`**
(linha ~129), servida pelo handler `handler_register_rate_limit_attempt` (linha ~404)
sobre o port `ports::RateLimiter` + adapter `adapters::RedisRateLimiter`. O reply é
`RegisterRateLimitAttemptReply`. Payload de entrada: `recurso`, `id`, `window_s`.

> **Correção do plano-base:** N7.3 **não constrói** o RPC. Ele já está pronto e é
> usado pelo `runtime_api`. A tarefa é **fazer o `webhook_ingress` chamar esse RPC
> do `data_redis`** em vez de manter contadores próprios no `redis-bus` (a conexão
> que o webhook já tinha). Assim os contadores ficam unificados com o `runtime_api`
> e independentes da política de eviction do bus.

### Quota de departamentos/storage (N7.1) — store **já aceita o recurso**
`server/apps/data_postgres/src/ports/quota.rs`: o trait `QuotaStore::verificar_quota`
recebe `recurso: &str` documentado como `"instancias" | "departamentos"` e roda
**sob a role de runtime** (RLS respeitado, nunca `admin_pool`). O `QuotaGuard`
(decorator N4.2) já cobre o caminho quente via `handler_check_quota`.

> **Correção do plano-base:** o recurso `"departamentos"` já é reconhecido pelo
> store/limite; falta apenas o **caller** no CRUD de criação de departamento
> (`data_postgres`) invocar a verificação antes de inserir. Para **storage** é
> preciso: (1) migration `max_storage_bytes` em `tenants_plan` (a tabela de limites
> por plano já existe — `0003_plans_subscriptions.sql`, `0017_plan_retention_days.sql`
> seguem o padrão aditivo); (2) medição já existe em `usage_metrics`; (3) novo
> recurso `"storage"` no `verificar_quota` + guard log-only no `data_storage`
> (`server/apps/data_storage/src/main.rs`) no caminho de `PutFile`.

### `local_engine` — pontos de atomicidade e stream (N7.4)
`server/crates/local_engine/src/offline_queue.rs` — `next_version()` faz
`SELECT MAX(version) FROM offline_actions` **+1 em memória**, e `move_*`/`send_*`
(em `src/lib.rs`) chamam `next_version()` e depois `enqueue()` em **statements
separados**. Entre duas conexões do pool SQLite isso é uma janela de corrida (duas
ações podem receber a mesma `version`). O `insert_pending_mensagem` (id local
negativo) tem o mesmo padrão de "ler o menor id e decrementar".

- **Mitigação alvo:** tornar a atribuição de `version`/id pendente **single-statement**
  (ex.: `INSERT ... SELECT COALESCE(MAX(version),0)+1 ...` numa transação, ou coluna
  `AUTOINCREMENT` dedicada) — SQLite serializa escritas, então um único statement
  elimina a corrida. Ver `doc_dev/libs/rust/sqlx.md`.
- **Stream FFI `Lagged`:** o motor usa `tokio::sync::broadcast` (`CAPACIDADE_EVENTOS = 128`);
  `stream_atendimentos()` devolve um `broadcast::Receiver`. Se o consumidor Dart
  (via FFI, `clients/packages/local_engine_ffi/rust/src/api/atendimento.rs`) ficar
  para trás, `recv()` devolve `RecvError::Lagged(n)` e hoje o stream encerra
  silencioso. **Alvo:** tratar `Lagged` com log (contagem de eventos perdidos) +
  **resubscribe** (continuar do estado atual), nunca encerrar. Ver
  `doc_dev/libs/rust/tokio.md` (broadcast).

### Idempotência do sync (N7.2) — `action_id` já viaja client-side
`local_engine`: `OfflineAction.id` é **uuid v7** e já é passado aos métodos do
`SyncTransport` (`move_atendimento_etapa(action_id, ...)`,
`send_outbound_message(action_id, ...)`) e aos callbacks Dart. O que falta é
**server-side**: os protos `MoveAtendimentoEtapaRequest`/`SendOutboundMessageRequest`
(em `server/crates/contracts/schemas/queries/admin.proto`) **não têm** campo
`action_id`, e não há dedupe no `runtime_api`/`data_postgres`.

> **Alvo N7.2:** adicionar `action_id` (aditivo, campo novo no fim da mensagem) aos
> dois Requests; dedupe server-side por índice único parcial
> (`action_id NOT NULL`) numa tabela de ações aplicadas (ou coluna na entidade
> afetada); mapear o `action_id` nos callbacks Dart já preparados. Campo **opcional**:
> clientes antigos (sem `action_id`) seguem funcionando.

### Outbound sem destino (N7.2, dead-letter)
Falha de resolução de destino sem `whatsapp_contact` ativo hoje não tem dead-letter.
Alvo: registrar em fila/tabela de dead-letter (auditável, reprocessável), auditando
`mensagem.dead_letter` **sem conteúdo/PII**.

---

## Libs / serviços (Grupo A + B)

### Flutter — `connectivity_plus` (novo → doc central criado)
Doc central: `doc_dev/libs/flutter/connectivity_plus.md` (criado 2026-07-18, via Context7).

Pontos que importam ao N7.4:
- API: `Connectivity().onConnectivityChanged` → `Stream<List<ConnectivityResult>>`
  (List desde a v5); `checkConnectivity()` → `Future<List<ConnectivityResult>>`.
- **Caveat central:** reporta o *tipo de interface*, **não** garante alcance real
  da internet. Trate o evento como gatilho oportunista: dispare `sincronizar()`, e
  se o transporte falhar, as ações seguem na fila (design já resiliente por `action_id`).
- **Debounce obrigatório** (eventos duplicados, especialmente iOS/macOS; no Windows
  é mais estável) + reuso da guarda anti-concorrência `_sincronizando` já existente
  no lado Dart. Nunca marcar como sincronizado com base na conectividade.

### Rust — libs USAR LOCAL (reaproveitadas da central, sem Context7)
| Lib | Doc central | Uso no N7 |
|-----|-------------|-----------|
| `sqlx` (0.8.x) | `doc_dev/libs/rust/sqlx.md` | atomicidade single-statement de `version`/id pendente no SQLite |
| `tokio` (1.x) | `doc_dev/libs/rust/tokio.md` | `broadcast::error::RecvError::Lagged` no stream FFI (log + resubscribe) |
| `tonic-build` | `doc_dev/libs/rust/tonic-build.md` | evolução **aditiva** dos protos (`action_id`) |
| `tracing` / `opentelemetry` | `doc_dev/libs/rust/{tracing,opentelemetry}.md` | contadores Prometheus + spans dos guards |
| `flutter_rust_bridge` | `doc_dev/libs/flutter/flutter_rust_bridge.md` | consumo do stream no FFI |

### Serviços externos (Grupo B)
Nenhum serviço externo **novo**. O rate-limit do webhook passa a falar com o
`data_redis` (RPC interno), não com um serviço de terceiros. A validação operacional
(N7.5) usa Grafana/Prometheus **já provisionados** (N1.4) e o túnel SSH do
`test_support` (ver memória `testes-db-tunel-e-reset`).

---

## Grupo C — Observabilidade e Auditoria (transversal)

Contrato herdado da N4 (lição registrada): **enforcement novo nasce log-only atrás
de flag**, com contador Prometheus, e **auditoria só no ponto de enforcement real**
— nunca no caminho quente de leitura.

| Etapa | Log/Trace | audit_log | Sanitização |
|-------|-----------|-----------|-------------|
| N7.1 quota storage/departamentos | span do guard com `tenant_id`/`recurso`/`error_code`; contador `quota_excedida_total{recurso}` | evento **só** quando o enforce real bloquear (não em log-only puro); sem valor de uso bruto sensível | sem PII (só ids/contagens) |
| N7.2 dedupe `action_id` | INFO ao rejeitar duplicata (`action_id`, `atendimento_id`) | rejeição de duplicata registrada (só ids) | `action_id` é uuid, não sensível; conteúdo da mensagem nunca logado |
| N7.2 dead-letter | WARN `mensagem.dead_letter` | evento `mensagem.dead_letter` **sem conteúdo/PII** (só `atendimento_id`, motivo) | conteúdo/telefone nunca no evento |
| N7.3 rate-limit unificado | contador do `data_redis` (já emitido pelo RPC) | sem evento (métrica operacional) | só `recurso`/`id` da chave, sem PII |
| N7.4 sync trigger/atomicidade | span de sync já existe; `Lagged` vira WARN com contagem | sem evento (client-side; auditoria é server-side no sync) | payload/PII nunca logado (regra já vigente) |
| N7.5 validação manual | relatório em `.context/workflow/docs/` | N/A | telefones mascarados no relatório |

---

## Notas gerais / gotchas
- **Dedupe indexado com cuidado:** índice único **parcial** por `action_id NOT NULL`
  para não penalizar o caminho quente nem quebrar clientes antigos (campo opcional).
- **Trigger de conectividade no Windows:** debounce + guarda `_sincronizando` para
  não entrar em loop de sync/bateria.
- **Validação de carga:** janela combinada, rajada **progressiva**, observar backlog
  no Grafana antes de subir carga — o dev é compartilhado.
- **Não ligar enforce em produção aqui** — isso é N8.3, após a janela de observação.
