# Network map — Qatys

Week 10 lecture (SIS 9). Owner: **Akbota Nurkasymova** (Architecture & Security).
Draft — `TODO(Akbota)`: remove this line when she agrees with the map (Week 11 update by the
AI agent: iPhone demo, APNs, Keychain, `/data-checks`, checked against the live system on
10 November 2026 with `docs/team/akbota/run_checks.sh`).

```
                        ┌──────────── Cloudflare + Render (Frankfurt) ─────────────┐
 Student's iPhone       │                                                          │
 ┌──────────────┐ HTTPS │ TLS ──▶ FastAPI (uvicorn, 1 instance, free tier 0.1 CPU) │
 │ Qatys app    │──────▶│         • JWT HS256 (24 h) on every request              │
 │ (TestFlight) │  443  │         • login rate limit, lockout, 64 KB body limit    │
 │ JWT in iOS   │       │         • business rules in SQL transactions             │
 │ Keychain     │       └────────────┬────────────────────────────┬────────────────┘
 └──────▲───────┘                    │ TLS 5432                   │ HTTPS 443
        │                            │ (sslmode=require)          │ OAuth2 service account
        │                            ▼                            ▼
        │              ┌──────────────────────────┐   ┌──────────────────────────┐
        │              │ Neon: PostgreSQL 16      │   │ Firebase Cloud Messaging │
        │              │ (Frankfurt, eu-central-1)│   │ (Google)                 │
        │              │ student, community,      │   └────────────┬─────────────┘
        │              │ event, registration,     │                │ HTTP/2 + TLS,
        │              │ notification,            │                │ APNs auth key (.p8)
        │              │ device_token             │                ▼
        │              └──────────────────────────┘   ┌──────────────────────────┐
        └────────────────── push (alert + event_id) ◀─│ Apple Push Notification  │
                                                      │ service (APNs)           │
                                                      └──────────────────────────┘

 Team laptop ──HTTPS──▶ same FastAPI:
     /admin        publish an event (confirmed admin, BR-01)
     /docs         Swagger UI (public for the demo, finding A-05)
     /data-checks  Laila's integrity checks, READ ONLY transaction
 http://… ──301──▶ https://…   (no HSTS header yet, finding A-04)
```

## Paths

| # | From → To | Protocol / port | What travels | Protection |
|---|---|---|---|---|
| 1 | iPhone → API | HTTPS 443 | login, feed, register, device token | TLS (Render certificate), JWT in the `Authorization` header |
| 2 | API → database | PostgreSQL over TLS, 5432 | SQL | `sslmode=require`; password only in the `DATABASE_URL` env var |
| 3 | API → FCM | HTTPS 443 | one message per device token | OAuth2 token from the service account key (env var) |
| 4 | FCM → APNs → iPhone | HTTP/2 + TLS (Apple) | notification title, body, `event_id` | APNs auth key of the team (stored in Firebase, not in git); no personal data beyond the event title |
| 5 | Team laptop → API | HTTPS 443 | publish (`/admin`, `/docs`), data checks (`/data-checks`) | JWT of a confirmed community owner (BR-01); data checks: `DATA_CHECK_EMAILS` allow list, read only |

The phone never talks to the database or to FCM's server API directly. Secrets (database
password, JWT secret, Firebase service account key) exist only as Render environment
variables; the APNs key only in the Firebase console. The token on the phone is kept in the
**iOS Keychain** through `flutter_secure_storage` (`qatys/lib/features/auth/data/session_storage.dart`).
Personal data (email, password) travels only on path 1, at login.

## Failures and what the user sees

**1. The server is asleep (Render free tier).** After 15 minutes without traffic the first
request takes 30–60 s.

| Layer | Behaviour |
|---|---|
| App | Requests time out; reachability is a successful `GET /health`, not the Wi-Fi flag |
| Screen | Banner **"No connection to the server"** with **Retry**; the saved feed stays visible with its time |
| Register tap | Saved on the phone and sent when `/health` answers; the server's answer at that moment wins (it may be the waiting list) |
| Response | Warm-up step in the demo runbook: open `/api/v1/health` one minute before speaking |

**2. Notifications not allowed on the iPhone.** The student pressed *Don't Allow*, or turned
notifications off in Settings.

| Layer | Behaviour |
|---|---|
| Server | Publishes, creates the `notification` row and sends to FCM as usual; APNs accepts the message |
| Phone | Shows nothing: **no banner, no sound, no vibration** |
| Student | Sees the new event only when opening the feed |
| Response | iPhone Settings → Notifications → Qatys → Allow; the TestFlight guide checks this on every phone |

**3. University Wi-Fi with a login page (captive portal).** Every request returns the Wi-Fi
login page instead of our API: the app treats an HTML answer as "no connection" and shows the
same banner ("Check the Wi-Fi login page or switch to mobile data"); pushes wait until the
phone reaches Apple again, nothing is lost on the server (`notification.sent_at`).

Also handled: database down (`/health` answers 503, same banner); a token of an uninstalled
app (FCM answers `UNREGISTERED`, the server deletes the token).

## Single point of failure

One free Render instance. If it sleeps or fails, everything stops; the app keeps the saved
feed and queues taps. If the JWT secret leaks, every token can be forged: rotate `JWT_SECRET`
on Render (everyone is logged out).
