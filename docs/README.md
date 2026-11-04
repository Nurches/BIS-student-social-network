# Student Social Network

A single place where a student sees the university event announcements that concern them,
while there is still time to register.

## Problem

Our university has no fixed academic groups: every student takes a different combination of
courses and therefore belongs to a different set of chats each semester. Announcements about
clubs, olympiads and career days are spread over WhatsApp, Telegram, Instagram and paper
noticeboards, and no single chat covers all of them. A first-year student usually sees an
announcement after the registration deadline has passed, or registers for an event where no
places are left.

## What the system does

- a student subscribes to communities (clubs, career center, faculty offices);
- a confirmed community admin publishes an event with a deadline and a participant limit;
- every subscriber gets a push notification and sees the event in a personal feed;
- registration closes automatically when the limit is reached; the rest go to a waiting list.

## Team

| Name | Student ID | Area |
|---|---|---|
| Ualikhan Gulnazym | 24B032093 | Systems Analysis & Requirements |
| Taubay Laila | 24B032051 | Data & Database |
| Turarbek Nurassyl | 24B032077 | Application & Development |
| Nurkasymova Akbota | 24B031933 | Architecture & Security |
| Shpanova Madina | 24B032120 | Testing, Analytics & Integration |

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
/docs      requirements, ER diagram, database schema, API specification, test cases
/server    FastAPI application (server/README.md)
/qatys     Flutter application (qatys/README.md)
```

| File | Content |
|---|---|
| `docs/requirements.md` | stakeholder, problem, FR / NFR / business rule, acceptance criteria, RTM |
| `docs/ER_diagram.png` | entity-relationship diagram of the database |
| `docs/schema.sql` | PostgreSQL schema with indexes, test data and the main queries |
| `docs/api.md` | API specification |
| `docs/roles_and_architecture.xlsx` | role matrix, architecture components, security decisions |
| `docs/test_cases_and_rtm.xlsx` | test cases, traceability matrix, analytics metrics |
| `docs/migrations/` | upgrades of an existing database (002: contract fixes) |
| `docs/roadmap.md` | plan to the Week 15 defence |
| `docs/project-status.md` | where the project is now, milestone log |
| `docs/deployment.md` | run the whole system from zero, deploy to Render + Neon |
| `docs/network-map.md` | phone → API → database, the push path, failures |
| `docs/tools/` | specifications of team tools (data checks page) |
| `docs/team/` | per-member notes (`laila.md`: data checks) |
| `server/app/checks/data_checks.sql` | data integrity checks run by the `/data-checks` page (owner: Data & Database) |

## How to run the server

```bash
cd server
docker compose up -d db                       # PostgreSQL 16 on localhost:5432
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env && python seed.py --yes  # tables + demo data
uvicorn app.main:app --reload
```

Interactive API documentation: http://localhost:8000/docs · admin page: http://localhost:8000/admin ·
data checks: http://localhost:8000/data-checks.
Details, tests and deployment: `server/README.md`, `docs/deployment.md`.

## Requirements and where they are enforced

| ID | Requirement | Enforced in |
|---|---|---|
| FR-01 | Notify subscribers when an event is published | `server/app/services/events.py` (`create_publish_notifications`), `services/push.py`; app: `qatys/lib/features/push/` |
| FR-02 | Reject an announcement with a past deadline | `services/events.py` (`publish`); app renders a passed deadline as closed |
| FR-03 | Reject registration over the limit, offer the waiting list | `services/events.py` (`register`, `SELECT ... FOR UPDATE`) |
| NFR-01 | 95% of feed loads under 2 s at 1000 concurrent users | one-query feed + keyset cursor + `idx_event_feed`; app: cache-first feed; `server/loadtest/` |
| NFR-02 | bcrypt cost 12, lockout after 5 failed logins | `services/auth.py` |
| BR-01 | University email only; confirmed admins publish | `services/auth.py`, `services/events.py` (`publish`) |

## Status

Week 10 — the main process works end to end on a real server and database (milestones
M0–M6 of `docs/roadmap.md` implemented). See `docs/project-status.md`.
