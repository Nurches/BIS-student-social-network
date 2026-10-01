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
```
