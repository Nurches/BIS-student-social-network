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
| `ALLOW_MOCK_RELEASE` | `false` | A release build on mock data shows a red "DEMO DATA — not connected to the server" strip on every screen; `true` hides it (only for a deliberate offline demo) |

Push notifications need the Firebase config of the team's project:
`ios/Runner/GoogleService-Info.plist` (iOS app **`com.qatys.app`**) and
`android/app/google-services.json` (package `kz.kbtu.qatys`), see
`../docs/deployment.md`. Without them the app runs normally, just without pushes.

**iPhone release (TestFlight)** — the demo platform. Never archive from Xcode's
menu (no `API_BASE_URL` → demo data); use the script, then upload with
Transporter (`../docs/testflight.md`):

```sh
API_BASE_URL=https://qatys-api.onrender.com/api/v1 tool/build_ios_release.sh
tool/build_ios_release.sh --check     # every check, no build
```

Android (configured, not demoed; signing key in `android/key.properties`, kept
out of git): `flutter build apk --release --dart-define=API_BASE_URL=https://<host>/api/v1`.

**App icon:** `assets/icon/qatys_icon.png` (1024 × 1024, no transparency; Figma
file "Qatys — app icon"). After changing it: `dart run flutter_launcher_icons`,
then check that `ios/Runner.xcodeproj/project.pbxproj` was not changed (the tool
sets `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon`
by mistake; revert that line). `test/platform/app_icon_test.dart` fails if the
Flutter logo comes back.

## Demo accounts

Mock mode and the seeded server (`server/seed.py`) use the same accounts:
`nurassyl@kbtu.kz`, `laila@kbtu.kz`, `madina@kbtu.kz`, … with the password
`qatys2026`. Five wrong passwords lock the account for 15 minutes; the 6th
attempt is refused (NFR-02, TC-06). In mock mode, restart the app to reset.

## What the app does

| Screen / behaviour | Requirement | Code |
|---|---|---|
| Login, lockout with minutes left; **sign-up** with a university email | BR-01, NFR-02 | `features/auth/` |
| **Bottom tabs**: Feed · Explore · My events · Profile | — | `features/home/` |
| **Explore**: search, follow / unfollow (the feed and pushes follow), community page with its open events | FR-01 | `features/community/` |
| **My events**: upcoming and past registrations and waiting lists | FR-03 | `features/event/presentation/my_events_screen.dart` |
| **Notifications inbox**: every notification, unread badge on the feed, marked read on opening | FR-01 | `features/inbox/` |
| **Profile**: account, numbers, notification status, how it works, about, sign out | brief §9 | `features/profile/` |
| Feed: saved page shown instantly, refreshed in the background, pull to refresh + button, greeting, filters (All / Places left / My registrations), empty state with "Find communities", "Load more" | NFR-01 | `features/feed/` |
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
