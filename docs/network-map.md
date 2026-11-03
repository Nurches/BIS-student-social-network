# Network map — Qatys

Week 10 lecture (SIS 9). Draft for Akbota's architecture & security part; she owns the final
version.

```
                       ┌──────────────────────────── Render (Frankfurt) ──────┐
 Student's phone       │                                                      │
 ┌──────────────┐ HTTPS│ TLS proxy ──▶ FastAPI (uvicorn, 1 instance)          │
 │ Qatys app    │─────▶│              • JWT check, rate limit, 64 KB limit    │
 │ JWT in       │ 443  │              • business rules in SQL transactions    │
 │ Keystore     │      │                     │                        │       │
 └──────▲───────┘      └─────────────────────┼────────────────────────┼───────┘
        │                                    │ TLS 5432 (sslmode=require)
        │                                    ▼                        │ HTTPS 443
        │                        ┌────────────────────────┐           │ OAuth2 service account
        │                        │ Neon: PostgreSQL 16    │           ▼
        │                        │ student, event,        │   ┌────────────────────┐
        │                        │ registration,          │   │ Firebase Cloud     │
        │                        │ notification,          │   │ Messaging (Google) │
        │                        │ device_token           │   └─────────┬──────────┘
        │                        └────────────────────────┘             │
        └──────────── push over Google Play services (persistent TLS) ───┘

 Admin's laptop ──HTTPS──▶ same FastAPI: /docs (Swagger) or /admin
```

## Paths

| # | From → To | Protocol / port | What travels | Protection |
|---|---|---|---|---|
| 1 | Phone → API | HTTPS 443 | login, feed, register, device token | TLS (Render certificate), JWT `Authorization` header |
| 2 | API → database | PostgreSQL over TLS, 5432 | SQL | `sslmode=require`, password in `DATABASE_URL` env var |
| 3 | API → FCM | HTTPS 443 | one message per device token | OAuth2 token from the service account key (env var) |
| 4 | FCM → phone | Google Play services connection | notification + `event_id` | Google-managed, no personal data beyond the event title |
| 5 | Admin laptop → API | HTTPS 443 | publish event | JWT of a confirmed community owner (BR-01) |

The phone never talks to the database or to FCM's server API directly. Secrets (database
password, JWT secret, Firebase key) exist only as Render environment variables.

## One likely failure and what the user sees

**University Wi-Fi with a login page (captive portal).** The phone shows "connected", but every
request returns the Wi-Fi login page instead of our API, and FCM is blocked too.

| Layer | Behaviour |
|---|---|
| App | Never trusts the connectivity flag: an HTML answer instead of JSON counts as "no connection" |
| Screen | Banner "No connection to the server. Check the Wi-Fi login page or switch to mobile data." with **Retry**; the saved feed stays visible with its time |
| Register tap | Saved on the phone, banner "waiting to be sent", sent automatically on the next refresh or launch; the server's answer at that moment wins (it may be the waiting list) |
| Push | Delayed until the phone reaches Google again; nothing is lost on the server (`notification.sent_at` shows what FCM accepted) |

Other failures handled: API asleep on the free tier (first request 30–60 s → warm-up step in the
demo script), database down (`/health` answers 503, the app shows the same banner), FCM token
of an uninstalled app (FCM answers `UNREGISTERED`, the server deletes the token).
