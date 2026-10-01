-- ============================================================
-- Conexão de WhatsApp por onde falar com um contato
-- ============================================================
-- O envio do atendente, a presença e o espelho da leitura dependiam só de
-- `whatsapp_contact`, que o caminho de entrada nunca preenchia: toda mensagem
-- do painel caía em dead-letter (`sem_whatsapp_contact_ativo`).
--
-- Ordem de escolha:
--   1. o vínculo do contato com uma conexão que continua ativa (a conexão por
--      onde ele escreveu por último);
--   2. sem vínculo (contato antigo, conversa iniciada pelo painel), a conexão
--      conectada do tenant verificada mais recentemente.
-- Conexão excluída ou desativada nunca é escolhida, mesmo com vínculo.
CREATE OR REPLACE FUNCTION conexao_do_contato(p_tenant uuid, p_contato int)
RETURNS int
LANGUAGE sql
STABLE
AS $$
    SELECT x.id
      FROM (
            SELECT wc.instance_id AS id, 0 AS ordem, wc.updated_at AS quando
              FROM whatsapp_contact wc
              JOIN whatsapp_instance wi
                ON wi.id = wc.instance_id AND wi.tenant_id = wc.tenant_id
             WHERE wc.tenant_id = p_tenant
               AND wc.contact_id = p_contato
               AND wc.active
               AND wi.active
               AND wi.excluido_em IS NULL
            UNION ALL
            SELECT wi.id, 1, COALESCE(wi.last_state_check, wi.created_at)
              FROM whatsapp_instance wi
             WHERE wi.tenant_id = p_tenant
               AND wi.active
               AND wi.excluido_em IS NULL
               AND wi.connection_state = 'connected'
           ) x
     ORDER BY x.ordem, x.quando DESC NULLS LAST
     LIMIT 1
$$;

-- Liga os contatos que já escreveram à conexão atual, para as conversas abertas
-- antes desta correção voltarem a enviar sem esperar a próxima mensagem.
INSERT INTO whatsapp_contact (tenant_id, instance_id, jid, contact_id)
SELECT oc.tenant_id, wi.id, oc.telefone, oc.id
  FROM oraculo_contato oc
  JOIN LATERAL (
        SELECT i.id
          FROM whatsapp_instance i
         WHERE i.tenant_id = oc.tenant_id
           AND i.active
           AND i.excluido_em IS NULL
           AND i.connection_state = 'connected'
         ORDER BY COALESCE(i.last_state_check, i.created_at) DESC NULLS LAST
         LIMIT 1
       ) wi ON true
 WHERE oc.telefone IS NOT NULL
   AND NOT EXISTS (
        SELECT 1 FROM whatsapp_contact wc
         WHERE wc.tenant_id = oc.tenant_id AND wc.contact_id = oc.id
       )
ON CONFLICT (tenant_id, instance_id, jid) DO NOTHING;
