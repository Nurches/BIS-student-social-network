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
/server    FastAPI application
/client    Flutter application
```

| File | Content |
|---|---|
| `docs/requirements.md` | stakeholder, problem, FR / NFR / business rule, acceptance criteria, RTM |
| `docs/ER_diagram.png` | entity-relationship diagram of the database |
| `docs/schema.sql` | PostgreSQL schema with indexes, test data and the main queries |
| `docs/api.md` | API specification |
| `docs/roles_and_architecture.xlsx` | role matrix, architecture components, security decisions |
| `docs/test_cases_and_rtm.xlsx` | test cases, traceability matrix, analytics metrics |

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

## Requirements and where they are enforced

| ID | Requirement | Enforced in |
|---|---|---|
| FR-01 | Notify subscribers when an event is published | `services/notifications.py` |
| FR-02 | Reject an announcement with a past deadline | `POST /communities/{id}/events` |
| FR-03 | Reject registration over the limit, offer the waiting list | `POST /events/{id}/registrations` |
| NFR-01 | 95% of feed loads under 2 s at 1000 concurrent users | feed query + indexes |
| NFR-02 | bcrypt cost 12, lockout after 5 failed logins | `services/auth.py` |
| BR-01 | University email only; confirmed admins publish | registration and role check |

## Status

Week 4 — requirements and design. Implementation starts in Week 5.
