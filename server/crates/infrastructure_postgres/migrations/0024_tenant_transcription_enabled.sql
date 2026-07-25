-- N6.4 (passo 4) — kill-switch de transcrição POR TENANT.
-- Antes só existia a env var global `TRANSCRIPTION_ENABLED` do ia_engine, que
-- liga/desliga a feature para a instalação inteira; o plano pedia a flag por
-- tenant, para habilitar transcrição em quem aceita o custo/latência sem forçar
-- os demais. Segue a cascata padrão Tenant > CoreSettings do projeto: NULL na
-- coluna do tenant cai no CoreSetting global.
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS transcription_enabled BOOLEAN;

COMMENT ON COLUMN tenants_tenantconfig.transcription_enabled IS
    'Liga a transcrição de áudio para este tenant; NULL = herda o CoreSetting global TRANSCRIPTION_ENABLED.';

-- Default global conservador (custo/latência por áudio recebido): desligado.
INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('TRANSCRIPTION_ENABLED', 'false',
     'Padrão global do kill-switch de transcrição de áudio; sobreposto por tenants_tenantconfig.transcription_enabled.')
ON CONFLICT (key) DO NOTHING;
