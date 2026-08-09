-- N9/E1-E2 — metadados da mídia na mensagem.
--
-- `arquivo_midia` (a chave do objeto) existe desde a 0006, mas sozinha ela não
-- basta para montar a bolha: a tela precisa saber o tipo para escolher entre
-- player de áudio, visualizador de imagem e cartão de documento, o nome para
-- exibir no anexo, e o tamanho para mostrar antes de baixar.
--
-- Até aqui isso não fazia falta porque a única mídia que existia era a RECEBIDA,
-- e dela o que se guardava era o resumo textual da IA. Com o envio pelo painel,
-- a mensagem passa a ser a fonte da verdade sobre o anexo.

ALTER TABLE oraculo_mensagem
    ADD COLUMN IF NOT EXISTS mimetype_midia     VARCHAR(120),
    ADD COLUMN IF NOT EXISTS nome_arquivo_midia VARCHAR(255),
    ADD COLUMN IF NOT EXISTS tamanho_midia      BIGINT;

COMMENT ON COLUMN oraculo_mensagem.mimetype_midia IS
    'Mimetype CONFERIDO do anexo (magic bytes), não o declarado pelo cliente.';
COMMENT ON COLUMN oraculo_mensagem.nome_arquivo_midia IS
    'Nome original do arquivo enviado. Pode conter PII — não vai para log nem auditoria.';
COMMENT ON COLUMN oraculo_mensagem.tamanho_midia IS
    'Tamanho em bytes medido no bucket após o upload; alimenta a contabilidade de quota.';

-- A galeria da ficha (N9/E2) varre as mídias de UM atendimento, da mais recente
-- para a mais antiga, ignorando as já purgadas pela retenção.
CREATE INDEX IF NOT EXISTS idx_mensagem_midia_do_atendimento
    ON oraculo_mensagem (tenant_id, atendimento_id, timestamp DESC)
    WHERE arquivo_midia IS NOT NULL AND midia_purgada_em IS NULL;
