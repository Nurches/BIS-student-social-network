-- ============================================================
-- Qatys API — database schema without test data.
-- Same tables as docs/schema.sql v5 (tests/test_schema_and_seed.py fails if they drift).
-- Used by seed.py and the test suite. Drops every table first.
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

