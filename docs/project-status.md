# Project Status — Qatys (BIS Student Social Network)

**Date:** 10 November 2026 (Week 11)
**Prepared by:** Nurassyl Turarbek (Application & Development)
**Repository:** https://github.com/Nurches/BIS-student-social-network
**Plan:** [`docs/roadmap.md`](roadmap.md)

---

## 1. Summary

| | |
|---|---|
| Code for the roadmap | **M0–M6 implemented and tested.** M7 stretch: admin web page done |
| Main process | Works end to end on a real server and a real PostgreSQL: publish → notification rows → register / waiting list / cancel → promotion. Shown over HTTP and with the app's real network code |
| Tests | **263 automated tests, all passing:** 150 server (pytest, real PostgreSQL 16), 112 app (Flutter), 1 app ↔ live server contract test. The W11-9 patch (applied at the reseed) adds 11 server tests → 161 |
| MVP | **Usable without help (11 Nov):** sign-up, Explore with follow / unfollow, community pages, My events, notifications inbox, profile; new visual design |
| Quality gates | `ruff` and `flutter analyze`: 0 issues |
| NFR-01 | Laptop: 1000 users, 0 errors, p95 30 ms. **Render free tier (0.1 CPU): meets the target up to ~60 simulated users (p95 1.1 s), saturates at ~20 requests/s** — see section 3 |
| Live system | **Deployed:** API https://qatys-api.onrender.com (Render, Frankfurt), database on Neon (Frankfurt). **A real push reached a real iPhone** and opened the event |
| What is left | TestFlight upload and install on phones B and C, the members' live runs, the reseed with schema v3, the backup video (section 6) |
| Platform decision | **Demo on iPhone through TestFlight** — owner's decision 3 Nov, **agreed with the PM 4 Nov**; roadmap §3 and M6 updated. Android configured, not a deliverable |

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
| M6 Quality, security, release | ✅ Security pass, load test on Render, docs. Release: TestFlight — build script ready, upload by the owner (W11-2) | `deployment.md`, `testflight.md`, `network-map.md`, security tests |
| M7 Stretch | 🟡 Admin web page done (`/admin`); Flutter Web and analytics not started | — |
| T1 Data checks page (tool) | ✅ Deployed: live run 10 Nov, 9 of 9 Pass on Neon; Laila, Madina, Akbota have access. C10 goes live with the Week 11 push | `/data-checks`, `test_data_checks.py`; spec `docs/tools/data-checks-spec.md` |

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
| TC-02 register while places are free | `test_registrations.py`, `event_detail_screen_test.dart` | on an iPhone (TestFlight) |
| TC-03 full → waiting list | same files | on an iPhone (TestFlight) |
| TC-06 lockout | `test_auth.py::test_tc06_lockout_after_5_failed_attempts` | on an iPhone (TestFlight), account `zhanel@` |
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

## 6. Week 11 — tasks and real status

Plan: `week11-agent-tasks` (W11-1…W11-11). The agent prepared each member's artifact; the
person's part is marked and not faked. "Ready" = done in the repository, not yet pushed.

| # | Task | Who | Status (10 Nov) |
|---|---|---|---|
| W11-1 | D-02 Qatys icon (app + push), icon test | Nurassyl | Ready. Push with the icon: after the TestFlight install |
| W11-2 | TestFlight: mock-data banner, build script, `Info.plist`, `testflight.md`; bundle id → `com.qatys.app` | Nurassyl | Ready. **Owner:** new Firebase iOS app + plist + APNs key, upload, testers |
| W11-3 | D-01 error responses in Swagger + tests | Nurassyl | Ready; on `/docs` after the push |
| W11-4 | `/data-checks` live | Nurassyl → Laila | ✅ Live, 9/9 Pass; allow list checked (Laila, Madina, Akbota → 200) |
| W11-5 | C07 fix, C10, deployment dry run | Laila | Ready. **Laila:** live run with 10 checks, `deployment.md` on her laptop |
| W11-6 | Test sheet U-01…U-04, defect log, RTM | Madina | Ready. **Madina:** TC-02, TC-07, TC-08 and app cases herself; RTM statuses from her results only |
| W11-7 | `run_checks.sh`, network map, roles matrix | Akbota | Ready; agent's run S-01…S-08 Pass. **Akbota:** her own run, agree map and matrix |
| W11-8 | Usability kit + SUS calculator | Gulnazym | Ready (formula proven: all 3s → 50). **Gulnazym:** 3 sessions with real students |
| W11-9 | Soft delete + `faculty` table (migration 003) | Akbota, Laila | Done as a patch (+10 tests); applied together with the reseed (`demo-runbook.md` §1), or moved to Week 12 if the reseed slips |
| W11-10 | Reseed safety (`--live`), read-only grants, demo runbook | Nurassyl | Ready. **Owner:** reseed after the members' runs, re-login on 3 phones, backup video |
| W11-11 | Documentation sync | all | Ready |

### Defects, findings and test-case updates

| ID | What | Status |
|---|---|---|
| D-01 | Swagger listed no error responses | Fixed (W11-3); Madina re-checks after the push |
| D-02 | Flutter logo in the push | Fixed (W11-1); Madina re-checks on the TestFlight build |
| D-03 | NFR-01 not met on free hosting | Open (hosting limit, section 3) |
| C07 | Waiting list with free places in the sample data of `schema.sql` | Fixed (W11-5, sample data only) |
| A-01 | No e-mail one-time code | Open: after Gulnazym's 3 UI changes; limitation if not done by Week 14 |
| A-02 | Matrix: guest views announcements | Closed: matrix → No (login required, BR-01) |
| A-03 | Moderator has no rights | Matrix says "After the defence" |
| A-04 | No HSTS header | Open (optional) |
| A-05 | Swagger public | Accepted for the demo |
| A-06 | Architecture and network map outdated | Updated; waiting for Akbota's agreement |
| A-07 | Firebase client configs in git | Accepted (public by design); optional key restriction |
| U-01…U-04 | Test-case wording | Applied with the original text kept; Madina agrees them with Gulnazym |

## 7. Risks and limitations

| Risk / limitation | Impact | Response |
|---|---|---|
| Android is configured but never built (APK dropped) | Low for the demo; expect the question "the target user has a cheap Android phone — why an iPhone demo?" | Answer: one Flutter code base, Android build configured; the demo uses the team's devices. Android pushes untested |
| Three iPhones are needed for the demo script (phones A, B, C) | Medium | TestFlight internal testing (no review); upload a day before; `docs/testflight.md` |
| The reseed deletes every push token and the members' test rows | Medium | `docs/demo-runbook.md`: reseed only after their live runs; `seed.py` needs `--live` and the typed database name for a remote host |
| Bundle id changed to `com.qatys.app` (App Store Connect record) | Medium until done | Firebase needs the new iOS app, plist and APNs key; the build script stops if the plist does not match |
| Free hosting meets NFR-01 only up to ~60 heavy simulated users | Medium (grading question) | Measured and explained honestly (section 3); scaling path: paid instance, more instances, feed cache |
| Render free tier sleeps (30–60 s first request) | Medium | Warm-up step in the demo script |
| Push library deprecates the token API (still works) | Low | After Week 15: move to Firebase Installation IDs |
| Two defaults not yet confirmed by the team: cancelling after the event started is refused; any published event can be opened by link | Low | Confirm or change in one line of `api.md` |
| Bus factor 1: all code written by one person | High | Task 7 (another member deploys from the guide) |

---

## 8. Milestone log

### MVP extension — 11 November 2026 (Week 11, owner's decision)

Goal: the app can be used freely, not only in the scripted demo. A new student signs up,
finds communities, follows them and gets their events and pushes.

- **Server** (new files only, so the W11-9 patch still applies): `GET /communities`,
  `PUT|DELETE /communities/{id}/subscription`, `GET /communities/{id}/events`,
  `GET /me/registrations`, `GET /me/notifications`, `POST /me/notifications/read`
  (`docs/api.md`). Every new route documents its errors in Swagger (checked by
  `test_openapi_errors.py`). Seed: + *Sports Club* and *Volunteer Hub* with one event each, not
  followed by the demo accounts (the demo feed is unchanged). 8 new tests.
- **App:** bottom tabs Feed · Explore · My events · Profile; sign-up; community page; inbox with
  an unread badge; feed greeting and filters; new theme from the icon (deep blue, amber
  accent), event cards with community badge, red deadline under 24 h and a capacity bar; the
  event detail keeps its layout and the 320 dp test. Mock mode shares one in-memory server, so
  following a community changes the feed there too. 14 new tests.
- **W11-9 patch** regenerated for this stage (`qatys_w11-9_soft_delete_faculty_after_mvp.patch`):
  the new lists also hide soft-deleted rows (+1 test).
- Not verified by a device build (owner builds through `tool/build_ios_release.sh`).

### Week 11 — 10 November 2026

- **W11-1 Icon (D-02):** Qatys icon designed in Figma, generated for every iOS and Android
  size (`flutter_launcher_icons`, alpha removed for iOS); Android status-bar icon for pushes.
  Test: no icon file equals the Flutter template.
- **W11-2 TestFlight:** a release build without `API_BASE_URL` shows a red "DEMO DATA" strip
  on every screen (4 tests); `qatys/tool/build_ios_release.sh` (URL check, Firebase plist ↔
  bundle id check, analyze + tests, build number, `aps-environment = production` check);
  `ITSAppUsesNonExemptEncryption = false`; iOS bundle id → `com.qatys.app`; `docs/testflight.md`.
- **W11-3 Swagger errors (D-01):** every endpoint documents exactly the errors it can return,
  with an example each; a static walk through the code proves "no more, no less" (20 tests).
  `password_too_long` was missing from `api.md` — added.
- **W11-4:** `/data-checks` confirmed live: 9 of 9 Pass on Neon.
- **W11-5 Laila:** C07 defect fixed in the sample data (before: C07 Fail; after: C01–C10 Pass
  on a fresh PostgreSQL 16); new check C10 with an injected-violation test; deployment dry run
  from a fresh clone (fixes in `deployment.md`).
- **W11-6 Madina, W11-7 Akbota, W11-8 Gulnazym:** workbooks, guides, `run_checks.sh`
  (live: S-01…S-08 Pass; HSTS missing = A-04), network map for the iPhone demo, usability kit
  and SUS calculator.
- **W11-9:** soft delete and `faculty` table with migration 003 (+10 tests, migration on v2
  equals a fresh v3) — kept as a patch until the reseed, because the live database is v2.
- **W11-10:** `seed.py` refuses a remote database without `--live` and the typed name, grants
  the read-only role again, seeds no "Career Day" look-alike (`IT Career Day` → `IT Job Fair`);
  `docs/demo-runbook.md`.
- **Tests:** server 135 (145 with W11-9), app 98, `ruff` and `flutter analyze` clean.

### T1 — Data checks page — implemented 3 November 2026 (Week 10)

- `/data-checks` page and `GET /api/v1/admin/data-checks`. They run the 9 checks of `server/app/checks/data_checks.sql` (owner: Laila) and show Pass/Fail/Error and the failing rows, with **Copy as Markdown** for her weekly report. A new check needs only an edit of the SQL file.
- Read only: one `READ ONLY` transaction, 3 s statement timeout, rolled back. The parser accepts only one `SELECT`/`WITH` per check. Access is limited to the `DATA_CHECK_EMAILS` allow list, with one run per 10 s per student. A sensitive check (C08, password hashes) returns only a row count.
- 36 tests on PostgreSQL 16. **Injected-violation tests:** for C01, C05–C09, each test breaks the seeded data and expects exactly that check to fail and all the others to pass. For C02–C04, the schema itself refuses the violation, and with the constraint dropped the check catches it. So "0 rows" is proven to mean "no defect", not "the query is wrong". Mutation check: weakening C07's condition makes its test fail.
- Finding for Laila (not fixed on purpose): on the sample data of `docs/schema.sql`, **C07 fails**. *IT Career Day* has 1 confirmed of 200 places and 1 student on the waiting list.

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
