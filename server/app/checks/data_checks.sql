-- ============================================================
-- Qatys — data integrity checks (run by the /data-checks page)
-- Owner: Taubay Laila (Data & Database). Edit this file to add or change a check.
-- Format: every check starts with four metadata lines (check, title, requirement, sensitive), then ONE SELECT ending with ';'.
-- A check passes when its SELECT returns 0 rows.
-- sensitive = true hides row values on the page (shows only the row count).
-- ============================================================

-- @check C01
-- @title Confirmed registrations never exceed the limit
-- @requirement FR-03
-- @sensitive false
SELECT e.event_id, e.title, e.participant_limit, COUNT(r.registration_id) AS confirmed
FROM event e
JOIN registration r ON r.event_id = e.event_id AND r.status = 'confirmed'
GROUP BY e.event_id, e.title, e.participant_limit
HAVING COUNT(r.registration_id) > e.participant_limit;

-- @check C02
-- @title One registration row per student and event
-- @requirement FR-03
-- @sensitive false
-- (cancel + register again must UPDATE the row, not insert a second one).
SELECT student_id, event_id, COUNT(*) AS rows_for_pair
FROM registration
GROUP BY student_id, event_id
HAVING COUNT(*) > 1;

-- @check C03
-- @title No duplicate notification per student, target and kind
-- @requirement FR-01
-- @sensitive false
-- community_approved has no event. Two approvals are two communities, so an empty event_id is replaced by the community.
SELECT student_id,
       COALESCE(event_id, -community_id) AS target_id,
       kind,
       COUNT(*) AS copies
FROM notification
GROUP BY student_id, COALESCE(event_id, -community_id), kind
HAVING COUNT(*) > 1;

-- @check C04
-- @title Registration deadline is not after the event start
-- @requirement FR-02
-- @sensitive false
SELECT event_id, title, registration_deadline, starts_at
FROM event
WHERE registration_deadline > starts_at;

-- @check C05
-- @title Only confirmed communities have published events
-- @requirement BR-01
-- @sensitive false
SELECT e.event_id, e.title, c.name AS community
FROM event e
JOIN community c ON c.community_id = e.community_id
WHERE e.status = 'published'
  AND c.is_confirmed = FALSE;

-- @check C06
-- @title Every email is a university address
-- @requirement BR-01
-- @sensitive false
SELECT student_id, email
FROM student
WHERE email NOT LIKE '%@kbtu.kz';

-- @check C07
-- @title Nobody waits while free places exist
-- @requirement FR-03
-- @sensitive false
-- If this returns rows, a cancellation did not promote the waiting list.
SELECT e.event_id, e.title, e.participant_limit,
       COUNT(*) FILTER (WHERE r.status = 'confirmed')    AS confirmed,
       COUNT(*) FILTER (WHERE r.status = 'waiting_list') AS waiting
FROM event e
JOIN registration r ON r.event_id = e.event_id
GROUP BY e.event_id, e.title, e.participant_limit
HAVING COUNT(*) FILTER (WHERE r.status = 'waiting_list') > 0
   AND COUNT(*) FILTER (WHERE r.status = 'confirmed') < e.participant_limit;

-- @check C08
-- @title Every password is a bcrypt hash with cost 12
-- @requirement NFR-02
-- @sensitive true
SELECT student_id, email, LEFT(password_hash, 7) AS hash_prefix
FROM student
WHERE password_hash NOT LIKE '$2b$12$%';

-- @check C09
-- @title A notice on an unpublished event is a cancellation or history
-- @requirement FR-01
-- @sensitive false
-- event_cancelled points at a cancelled event on purpose. Notices sent before the cancellation stay. A row here is a new notice about a draft, or one created after the event was cancelled.
SELECT n.notification_id, n.event_id, n.kind, e.status
FROM notification n
JOIN event e ON e.event_id = n.event_id
WHERE e.status <> 'published'
  AND n.kind <> 'event_cancelled'
  AND (e.cancelled_at IS NULL OR n.created_at > e.cancelled_at);

-- @check C10
-- @title Nobody holds an active registration for a draft event
-- @requirement FR-03
-- @sensitive false
-- A cancelled event keeps its registrations for the record. A row here is a draft with a confirmed or waiting student.
SELECT r.registration_id, r.student_id, e.event_id, e.title,
       e.status AS event_status, r.status AS registration_status
FROM registration r
JOIN event e ON e.event_id = r.event_id
WHERE r.status IN ('confirmed', 'waiting_list')
  AND e.status = 'draft';

-- @check C11
-- @title A community that is not confirmed has no published event
-- @requirement BR-01
-- @sensitive false
-- FR-04. pending and rejected cannot publish. Same rule as C05, read from status.
SELECT e.event_id, e.title, c.name AS community, c.status
FROM event e
JOIN community c ON c.community_id = e.community_id
WHERE e.status = 'published'
  AND c.status <> 'confirmed';

-- @check C12
-- @title No student owns more than 3 pending communities
-- @requirement FR-04
-- @sensitive false
-- The limit covers many rows of one student, so a CHECK constraint cannot express it.
SELECT s.student_id, s.email, COUNT(*) AS pending_requests
FROM community c
JOIN student s ON s.student_id = c.owner_id
WHERE c.status = 'pending'
  AND c.deleted_at IS NULL
GROUP BY s.student_id, s.email
HAVING COUNT(*) > 3;

-- @check C13
-- @title Everyone registered for a cancelled event was notified
-- @requirement FR-05
-- @sensitive false
-- confirmed and waiting_list students must have an event_cancelled notice. A missing row means they were not told.
SELECT r.registration_id, r.student_id, e.event_id, e.title
FROM registration r
JOIN event e ON e.event_id = r.event_id
WHERE e.status = 'cancelled'
  AND r.status IN ('confirmed', 'waiting_list')
  AND NOT EXISTS (
      SELECT 1
      FROM notification n
      WHERE n.student_id = r.student_id
        AND n.event_id = e.event_id
        AND n.kind = 'event_cancelled'
  );
