-- ============================================================
-- Migration 003 — soft delete and faculty table (2026-11-10, Week 11)
-- Upgrades a database created by docs/schema.sql v2 to v3.
-- Promised to the instructor in Task 09:
--   * cascade delete loses history → soft delete      (Akbota, Architecture & Security)
--   * faculty as free text → faculty table             (Laila, Data & Database)
-- A fresh database does not need it: schema.sql v3 already contains it all.
-- The live database gets v3 by the reseed (docs/demo-runbook.md), not by this file.
-- Run once:  psql "$DATABASE_URL" -f docs/migrations/003_soft_delete_and_faculty.sql
-- ============================================================

BEGIN;

-- ---------- 1. Faculty table (Laila) ----------
CREATE TABLE faculty (
    faculty_id  SERIAL PRIMARY KEY,
    code        VARCHAR(40)  NOT NULL UNIQUE,
    name        VARCHAR(120) NOT NULL
);

INSERT INTO faculty (code, name) VALUES
 ('SITE',          'School of Information Technology and Engineering'),
 ('BS',            'Business School'),
 ('ISE',           'International School of Economics'),
 ('IT',            'Information Technology (example code of docs/api.md)'),
 ('Student Union', 'Student Union staff');

-- Nothing is lost: a free-text value that is not in the list becomes its own code.
INSERT INTO faculty (code, name)
SELECT DISTINCT LEFT(BTRIM(faculty), 40), BTRIM(faculty)
FROM student
WHERE NULLIF(BTRIM(faculty), '') IS NOT NULL
ON CONFLICT (code) DO NOTHING;

ALTER TABLE student ADD COLUMN faculty_id INTEGER REFERENCES faculty(faculty_id);
UPDATE student s
SET faculty_id = f.faculty_id
FROM faculty f
WHERE f.code = LEFT(BTRIM(s.faculty), 40);
ALTER TABLE student DROP COLUMN faculty;

-- ---------- 2. Soft delete (Akbota) ----------
-- A deleted row keeps its history: set deleted_at instead of DELETE. The API
-- ignores such rows (feed, event detail, registration, publishing, login).
ALTER TABLE student   ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE community ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE event     ADD COLUMN deleted_at TIMESTAMPTZ;

-- A real DELETE of a student or an event with registrations or notifications
-- is now refused instead of wiping that history.
ALTER TABLE registration
    DROP CONSTRAINT registration_student_id_fkey,
    ADD CONSTRAINT registration_student_id_fkey
        FOREIGN KEY (student_id) REFERENCES student(student_id) ON DELETE RESTRICT,
    DROP CONSTRAINT registration_event_id_fkey,
    ADD CONSTRAINT registration_event_id_fkey
        FOREIGN KEY (event_id) REFERENCES event(event_id) ON DELETE RESTRICT;

ALTER TABLE notification
    DROP CONSTRAINT notification_student_id_fkey,
    ADD CONSTRAINT notification_student_id_fkey
        FOREIGN KEY (student_id) REFERENCES student(student_id) ON DELETE RESTRICT,
    DROP CONSTRAINT notification_event_id_fkey,
    ADD CONSTRAINT notification_event_id_fkey
        FOREIGN KEY (event_id) REFERENCES event(event_id) ON DELETE RESTRICT;

COMMIT;
