-- D5 — encerrar conversa abandonada.
--
-- Construção nova: a v1 não tinha isto (a própria lista de paridade a marca
-- como ausente). Hoje uma conversa em que o cliente sumiu fica na fila para
-- sempre — ocupa coluna no quadro, conta como carga do atendente no rodízio
-- (D2) e faz a fila parecer maior do que é.
--
-- `NULL` = usa o padrão global (`MINUTOS_INATIVIDADE_ENCERRA` no CoreSettings,
-- e 30 na ausência dele). Valor `<= 0` DESLIGA o encerramento para o tenant —
-- é a saída para quem atende por WhatsApp com janelas longas e não quer que um
-- cliente que responde no dia seguinte encontre a conversa arquivada.
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS minutos_inatividade_encerra INT;

COMMENT ON COLUMN tenants_tenantconfig.minutos_inatividade_encerra IS
    'Minutos sem mensagem antes de arquivar a conversa. NULL = padrão global; <= 0 desliga.';

-- A varredura do scheduler é cross-tenant e filtra por status de espera +
-- instante da última atividade. Índice parcial cobre exatamente esse recorte:
-- só as conversas que ainda podem ser encerradas entram no índice.
--
-- Índice sobre a EXPRESSÃO, não sobre a coluna crua: a consulta usa
-- `COALESCE(data_ultima_mensagem, data_inicio)` — porque uma conversa criada e
-- nunca respondida tem `data_ultima_mensagem` nula e é justamente a que ficava
-- para sempre. Um índice em `data_ultima_mensagem` não seria usado por essa
-- consulta, e custaria escrita sem comprar leitura.
CREATE INDEX IF NOT EXISTS idx_atendimento_inatividade
    ON oraculo_atendimento (COALESCE(data_ultima_mensagem, data_inicio))
    WHERE status IN ('fila', 'pendencia');
