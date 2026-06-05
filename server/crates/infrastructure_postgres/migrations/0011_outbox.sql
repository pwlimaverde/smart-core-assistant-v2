-- ============================================================
-- Módulo Outbox: eventos pendentes de publicação no barramento
-- Tabela protegida por RLS.
-- ============================================================

CREATE TABLE outbox (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    event_type    TEXT NOT NULL,
    payload       BYTEA NOT NULL,          -- envelope FlatBuffers ou JSON serializado
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at  TIMESTAMPTZ              -- NULL = ainda não publicado no bus
);

COMMENT ON TABLE outbox IS
    'Eventos de domínio gerados em transações ACID, prontos para retransmissão confiável via relay.';

-- ============================================================
-- Índices
-- ============================================================

-- Índice para busca rápida de eventos não publicados por tenant
CREATE INDEX idx_outbox_unpub_tenant
    ON outbox (tenant_id, occurred_at ASC)
    WHERE published_at IS NULL;

-- Índice global para o relay buscar eventos pendentes
CREATE INDEX idx_outbox_unpub_global
    ON outbox (occurred_at ASC)
    WHERE published_at IS NULL;

-- ============================================================
-- RLS (Row Level Security)
-- ============================================================

ALTER TABLE outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE outbox FORCE ROW LEVEL SECURITY;

-- Inquilinos só acessam os próprios eventos de outbox
CREATE POLICY outbox_tenant_isolation ON outbox
    FOR ALL
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    );

-- ============================================================
-- Triggers e Notificações (PgListener)
-- ============================================================

CREATE OR REPLACE FUNCTION outbox_notify() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('outbox_new', NEW.id::text); -- Notifica o relay em background
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER outbox_after_insert
    AFTER INSERT ON outbox
    FOR EACH ROW EXECUTE FUNCTION outbox_notify();
