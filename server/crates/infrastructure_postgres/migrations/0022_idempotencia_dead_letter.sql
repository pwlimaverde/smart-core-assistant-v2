-- N7.2 — idempotência do sync offline (action_id) + dead-letter de outbound.

-- Dedupe server-side de ações reenviadas pelo sync offline (MoveAtendimentoEtapa,
-- SendOutboundMessage). `action_id` é uuid v7 gerado client-side (aditivo/opcional
-- no proto); clientes antigos não enviam e seguem sem dedupe. `resultado` guarda o
-- JSON de resposta idempotente devolvido em reenvios (ex.: message_id definitivo).
CREATE TABLE applied_actions (
    action_id  UUID PRIMARY KEY,
    tenant_id  UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    resultado  JSONB NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE applied_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE applied_actions FORCE  ROW LEVEL SECURITY;
CREATE POLICY applied_actions_tenant_isolation ON applied_actions
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- Dead-letter de mensagens outbound sem destino resolvível (sem whatsapp_contact
-- ativo no momento do envio): auditável e reprocessável manualmente, em vez de
-- descartada/perdida em erro silencioso.
CREATE TABLE mensagem_dead_letter (
    id            SERIAL PRIMARY KEY,
    tenant_id     UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    mensagem_id   INT NOT NULL,
    atendimento_id INT NOT NULL,
    motivo        TEXT NOT NULL,
    criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reprocessado  BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE mensagem_dead_letter ENABLE ROW LEVEL SECURITY;
ALTER TABLE mensagem_dead_letter FORCE  ROW LEVEL SECURITY;
CREATE POLICY mensagem_dead_letter_tenant_isolation ON mensagem_dead_letter
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX mensagem_dead_letter_tenant_pendentes
    ON mensagem_dead_letter (tenant_id, reprocessado)
    WHERE reprocessado = false;
