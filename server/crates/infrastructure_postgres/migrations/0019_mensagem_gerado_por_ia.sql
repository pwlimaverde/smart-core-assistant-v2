-- N6.2 — selo "gerado por IA" no chat.
-- Aditiva: marca mensagens cujo conteúdo foi gerado pela IA (resposta do bot).
-- Default FALSE; a população (marcar as respostas do bot com TRUE) fica para o
-- passo que persistir as mensagens do bot no thread — fora do escopo desta fase.
ALTER TABLE oraculo_mensagem
    ADD COLUMN IF NOT EXISTS gerado_por_ia BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN oraculo_mensagem.gerado_por_ia IS
    'TRUE quando o conteúdo da mensagem foi gerado pela IA (resposta automática do bot).';
