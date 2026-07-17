-- N4.1 — grants mínimos para a role de runtime, destravando o RLS de verdade.
--
-- A separação role runtime (smartcore_app, NOBYPASSRLS) x role admin
-- (smartcore_app_admin, superuser/DDL) é provisionada por infra — ver
-- infra/provision-db-role.sh — e não por migration: REASSIGN OWNED/ALTER ROLE
-- NOSUPERUSER só são seguros rodando uma única vez por ambiente, com a credencial
-- ainda-superuser, não a cada `sqlx migrate run` no boot do serviço. Esta migration
-- só garante DML nas tabelas/sequences atuais e futuras para smartcore_app —
-- idempotente, roda tanto em dev/prod (já migrados via script) quanto no CI (onde a
-- role de runtime já nasce restrita pelo bootstrap do workflow).
GRANT USAGE ON SCHEMA public TO smartcore_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO smartcore_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO smartcore_app;

-- Privilégios padrão para objetos criados por migrations futuras — sem isto, cada
-- nova migration exigiria um GRANT manual adicional para a role de runtime enxergar
-- as tabelas/sequences novas.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO smartcore_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO smartcore_app;
