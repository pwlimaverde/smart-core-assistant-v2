-- P17 — a avaliação do teste de resposta já foi tratada (virou material de
-- treinamento, ou foi dispensada). Sem isto a lista de revisão só cresceria: a
-- mesma correção apareceria para sempre, mesmo depois de aproveitada.
ALTER TABLE treinamento_query_test_feedback
    ADD COLUMN IF NOT EXISTS tratada_em TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS treinamento_feedback_pendentes
    ON treinamento_query_test_feedback (tenant_id, created_at DESC)
    WHERE tratada_em IS NULL;
