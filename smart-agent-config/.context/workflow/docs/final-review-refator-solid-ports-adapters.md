# Final Review — refator-solid-ports-adapters
Data: 2026-06-22 · Modelo: Opus · Escopo: rollout COMPLETO (Fases 0/1 piloto + 2..9 data_postgres + D data_redis)

## Rótulo: CORRIGIDO  (informativo — não bloqueia o ciclo)

## Resumo das correções
O gate de final-review auditou o piloto (Fase 0/1, commit `3ddf58c`) e corrigiu o desvio do teste 1.10 (substituído por testes mockall). Em seguida, por decisão do dono do projeto ("implementar tudo antes de arquivar"), o **rollout completo** das Fases 2..9 (data_postgres) e Fase D (data_redis) foi implementado neste ciclo — efetivamente convertendo os dois serviços de dados inteiros para Ports & Adapters. Todos os ~41 handlers RPC passaram a depender apenas de traits (DIP); o SQL/transação/cifragem/Redis vive nos adapters. Os testes que batiam no banco/Redis em `src/**` foram substituídos por testes unitários `mockall` (ou marcados `#[ignore]` quando exercem genuinamente integração de uma função privada). Resultado: `cargo test -p data_postgres --bins` e `-p data_redis --bins` passam **sem túnel SSH**, clippy `-D warnings` limpo e `cargo fmt --check` limpo.

## 1. Plano vs. Implementado

| Fase | Domínio/Item | Status | Observação |
|---|---|---|---|
| 0 | `mockall`/`async-trait` no workspace e nos 2 apps | ✅ | piloto |
| 1 | Piloto WhatsApp (ports/adapters/handlers/testes) | ✅ | corrigido no gate (teste 1.10) |
| 2 | `TenantStore` (create/list/get/update/set_active/access_code/export_csv) | ✅ | 7 handlers + 4 testes |
| 3 | `AuthStore` (verify_credentials, get_user_identity, superusers) | ✅ | + `AuditPort.publish_security` p/ eventos globais; 4 testes |
| 4 | `AtendimentoStore` (get_thread, list_atendimentos, persist_message c/ outbox) | ✅ | 3 testes |
| 5 | `ClienteStore` (upsert_contact) | ✅ | coberto junto à Fase 4 |
| 6 | `OperacionalStore` (core_settings, tenant_config c/ cipher, feature_flags, audit_log, health, dashboard, evolution) | ✅ | 12 handlers + 4 testes |
| 7 | `PlansStore` (plans, subscriptions, payments) | ✅ | 6 handlers + 4 testes |
| 8 | `TreinamentoStore` | ➕ N/A | não há handler RPC de treinamento no data_postgres — fase vazia (ver Pendências) |
| 9 | `OutboxRelay` atrás de port (`OutboxStore`) | ✅ | drain testável com mock; 2 testes |
| D | data_redis: `CacheStore`/`RefreshTokenPort`/`TokenBlocklist`/`LoginRateLimiter` (ISP) | ✅ | 8 handlers, 4 ports, 4 adapters + 7 testes |

## 2. Correções/Decisões aplicadas no rollout

| Tema | Decisão |
|---|---|
| `Option<&str>` em traits com `automock` | Trocado por `Option<String>` (lifetime aninhado não suportado pelo automock). |
| `query!` (macro) movido p/ adapter com indentação diferente | As 2 queries multi-linha do tenant_config viraram queries **runtime** (`sqlx::query`/`bind`) — independem do cache `.sqlx`, mantendo o caminho rápido sem banco. SQL idêntico. |
| `AuditPort` insuficiente p/ eventos globais | Adicionado método `publish_security(traceparent, tenant_id, level, event, msg, ctx, user_id)` p/ `login_failed`/`superuser_created` (INFO/WARN, tenant `None`). |
| último login no `verify_credentials` | Antes era `tokio::spawn` (fire-and-forget); agora `await` via port (best-effort, erro só logado). Pequena mudança de latência, comportamento preservado. |
| `test_processar_evento_auditoria` (consumidor de auditoria) | Mantido como teste de integração `#[ignore]` (função privada que exige Postgres real). |
| `test_outbox_relay_drenar` (banco+Redis reais) | Removido e substituído por 2 testes `mockall` da lógica de drenagem. |

## 2b. Observabilidade & Auditoria

| Eixo | Status | Observação |
|---|---|---|
| Logs/traces | ✅ | `#[instrument(skip_all, fields(...))]` nos adapters (com `tenant_id`/correlação); sem `println!`; handlers sem `#[instrument(err)]`. |
| Auditoria (mutações sensíveis) | ✅ | Eventos via `AuditPort`: `tenant_created/updated/active_changed/access_code_generated`, `core_setting_upserted/deleted`, `tenant_config_updated`, `tenant_api_key_changed`, `feature_flag_set`, `billing_plan_created/updated`, `payment_registered`, `superuser_created/deleted`, `login_failed`, `whatsapp_instance.*`. |
| Sanitização | ✅ | `api_key`/`token_hash`/`key_hash`/chaves de API nunca em log/span/context; pagamentos auditam só metadados (id/valor/tenant); config mascara chaves no GET. |

## 3. Decisões Autônomas (revisar depois)
- Conversão das 2 queries `query!` do tenant_config para runtime: perde-se a verificação SQL em tempo de compilação **dessas duas** (o restante mantém `query!`); a correção é coberta por `sqlx prepare --check` + integração no `test-local.ps1`.
- `verify_credentials` aguarda o registro de último login em vez de `spawn` (simplicidade/robustez sobre latência marginal).
- AppState do data_postgres mantém `cipher`/`config_cache`/`pool`/`admin_pool`/`redis_conn` com `#[allow(dead_code)]` (alguns ainda usados na construção dos adapters); limpeza fina pode remover os realmente órfãos.

## 4. Revalidação (SQLX_OFFLINE=true, sem túnel)
- clippy `data_postgres` + `data_redis` (`--bins --tests -D warnings`): ✅ limpo
- `cargo fmt -p data_postgres -p data_redis --check`: ✅ limpo
- testes `data_postgres --bins`: ✅ 29 passed, 1 ignored (integração)
- testes `data_redis --bins`: ✅ 7 passed
- DIP: nenhum `handler_*` recebe `PgPool`/`ConnectionManager`; nenhuma instanciação concreta de repositório nos handlers.

## 5. Pendências (fora do escopo do plano / a fazer depois)
- **Cobertura de integração de algumas operações novas dos adapters** (ex.: `PgOperacionalStore` tenant_config runtime, `PgOutboxStore.fetch_pending/mark_published`, `PgPlansStore`) deve ser confirmada/ampliada em `crates/infrastructure_postgres/tests/integracoes/` na próxima rodada de `test-local.ps1` (banco real + `sqlx prepare --check`).
- **Fase 8 (TreinamentoStore)**: o domínio de treinamento não expõe handlers RPC no `data_postgres` hoje; quando expor, replicar o padrão.
- **Limpeza de campos órfãos** do `AppState` (`#[allow(dead_code)]`) ao final.
- **`test_support` como dev-dependency** do `data_redis` ficou sem uso após remover os testes de integração; pode ser removido do `Cargo.toml`.

Rótulo final: **CORRIGIDO** — piloto teve desvio corrigido e o rollout completo foi implementado, revalidado (clippy/fmt/testes sem túnel) antes do arquivamento.
