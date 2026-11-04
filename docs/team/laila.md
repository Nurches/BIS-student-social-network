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
