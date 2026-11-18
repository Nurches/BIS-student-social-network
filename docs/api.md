# API v0.2 (+ Week 12, schema v4)

Base URL `/api/v1` · JSON only · every endpoint except `/health` and `/auth/*` requires
`Authorization: Bearer <token>`.

All business rules are enforced on the server. The client never decides whether a
registration is allowed — it only displays the answer.

**v0.2 (2026-11-03, roadmap M0):** added `GET /health`, `GET /events/{id}`,
`PUT|DELETE /me/device-token`, every response body, the Event object, the feed envelope and
cursor, the lockout rule and the error format. Database changes are in
`docs/migrations/002_contract_fixes.sql`.

**Week 11 (2026-11-10):** error responses are documented in Swagger for every endpoint (D-01);
`password_too_long` (422 on register) was raised by the server but missing here, now listed.
Schema v3 (`docs/migrations/003_soft_delete_and_faculty.sql`): `faculty` is a code, an
unknown one answers `422 unknown_faculty`; **soft delete** — a student, community or event
with `deleted_at` set is invisible to the API: not in the feed, `404` for its event page,
registration and publishing, `401` for its login and tokens, no notifications. There is no
delete endpoint yet (`TODO(confirm)`).

**Week 12 (2026-11-17), schema v4** (`docs/migrations/004_community_requests_and_event_changes.sql`):
any student **requests a community** (`POST /communities`, `GET /me/community-requests`), a
moderator approves or rejects it in the admin panel (approval pushes `community_approved`);
**cancelling or moving an event** pushes `event_cancelled` / `event_rescheduled` to every
confirmed or waiting student; the Event object gains `status`, `previous_starts_at`,
`cancelled_at`; a cancelled event stays readable; **announcement cards** for the home screen
(`GET /events/announcements`). A client older than this version cannot read an inbox with a
`community_approved` row (`event_id` is `null` there): ship the new app build with it.

## Conventions

**Errors.** Every error response has the body `{ "error": "<code>" }`, where `<code>` is a
stable `snake_case` string the client can switch on. Extra fields are allowed (for example
`retry_after_minutes`). Request validation failures (missing field, wrong type, limit out of
range) are `422 { "error": "validation_failed", "detail": [...] }`.

| Code | Error | When |
|---|---|---|
| 401 | `unauthorized` | Token missing, malformed, wrong signature or expired |
| 403 | `not_a_confirmed_admin`, `not_allowed` | BR-01 publishing; the data checks allow list |
| 404 | `<entity>_not_found`, `not_registered` | The resource does not exist or the student may not see it |
| 409 | `email_already_registered`, `already_registered` | The thing already exists |
| 410 | `deadline_passed`, `event_started` | Too late for this action |
| 413 | `payload_too_large` | Body over 64 KB, rejected before parsing |
| 422 | `validation_failed` | The body, path or query does not match this document |
| 423 | `account_locked` | NFR-02 lockout, with `retry_after_minutes` and header `Retry-After` |
| 429 | `too_many_requests` | `POST /auth/login`: more than 20 attempts per minute from one IP; `/admin/data-checks`: second run within 10 s; header `Retry-After` |
| 500 | `internal_error` | Never with a stack trace |

**Swagger (`/docs`) shows the same.** Every endpoint lists the errors it can really return,
with one example body each. The list lives in `server/app/errors.py` (`ERRORS`), and
`server/tests/test_openapi_errors.py` follows each route through the code to every
`ApiError` it can reach and fails if Swagger lists one code more or one code less (D-01,
Week 11). The validation error appears in our format, not FastAPI's default
`{"detail": [...]}`:

```json
{ "error": "validation_failed",
  "detail": [ { "loc": ["body", "title"], "msg": "Field required", "type": "missing" } ] }
```

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

`faculty` and `enrolled_year` are optional. `faculty` is a **code** of the `faculty` table
(schema v3): `SITE`, `BS`, `ISE`, `IT`, `Student Union`; matched without regard to case
(`TODO(confirm)`). The email is trimmed and lower-cased before any check. The password is
stored as a bcrypt hash with cost 12 (NFR-02).

| Code | Body |
|---|---|
| 201 | `{ "student_id": 12, "email": "student@kbtu.kz", "full_name": "Aru Sadykova" }` |
| 422 | `{ "error": "not_a_university_email" }` — BR-01 |
| 422 | `{ "error": "password_too_short" }` — under 8 characters |
| 422 | `{ "error": "password_too_long" }` — over 72 bytes (bcrypt reads only 72; refused instead of silently cut) |
| 422 | `{ "error": "unknown_faculty" }` — `faculty` is not a code of the `faculty` table (`TODO(confirm)`) |
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
  "waiting_position": 3,
  "status": "published",
  "previous_starts_at": "2026-11-19T10:00:00+05:00",
  "cancelled_at": null
}
```

| Field | Rule |
|---|---|
| `description`, `location` | May be `null` |
| `free_places` | `participant_limit` minus confirmed registrations, never below 0 |
| `my_status` | `null` (not registered or cancelled), `"confirmed"` or `"waiting_list"` |
| `waiting_position` | 1-based place in the queue when `my_status = "waiting_list"`, otherwise `null` |
| `status` | v4: `"published"` or `"cancelled"` (a cancelled event is shown only by `GET /events/{id}` and `GET /me/registrations`) |
| `previous_starts_at` | v4: the start before the organiser last moved the event; `null` if never moved |
| `cancelled_at` | v4: when the event was cancelled, otherwise `null` |

The queue is ordered by `registration.updated_at`, then `registration_id`: the moment the
student joined the waiting list, not when they first registered for the event.

## GET /events/{id}

One Event object with fresh `free_places` and `my_status`. The detail screen calls it every
time it opens, because the feed copy may be stale.

Any authenticated student can open any **published** event, including one from a community
they do not follow (a link from a friend) and one whose deadline has passed (the app shows it
as closed, FR-02). v4: a **cancelled** event answers `200` with `status: "cancelled"`, so a
student who opens the cancellation push sees what happened. Registering for it or cancelling
a place in it answers `409 { "error": "event_cancelled" }`.

| Code | Body |
|---|---|
| 200 | Event object |
| 404 | `{ "error": "event_not_found" }` — no such event, or it is a `draft` |

## GET /events/announcements

Week 12: `{ "items": [Event, …] }` for the cards on top of the home screen — published events
of **every confirmed community, followed or not**, whose deadline has not passed, soonest
deadline first, at most 10. The feed below the cards stays "communities I follow".

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

## Communities and the student's own lists (MVP extension, Week 11)

Added on 11 November 2026 so the app can be used without help: a new student finds
communities and follows them, sees their own registrations and an inbox of every
notification. All need the token; errors as in "Conventions" (Swagger lists them).

### GET /communities

Confirmed communities, plus the caller's own pending request (v4), ordered by name. Another
student's pending or rejected request is not listed.

```json
[ { "community_id": 4, "name": "Sports Club", "description": "Futsal, volleyball and …",
    "is_confirmed": true, "status": "confirmed", "is_mine": false,
    "subscriber_count": 56, "upcoming_events": 1, "is_subscribed": false } ]
```

`status`: `pending` | `confirmed` | `rejected`; `is_confirmed` = `status == "confirmed"` (kept
for older readers): only a confirmed community publishes (BR-01) and can be followed (else
`404 community_not_found`). `upcoming_events`: published, deadline not passed.

### POST /communities (Week 12)

Any student asks the Student Union for a new community; the caller becomes its owner.

```json
{ "name": "Chess Club", "description": "Blitz on Fridays" }
```

| Code | Body |
|---|---|
| 201 | `{ "community_id", "name", "description", "status": "pending", "reject_reason": null, "created_at", "reviewed_at": null }` |
| 409 | `{ "error": "community_name_taken" }` — a pending or confirmed community has this name, ignoring case (a rejected name is free) |
| 409 | `{ "error": "too_many_pending_requests" }` — 3 requests of this student already wait |
| 422 | `validation_failed` — name shorter than 3 or longer than 120 characters |

A pending community publishes nothing and gives its owner no admin panel. After approval the
owner gets the `community_approved` push and publishes in `/admin`.

### GET /me/community-requests (Week 12)

`{ "items": [same object as above, …], "pending_limit": 3 }` — every community the student
asked for (or owns), newest first, with `status`, `reject_reason` and `reviewed_at`.

### PUT | DELETE /communities/{id}/subscription

Follow / unfollow. Both are idempotent and answer `204`. Following adds the community's events
to `GET /feed` and its future pushes (FR-01); unfollowing does not touch existing
registrations. `404 { "error": "community_not_found" }`.

### GET /communities/{id}/events

`{ "items": [Event, …] }` — published events of the community whose deadline has not passed,
ordered by deadline, at most 50; also for a student who does not follow it. `404
community_not_found`.

### GET /me/registrations

`{ "items": [Event, …] }` — events the student is `confirmed` for or on the `waiting_list` of,
past ones included (the app splits "Upcoming" and "Past"). Cancelled rows are not listed.
v4: an event the organiser cancelled stays here with `status: "cancelled"`.

### GET /me/notifications · POST /me/notifications/read

The in-app inbox: the same `notification` rows the pushes were sent for, so a missed push
(silent phone, no network) is not lost. Newest first, at most 50, only published events —
plus, in v4, `event_cancelled` rows of cancelled events and `community_approved` rows.

```json
{ "items": [ { "notification_id": 31, "kind": "event_rescheduled", "event_id": 7,
               "community_id": 4, "event_title": "Futsal cup", "community_name": "Sports Club",
               "starts_at": "2026-11-22T17:00:00+05:00",
               "previous_starts_at": "2026-11-20T17:00:00+05:00",
               "created_at": "2026-11-11T08:00:00+00:00", "is_read": false } ],
  "unread_count": 1 }
```

`kind`: `event_published` | `waiting_list_promoted` | `event_cancelled` | `event_rescheduled` |
`community_approved`. For `community_approved` `event_id`, `event_title`, `starts_at` are
`null`. Push `data`: `{ "type": <kind>, "event_id": "7" }`, or `{ "type":
"community_approved", "community_id": "9" }`.

`POST /me/notifications/read` marks all of the student's notifications read; `204`.

## Admin panel (`/admin`, 11 November 2026)

The page `/admin` and the endpoints under `/admin/...` behind it. Every call needs the token.
Two kinds of admin, read from the database on every request:

* **Moderator** of the Student Union (`student.is_moderator`, seed: `union@kbtu.kz`) — sees
  and manages everything: creates communities, chooses their owner, confirms them (BR-01),
  manages students.
* **Community owner** (`community.owner_id`) of a **confirmed** community (v4) — sees only
  the communities they own and their events. A pending request gives no admin access.

Anyone else: `403 { "error": "not_an_admin" }`. Publishing stays
`POST /communities/{id}/events` above, so BR-01 is checked in one place. Errors of every
endpoint are listed in Swagger (tag *admin panel*). Week 12 adds the review of community requests (schema v4).

| Endpoint | Who | What |
|---|---|---|
| `GET /admin/me` | admin | Account, `is_moderator`, owned communities |
| `GET /admin/overview` | admin | Counts over the caller's scope; `students` and `devices` only for a moderator (else `null`) |
| `GET /admin/communities?status=` | admin | Communities with owner, `status`, `reject_reason`, `reviewed_at`, `subscriber_count`, `published_events`, `open_events`; `?status=pending` = the requests |
| `POST /admin/communities/{id}/approve` | moderator | Week 12: `pending` → `confirmed`; the owner gets the `community_approved` push → `{ "community", "notified": 1 }`; `409 community_not_pending`, `403 cannot_review_own_request` |
| `POST /admin/communities/{id}/reject` | moderator | Week 12: `{ "reason"? }` (≤ 300, shown to the student) → `rejected`, no push, the name is free again; same errors |
| `POST /admin/communities` | moderator | `{ "name", "description"?, "owner_email", "is_confirmed": true }` → `201`; `404 student_not_found`, `409 community_name_taken` |
| `PATCH /admin/communities/{id}` | moderator | Any of `name`, `description` (`null` clears), `owner_email`, `is_confirmed` (`true` on an unconfirmed one = approval with push; `false` = back to `pending`) |
| `GET /admin/events?community_id=` | admin | Every status, past included, newest deadline first, at most 300; `state` = `open \| closed \| finished \| cancelled \| draft`, `confirmed_count`, `waiting_count`, `notified_count`, `sent_count` |
| `PATCH /admin/events/{id}` | owner / moderator | Any of `title`, `description`, `location`, `starts_at`, `registration_deadline`, `participant_limit` → `{ "event", "promoted", "rescheduled_notified" }` |
| `POST /admin/events/{id}/cancel` | owner / moderator | `status = 'cancelled'`, `cancelled_at`; every confirmed or waiting student gets `event_cancelled` → `{ "event", "notified" }`; `409 event_cancelled` the second time, `410 event_started` once it has started |
| `POST /admin/events/{id}/notify` | owner / moderator | Notifies followers who joined after publication and resends pushes FCM has not accepted → `{ "new_recipients", "queued" }` |
| `GET /admin/events/{id}/registrations` | owner / moderator | `{ "event", "items" }`: confirmed, then the waiting list with `position`, then cancelled |
| `GET /admin/notifications?event_id=` | admin | Delivery log, newest first, at most 200: `sent_at` (`null` = not accepted by FCM), the student's `devices` now |
| `POST /admin/push-test` | admin | One push (`data.type = "test"`) to every phone of the caller's own account, at once → `{ "fcm_configured", "devices", "sent", "failed", "removed" }` |
| `GET /admin/students?q=` | moderator | Students with `is_moderator`, `is_locked`, counts; `q` matches email or name; at most 300 |
| `PUT /admin/students/{id}/moderator` | moderator | `{ "is_moderator": bool }` → `204`; `409 cannot_change_own_role` |
| `POST /admin/students/{id}/unlock` | moderator | Lifts the NFR-02 lockout → `204` |

Rules of `PATCH /admin/events/{id}`:

* a cancelled event cannot be changed: `409 event_cancelled`;
* a **moved** deadline must be in the future (`422 deadline_in_the_past`, FR-02) and the
  deadline is never after the start (`422 deadline_after_event_start`);
* the limit cannot go below the confirmed count: `409 limit_below_confirmed` (nobody loses a
  place);
* a **larger** limit moves students up from the waiting list in queue order at once; each gets
  the `waiting_list_promoted` notification and push, as after a cancellation (FR-03).

* v4: a new `starts_at` is a **reschedule**: it must be in the future (`422
  start_in_the_past`), the old start is kept in `previous_starts_at`, and every confirmed or
  waiting student gets the `event_rescheduled` push (a second move re-sends the same
  notification row).

Other edits do not re-notify the followers. Cancelling removes the event from the feed and
the announcements and keeps the registrations; the registered students get the push, and the
event page and "My events" show it as cancelled.

## Tools (not part of the product)

Used by the team, not by the app. Full specification: `docs/tools/data-checks-spec.md`.

### GET /admin/data-checks

Runs every check of `server/app/checks/data_checks.sql` (owned by the Data & Database member)
against the database and returns the result. Page: `/data-checks`.

* **Access:** the JWT from `POST /auth/login`, and the student's email must be in the
  `DATA_CHECK_EMAILS` allow list.
* **Read only:** one `READ ONLY` transaction, `statement_timeout` 3 s per statement, rolled
  back at the end. Only the checks in the file run. There is no SQL from the request.
* **Rate limit:** one run per 10 s per student.

A check **passes** when its SELECT returns 0 rows, **fails** with 1 or more rows, and is an
**error** on an SQL error, a timeout or a broken block in the file.

```json
{
  "ran_at": "2026-11-10T09:14:03+00:00",
  "database": "neon / qatys",
  "duration_ms": 412,
  "summary": { "total": 9, "passed": 8, "failed": 1, "errors": 0 },
  "checks": [
    {
      "id": "C07",
      "title": "Nobody waits while free places exist",
      "requirement": "FR-03",
      "note": "If this returns rows, a cancellation did not promote the waiting list.",
      "status": "fail",
      "row_count": 1,
      "truncated": false,
      "columns": ["event_id", "title", "participant_limit", "confirmed", "waiting"],
      "rows": [[2, "IT Career Day", 200, 1, 1]],
      "duration_ms": 18,
      "error": null
    }
  ]
}
```

`status` is `pass | fail | error`. `rows` holds at most 20 rows; `truncated` is `true` when
`row_count` is larger. For a check marked `@sensitive true`, `columns` and `rows` are always
empty, and only `row_count` is given. `row_count` is `null` for an error, and `error` holds
the PostgreSQL message or the file-format problem. `database` is the host alias and the
database name, never the user or the password. Timestamps in `rows` are ISO 8601 with an offset.

| Code | Body |
|---|---|
| 200 | the report above |
| 401 | `{ "error": "unauthorized" }` |
| 403 | `{ "error": "not_allowed" }` — not on the allow list; nothing runs |
| 429 | `{ "error": "too_many_requests" }` — second run within 10 s; header `Retry-After` |

## Still to design

- editing an already published event: which changes re-notify the subscribers? (now: none;
  only students promoted by a larger limit get a push);
- ~~cancelling an event: notify everyone who registered~~ — done (Week 12, schema v4);
- ~~moderator endpoints (confirming a community)~~ — done (admin panel); blocking a user is
  the soft delete of schema v3;
- ~~subscribe / unsubscribe endpoints~~ — done (MVP extension, see above).
