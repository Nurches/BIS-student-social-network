# Tool spec — Data checks page (`/data-checks`)

**Date:** 3 November 2026 (Week 10)
**Product owner:** Nurassyl Turarbek · **User of the tool:** Taubay Laila (Data & Database)
**Implements:** the coding agent, as one milestone (`T1`), following `docs/roadmap.md` §0 rules
**Reads with:** `docs/schema.sql`, `docs/api.md`, `docs/team/laila.md`

---

## 1. Why this tool exists

Laila owns the data model. Her weekly evidence is proof that the **live** data follows the
rules of `docs/requirements.md`. Today that needs DBeaver, a connection string and manual
screenshots. The tool turns her SQL file into a page she opens with her own account and that
shows Pass/Fail for every rule on the live database.

**Ownership rule (important for grading):** the tool only **executes** checks. The checks
themselves live in one SQL file that Laila edits. Adding or changing a check must never need
Python or HTML changes. Laila's commits to that file are her evidence of contribution.

## 2. User story and acceptance

> As the Data & Database member, I open `/data-checks`, log in, press **Run checks**, and see
> for every rule whether the live data passes, which rows break it, and I can copy the result
> table into my weekly report.

**Accepted when** (demonstrable in class):

1. Laila logs in at https://qatys-api.onrender.com/data-checks with `laila@kbtu.kz` and sees 9 checks with Pass/Fail in under 5 seconds.
2. A student account not on the allow list gets "Access denied" (403), and nothing runs.
3. A check that finds rows shows **Fail**, the row count and up to 20 rows in a table.
4. **Copy as Markdown** puts a results table on the clipboard that pastes into `laila_report.md` unchanged.
5. Laila adds a 10th check by editing only `data_checks.sql`, pushes, Render redeploys, and the page shows 10 checks.
6. The page cannot change data: a test proves an `UPDATE` placed in the file is refused.

## 3. Scope

### In scope

- Server: check loader, runner, one JSON endpoint, one HTML page.
- Read-only execution with a time limit.
- Allow list of who may run checks.
- Tests on real PostgreSQL, including tests that **inject a violation** and expect Fail.

### Out of scope

- Free-text SQL from the browser (never: the page runs only the file in the repo).
- Storing run history in the database (the page shows the latest run; Laila keeps screenshots and the Markdown copy).
- Scheduling, email alerts, charts.
- Fixing defects the checks find. **Do not fix the sample-data defect in `docs/schema.sql` (check C07)** — Laila found it and fixes it herself as her own commit.

## 4. Check file

**Location:** `server/app/checks/data_checks.sql` (shipped in the Docker image).
Add a short pointer in `docs/README.md` and `docs/team/laila.md` to this path. The initial
content is the file delivered with this spec (`data_checks.sql`, 9 checks).

**Format.** Every check is a block that starts with four metadata comment lines, followed by
optional comment lines and exactly one `SELECT` that ends with `;`:

```sql
-- @check C07
-- @title Nobody waits while free places exist
-- @requirement FR-03
-- @sensitive false
-- Optional explanation lines are shown on the page under the title.
SELECT ...;
```

| Field | Rule |
|---|---|
| `@check` | Unique id `C` + two digits. Duplicates → server refuses to start (clear error in the log) |
| `@title` | Shown on the page, up to 100 characters |
| `@requirement` | One of the IDs in `requirements.md` (FR-01…, NFR-01…, BR-01) or `—` |
| `@sensitive` | `true` → the page shows only the row count, never row values (used for C08: password hashes) |
| Body | Exactly one statement; must start with `SELECT` or `WITH` (case-insensitive, after comments). Anything else → that check shows **Error: not a SELECT** and is not executed |

**Pass rule:** 0 rows = Pass, 1 or more rows = Fail, SQL error or timeout = Error.

Parsing happens once at startup and on each request in debug mode. A malformed file must not
crash the server: broken blocks appear on the page as **Error** with the parser message, so
Laila sees her mistake in the browser.

## 5. Execution rules (security)

1. Each run opens one transaction with `SET TRANSACTION READ ONLY` and
   `SET LOCAL statement_timeout = '3s'`, runs the checks one by one, then `ROLLBACK`.
   Defence in depth: even if a non-SELECT slipped through the parser, PostgreSQL refuses it.
2. If the environment variable `DATABASE_URL_READONLY` is set, the runner uses that
   connection (the `qatys_readonly` role from `docs/team/setup/readonly_role.sql`);
   otherwise the normal pool with rule 1.
3. Rows returned per check are capped at 20 (`LIMIT` added by wrapping:
   `SELECT * FROM (<check>) AS c LIMIT 21` — 21 to know whether there are more). The
   full count comes from `SELECT COUNT(*) FROM (<check>) AS c`.
4. Values are rendered as text and HTML-escaped. Timestamps in ISO 8601 with offset.
5. A run is limited to **one per 10 seconds per user** → `429 too_many_requests`.
6. Errors on the page never show stack traces; the SQL error message from PostgreSQL is
   shown (it is Laila's own SQL, she needs it), but connection details never are.

## 6. Access

- Authentication: the existing JWT from `POST /api/v1/auth/login` (24 h).
- Authorization: allow list in env `DATA_CHECK_EMAILS`, comma-separated. Default when unset:
  `laila@kbtu.kz,madina@kbtu.kz,akbota@kbtu.kz,nurassyl@kbtu.kz,union@kbtu.kz`.
- Not on the list → `403 { "error": "not_allowed" }`. No token → `401`.
- Do not add a new role column; this is a tool permission, not a product role. Leave a
  `# TODO(confirm):` if the allow list should move to the database later.

## 7. API

### `GET /api/v1/admin/data-checks`

Runs all checks and returns:

```json
{
  "ran_at": "2026-11-10T09:14:03+00:00",
  "database": "neon / qatys",
  "duration_ms": 412,
  "summary": { "total": 9, "passed": 8, "failed": 1, "errors": 0 },
  "checks": [
    {
      "id": "C07",
      "title": "Nobody waits while free places exist",
      "requirement": "FR-03",
      "note": "If this returns rows, a cancellation did not promote the waiting list.",
      "status": "fail",
      "row_count": 1,
      "truncated": false,
      "columns": ["event_id", "title", "participant_limit", "confirmed", "waiting"],
      "rows": [[2, "IT Career Day", 200, 1, 1]],
      "duration_ms": 18,
      "error": null
    }
  ]
}
```

`status` is `pass | fail | error`. For `@sensitive true`: `columns` and `rows` are empty
arrays, `row_count` is still given. `database` shows host alias and database name only,
never the user or password.

Document it in `docs/api.md` under a new section "Tools (not part of the product)".

## 8. Page (`/data-checks`)

Single static HTML file in `server/app/static/data_checks.html`, same style and login approach
as `/admin` (reuse its login form and token handling; token kept in `sessionStorage`, cleared
on Log out). No build step, no external scripts.

Layout, top to bottom:

1. Header: "Qatys — Data checks", logged-in email, Log out.
2. **Run checks** button + last run time + summary chips: `8 passed · 1 failed · 0 errors`.
3. One card per check, in file order:
   - left: id and status badge (green Pass / red Fail / grey Error — with text, not colour alone);
   - title, requirement tag, note;
   - for Fail: "1 row breaks this rule" and the rows table (horizontal scroll if wide);
   - for Error: the error message in monospace.
4. Buttons: **Copy as Markdown**, **Download JSON**.

**Copy as Markdown** produces exactly:

```markdown
Run: 2026-11-10 14:14 (Asia/Almaty) · live database · 8 passed, 1 failed, 0 errors

| # | Rule | Requirement | Rows | Result |
|---|---|---|---|---|
| C01 | Confirmed registrations never exceed the limit | FR-03 | 0 | Pass |
| C07 | Nobody waits while free places exist | FR-03 | 1 | Fail |
```

Show run time in Asia/Almaty. Must be readable on a laptop projector: base font 16 px,
real contrast, works in light and dark mode.

## 9. Tests (pytest, real PostgreSQL from docker-compose)

| Test | Proves |
|---|---|
| Parser reads the shipped file: 9 checks, ids C01…C09, all SELECT | file format |
| Parser: duplicate id → startup error; missing `@title` → that block is Error | format errors are visible |
| Body `UPDATE event SET title = 'x';` → status `error`, table unchanged | read-only (rules 1 and parser) |
| A check that sleeps (`SELECT pg_sleep(5)`) → `error` with timeout, other checks still run | timeout isolation |
| Seeded database → all 9 pass | no false alarms on clean data |
| Inject a violation and expect Fail: C01 (extra confirmed rows over the limit), C05 (publish under unconfirmed community via SQL), C06 (email outside the domain, constraint dropped in the test DB), C07 (waiting row with free places), C08 (plain-text password), C09 (notification for a draft event) | each check really catches what it claims |
| C02, C03, C04: inserting the violation fails with the constraint name | these rules are protected by the schema itself |
| No token → 401; madina → 200; aru@kbtu.kz → 403 | access |
| Second run within 10 s → 429 | rate limit |
| `@sensitive true` → rows not present in JSON | no password hashes leave the server |

The injected-violation tests are the most important: they turn "0 rows" from "maybe the
query is wrong" into "the query is proven to catch the problem". Mention them in
`docs/project-status.md`.

## 10. Deliverables and definition of done

- `server/app/checks/data_checks.sql` (initial content from this spec), loader, runner, router, page.
- Tests above, all green; `ruff` clean.
- `docs/api.md` (Tools section), `server/README.md` (how to run checks locally), `docs/team/laila.md` (link to the page, how to add a check).
- `DATA_CHECK_EMAILS` and optional `DATABASE_URL_READONLY` added to `render.yaml` / deployment docs.
- Entry in `docs/project-status.md` milestone log.
- Small commits; **one commit message per change, and Laila's later edits to the SQL file stay separate commits under her name.**

## 11. How Laila uses it (for her weekly check)

1. Open `/data-checks`, log in, **Run checks**.
2. Read every Fail; decide whether it is a defect in the data, the server or her query.
3. Copy as Markdown into `laila_report.md`; log defects; tell Nurassyl.
4. Add or improve a check in `data_checks.sql` and push it as her own commit.
5. In class: open the page, run it live, explain one check and one finding (C07 is a good one).
