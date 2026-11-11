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
-- ============================================================

DROP TABLE IF EXISTS device_token, notification, registration, event, subscription, community, student CASCADE;

-- ---------- Tables ----------

CREATE TABLE student (
    student_id     SERIAL PRIMARY KEY,
    email          VARCHAR(120) NOT NULL UNIQUE,      -- university address only (BR-01)
    full_name      VARCHAR(120) NOT NULL,
    password_hash  VARCHAR(120) NOT NULL,             -- bcrypt, cost 12 (NFR-02)
    faculty        VARCHAR(80),
    enrolled_year  INTEGER,
    is_moderator   BOOLEAN      NOT NULL DEFAULT FALSE,
    failed_logins  INTEGER      NOT NULL DEFAULT 0,   -- NFR-02 lockout counter
    first_failed_login_at TIMESTAMPTZ,                -- NFR-02: start of the 10-minute window
    locked_until   TIMESTAMPTZ,                       -- NFR-02: now() + 15 min after 5 failures
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_university_email CHECK (email LIKE '%@kbtu.kz')
);

CREATE TABLE community (
    community_id  SERIAL PRIMARY KEY,
    name          VARCHAR(120) NOT NULL UNIQUE,
    description   TEXT,
    owner_id      INTEGER      NOT NULL REFERENCES student(student_id),
    is_confirmed  BOOLEAN      NOT NULL DEFAULT FALSE,  -- confirmed by the Student Union (BR-01)
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
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
    CONSTRAINT chk_event_status CHECK (status IN ('draft', 'published', 'cancelled')),
    CONSTRAINT chk_deadline_before_start CHECK (registration_deadline <= starts_at)
    -- FR-02 (the deadline must still be in the future at the moment of publication)
    -- is checked by the application: a CHECK constraint cannot compare with the current time.
);

CREATE TABLE registration (
    registration_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    event_id        INTEGER     NOT NULL REFERENCES event(event_id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL DEFAULT 'confirmed',   -- FR-03
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),         -- when the current status began
    -- One row per student and event. Cancelling sets status = 'cancelled';
    -- registering again UPDATEs this row (and updated_at), never INSERTs a second one.
    CONSTRAINT uq_registration UNIQUE (student_id, event_id),
    CONSTRAINT chk_registration_status CHECK (status IN ('confirmed', 'waiting_list', 'cancelled'))
);

CREATE TABLE notification (
    notification_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    event_id        INTEGER     NOT NULL REFERENCES event(event_id) ON DELETE CASCADE,
    kind            VARCHAR(30) NOT NULL DEFAULT 'event_published',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at         TIMESTAMPTZ,                                -- set when FCM accepted the push
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- FR-01: publishing twice (or a retried request) cannot notify a student twice.
    CONSTRAINT uq_notification UNIQUE (student_id, event_id, kind),
    CONSTRAINT chk_notification_kind CHECK (kind IN ('event_published', 'waiting_list_promoted'))
);

CREATE TABLE device_token (
    device_token_id SERIAL PRIMARY KEY,
    student_id      INTEGER      NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    token           VARCHAR(512) NOT NULL UNIQUE,                 -- FCM registration token
    platform        VARCHAR(10)  NOT NULL DEFAULT 'android',
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_device_platform CHECK (platform IN ('android', 'ios', 'web'))
);

-- ---------- Indexes (feed performance, NFR-01) ----------
CREATE INDEX idx_event_feed          ON event (status, registration_deadline, event_id);
CREATE INDEX idx_subscription_student ON subscription (student_id);
CREATE INDEX idx_registration_event   ON registration (event_id, status);
CREATE INDEX idx_notification_inbox   ON notification (student_id, is_read);
CREATE INDEX idx_device_token_student ON device_token (student_id);

-- ---------- Test data ----------

INSERT INTO student (email, full_name, password_hash, faculty, enrolled_year, is_moderator) VALUES
 ('nurassyl@kbtu.kz', 'Turarbek Nurassyl',  '$2b$12$placeholderhash1', 'IT',      2024, FALSE),
 ('akbota@kbtu.kz',   'Nurkasymova Akbota', '$2b$12$placeholderhash2', 'IT',      2024, FALSE),
 ('laila@kbtu.kz',    'Taubay Laila',       '$2b$12$placeholderhash3', 'IT',      2024, FALSE),
 ('madina@kbtu.kz',   'Shpanova Madina',    '$2b$12$placeholderhash4', 'IT',      2024, FALSE),
 ('gulnazym@kbtu.kz', 'Ualikhan Gulnazym',  '$2b$12$placeholderhash5', 'IT',      2024, FALSE),
 ('union@kbtu.kz',    'Student Union Staff','$2b$12$placeholderhash6', 'Admin',   2020, TRUE);

INSERT INTO community (name, description, owner_id, is_confirmed) VALUES
 ('IT Club',        'Programming contests, hackathons and workshops', 1, TRUE),
 ('Career Center',  'Internships, job fairs, CV clinics',             6, TRUE),
 ('Debate Society', 'Weekly debates and tournaments',                 2, FALSE);

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
