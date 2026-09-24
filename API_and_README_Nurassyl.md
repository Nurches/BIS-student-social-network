# Development artifacts — Application & Development (Turarbek Nurassyl, 24B032077)

Copy the two blocks below into the team GitHub repository as `README.md` and `docs/api.md`.
The link to that commit is the Evidence for Lab 04.

---

## FILE 1 — `README.md`

```markdown
# Student Social Network

A single place where a student sees the university event announcements that concern them,
while there is still time to register.

## Problem
Our university has no fixed academic groups: every student takes a different combination
of courses and therefore belongs to a different set of chats each semester. Announcements
about clubs, olympiads and career days are spread over WhatsApp, Telegram, Instagram and
paper noticeboards, and no single chat covers all of them. A first-year student usually
sees an announcement after the registration deadline has passed, or registers for an event
where no places are left.

## What the system does
- a student subscribes to communities (clubs, career center, faculty offices);
- a confirmed community admin publishes an event with a deadline and a participant limit;
- every subscriber gets a push notification and sees the event in a personal feed;
- registration is closed automatically when the limit is reached; the rest go to a waiting list.

## Team
| Name | Student ID | Area |
|---|---|---|
| Ualikhan Gulnazym | | Systems Analysis & Requirements |
| Taubay Laila | | Data & Database |
| Turarbek Nurassyl | 24B032077 | Application & Development |
| Nurkasymova Akbota | | Architecture & Security |
| Shpanova Madina | | Testing, Analytics & Integration |

## Tech stack
| Layer | Technology |
|---|---|
| Mobile client | Flutter (Android, iOS) |
| Push notifications | Firebase Cloud Messaging |
| Server | FastAPI (Python 3.12) |
| Database | PostgreSQL 16 |
| Auth | JWT access token, bcrypt cost 12 |

## Repository structure
```
/docs      requirements, ER diagram, API specification, test cases
/server    FastAPI application
/client    Flutter application
```

## How to run the server
```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # set DATABASE_URL and JWT_SECRET
psql "$DATABASE_URL" -f ../docs/schema.sql
uvicorn app.main:app --reload
```
Interactive API documentation: http://localhost:8000/docs

## Requirements implemented
| ID | Requirement | Where it is enforced |
|---|---|---|
| FR-01 | Notify subscribers when an event is published | `services/notifications.py` |
| FR-02 | Reject an announcement with a past deadline | `POST /communities/{id}/events` |
| FR-03 | Reject registration over the limit, offer the waiting list | `POST /events/{id}/registrations` |
| NFR-01 | 95% of feed loads under 2 s at 1000 users | feed query + indexes |
| NFR-02 | bcrypt cost 12, lockout after 5 failed logins | `services/auth.py` |
| BR-01 | University email only; confirmed admins publish | registration and role check |
```

---

## FILE 2 — `docs/api.md`

```markdown
# API v0.1

Base URL `/api/v1` · JSON only · every endpoint except `/auth/*` needs
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

## GET /feed?limit=20&cursor=<event_id>
Published events from the communities the student follows, whose registration deadline
has not passed, ordered by deadline. Target: 95% of calls under 2 seconds with 1000
concurrent users (NFR-01). Pagination is cursor-based, not OFFSET, because OFFSET gets
slower on every next page.

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
A check in the user interface cannot solve this at all, and can additionally be bypassed
by any modified client.

## DELETE /events/{id}/registrations
Cancels the student's own registration. When a confirmed place is freed, the oldest
`waiting_list` row for that event is promoted to `confirmed` inside the same transaction
and that student is notified.

## Still to design (next weeks)
- editing an already published event: which changes re-notify the subscribers?
- cancelling an event: notify everyone who registered;
- moderator endpoints (confirming a community, blocking a user) — agreed with Akbota.
```

---

### Minimum for this week
Create the repository, commit these two files plus `docs/schema.sql` from Laila, and add
the other four as collaborators. Even with no application code yet, that is a real
artifact you can link in the Evidence field.
