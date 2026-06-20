-- ============================================================
-- Módulo Feature Flags: controle de liberação de funcionalidades
-- feature_flags: tabela global (sem RLS)
-- feature_flag_overrides: tabela com isolamento RLS por tenant
-- ============================================================

CREATE TABLE feature_flags (
    key              VARCHAR(100) PRIMARY KEY,
    description      TEXT NOT NULL,
    enabled_globally BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE feature_flag_overrides (
    feature_key VARCHAR(100) REFERENCES feature_flags(key) ON DELETE CASCADE,
    tenant_id   UUID REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    enabled     BOOLEAN NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (feature_key, tenant_id)
);

-- ============================================================
-- RLS (Row Level Security) para overrides
-- ============================================================

ALTER TABLE feature_flag_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flag_overrides FORCE ROW LEVEL SECURITY;

CREATE POLICY feature_flag_overrides_isolation ON feature_flag_overrides
    FOR ALL
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    );

-- Insere feature flags padrão para fins de demonstração/inicialização
INSERT INTO feature_flags (key, description, enabled_globally) VALUES
    ('chat_gpt_4o', 'Habilita o uso de GPT-4o em vez de GPT-4o-mini', false),
    ('voice_messages', 'Habilita o processamento e transcrição de áudios', true),
    ('dashboard_v2', 'Exibe a nova interface gráfica do dashboard', false)
ON CONFLICT (key) DO NOTHING;
