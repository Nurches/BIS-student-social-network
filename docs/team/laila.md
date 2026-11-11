# Taubay Laila — Data & Database

This page currently covers only the data checks tool. The rest of the page is Laila's to write.
Step-by-step guide for an AI assistant: [`laila-agent-prompt.md`](laila-agent-prompt.md).

## Data checks

* **Page:** https://qatys-api.onrender.com/data-checks. Locally: http://localhost:8000/data-checks.
  Log in with `laila@kbtu.kz` and press **Run checks**.
* **The checks:** [`server/app/checks/data_checks.sql`](../../server/app/checks/data_checks.sql).
  The page only runs this file. Changing a check never needs Python or HTML.
* **Spec:** [`docs/tools/data-checks-spec.md`](../tools/data-checks-spec.md).

A check **passes** when its SELECT returns 0 rows. It **fails** when the SELECT returns rows,
and the page shows up to 20 of them. A check is an **error** when its SQL fails, takes more
than 3 s, or its block is broken. The page then shows the message.

### Add or change a check

1. Add a block to `data_checks.sql`:

   ```sql
   -- @check C10
   -- @title Every event has a limit of at least one place
   -- @requirement FR-03
   -- @sensitive false
   -- Optional lines like this one are shown under the title.
   SELECT event_id, title FROM event WHERE participant_limit < 1;
   ```

   * `@check`: `C` and two digits, unique. A duplicate id stops the server at start.
   * `@title`: up to 100 characters.
   * `@requirement`: an ID from `docs/requirements.md` (`FR-01`, `NFR-02`, `BR-01`, …) or `—`.
   * `@sensitive true`: the page shows only the row count, never the values. Use it for
     anything with password hashes.
   * Then exactly **one** `SELECT` (or `WITH … SELECT`) ending with `;`. Anything else shows
     as **Error: not a SELECT** and does not run. The run is read only in any case.
2. Try it locally (`server/README.md`, "Data checks").
3. Commit the file as your own commit, push, and Render redeploys in a few minutes.

### Weekly use

Run the checks and read every Fail: is the defect in the data, the server or the query? Then
press **Copy as Markdown** and paste the table into your weekly report.

## Week 11

Prepared by the AI agent in Nurassyl's session (W11-5). Laila reviews it, runs it live and
explains it. What she does herself is marked **Laila does**.

### C07: the defect her check found

* **What the check says.** C07 *Nobody waits while free places exist* (FR-03) lists every
  event that has someone on the waiting list **and** fewer confirmed students than its limit.
  In a correct system this cannot happen: the server puts a student on the waiting list only
  when the event is full, and a cancellation promotes the first waiting student at once.
* **What it found.** On the sample data of `docs/schema.sql`, *IT Career Day* had 200 places,
  1 confirmed student and **1 student on the waiting list**. A student was told "the event is
  full" while 199 places were free. The live database was never affected: the rows were only
  in the sample data of the file.
* **The fix** (commit `Laila: schema.sql sample data: fix waiting list with free places (found
  by C07)`): only the sample `INSERT` rows changed, no table, constraint or index.
  * Student 1 is now **confirmed** for IT Career Day (199 → 198 free places).
  * The waiting-list example moved to the *Git workshop*, which now has 2 places, 2 confirmed
    students and 1 student waiting. So the "WAITING LIST" example query at the end of the file
    reads event 3 and still returns a row.
  * `TODO(confirm)`: the other option was to make IT Career Day full. Laila decides.
* **Proof:** `docs/schema.sql` was run in a fresh local PostgreSQL 16. Before the fix C07
  failed with 1 row; after the fix C01–C10 all return 0 rows.

### C10: her new check

```sql
-- @check C10
-- @title Nobody holds an active registration for an unpublished event
-- @requirement FR-03
```

* **Rule.** A student can be confirmed or waiting only for a **published** event. A draft is
  not visible to students, and a cancelled event has no places at all. A row here means the
  server let a registration through for such an event, or an event was unpublished and its
  registrations were left active.
* **Why not a constraint.** The rule compares two tables (`registration.status` and
  `event.status`). A `CHECK` constraint sees only one row of one table, so PostgreSQL cannot
  enforce it. The server enforces it (404 for a non-published event), and C10 proves it in the
  data.
* **How the test proves it.** `server/tests/test_data_checks.py` seeds the demo data, inserts
  one confirmed registration for the draft *Debate tournament* and expects **exactly C10** to
  fail with that row, and all other checks to pass. When the query was weakened on purpose
  (`= 'cancelled'` instead of `<> 'published'`), the test failed, so the test really depends
  on the query.
* It passes on the seed data (test) and on the sample data of `docs/schema.sql` (local run).

### Constraint vs check

* **C02, C03** (unique pairs) and **C04, C06** (deadline before start, university email) are
  also guaranteed by `UNIQUE` / `CHECK` constraints. PostgreSQL refuses the bad row, so these
  checks **cannot fail** on real data. They are a second line of defence: if someone drops the
  constraint, the check still catches the problem (the tests prove it by dropping it).
* **C01, C07, C10** span several rows or two tables. No simple constraint can express them, so
  the check query is the **only** proof that the data obeys the rule. That is why C07 could
  find a real defect.

### Live run (Laila does, after the Week 11 deploy)

Open https://qatys-api.onrender.com/data-checks, log in as `laila@kbtu.kz`, press **Run
checks**, then **Copy as Markdown** into the weekly report, plus a screenshot.

| Date | Checks | Pass | Fail | Error | Note |
|---|---|---|---|---|---|
| TODO(Laila) | 10 | | | | |

Agent's own run before the deploy (10 Nov 2026, 13:57 UTC, live Neon): 9 checks, 9 Pass. C10
is not on the live server until the Week 11 commit is pushed.

**Also Laila does:** follow `docs/deployment.md` on her own laptop (bus-factor evidence) and
note every step that was unclear.

### Explain it yourself

My checks are SELECT queries that look for rows breaking a rule from our requirements: 0 rows
means the rule holds, any row is a broken record. This week my check C07 found a real defect:
in the sample data of our schema file, a student was on the waiting list of IT Career Day
while 199 of its 200 places were free, which contradicts FR-03. I chose the fix: confirm that
student and move the waiting-list example to a workshop that is really full. I added C10:
nobody may hold an active registration for an event that is not published. A constraint
cannot express this because it compares two tables, so only a check query can prove it. The
tests break the data on purpose and show that exactly my check fails, so "0 rows" means "no
defect", not "a wrong query". The AI agent wrote the SQL changes and the test; I chose the
rules and the fix, ran the checks on the live page and can explain every line.

**Likely questions**

1. *Why can C02 never fail, but C07 can?* — C02 is also a `UNIQUE` constraint, so PostgreSQL
   refuses a duplicate before it is stored. C07 spans many rows of an event; no constraint
   checks it, so only my query can find it.
2. *How do you know C10 is not just a wrong query that always returns 0 rows?* — The test
   inserts one bad registration into a draft event and C10 fails with exactly that row; when
   the query was weakened, the test failed.
3. *Why fix the sample data and not the check?* — The check was right and the data was
   wrong. Changing the query to hide a finding would make the check useless.
