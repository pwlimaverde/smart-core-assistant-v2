-- Índice de busca por stanzaId do WhatsApp em `oraculo_mensagem`.
--
-- Duas consultas do fluxo vivo filtram por (tenant_id, message_id_whatsapp) e não
-- tinham índice — faziam varredura da partição do tenant a cada evento:
--   * `atualizar_status_por_whatsapp_id` (webhook `messages.update`: sent/delivered/read);
--   * `buscar_por_whatsapp_id`, a chave natural de idempotência da ingestão inbound.
--
-- Parcial (`WHERE ... IS NOT NULL`): a coluna é nula na maioria das linhas antigas
-- e em mensagens que nunca trafegaram pelo provedor, então o índice fica pequeno.
--
-- NÃO é UNIQUE de propósito: a base migrada da v1 pode conter stanzaIds repetidos
-- (reenvios/importações do histórico), e uma unicidade retroativa faria a migration
-- falhar no cutover — travando o boot do data_postgres. A idempotência é garantida
-- na aplicação (busca antes de inserir, dentro da mesma transação do tenant).
CREATE INDEX IF NOT EXISTS oraculo_mensagem_tenant_wa_id
    ON oraculo_mensagem (tenant_id, message_id_whatsapp)
    WHERE message_id_whatsapp IS NOT NULL;
