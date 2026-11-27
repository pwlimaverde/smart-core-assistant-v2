-- Contrato genérico de canal (ADR intermediário de webhooks/provedores, 2026-11).
--
-- ADITIVA E SEM MOVER DADO NENHUM. A conexão continua morando em
-- `whatsapp_instance`: as FKs de `whatsapp_contact`, departamentos e atendimentos
-- apontam para ela, e mover linhas para uma tabela nova obrigaria a reescrever
-- todas — com risco direto às conexões em uso (a 181 da dev). O nome genérico
-- vem pela view `channels`.
--
-- - `channel_kind`: tipo do canal (whatsapp, webchat, telegram…). Toda linha
--   existente é WhatsApp, e o DEFAULT a preenche sem UPDATE.
-- - `provider_config`: configuração NÃO secreta do provedor (ex.: `waba_id` da
--   Cloud API). Segredo continua em `api_key`, cifrado (0023).
-- - `instance_id` já é o id externo (nome da instância na Evolution,
--   `phone_number_id` na Cloud API) e já é UNIQUE: é a chave de roteamento do
--   webhook que não traz o tenant no caminho.
ALTER TABLE whatsapp_instance
    ADD COLUMN IF NOT EXISTS channel_kind VARCHAR(30) NOT NULL DEFAULT 'whatsapp';

ALTER TABLE whatsapp_instance
    ADD COLUMN IF NOT EXISTS provider_config JSONB NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN whatsapp_instance.channel_kind IS
    'Tipo do canal (whatsapp, webchat, telegram, instagram, messenger)';
COMMENT ON COLUMN whatsapp_instance.provider_config IS
    'Configuração não secreta do provedor; segredos ficam em api_key (cifrado)';

-- Id externo único só entre conexões VIVAS, como o nome desde a 0045. A
-- exclusão é lógica (`excluido_em`) e deixava o `instance_id` ocupado para
-- sempre: um número da Cloud API removido (ex.: para trocar um token vencido)
-- nunca mais podia ser conectado, por nenhum tenant. Linhas vivas continuam
-- sem repetição; o índice parcial é criado antes de largar a constraint, então
-- não há instante sem garantia.
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_instance_instance_id_viva
    ON whatsapp_instance (instance_id) WHERE excluido_em IS NULL;
ALTER TABLE whatsapp_instance DROP CONSTRAINT IF EXISTS whatsapp_instance_instance_id_key;

-- Roteamento por id externo dentro do provedor (webhook da Meta).
CREATE INDEX IF NOT EXISTS whatsapp_instance_provider_instance_id
    ON whatsapp_instance (provider, instance_id);

-- Nome genérico. `security_invoker` faz a RLS de `whatsapp_instance` valer para
-- quem consulta a view (sem ele, a view rodaria com o dono e vazaria tenants).
-- Sem `api_key`: segredo não sai por aqui.
CREATE OR REPLACE VIEW channels WITH (security_invoker = true) AS
SELECT
    id,
    tenant_id,
    channel_kind      AS kind,
    provider,
    instance_id       AS external_id,
    name,
    phone_number,
    connection_state  AS status,
    active,
    provider_config,
    created_at
FROM whatsapp_instance;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartcore_app_rt') THEN
        EXECUTE 'GRANT SELECT ON channels TO smartcore_app_rt';
    END IF;
END
$$;
