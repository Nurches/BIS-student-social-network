-- ============================================================
-- Migration 004 — community requests and event changes (2026-11-17, Week 12)
-- Upgrades a database created by docs/schema.sql v3 to v4.
--   * any student requests a community; a moderator approves or rejects it
--   * students registered for an event get a push when it is cancelled or moved
-- A fresh database does not need it: schema.sql v4 already contains it all.
-- Run once:  psql "$DATABASE_URL" -f docs/migrations/004_community_requests_and_event_changes.sql
-- ============================================================

BEGIN;

-- ---------- 1. Community status ----------
ALTER TABLE community
    ADD COLUMN status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    ADD COLUMN reject_reason VARCHAR(300),
    ADD COLUMN reviewed_at   TIMESTAMPTZ,
    ADD CONSTRAINT chk_community_status CHECK (status IN ('pending', 'confirmed', 'rejected'));

-- An unconfirmed v3 community becomes a request that still waits.
UPDATE community SET status = CASE WHEN is_confirmed THEN 'confirmed' ELSE 'pending' END;

-- is_confirmed stays readable (data checks, older queries) but follows status.
ALTER TABLE community DROP COLUMN is_confirmed;
ALTER TABLE community
    ADD COLUMN is_confirmed BOOLEAN GENERATED ALWAYS AS (status = 'confirmed') STORED;

-- The name is unique case-insensitively among pending and confirmed communities;
-- a rejected request frees its name.
ALTER TABLE community DROP CONSTRAINT community_name_key;
CREATE UNIQUE INDEX uq_community_name ON community (LOWER(name)) WHERE status <> 'rejected';
CREATE INDEX idx_community_owner_status ON community (owner_id, status);

-- ---------- 2. Event: cancelled and rescheduled ----------
ALTER TABLE event
    ADD COLUMN previous_starts_at TIMESTAMPTZ,
    ADD COLUMN cancelled_at       TIMESTAMPTZ;

UPDATE event SET cancelled_at = created_at WHERE status = 'cancelled';

-- ---------- 3. Notification kinds ----------
ALTER TABLE notification
    ALTER COLUMN event_id DROP NOT NULL,
    ADD COLUMN community_id INTEGER REFERENCES community(community_id) ON DELETE RESTRICT,
    DROP CONSTRAINT chk_notification_kind,
    ADD CONSTRAINT chk_notification_kind CHECK (kind IN (
        'event_published', 'waiting_list_promoted',
        'event_cancelled', 'event_rescheduled', 'community_approved')),
    ADD CONSTRAINT chk_notification_target CHECK (
        (kind = 'community_approved' AND community_id IS NOT NULL AND event_id IS NULL)
        OR (kind <> 'community_approved' AND event_id IS NOT NULL AND community_id IS NULL));

CREATE UNIQUE INDEX uq_notification_community
    ON notification (student_id, community_id, kind) WHERE community_id IS NOT NULL;

COMMIT;
