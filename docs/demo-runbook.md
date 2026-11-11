# Demo runbook — Qatys

**Audience:** Nurassyl (owner) and the two members whose iPhones are phones B and C.
**Reads with:** [`testflight.md`](testflight.md) (installing the app),
[`roadmap.md`](roadmap.md) §7 (the 5-minute demo), [`deployment.md`](deployment.md).

| Phone | Owner | Account | Role in the demo |
|---|---|---|---|
| A | Nurassyl (iPhone 13) | `nurassyl@kbtu.kz` | first to register, later cancels |
| B | Madina | `madina@kbtu.kz` | takes the last place |
| C | Laila | `laila@kbtu.kz` | waiting list → promoted |
| Laptop | Nurassyl | `union@kbtu.kz` | publishes on `/admin`, shows `/data-checks` and Swagger |

All three students follow **IT Club** and **Career Center** after a reseed and start with no
registrations. The seed has no event called "Career Day": it is published live.

---

## 1. When to reseed

`server/seed.py` **deletes every table**: every registration, notification, the members' test
rows and **every phone's push token**. So:

1. **Only after** Laila (`/data-checks` run), Madina (TC-07, TC-08, app cases) and Akbota
   (`run_checks.sh`) have finished their live runs. **Ask them first** in the team chat.
2. **Again on the morning of the defence** (dates in the seed are relative to "now").

### Week 11 only: the reseed also brings schema v3

Migration 003 (soft delete, `faculty` table, W11-9) reaches the live database **only through
this reseed**. The server code of W11-9 needs schema v3, and the code before it needs v2, so
the order matters:

1. Members' live runs are done on the code already deployed (W11-1…W11-8, schema v2).
2. Apply the W11-9 patch on the laptop, run the tests, commit (`Akbota: soft delete …`,
   `Laila: faculty table …`), **do not push yet**.
3. Reseed from this checkout (section 2): the live database becomes v3.
4. **Push at once.** Render redeploys in 3–5 minutes. Meanwhile the old code keeps working on
   v3 (it reads no new column); only `POST /auth/register` fails, which the demo does not use.
5. Continue with section 2, step 4.

If W11-9 is not ready at the agreed reseed time, reseed without it and move W11-9 to Week 12
(say so in `project-status.md`).

## 2. Reseed, step by step (about 15 minutes)

```bash
# 1. Warm up the server (free tier sleeps): wait for {"status":"ok"}
curl -s -m 90 https://qatys-api.onrender.com/api/v1/health

# 2. Reseed from the laptop. The Neon URL is in the Neon console, never in git or chat.
cd server && source .venv/bin/activate
export DATABASE_URL='postgresql://…neon.tech/neondb?sslmode=require'
export JWT_SECRET=not-used-by-seed-but-required-32chars
# Only if the read-only role is used on Render: the same value as there.
# export DATABASE_URL_READONLY='postgresql://qatys_readonly:…@…/neondb?sslmode=require'
python seed.py --yes --live
#   Target: database 'neondb' on host 'ep-….neon.tech'
#   Type the database name 'neondb' to delete every table in it: neondb
#   Seeded 10 students, 5 communities, 8 events. Admin: union@kbtu.kz
#   Read-only role qatys_readonly: SELECT granted again   (or: not present)
unset DATABASE_URL DATABASE_URL_READONLY
```

3. **Data checks:** https://qatys-api.onrender.com/data-checks → log in as `laila@kbtu.kz` →
   **Run checks** → every check **Pass** (10 since Week 11). Any Fail or Error: stop and look
   at it before the demo.
4. **Phones A, B, C:** in Qatys **log out and log in again** (the reseed deleted the push
   tokens; login sends a new one). Keep notifications allowed.
5. **Tokens arrived** — Neon → SQL Editor, read only; **never show the token column**:

   ```sql
   SELECT s.email, d.platform, COUNT(*) AS tokens, MAX(d.updated_at) AS last_update
   FROM device_token d JOIN student s USING (student_id)
   GROUP BY s.email, d.platform ORDER BY s.email;
   ```

   Expected: one `ios` row each for `laila@`, `madina@`, `nurassyl@`.
6. **Test publish:** laptop → https://qatys-api.onrender.com/admin → `union@kbtu.kz` →
   community **1** (IT Club), title "Push test", deadline tomorrow, 5 places → **Publish**.
   **All three phones vibrate** and show the push with the Qatys icon. Leave the event; it
   does not disturb the demo.

## 3. Demo script on iPhones (roadmap §7, 5 minutes)

Before speaking: phones charged, on **silent**, Qatys open on the feed; laptop with `/admin`
signed in as `union@kbtu.kz`, a second tab with `/data-checks`, a third with `/docs`.

1. **Warm-up** (1 minute before): open `/api/v1/health` → `{"status":"ok"}`.
2. **Problem** in one sentence: events are lost in 10+ chats; students learn too late.
3. **Phone A** shows the feed.
4. **Laptop, `/admin`:** publish **"Career Day"** in community **2** (Career Center), deadline
   in 2 days, **2 places**.
5. **Phone A vibrates** → tap the push → event → **Register** → *Registered ✓*.
6. **Phone B** opens Career Day → **Register** → confirmed (the last place).
   **Phone C** → **Join waiting list** → "You are number 1 on the waiting list".
7. **Phone A** → **Cancel** → **Phone C** gets the push "you got a place" → confirmed.
8. **Data:** `/data-checks` → Run → all Pass (C01: never more confirmed than the limit; C07:
   nobody waits while places are free). Optional: Neon SQL Editor,

   ```sql
   SELECT s.email, r.status, r.updated_at FROM registration r
   JOIN student s USING (student_id) JOIN event e USING (event_id)
   WHERE e.title = 'Career Day' ORDER BY r.updated_at;
   ```

9. **Error cases on `/admin`:** publish with a deadline in the past → *422 deadline in the
   past* (FR-02). In Swagger, log in as `aru@kbtu.kz` and publish → **403
   `not_a_confirmed_admin`** (BR-01).
10. **Wrap-up:** tests and RTM (Madina), each member's part, limitations (roadmap §8).

**Fallback order:** second phone → backup video (section 4) → Swagger only → mock mode as a
last resort, **said openly** ("this is demo data").

## 4. Backup video

Recorded once, after the reseed and the test publish, with the same steps as section 3.

**Shot list (one take, 2–3 minutes):**

| # | Screen | What happens |
|---|---|---|
| 1 | Phone A (screen recording) | Feed of `nurassyl@` |
| 2 | Laptop (screen recording) | `/admin` → publish "Career Day", 2 places |
| 3 | Phone A | Push arrives → tap → Register → *Registered ✓* |
| 4 | Phone B / C (or phone A logged in as them) | last place → confirmed; next → waiting list number 1 |
| 5 | Phone A | Cancel |
| 6 | Phone C | Push "you got a place" → confirmed |
| 7 | Laptop | `/data-checks` → Run → all Pass |
| 8 | Laptop | `/admin` past deadline → 422; Swagger student publish → 403 |

* iPhone: Control Centre → **Screen Recording** (add it in Settings → Control Centre).
  Laptop: QuickTime → New Screen Recording, or ⇧⌘5.
* **No passwords on screen:** type them before starting the recording, or blur that part.
  Hide notifications from other apps (Focus mode).
* Put the files on the team's shared drive, **not in git**, and paste the link here:

**Backup video:** `TODO(Nurassyl)` — link, date recorded.
