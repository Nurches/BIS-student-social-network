# Student Social Network — Flutter Client Brief

**For:** the coding assistant building the Flutter app
**Owner:** Nurassyl Turarbek (24B032077), area *Application & Development*
**Repo:** https://github.com/Nurches/BIS-student-social-network
**Course:** Basics of Information Systems, KBTU SITE, Fall 2026 — semester project, final defence is an offline presentation **with a working demo**

---

## 0. How to use this file

This is the single source of truth for the mobile client. Everything below is already agreed by the team in the course documents (`docs/requirements.md`, `docs/api.md`, `docs/schema.sql`). Where something is marked **TO CONFIRM**, do not invent a different answer silently — implement the stated default and leave a `// TODO(confirm):` comment.

Build order is in section 11. Start there if you want to write code immediately.

---

## 1. The problem we are solving

University event announcements are scattered across dozens of chats, so students miss registration deadlines.

Root cause: KBTU has no fixed academic groups. Every student ends up in a different set of course chats, so there is no single place where "what is happening this week" lives. A first-year student hears about a career day the morning after registration closed.

The app gives one feed of events from the communities a student follows, plus a push notification the moment an event is published.

**Primary user:** first-year student, cheap Android phone, moving between classes.
**Secondary user:** community admin (club / Student Union) who publishes events.

---

## 2. Scope of this build

One user action end to end, because this is what the team analysed and what the demo must show:

> A student receives a push notification about a new event, unlocks the phone, opens the app, and registers while free places and the deadline are still open.

In scope: login, event feed, event detail, register / cancel, waiting list, push notification handling.

Out of scope for now: creating events from the app (admin side is web/API for the demo), chat, comments, profile editing, friend requests.

---

## 3. Stack

| Layer | Choice | Notes |
|---|---|---|
| Client | **Flutter** (stable channel) | Android first, Flutter Web as fallback demo target |
| Push | **Firebase Cloud Messaging** | Android + web; no APNs work needed for the demo |
| Server | **FastAPI** (Python) | separate repo folder, not your job unless asked |
| DB | **PostgreSQL 16** | schema in `docs/schema.sql` |
| Auth | **JWT**, passwords **bcrypt cost 12** | server-side; client only stores the token |

**Delivery for the demo:** no App Store. Android APK published via GitHub Releases, or a Flutter Web build on free hosting. Server on Render / Railway / Fly.io. The team has an Apple developer account, so TestFlight is an optional bonus, not the main path.

**State management: TO CONFIRM.** Default to `flutter_riverpod` unless the team says otherwise. Keep business logic out of widgets either way.

---

## 4. Data model

Six tables exist server-side: `student`, `community`, `subscription`, `event`, `registration`, `notification`. The client needs these shapes:

```dart
class Student {
  final int id;
  final String email;        // university email only, see BR-01
  final String fullName;
}

class Community {
  final int id;
  final String name;
  final bool isSubscribed;
}

class Event {
  final int id;
  final int communityId;
  final String communityName;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime registrationDeadline;
  final int participantLimit;
  final int freePlaces;          // server-computed, never computed on the client
  final RegistrationState myState; // none | registered | waitingList
}

enum RegistrationState { none, registered, waitingList }
```

`freePlaces` and `myState` always come from the server. The client must never guess them from a cached list — see the race condition in section 9.

---

## 5. API contract

Base URL from `--dart-define=API_BASE_URL`. All authed calls send `Authorization: Bearer <jwt>`.

**TO CONFIRM against `docs/api.md`** — these four endpoints are the agreed set; match exact paths and field names to that file before writing the client, and fix this brief if they differ.

### POST /auth/login
```json
// request
{ "email": "student@kbtu.kz", "password": "..." }
// 200
{ "token": "<jwt>", "student": { "id": 12, "email": "...", "fullName": "..." } }
// 401 wrong credentials
// 423 account locked (5 failed attempts, 15 min) — see NFR-02
```

### GET /feed?limit=20&cursor=<opaque>
Events from the communities the student follows, newest first.
```json
{ "items": [ { /* Event */ } ], "nextCursor": "..." }
```

### GET /events/{id}
One event with fresh `freePlaces` and `myState`.

### POST /events/{id}/registration
```json
// 201 registered
{ "state": "registered", "freePlaces": 7 }
// 200 waiting list (event was full)
{ "state": "waitingList", "waitingPosition": 3 }
// 409 deadline passed
{ "error": "DEADLINE_PASSED" }
```
`DELETE /events/{id}/registration` cancels and returns the new `freePlaces`.

Server does the limit check inside a transaction with `SELECT ... FOR UPDATE`, so two simultaneous taps cannot oversell the last place. The client just renders whatever comes back.

---

## 6. Requirements this client must satisfy

| ID | Requirement | What it means in the app |
|---|---|---|
| FR-01 | The system shall notify subscribers when an announcement is published | FCM message opens the right event detail screen |
| FR-02 | The system shall reject an announcement with a past registration deadline | admin side, but the client must render a past deadline as closed |
| FR-03 | The system shall reject registration over the participant limit and offer a waiting list | handle `waitingList` as a first-class state, not an error |
| NFR-01 | 95% of feed loads under 2 s at 1000 concurrent users | cache the last feed, show it instantly, refresh in background |
| NFR-02 | bcrypt cost ≥ 12, 15-minute lockout after 5 failed logins | show the lockout clearly with remaining time, do not retry automatically |
| BR-01 | Only university email, and only Student-Union-confirmed admins may publish | client shows a clear message for non-university email at login |

---

## 7. Screens

Four screens. Nothing else for now.

**Login.** Email + password. Inline errors. Lockout message with minutes left.

**Feed.** List of event cards. Each card shows: community name, title, start date, **deadline**, **free places**. Pull to refresh. Empty state when the student follows nothing yet.

**Event detail.** Full description plus the primary action button. Button states: `Register` / `Join waiting list` (when full) / `Registered ✓` with cancel / `Registration closed` (disabled).

**Permission prompt.** Android 13+ notification permission, asked after first login, with one sentence explaining why — not on cold start before any context.

---

## 8. UI constraints — these are graded decisions, do not change them

**Design for a 5-inch phone first, not a flagship.** On the event detail screen, the deadline, the free places and the Register button must all fit without scrolling at 320 dp width. Most first-years carry cheap phones; the whole point of the app dies if the student has to scroll to find the button.

**Minimum tap target 48 dp.** The action is performed while walking between classes, often one-handed.

**Readable outdoors.** Real contrast, no light grey on white. The analysed scenario is a student checking a deadline at an outdoor career day.

**Primary action in the bottom third** of the detail screen, reachable with a thumb.

**No gesture-only paths.** Everything must be doable with single taps — the design assumes a plain capacitive screen, nothing fancy.

---

## 9. Failure modes to handle explicitly

These came out of the team's hardware analysis and the test cases. Each one is a real demo question.

**Captive-portal Wi-Fi.** University Wi-Fi shows a login page. The phone reports "connected" while there is no real internet, so FCM and our API are unreachable. **Never trust the connectivity flag.** Reachability = a successful call to our own health endpoint. On failure, show "No connection to the server" and retry over mobile data rather than silently spinning.

**Low battery / app killed.** A registration tap that did not reach the server must not be lost. Queue it locally, retry on next launch, and reconcile with server state — the server is always right about `freePlaces`.

**Silent phone.** The notification must survive a muted phone. Use a high-importance FCM channel so vibration still fires; do not rely on sound alone.

**Stale list.** Free places in the cached feed go out of date in seconds. Re-fetch `GET /events/{id}` when the detail screen opens, and never let the client decide that a registration will succeed.

**Race on the last place.** Two students tap at the same moment. The loser gets `waitingList`, not an error dialog. Render it as a normal, calm outcome.

**Token on a shared device.** Logout must clear the token from secure storage completely. Store the JWT in `flutter_secure_storage`, never in plain `SharedPreferences`.

---

## 10. Tests to write

Mirror the team's test cases so the RTM can move from "Not run" to "Pass".

- TC-01: push delivered → tapping it opens the correct event detail
- registration succeeds while free places > 0 and deadline is in the future
- registration when full → `waitingList` state rendered
- registration after the deadline → closed state, button disabled
- two simultaneous registrations for the last place → one registered, one waiting list
- direct API call bypassing the UI still enforces the limit (integration, server side)
- login lockout after 5 failed attempts

Widget tests for the three button states on the detail screen are enough for the UI layer; do not chase coverage.

---

## 11. Build order

1. **Project skeleton** — Flutter app, folder structure (`lib/features/<feature>/{data,domain,presentation}`), `--dart-define` config, lint rules.
2. **API layer behind an interface** — `EventRepository` with two implementations: `HttpEventRepository` and `MockEventRepository` with fake data. The server may not be deployed when the UI is being built, and the demo must never depend on the server being awake.
3. **Login + secure token storage.**
4. **Feed screen** with cache-first loading.
5. **Event detail + registration**, all four button states.
6. **FCM integration** and deep link from notification to detail.
7. **Offline queue and reachability check.**
8. **Tests**, then an APK on GitHub Releases.

Stop after each step and let the owner check it. Do not scaffold all seven at once.

---

## 12. Conventions

- Everything in the repo is in **English**, including comments and commit messages.
- Docs live in `docs/`. If a decision changes, update `docs/api.md` or this file in the same commit.
- Canonical file names already referenced in submitted coursework — do not rename: `README.md`, `docs/api.md`, `docs/requirements.md`, `docs/schema.sql`, `docs/ER_diagram.png`.
- Add a `.gitignore` for `.DS_Store` if it is still missing.
- Commits should be small and dated — they double as coursework evidence of individual contribution.

---

## 13. Open questions

- State management library — Riverpod assumed.
- Exact endpoint paths and field names — verify against `docs/api.md`.
- Whether the demo target is Android APK or Flutter Web; build for both if cheap.
- Admin publishing flow: web only for the demo, or a hidden screen in the app.
