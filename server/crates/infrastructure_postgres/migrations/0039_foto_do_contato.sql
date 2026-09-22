-- P13 — quando a foto do contato foi conferida com o WhatsApp pela última vez.
--
-- É o freio da busca sob demanda: sem ele, abrir uma conversa consultaria o
-- provedor toda vez. Com ele, no máximo uma consulta por contato a cada 7 dias,
-- inclusive quando a resposta foi "sem foto" (que é a resposta de quem não
-- quer foto pública — perguntar de novo amanhã não muda nada).
ALTER TABLE oraculo_contato
    ADD COLUMN IF NOT EXISTS foto_verificada_em TIMESTAMPTZ;

COMMENT ON COLUMN oraculo_contato.foto_verificada_em IS
    'P13 — última consulta da foto de perfil ao provedor; NULL = nunca consultada';
