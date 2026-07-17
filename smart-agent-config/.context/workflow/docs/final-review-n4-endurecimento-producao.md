# Final Review — n4-endurecimento-producao
Data: 2026-07-16 · Modelo: Opus · Diff: working tree (feature/n4-endurecimento-producao)

## Rótulo: CORRIGIDO

## Resumo das correções
- **Inundação da trilha de auditoria no caminho quente (defeito principal):** `CheckQuota` auditava `quota.excedida` e `tenant.bloqueado_inadimplencia` em toda chamada. Como o `webhook_ingress` invoca `CheckQuota` por mensagem recebida só para ler `inadimplente`, um tenant saudável **no limite** do plano (`uso == limite` → `excedido == true`) geraria uma linha de auditoria por mensagem. Gatilho de auditoria movido para um flag explícito `auditar` (default `false`), setado apenas no ponto de enforcement real (provisionamento em `data_whatsapp`).
- **Auditoria por-mensagem em modo log-only:** o webhook auditava `webhook.rejected` (inadimplência) em toda mensagem mesmo com `SMARTCORE_QUOTA_ENFORCE=false` (nada era rejeitado). Agora só audita na rejeição real (`enforce=true`); em log-only apenas `tracing::warn` + métricas.
- Correções menores de documentação/comentário (referência de migration e comentário estático desatualizado).
- Revalidado: `clippy --all-targets --all-features -D warnings` limpo; `cargo fmt --check` limpo.

## 1. Plano vs. Implementado
| Item do plano | Status | Observação |
|---|---|---|
| N4.1 role não-superuser (`smartcore_app_rt`, NOSUPERUSER NOBYPASSRLS) | ✅ | migrations `0016`/`0018` (idempotentes/condicionais) + `infra/provision-db-role.sh` + `ci.yml` (unifica nome) + `.env.example` (dev/prod) |
| N4.1 fronteira `pool` × `admin_pool` documentada | ✅ | `PgPlansStore::cross_tenant_pool` (assinaturas/pagamentos via `admin_pool`); doc em `connection::criar_admin_pool` |
| N4.1 revalidação RLS sob role real | ✅ | 37 verde sob `smartcore_app_rt` (validado nesta sessão) |
| N4.2 medição de uso (mensagens/mídia) via Prometheus | ✅ | `observability::usage_metrics` (OTel counters); `set_meter_provider` já inicializado em `telemetry::init_metrics` |
| N4.2 `QuotaGuard` port + adapter (RPC) + decorator | ✅ | `ports/quota.rs` + `adapters/quota.rs` + `infra tenants/quota.rs`; decorator `aplicar_quota_guard` (data_whatsapp) e ingestão (webhook) |
| N4.2 log-only → enforce via `SMARTCORE_QUOTA_ENFORCE` | ✅ | presente em webhook e data_whatsapp; default `false` no `.env` |
| N4.2 bloqueio por inadimplência (ingestão) | ✅ | 402 `PAYMENT_REQUIRED` quando `enforce`; auditado no ponto de rejeição |
| N4.2 quota de instância | ✅ | recurso `instancias` (`COUNT active` vs `plan.max_instances`) no provisionamento |
| N4.2 quota de storage / departamentos | ⚠️ | Storage é **só medição** (sem coluna de limite em `tenants_plan`, documentado no código); `Departamentos` existe no enum/RPC mas nenhum ponto de enforcement o chama — infra pronta, não cabeado |
| N4.3 retenção por política (por plano) | ✅ | `tenants_plan.retention_days` (0017) + `COALESCE(p.retention_days, $1)` em `listar_midias_expiradas` |
| N4.3 R2 lifecycle versionado | ✅ | `garantir_lifecycle` (`put_bucket_lifecycle_configuration`) + `S3_LIFECYCLE_EXPIRATION_DAYS=90` (versionado no `.env`); best-effort no boot |
| N4.3 doc `08-infraestrutura-storage` | ✅ | documentado (como §7.1, conteúdo completo) |
| N4.4 auditoria RLS / vazamento cross-tenant | ✅ | provado sob role real (sessão) |
| N4.4 rate limiting amplo | ✅ | webhook (por `tenant:instance`) + `runtime_api` (por `tenant:user`, via RPC) + rota `RegisterRateLimitAttempt` no data_redis + `chave_rate_limit`/`registrar_tentativa_recurso` |
| N4.4 testes de rajada / backpressure | ⚠️ | Validação **manual/operacional** (túnel/`test_support`); projeto proíbe testes automatizados — não há harness no diff |
| N4.4 `SecretString` + varredura de segredos | ⚠️ | `S3Config.secret_access_key` → `SecretString`; DTOs de linha/RPC (`api_key`/`token`) seguem `String` (exigem serialização sqlx/serde) mas são embrulhados em `SecretString` no uso e **nunca logados** — objetivo de sanitização atendido |

## 2. Correções Aplicadas
| Arquivo:linha | Problema | Correção |
|---|---|---|
| `server/apps/data_postgres/src/main.rs:2987` e `:3013`/`:3024` | `quota.excedida`/`tenant.bloqueado_inadimplencia` auditados em toda chamada de `CheckQuota` → inundação da trilha no caminho quente (1 evento por mensagem para tenant no limite) | Adicionado flag `auditar` (default `false`); auditoria só quando `excedido && auditar` / `inadimplente && auditar` |
| `server/apps/data_whatsapp/src/main.rs:194` | Guard de provisionamento (ponto de enforcement legítimo) não sinalizava auditoria | Payload passa `"auditar": true` |
| `server/apps/webhook_ingress/src/main.rs:347` | Audit `webhook.rejected` por-mensagem mesmo em log-only (nada era rejeitado) → inundação + evento enganoso | Audita só na rejeição real (`enforce=true`); log-only vira `tracing::warn` |
| `server/apps/worker/src/scheduler.rs:187` | Comentário afirmava que `data_storage` audita `midia.purgada` — falso (data_storage só deleta); o scheduler é quem audita | Comentário corrigido para refletir o comportamento real |
| `smart-agent-config/doc_dev/modelagem_dados/08_diretrizes_seguranca.md:30` | Doc referenciava migration `0016` para sincronizar grants da role de runtime, mas `0016` cobre a role admin; `0018` é quem sincroniza `smartcore_app_rt` | Referência corrigida para `0018` (com nota sobre `0016`) |

## 2b. Observabilidade & Auditoria
| Comportamento | Logs/Trace | Audit log | Sanitização | Observação |
|---|---|---|---|---|
| Verificação de quota (`CheckQuota`) | ✅ `#[instrument]` com `tenant_id`/`recurso`; adapter usa `run_in_tenant_transaction` | ✅ (corrigido) `quota.excedida`/`tenant.bloqueado_inadimplencia` só no ponto de enforcement | ✅ status é agregado (uso/limite), sem PII | Flooding eliminado |
| Bloqueio por inadimplência (webhook) | ✅ `tracing::warn` em log-only | ✅ (corrigido) `webhook.rejected` só na rejeição real | ✅ metadados = provider/instance/reason | — |
| Medição de uso (mensagens/mídia) | ✅ contadores OTel/Prometheus | N/A (métrica, não mutação) | ✅ só `tenant_id`/`direcao` — sem telefone/conteúdo | Cardinalidade por-tenant é design do plano |
| Rate limiting (webhook/runtime_api) | ✅ `tracing::warn` fail-open; `instrument(skip_all)` no adapter | ✅ negação real auditada (`webhook.rejected`/`rate_limit_exceeded`) | ✅ `id` opaco (`tenant:instance`/`tenant:user`), nunca logado | runtime_api via RPC; webhook direto no redis-bus (ver §5) |
| Retenção/purga de mídia | ✅ span do scheduler; logs de deleção | ✅ `midia.purgada` (INFO), 1 por arquivo, só `mensagem_id` | ✅ sem binário/nome-de-arquivo sensível | Sem duplicação (data_storage não audita) |
| Role N4.1 / lifecycle R2 | ✅ logs de boot/provisionamento | N/A (infra versionada, sem evento runtime — conforme plano) | ✅ senha em secret de ambiente; `SecretString` no `S3Config` | — |

## 3. Decisões Autônomas (revisar depois)
- **Contrato de auditoria de `CheckQuota` mudou:** introduzido flag `auditar` no payload. A rota permanece retrocompatível (default `false`), mas quem quiser eventos de auditoria precisa enviá-lo. Escolha deliberada para separar *leitura* (hot path) de *enforcement*.
- **Log-only não audita mais inadimplência por mensagem** — decisão de priorizar a higiene da trilha (métricas + `tracing::warn` cobrem a observabilidade em modo shadow). Se o time quiser evidência auditável do modo shadow, adicionar auditoria **amostrada** (ex.: 1/N) em vez de por-mensagem.

## 4. Revalidação
- clippy (Rust): ✅ `cargo clippy --all-targets --all-features -- -D warnings` limpo (SQLX_OFFLINE=true)
- fmt: ✅ `cargo fmt --check` sem diferenças
- testes: já validados nesta sessão (RLS 37 verde sob role real `smartcore_app_rt`; Redis 9 verde após fix do helper `url_redis_teste`; R2 opt-in falha por DNS ambiental — não é desvio de código)

## 5. Pendências (escopo extra ou fora do plano)
- **Quota de storage e de departamentos não cabeada:** medição de storage existe, mas falta coluna de limite em `tenants_plan` e ponto de enforcement; `Departamentos` está no enum/RPC sem caller. Follow-up: adicionar `max_storage_bytes`/guard em `data_storage` e wire de `departamentos` no CRUD de departamento.
- **Testes de rajada (N4.4.3):** não há harness no diff (projeto proíbe testes automatizados). Executar validação manual via túnel/`test_support` e documentar números de referência (medir tendência).
- **`SecretString` nas DTOs de credencial:** conversão total (`api_key`/`instance_token`/`token`) é inviável sem quebrar `sqlx::FromRow`/`serde` e o transporte por RPC. Nenhum segredo é logado hoje; se quiser robustez, criar um wrapper que redija no `Debug`/log mas ainda serialize no transporte interno.
- **Chaves de rate-limit do webhook vivem no `redis-bus`** (a conexão que o webhook já possuía), não no redis principal usado pelo `data_redis`. Funcional e isolado (em dev/CI há um único Redis), mas em prod os contadores ficam separados dos do `runtime_api`. Avaliar centralizar via a rota RPC `RegisterRateLimitAttempt` para consistência e para não depender da política de eviction do bus.
