-- P16 — a IA respondeu abaixo da confiança automática do tenant (B4): a
-- resposta saiu, mas alguém precisa conferir. Até aqui a decisão `revisao` só
-- existia no evento `bot.respondeu`, que ninguém do atendimento vê.
--
-- Liga quando o worker decide `revisao`; desliga quando um atendente responde
-- na conversa ou marca como revisado.
ALTER TABLE oraculo_atendimento
    ADD COLUMN IF NOT EXISTS revisao_pendente BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS oraculo_atendimento_revisao_pendente
    ON oraculo_atendimento (tenant_id)
    WHERE revisao_pendente;
