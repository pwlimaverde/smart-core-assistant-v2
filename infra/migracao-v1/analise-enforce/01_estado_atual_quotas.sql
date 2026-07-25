-- =============================================================================
-- N8.3 — Estado ATUAL de quota por tenant/recurso/plano.
-- =============================================================================
-- Recalcula, diretamente contra o banco, a MESMA lógica de
-- server/crates/infrastructure_postgres/src/tenants/quota.rs::verificar_quota
-- para os 3 recursos com limite hoje: instancias, departamentos, storage.
--
-- Por que "recalcular o estado atual" em vez de só ler métricas históricas?
-- A trilha de auditoria do modo log-only (N7) NÃO é uniforme entre recursos
-- (ver README.md desta pasta) — 'storage' e 'departamentos' só geram evento de
-- auditoria quando o guard vai de fato bloquear (ou seja, quando
-- SMARTCORE_QUOTA_ENFORCE=true), que é justamente o que NUNCA aconteceu em
-- produção até hoje. 'instancias' é o único recurso auditado incondicionalmente
-- (ver 02_janela_log_only_audit.sql). Este script cobre os 3 recursos de forma
-- uniforme porque 'uso_atual' já é um contador persistido (COUNT/soma), não uma
-- métrica de taxa — logo o snapshot de HOJE já reflete o efeito acumulado da
-- janela de observação, sem depender de nenhum log.
--
-- Pré-requisito: rodar como o role BOOTSTRAP (smartcore_app / DATABASE_ADMIN_URL),
-- nunca como smartcore_app_rt — RLS em tenants_subscription/tenants_storage_usage
-- filtra por app.current_tenant e bloquearia a leitura cross-tenant necessária
-- aqui. Isto é uma ferramenta de análise offline (mesmo padrão do ETL em
-- infra/migracao-v1/), não um novo caminho de aplicação — ver README.md.
--
-- Uso:
--   psql "$DATABASE_ADMIN_URL" -f 01_estado_atual_quotas.sql
--
-- (ou via infra/tunnel.ps1 -Env prod / tunnel.sh, se acessando de fora do
-- servidor — ver infra/migracao-v1/analise-enforce/README.md)
-- =============================================================================

WITH uso_instancias AS (
    SELECT tenant_id, COUNT(*)::bigint AS uso_atual
    FROM oraculo_app_instance
    WHERE active = true
    GROUP BY tenant_id
),
uso_departamentos AS (
    SELECT tenant_id, COUNT(*)::bigint AS uso_atual
    FROM oraculo_departamento
    WHERE ativo = true
    GROUP BY tenant_id
),
uso_storage AS (
    SELECT tenant_id, COALESCE(total_bytes, 0)::bigint AS uso_atual
    FROM tenants_storage_usage
),
base AS (
    -- Só tenants com assinatura vinculada têm limite aplicável (mesma postura
    -- conservadora do código: sem assinatura = sem bloqueio, nunca aparece aqui
    -- como "excedido"). Tenants sem tenants_subscription ficam de fora do
    -- relatório por construção — se isso for inesperado, ver a NOTA no README
    -- sobre tenants órfãos/trial.
    SELECT
        t.id      AS tenant_id,
        t.name    AS tenant_name,
        t.active  AS tenant_active,
        p.id      AS plan_id,
        p.name    AS plan_name,
        p.active  AS plan_active,
        s.status  AS subscription_status,
        p.max_instances,
        p.max_departments,
        p.max_storage_bytes
    FROM tenants_tenant t
    JOIN tenants_subscription s ON s.tenant_id = t.id
    JOIN tenants_plan p ON p.id = s.plan_id
),
por_recurso AS (
    SELECT
        b.plan_id, b.plan_name, b.tenant_id, b.tenant_name, b.tenant_active,
        b.subscription_status,
        'instancias'::text        AS recurso,
        b.max_instances::bigint   AS limite,
        COALESCE(ui.uso_atual, 0) AS uso_atual
    FROM base b
    LEFT JOIN uso_instancias ui ON ui.tenant_id = b.tenant_id

    UNION ALL

    SELECT
        b.plan_id, b.plan_name, b.tenant_id, b.tenant_name, b.tenant_active,
        b.subscription_status,
        'departamentos'::text,
        b.max_departments::bigint,
        COALESCE(ud.uso_atual, 0)
    FROM base b
    LEFT JOIN uso_departamentos ud ON ud.tenant_id = b.tenant_id

    UNION ALL

    SELECT
        b.plan_id, b.plan_name, b.tenant_id, b.tenant_name, b.tenant_active,
        b.subscription_status,
        'storage'::text,
        b.max_storage_bytes,      -- NULL = ilimitado (mesma semântica do código)
        COALESCE(us.uso_atual, 0)
    FROM base b
    LEFT JOIN uso_storage us ON us.tenant_id = b.tenant_id
),
avaliado AS (
    SELECT
        *,
        (limite IS NOT NULL AND uso_atual >= limite) AS excedido,
        CASE WHEN limite IS NOT NULL
             THEN GREATEST(uso_atual - limite, 0)
             ELSE NULL
        END AS excesso
    FROM por_recurso
)

-- -----------------------------------------------------------------------------
-- Bloco 1: resumo por (plano, recurso) — quantos tenants excedem hoje e por
-- quanto (útil pra decidir se o limite do plano está bem calibrado).
-- -----------------------------------------------------------------------------
SELECT
    plan_name,
    recurso,
    COUNT(*)                                                                  AS tenants_no_plano,
    COUNT(*) FILTER (WHERE excedido)                                          AS tenants_excedendo,
    ROUND(100.0 * COUNT(*) FILTER (WHERE excedido) / NULLIF(COUNT(*), 0), 1)  AS pct_excedendo,
    MIN(excesso) FILTER (WHERE excedido)                                      AS excesso_min,
    ROUND(AVG(excesso) FILTER (WHERE excedido), 1)                            AS excesso_medio,
    MAX(excesso) FILTER (WHERE excedido)                                      AS excesso_max,
    -- soma do excesso agregado do plano — pra 'storage' dá a ordem de grandeza
    -- do "buraco" total em bytes se o enforce ligasse hoje.
    SUM(excesso) FILTER (WHERE excedido)                                      AS excesso_total
FROM avaliado
GROUP BY plan_name, recurso
ORDER BY plan_name, recurso;

-- -----------------------------------------------------------------------------
-- Bloco 2: lista nominal dos tenants que SERIAM bloqueados hoje, para revisão
-- manual antes de ligar o enforce (o risco real é bloquear cliente legítimo por
-- limite mal calibrado — ver RUNBOOK_ENFORCE_ROLLOUT_N8.md).
-- -----------------------------------------------------------------------------
SELECT
    plan_name,
    recurso,
    tenant_name,
    tenant_id,
    tenant_active,
    subscription_status,
    limite,
    uso_atual,
    excesso
FROM avaliado
WHERE excedido
ORDER BY recurso, excesso DESC;
