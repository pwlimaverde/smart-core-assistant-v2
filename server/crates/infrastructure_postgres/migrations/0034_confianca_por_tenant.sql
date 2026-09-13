-- B4 (regras do bot, D1 passo 2) — confiança da IA com veto, por tenant.
--
-- O passo 1 já grava a confiança de cada resposta (`oraculo_mensagem.
-- confianca_resposta`). Este passo dá ao tenant os dois números que decidem o
-- que fazer com ela, na mesma cascata Tenant > CoreSettings dos outros limiares:
--
-- * `confianca_minima_transferencia`: abaixo disto a resposta vira
--   transferência, mesmo com o modelo dizendo que sabe responder. NULL/0 =
--   veto desligado, e é o PADRÃO — ligar o veto sem histórico é calibrar no
--   escuro, e o histórico só começa a existir agora;
-- * `confianca_minima_automatica`: a partir disto a IA responde sem revisão, e
--   é também o piso para um valor extraído entrar na ficha do cliente (C1) —
--   um número só para "quando confio na IA", e não dois discordando.
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS confianca_minima_transferencia NUMERIC(3,2);

ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS confianca_minima_automatica NUMERIC(3,2);

COMMENT ON COLUMN tenants_tenantconfig.confianca_minima_transferencia IS
    'Abaixo disto a resposta da IA vira transferência (veto). NULL herda o CoreSetting CONFIANCA_MINIMA_TRANSFERENCIA; 0 desliga.';

COMMENT ON COLUMN tenants_tenantconfig.confianca_minima_automatica IS
    'A partir disto a IA responde sem revisão; também é o piso de extração de campos. NULL herda CONFIANCA_MINIMA_AUTOMATICA.';

INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('CONFIANCA_MINIMA_TRANSFERENCIA', '',
     'Padrão global do veto de confiança da IA. Vazio ou 0 = desligado; sobreposto por tenants_tenantconfig.confianca_minima_transferencia.'),
    ('CONFIANCA_MINIMA_AUTOMATICA', '0.8',
     'Padrão global da confiança a partir da qual a IA responde sem revisão e grava campos extraídos; sobreposto por tenants_tenantconfig.confianca_minima_automatica.')
ON CONFLICT (key) DO NOTHING;
