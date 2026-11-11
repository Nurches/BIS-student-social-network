# Deployment — run Qatys from zero

**Audience:** a team member who did not write the code (roadmap M6: Laila or Akbota executes
this on their own laptop as evidence). Every step is copy-paste. Time: about 1 hour, most of
it waiting for sign-ups and the first deploy.

**What you get:** the API on Render, the database on Neon, pushes through Firebase and Apple
(APNs), and the iPhone app installed through TestFlight.

```
iPhone (Qatys, TestFlight) ──HTTPS──▶ Render: FastAPI ──TLS──▶ Neon: PostgreSQL 16
        ▲                                   │
        └── APNs (Apple) ◀── Firebase Cloud Messaging ◀── push on publish
```

**Dry run, 10 November 2026 (W11-5):** sections 1 and "Run the API on your laptop" were run
from a fresh clone with a new virtual environment and an empty database: the seed and the
API (`/api/v1/health`, `/data-checks`) worked. Fixed after the run: how to get Python 3.12,
Windows commands, the `--live` switch of the seed, the iPhone instead of the Android APK.

---

## 0. Accounts and tools

| Need | Where | Cost |
|---|---|---|
| GitHub access to `Nurches/BIS-student-social-network` | ask Nurassyl | free |
| Neon account | https://neon.tech | free tier |
| Render account (sign in with GitHub) | https://render.com | free tier |
| Firebase project (owner: Nurassyl) | https://console.firebase.google.com | free (Spark) |
| Git | https://git-scm.com | free |
| **Python 3.12** (not 3.13, not 3.11) | see below | free |
| Only to build the iPhone app: a Mac with Xcode + Flutter SDK, Apple Developer team | owner only | — |

**Python 3.12.** Check with `python3.12 --version` (Windows: `py -3.12 --version`). If it is
missing:

* **Mac:** install "Python 3.12" from https://www.python.org/downloads/ (macOS 64-bit
  universal2 installer), or `brew install python@3.12`. Open a **new** Terminal afterwards.
* **Windows:** install "Python 3.12" from https://www.python.org/downloads/ and tick **"Add
  python.exe to PATH"**. Use **Git Bash** or PowerShell for the commands below.

**Why Neon and not Render Postgres:** a free Render database is deleted 30 days after it is
created (Render's policy at the time of writing). Created in Week 10, it would disappear right
before the Week 15 defence. Neon's free database does not expire.

---

## 1. Database on Neon

1. Neon → **New project** → name `qatys`, Postgres **16**, region **Frankfurt (eu-central-1)**.
2. Copy the connection string (**Connection details → Pooled connection off**). It looks like
   `postgresql://neondb_owner:...@ep-xxx.eu-central-1.aws.neon.tech/neondb?sslmode=require`.
   It contains the password: never commit it or paste it in a chat.
3. Fill it with the schema and the demo data from your laptop.

Mac / Linux / Git Bash:

```bash
git clone https://github.com/Nurches/BIS-student-social-network.git
cd BIS-student-social-network/server
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL='postgresql://...neon.tech/neondb?sslmode=require'
export JWT_SECRET=not-used-by-seed-but-required-32chars
python seed.py --yes --live
```

Windows PowerShell (the same steps):

```powershell
git clone https://github.com/Nurches/BIS-student-social-network.git
cd BIS-student-social-network\server
py -3.12 -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:DATABASE_URL = 'postgresql://...neon.tech/neondb?sslmode=require'
$env:JWT_SECRET = 'not-used-by-seed-but-required-32chars'
python seed.py --yes --live
```

The seed prints the target, then asks you to **type the database name** (`neondb`), because
it deletes every table. Expected at the end:
`Seeded 10 students, 5 communities, 8 events. Admin: union@kbtu.kz`.

For a database on your own laptop (`localhost`), `--yes` is enough. Re-seeding the shared
live database deletes everybody's test data and phone tokens: follow
[`demo-runbook.md`](demo-runbook.md), section 1, first.

### Run the API on your laptop (optional, 2 minutes)

With the same terminal (variables still set; for a fully local setup see `server/README.md`):

```bash
uvicorn app.main:app --port 8000
# another terminal:
curl http://localhost:8000/api/v1/health      # {"status":"ok"}
```

Open http://localhost:8000/docs (Swagger) and http://localhost:8000/data-checks. Stop with
Ctrl+C.

## 2. Firebase (push)

Done once by the project owner; the others only need the result.

1. Firebase console → **Add project** `qatys` (Analytics off).
2. **Add app → iOS**, bundle id **`com.qatys.app`** (must match exactly). Download
   `GoogleService-Info.plist` → `qatys/ios/Runner/GoogleService-Info.plist`. Then **Project
   settings → Cloud Messaging → Apple app configuration → APNs Authentication Key → Upload**
   the team's `.p8` key (Key ID and Team ID from the Apple Developer account). Details:
   [`testflight.md`](testflight.md), section 0.
3. Android (configured, not demoed): **Add app → Android**, package name `kz.kbtu.qatys`;
   `google-services.json` → `qatys/android/app/google-services.json`.
4. **Project settings → Service accounts → Generate new private key**. A JSON file downloads.
   It is a secret: never commit it, never send it in a chat. Turn it into one line:

```bash
python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))" ~/Downloads/qatys-*.json
```

## 3. API on Render

1. Render → **New → Blueprint** → pick the repository. Render reads `render.yaml`.
2. It asks for two values:
   * `DATABASE_URL` — the Neon string from step 1;
   * `FCM_SERVICE_ACCOUNT_JSON` — the one-line JSON from step 2 (leave empty to run without push).
   `JWT_SECRET` is generated by Render automatically.
3. **Apply**. The first build takes 3–5 minutes. The service URL looks like
   `https://qatys-api.onrender.com`.
4. Check:

```bash
curl https://qatys-api.onrender.com/api/v1/health
# {"status":"ok"}
```

Swagger UI: `https://qatys-api.onrender.com/docs` · admin page: `/admin` · data checks: `/data-checks`.

**Data checks page** (`docs/tools/data-checks-spec.md`): `DATA_CHECK_EMAILS` (in `render.yaml`)
lists who may run it. `DATABASE_URL_READONLY` is optional. Leave it empty and the checks use
`DATABASE_URL` inside a READ ONLY transaction. To use a read-only database role as a second
line of defence, create it once with `docs/team/setup/readonly_role.sql` and set
`DATABASE_URL_READONLY` to its connection string; `seed.py` grants it access again after
every reseed.

**Free tier sleeps** after 15 minutes without traffic; the first request then takes 30–60 s.
Open `/api/v1/health` one minute before any demo (roadmap §7, step 1).

## 4. iPhone app (TestFlight)

Built by the owner on a Mac and installed on the demo phones through TestFlight:
**[`testflight.md`](testflight.md)** (build script `qatys/tool/build_ios_release.sh`, upload,
testers, per-phone steps).

Android is configured (`kz.kbtu.qatys`) but not a deliverable. If ever needed:
`flutter build apk --release --dart-define=API_BASE_URL=https://qatys-api.onrender.com/api/v1`
(signing key in `qatys/android/key.properties`, never in git). Android pushes are untested.

## 5. Check the whole process

Follow [`demo-runbook.md`](demo-runbook.md): reseed order, the three phones, the 5-minute demo
script and the backup video. In short:

1. Phones A, B, C have Qatys from TestFlight; log in as `nurassyl@`, `madina@`, `laila@kbtu.kz`
   (demo password from the owner); allow notifications.
2. Laptop: `https://qatys-api.onrender.com/admin` → sign in as `union@kbtu.kz` → publish
   "Career Day" in community **2** with **2** places.
3. Phone A vibrates → tap → event → **Register** → *Registered ✓*.
4. Show the rows in Neon (**SQL Editor**):

```sql
SELECT s.email, r.status, r.updated_at FROM registration r
JOIN student s USING (student_id) ORDER BY r.updated_at DESC LIMIT 5;

SELECT s.email, n.kind, n.sent_at FROM notification n
JOIN student s USING (student_id) ORDER BY n.notification_id DESC LIMIT 10;
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `python3.12: command not found` | Python 3.12 not installed, or an old Terminal | Section 0; open a new Terminal |
| `/health` answers 503 | wrong `DATABASE_URL`, or Neon project suspended | check the string, open the Neon console once |
| Render build fails on `JWT_SECRET` | variable missing | Render → Environment → generate a value (≥ 32 chars) |
| App says "No connection to the server" | API asleep, or the phone is on a Wi-Fi login page | open `/api/v1/health` in the phone's browser |
| Red **DEMO DATA** strip in the app | built without `API_BASE_URL` | build with `qatys/tool/build_ios_release.sh` |
| No push, `notification.sent_at` stays empty | `FCM_SERVICE_ACCOUNT_JSON` empty or from another project | Render logs show `FCM not configured` or the FCM error |
| `sent_at` is set but the iPhone shows nothing | notifications not allowed, or the APNs key / `GoogleService-Info.plist` is for another bundle id | iPhone Settings → Notifications → Qatys; `testflight.md` section 0 |
| No push after a reseed | the reseed deleted the push tokens | log out and log in on every phone |
| `seed.py` refuses to run | safety switch | `--yes` for a local database; `--yes --live` and the database name for Neon |
| Data checks: `permission denied` after a reseed | read-only role lost its grants | set `DATABASE_URL_READONLY` when running `seed.py` (it re-grants), or run `readonly_role.sql` again |
