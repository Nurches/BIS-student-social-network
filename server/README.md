# Qatys API — FastAPI server

Server of the BIS student social network. Contract: [`../docs/api.md`](../docs/api.md).
Deployment from zero: [`../docs/deployment.md`](../docs/deployment.md).

## Run locally in 5 commands

Needs Python 3.12 and Docker.

```bash
docker compose up -d db                       # PostgreSQL 16 on localhost:5432
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env && python seed.py --yes  # tables + demo data
uvicorn app.main:app --reload                 # http://localhost:8000/docs
```

Demo accounts (password `qatys2026`): students `nurassyl@`, `laila@`, `madina@`, … `@kbtu.kz`;
confirmed admin `union@kbtu.kz` (owner of *IT Club* = community 1 and *Career Center* = 2).

## Publish an event (admin)

* **Swagger UI** — http://localhost:8000/docs: `POST /api/v1/auth/login` as `union@kbtu.kz`,
  copy `token`, press **Authorize**, then `POST /api/v1/communities/2/events`.
* **Admin page** — http://localhost:8000/admin: the same in a small form.

## Checks

```bash
ruff check . && ruff format --check .
pytest                       # needs the database from docker compose (qatys_test)
```

| Test file | What it proves |
|---|---|
| `test_auth.py` | BR-01 domain check, bcrypt, TC-06 lockout (6th attempt → 423), rate limit, JWT |
| `test_feed.py` | keyset pagination over 45 events, no skips/repeats, Event object contract |
| `test_registrations.py` | TC-02, TC-03, re-registration, waiting-list promotion, no overbooking |
| `test_race.py` | two (and eight) students take the last place at the same moment |
| `test_publish.py` | FR-01 one notification per subscriber, no duplicates, FR-02, BR-01 403 |
| `test_devices_and_security.py` | device tokens, `/health`, 413, 500 without stack trace, CORS |
| `test_schema_and_seed.py` | `app/schema.sql` is identical to `docs/schema.sql`; the demo seed |

## Load test (NFR-01)

```bash
python seed.py --yes && uvicorn app.main:app --port 8000 &
locust -f loadtest/locustfile.py --host http://localhost:8000 \
       --headless -u 1000 -r 100 -t 60s --only-summary
```

## Layout

```
app/
  main.py       app factory: routers, error format, body size limit, CORS, Swagger, /admin
  config.py     settings from environment variables
  db.py         psycopg 3 connection pool (UTC, autocommit + explicit transactions)
  security.py   bcrypt, JWT, current student, login rate limit
  errors.py     { "error": "<code>" } for every failure
  schemas.py    request / response bodies of docs/api.md
  routers/      HTTP layer only
  services/     business rules in plain SQL: auth, events (feed, registration,
                publishing), devices, push (FCM HTTP v1)
  schema.sql    docs/schema.sql without test data
seed.py         demo data (DELETES every table)
tests/          pytest against a real PostgreSQL
loadtest/       locust scenario for NFR-01
```

## Environment

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_URL` | yes | `postgresql://user:password@host:5432/db` (Neon: add `?sslmode=require`) |
| `JWT_SECRET` | yes | at least 32 characters; the server refuses to start otherwise |
| `FCM_SERVICE_ACCOUNT_JSON` | for push | Firebase service account key, the JSON on one line |
| `CORS_ORIGINS` | no | JSON list, e.g. `["https://admin.example"]`; empty = closed |
| `BCRYPT_ROUNDS` | no | default 12 (NFR-02); tests use 4 |
| `LOGIN_RATE_LIMIT_PER_MINUTE` | no | default 20 per IP |
| `ENABLE_DOCS` | no | default `true`: Swagger is the admin tool of the demo |
