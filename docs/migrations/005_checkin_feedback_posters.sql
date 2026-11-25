-- ============================================================
-- Migration 005 — check-in, feedback and posters (2026-11-23, Week 13)
-- Upgrades a database created by docs/schema.sql v4 to v5.
--   * FR-06: the organiser checks a student in at the door (QR ticket or code)
--   * FR-07: a student who attended rates the event 1–5 after it ends
--   * FR-08: a community owner uploads a poster for an event in /admin
-- A fresh database does not need it: schema.sql v5 already contains it all.
-- Run once:  psql "$DATABASE_URL" -f docs/migrations/005_checkin_feedback_posters.sql
-- ============================================================

BEGIN;

-- ---------- 1. Event end ----------
-- NULL = two hours after the start; feedback opens at the end.
ALTER TABLE event
    ADD COLUMN ends_at TIMESTAMPTZ,
    ADD CONSTRAINT chk_end_after_start CHECK (ends_at IS NULL OR ends_at > starts_at);

-- ---------- 2. Check-in ----------
-- Only a confirmed registration is checked in, once (application rule, data check C14).
ALTER TABLE registration
    ADD COLUMN checked_in_at TIMESTAMPTZ,
    ADD COLUMN checked_in_by INTEGER REFERENCES student(student_id) ON DELETE RESTRICT;

CREATE INDEX idx_registration_checked_in ON registration (event_id) WHERE checked_in_at IS NOT NULL;

-- ---------- 3. Feedback ----------
CREATE TABLE event_feedback (
    feedback_id SERIAL PRIMARY KEY,
    event_id    INTEGER      NOT NULL REFERENCES event(event_id) ON DELETE RESTRICT,
    student_id  INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    rating      SMALLINT     NOT NULL,
    comment     VARCHAR(500),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_feedback UNIQUE (event_id, student_id),
    CONSTRAINT chk_feedback_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE INDEX idx_feedback_event ON event_feedback (event_id);

-- ---------- 4. Posters ----------
CREATE TABLE event_poster (
    event_id    INTEGER      PRIMARY KEY REFERENCES event(event_id) ON DELETE CASCADE,
    mime        VARCHAR(20)  NOT NULL,
    size_bytes  INTEGER      NOT NULL,
    width       INTEGER      NOT NULL CHECK (width > 0),
    height      INTEGER      NOT NULL CHECK (height > 0),
    data        BYTEA        NOT NULL,
    uploaded_by INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    uploaded_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_poster_mime CHECK (mime IN ('image/jpeg', 'image/png', 'image/webp')),
    CONSTRAINT chk_poster_size CHECK (size_bytes > 0 AND size_bytes <= 2097152),
    CONSTRAINT chk_poster_size_matches CHECK (octet_length(data) = size_bytes)
);

COMMIT;

-- After the migration, give the read-only role of the data checks the new tables:
--   GRANT SELECT ON event_feedback, event_poster TO qatys_readonly;
