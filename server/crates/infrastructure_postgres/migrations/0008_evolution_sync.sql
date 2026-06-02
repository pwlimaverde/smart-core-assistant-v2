-- ============================================================
-- Módulo Integrações WhatsApp (Evolution API): instâncias, contatos e whitelist
-- ============================================================

-- EvolutionInstance: configuração da instância física na Evolution API centralizada
CREATE TABLE evolution_sync_instance (
    id                    SERIAL PRIMARY KEY,
    tenant_id             UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    name                  VARCHAR(100) NOT NULL,
    instance_id           VARCHAR(100) UNIQUE,
    api_key               VARCHAR(256) NOT NULL,
    phone_number          VARCHAR(20),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    connection_state      VARCHAR(20) NOT NULL DEFAULT 'unknown',
    last_state_check      TIMESTAMPTZ,
    media_storage_backend VARCHAR(10) NOT NULL DEFAULT 's3',
    subscribed_events     JSONB NOT NULL DEFAULT '[]',
    last_connection_state VARCHAR(50),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)
);

ALTER TABLE evolution_sync_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE evolution_sync_instance FORCE  ROW LEVEL SECURITY;
CREATE POLICY evolution_sync_instance_tenant_isolation ON evolution_sync_instance
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX evolution_sync_instance_tenant_state
    ON evolution_sync_instance (tenant_id, active, connection_state);

-- EvolutionContact: mapeamento JID/LID → Contato do CRM
CREATE TABLE evolution_sync_contact (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id      INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    instance_id     INT NOT NULL REFERENCES evolution_sync_instance(id) ON DELETE CASCADE,
    jid             VARCHAR(100),
    lid             VARCHAR(100),
    addressing_mode VARCHAR(8),
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    metadados       JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, instance_id, jid)
);

ALTER TABLE evolution_sync_contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE evolution_sync_contact FORCE  ROW LEVEL SECURITY;
CREATE POLICY evolution_sync_contact_tenant_isolation ON evolution_sync_contact
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX evolution_sync_contact_tenant_jid ON evolution_sync_contact (tenant_id, jid);
CREATE INDEX evolution_sync_contact_tenant_lid ON evolution_sync_contact (tenant_id, lid);
CREATE INDEX evolution_sync_contact_tenant_crm ON evolution_sync_contact (tenant_id, contact_id);

-- WhiteList: números que o bot deve ignorar completamente
CREATE TABLE evolution_sync_whitelist (
    id           SERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contact_id   INT REFERENCES oraculo_contato(id) ON DELETE SET NULL,
    name         VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, phone_number)
);

ALTER TABLE evolution_sync_whitelist ENABLE ROW LEVEL SECURITY;
ALTER TABLE evolution_sync_whitelist FORCE  ROW LEVEL SECURITY;
CREATE POLICY evolution_sync_whitelist_tenant_isolation ON evolution_sync_whitelist
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX evolution_sync_whitelist_tenant_phone ON evolution_sync_whitelist (tenant_id, phone_number);
