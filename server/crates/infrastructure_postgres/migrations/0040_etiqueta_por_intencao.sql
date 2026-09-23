-- P14 — etiquetagem por intenção (N10 E3).
--
-- `origem` distingue a etiqueta colocada pela IA da colocada por uma pessoa.
-- As linhas que já existem foram todas postas à mão, e o default diz isso.
ALTER TABLE atu_etiqueta_atendimento
    ADD COLUMN IF NOT EXISTS origem VARCHAR(10) NOT NULL DEFAULT 'manual';

-- "Removida por humano não volta." Uma linha apagada não guarda nada, então a
-- remoção feita por uma pessoa fica registrada aqui, e a IA consulta antes de
-- aplicar. Religar à mão apaga o bloqueio.
CREATE TABLE IF NOT EXISTS atu_etiqueta_bloqueada (
    id             BIGSERIAL PRIMARY KEY,
    tenant_id      UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    etiqueta_id    BIGINT NOT NULL REFERENCES atu_etiqueta(id) ON DELETE CASCADE,
    bloqueada_em   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    por_usuario_id INT,
    UNIQUE (tenant_id, atendimento_id, etiqueta_id)
);
ALTER TABLE atu_etiqueta_bloqueada ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_etiqueta_bloqueada FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_etiqueta_bloqueada_tenant_isolation ON atu_etiqueta_bloqueada
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
