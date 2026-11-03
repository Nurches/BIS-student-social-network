# API v0.2

Base URL `/api/v1` · JSON only · every endpoint except `/health` and `/auth/*` requires
`Authorization: Bearer <token>`.

All business rules are enforced on the server. The client never decides whether a
registration is allowed — it only displays the answer.

**v0.2 (2026-11-03, roadmap M0):** added `GET /health`, `GET /events/{id}`,
`PUT|DELETE /me/device-token`, every response body, the Event object, the feed envelope and
cursor, the lockout rule and the error format. Database changes are in
`docs/migrations/002_contract_fixes.sql`.

## Conventions

**Errors.** Every error response has the body `{ "error": "<code>" }`, where `<code>` is a
stable `snake_case` string the client can switch on. Extra fields are allowed (for example
`retry_after_minutes`). Request validation failures (missing field, wrong type, limit out of
range) are `422 { "error": "validation_failed", "detail": [...] }`.

| Code | Error | When |
|---|---|---|
| 401 | `unauthorized` | Token missing, malformed, wrong signature or expired |
| 404 | `<entity>_not_found` | The resource does not exist or the student may not see it |
| 422 | `validation_failed` | The body or query does not match this document |
| 413 | `payload_too_large` | Body over 64 KB, rejected before parsing |
| 429 | `too_many_requests` | `POST /auth/login`: more than 20 attempts per minute from one IP; header `Retry-After` |
| 500 | `internal_error` | Never with a stack trace |

**Time.** Every timestamp is ISO 8601 **with an offset**, for example
`2026-11-20T18:00:00+05:00`. The server stores `TIMESTAMPTZ`, runs in UTC and may answer in
UTC (`...Z` or `+00:00`); the client converts to device time. A request timestamp without an
offset is rejected with `422 { "error": "timestamp_without_offset" }`.

**Names.** JSON fields are `snake_case` and follow the column names in `docs/schema.sql`.

## GET /health

Full path `/api/v1/health`. No authentication. Cheap enough to call before every retry. Also checks the database
connection, so the client treats only `200` as "the server is reachable".

| Code | Body |
|---|---|
| 200 | `{ "status": "ok" }` |
| 503 | `{ "status": "unavailable", "error": "database_unavailable" }` |

## POST /auth/register

Creates an account. Implements BR-01.

```json
{ "email": "student@kbtu.kz", "password": "at least 8 characters", "full_name": "Aru Sadykova",
  "faculty": "IT", "enrolled_year": 2026 }
```

`faculty` and `enrolled_year` are optional. The email is trimmed and lower-cased before any
check. The password is stored as a bcrypt hash with cost 12 (NFR-02).

| Code | Body |
|---|---|
| 201 | `{ "student_id": 12, "email": "student@kbtu.kz", "full_name": "Aru Sadykova" }` |
| 422 | `{ "error": "not_a_university_email" }` — BR-01 |
| 422 | `{ "error": "password_too_short" }` |
| 409 | `{ "error": "email_already_registered" }` |

For the demo the account is active at once; no verification email is sent (known
limitation, roadmap §8).

## POST /auth/login

Returns a JWT valid for 24 hours. Implements NFR-02.

```json
{ "email": "student@kbtu.kz", "password": "..." }
```

| Code | Body |
|---|---|
| 200 | `{ "token": "<jwt>", "student": { "student_id": 12, "email": "student@kbtu.kz", "full_name": "Aru Sadykova" } }` |
| 401 | `{ "error": "invalid_credentials" }` — unknown email or wrong password, same answer for both |
| 422 | `{ "error": "not_a_university_email" }` — BR-01 |
| 423 | `{ "error": "account_locked", "retry_after_minutes": 14 }` plus header `Retry-After: <seconds>` |

**Lockout rule (NFR-02).**

1. A wrong password answers `401`. The first failure opens a 10-minute window
   (`student.first_failed_login_at`); a failure after the window has closed starts a new one.
2. The **5th** failure inside the window still answers `401` and sets
   `locked_until = now() + 15 min`; the counter and the window are reset.
3. While `locked_until` is in the future every login answers `423`, **even with the correct
   password**, and failed attempts do not extend the lock.
   `retry_after_minutes` is the remaining time rounded up, so it is never 0.
4. A successful login resets `failed_logins` and `first_failed_login_at`.

So the 6th attempt in a row is the first one that sees `423`.

JWT claims: `sub` = `student_id` (string), `exp` = issue time + 24 h. Algorithm HS256, secret
from the environment.

## GET /feed?limit=20&cursor=&lt;cursor&gt;

Published events from the communities the student follows, whose registration deadline has
not passed, ordered by `(registration_deadline, event_id)`. Target: 95% of calls under 2
seconds with 1000 concurrent users (NFR-01). `free_places` and `my_status` are computed in the
same SQL query, not per event.

| Parameter | Rule |
|---|---|
| `limit` | 1–50, default 20 |
| `cursor` | Omit for the first page; then pass `next_cursor` from the previous page unchanged |

```json
{ "items": [ /* Event, Event, ... */ ], "next_cursor": "MjAyNi0xMS0xNlQxODo1OTowMFp8MTc" }
```

`next_cursor` is `null` on the last page.

**Cursor.** Keyset pagination rather than OFFSET, because OFFSET gets slower on every next
page and skips or repeats rows when events are published in between. The cursor encodes the
`(registration_deadline, event_id)` of the last item of the page, and the next page continues
with `WHERE (registration_deadline, event_id) > (:deadline, :event_id)`. It is an opaque string
for the client (today: base64url of `<deadline ISO 8601>|<event_id>`, no padding). A cursor
that cannot be decoded answers `422 { "error": "invalid_cursor" }`.

## Event object

Used by the feed and by `GET /events/{id}`.

```json
{
  "event_id": 17,
  "community_id": 1,
  "community_name": "IT Club",
  "title": "Autumn Hackathon 2026",
  "description": "24-hour team hackathon",
  "location": "Block C, room 301",
  "starts_at": "2026-11-20T10:00:00+05:00",
  "registration_deadline": "2026-11-16T23:59:00+05:00",
  "participant_limit": 30,
  "free_places": 27,
  "my_status": "waiting_list",
  "waiting_position": 3
}
```

| Field | Rule |
|---|---|
| `description`, `location` | May be `null` |
| `free_places` | `participant_limit` minus confirmed registrations, never below 0 |
| `my_status` | `null` (not registered or cancelled), `"confirmed"` or `"waiting_list"` |
| `waiting_position` | 1-based place in the queue when `my_status = "waiting_list"`, otherwise `null` |

The queue is ordered by `registration.updated_at`, then `registration_id`: the moment the
student joined the waiting list, not when they first registered for the event.

## GET /events/{id}

One Event object with fresh `free_places` and `my_status`. The detail screen calls it every
time it opens, because the feed copy may be stale.

Any authenticated student can open any **published** event, including one from a community
they do not follow (a link from a friend) and one whose deadline has passed (the app shows it
as closed, FR-02).

| Code | Body |
|---|---|
| 200 | Event object |
| 404 | `{ "error": "event_not_found" }` — no such event, or it is `draft` / `cancelled` |

## POST /communities/{id}/events

Publishes an event announcement. Implements FR-02 and BR-01.

Request:

```json
{
  "title": "Autumn Hackathon 2026",
  "description": "24-hour team hackathon",
  "location": "Block C, room 301",
  "starts_at": "2026-11-20T10:00:00+05:00",
  "registration_deadline": "2026-11-16T23:59:00+05:00",
  "participant_limit": 30
}
```

| Code | Body |
|---|---|
| 201 | `{ "event_id": 17, "status": "published" }` |
| 404 | `{ "error": "community_not_found" }` |
| 403 | `{ "error": "not_a_confirmed_admin" }` — BR-01: caller is not the owner, or the community is not confirmed |
| 422 | `{ "error": "deadline_in_the_past" }` — FR-02 |
| 422 | `{ "error": "deadline_after_event_start" }` |

After a successful publication the server creates one `notification` row
(`kind = 'event_published'`) for every subscriber and sends the push in a background task, so
the response does not wait for FCM (FR-01). Rows are inserted with
`ON CONFLICT (student_id, event_id, kind) DO NOTHING`: a retried request never notifies anyone
twice. `sent_at` is set when FCM accepts the message.

**Push payload.** FCM message with a `notification` block (title = event title, body =
community name and deadline) and `data: { "type": "event_published", "event_id": "17" }`.
The app opens `GET /events/{event_id}` when the notification is tapped. Android channel id:
`events_high` (high importance, so it vibrates on a phone in silent mode).
iPhone: `apns.payload.aps.sound = "default"`, so the alert is not delivered silently.

## POST /events/{id}/registrations

Registers the authenticated student. Implements FR-03. No request body.

| Code | Body |
|---|---|
| 201 | `{ "status": "confirmed", "registration_id": 42 }` |
| 200 | `{ "status": "waiting_list", "position": 3 }` |
| 404 | `{ "error": "event_not_found" }` |
| 409 | `{ "error": "already_registered" }` — status is already `confirmed` or `waiting_list` |
| 410 | `{ "error": "deadline_passed" }` |

The response carries no `free_places`; the client re-fetches the event afterwards.

Server logic:

```
BEGIN;
  SELECT participant_limit, registration_deadline, status
    FROM event WHERE event_id = :id FOR UPDATE;        -- lock the event row

  IF NOT FOUND OR status <> 'published' THEN ROLLBACK; RETURN 404;
  IF registration_deadline <= NOW()     THEN ROLLBACK; RETURN 410;

  SELECT registration_id, status INTO mine FROM registration
    WHERE event_id = :id AND student_id = :student;
  IF mine.status IN ('confirmed', 'waiting_list') THEN ROLLBACK; RETURN 409;

  SELECT COUNT(*) INTO taken FROM registration
    WHERE event_id = :id AND status = 'confirmed';

  new_status := CASE WHEN taken >= participant_limit
                     THEN 'waiting_list' ELSE 'confirmed' END;

  IF mine IS NULL THEN
    INSERT INTO registration (student_id, event_id, status, created_at, updated_at)
      VALUES (:student, :id, new_status, clock_timestamp(), clock_timestamp());
  ELSE                                                  -- registered before, then cancelled
    UPDATE registration SET status = new_status, updated_at = clock_timestamp()
      WHERE registration_id = mine.registration_id;     -- never a second row
  END IF;
COMMIT;
```

**Why the row lock.** Without `FOR UPDATE`, two students pressing "Register" in the same
second both read `taken = 29` against a limit of 30, both pass the check and both are
confirmed — the event is overbooked and FR-03 is violated even though the code looks
correct. The lock makes the second transaction wait until the first one has committed.
A check in the user interface cannot solve this at all, and can additionally be bypassed by
any modified client.

**Why `clock_timestamp()` and not `NOW()`.** `NOW()` is the time the transaction *started*.
A student who waited for the lock started earlier than the one who got it first, so with
`NOW()` both would read the same waiting-list position. `clock_timestamp()` is the moment of
the write, which happens under the lock. Found by the race test (`server/tests/test_race.py`).

**Why UPDATE on re-registration.** Cancelling keeps the row with `status = 'cancelled'`, so a
second `INSERT` would hit `uq_registration`. The constraint stays: it is what guarantees one
row per student and event.

## DELETE /events/{id}/registrations

Cancels the student's own registration (`confirmed` or `waiting_list` → `cancelled`). No
request body. Runs in one transaction with the same `FOR UPDATE` lock on the event row.

When a **confirmed** place is freed, the first `waiting_list` row (ordered by `updated_at`,
then `registration_id`) is promoted to `confirmed` in the same transaction, and that student
gets a `notification` row with `kind = 'waiting_list_promoted'` and a push with
`data: { "type": "waiting_list_promoted", "event_id": "17" }`. If that student was promoted
for this event before, the existing row is reused (`ON CONFLICT ... DO UPDATE SET
sent_at = NULL, is_read = FALSE`).

| Code | Body |
|---|---|
| 200 | `{ "status": "cancelled" }` |
| 404 | `{ "error": "event_not_found" }` |
| 404 | `{ "error": "not_registered" }` — no active registration for this student |
| 410 | `{ "error": "event_started" }` — cancelling after `starts_at` is not allowed |

The body does not say who was promoted: that is another student's data. The client
re-fetches the event.

## PUT /me/device-token

Stores the FCM registration token of the student's phone (FR-01). The app calls it after
every login and whenever FCM rotates the token.

```json
{ "token": "<fcm registration token>", "platform": "android" }
```

`platform` is `android` (default), `ios` or `web`. The token is unique: if it is already
stored for another student (same phone, different account), it is moved to the caller. A
student may have several tokens (several devices).

| Code | Body |
|---|---|
| 204 | — |
| 422 | `{ "error": "validation_failed", ... }` — empty token or unknown platform |

## DELETE /me/device-token

Removes the token on logout, so a logged-out phone stops receiving pushes for that account.

```json
{ "token": "<fcm registration token>" }
```

| Code | Body |
|---|---|
| 204 | — also when the token was not stored, so logout never fails on it |

The server also deletes a token itself when FCM reports it as unregistered or invalid.

## Still to design

- editing an already published event: which changes re-notify the subscribers?
- cancelling an event: notify everyone who registered;
- moderator endpoints (confirming a community, blocking a user);
- subscribe / unsubscribe endpoints (roadmap M7; for the demo, subscriptions come from the seed).
