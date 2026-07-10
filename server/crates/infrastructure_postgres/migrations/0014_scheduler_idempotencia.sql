-- ============================================================
-- Scheduler temporal do worker (F4.3b): marcações de idempotência
-- para timeout de feedback e disparo de purga de mídia.
-- ============================================================

ALTER TABLE oraculo_atendimento
    ADD COLUMN feedback_expirado_em TIMESTAMPTZ;

ALTER TABLE oraculo_mensagem
    ADD COLUMN midia_purgada_em TIMESTAMPTZ;

-- Varredura de feedback vencido: atendimentos resolvidos, sem feedback e ainda
-- não marcados como expirados. Índice parcial cobre o filtro do scheduler.
CREATE INDEX oraculo_atendimento_feedback_pendente
    ON oraculo_atendimento (data_fim)
    WHERE status = 'resolvido' AND feedback IS NULL AND feedback_expirado_em IS NULL;

-- Varredura de mídia expirada: mensagens com arquivo de mídia ainda não purgado.
CREATE INDEX oraculo_mensagem_midia_pendente
    ON oraculo_mensagem (timestamp)
    WHERE arquivo_midia IS NOT NULL AND midia_purgada_em IS NULL;
