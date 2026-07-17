-- N4.1 (correção) — grants mínimos para a role de runtime real: smartcore_app_rt.
--
-- smartcore_app é o bootstrap user do container Postgres — o próprio Postgres
-- exige que ele permaneça SUPERUSER ("the bootstrap user must have the SUPERUSER
-- attribute"), então não pode virar a role restrita (ver nota em
-- 0016_app_runtime_role.sql). smartcore_app_rt é a role NOVA e aditiva
-- (NOSUPERUSER NOBYPASSRLS), provisionada por infra (infra/provision-db-role.sh
-- em dev/prod; bootstrap do workflow no CI) — pode não existir ainda no momento
-- em que esta migration roda (ex.: deploy antes de rodar o script em prod pela
-- 1ª vez), por isso o bloco é condicional: vira no-op nesse caso, e o próprio
-- script de provisionamento aplica os grants iniciais quando cria a role.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'smartcore_app_rt') THEN
        EXECUTE 'GRANT USAGE ON SCHEMA public TO smartcore_app_rt';
        EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app_rt';
        EXECUTE 'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO smartcore_app_rt';
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smartcore_app_rt';
        EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO smartcore_app_rt';
    END IF;
END $$;
