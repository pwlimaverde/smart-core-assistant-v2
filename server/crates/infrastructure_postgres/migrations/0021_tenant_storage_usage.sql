-- N7.1 — quota de armazenamento por tenant (storage).
-- NULL em max_storage_bytes = ilimitado (comportamento conservador, mesmo padrão
-- de retention_days em 0017): tenants em planos legados/trial não são bloqueados
-- até terem um limite explícito configurado.
ALTER TABLE tenants_plan
    ADD COLUMN IF NOT EXISTS max_storage_bytes BIGINT;

COMMENT ON COLUMN tenants_plan.max_storage_bytes IS
    'Limite de armazenamento de mídia em bytes para tenants neste plano; NULL = ilimitado (log-only).';

-- Uso agregado de armazenamento por tenant, incrementado a cada upload bem-sucedido
-- em data_storage (RPC RegisterStorageUsage, chamada após o PutFile no R2).
CREATE TABLE tenants_storage_usage (
    tenant_id   UUID PRIMARY KEY REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    total_bytes BIGINT NOT NULL DEFAULT 0,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tenants_storage_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_storage_usage FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_storage_usage_tenant_isolation ON tenants_storage_usage
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
