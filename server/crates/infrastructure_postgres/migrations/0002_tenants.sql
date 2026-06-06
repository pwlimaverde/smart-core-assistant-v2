-- ============================================================
-- Módulo Tenants: tenant raiz, config de IA, usuários e convites
-- ============================================================

CREATE TABLE tenants_tenant (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name             VARCHAR(100) NOT NULL,
    slug             VARCHAR(100) NOT NULL UNIQUE,
    api_key          VARCHAR(100) NOT NULL UNIQUE,
    owner_id         INT NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
    email            VARCHAR(254) NOT NULL DEFAULT '',
    phone            VARCHAR(20),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    setup_completed  BOOLEAN NOT NULL DEFAULT FALSE,
    onboarding_step  INT NOT NULL DEFAULT 1,
    access_code      VARCHAR(20),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS usa a PK id (tabela raiz, não possui coluna tenant_id)
ALTER TABLE tenants_tenant ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_tenant FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_tenant_tenant_isolation ON tenants_tenant
    FOR ALL
    USING (id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX tenants_tenant_slug       ON tenants_tenant (slug);
CREATE INDEX tenants_tenant_api_key    ON tenants_tenant (api_key);

-- ------------------------------------------------------------
-- TenantConfig: configurações de IA, LLM, RAG e branding por tenant
-- ------------------------------------------------------------
CREATE TABLE tenants_tenantconfig (
    id                       SERIAL PRIMARY KEY,
    tenant_id                UUID NOT NULL UNIQUE REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    -- Prompts de IA (campos explícitos)
    dados_empresa            TEXT,
    persona_bot              TEXT,
    bot_agent_name           VARCHAR(80),
    -- Mensagens automáticas (null = usa o global do CoreSettings)
    msg_fallback             VARCHAR(500),
    msg_sem_info             VARCHAR(500),
    msg_transferencia        VARCHAR(500),
    -- Extração de entidades
    entity_types             JSONB NOT NULL DEFAULT '{}',
    -- LLM
    llm_class                VARCHAR(50),
    model                    VARCHAR(100),
    llm_temperature          NUMERIC(3,2),
    -- Transcrição e visão
    transcription_provider   VARCHAR(50),
    transcription_model      VARCHAR(100),
    vision_provider          VARCHAR(50),
    vision_model             VARCHAR(100),
    -- Embeddings e RAG
    embeddings_class         VARCHAR(50),
    embeddings_model         VARCHAR(100),
    chunk_size               INT,
    chunk_overlap            INT,
    -- Thresholds de similaridade
    similarity_threshold         NUMERIC(3,2),
    vector_distance_threshold    NUMERIC(3,2),
    -- Chaves de API locais criptografadas (AES-256-GCM, formato JSONB)
    api_keys                 JSONB NOT NULL DEFAULT '{}',
    -- Branding e regionalização
    brand_name               VARCHAR(100),
    primary_color            VARCHAR(7)  NOT NULL DEFAULT '#0d6efd',
    secondary_color          VARCHAR(7)  NOT NULL DEFAULT '#6c757d',
    timezone                 VARCHAR(50) NOT NULL DEFAULT 'America/Sao_Paulo',
    language_code            VARCHAR(10) NOT NULL DEFAULT 'pt-br',
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tenants_tenantconfig ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_tenantconfig FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_tenantconfig_tenant_isolation ON tenants_tenantconfig
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- ------------------------------------------------------------
-- TenantUser: perfil de funcionário vinculado a um tenant
-- ------------------------------------------------------------
CREATE TABLE tenants_tenantuser (
    id                  SERIAL PRIMARY KEY,
    user_id             INT NOT NULL UNIQUE REFERENCES auth_user(id) ON DELETE CASCADE,
    tenant_id           UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    role                VARCHAR(20) NOT NULL DEFAULT 'staff',
    module_permissions  JSONB NOT NULL DEFAULT '{}',
    flow_permissions    JSONB NOT NULL DEFAULT '[]',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by_id       INT REFERENCES auth_user(id) ON DELETE SET NULL
);

ALTER TABLE tenants_tenantuser ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_tenantuser FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_tenantuser_tenant_isolation ON tenants_tenantuser
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX tenants_tenantuser_tenant_user ON tenants_tenantuser (tenant_id, user_id);

-- ------------------------------------------------------------
-- TenantInvite: convites com token seguro (64 chars URL-safe)
-- ------------------------------------------------------------
CREATE TABLE tenants_tenantinvite (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    email           VARCHAR(254) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    role            VARCHAR(20) NOT NULL DEFAULT 'staff',
    module_permissions  JSONB NOT NULL DEFAULT '{}',
    flow_permissions    JSONB NOT NULL DEFAULT '[]',
    token           VARCHAR(64) NOT NULL UNIQUE,
    expires_at      TIMESTAMPTZ NOT NULL,
    used            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by_id   INT REFERENCES auth_user(id) ON DELETE SET NULL
);

ALTER TABLE tenants_tenantinvite ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_tenantinvite FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_tenantinvite_tenant_isolation ON tenants_tenantinvite
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX tenants_tenantinvite_token ON tenants_tenantinvite (token);
