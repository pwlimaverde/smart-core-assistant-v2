-- Extensões (idempotente — init-script do Docker já as cria, mas garantimos aqui)
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabela global de usuários — mínima, sem RLS.
-- Alvo das FKs herdadas do legado Django (owner_id, user_id, recorded_by_id, etc.).
-- Gerenciamento real de usuários é feito pelo control_plane (fase futura).
CREATE TABLE IF NOT EXISTS auth_user (
    id           SERIAL PRIMARY KEY,
    username     VARCHAR(150) NOT NULL UNIQUE,
    email        VARCHAR(254) NOT NULL DEFAULT '',
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    is_staff     BOOLEAN NOT NULL DEFAULT FALSE,
    is_superuser BOOLEAN NOT NULL DEFAULT FALSE,
    date_joined  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- NOTA DE INFRA (não executado pelas migrations, role provisionada na infra):
-- CREATE ROLE smartcore_app WITH LOGIN PASSWORD '...' NOBYPASSRLS;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO smartcore_app;
-- A app NUNCA se conecta como superuser ou owner — RLS é obrigatório via smartcore_app.
