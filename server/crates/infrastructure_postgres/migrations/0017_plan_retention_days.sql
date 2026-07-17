-- N4.3 — retenção de mídia configurável por plano.
-- NULL = usa o default global do scheduler (SMARTCORE_SCHEDULER_MEDIA_IDADE_MAX_DIAS,
-- hoje 30 dias) — ver `listar_midias_expiradas` (JOIN com tenants_plan, COALESCE).
ALTER TABLE tenants_plan
    ADD COLUMN IF NOT EXISTS retention_days INT;

COMMENT ON COLUMN tenants_plan.retention_days IS
    'Dias de retenção de mídia para tenants neste plano; NULL = usa o default global do scheduler.';
