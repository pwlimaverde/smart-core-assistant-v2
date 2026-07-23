# Final Review — n7-endurecimento-residual
Data: 2026-07-23 · Modelo: Opus · Diff: working tree (branch feature/n6-ia-fluxo-vivo)

## Rótulo: CORRIGIDO

## Resumo das correções
- **Auditoria vazando em log-only (N7.1):** o `QuotaGuard` de storage no `data_storage` chamava `CheckQuota` com `"auditar": true` fixo, publicando `quota.excedida` no `audit_log` mesmo sem enforce ligado — viola o invariante do plano ("auditoria só no ponto de enforce real; em log-only puro não há evento") e diverge do `handler_create_departamento` (que só audita quando `enforce==true`). Corrigido: `auditar` passa a acompanhar a flag `SMARTCORE_QUOTA_ENFORCE`.
- **Falta de guard de escopo (N7.2):** `reprocessar_dead_letter` (RPC administrativo que remuta estado, reenfileirando o envio outbound no outbox) não checava escopo, ao contrário de `criar_departamento`. Adicionado `ctx.exigir_qualquer(["operacional:admin","tenant:admin"])` como defesa em profundidade sobre a RLS.
- **Typo** no relatório N7.5 ("seguraz" → "segura").

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N7.1 migration `max_storage_bytes` (aditiva, NULL=ilimitado) | ✅ | `0021_tenant_storage_usage.sql`, mesmo padrão conservador de `0017`. |
| N7.1 recurso `"storage"` em `verificar_quota` | ✅ | Trata `Option<i64>` NULLABLE corretamente; uso agregado de `tenants_storage_usage`. |
| N7.1 tabela `tenants_storage_usage` + RPC `RegisterStorageUsage` | ➕ | Desvio aceito; upsert atômico (`ON CONFLICT ... total_bytes + EXCLUDED`), RLS por tenant. |
| N7.1 guard log-only no `data_storage::PutFile` | ⚠️→✅ | Guard correto (fail-open, log-only default), **mas auditava em log-only — corrigido**. |
| N7.1 `CreateDepartamento` com guard de quota embutido | ➕ | Desvio aceito; caller antes do INSERT, log-only/enforce por flag, fail-open. |
| N7.2 `action_id` opcional/aditivo nos 2 Requests (proto) | ✅ | `optional string action_id = 4` no fim; stubs Rust+Dart regenerados. |
| N7.2 dedupe server-side por `action_id` (atômico, mesma tx) | ✅ | `applied_actions` + `buscar/registrar_acao_aplicada` dentro de `run_in_tenant_transaction`. |
| N7.2 dead-letter de outbound sem destino | ✅ | `mensagem_dead_letter` + marcador transitório `dead_letter_novo` (desvio aceito). |
| N7.2 RPC `ReprocessarDeadLetter` | ➕ | Desvio aceito; reinsere no outbox na mesma tx. **Guard de escopo adicionado.** |
| N7.2 mapeamento `action_id` nos callbacks Dart | ✅ | Repassado em `onMove`/`onSend`; clientes antigos mandam vazio → sem dedupe. |
| N7.3 webhook chama `RegisterRateLimitAttempt` do `data_redis` | ✅ | Mesma chave (`recurso="webhook"`+`id`), lê `attempts` (formato confirmado no data_redis). |
| N7.3 remoção do contador próprio no `redis-bus` | ✅ | Dep `infrastructure_redis` removida do `Cargo.toml`/`Cargo.lock`; fail-open preservado. |
| N7.4 atomicidade single-statement (`enqueue` + `insert_pending_mensagem`) | ✅ | `INSERT ... SELECT COALESCE(MAX/MIN,0)±1 ... RETURNING`; testes de concorrência novos verdes. |
| N7.4 `RecvError::Lagged` no stream FFI (log + continua) | ✅ | `loop`/`match`, WARN com `perdidos`, `Closed`→break; dep `tracing` adicionada ao FFI. |
| N7.4 trigger de reconexão (`connectivity_plus`, debounce 3s) + timer 60s | ✅ | Debounce + guarda `_sincronizando`; ignora `ConnectivityResult.none`. |
| N7.4 `LocalEngineFfiDataSource` não registrada no DI de produção | ⚠️ | Esperado (classe preparatória F8/desktop, documentada) — não é bug. |
| N7.5 relatório de validação arquivado | ✅ | Presente em `.context/workflow/docs/`, sem PII, pendências manuais listadas. |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `server/apps/data_storage/src/main.rs:204-235` | `CheckQuota` chamado com `"auditar": true` fixo → evento `quota.excedida` publicado em log-only, contra o invariante do plano | Lê `enforce` antes e passa `"auditar": enforce` — audita só quando o guard vai de fato bloquear |
| `server/crates/infrastructure_postgres/src/atendimentos/mensagens.rs:456-460` | `reprocessar_dead_letter` (mutação administrativa) sem checagem de escopo, divergindo de `criar_departamento` | Adicionado `ctx.exigir_qualquer(["operacional:admin","tenant:admin"])?` (defesa em profundidade) |
| `.context/workflow/docs/validacao-operacional-n7-endurecimento-residual.md:26` | Typo "seguraz" | "segura" |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| N7.1 quota storage (guard `data_storage`) | ✅ | ✅ (após fix) | ✅ | WARN log-only; audit só em enforce real (corrigido). Fail-open logado. |
| N7.1 quota departamentos (`CreateDepartamento`) | ✅ | ✅ | ✅ | `#[instrument]` com `tenant_id`; audita `quota.excedida` só quando enforce bloqueia. |
| N7.1 `RegisterStorageUsage` | ✅ | N/A | ✅ | `#[instrument(skip_all)]` com `tenant_id`/`delta_bytes`; sem PII. |
| N7.2 dedupe `action_id` | ✅ | N/A* | ✅ | `#[instrument]` com `tenant_id`/`action_id` (uuid, não sensível). *Rejeição de duplicata é no-op silencioso na mesma tx; o plano cita INFO — ver §3. |
| N7.2 dead-letter | ✅ | ✅ | ✅ | `mensagem.dead_letter` só no instante do registro (`dead_letter_novo`); detalhes só `atendimento_id`/`mensagem_id`/`motivo`, sem conteúdo/telefone. |
| N7.2 `ReprocessarDeadLetter` | ✅ | ⚠️ | ✅ | `#[instrument]` com `tenant_id`/`dead_letter_id`; sem evento de auditoria no reprocessamento bem-sucedido (ver §3). Conteúdo só trafega no outbox, nunca em log. |
| N7.3 rate-limit unificado | ✅ | N/A | ✅ | Contador emitido pelo `data_redis`; webhook loga veredito com `recurso`/`id` (sem telefone). |
| N7.4 sync trigger/atomicidade | ✅ | N/A | ✅ | `Lagged` vira WARN com contagem; payload/PII nunca logado. Auditoria é server-side no sync (invariante N5). |
| N7.5 validação manual | ✅ | N/A | ✅ | Relatório sem PII; pendências de tráfego real listadas. |

## 3. Decisões Autônomas (revisar depois)
- **⚠️ Guard de escopo em `reprocessar_dead_letter`** adicionado pelo subagente de auditoria (não estava no diff original). É defesa em profundidade e espelha `criar_departamento`; como o RPC ainda não tem chamador externo (só roteado internamente no `data_postgres`), não havia furo ativo, mas ao expô-lo via `runtime_api` isso já fica coberto. Se houver intenção de um chamador interno sem escopos, revisar.
- **Auditoria de duplicata (N7.2 §a do plano):** o plano pedia "INFO ao rejeitar duplicata". A implementação faz o dedupe como no-op atômico dentro da transação (mais robusto), sem log INFO explícito por reenvio. Comportamento superior (evita ruído de log em retries legítimos) e o `#[instrument]` já dá o span com `action_id`. Registrado para ciência, não corrigido.
- **Detalhe do evento `quota.excedida`:** `CreateDepartamento`/`CheckQuota` publicam o `status` completo (inclui `uso_atual`, que para departamentos é uma contagem). Mantido — idêntico ao padrão N4 já em produção e não é PII.

## 4. Revalidação
- fmt/clippy (Rust, workspace completo): ✅
- testes unitários (Rust, crates tocadas): ✅ — `local_engine` 44/44 (inclui regressões de concorrência N7.4); `data_postgres` unit 62/62 (action_id, RegisterStorageUsage, CreateDepartamento); `webhook_ingress` 6/6 (rate-limit unificado); `data_storage` 14/14; `infrastructure_postgres` 21/21.
- flutter analyze/test (Dart): ✅ — `.\infra\test-flutter.ps1`: 337/337 testes verdes, 17/17 pacotes analyze limpos.
- **`cargo test --workspace` via `.\infra\test-local.ps1`** (unit + integração real via túnel SSH contra Postgres/RLS/Redis remoto dev): ✅ **TUDO VERDE**, executado nesta mesma sessão antes do gate de auditoria — inclui os 37 testes de integração do `infrastructure_postgres` (RLS, CRUD) com as migrations `0021`/`0022` já aplicadas ao Postgres remoto, e `cargo sqlx prepare --workspace --check` ok. (O subagente de auditoria não re-executou este passo por ser caro/já coberto — ver seção "Pendências" original dele.)

## 5. Pendências (escopo extra ou fora do plano)
- `CreateDepartamento` e `ReprocessarDeadLetter` existem como rotas do `data_postgres` mas **ainda não têm chamador em `runtime_api`/cliente** (nenhum CRUD de departamento existia antes; reprocessamento é RPC administrativo interno). Quando forem expostos via gRPC-Web, lembrar do requisito de exposição explícita no `AdminService`/`grpc_web.rs`.
- As 4 validações manuais da N7.5 (rajada, dashboards/alertas, E2E, teste manual dedupe/dead-letter com tráfego real) seguem como pré-condição dura do N8 — pendentes do ambiente do dono do produto (ver `.context/workflow/docs/validacao-operacional-n7-endurecimento-residual.md`).
- `LocalEngineFfiDataSource` permanece fora do DI/get_it de produção (esperado; ligação prevista para F8/desktop).
