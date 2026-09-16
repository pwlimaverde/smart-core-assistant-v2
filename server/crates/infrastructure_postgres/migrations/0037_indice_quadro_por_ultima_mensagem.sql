-- P1 — o quadro passa a ordenar pela última mensagem (paridade com a v1).
--
-- Sem este índice, cada abertura do quadro faz um sort completo dos
-- atendimentos ativos do tenant; com ele, o Postgres lê direto na ordem da
-- tela e corta no LIMIT.
CREATE INDEX IF NOT EXISTS oraculo_atendimento_tenant_ultima_msg
    ON oraculo_atendimento (tenant_id, data_ultima_mensagem DESC NULLS LAST, data_inicio DESC)
    WHERE status <> 'arquivado';

-- O filtro "não lidas" do quadro pergunta, por conversa, se sobrou mensagem do
-- contato sem ler. O índice parcial deixa esse EXISTS custar quase nada.
CREATE INDEX IF NOT EXISTS oraculo_mensagem_nao_lidas_do_contato
    ON oraculo_mensagem (tenant_id, atendimento_id)
    WHERE lido = false AND remetente = 'contato';
