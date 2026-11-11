-- ============================================================
-- qatys_readonly — the database role of the /data-checks page (optional).
-- docs/tools/data-checks-spec.md: with DATABASE_URL_READONLY set, the checks
-- connect as this role, a second line of defence after the READ ONLY transaction.
--
-- Run once as the database owner (Neon: SQL Editor, or psql "$DATABASE_URL"):
--   psql "$DATABASE_URL" -v password="'<a long random password>'" -f docs/team/setup/readonly_role.sql
-- Then on Render set DATABASE_URL_READONLY to the same URL with user qatys_readonly
-- and that password. Never commit the password.
--
-- seed.py drops and recreates every table, and grants on a dropped table are
-- lost; it therefore grants SELECT to this role again at the end of every run
-- (W11-10), and the default privileges below cover tables created later.
-- ============================================================

CREATE ROLE qatys_readonly LOGIN PASSWORD :password;
SELECT format('GRANT CONNECT ON DATABASE %I TO qatys_readonly', current_database()) \gexec
GRANT USAGE ON SCHEMA public TO qatys_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO qatys_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO qatys_readonly;
