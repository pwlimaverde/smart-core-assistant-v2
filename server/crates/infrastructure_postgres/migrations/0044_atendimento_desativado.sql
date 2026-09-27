-- Exclusão lógica do atendimento.
--
-- "Excluir" no Smart Core é desativar: o registro fica, some do painel e das
-- listas, e a exclusão vai para a trilha de auditoria com o id — é por ela que
-- se restaura. Coluna própria, e não o status `arquivado`, porque arquivar é
-- curadoria do histórico (o worker arquiva sozinho as conversas paradas) e o
-- histórico do contato continua mostrando o que foi arquivado. O excluído não
-- aparece em lugar nenhum do painel.
--
-- NULL = ativo. Preenchida = desativado naquele instante.
ALTER TABLE oraculo_atendimento
    ADD COLUMN IF NOT EXISTS desativado_em TIMESTAMPTZ;
