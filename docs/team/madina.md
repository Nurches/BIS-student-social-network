# Shpanova Madina — Testing, Analytics & Integration

Her artifact: [`docs/test_cases_and_rtm.xlsx`](../test_cases_and_rtm.xlsx) — test cases TC-01…TC-08,
the RTM and the defect log. Step-by-step prompt for her own AI assistant:
[`madina-agent-prompt.md`](madina-agent-prompt.md).

## Week 11

Prepared by the AI agent in Nurassyl's session (W11-6). **Madina runs the cases herself** and
sends the results to Nurassyl; only then do statuses in the RTM change.

### What changed in the workbook

* **Test cases:** U-01…U-04 applied. The old wording is kept in **Original text**, the reason
  in **Reason for change**. New columns **Performed by**, **Date**, **Evidence**.
  * U-01 (TC-07): the expected answer is the API code `not_a_university_email`, not a UI
    message (the app has no sign-up screen).
  * U-02 (TC-02): the message on `/admin` is "The deadline is in the past (FR-02)", and
    publishing is done on `/admin`, not in the app.
  * U-03 (TC-03): the full demo event is *CV clinic* (limit 3), not an event with 30 places.
  * U-04 (TC-01): the new event appears in the feed at the position of its deadline, not at
    the top.
  * `TODO(Madina)`: agree U-01…U-04 with Gulnazym (requirements owner).
* **Defect log** (new sheet): D-01 Swagger without error responses → *fixed in W11-3*;
  D-02 Flutter logo in the push → *fixed in W11-1*; D-03 NFR-01 on free hosting → *open*.
  D-01 and D-02 are closed only after her re-check (below).
* **RTM:** every status is still **Not run**. Nurassyl's iPhone runs of Week 10 (TC-01, TC-03,
  TC-06) and the load test (TC-05) are listed as *evidence waiting for Madina*: she looks at
  the screenshots, compares them with the expected result and sets Pass or Fail herself.

### Accounts

Password for every demo account: see `server/README.md` (the seeded demo password).

| Account | Role | Use it for |
|---|---|---|
| `aru@kbtu.kz` | student, not an admin | TC-08 |
| `union@kbtu.kz` | confirmed admin of IT Club (1) and Career Center (2) | TC-02, publishing for TC-01 |
| `madina@kbtu.kz` | student, phone B | TC-01, TC-03 |
| `zhanel@kbtu.kz` | student | **TC-06 only** (it locks the account for 15 minutes) |

The free server sleeps: open https://qatys-api.onrender.com/api/v1/health first and wait for
`{"status":"ok"}` (up to a minute).

### TC-08 in Swagger — a student cannot publish (BR-01)

1. Open https://qatys-api.onrender.com/docs.
2. **POST /api/v1/auth/login** → *Try it out* → body
   `{"email": "aru@kbtu.kz", "password": "<demo password>"}` → *Execute*.
   Copy the value of `token` (without quotes).
3. Press **Authorize** (top right) → paste the token → *Authorize* → *Close*.
4. **POST /api/v1/communities/{community_id}/events** → *Try it out* → `community_id` = `1` →
   body (any future dates):

   ```json
   { "title": "TC-08 hack attempt", "starts_at": "2026-12-01T10:00:00+05:00",
     "registration_deadline": "2026-11-30T18:00:00+05:00", "participant_limit": 5 }
   ```

   → *Execute*.
5. **Pass when:** code **403**, body `{"error": "not_a_confirmed_admin"}`.
6. Prove no event was created: **GET /api/v1/feed** → *Execute* → no "TC-08 hack attempt" in
   `items`.
7. Screenshots: the request, the 403 answer, the feed.

### TC-07 in Swagger — only university e-mails (BR-01)

1. In `/docs` press **Authorize → Logout** (TC-07 is for a visitor without an account).
2. **POST /api/v1/auth/register** → *Try it out* → body
   `{"email": "student@gmail.com", "password": "testpass123", "full_name": "Test Student"}` →
   *Execute*.
3. **Pass when:** code **422**, body `{"error": "not_a_university_email"}`.
4. Extra proof that no account exists: **POST /api/v1/auth/login** with the same e-mail →
   also **422** `not_a_university_email`.
5. Screenshots: both requests and answers.

### TC-02 on /admin — a past deadline is refused (FR-02)

1. Open https://qatys-api.onrender.com/admin, sign in as `union@kbtu.kz`.
2. Fill the form: community 2, title "TC-02 past deadline", **registration deadline one hour
   ago**, start in two days, 5 places → **Publish**.
3. **Pass when:** the page shows "The deadline is in the past (FR-02)" with HTTP 422, the
   form keeps what you typed, and the event is not in the feed (GET /feed as any student).

### App cases on her iPhone (after the TestFlight install)

Install first: [`docs/testflight.md`](../testflight.md), section 5. Log in as `madina@kbtu.kz`.

**TC-01 — push opens the event (FR-01).** Put the phone on silent and lock it. Ask Nurassyl
(or use `/admin` as `union@kbtu.kz`) to publish an event in IT Club. **Pass when:** within 1
minute the push with the event title and the **Qatys icon** appears; a tap opens that event;
the event is in the feed. Note the time of publishing and of the push.

**TC-03 — full event → waiting list (FR-03).** Open *CV clinic* (limit 3, 3 confirmed).
**Pass when:** it says "Full · waiting list open"; after the button the app shows "You are
number N on the waiting list" and no confirmed place is taken. Then press *Leave waiting list*
to clean up.

**TC-06 — lockout (NFR-02).** Log out, then log in as **`zhanel@kbtu.kz`** (never your own
account: it stays locked for 15 minutes). Enter a wrong password 5 times, then the correct
one. **Pass when:** the 6th attempt says the account is locked for 15 minutes; after 15
minutes the correct password works. Log out and back in as `madina@` afterwards.

### Re-check the fixed defects

* **D-01:** in `/docs`, open POST `/api/v1/communities/{community_id}/events` →
  *Responses*. 401, 403, 404, 413 and 422 must be listed with an example each, and 422 in our
  format (`{"error": ..., "detail": [...]}`). Then TC-08 again: the 403 you get must match
  the documented example. → *Closed* with the date.
* **D-02:** with the TestFlight build, the push in TC-01 shows the blue Qatys "Q" icon, not
  the Flutter logo. → *Closed* with the date.

If either is not fixed on the live system, keep it open and write what you saw.

### Where the results go

* Screenshots: `docs/team/madina/evidence/`, named `TC-08_403.png`, `TC-01_push.png`,
  `D-01_swagger.png`, … Blur anything private (lock-screen wallpaper, tokens).
* In the workbook: **Actual result**, **Status**, **Performed by** = "Madina", **Date**,
  **Evidence** = the file names. Then the RTM row of that requirement.
* Send Nurassyl a message with TC, actual result, Pass/Fail, date and file name for each run
  (the agent fills only what she sends).

### Explain it yourself

My artifact is the test run of TC-01…TC-08 with the RTM and the defect log. Every
requirement has at least one test case, and the RTM shows which test proves which
requirement. This week the test texts were updated where the requirement wording was
imprecise (U-01…U-04); the original wording stays in the sheet with the reason, so nothing
was silently rewritten. I ran TC-07 and TC-08 myself in Swagger against the live server and
the app cases on my iPhone, and set every status from what I saw. Two defects from my Week 10
run were fixed (D-01, D-02) and I re-checked them; D-03 stays open because free hosting
cannot carry 1000 users, and I can explain why. The AI agent prepared the sheet structure,
the defect log and these instructions; the results and the statuses are mine.

**Likely questions**

1. *Why did you change the test cases instead of the system?* — The system follows the
   agreed design (for example, the feed is ordered by deadline); the old text was written
   before that design. The PM approved each change and the original text is kept.
2. *Who ran the app tests?* — In Week 10 Nurassyl ran them on his iPhone and sent me the
   evidence; in Week 11 I ran them on my own phone. Every Pass in the RTM has a date and a
   screenshot.
3. *Why is TC-05 a Fail if the code is fast?* — The requirement is about the real system, and
   on the free hosting the server saturates at ~20 requests/s. On a laptop the same code
   meets it; the fix is a paid instance.
