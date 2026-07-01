-- ============================================================
-- WS-5b: user_agent no audit_log (doc 08 §4.2 — metadados mínimos de auditoria)
-- Aditiva e nullable: sem backfill, retrocompatível com linhas existentes.
-- ============================================================

ALTER TABLE audit_log ADD COLUMN user_agent TEXT NULL;

COMMENT ON COLUMN audit_log.user_agent IS
    'User-Agent do cliente que originou o evento (metadado, nunca segredo). '
    'NULL para eventos sem contexto de requisição HTTP (sistema/background).';
