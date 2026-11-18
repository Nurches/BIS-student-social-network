-- Schema v3 (server/app/schema.sql of Week 11), kept for the migration 004 test.
-- Do not edit: it is what the live database looks like before docs/migrations/004.
DROP TABLE IF EXISTS device_token, notification, registration, event, subscription, community, student, faculty CASCADE;

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

CREATE TABLE community (
    community_id  SERIAL PRIMARY KEY,
    name          VARCHAR(120) NOT NULL UNIQUE,
    description   TEXT,
    owner_id      INTEGER      NOT NULL REFERENCES student(student_id),
    is_confirmed  BOOLEAN      NOT NULL DEFAULT FALSE,  -- confirmed by the Student Union (BR-01)
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ                           -- soft delete
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
    CONSTRAINT chk_event_status CHECK (status IN ('draft', 'published', 'cancelled')),
    CONSTRAINT chk_deadline_before_start CHECK (registration_deadline <= starts_at)
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
    -- One row per student and event. Cancelling sets status = 'cancelled';
    -- registering again UPDATEs this row (and updated_at), never INSERTs a second one.
    CONSTRAINT uq_registration UNIQUE (student_id, event_id),
    CONSTRAINT chk_registration_status CHECK (status IN ('confirmed', 'waiting_list', 'cancelled'))
);

CREATE TABLE notification (
    notification_id SERIAL PRIMARY KEY,
    student_id      INTEGER     NOT NULL REFERENCES student(student_id) ON DELETE RESTRICT,
    event_id        INTEGER     NOT NULL REFERENCES event(event_id) ON DELETE RESTRICT,
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

-- ---------- Reference data ----------
-- Faculty codes the API accepts (POST /auth/register "faculty"); any other code is
-- refused with 422 unknown_faculty. TODO(confirm): the official list of KBTU schools.
INSERT INTO faculty (code, name) VALUES
 ('SITE',          'School of Information Technology and Engineering'),
 ('BS',            'Business School'),
 ('ISE',           'International School of Economics'),
 ('IT',            'Information Technology (example code of docs/api.md)'),
 ('Student Union', 'Student Union staff');

