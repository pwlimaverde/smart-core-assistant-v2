#!/bin/bash
set -e

# Conecta no banco POSTGRES_DB (evogo_auth) — o padrão seria db = nome do usuário
# ("evolution"), que NÃO existe, causando FATAL e travando a inicialização.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE evogo_users'
    WHERE NOT EXISTS (
        SELECT FROM pg_database WHERE datname = 'evogo_users'
    )\gexec
EOSQL
