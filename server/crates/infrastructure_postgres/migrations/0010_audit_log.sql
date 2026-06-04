-- ============================================================
-- Módulo Auditoria: logs de eventos de negócio e segurança
-- Tabela com RLS ativa.
-- tenant_id NULLABLE — ações de superusuário/sistema não têm tenant.
-- ============================================================

CREATE TABLE audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID REFERENCES tenants_tenant(id) ON DELETE CASCADE, -- NULL = ação de superusuário ou sistema
    timestamp   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level       VARCHAR(10) NOT NULL DEFAULT 'INFO',
    service     VARCHAR(100) NOT NULL,
    trace_id    VARCHAR(64),
    event       VARCHAR(255) NOT NULL,
    message     TEXT NOT NULL,
    context     JSONB NOT NULL DEFAULT '{}',
    user_id     INTEGER REFERENCES auth_user(id) ON DELETE SET NULL,  -- NULL = ação automática ou externa
    ip_address  VARCHAR(45),       -- suporta IPv4 e IPv6
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_log IS
    'Logs de auditoria de eventos de negócio e segurança. '
    'tenant_id NULL indica ação de superusuário/sistema. '
    'Protegida por RLS com policy restrita para inquilinos.';

-- ============================================================
-- Índices
-- ============================================================

-- Consultas por tenant (a maioria)
CREATE INDEX idx_audit_log_tenant_timestamp
    ON audit_log (tenant_id, timestamp DESC)
    WHERE tenant_id IS NOT NULL;

CREATE INDEX idx_audit_log_tenant_event
    ON audit_log (tenant_id, event)
    WHERE tenant_id IS NOT NULL;

CREATE INDEX idx_audit_log_tenant_user
    ON audit_log (tenant_id, user_id)
    WHERE tenant_id IS NOT NULL AND user_id IS NOT NULL;

-- Consultas de ações globais (superusuário) — sem tenant
CREATE INDEX idx_audit_log_global_timestamp
    ON audit_log (timestamp DESC)
    WHERE tenant_id IS NULL;

-- Consultas por nível de alerta
CREATE INDEX idx_audit_log_level
    ON audit_log (level, timestamp DESC)
    WHERE level IN ('WARN', 'ERROR');

-- Busca no JSONB context
CREATE INDEX idx_audit_log_context
    ON audit_log USING GIN (context jsonb_path_ops);

-- Busca por evento (cross-tenant, para dashboards admin)
CREATE INDEX idx_audit_log_event_timestamp
    ON audit_log (event, timestamp DESC);

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;

-- Policy para operações do inquilino (tenant): vê apenas registros do seu tenant
CREATE POLICY audit_log_tenant_isolation ON audit_log
    FOR ALL
    USING (
        tenant_id IS NOT NULL
        AND tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    );
