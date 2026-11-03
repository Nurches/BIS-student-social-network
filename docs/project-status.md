# Project Status — Qatys (BIS Student Social Network)

**Date:** 3 November 2026
**Prepared by:** Nurassyl Turarbek (Application & Development)
**Repository:** https://github.com/Nurches/BIS-student-social-network

---

## 1. Summary

| | |
|---|---|
| Overall progress | **3 of 8 build steps done (~35–40%)** |
| Health | Green: 46 automated tests pass, static analysis finds no issues |
| Main risk | The backend (FastAPI + PostgreSQL) has not been started. Push notifications (FR-01), the core of the demo, depend on it |
| Demo readiness | Login works today on mock data. Feed, registration and push are not ready yet |

The mobile client is built in small steps that can each be checked on their own. The foundation is finished: architecture, network layer and authentication. The remaining client steps are mostly screens built on that foundation. The backend has to start now so that it is ready before push notifications (step 6).

---

## 2. Mobile client (Flutter) — build progress

| # | Step | Status |
|---|------|--------|
| 1 | Project skeleton, architecture, lint rules, theme | ✅ Done |
| 2 | Data layer: real API client and mock data behind one interface | ✅ Done |
| 3 | Login, session handling, secure token storage | ✅ Done |
| 4 | Event feed (cached feed shown instantly, pull to refresh) | ⏭ Next |
| 5 | Event detail and registration (register / cancel / waiting list / closed) | ⬜ Planned |
| 6 | Push notifications (FCM), tap opens the event | ⬜ Planned, **blocked by backend** |
| 7 | Offline queue and server reachability check | ⬜ Planned |
| 8 | Final tests and an Android APK on GitHub Releases | ⬜ Planned |

**Design decision:** when no server address is configured, the app runs on built-in mock data. The demo can therefore never fail because the server is asleep or unreachable.

---

## 3. Requirements coverage

| ID | Requirement | Status |
|---|---|---|
| FR-01 | Notify subscribers when an event is published | ⬜ Step 6. Needs backend and FCM |
| FR-02 | Past registration deadline is rejected / shown as closed | 🟡 Data model ready. Screen in step 5 |
| FR-03 | Over the limit, offer a waiting list | 🟡 Logic ready in the data layer. Screen in step 5 |
| NFR-01 | Feed loads fast (95% under 2 s) | ⬜ Step 4 (cache-first feed) |
| NFR-02 | 15-minute lockout after 5 failed logins | ✅ Login screen shows the lockout with minutes left (tested) |
| BR-01 | University email only | ✅ Login shows a clear message for non-university email |

---

## 4. Backend (FastAPI + PostgreSQL)

**Status: not started.** It is built by the Application & Development role.

Before coding, the API document (`docs/api.md`) and the schema (`docs/schema.sql`) need these fixes, found while building the client:

1. **Blocker for FR-01:** there is no table for phone push tokens and no endpoint to send one to the server. Without this the server cannot deliver any push. Proposed: `PUT /me/device-token`.
2. **Missing from the API document:** event detail (`GET /events/{id}`), health check (`GET /health`), the login response body, the feed response format, the event object, the cancel response and the lockout retry time.
3. **Bug:** a student who cancels and then registers again gets a database error (unique constraint `uq_registration`). The server must update the existing row instead of inserting a new one.
4. **Bug:** the feed is sorted by deadline but paged by event ID, so pages can skip or repeat events. The page cursor must be (deadline, event ID).
5. Timestamps are stored without a time zone. The API must return them with the offset.

The client marks each place that depends on these points (7 places in total), so they are easy to update once the API is final.

---

## 5. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Backend not started | High: no live push in the demo | Start the backend in parallel with steps 4–5 |
| Recent work exists only on one laptop (3 commits not pushed) | High: work could be lost, and the team cannot see it | Push to GitHub now |
| Firebase setup (app ID, push channel for silent phones) | Medium | Planned in step 6 |
| Open lockout rule: locked on the 5th or the 6th failed attempt | Low | Agree on it with requirements / test cases |

---

## 6. Next steps

1. Push the existing commits to GitHub.
2. Client step 4: event feed.
3. In parallel: fix `api.md` and `schema.sql`, then start the backend.
4. Client step 5: event detail and registration.
5. Step 6 (push) once the backend can store device tokens.

---

## 7. Decisions needed from the team

- **Demo platform:** Android APK only, or Flutter Web as well?
- **Admin publishing for the demo:** web/API only, or a hidden screen in the app?
- **Lockout rule:** is the account locked on the 5th or the 6th failed login? Requirements and test cases need to match.
