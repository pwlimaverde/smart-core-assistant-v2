# Plano Completo — Fase N4: Endurecimento de Produção (billing, quotas, retenção, segurança)

> **Reestruturado em 2026-07-06** a partir de `doc_dev/planejamento/19-fase-N4-endurecimento-producao.md`,
> validado contra a central de libs e a doc atual do Cloudflare R2.
> **Canônico:** `.context/plans/n4-endurecimento-producao.md` · **Docs auxiliares:** [info_aux](./info_aux_n4-endurecimento-producao.md)
> **Objetivo:** prontidão comercial — role Postgres **não-superuser** (destrava o RLS de verdade),
> billing/quotas com enforcement no caminho quente, retenção de mídia por política e segurança/carga.

## Correções aplicadas (reestruturação)

| # | O quê | Por quê | Fonte |
|---|---|---|---|
| 1 | Confirmado que o R2 **suporta `PutBucketLifecycleConfiguration` via API S3** (aplicável pelo `aws-sdk-s3` Rust já usado no projeto), com `Filter.Prefix` + `Expiration.Days`; objetos removidos em **até 24h** do vencimento; máx. 1.000 regras/bucket | O plano base tratava lifecycle como "alternativa/complemento" sem confirmar viabilidade pela API | developers.cloudflare.com/r2 (2026-07-06) |
| 2 | N4.1 detalhado com SQL de referência da role (`NOSUPERUSER NOBYPASSRLS` + grants DML mínimos + `ALTER DEFAULT PRIVILEGES`) e nota sobre `FORCE ROW LEVEL SECURITY` | Concretiza a tarefa e evita recriar a role com privilégio demais | Postgres docs (padrão) + memória `db-remoto-role-bootstrap-superuser` |
| 3 | Enforcement de quota nasce em **modo log-only** com flag para "enforce" | Mitigação de falso positivo promovida a passo do plano (não só risco) | prática do próprio plano base |
| 4 | Nenhuma correção de API nas libs Rust (sqlx 0.9, redis 0.25, aws-sdk-s3 1.135) | Central ✅ | triagem 2026-07-06 |

## 0. Estado real (aterramento)

| Área | Referência | Estado | Impacto |
|---|---|---|---|
| Role do Postgres | memória `db-remoto-role-bootstrap-superuser` | `smartcore_app` é bootstrap **superuser** → RLS não exercitado; teste de isolamento de `audit_log` falha por ambiente | N4.1 cria role dedicada e revalida |
| Plans/Subscription | `tenants/plans.rs`, `tenants/settings.rs` + telas admin | CRUD pronto; **sem enforcement** | N4.2 aplica limites |
| Quota de atendentes | `operacional/atendentes.rs:148` | Padrão de subquery de limite já existe | N4.2 estende a quotas de tenant |
| Purga de mídia | `data_storage` (`processar_purga_midia`) + scheduler (N1.2) | Consumidor pronto; disparo por idade vem da N1.2 | N4.3 adiciona política por plano |
| Rate limiting | `data_redis` (rate_limiter de login) | Só login | N4.4 amplia |
| Testes de isolamento | `infrastructure_postgres/tests/` | Parcialmente cegos em dev (role superuser) | N4.1 destrava |

> **N4.1 é pré-condição de credibilidade** — candidata a **antecipação para logo após N1** (decisão do dono na fase P).

## 1. Escopo

**Dentro:** N4.1 role não-superuser · N4.2 billing/usage/quotas · N4.3 retenção por política · N4.4 segurança/carga.
**Fora:** dashboards (curados na N1.4 — aqui só métricas novas); local engine/offline (→ N5).

## 2. Etapas

### N4.1 — Role Postgres não-superuser (destrava o RLS)

Superuser **ignora RLS** — em dev as policies fail-closed nunca são testadas de verdade.

1. Role de aplicação **não-superuser** (sem `BYPASSRLS`), privilégios mínimos (DML nas tabelas de domínio; sem DDL) — SQL de referência no info_aux (`CREATE ROLE ... NOSUPERUSER NOBYPASSRLS` + grants + `ALTER DEFAULT PRIVILEGES`; avaliar `FORCE ROW LEVEL SECURITY` nas tabelas de tenant). Migrar o `admin_pool` (audit global) para role separada e mínima, documentando a fronteira `pool` × `admin_pool`.
2. Ajustar provisionamento (`infra/server-setup.sh`/bootstrap) e `.env` por ambiente.
3. **Revalidar** a suíte de isolamento (`infrastructure_postgres/tests/`) — o teste de `audit_log` hoje cego deve **passar**; atualizar a memória `db-remoto-role-bootstrap-superuser` quando resolvido.

**Observabilidade & Auditoria:** logs de migração/provisionamento; **sem evento de auditoria em runtime** (mudança de infra, versionada em migration/script). Senha da role só em secret de ambiente.

**DoD:** app roda com a role nova; suíte de isolamento **verde** (incl. o teste antes cego); fronteira de pools documentada.

### N4.2 — Billing/usage e quotas

1. **Medição de uso:** contadores por tenant (mensagens recebidas/enviadas, mídia armazenada, instâncias ativas) atualizados no caminho de ingestão/envio e expostos como métricas Prometheus.
2. **Enforcement:** `QuotaGuard { verificar(tenant, recurso) }` (port) + adapter lendo `plan`/`subscription` via RPC; aplicado como **decorator** nos caminhos de ingestão/envio (`webhook_ingress`/`worker`/`data_whatsapp`) — OCP, sem reescrever handlers. **Modo log-only primeiro** (correção #3), depois enforce por flag.
3. **Bloqueio por inadimplência:** assinatura vencida → tenant bloqueado (ingestão rejeitada, auditada); refletido no painel admin (rotas existentes).
4. **Quotas de instância/storage:** guard ao provisionar instância Evolution e ao gravar mídia (reusar o padrão de subquery de `atendentes.rs:148`).

**Observabilidade & Auditoria:**
- *Logs/trace:* spans `quota.verificada`, `billing.bloqueado` com `tenant_id`; métricas de uso no Prometheus.
- *Auditoria:* `quota.excedida` (WARN), `tenant.bloqueado_inadimplencia` (WARN) — `Subscription`/`PaymentRecord` são eventos críticos (doc 08 §4.2), com `user_agent`/`ip` quando houver ator.
- *Sanitização:* métricas são contadores agregados — sem PII/telefone/conteúdo.

**DoD:** excedente barrado/limitado com auditoria; inadimplente bloqueado ponta-a-ponta; métricas visíveis; `clippy -D warnings` + `.\infra\test-local.ps1` verde.

### N4.3 — Retenção de mídia por política

1. Política configurável (por plano/tenant, default ≤ 30 dias): o scheduler (N1.2) consulta a política e dispara purga dos `MediaPointer`s vencidos; `data_storage` remove do R2. **O resumo/análise permanece.**
2. **R2 lifecycle como defesa em profundidade** (correção #1): regra por prefixo com `Expiration.Days` conservador aplicada via `put_bucket_lifecycle_configuration` (aws-sdk-s3) ou wrangler — config **versionada** no repositório. A purga primária continua aplicativa (respeita política por plano).
3. Documentar em `doc_dev/planejamento/08-infraestrutura-storage.md §8`.

**Observabilidade & Auditoria:** span do scheduler ao consultar política; `midia.retida`/`midia.purgada` (INFO) com só ids de `MediaPointer`.

**DoD:** mídia além da retenção removida do R2; resumo persiste; auditado; nenhum binário órfão; lifecycle versionado aplicado ao bucket.

### N4.4 — Segurança e carga

1. **Auditoria RLS:** revisão das policies por tabela (fail-closed) + testes de vazamento cross-tenant ampliados (agora com a role da N4.1 — os testes finalmente provam algo).
2. **Rate limiting amplo:** estender o `rate_limiter` do `data_redis` (hoje só login) ao webhook (por instância/tenant) e rotas quentes do `runtime_api`.
3. **Testes de rajada:** picos de `messages.upsert`; medir backlog de outbox e lag de consumer group; validar backpressure (via `test_support`/túnel — medir tendência, não pico único).
4. **Revisão de segredos:** `SecretString` em todas as structs com credencial; varredura de logs por token/JWT/api key/telefone.

**Observabilidade & Auditoria:** métricas de rajada/lag; negações de rate limit auditadas **por amostragem** (não inundar a trilha); zero segredo/PII em log (varredura é entregável).

**DoD:** vazamento verde com role real; rate limiting barra rajada; carga documentada com números de referência; varredura de logs limpa.

## 3. SOLID / Ports & Adapters

- **Quota/billing:** port `QuotaGuard` + adapter RPC; enforcement como decorator (OCP).
- **Retenção:** política é value object; scheduler depende do port de leitura de `MediaPointer` (N1.2) e publica no bus (adapter Redis).

## 4. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Migração de role quebra permissões em prod | Fora do ar | Primeiro em dev; grants mínimos revisados; rollback documentado |
| Quota barra tenant legítimo | Perda de mensagem | Log-only antes de enforce (correção #3); auditoria de toda negação |
| Purga remove mídia em uso | Perda de dado | Só purgar com resumo/análise gravados; retenção conservadora; lifecycle com margem extra sobre a política |
| Carga instável no ambiente remoto | Falso negativo | `test_support` (túnel); janela isolada; tendência, não pico |

## 5. Frontmatter PREVC

| Fase | P | R | E | V | C |
|---|---|---|---|---|---|
| **N4** | Role não-superuser + modelo de quota | Aprovar grants mínimos + `QuotaGuard` + política de retenção | Role; enforcement; retenção; rate limiting/carga | `test-local.ps1`: isolamento verde (role real) + quota/bloqueio + carga | Métricas de uso; eventos auditados; sem vazamento |
