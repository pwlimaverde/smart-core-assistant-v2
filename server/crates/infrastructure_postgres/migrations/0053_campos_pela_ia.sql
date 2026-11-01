-- V3 — quais campos do cliente e do contato foram preenchidos pela IA a partir
-- da conversa. A ficha mostra a marca; editar o campo tira a marca.
ALTER TABLE oraculo_cliente
    ADD COLUMN IF NOT EXISTS campos_pela_ia TEXT[] NOT NULL DEFAULT '{}';

ALTER TABLE oraculo_contato
    ADD COLUMN IF NOT EXISTS campos_pela_ia TEXT[] NOT NULL DEFAULT '{}';
