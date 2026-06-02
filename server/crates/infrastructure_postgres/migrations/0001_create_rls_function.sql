-- Extensões (idempotente — init-script do Docker já as cria, mas garantimos aqui)
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabela global de usuários — sem RLS (lookups de autenticação são cross-tenant).
-- Alvo das FKs de owner_id, user_id, recorded_by_id, oraculo_atendente.usuario_id, etc.
-- Hierarquia: is_superuser=true → acesso ao control_plane; senão → usuário de tenant
-- (owner via tenants_tenant.owner_id ou funcionário via tenants_tenantuser).
CREATE TABLE IF NOT EXISTS auth_user (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(150) NOT NULL UNIQUE,
    email         VARCHAR(254) NOT NULL DEFAULT '',
    password_hash VARCHAR(255) NOT NULL DEFAULT '',  -- string PHC argon2id
    first_name    VARCHAR(150) NOT NULL DEFAULT '',
    last_name     VARCHAR(150) NOT NULL DEFAULT '',
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    is_staff      BOOLEAN NOT NULL DEFAULT FALSE,
    is_superuser  BOOLEAN NOT NULL DEFAULT FALSE,
    last_login    TIMESTAMPTZ,
    date_joined   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para lookups de autenticação (cross-tenant, sem RLS).
CREATE UNIQUE INDEX IF NOT EXISTS auth_user_email_idx
    ON auth_user (email) WHERE email != '';
CREATE INDEX IF NOT EXISTS auth_user_superuser_idx
    ON auth_user (is_superuser) WHERE is_superuser = TRUE;

-- NOTA DE INFRA (não executado pelas migrations, role provisionada na infra):
-- CREATE ROLE smartcore_app WITH LOGIN PASSWORD '...' NOBYPASSRLS;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app;
-- GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO smartcore_app;
-- A app NUNCA se conecta como superuser ou owner — RLS é obrigatório via smartcore_app.

-- ============================================================
-- Timeouts de confiabilidade (nível DATABASE/ROLE; sobrevivem a dump/restore)
-- ============================================================
-- Transação idle por mais de 30s é abortada, liberando locks e conexão ao pool.
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET idle_in_transaction_session_timeout = ''30s''',
                   current_database());
END $$;

-- Espera por lock superior a 15s é abortada (evita deadlock silencioso em cascata).
DO $$ BEGIN
    EXECUTE format('ALTER DATABASE %I SET lock_timeout = ''15s''', current_database());
END $$;

-- statement_timeout apenas no role de runtime; não afeta migrations/manutenção (admin).
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartcore_app') THEN
        ALTER ROLE smartcore_app SET statement_timeout = '30s';
    END IF;
END $$;
