-- P7 — a conexão passa a saber para qual departamento ela roteia.
--
-- Era assim na v1 (`AppInstance.departamento`): a conversa que chegava num
-- número entrava no fluxo daquele departamento. A v2 perdeu o vínculo e
-- mandava TODA conversa para o primeiro fluxo ativo do tenant — quem tem um
-- número de vendas e outro de suporte via os dois caírem na mesma fila.
--
-- NULL continua sendo válido e é o comportamento de hoje: sem departamento, o
-- roteamento cai no primeiro fluxo ativo. Por isso a coluna nasce anulável e
-- sem default: migrar não pode mudar o destino de conexão nenhuma.
ALTER TABLE whatsapp_instance
    ADD COLUMN IF NOT EXISTS departamento_id INT
        REFERENCES oraculo_departamento(id) ON DELETE SET NULL;

COMMENT ON COLUMN whatsapp_instance.departamento_id IS
    'P7 — departamento para onde as conversas desta conexão são roteadas; NULL = primeiro fluxo ativo do tenant';

-- A ingestão lê esta coluna a cada conversa nova, sempre por (tenant, id).
CREATE INDEX IF NOT EXISTS whatsapp_instance_tenant_dept
    ON whatsapp_instance (tenant_id, departamento_id)
    WHERE departamento_id IS NOT NULL;

-- A lista de números ignorados mostra também os desligados, ordenada por nome:
-- sem este índice a tela varre a tabela inteira do tenant a cada abertura.
CREATE INDEX IF NOT EXISTS whatsapp_whitelist_tenant_nome
    ON whatsapp_whitelist (tenant_id, name);
