-- ============================================================
-- Módulo Mensageria WhatsApp (genérico, multi-provedor)
-- ============================================================
CREATE TABLE whatsapp_instance (
    id                    SERIAL PRIMARY KEY,
    tenant_id             UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    name                  VARCHAR(100) NOT NULL,
    instance_id           VARCHAR(100) UNIQUE,
    api_key               VARCHAR(256) NOT NULL,          -- encriptado em repouso
    phone_number          VARCHAR(20),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    connection_state      VARCHAR(20) NOT NULL DEFAULT 'unknown',
    last_state_check      TIMESTAMPTZ,
    media_storage_backend VARCHAR(10) NOT NULL DEFAULT 's3',
    provider              VARCHAR(50) NOT NULL,           -- SEM default acoplado
    subscribed_events     JSONB NOT NULL DEFAULT '[]',
    last_connection_state VARCHAR(50),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)                              -- removido UNIQUE(name) global (quebra multi-tenancy)
);
ALTER TABLE whatsapp_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_instance FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_instance_tenant_isolation ON whatsapp_instance
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_instance_tenant_state ON whatsapp_instance (tenant_id, active, connection_state);

CREATE TABLE whatsapp_contact (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id      INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    instance_id     INT NOT NULL REFERENCES whatsapp_instance(id) ON DELETE CASCADE,
    jid             VARCHAR(100),
    lid             VARCHAR(100),
    addressing_mode VARCHAR(8),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    metadados       JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, instance_id, jid)
);
ALTER TABLE whatsapp_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_contact FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_contact_tenant_isolation ON whatsapp_contact
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_contact_tenant_jid ON whatsapp_contact (tenant_id, jid);
CREATE INDEX whatsapp_contact_tenant_lid ON whatsapp_contact (tenant_id, lid);
CREATE INDEX whatsapp_contact_tenant_crm ON whatsapp_contact (tenant_id, contact_id);

CREATE TABLE whatsapp_whitelist (
    id           SERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id   INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    name         VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, phone_number)
);
ALTER TABLE whatsapp_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_whitelist FORCE  ROW LEVEL SECURITY;
CREATE POLICY whatsapp_whitelist_tenant_isolation ON whatsapp_whitelist
    FOR ALL USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
CREATE INDEX whatsapp_whitelist_tenant_phone ON whatsapp_whitelist (tenant_id, phone_number);
