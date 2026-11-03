-- ============================================================
-- Migration 002 — contract fixes (2026-11-03, roadmap M0)
-- Upgrades a database created by docs/schema.sql v1 to v2.
-- A fresh database does not need it: schema.sql v2 already contains it all.
-- Run once:  psql "$DATABASE_URL" -f docs/migrations/002_contract_fixes.sql
-- ============================================================

BEGIN;

-- v1 stored local times without a zone. The server runs in UTC, so existing
-- values are read as UTC. If a database was filled from a session in another
-- zone (for example pgAdmin on Asia/Almaty), set that zone here instead.
SET LOCAL TIME ZONE 'UTC';

-- ---------- 1. TIMESTAMP -> TIMESTAMPTZ ----------
ALTER TABLE student
    ALTER COLUMN locked_until TYPE TIMESTAMPTZ,
    ALTER COLUMN created_at   TYPE TIMESTAMPTZ;
ALTER TABLE community    ALTER COLUMN created_at TYPE TIMESTAMPTZ;
ALTER TABLE subscription ALTER COLUMN created_at TYPE TIMESTAMPTZ;
ALTER TABLE event
    ALTER COLUMN starts_at             TYPE TIMESTAMPTZ,
    ALTER COLUMN registration_deadline TYPE TIMESTAMPTZ,
    ALTER COLUMN created_at            TYPE TIMESTAMPTZ;
ALTER TABLE registration ALTER COLUMN created_at TYPE TIMESTAMPTZ;
ALTER TABLE notification ALTER COLUMN sent_at    TYPE TIMESTAMPTZ;

-- ---------- 2. Lockout window (NFR-02) ----------
-- "5 failed attempts within 10 minutes" needs the start of the window.
ALTER TABLE student ADD COLUMN first_failed_login_at TIMESTAMPTZ;

-- ---------- 3. Re-registration and waiting-list order (FR-03) ----------
-- Registering again after a cancel UPDATEs the row, so created_at no longer
-- says when the student joined the queue; updated_at does.
ALTER TABLE registration ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
UPDATE registration SET updated_at = created_at;

-- ---------- 4. No duplicate notifications (FR-01) ----------
ALTER TABLE notification
    ADD COLUMN kind       VARCHAR(30) NOT NULL DEFAULT 'event_published',
    ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ADD CONSTRAINT chk_notification_kind CHECK (kind IN ('event_published', 'waiting_list_promoted'));

-- Keep the oldest row of every duplicate before adding the constraint.
DELETE FROM notification n
USING notification older
WHERE older.student_id = n.student_id
  AND older.event_id = n.event_id
  AND older.kind = n.kind
  AND older.notification_id < n.notification_id;

ALTER TABLE notification
    ADD CONSTRAINT uq_notification UNIQUE (student_id, event_id, kind);

-- ---------- 5. FCM device tokens (FR-01) ----------
CREATE TABLE device_token (
    device_token_id SERIAL PRIMARY KEY,
    student_id      INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    token           VARCHAR(512) NOT NULL UNIQUE,
    platform        VARCHAR(10)  NOT NULL DEFAULT 'android',
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_device_platform CHECK (platform IN ('android', 'ios', 'web'))
);
CREATE INDEX idx_device_token_student ON device_token (student_id);

-- ---------- 6. Feed index matches the keyset cursor (NFR-01) ----------
DROP INDEX idx_event_feed;
CREATE INDEX idx_event_feed ON event (status, registration_deadline, event_id);

COMMIT;
