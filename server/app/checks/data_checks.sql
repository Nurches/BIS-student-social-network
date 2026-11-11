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
-- @title No duplicate notification per student, event and kind
-- @requirement FR-01
-- @sensitive false
SELECT student_id, event_id, kind, COUNT(*) AS copies
FROM notification
GROUP BY student_id, event_id, kind
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
-- @title Notifications point only to published events
-- @requirement FR-01
-- @sensitive false
SELECT n.notification_id, n.event_id, e.status
FROM notification n
JOIN event e ON e.event_id = n.event_id
WHERE e.status <> 'published';

-- @check C10
-- @title Nobody holds an active registration for an unpublished event
-- @requirement FR-03
-- @sensitive false
-- Only a published event takes registrations; a row here is a draft or cancelled event with confirmed or waiting students.
SELECT r.registration_id, r.student_id, e.event_id, e.title,
       e.status AS event_status, r.status AS registration_status
FROM registration r
JOIN event e ON e.event_id = r.event_id
WHERE r.status IN ('confirmed', 'waiting_list')
  AND e.status <> 'published';
