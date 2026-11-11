# Nurkasymova Akbota — Architecture & Security

Her artifacts: [`docs/roles_and_architecture.xlsx`](../roles_and_architecture.xlsx) (roles
matrix, architecture, security decisions), [`docs/network-map.md`](../network-map.md) and the
security check script [`akbota/run_checks.sh`](akbota/run_checks.sh).

## Week 11

Prepared by the AI agent in Nurassyl's session (W11-7). **Akbota runs the script herself,
keeps the output, and reviews the map and the matrix.** The agent's own run is listed below
only so she can compare.

### Findings A-01…A-07 (security review of 4 November)

| ID | What, in plain words | Risk | Severity | Decision | Owner |
|---|---|---|---|---|---|
| A-01 | Anyone can register any `@kbtu.kz` address; nobody checks that the person owns the mailbox (no one-time code). Security decision 1 is only half done | Someone registers a classmate's address and acts in their name | Medium | Build the e-mail code **after** Gulnazym's three UI changes; if not done by Week 14, document it as a limitation. No code this week | Nurassyl |
| A-02 | The matrix said a guest may view announcements; the system asks for a login first | Matrix and system disagree, nothing unsafe | Low | Login stays required (BR-01). **Matrix changed**: Guest → No. No code change | Akbota |
| A-03 | The matrix gives the moderator six powers (approve admins, delete, block, statistics…); the system has a `is_moderator` column but no endpoint uses it | A promise the system does not keep; no moderation in an emergency | Medium | Planned **after the defence**. Matrix got an *Implemented* column that says so. No code this week | Nurassyl |
| A-04 | HTTP is redirected to HTTPS, but the server does not send the **HSTS** header that tells the browser "always use HTTPS" | The very first plain-HTTP request on public Wi-Fi could be intercepted | Low | Open; optional before the defence (one header) | Nurassyl |
| A-05 | Swagger (`/docs`) is open to everyone | Anyone sees the list of endpoints (not the data) | Info | **Accepted** for the demo: Swagger is the admin tool. Turn it off after the defence (`ENABLE_DOCS=false`) | Nurassyl |
| A-06 | The architecture sheet and the network map still described Android, Keystore, SMTP and file storage | Wrong documentation at the defence | Low | **Fixed this week** (matrix, architecture sheet, `network-map.md`) — waiting for Akbota's agreement | Akbota |
| A-07 | The Firebase config files of the app are in git | They are public by design (they identify the app, they are not keys); the server key is **not** in git | Info | Optional: restrict the Firebase API key to the app's bundle id in Google Cloud | Nurassyl |

### What changed in the matrix and why

* **Roles matrix:** "View public announcements" for **Guest → No (login required, BR-01)**
  (A-02). New column **Implemented** (Yes / No / After the defence) and a column **How it is
  now**, so the matrix shows both the design and the real system:
  * Yes — view, create an account (API), log in, publish (owner of a confirmed community),
    register, cancel own registration, nobody sees another student's e-mail;
  * No — edit / delete an announcement, block a user (no endpoint at all);
  * After the defence — every moderator power, subscribe, participant list, statistics,
    the admin request / approval flow (A-03).
* **Architecture:** the stack that is really deployed (Flutter on iPhone via TestFlight,
  FCM → APNs, FastAPI on Render, PostgreSQL 16 on Neon, JWT + bcrypt); the Week 4 proposal
  is kept in its own column. E-mail code: not implemented (A-01). File storage: not needed.
* **Security decisions:** a column *Checked by* that links every decision to the check that
  proves it (`run_checks.sh` S-01…S-09, data check C08, TC-06/07/08).
* **Network map:** push path **FCM → APNs → iPhone** (not Google Play services), token in the
  **iOS Keychain** (not the Android Keystore), Neon in Frankfurt, the `/admin`, `/docs` and
  `/data-checks` pages, and two failures with what the user sees (server asleep; push not
  allowed → no banner, no vibration). The "draft" line stays until Akbota agrees
  (`TODO(Akbota)`).

### Run the checks yourself

Needs a Mac or Linux Terminal (Windows: Git Bash). Nothing to install.

```bash
cd BIS-student-social-network          # the repository folder
bash docs/team/akbota/run_checks.sh
```

1. It wakes the server (up to a minute).
2. It asks for the **demo password** (see `server/README.md`); it is not shown or saved.
3. At the end it asks whether to run **S-09 lockout**. Answer `y` only when you want to show
   it: it locks **`zhanel@kbtu.kz`** for 15 minutes (never your own account). The demo phones
   are not affected.
4. It prints one line per check and saves every answer in `my_evidence/` (folder where you
   ran it). Keep that folder: it is your evidence. Running it twice is safe.

| ID | Security decision | What it does |
|---|---|---|
| S-01 | 7 HTTPS only | `http://` must answer 301 to `https://`; also reports the HSTS header (A-04) |
| S-02 | 5 checks on the server | 5 protected endpoints without a token → 401 |
| S-03 | 7 token | a forged token and an unsigned token → 401 |
| S-04 | 2 only confirmed admins publish | logs in as `aru@` (a student) and tries to publish → 403, nothing created |
| S-05 | 5 | a 70 KB body → 413 |
| S-06 | 5 | a foreign website gets no CORS permission |
| S-07 | 5 | broken JSON and an SQL injection attempt → short error code, no stack trace |
| S-08 | 3, 6 | no password or bcrypt hash in the login answer, the feed or the API schema |
| S-09 | 4 lockout | optional, see above → 423 with `retry_after_minutes` |

**Agent's run, 10 November 2026 (live server):** S-01…S-08 Pass, S-01b Info (no HSTS, A-04),
S-09 skipped on the live server; S-09 Pass on a local server (423, `retry_after_minutes = 15`,
twice in a row).

**Akbota's run:** `TODO(Akbota)` — date, the summary lines, the `my_evidence/` folder.

### Explain it yourself

My area is who may do what in the system and how the data travels safely. The roles matrix
now shows two things for every action: what the design allows and what the deployed system
really does, so the instructor sees honestly that moderator powers are planned after the
defence. The network map shows the real path of a push for the iPhone demo: our server sends
it to Firebase, Firebase hands it to Apple's push service, and Apple delivers it; the login
token stays in the iPhone's Keychain. I ran the security script against the live server: it
proves that HTTPS is forced, a token is required and cannot be forged, a student cannot
publish, large bodies and foreign websites are refused, errors show no stack trace and no
password ever comes back. The review found seven issues; two are medium (no e-mail code,
no moderator rights) and both have a decision and an owner. The AI agent wrote the script and
the first version of the documents; I ran the checks, reviewed the matrix and the map, and I
can explain each finding.

**Likely questions**

1. *Why is a missing e-mail code only "medium"?* — Only `@kbtu.kz` addresses are accepted and
   the password is still needed to log in, so an outsider cannot get in; the risk is a
   student registering a classmate's address. It is planned, with a deadline (Week 14).
2. *What happens if the JWT secret leaks?* — Anyone could forge a token for any student. We
   rotate `JWT_SECRET` on Render; all tokens become invalid and everyone logs in again.
3. *Why is Swagger public?* — It is our admin tool for the demo and shows only the list of
   endpoints, not data; every call still needs a token. We turn it off after the defence.
