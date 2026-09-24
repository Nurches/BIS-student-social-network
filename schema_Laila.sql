-- ============================================================
-- Student Social Network — database schema (PostgreSQL)
-- Data & Database — Taubay Laila
-- Run in pgAdmin or DBeaver: it creates the tables, inserts test data
-- and runs the two queries the requirements depend on.
-- ============================================================

DROP TABLE IF EXISTS notification, registration, event, subscription, community, student CASCADE;

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
    locked_until   TIMESTAMP,                         -- NFR-02: now() + 15 min after 5 failures
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_university_email CHECK (email LIKE '%@kbtu.kz')
);

CREATE TABLE community (
    community_id  SERIAL PRIMARY KEY,
    name          VARCHAR(120) NOT NULL UNIQUE,
    description   TEXT,
    owner_id      INTEGER      NOT NULL REFERENCES student(student_id),
    is_confirmed  BOOLEAN      NOT NULL DEFAULT FALSE,  -- confirmed by the Student Union (BR-01)
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE TABLE subscription (
    subscription_id SERIAL PRIMARY KEY,
    student_id      INTEGER   NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    community_id    INTEGER   NOT NULL REFERENCES community(community_id) ON DELETE CASCADE,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_subscription UNIQUE (student_id, community_id)
);

CREATE TABLE event (
    event_id              SERIAL PRIMARY KEY,
    community_id          INTEGER      NOT NULL REFERENCES community(community_id),
    title                 VARCHAR(160) NOT NULL,
    description           TEXT,
    location              VARCHAR(160),
    starts_at             TIMESTAMP    NOT NULL,
    registration_deadline TIMESTAMP    NOT NULL,
    participant_limit     INTEGER      NOT NULL CHECK (participant_limit > 0),
    status                VARCHAR(20)  NOT NULL DEFAULT 'draft',
    created_at            TIMESTAMP    NOT NULL DEFAULT NOW(),
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
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_registration UNIQUE (student_id, event_id),
    CONSTRAINT chk_registration_status CHECK (status IN ('confirmed', 'waiting_list', 'cancelled'))
);

CREATE TABLE notification (
    notification_id SERIAL PRIMARY KEY,
    student_id      INTEGER NOT NULL REFERENCES student(student_id) ON DELETE CASCADE,
    event_id        INTEGER NOT NULL REFERENCES event(event_id) ON DELETE CASCADE,
    sent_at         TIMESTAMP,
    is_read         BOOLEAN NOT NULL DEFAULT FALSE
);

-- ---------- Indexes (feed performance, NFR-01) ----------
CREATE INDEX idx_event_feed          ON event (status, registration_deadline);
CREATE INDEX idx_subscription_student ON subscription (student_id);
CREATE INDEX idx_registration_event   ON registration (event_id, status);
CREATE INDEX idx_notification_inbox   ON notification (student_id, is_read);

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
     NOW() + INTERVAL '3 days',  NOW() - INTERVAL '1 day',  25, 'published'),
 (3, 'Debate tournament', 'Draft, not published yet', 'Block B',
     NOW() + INTERVAL '21 days', NOW() + INTERVAL '18 days', 16, 'draft');

INSERT INTO registration (student_id, event_id, status) VALUES
 (2, 1, 'confirmed'),
 (3, 1, 'confirmed'),
 (4, 1, 'confirmed'),
 (5, 2, 'confirmed'),
 (1, 2, 'waiting_list');

-- ---------- The two queries the requirements depend on ----------

-- FEED (NFR-01): published events from the communities a student follows,
-- whose registration deadline has not passed. Example: student_id = 1.
SELECT e.event_id, c.name AS community, e.title, e.starts_at, e.registration_deadline
FROM event e
JOIN community c    ON c.community_id = e.community_id
JOIN subscription s ON s.community_id = e.community_id
WHERE s.student_id = 1
  AND e.status = 'published'
  AND e.registration_deadline > NOW()
ORDER BY e.registration_deadline;

-- FREE PLACES (FR-03): how many confirmed places are left for each published event.
SELECT e.event_id, e.title, e.participant_limit,
       COUNT(r.registration_id) FILTER (WHERE r.status = 'confirmed') AS taken,
       e.participant_limit - COUNT(r.registration_id) FILTER (WHERE r.status = 'confirmed') AS free_places
FROM event e
LEFT JOIN registration r ON r.event_id = e.event_id
WHERE e.status = 'published'
GROUP BY e.event_id, e.title, e.participant_limit
ORDER BY e.event_id;

-- Check that the unique constraint really works (this must fail):
-- INSERT INTO registration (student_id, event_id) VALUES (2, 1);
-- expected: duplicate key value violates unique constraint "uq_registration"
