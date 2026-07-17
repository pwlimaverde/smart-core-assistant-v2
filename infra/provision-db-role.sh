#!/usr/bin/env bash
# =============================================================================
# N4.1 — Role Postgres de runtime não-superuser (destrava o RLS)
# =============================================================================
# HOJE: smartcore_app é o role de bootstrap do container Postgres (POSTGRES_USER
# do compose) — o Postgres SEMPRE torna esse role SUPERUSER e o cluster proíbe
# removê-lo ("the bootstrap user must have the SUPERUSER attribute"). Por isso
# esta migração NÃO tenta rebaixar smartcore_app: ele continua sendo a role
# administrativa (DATABASE_ADMIN_URL) — inalterado.
#
# Este script cria, de forma aditiva e idempotente, uma NOVA role de runtime:
#   smartcore_app_rt — LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE,
#   com DML mínimo (SELECT/INSERT/UPDATE/DELETE) nas tabelas/sequences atuais e
#   futuras (ALTER DEFAULT PRIVILEGES FOR ROLE smartcore_app, que é quem roda as
#   migrations). É essa role, e não smartcore_app, que passa de verdade pelas
#   policies de RLS — igual ao modelo já usado no CI (lá a role restrita nasce
#   direto com esse nome, e o admin é `postgres`).
#
# APÓS rodar este script, atualize DATABASE_URL no .env do ambiente para apontar
# para smartcore_app_rt (DATABASE_ADMIN_URL continua em smartcore_app, sem
# mudança) e reinicie os serviços (data_postgres primeiro).
#
# Uso (a partir da raiz do repo ou de infra/), executado NO SERVIDOR ou via túnel
# apontando para o Postgres do ambiente alvo:
#   DATABASE_ADMIN_URL="postgresql://smartcore_app:<senha-atual>@host:5432/smartcore_v2" \
#   APP_RT_PASSWORD="<senha-forte-nova>" \
#   bash infra/provision-db-role.sh
#
# Pré-requisito: psql instalado; DATABASE_ADMIN_URL aponta para smartcore_app
# (a role administrativa/bootstrap do ambiente).
# =============================================================================
set -euo pipefail

if [[ -z "${DATABASE_ADMIN_URL:-}" ]]; then
    echo "ERRO: defina DATABASE_ADMIN_URL apontando para smartcore_app (role administrativa atual)." >&2
    exit 1
fi
if [[ -z "${APP_RT_PASSWORD:-}" ]]; then
    echo "ERRO: defina APP_RT_PASSWORD com a senha nova para smartcore_app_rt." >&2
    exit 1
fi

echo "============================================================"
echo " Provisionamento da role de runtime não-superuser (N4.1)"
echo "============================================================"

psql "$DATABASE_ADMIN_URL" -v ON_ERROR_STOP=1 -v rt_pw="$APP_RT_PASSWORD" <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartcore_app_rt') THEN
        EXECUTE format(
            'CREATE ROLE smartcore_app_rt LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE PASSWORD %L',
            :'rt_pw'
        );
    ELSE
        EXECUTE format('ALTER ROLE smartcore_app_rt PASSWORD %L', :'rt_pw');
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO smartcore_app_rt;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app_rt;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO smartcore_app_rt;

ALTER DEFAULT PRIVILEGES FOR ROLE smartcore_app IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smartcore_app_rt;
ALTER DEFAULT PRIVILEGES FOR ROLE smartcore_app IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO smartcore_app_rt;

ALTER ROLE smartcore_app_rt SET statement_timeout = '30s';
SQL

echo ""
echo "✓ smartcore_app_rt provisionada (NOSUPERUSER NOBYPASSRLS, DML mínimo)."
echo ""
echo "PRÓXIMOS PASSOS:"
echo "  1. Atualize DATABASE_URL no .env do ambiente:"
echo "     DATABASE_URL=postgresql://smartcore_app_rt:<APP_RT_PASSWORD>@<host>:5432/<db>"
echo "     (DATABASE_ADMIN_URL continua em smartcore_app, sem mudança)"
echo "  2. Reinicie os serviços (data_postgres primeiro; ele roda as migrations no boot)."
echo "  3. Revalide a suíte de isolamento: .\\infra\\test-local.ps1"
