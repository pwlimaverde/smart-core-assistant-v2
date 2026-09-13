-- B9 (N10 E1) — kill-switch da análise prévia (intenções e entidades) por tenant.
--
-- A análise é uma chamada de LLM a mais por mensagem do contato. Mesma cascata do
-- `transcription_enabled` (migration 0024), com default global LIGADO: a v1
-- sempre analisava, e é dela que sai o assunto automático do atendimento (E2).
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS analise_previa_habilitada BOOLEAN;

COMMENT ON COLUMN tenants_tenantconfig.analise_previa_habilitada IS
    'Liga a análise prévia (intenções/entidades) das mensagens do contato; NULL = herda o CoreSetting ANALISE_PREVIA_HABILITADA.';

INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('ANALISE_PREVIA_HABILITADA', 'true',
     'Padrão global do kill-switch da análise prévia de mensagens; sobreposto por tenants_tenantconfig.analise_previa_habilitada.')
ON CONFLICT (key) DO NOTHING;
