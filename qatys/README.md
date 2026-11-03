# Qatys — Flutter client

Mobile client of the BIS student social network. The full brief is in
[`../FLUTTER_BRIEF.md`](../FLUTTER_BRIEF.md); the API contract is in
[`../docs/api.md`](../docs/api.md).

## Run

```sh
# Mock data, no server needed (default)
flutter run

# Against a deployed server
flutter run --dart-define=API_BASE_URL=https://<host>/api/v1
```

| Define | Default | Meaning |
|---|---|---|
| `API_BASE_URL` | empty | Server prefix including `/api/v1` |
| `USE_MOCK_API` | `true` when `API_BASE_URL` is empty | Force mock repositories |

Push notifications need `android/app/google-services.json` from the team's
Firebase project (package `kz.kbtu.qatys`, see `../docs/deployment.md`).
Without it the app builds and runs normally, just without pushes.

Release APK (signing key in `android/key.properties`, kept out of git):

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://<host>/api/v1
```

## Demo accounts

Mock mode and the seeded server (`server/seed.py`) use the same accounts:
`nurassyl@kbtu.kz`, `laila@kbtu.kz`, `madina@kbtu.kz`, … with the password
`qatys2026`. Five wrong passwords lock the account for 15 minutes; the 6th
attempt is refused (NFR-02, TC-06). In mock mode, restart the app to reset.

## What the app does

| Screen / behaviour | Requirement | Code |
|---|---|---|
| Login, lockout with minutes left | BR-01, NFR-02 | `features/auth/` |
| Feed: saved page shown instantly, refreshed in the background, pull to refresh + button, empty state, "Load more" | NFR-01 | `features/feed/` |
| Event detail: re-fetched on open; Register / Join waiting list / Registered ✓ + cancel / Registration closed; fits a 320 dp phone | FR-02, FR-03, brief §7–8 | `features/event/presentation/` |
| Push: permission asked once after the first login, token sent to the server, tap opens the event (cold start, background), banner while open | FR-01, TC-01 | `features/push/` |
| Offline: taps saved and sent later, `/health` reachability, "No connection to the server" banner | brief §9 | `features/sync/`, `core/network/reachability.dart` |
| Logout clears the token, the cached feed, the queue and the phone's push token | brief §9 | `SessionController.logout` |

## Structure

```
lib/
  core/            config, theme, shared infrastructure
  features/<name>/
    data/          repositories, DTOs, HTTP and mock sources
    domain/        models and business logic, no Flutter imports
    presentation/  screens, widgets, Riverpod providers
```

## Checks

```sh
dart format .
flutter analyze
flutter test

# Contract test of the real HTTP code against a running server (server/README.md):
flutter test test/integration --dart-define=LIVE_API=http://localhost:8000/api/v1
```
