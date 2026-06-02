-- ============================================================
-- Módulo Planos e Assinaturas: faturamento e limites do SaaS
-- ============================================================

-- Plan: tabela global (sem RLS) — limites operacionais por plano comercial
CREATE TABLE tenants_plan (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    price           NUMERIC(10,2),
    max_instances   INT NOT NULL DEFAULT 1,
    max_departments INT NOT NULL DEFAULT 1,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Sem RLS: plans são globais do SaaS, visíveis para toda a aplicação.

-- Subscription: assinatura do tenant com rastreamento de faturamento
CREATE TABLE tenants_subscription (
    id                       SERIAL PRIMARY KEY,
    tenant_id                UUID NOT NULL UNIQUE REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    plan_id                  INT REFERENCES tenants_plan(id) ON DELETE RESTRICT,
    status                   VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    current_period_start     TIMESTAMPTZ,
    current_period_end       TIMESTAMPTZ,
    payment_gateway          VARCHAR(50) NOT NULL DEFAULT '',
    external_customer_id     VARCHAR(100) NOT NULL DEFAULT '',
    external_subscription_id VARCHAR(100) NOT NULL DEFAULT '',
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tenants_subscription ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_subscription FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_subscription_tenant_isolation ON tenants_subscription
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- PaymentRecord: histórico de lançamentos financeiros manuais
CREATE TABLE tenants_paymentrecord (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    amount          NUMERIC(10,2) NOT NULL,
    payment_date    DATE NOT NULL,
    payment_method  VARCHAR(20) NOT NULL,
    period_start    DATE NOT NULL,
    period_end      DATE NOT NULL,
    notes           TEXT NOT NULL DEFAULT '',
    recorded_by_id  INT REFERENCES auth_user(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE tenants_paymentrecord ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants_paymentrecord FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenants_paymentrecord_tenant_isolation ON tenants_paymentrecord
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX tenants_paymentrecord_tenant_date ON tenants_paymentrecord (tenant_id, payment_date DESC);
