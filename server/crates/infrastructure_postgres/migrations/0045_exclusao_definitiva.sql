-- Exclusão definitiva, separada de desativar (doc_dev/planejamento/39).
--
-- Três estados, e a diferença entre os dois últimos é o ponto:
--   ativo    — em uso;
--   inativo  — `ativo = false`: saiu de uso, aparece nas listas de gestão com
--              selo e volta com "Reativar";
--   excluído — `excluido_em` preenchido: some do painel, de seleções, da IA, das
--              filas, dos relatórios e das estatísticas, e NÃO volta — se for
--              preciso, cria-se outro. A linha fica só para a auditoria.
--
-- Coluna, e não um valor novo de status: só o atendimento tem status, e ele
-- dirige o quadro; as outras tabelas precisariam de uma coluna de qualquer jeito.

-- A 0044 criou `desativado_em` com a semântica de exclusão restaurável, que o
-- responsável substituiu por esta. Renomear em vez de criar outra coluna mantém
-- um lugar só para a informação.
ALTER TABLE oraculo_atendimento RENAME COLUMN desativado_em TO excluido_em;

ALTER TABLE oraculo_atendimento       ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;

ALTER TABLE oraculo_contato           ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_cliente           ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_departamento      ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_fluxo_atendimento ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_etapa_fluxo       ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_atendente         ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE atu_campo_personalizado   ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE atu_etiqueta              ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE atu_nota                  ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE treinamento_querycompose  ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE oraculo_treinamento       ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE whatsapp_whitelist        ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;
ALTER TABLE whatsapp_instance         ADD COLUMN IF NOT EXISTS excluido_em TIMESTAMPTZ,
                                      ADD COLUMN IF NOT EXISTS excluido_por_id INTEGER REFERENCES auth_user(id) ON DELETE SET NULL;

-- Unicidades só entre os não excluídos: o excluído não pode segurar o telefone,
-- o nome ou o e-mail — é o que permite "criar outro". Os `ON CONFLICT` que
-- dependiam das constraints passam a declarar o mesmo predicado.
ALTER TABLE oraculo_contato DROP CONSTRAINT IF EXISTS oraculo_contato_tenant_id_telefone_key;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_contato_tenant_telefone_vivo
    ON oraculo_contato (tenant_id, telefone) WHERE excluido_em IS NULL;

ALTER TABLE oraculo_departamento DROP CONSTRAINT IF EXISTS oraculo_departamento_tenant_id_nome_key;
ALTER TABLE oraculo_departamento DROP CONSTRAINT IF EXISTS oraculo_departamento_tenant_id_slug_key;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_departamento_tenant_nome_vivo
    ON oraculo_departamento (tenant_id, nome) WHERE excluido_em IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_departamento_tenant_slug_vivo
    ON oraculo_departamento (tenant_id, slug) WHERE excluido_em IS NULL;

ALTER TABLE oraculo_etapa_fluxo DROP CONSTRAINT IF EXISTS oraculo_etapa_fluxo_fluxo_id_ordem_key;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_etapa_fluxo_fluxo_ordem_viva
    ON oraculo_etapa_fluxo (fluxo_id, ordem) WHERE excluido_em IS NULL;

ALTER TABLE oraculo_atendente DROP CONSTRAINT IF EXISTS oraculo_atendente_tenant_id_email_key;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_atendente_tenant_email_vivo
    ON oraculo_atendente (tenant_id, email) WHERE excluido_em IS NULL;
DROP INDEX IF EXISTS oraculo_atendente_tenant_telefone;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_atendente_tenant_telefone
    ON oraculo_atendente (tenant_id, telefone)
    WHERE telefone IS NOT NULL AND telefone <> '' AND excluido_em IS NULL;

ALTER TABLE atu_campo_personalizado DROP CONSTRAINT IF EXISTS atu_campo_personalizado_tenant_id_slug_escopo_fluxo_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS atu_campo_personalizado_slug_vivo
    ON atu_campo_personalizado (tenant_id, slug, escopo, fluxo_id) WHERE excluido_em IS NULL;

ALTER TABLE atu_etiqueta DROP CONSTRAINT IF EXISTS atu_etiqueta_tenant_id_nome_key;
CREATE UNIQUE INDEX IF NOT EXISTS atu_etiqueta_tenant_nome_viva
    ON atu_etiqueta (tenant_id, nome) WHERE excluido_em IS NULL;

ALTER TABLE treinamento_querycompose DROP CONSTRAINT IF EXISTS treinamento_querycompose_tenant_id_tag_grupo_key;
CREATE UNIQUE INDEX IF NOT EXISTS treinamento_querycompose_tag_grupo_viva
    ON treinamento_querycompose (tenant_id, tag, grupo) WHERE excluido_em IS NULL;

ALTER TABLE oraculo_treinamento DROP CONSTRAINT IF EXISTS oraculo_treinamento_tenant_id_tag_grupo_key;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_treinamento_tag_grupo_vivo
    ON oraculo_treinamento (tenant_id, tag, grupo) WHERE excluido_em IS NULL;

ALTER TABLE whatsapp_whitelist DROP CONSTRAINT IF EXISTS whatsapp_whitelist_tenant_id_phone_number_key;
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_whitelist_tenant_telefone_vivo
    ON whatsapp_whitelist (tenant_id, phone_number) WHERE excluido_em IS NULL;

-- `instance_id` é o id do provedor, que some junto com a instância apagada lá:
-- continua único para sempre. Só o nome volta a ficar livre.
ALTER TABLE whatsapp_instance DROP CONSTRAINT IF EXISTS whatsapp_instance_tenant_id_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_instance_tenant_nome_viva
    ON whatsapp_instance (tenant_id, name) WHERE excluido_em IS NULL;

DROP INDEX IF EXISTS oraculo_cliente_tenant_cnpj;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_cliente_tenant_cnpj
    ON oraculo_cliente (tenant_id, cnpj)
    WHERE cnpj IS NOT NULL AND cnpj <> '' AND excluido_em IS NULL;
DROP INDEX IF EXISTS oraculo_cliente_tenant_cpf;
CREATE UNIQUE INDEX IF NOT EXISTS oraculo_cliente_tenant_cpf
    ON oraculo_cliente (tenant_id, cpf)
    WHERE cpf IS NOT NULL AND cpf <> '' AND excluido_em IS NULL;
