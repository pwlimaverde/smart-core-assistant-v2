-- Plano ia-engine-jev (metodologia "o Jev lê, o código decide o ato, a LLM só
-- redige, o Jev confere" — doc_dev/planejamento/40-metodologia-motor-jev.md).

-- 1. Coleta estruturada por intenção: os dados essenciais que o bot pede
--    (tipo de entidade ou slug de campo do cartão), quantos por mensagem, e o
--    que fazer quando a rodada acaba. Antes era texto no comportamento e na
--    persona ("no máximo 2 perguntas, uma única vez"), que a LLM tinha de
--    contar lendo o histórico.
ALTER TABLE treinamento_querycompose
    ADD COLUMN IF NOT EXISTS campos_coleta TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS max_perguntas SMALLINT NOT NULL DEFAULT 2,
    ADD COLUMN IF NOT EXISTS apos_coleta VARCHAR(12) NOT NULL DEFAULT 'transferir';

ALTER TABLE treinamento_querycompose
    ADD CONSTRAINT querycompose_max_perguntas_valido
    CHECK (max_perguntas BETWEEN 1 AND 5);
ALTER TABLE treinamento_querycompose
    ADD CONSTRAINT querycompose_apos_coleta_valido
    CHECK (apos_coleta IN ('transferir', 'continuar'));

-- 2. Rodadas de coleta feitas pelo bot no atendimento: a regra "uma rodada
--    só" é contada aqui, pelo worker, e não inferida pela LLM.
ALTER TABLE oraculo_atendimento
    ADD COLUMN IF NOT EXISTS ia_coleta_rodadas SMALLINT NOT NULL DEFAULT 0;

-- 3. Registro das decisões: o ato decidido, a cascata e onde o tempo foi.
--    Continua SEM texto de conversa: ato, nomes de problema, slugs de campo e
--    milissegundos por etapa.
ALTER TABLE oraculo_decisao_ia
    ADD COLUMN IF NOT EXISTS ato VARCHAR(12) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS escalada BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS problemas JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS modelo_llm VARCHAR(60) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS etapas JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS campos_perguntados JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_decisao_ia_ato
    ON oraculo_decisao_ia (tenant_id, ato, criado_em DESC) WHERE vale;
