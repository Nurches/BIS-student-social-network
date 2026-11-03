# Project Status — Qatys (BIS Student Social Network)

**Date:** 3 November 2026 (Week 10)
**Prepared by:** Nurassyl Turarbek (Application & Development)
**Repository:** https://github.com/Nurches/BIS-student-social-network
**Plan:** [`docs/roadmap.md`](roadmap.md)

---

## 1. Summary

| | |
|---|---|
| Code for the roadmap | **M0–M6 implemented and tested.** M7 stretch: admin web page done |
| Main process | Works end to end on a real server and a real PostgreSQL: publish → notification rows → register / waiting list / cancel → promotion. Shown over HTTP and with the app's real network code |
| Tests | **157 automated tests, all passing:** 66 server (pytest, real PostgreSQL 16), 90 app (Flutter), 1 app ↔ live server contract test |
| Quality gates | `ruff` and `flutter analyze`: 0 issues |
| NFR-01 | Laptop: 1000 users, 0 errors, p95 30 ms. **Render free tier (0.1 CPU): meets the target up to ~60 simulated users (p95 1.1 s), saturates at ~20 requests/s** — see section 3 |
| Live system | **Deployed:** API https://qatys-api.onrender.com (Render, Frankfurt), database on Neon (Frankfurt). **A real push reached a real iPhone** and opened the event |
| What is left | Install on the other demo iPhones, team handover (section 6) |
| Platform decision | **Demo on iPhone only, no Android APK** (owner's decision, 3 Nov). Changes roadmap §3 "Android APK is primary" and the M6 release — **needs the PM's agreement** |

The Week 10 promises to the instructor are kept: the **race test for the last place** passes
(also with 8 students for 1 place, 30 runs in a row), and **duplicate notifications** are
impossible by a database constraint.

---

## 2. Milestones

| Milestone | Status | Proof |
|---|---|---|
| M0 Contract fix | ✅ Done | `api.md` v0.2, `schema.sql` v2, migration 002; checked on PostgreSQL 16 |
| M1 Server skeleton, auth, deploy | ✅ Done, deployed | https://qatys-api.onrender.com/api/v1/health; Swagger at `/docs` |
| M2 Live feed | ✅ Done | Server feed with keyset cursor (45-event test); app feed with offline cache |
| M3 Detail and registration | ✅ Done | All four button states; register → cancel → register; waiting-list promotion |
| M4 Push | ✅ Done on iPhone (Firebase + APNs) | Admin publish → push on a silent iPhone → tap opens the event |
| M5 Reliability | ✅ Done | Offline queue, `/health` reachability, no endless spinners, full logout cleanup |
| M6 Quality, security, release | ✅ Security pass, load test on Render, docs. Release: iPhone builds instead of the APK (pending PM agreement) | `deployment.md`, `network-map.md`, security tests |
| M7 Stretch | 🟡 Admin web page done (`/admin`); Flutter Web and analytics not started | — |

---

## 3. Requirements coverage

| ID | Requirement | Status | Where it is proven |
|---|---|---|---|
| FR-01 | Notify subscribers on publication | ✅ Real push delivered to an iPhone from the deployed server | `test_publish.py`; app `push_test.dart` (TC-01) |
| FR-02 | Reject a past deadline | ✅ 422 `deadline_in_the_past`; app shows "Registration closed" | `test_publish.py`; `event_detail_screen_test.dart` |
| FR-03 | Limit + waiting list | ✅ Row lock, waiting list, promotion on cancel | `test_registrations.py`, `test_race.py` |
| NFR-01 | 95% of feed loads under 2 s | 🟡 Code meets it (laptop: 1000 users, p95 30 ms). Free hosting does not at 1000 users (table below). The app shows the saved feed instantly in any case | `server/loadtest/`; `feed_screen_test.dart` |
| NFR-02 | bcrypt 12, lockout | ✅ 6th attempt refused for 15 min (TC-06) | `test_auth.py`; app login tests |
| BR-01 | University email, confirmed admins only | ✅ 422 for other domains, 403 `not_a_confirmed_admin` | `test_auth.py`, `test_publish.py` |

### NFR-01 load test on the deployed server (3 November 2026)

Locust from Almaty against https://qatys-api.onrender.com; each simulated user opens the feed
or an event every 1–3 s (far more often than a real student, roughly once a minute).

| Simulated users | Requests/s | p95 feed | Errors | Target met |
|---|---|---|---|---|
| 25 | 6 | 0.5 s | 0% | ✅ |
| 60 | 12 | 1.1 s | 0% | ✅ |
| 200 | 20 (ceiling) | 8.5 s | 8% (502 from Render's proxy) | ❌ |

Cause: the free Render instance has 0.1 CPU; the same code on a laptop served 450 requests/s
at 1000 users with p95 30 ms. Scaling path: a paid instance (0.5 CPU and more, several
instances behind Render's load balancer; the code keeps no state in memory except the login
rate limit), then caching of the feed query. For the demo (3 phones) the free tier is far
more than enough.

### Test cases (for Madina's run sheet)

| TC | Automated test | Manual check still needed |
|---|---|---|
| TC-01 push opens the event | `qatys/test/features/push/push_test.dart` | yes: real phone, silent mode |
| TC-02 register while places are free | `test_registrations.py`, `event_detail_screen_test.dart` | on the installed APK |
| TC-03 full → waiting list | same files | on the installed APK |
| TC-06 lockout | `test_auth.py::test_tc06_lockout_after_5_failed_attempts` | on the installed APK |
| Race on the last place | `test_race.py` | two phones in class |
| Direct API call cannot overbook | `test_registrations.py::test_direct_api_calls_cannot_overbook` | Swagger in class |

---

## 4. What was built

### Server (`server/`, new)

- FastAPI + psycopg 3, business rules in plain SQL that matches `docs/api.md`.
- Endpoints:
  - `/health`;
  - register and login with lockout;
  - feed with keyset cursor;
  - event detail;
  - register and cancel;
  - publish;
  - device token.
- Push through the FCM HTTP v1 API, sent after the response. Dead tokens are deleted, and `sent_at` shows what was delivered.
- Security:
  - bcrypt 12, JWT 24 h;
  - the server will not start with a short or missing secret;
  - 20 login attempts per minute per IP;
  - 64 KB body limit;
  - CORS closed;
  - errors never show a stack trace, and passwords are never logged;
  - the Docker image runs without root.
- Tooling:
  - `seed.py`: 10 students, 3 communities, 6 events, 1 confirmed admin;
  - `docker-compose.yml` and `render.yaml`;
  - a locust load test.

### App (`qatys/`)

- **Feed.** The saved page shows instantly and refreshes in the background. Pull to refresh also has a button. There is an empty state and "Load more".
- **Event detail.**
  - Re-fetched every time it opens.
  - Buttons: Register / Join waiting list / Registered ✓ + Cancel / Registration closed.
  - Tested to fit a 5-inch (320 dp) phone with the button in the bottom third.
- **Push.**
  - The permission is asked once, after the first login, with one sentence of explanation.
  - The phone's token goes to the server.
  - A tap opens the event from the background, from a cold start, and even before login.
  - A banner appears while the app is open.
- **Offline.**
  - A tap without a connection is saved on the phone and sent later.
  - Sending starts only after the server's `/health` answers, so a Wi-Fi login page cannot fool it.
- **Logout** clears the token, the saved feed, the queue and the phone's push token (shared device).
- **Android:**
  - app ID `kz.kbtu.qatys`;
  - high-importance notification channel, so the phone vibrates on silent;
  - release signing;
  - Firebase switched on automatically when its config file is present.

### Documents

- New:
  - [`deployment.md`](deployment.md): from zero to the deployed system, written for a member who did not write the code;
  - [`network-map.md`](network-map.md): draft for Akbota;
  - [`server/README.md`](../server/README.md).
- Updated:
  - `api.md`;
  - `README.md`;
  - `qatys/README.md`;
  - roadmap §8 (limitations).

---

## 5. Problems found and fixed by testing

These are worth mentioning at the defence: each one was found by a test or a measurement, not
by luck.

| Found by | Problem | Fix |
|---|---|---|
| Race test (8 students, 1 place) | Waiting-list positions were duplicated (`1, 1, 2, 2…`): `NOW()` is the start of a transaction, not the moment of writing | Queue times use `clock_timestamp()`, written under the row lock |
| Load test (300 users) | 44% errors and 30 s answers: worker threads waited for database connections held by threads that were waiting for workers (deadlock) | A connection is taken and returned inside one thread. After: 0 errors at 1000 users |
| Widget test | The result message covered the action button for 4 seconds, in the bottom third where the thumb is | The message is shown above the button instead |
| Widget test | After an app restart, a saved offline tap was not sent until the next manual refresh | The queue waits for the restored session before sending |
| Code review | Release APK had no Internet permission (only debug builds had it) | Added to the main Android manifest |
| Plan review | A free Render database is deleted after 30 days — before the defence | Database on Neon (`deployment.md`) |
| Contract review | One notification per student and event would block the "you got a place" push for an event already announced | Unique per student, event **and kind** |

---

## 6. What the owner and the team still need to do

| # | Task | Who | Time | Instructions |
|---|---|---|---|---|
| 1–3 | Neon database, Firebase (Android + iOS + APNs key), Render deploy | Nurassyl | — | ✅ done 3 Nov |
| 4 | ~~Signed APK on GitHub Releases~~ — dropped: demo on iPhone only (needs PM agreement) | — | — | — |
| 5 | Install on the other two demo iPhones (cable from the owner's Mac, or TestFlight) and run the full demo script | Nurassyl + Madina | 30 min | `qatys/README.md` |
| 6 | Load test against Render | Nurassyl | — | ✅ done 3 Nov (section 3) |
| 7 | Run the system from zero on another laptop (bus factor) | Laila or Akbota | 1 h | `deployment.md` |
| 8 | TC-01…TC-08 on the installed APK, RTM → Pass with dates | Madina | — | section 3 above |
| 9 | Integrity queries against the live DB (`docs/data_checks.sql`) | Laila | — | roadmap §6 |
| 10 | Security checklist, final network map | Akbota | — | `network-map.md` draft |
| 11 | Figma flow, usability test with 2–3 students | Gulnazym | — | roadmap §6 |

---

## 7. Risks and limitations

| Risk / limitation | Impact | Response |
|---|---|---|
| Android is configured but never built (APK dropped) | Low for the demo; expect the question "the target user has a cheap Android phone — why an iPhone demo?" | Answer: one Flutter code base, Android build configured; the demo uses the team's devices. Android pushes untested |
| Three iPhones are needed for the demo script (phones A, B, C) | Medium | Install on teammates' iPhones by cable this week, or start TestFlight early (review takes ~1 day) |
| Free hosting meets NFR-01 only up to ~60 heavy simulated users | Medium (grading question) | Measured and explained honestly (section 3); scaling path: paid instance, more instances, feed cache |
| Render free tier sleeps (30–60 s first request) | Medium | Warm-up step in the demo script |
| Push library deprecates the token API (still works) | Low | After Week 15: move to Firebase Installation IDs |
| Two defaults not yet confirmed by the team: cancelling after the event started is refused; any published event can be opened by link | Low | Confirm or change in one line of `api.md` |
| Bus factor 1: all code written by one person | High | Task 7 (another member deploys from the guide) |

---

## 8. Milestone log

### Live deploy — 3 November 2026 (Week 10)

- API on Render (Frankfurt) and PostgreSQL on Neon (Frankfurt), seeded; `/health`, Swagger and `/admin` reachable; feed answers in 0.33–0.43 s from Kazakhstan.
- iOS set up for push (bundle `kz.kbtu.qatys`, APNs key in Firebase); release build runs on an iPhone 13.
- **First real push:** published from `/admin` → delivered to the iPhone → tap opened the event.

### M1–M6 — implemented 3 November 2026 (Week 10)

- Server: 66 tests on PostgreSQL 16; race test 30× in a row; live demo script run over HTTP
  (publish → register → waiting list → cancel → promotion → 422 FR-02 → 403 BR-01).
- App: 90 tests, including TC-01, all button states, 320 dp layout, offline queue across an
  app restart, logout cleanup; 1 contract test against the live server.
- Load test: 1000 users, 0 errors, p95 30 ms (feed), p99 100 ms.

### M0 — Contract fix — done 3 November 2026 (Week 10)

- `docs/api.md` v0.2: every endpoint of the main process is defined with request and response bodies, error codes, the lockout rule, the feed cursor and the push payload. Nothing is left "to confirm".
- `docs/schema.sql` v2 and `docs/migrations/002_contract_fixes.sql` (upgrades an existing v1 database):
  - `device_token` table;
  - all timestamps are `TIMESTAMPTZ`;
  - the lockout window has its own column;
  - the waiting-list order survives re-registration;
  - the feed index matches the cursor.
- **Duplicate notifications** (promised for Week 10): `UNIQUE (student_id, event_id, kind)` on `notification`.
- Checked on PostgreSQL 16.2: `schema.sql` runs clean; a duplicate notification fails; a v1 database upgraded with migration 002 equals a fresh v2.
