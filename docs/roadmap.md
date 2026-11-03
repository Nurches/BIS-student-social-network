# Roadmap to Week 15 — Qatys (BIS Student Social Network)

**Date:** 3 November 2026 (Week 10)
**Owner:** Nurassyl Turarbek (Application & Development)
**Reads with:** `docs/project-status.md` (where we are), `FLUTTER_BRIEF.md` (client spec), `docs/api.md`, `docs/schema.sql`, `docs/requirements.md`
**Audience:** the coding agent that implements this plan, and the team

---

## 0. How the agent should use this file

1. Work on **one milestone at a time**, in the order of section 4. Do not start the next milestone until the current one meets its acceptance criteria and the owner has checked it.
2. Each milestone ends with: all tests green, `flutter analyze` clean (client) / `ruff` + `pytest` clean (server), a short entry in `docs/project-status.md`, and small dated commits.
3. If this file conflicts with `FLUTTER_BRIEF.md`, this file wins for **priority and scope**; the brief wins for **client details** (screens, UI constraints, failure modes).
4. Product decisions are fixed in section 3. Do not reopen them in code. If something is genuinely undecided, implement the stated default and leave `// TODO(confirm):` or `# TODO(confirm):`.
5. Everything in the repo stays in English. Do not rename files listed in `FLUTTER_BRIEF.md` §12.

---

## 1. Goal

By **Week 15** the team demonstrates a working information system for the end-term defence. One user process must work **from start to finish on real data**, not on mocks:

> A confirmed community admin publishes an event → every subscriber gets a push notification → a student taps it, opens the event, and registers (or joins the waiting list) while the deadline is open → the data is stored in PostgreSQL and the free places update.

What "finished" means for the course (from the instructor's brief), and how we prove each point:

| Course criterion | How Qatys proves it |
|---|---|
| Solves the agreed problem | One feed instead of 5+ chats, push at publication time |
| Main process works end to end | Live demo of the process above, on the deployed server |
| Data is created, stored, changed, used correctly | Registration rows, waiting list promotion, notification rows, visible in DB |
| User roles and access rules are clear | Student vs confirmed admin; 403 for non-admin publish |
| Main process and error cases are tested | pytest + Flutter tests mapped to TC-01…TC-08 in the RTM |
| Stable demo | Deployed server, warm-up step, mock fallback only as a last resort |
| Limitations and improvements explained | Section 8 of this file, kept current |
| Every member can prove their contribution | Section 6 — each member owns a checkable artifact |

**Important:** the mock-data mode is a safety net, not the demo. The grade depends on a real system: real server, real database, real push.

---

## 2. Current state (summary of `project-status.md`)

- Client steps 1–3 done: architecture, data layer with mock + HTTP, login with lockout display. 46 tests pass.
- **Backend not started.** This is the critical path. Push (FR-01) and every real demo depend on it.
- Known contract gaps and bugs: device token storage, missing endpoints/bodies, re-registration hits `uq_registration`, feed cursor bug, timestamps without time zone.
- Two items the team promised for Week 10 in Task 09 are still open: **race test for the last place** and **duplicate notifications**. They are scheduled in M1/M3 below and must be shown at the next check.

---

## 3. Product decisions (fixed)

| Question | Decision | Why |
|---|---|---|
| Demo platform | **Android APK** is primary. Flutter Web only if it costs under half a day; push is not required on Web. | Target user is a student with a cheap Android phone; FCM on Android is the simplest path. |
| Admin publishing | **No admin screen in the app.** Admin publishes through the server's Swagger UI (`/docs`) or a one-file seed/publish script. A tiny HTML admin page is a stretch goal (M7). | Admin side is out of the client scope; Swagger is free, visible and demonstrates the API. |
| Lockout rule | Attempts 1–5 with a wrong password return **401**. The **5th** failure within 10 minutes sets `locked_until = now() + 15 min`. Any login during the lock returns **423** with `retry_after_minutes`, even with the correct password. A successful login resets the counter. | Matches NFR-02 wording "lock after 5 failed attempts". Test cases and requirements must be updated to say the same. |
| Re-registration after cancel | Server **updates the existing row** (`cancelled → confirmed/waiting_list`), never inserts a second one. | Fixes the `uq_registration` bug without dropping the constraint. |
| Feed pagination | Keyset cursor on `(registration_deadline, event_id)`, encoded as an opaque string. | Fixes skipped/repeated events. |
| Time | Columns become `TIMESTAMPTZ`; API returns ISO 8601 with offset; server runs in UTC; seed data uses `+05:00`. | Correct deadlines on any phone. |
| Hosting | FastAPI on **Render** (free web service), PostgreSQL on **Neon** or Render Postgres. | Free, enough for a demo. Free tier sleeps, so the demo checklist includes a warm-up. |
| State management | Riverpod (already in use). | Already decided in code. |

Out of scope until after Week 15: chat, comments, reactions, profile editing, friends, event editing/cancelling flows, moderator endpoints, iOS push, email verification sending (account creation can mark email as verified for the demo — leave `TODO(confirm)`).

---

## 4. Milestones

Each milestone has an owner (always Nurassyl + agent for code), a target practical lesson, and acceptance criteria that can be demonstrated in class.

### M0 — Contract fix (start now, before any server code) — target: Week 10 lesson

Update `docs/api.md` and add `docs/migrations/002_contract_fixes.sql` (keep `schema.sql` runnable as before, and apply the same changes there).

- Add `device_token` table: `device_token_id`, `student_id` FK, `token` (unique), `platform`, `updated_at`.
- Add `UNIQUE (student_id, event_id)` on `notification` — this is the **duplicate notification** fix promised for Week 10.
- Convert all `TIMESTAMP` columns to `TIMESTAMPTZ`.
- Document in `api.md`: `GET /health`, `GET /events/{id}`, `PUT /me/device-token`, login 200 body, login 423 body with `retry_after_minutes`, feed envelope `{ items, next_cursor }`, the Event object, `DELETE` registration response, the cursor format, error body format `{ "error": "<code>" }`.
- Update `FLUTTER_BRIEF.md` §5: remove "TO CONFIRM" for everything now defined.

**Accepted when:** `api.md` has no "TO CONFIRM" for the core process; `schema.sql` runs clean in a fresh PostgreSQL 16; inserting the same notification twice fails with the unique constraint.

### M1 — Server skeleton, auth, deploy — target: Week 11 lesson

Create `server/` (Python 3.12, FastAPI, SQLAlchemy 2 or plain `psycopg` 3, pydantic settings, pytest).

```
server/
  app/main.py, config.py, db.py
  app/routers/{health,auth,feed,events,registrations,devices,admin}.py
  app/services/   # business rules live here, not in routers
  tests/
  seed.py         # demo data: 3 communities, 6 events, 10 students, 1 confirmed admin
  requirements.txt, Dockerfile, docker-compose.yml (postgres for local + tests)
  README.md       # how to run locally in 5 commands
```

- `GET /health` → `200 {"status":"ok"}`, also checks the DB connection.
- `POST /auth/register` (BR-01: `@kbtu.kz` only → 422; duplicate → 409), bcrypt cost 12.
- `POST /auth/login` with JWT (24 h) and the lockout rule from section 3.
- Auth dependency: missing/invalid token → 401 `{"error":"unauthorized"}`.
- Deploy to Render with the DB; seed it.
- **Race test** (promised for Week 10): pytest that fires two concurrent registrations for the last place against a real PostgreSQL (from docker-compose) and asserts exactly one `confirmed` and one `waiting_list`. It can be written now against the registration service even before the router exists.

**Accepted when:** the deployed `/health` returns 200; login from the Flutter app (`API_BASE_URL` set) works against the live server; lockout returns 423 on the 6th attempt; race test passes; Swagger UI is reachable.

**Demo at the lesson:** Swagger → register → login → token; app logs in against the live server; race test running in the terminal.

### M2 — Feed, live (server + client step 4) — target: Week 11 lesson (stretch) / Week 12

- Server `GET /feed`: published events from subscribed communities, deadline not passed, ordered by `(registration_deadline, event_id)`, keyset cursor, `free_places` and `my_status` computed in SQL in **one query** (no N+1).
- Client step 4 from the brief: cache-first feed, pull to refresh, empty state, card fields per brief §7.
- Server test: pagination over 45 seeded events returns every event exactly once.

**Accepted when:** the app shows the live feed from the deployed server; turning off the network shows the cached feed instantly; the pagination test passes.

### M3 — Event detail and registration end to end (server + client step 5) — target: Week 12 lesson

- Server `GET /events/{id}`, `POST /events/{id}/registrations` (transaction with `SELECT … FOR UPDATE`, re-registration via UPDATE), `DELETE /events/{id}/registrations` (promotes the oldest waiting-list row in the same transaction and creates a notification for that student).
- Admin `POST /communities/{id}/events`: FR-02 (deadline in the past → 422 `deadline_in_the_past`), deadline after start → 422, not a confirmed owner → 403 `not_a_confirmed_admin`.
- Client step 5: detail screen re-fetches on open, four button states, waiting list as a calm normal outcome, UI constraints from brief §8 (320 dp, 48 dp targets, action in the bottom third).
- Tests: TC-02, TC-03, register → cancel → register again (no DB error), cancel promotes the waiting list, a direct API call cannot overbook.

**Accepted when:** in class, one phone registers for the last place, a second account gets the waiting list, the first cancels, the second is promoted — and the rows are shown in the database.

### M4 — Push notifications (server + client step 6) — target: Week 13 lesson

- Human prerequisite (owner, not the agent): create the Firebase project, add the Android app, download `google-services.json`, create a service account key for the server. Keys go into Render environment variables, **never into git**.
- Client: request notification permission after the first login (Android 13+), send the token via `PUT /me/device-token` on login and on token refresh, high-importance channel, tap on the notification opens the event detail (cold start and background).
- Server: on successful publish, create one `notification` row per subscriber (unique constraint from M0 prevents duplicates) and send FCM in a background task; invalid tokens are deleted; `sent_at` is set on success.
- Tests: TC-01 (tap opens the right event), server test that publishing twice does not create duplicate notification rows, server test with FCM mocked.

**Accepted when:** admin publishes in Swagger → a real phone on silent mode vibrates within seconds → tap opens the new event → register. This is the core demo of the project.

### M5 — Reliability (client step 7) — target: Week 13–14

- Reachability = successful `GET /health`, not the connectivity flag (captive-portal Wi-Fi).
- Offline queue for registration taps; retry on next launch; reconcile with the server (server is always right about free places).
- Clear "No connection to the server" state; no infinite spinners; request timeouts.
- Logout clears secure storage completely.

**Accepted when:** each failure mode from brief §9 has a test or a documented manual check, and can be shown in class (airplane mode, server stopped).

### M6 — Quality, security, release (client step 8) — target: Week 14 lesson

- Security pass (input with Akbota's checklist, section 6): JWT secret from env, CORS restricted, request size limits, rate limit on `/auth/login`, no stack traces in production errors, passwords never logged.
- NFR-01 check: a small load test (`locust` or `k6`) on `/feed` with recorded p95; if 1000 concurrent users is unrealistic on the free tier, record the measured number honestly and explain the limitation.
- Signed release APK on GitHub Releases with the live `API_BASE_URL`.
- `docs/deployment.md`: run the whole system from zero on another computer (Laila or Akbota executes it as evidence).
- `docs/network-map.md` (Week 10 lecture, SIS 9): phone → HTTPS → FastAPI on Render → PostgreSQL; FCM path; one likely failure and what the user sees.

**Accepted when:** a team member who did not write the code installs the APK and completes the main process; RTM rows move to Pass with dates.

### M7 — Stretch, only if M0–M6 are done

In priority order: tiny HTML admin page for publishing; Flutter Web build; simple analytics (number of notifications sent vs registrations made); subscribe/unsubscribe screen.

### Week 15 — freeze and defence

- Code freeze 2 days before the defence. Only bug fixes after that.
- Rehearse the demo script (section 7) twice on the real phones that will be used.

---

## 5. Timeline at a glance

| Practical lesson | What we show | Milestones |
|---|---|---|
| Week 10 (now) | Login on mock, 46 tests, this plan, fixed API contract, network map draft | M0 |
| Week 11 | Live server: Swagger, login from the app, race test green | M1 (+ M2 stretch) |
| Week 12 | Live feed + register / waiting list / cancel with DB rows | M2, M3 |
| Week 13 | Real push → tap → register on a real phone | M4 (+ M5 start) |
| Week 14 | Offline handling, security pass, APK, deployment guide | M5, M6 |
| Week 15 | Final defence | freeze, rehearsal |

Buffer: if M1 slips, M2 moves fully into Week 12 and M5 is reduced to reachability + logout only. **Push (M4) is never cut** — it is FR-01 and the reason the product exists.

---

## 6. Team ownership and evidence

The agent implements code; the other members own checkable artifacts that use that code. The agent should keep the system easy for them to inspect: Swagger UI enabled, seed data with readable names, `server/README.md` with copy-paste commands.

| Member | Area | Recurring artifact (updated every check) |
|---|---|---|
| Nurassyl Turarbek | Application & Development | Working milestone demo, commits, explanation of what AI generated, what was changed and how it was tested |
| Taubay Laila | Data & Database | `docs/data_checks.sql` — integrity queries against the live DB (over-limit registrations, duplicates, orphan rows), results screenshots; executes `deployment.md` on her laptop |
| Shpanova Madina | Testing & Integration | Test run sheet for TC-01…TC-08 on the real app (Pass/Fail, date), defect log, RTM status |
| Nurkasymova Akbota | Architecture & Security | Role and security checklist (student cannot publish, password stored as hash, token required, lockout works), network map |
| Ualikhan Gulnazym | Requirements & UX | User flow of the main process in Figma, one usability test with 2–3 students, 3 interface changes with before/after |

Rule for every check: each member names one measurable task with a deadline and shows last week's result.

---

## 7. Final demo script (target: 5 minutes)

1. Warm up the server (open `/health`) one minute before speaking.
2. Problem in one sentence; who needs it.
3. Phone A (student, silent mode) is on the feed.
4. Laptop: admin publishes "Career Day" with 2 places via Swagger.
5. Phone A vibrates → tap → event detail → Register → confirmed.
6. Phone B registers → confirmed (last place). Phone C → waiting list.
7. Phone A cancels → Phone C is promoted and notified.
8. Show the rows in `registration` and `notification`.
9. Try to publish with a past deadline → 422 (FR-02). Student account tries to publish → 403 (BR-01).
10. What was tested (RTM), what each member did, limitations (section 8).

Fallback order if something fails live: second phone → recorded video of the same flow → mock mode (say openly that it is mock).

---

## 8. Risks and known limitations

| Risk / limitation | Impact | Response |
|---|---|---|
| Backend not started, 5 weeks left | High | M1 starts immediately; scope cuts in section 5 buffer |
| All code is written by one person (bus factor 1) | High | `deployment.md`, `server/README.md`; another member runs the system from zero in M6 |
| Render free tier sleeps (cold start ~30–60 s) | Medium | Warm-up step in the demo; reachability check in the app |
| Firebase setup needs manual steps and keys | Medium | Owner does it before M4; keys only in env vars |
| NFR-01 (1000 users) cannot be proven on a free tier | Low | Measure and report honestly; explain the scaling path (indexes, caching, paid tier) |
| Email verification is not really sent | Low | Documented limitation; BR-01 domain check still enforced |
| Render free Postgres is deleted 30 days after creation | High if used | Database on Neon instead (`docs/deployment.md`) |
| NFR-01 measured on a laptop (1000 users, p95 30 ms), not on the free tier | Low | Re-run `server/loadtest` against Render before the defence and report that number |
| `firebase_messaging` 17 deprecates the registration-token API (still works) | Low | After Week 15: move app and server to Firebase Installation IDs |
| Login rate limit and FCM sender live in one server process | Low | Enough for one Render instance; several instances would need Redis |

---

## 9. Definition of done for any task

- Acceptance criteria of the milestone are met and can be shown.
- Tests added or updated; all tests pass; linters clean.
- `docs/api.md` / `schema.sql` / `FLUTTER_BRIEF.md` updated in the same commit if the contract changed.
- `docs/project-status.md` updated (step table, requirements coverage, risks).
- No secrets in git; `.DS_Store` ignored.
