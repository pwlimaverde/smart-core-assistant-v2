-- Plano ia-engine-jev (J2/J3) — motor por tenant, sinais de transferência e o
-- registro das decisões da IA.

-- 1. Config do tenant. NULL herda o global (CoreSettings).
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS motor_analise VARCHAR(10),
    ADD COLUMN IF NOT EXISTS jev_modelo VARCHAR(40),
    -- Pisos calibrados na avaliação (J0) e estratégia por tipo de entidade.
    ADD COLUMN IF NOT EXISTS jev_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Sinais automáticos da transferência: liga/desliga e sensibilidade.
    ADD COLUMN IF NOT EXISTS transferencia_sinais JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS transferencia_fluxo_padrao_id INT
        REFERENCES oraculo_fluxo_atendimento(id) ON DELETE SET NULL;

ALTER TABLE tenants_tenantconfig
    ADD CONSTRAINT tenantconfig_motor_analise_valido
    CHECK (motor_analise IS NULL OR motor_analise IN ('llm', 'sombra', 'jev'));

-- 2. A confiança gravada muda de escala com o motor: cosseno (llm) ou
--    probabilidade (jev). Sem o motor ao lado, o histórico mistura as duas.
ALTER TABLE oraculo_mensagem
    ADD COLUMN IF NOT EXISTS motor VARCHAR(10),
    ADD COLUMN IF NOT EXISTS modelo VARCHAR(40);

-- 3. Registro das decisões da IA, uma linha por motor (na sombra, duas).
--    Fonte das métricas da avaliação, da calibração por tenant e das "últimas
--    transferências". SEM texto de mensagem nem de trecho: só números, nomes de
--    sinal e ids. Retenção de 90 dias (limpeza pelo worker).
CREATE TABLE IF NOT EXISTS oraculo_decisao_ia (
    id                  BIGSERIAL PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id      INT REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    etapa               VARCHAR(20) NOT NULL,          -- analise | resposta
    motor               VARCHAR(10) NOT NULL,          -- llm | jev
    vale                BOOLEAN NOT NULL DEFAULT TRUE, -- false = sombra
    modelo              VARCHAR(40) NOT NULL DEFAULT '',
    intencao            VARCHAR(120) NOT NULL DEFAULT '',
    confianca_intencao  DOUBLE PRECISION,
    decisao             VARCHAR(20) NOT NULL DEFAULT '',
    transferiu          BOOLEAN NOT NULL DEFAULT FALSE,
    motivo              VARCHAR(200) NOT NULL DEFAULT '',
    regra_id            BIGINT,
    fluxo_id            INT,
    sinais              JSONB NOT NULL DEFAULT '[]'::jsonb,
    trechos_aprovados   JSONB NOT NULL DEFAULT '[]'::jsonb,
    trechos_descartados JSONB NOT NULL DEFAULT '[]'::jsonb,
    confiabilidade      DOUBLE PRECISION,
    tokens_entrada      BIGINT NOT NULL DEFAULT 0,
    requisicoes         INT NOT NULL DEFAULT 0,
    duracao_ms          BIGINT NOT NULL DEFAULT 0,
    criado_em           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_decisao_ia_tenant_data
    ON oraculo_decisao_ia (tenant_id, criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_decisao_ia_transferencias
    ON oraculo_decisao_ia (tenant_id, criado_em DESC) WHERE transferiu AND vale;

ALTER TABLE oraculo_decisao_ia ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_decisao_ia FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_decisao_ia_tenant_isolation ON oraculo_decisao_ia
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
