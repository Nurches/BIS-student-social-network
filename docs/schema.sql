-- ============================================================
-- Student Social Network — database schema (PostgreSQL 16)
-- Data & Database — Taubay Laila
-- Run in pgAdmin or DBeaver: it creates the tables, inserts test data
-- and runs the queries the requirements depend on.
--
-- v2 (2026-11-03): contract fixes from docs/migrations/002_contract_fixes.sql
-- are already applied here — TIMESTAMPTZ everywhere, device_token table,
-- no duplicate notifications, lockout window, waiting-list order.
-- An existing v1 database is upgraded with that migration instead.
--
-- v3 (2026-11-10, Week 11): docs/migrations/003_soft_delete_and_faculty.sql —
-- faculty reference table (student.faculty_id), soft delete (deleted_at on
-- student, community, event) and ON DELETE RESTRICT for registration and
-- notification, so history cannot disappear by accident.
--
-- v4 (2026-11-17, Week 12): docs/migrations/004_community_requests_and_event_changes.sql —
-- community.status (pending / confirmed / rejected) for requests by any student,
-- event.previous_starts_at and event.cancelled_at, and three notification kinds:
-- community_approved, event_cancelled, event_rescheduled.
--
-- v5 (2026-11-23, Week 13): docs/migrations/005_checkin_feedback_posters.sql —
-- registration.checked_in_at / checked_in_by (QR check-in), event.ends_at,
-- event_feedback (rating 1–5, one per student and event) and event_poster
-- (one image per event, JPEG / PNG / WebP up to 2 MB).
-- ============================================================

DROP TABLE IF EXISTS event_poster, event_feedback, device_token, notification, registration, event, subscription, community, student, faculty CASCADE;

-- ---------- Tables ----------

-- v3 (Week 11): faculties are a reference table instead of free text, so one
-- faculty cannot be spelled three ways (docs/migrations/003).
CREATE TABLE faculty (
    faculty_id  SERIAL PRIMARY KEY,
    code        VARCHAR(40)  NOT NULL UNIQUE,         -- what the API accepts, e.g. 'SITE'
    name        VARCHAR(120) NOT NULL
);

CREATE TABLE student (
    student_id     SERIAL PRIMARY KEY,
    email          VARCHAR(120) NOT NULL UNIQUE,      -- university address only (BR-01)
    full_name      VARCHAR(120) NOT NULL,
    password_hash  VARCHAR(120) NOT NULL,             -- bcrypt, cost 12 (NFR-02)
    faculty_id     INTEGER      REFERENCES faculty(faculty_id),
    enrolled_year  INTEGER,
    is_moderator   BOOLEAN      NOT NULL DEFAULT FALSE,
    failed_logins  INTEGER      NOT NULL DEFAULT 0,   -- NFR-02 lockout counter
    first_failed_login_at TIMESTAMPTZ,                -- NFR-02: start of the 10-minute window
    locked_until   TIMESTAMPTZ,                       -- NFR-02: now() + 15 min after 5 failures
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMPTZ,                       -- soft delete: set instead of DELETE
    CONSTRAINT chk_university_email CHECK (email LIKE '%@kbtu.kz')
);

-- v4 (Week 12): any student may request a community (status 'pending'); a
-- Student Union moderator approves ('confirmed') or rejects it. Only a confirmed
-- community may publish (BR-01). The requester is the owner.
CREATE TABLE community (
    community_id  SERIAL PRIMARY KEY,
    name          VARCHAR(120) NOT NULL,                -- unique, see uq_community_name
    description   TEXT,
    owner_id      INTEGER      NOT NULL REFERENCES student(student_id),
    status        VARCHAR(20)  NOT NULL DEFAULT 'pending',
    -- Kept from v3 so every reader of is_confirmed still works; never written.
    is_confirmed  BOOLEAN      GENERATED ALWAYS AS (status = 'confirmed') STORED,
    reject_reason VARCHAR(300),                         -- shown to the student who asked
    reviewed_at   TIMESTAMPTZ,                          -- when a moderator approved or rejected
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ,                          -- soft delete
    CONSTRAINT chk_community_status CHECK (status IN ('pending', 'confirmed', 'rejected'))
);

CREATE TABLE subscription (
    subscription_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    community_id    INTEGER     NOT NULL REFERENCES community(community_id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_subscription UNIQUE (student_id, community_id)
);

CREATE TABLE event (
    event_id              SERIAL PRIMARY KEY,
    community_id          INTEGER      NOT NULL REFERENCES community(community_id),
    title                 VARCHAR(160) NOT NULL,
    description           TEXT,
    location              VARCHAR(160),
    starts_at             TIMESTAMPTZ  NOT NULL,
    registration_deadline TIMESTAMPTZ  NOT NULL,
    participant_limit     INTEGER      NOT NULL CHECK (participant_limit > 0),
    status                VARCHAR(20)  NOT NULL DEFAULT 'draft',
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at            TIMESTAMPTZ,                 -- soft delete
    previous_starts_at    TIMESTAMPTZ,                 -- v4: the start before the last reschedule
    cancelled_at          TIMESTAMPTZ,                 -- v4: when the event was cancelled
    -- v5 (Week 13): when the event ends; NULL = two hours after the start.
    -- Feedback opens at the end (FR-07); "Finish now" in /admin sets it.
    ends_at               TIMESTAMPTZ,
    CONSTRAINT chk_event_status CHECK (status IN ('draft', 'published', 'cancelled')),
    CONSTRAINT chk_deadline_before_start CHECK (registration_deadline <= starts_at),
    CONSTRAINT chk_end_after_start CHECK (ends_at IS NULL OR ends_at > starts_at)
    -- FR-02 (the deadline must still be in the future at the moment of publication)
    -- is checked by the application: a CHECK constraint cannot compare with the current time.
);

CREATE TABLE registration (
    registration_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    event_id        INTEGER     NOT NULL REFERENCES event(event_id) ON DELETE RESTRICT,
    status          VARCHAR(20) NOT NULL DEFAULT 'confirmed',   -- FR-03
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),         -- when the current status began
    -- v5 (Week 13, FR-06): the organiser scanned the ticket at the door. Only a
    -- confirmed registration is checked in, once (application rule, data check C14).
    checked_in_at   TIMESTAMPTZ,
    checked_in_by   INTEGER     REFERENCES student(student_id) ON DELETE RESTRICT,
    -- One row per student and event. Cancelling sets status = 'cancelled';
    -- registering again UPDATEs this row (and updated_at), never INSERTs a second one.
    CONSTRAINT uq_registration UNIQUE (student_id, event_id),
    CONSTRAINT chk_registration_status CHECK (status IN ('confirmed', 'waiting_list', 'cancelled'))
);

CREATE TABLE notification (
    notification_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    event_id        INTEGER     REFERENCES event(event_id) ON DELETE RESTRICT,
    -- v4: a notification is about an event, or (community_approved) about a community.
    community_id    INTEGER     REFERENCES community(community_id) ON DELETE RESTRICT,
    kind            VARCHAR(30) NOT NULL DEFAULT 'event_published',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at         TIMESTAMPTZ,                                -- set when FCM accepted the push
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- FR-01: publishing twice (or a retried request) cannot notify a student twice.
    -- A second reschedule re-sends the same row (sent_at = NULL) instead of adding one.
    CONSTRAINT uq_notification UNIQUE (student_id, event_id, kind),
    CONSTRAINT chk_notification_kind CHECK (kind IN (
        'event_published', 'waiting_list_promoted',
        'event_cancelled', 'event_rescheduled', 'community_approved')),
    CONSTRAINT chk_notification_target CHECK (
        (kind = 'community_approved' AND community_id IS NOT NULL AND event_id IS NULL)
        OR (kind <> 'community_approved' AND event_id IS NOT NULL AND community_id IS NULL))
);

CREATE TABLE device_token (
    device_token_id SERIAL PRIMARY KEY,
    student_id      INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    token           VARCHAR(512) NOT NULL UNIQUE,                 -- FCM registration token
    platform        VARCHAR(10)  NOT NULL DEFAULT 'android',
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_device_platform CHECK (platform IN ('android', 'ios', 'web'))
);

-- v5 (Week 13, FR-07): one rating per student and event, from a student who was
-- checked in, after the event ended (application rules, data check C15).
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

-- v5 (Week 13, FR-08): at most one poster per event, uploaded in /admin by the
-- community owner or a moderator. Kept in the database: the free Render disk is
-- wiped on every deploy. The server re-encodes every upload (no EXIF / GPS).
CREATE TABLE event_poster (
    event_id    INTEGER      PRIMARY KEY REFERENCES event(event_id) ON DELETE CASCADE,
    mime        VARCHAR(20)  NOT NULL,
    size_bytes  INTEGER      NOT NULL,
    width       INTEGER      NOT NULL CHECK (width > 0),
    height      INTEGER      NOT NULL CHECK (height > 0),
    data        BYTEA        NOT NULL,                  -- the re-encoded image
    uploaded_by INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    uploaded_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_poster_mime CHECK (mime IN ('image/jpeg', 'image/png', 'image/webp')),
    CONSTRAINT chk_poster_size CHECK (size_bytes > 0 AND size_bytes <= 2097152),  -- 2 MB
    CONSTRAINT chk_poster_size_matches CHECK (octet_length(data) = size_bytes)
);

-- ---------- Indexes (feed performance, NFR-01) ----------
CREATE INDEX idx_event_feed          ON event (status, registration_deadline, event_id);
CREATE INDEX idx_subscription_student ON subscription (student_id);
CREATE INDEX idx_registration_event   ON registration (event_id, status);
CREATE INDEX idx_notification_inbox   ON notification (student_id, is_read);
CREATE INDEX idx_device_token_student ON device_token (student_id);
-- v4: a name is taken case-insensitively by a pending or confirmed community;
-- a rejected request frees it. The owner index serves the 3-pending limit.
CREATE UNIQUE INDEX uq_community_name ON community (LOWER(name)) WHERE status <> 'rejected';
CREATE INDEX idx_community_owner_status ON community (owner_id, status);
CREATE UNIQUE INDEX uq_notification_community
    ON notification (student_id, community_id, kind) WHERE community_id IS NOT NULL;
-- v5: analytics count check-ins and ratings per event.
CREATE INDEX idx_registration_checked_in ON registration (event_id) WHERE checked_in_at IS NOT NULL;
CREATE INDEX idx_feedback_event ON event_feedback (event_id);

-- ---------- Reference data ----------
-- Faculty codes the API accepts (POST /auth/register "faculty"); any other code is
-- refused with 422 unknown_faculty. TODO(confirm): the official list of KBTU schools.
INSERT INTO faculty (code, name) VALUES
 ('SITE',          'School of Information Technology and Engineering'),
 ('BS',            'Business School'),
 ('ISE',           'International School of Economics'),
 ('IT',            'Information Technology (example code of docs/api.md)'),
 ('Student Union', 'Student Union staff');

-- ---------- Test data ----------

-- Faculty by code (v3): 1 = SITE … 4 = IT, 5 = Student Union (reference data above).
INSERT INTO student (email, full_name, password_hash, faculty_id, enrolled_year, is_moderator) VALUES
 ('nurassyl@kbtu.kz', 'Turarbek Nurassyl',  '$2b$12$placeholderhash1', 4, 2024, FALSE),
 ('akbota@kbtu.kz',   'Nurkasymova Akbota', '$2b$12$placeholderhash2', 4, 2024, FALSE),
 ('laila@kbtu.kz',    'Taubay Laila',       '$2b$12$placeholderhash3', 4, 2024, FALSE),
 ('madina@kbtu.kz',   'Shpanova Madina',    '$2b$12$placeholderhash4', 4, 2024, FALSE),
 ('gulnazym@kbtu.kz', 'Ualikhan Gulnazym',  '$2b$12$placeholderhash5', 4, 2024, FALSE),
 ('union@kbtu.kz',    'Student Union Staff','$2b$12$placeholderhash6', 5, 2020, TRUE);

-- v4: Debate Society is a request of student 2 that waits for the Student Union.
INSERT INTO community (name, description, owner_id, status) VALUES
 ('IT Club',        'Programming contests, hackathons and workshops', 1, 'confirmed'),
 ('Career Center',  'Internships, job fairs, CV clinics',             6, 'confirmed'),
 ('Debate Society', 'Weekly debates and tournaments',                 2, 'pending');

INSERT INTO subscription (student_id, community_id) VALUES
 (1,1), (2,1), (3,1), (4,1), (5,1),
 (1,2), (3,2), (5,2),
 (2,3);

INSERT INTO event (community_id, title, description, location, starts_at, registration_deadline, participant_limit, status) VALUES
 (1, 'Autumn Hackathon 2026', '24-hour team hackathon', 'Block C, room 301',
     NOW() + INTERVAL '14 days', NOW() + INTERVAL '10 days', 30, 'published'),
 (2, 'IT Career Day',         'Meeting with 12 companies', 'Main hall',
     NOW() + INTERVAL '7 days',  NOW() + INTERVAL '5 days', 200, 'published'),
 (1, 'Git workshop for first-years', 'Basics of version control', 'Block A, room 105',
     NOW() + INTERVAL '3 days',  NOW() - INTERVAL '1 day',   2, 'published'),
 (3, 'Debate tournament', 'Draft, not published yet', 'Block B',
     NOW() + INTERVAL '21 days', NOW() + INTERVAL '18 days', 16, 'draft');

-- Week 11 (found by data check C07): student 1 used to wait for IT Career Day
-- while 199 of its 200 places were free, which breaks FR-03. Student 1 is now
-- confirmed there, and the waiting-list example moved to the Git workshop,
-- which is full (2 of 2).
-- TODO(confirm): Laila may prefer making IT Career Day full instead.
INSERT INTO registration (student_id, event_id, status) VALUES
 (2, 1, 'confirmed'),
 (3, 1, 'confirmed'),
 (4, 1, 'confirmed'),
 (5, 2, 'confirmed'),
 (1, 2, 'confirmed'),
 (2, 3, 'confirmed'),
 (3, 3, 'confirmed'),
 (4, 3, 'waiting_list');

-- One notification per subscriber for each published event (FR-01).
INSERT INTO notification (student_id, event_id, sent_at)
SELECT s.student_id, e.event_id, e.created_at
FROM event e
JOIN subscription s ON s.community_id = e.community_id
WHERE e.status = 'published';

-- ---------- The queries the requirements depend on ----------

-- FEED (NFR-01): published events from the communities a student follows,
-- whose registration deadline has not passed. Example: student_id = 1.
-- Keyset pagination: the next page passes the (registration_deadline, event_id)
-- of the last row of this page instead of an OFFSET.
SELECT e.event_id, c.name AS community, e.title, e.starts_at, e.registration_deadline
FROM event e
JOIN community c    ON c.community_id = e.community_id
JOIN subscription s ON s.community_id = e.community_id
WHERE s.student_id = 1
  AND e.status = 'published'
  AND e.registration_deadline > NOW()
  -- next page: AND (e.registration_deadline, e.event_id) > (:last_deadline, :last_event_id)
ORDER BY e.registration_deadline, e.event_id
LIMIT 20;

-- FREE PLACES (FR-03): how many confirmed places are left for each published event.
SELECT e.event_id, e.title, e.participant_limit,
       COUNT(r.registration_id) FILTER (WHERE r.status = 'confirmed') AS taken,
       e.participant_limit - COUNT(r.registration_id) FILTER (WHERE r.status = 'confirmed') AS free_places
FROM event e
LEFT JOIN registration r ON r.event_id = e.event_id
WHERE e.status = 'published'
GROUP BY e.event_id, e.title, e.participant_limit
ORDER BY e.event_id;

-- WAITING LIST (FR-03): queue order for one event; the first row is promoted
-- when a confirmed place is cancelled.
SELECT r.student_id,
       ROW_NUMBER() OVER (ORDER BY r.updated_at, r.registration_id) AS position
FROM registration r
WHERE r.event_id = 3 AND r.status = 'waiting_list';

-- Check that the unique constraints really work (each of these must fail):
-- INSERT INTO registration (student_id, event_id) VALUES (2, 1);
-- expected: duplicate key value violates unique constraint "uq_registration"
-- INSERT INTO notification (student_id, event_id) VALUES (1, 1);
-- expected: duplicate key value violates unique constraint "uq_notification"
