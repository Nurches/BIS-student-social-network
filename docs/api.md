# API v0.1

Base URL `/api/v1` · JSON only · every endpoint except `/auth/*` requires
`Authorization: Bearer <token>`.

All business rules are enforced on the server. The client never decides whether a
registration is allowed — it only displays the answer.

## POST /auth/register

Creates an account. Implements BR-01.

| Code | Meaning |
|---|---|
| 201 | Account created, verification code sent to the university address |
| 422 | The address is not a university address |
| 409 | The address is already registered |

## POST /auth/login

Returns a JWT valid for 24 hours. Implements NFR-02: after 5 failed attempts within
10 minutes the account is locked for 15 minutes and the endpoint answers 423 Locked.

## GET /feed?limit=20&cursor=&lt;event_id&gt;

Published events from the communities the student follows, whose registration deadline has
not passed, ordered by deadline. Target: 95% of calls under 2 seconds with 1000 concurrent
users (NFR-01). Pagination is cursor-based rather than OFFSET, because OFFSET gets slower
on every next page.

## POST /communities/{id}/events

Publishes an event announcement. Implements FR-02 and BR-01.

Request:

```json
{
  "title": "Autumn Hackathon 2026",
  "description": "24-hour team hackathon",
  "location": "Block C, room 301",
  "starts_at": "2026-10-08T10:00:00",
  "registration_deadline": "2026-10-04T23:59:00",
  "participant_limit": 30
}
```

| Code | Body |
|---|---|
| 201 | `{ "event_id": 17, "status": "published" }` |
| 422 | `{ "error": "deadline_in_the_past" }` — FR-02 |
| 422 | `{ "error": "deadline_after_event_start" }` |
| 403 | `{ "error": "not_a_confirmed_admin" }` — BR-01 |

After a successful publication the server creates a notification row for every subscriber
and sends a push message (FR-01).

## POST /events/{id}/registrations

Registers the authenticated student. Implements FR-03.

| Code | Body |
|---|---|
| 201 | `{ "status": "confirmed", "registration_id": 42 }` |
| 200 | `{ "status": "waiting_list", "position": 3 }` |
| 409 | `{ "error": "already_registered" }` |
| 410 | `{ "error": "deadline_passed" }` |
| 401 | `{ "error": "unauthorized" }` |

Server logic:

```
BEGIN;
  SELECT participant_limit, registration_deadline, status
    FROM event WHERE event_id = :id FOR UPDATE;        -- lock the event row

  IF status <> 'published'          THEN ROLLBACK; RETURN 404;
  IF registration_deadline < NOW()  THEN ROLLBACK; RETURN 410;

  SELECT COUNT(*) INTO taken FROM registration
    WHERE event_id = :id AND status = 'confirmed';

  new_status := CASE WHEN taken >= participant_limit
                     THEN 'waiting_list' ELSE 'confirmed' END;

  INSERT INTO registration (student_id, event_id, status)
    VALUES (:student, :id, new_status);                -- unique (student, event)
COMMIT;
```

**Why the row lock.** Without `FOR UPDATE`, two students pressing "Register" in the same
second both read `taken = 29` against a limit of 30, both pass the check and both are
confirmed — the event is overbooked and FR-03 is violated even though the code looks
correct. The lock makes the second transaction wait until the first one has committed.
A check in the user interface cannot solve this at all, and can additionally be bypassed by
any modified client.

## DELETE /events/{id}/registrations

Cancels the student's own registration. When a confirmed place is freed, the oldest
`waiting_list` row for that event is promoted to `confirmed` inside the same transaction and
that student is notified.

## Still to design

- editing an already published event: which changes re-notify the subscribers?
- cancelling an event: notify everyone who registered;
- moderator endpoints (confirming a community, blocking a user).
