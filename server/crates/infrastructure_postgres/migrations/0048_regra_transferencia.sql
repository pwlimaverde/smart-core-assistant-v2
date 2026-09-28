-- Plano ia-engine-jev (J3) — cadastro das regras de transferência do tenant.
--
-- A transferência é decisão do tenant, e até aqui ela vivia espalhada em
-- prosa: no prompt de regras, na persona e no comportamento das intenções.
-- Este cadastro vira a ÚNICA fonte de quando o bot transfere no motor Jev.
-- As regras ativas vão ao Redis com a config do tenant (o ia_engine_jev as
-- lê de lá); cada condição vira um `Noul`, lido ao pé da letra.
CREATE TABLE IF NOT EXISTS oraculo_regra_transferencia (
    id                BIGSERIAL PRIMARY KEY,
    tenant_id         UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    nome              VARCHAR(120) NOT NULL,
    -- condicao: um `Noul` sobre a frase; intencao: a intenção escolhida pelo Jev.
    gatilho_tipo      VARCHAR(10) NOT NULL DEFAULT 'condicao'
        CHECK (gatilho_tipo IN ('condicao', 'intencao')),
    condicao          TEXT NOT NULL DEFAULT '',
    intencao_tag      VARCHAR(120) NOT NULL DEFAULT '',
    exemplos_sim      JSONB NOT NULL DEFAULT '[]'::jsonb,
    exemplos_nao      JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- imediato, ou só depois de preenchidos os campos do cartão listados.
    momento           VARCHAR(12) NOT NULL DEFAULT 'imediato'
        CHECK (momento IN ('imediato', 'apos_coleta')),
    campos_coleta     JSONB NOT NULL DEFAULT '[]'::jsonb,
    destino_tipo      VARCHAR(10) NOT NULL DEFAULT 'padrao'
        CHECK (destino_tipo IN ('fluxo', 'setor_jev', 'padrao')),
    destino_fluxo_id  INT REFERENCES oraculo_fluxo_atendimento(id) ON DELETE SET NULL,
    mensagem          TEXT NOT NULL DEFAULT '',
    sensibilidade     VARCHAR(5) NOT NULL DEFAULT 'media'
        CHECK (sensibilidade IN ('baixa', 'media', 'alta')),
    ativa             BOOLEAN NOT NULL DEFAULT FALSE,
    -- Criada pela migração do texto antigo; o tenant revisa e ativa.
    sugestao          BOOLEAN NOT NULL DEFAULT FALSE,
    criado_em         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_regra_transferencia_nome
    ON oraculo_regra_transferencia (tenant_id, lower(nome));

ALTER TABLE oraculo_regra_transferencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_regra_transferencia FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_regra_transferencia_tenant_isolation ON oraculo_regra_transferencia
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
