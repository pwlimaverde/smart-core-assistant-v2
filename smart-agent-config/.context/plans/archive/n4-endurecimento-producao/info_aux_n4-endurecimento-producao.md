# Documentação Auxiliar — Fase N4: Endurecimento de Produção

> Gerado em: 2026-07-06
> Plano canônico: `.context/plans/n4-endurecimento-producao.md`
> Plano completo: `.context/plans/n4-endurecimento-producao/plano_completo_n4-endurecimento-producao.md`
> Origem do plano-base: `doc_dev/planejamento/19-fase-N4-endurecimento-producao.md`

## Libs Rust (todas USAR LOCAL — central `doc_dev/libs/rust/`)

| Lib | Versão | Verificação | Uso na N4 |
|---|---|---|---|
| sqlx | 0.9 | 2026-06-10 | migrations de role/grants; queries de quota (padrão de subquery de limite já em `atendentes.rs:148`) |
| redis | 0.25.0 | 2026-06-10 | rate limiting amplo (extensão do `rate_limiter` de login do `data_redis`) |
| aws-sdk-s3 | 1 (1.135.0) | 2026-06-06 | `put_bucket_lifecycle_configuration` no R2 (defesa em profundidade da retenção) |
| secrecy | 0.10.3 | 2026-06-01 | varredura: toda struct com credencial usa `SecretString`/`SecretVec` |
| tracing | 0.1.40 | 2026-05-31 | spans de enforcement (`quota.verificada`, `billing.bloqueado`) |

## Postgres — role não-superuser (N4.1)
Referências do projeto (não é lib): `doc_dev/modelagem_dados/08_diretrizes_seguranca.md` (RLS fail-closed), memória `db-remoto-role-bootstrap-superuser` (estado atual: `smartcore_app` é bootstrap **superuser** → RLS nunca é exercitado em dev; teste de isolamento de `audit_log` falha por ambiente).

SQL de referência (padrão Postgres, sem lib externa):

```sql
-- role de aplicação mínima (sem BYPASSRLS, sem DDL)
CREATE ROLE smartcore_app_rt LOGIN PASSWORD :'pwd' NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
GRANT USAGE ON SCHEMA public TO smartcore_app_rt;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app_rt;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smartcore_app_rt;
-- role separada e mínima para o admin_pool (audit global), fronteira documentada
```

- Superuser **ignora RLS** — por isso a suíte de isolamento só prova algo com a role nova.
- `FORCE ROW LEVEL SECURITY` nas tabelas de tenant garante que até o owner passa pelas policies.

## Serviços Externos

### Cloudflare R2 — Object Lifecycle Rules (N4.3)
Fonte: [developers.cloudflare.com/r2/buckets/object-lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/), coletado em 2026-07-06.

- Configuração: dashboard, `npx wrangler r2 bucket lifecycle set <BUCKET> --file <FILE>` ou **API S3 `PutBucketLifecycleConfiguration`** (o `aws-sdk-s3` Rust aplica normalmente — estrutura compatível com AWS S3).
- Schema de regra: `ID`, `Status` (Enabled/Disabled), `Filter.Prefix`, `Expiration.Days`/`Expiration.Date`, `AbortIncompleteMultipartUpload.DaysAfterInitiation`; transições de classe (Standard → Infrequent Access) também suportadas.
- Comportamento: objetos removidos **em até 24h** do vencimento (`x-amz-expiration`); máx. 1.000 regras/bucket; deleção tem precedência sobre transição.
- Uso na N4.3: regra por prefixo de mídia com `Expiration.Days` conservador como **defesa em profundidade**; a purga primária continua sendo aplicativa (scheduler N1.2 → evento no bus → `data_storage`), que respeita a política por plano e garante que o **resumo permanece**.

Exemplo (aws-sdk-s3 Rust, esboço):

```rust
client.put_bucket_lifecycle_configuration()
    .bucket(bucket)
    .lifecycle_configuration(
        BucketLifecycleConfiguration::builder().rules(
            LifecycleRule::builder()
                .id("expira-midia-90d").status(ExpirationStatus::Enabled)
                .filter(LifecycleRuleFilter::builder().prefix("media/").build())
                .expiration(LifecycleExpiration::builder().days(90).build())
                .build()?,
        ).build()?,
    ).send().await?;
```

## Grupo C — Observabilidade e Auditoria (por etapa)

| Etapa | Logs/trace | Auditoria | Sanitização |
|---|---|---|---|
| N4.1 role não-superuser | logs de migração/provisionamento | sem evento de auditoria em runtime (mudança de infra; registrada em migration/infra versionada) | senha da role só em secret de ambiente |
| N4.2 billing/quotas | spans `quota.verificada`, `billing.bloqueado` com `tenant_id`; métricas de uso no Prometheus | `quota.excedida` (WARN), `tenant.bloqueado_inadimplencia` (WARN) — `Subscription`/`PaymentRecord` são eventos críticos (doc 08 §4.2) | métricas são contadores agregados — sem PII |
| N4.3 retenção | span do scheduler consultando política | `midia.retida`/`midia.purgada` (INFO) | só ids de `MediaPointer` |
| N4.4 segurança/carga | métricas de rajada; lag de consumer group | negações de rate limit auditadas por amostragem (evitar inundar trilha) | varredura de logs por token/JWT/api key/telefone |

## Notas Gerais
- N4.1 é pré-condição de credibilidade dos testes de RLS — candidata a **antecipação** (logo após N1).
- Enforcement de quota nasce em modo **log-only** antes de "enforce" (mitigação de falso positivo).
- Rate limiter existente: `data_redis` (só login) — estender por instância/tenant no webhook e rotas quentes.
