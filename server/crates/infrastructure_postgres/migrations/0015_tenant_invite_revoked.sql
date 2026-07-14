-- ============================================================
-- Fase N3 (Painel do Tenant): revogação de convites
-- Permite ao admin do tenant revogar convites ainda não usados.
-- ============================================================

ALTER TABLE tenants_tenantinvite ADD COLUMN revoked BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE tenants_tenantinvite ADD COLUMN revoked_at TIMESTAMPTZ;
