-- Cadastro completo: cargo, segmento e observações para contato e cargo do
-- responsável para cliente. Colunas nullable, sem default, para não reescrever
-- cadastros existentes. `segmento` do cliente reaproveita `ramo_atividade`
-- (já existe), por isso não entra aqui.

ALTER TABLE oraculo_contato
    ADD COLUMN IF NOT EXISTS cargo        VARCHAR(100),
    ADD COLUMN IF NOT EXISTS segmento     VARCHAR(100),
    ADD COLUMN IF NOT EXISTS observacoes  TEXT;

ALTER TABLE oraculo_cliente
    ADD COLUMN IF NOT EXISTS cargo_responsavel VARCHAR(100);
