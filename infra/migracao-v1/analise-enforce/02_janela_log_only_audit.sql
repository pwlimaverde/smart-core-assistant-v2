-- =============================================================================
-- N8.3 — Frequência do evento 'quota.excedida' na trilha de auditoria
-- (audit_log) durante a janela de observação log-only.
-- =============================================================================
-- IMPORTANTE — cobertura desigual entre recursos (ver README.md):
--
--   * 'instancias' — auditado INCONDICIONALMENTE. O guard de provisionamento de
--     instância (server/apps/data_whatsapp/src/main.rs::aplicar_quota_guard)
--     chama CheckQuota com `auditar: true` sempre, então toda vez que
--     excedido=true vira uma linha aqui, independente de
--     SMARTCORE_QUOTA_ENFORCE. Este é o único recurso em que esta consulta dá
--     uma série histórica de verdade.
--
--   * 'departamentos' e 'storage' — só auditam quando `auditar` acompanha a
--     PRÓPRIA flag de enforce (server/apps/data_postgres/src/main.rs e
--     server/apps/data_storage/src/main.rs). Em log-only (enforce=false, o
--     padrão em produção até hoje) eles NUNCA publicam em audit_log — só um
--     tracing::warn! (ver 03_loki_logql_storage_departamentos.md). Se esta
--     consulta retornar 0 linhas para esses dois recursos, isso é ESPERADO e
--     não significa "sem excesso" — significa "sem sinal nesta fonte". Use
--     01_estado_atual_quotas.sql (snapshot atual, sempre confiável) como fonte
--     primária para 'departamentos'/'storage'; use este script só como
--     confirmação de frequência para 'instancias'.
--
-- Uso:
--   psql "$DATABASE_ADMIN_URL" -f 02_janela_log_only_audit.sql
--
-- Ajuste a janela abaixo para o período de observação decidido na N7 antes de
-- rodar (psql expande as variáveis :'janela_inicio'/:'janela_fim').
-- =============================================================================

\set janela_inicio '2026-04-01'
\set janela_fim '2026-07-01'

SELECT
    (a.context ->> 'recurso')                AS recurso,
    t.name                                    AS tenant_name,
    a.tenant_id,
    COUNT(*)                                  AS ocorrencias,
    MIN(a.created_at)                         AS primeira_ocorrencia,
    MAX(a.created_at)                         AS ultima_ocorrencia,
    MAX((a.context ->> 'uso_atual')::bigint)  AS uso_atual_max_no_periodo,
    MAX((a.context ->> 'limite')::bigint)     AS limite_no_periodo
FROM audit_log a
LEFT JOIN tenants_tenant t ON t.id = a.tenant_id
WHERE a.event = 'quota.excedida'
  AND a.created_at >= :'janela_inicio'::timestamptz
  AND a.created_at <  :'janela_fim'::timestamptz
GROUP BY 1, 2, a.tenant_id
ORDER BY ocorrencias DESC;

-- Complemento: mesma coisa para inadimplência (não é "quota" no sentido de
-- max_instancias/max_departamentos/max_storage_bytes, mas usa a MESMA flag
-- SMARTCORE_QUOTA_ENFORCE e o mesmo guard — relevante pro rollout do runbook).
-- Este evento também só é auditado quando enforce=true no ponto de
-- provisionamento (data_whatsapp); no caminho quente de ingestão
-- (webhook_ingress) é sempre log-only (ver README.md).
SELECT
    t.name AS tenant_name,
    a.tenant_id,
    COUNT(*) AS ocorrencias,
    MIN(a.created_at) AS primeira_ocorrencia,
    MAX(a.created_at) AS ultima_ocorrencia
FROM audit_log a
LEFT JOIN tenants_tenant t ON t.id = a.tenant_id
WHERE a.event = 'tenant.bloqueado_inadimplencia'
  AND a.created_at >= :'janela_inicio'::timestamptz
  AND a.created_at <  :'janela_fim'::timestamptz
GROUP BY 1, a.tenant_id
ORDER BY ocorrencias DESC;
