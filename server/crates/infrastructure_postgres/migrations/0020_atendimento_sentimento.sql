-- N6.5 — sentimento ligado ao fluxo.
-- Aditiva: guarda a última leitura de sentimento do atendimento (best-effort,
-- atualizada a cada mensagem inbound de texto/transcrição de áudio).
ALTER TABLE oraculo_atendimento
    ADD COLUMN IF NOT EXISTS sentimento_nota INT,
    ADD COLUMN IF NOT EXISTS sentimento_label VARCHAR(20);

COMMENT ON COLUMN oraculo_atendimento.sentimento_nota IS
    'Nota de sentimento (escala definida pelo ia_engine) da última análise; NULL enquanto não avaliado.';
COMMENT ON COLUMN oraculo_atendimento.sentimento_label IS
    'Rótulo textual do sentimento (ex.: positivo/neutro/negativo) da última análise.';
