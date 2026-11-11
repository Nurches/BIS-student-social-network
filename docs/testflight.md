# TestFlight — install Qatys on the demo iPhones

**Audience:** Nurassyl (owner of the Apple account) and the members whose phones are used
in the demo: phone B = Madina, phone C = Laila.
**Decision (Week 11):** the demo runs on iPhones only, installed through TestFlight. Internal
testing needs **no Beta App Review**: a build is usually installable 10–30 minutes after
the upload.

| | |
|---|---|
| App Store Connect app | **Qatys**, bundle id **`com.qatys.app`** (the iOS app; Android stays `kz.kbtu.qatys`) |
| Apple team | `WCY9BRVPYB` |
| Internal testing group | **UniHub demo** |
| Build script | `qatys/tool/build_ios_release.sh` |
| Server | `https://qatys-api.onrender.com/api/v1` |

---

## 0. One time: Firebase for `com.qatys.app`

The bundle id changed from `kz.kbtu.qatys` to `com.qatys.app` in Week 11, because the App
Store Connect record was created with it. Firebase must know the new id, or pushes never
arrive.

1. Firebase console → project **qatys** → ⚙ **Project settings** → **Add app** → **iOS** →
   bundle id `com.qatys.app`, nickname `Qatys iOS`. Skip the SDK steps.
2. Download **`GoogleService-Info.plist`** and replace `qatys/ios/Runner/GoogleService-Info.plist`.
3. Project settings → **Cloud Messaging** → **Apple app configuration** → app `com.qatys.app`
   → **APNs Authentication Key → Upload**: the same `.p8` key (Key ID `B34K2VPKF8`, Team ID
   `WCY9BRVPYB`). The key works for every app of the team.
4. The server needs no change: it sends through the same Firebase project.

The build script checks that the plist belongs to `com.qatys.app` and stops otherwise.

## 1. One time: the app record

Already done: **App Store Connect → Apps → Qatys** (`com.qatys.app`).
If Xcode ever asks: Signing & Capabilities → Team `WCY9BRVPYB`, **Automatically manage
signing** on, capability **Push Notifications** present.

## 2. Build the .ipa

```bash
cd qatys
API_BASE_URL=https://qatys-api.onrender.com/api/v1 tool/build_ios_release.sh
```

The script:

1. refuses to run without `API_BASE_URL` (or asks you to type `yes` for the default);
2. checks that `GoogleService-Info.plist` belongs to the app's bundle id;
3. runs `flutter analyze` and `flutter test` and stops on any failure;
4. increases the build number in `pubspec.yaml` (`1.0.0+1` → `1.0.0+2`): TestFlight rejects a
   number it has seen. **Commit this change** after the upload;
5. runs `flutter build ipa --release --dart-define=API_BASE_URL=...`;
6. prints the `.ipa` path and the app's `aps-environment`, and stops if it is not
   `production`.

Dry run without building: `tool/build_ios_release.sh --check`.

**Never archive from Xcode's menu** (Product → Archive): without the `--dart-define` the app
runs on demo data. Such a build shows a red **"DEMO DATA — not connected to the server"**
strip on every screen, so you would notice, but you would have to upload again.

## 3. Upload

**Transporter** (Mac App Store, free): sign in with the Apple ID → drag
`qatys/build/ios/ipa/qatys.ipa` → **Deliver**.

Or **Xcode → Window → Organizer → Archives** → the newest `Runner` archive (the script made
it in `build/ios/archive/Runner.xcarchive`) → **Distribute App → App Store Connect → Upload**.

Then App Store Connect → Qatys → **TestFlight**: the build shows **Processing** for 5–30
minutes, then **Ready to Submit / Testing**.

## 4. Add Madina and Laila as internal testers

Internal testers must be users of the App Store Connect team.

1. App Store Connect → **Users and Access** → **＋** → first name, last name, **the Apple ID
   e-mail they use on their iPhone**, role **Developer** (or **Marketing**) → **Invite**.
2. They open the e-mail **"You've been invited to join … App Store Connect"** and accept it
   (sign in with that Apple ID, no payment).
3. App Store Connect → Qatys → **TestFlight** → **Internal Testing** → **＋** → group
   **UniHub demo** → **Testers ＋** → tick Madina, Laila and yourself → **Add**.
4. In the group: **Builds ＋** → pick the new build. Turn on **Automatic distribution**, so the
   next builds reach the group without this step.

## 5. On each phone (A, B, C)

1. Install **TestFlight** from the App Store.
2. Open the invite e-mail **"Qatys is ready to test"** on the phone → **View in TestFlight** →
   **Install**. (No e-mail: TestFlight → the app appears in the list when you are signed in
   with the invited Apple ID.)
3. If an older Qatys from Xcode is installed, **delete it first**: iOS caches icons, and a
   development build gets pushes through a different APNs server.
4. Open **Qatys** → log in (`madina@kbtu.kz` / `laila@kbtu.kz` / `nurassyl@kbtu.kz`, password
   from the owner) → **Turn on** in the app's question → **Allow** in the iOS question.
5. Settings → Notifications → **Qatys**: Allow Notifications on, Sounds on, Banners on.
6. **Test push:** the owner publishes an event from `https://qatys-api.onrender.com/admin` in
   community 2. All three phones show the push **with the Qatys icon**. Tap → the event opens.

## 6. Known problems

| Symptom | Cause | Fix |
|---|---|---|
| Build stuck in **Processing** for over an hour | Apple's queue | Wait; if over 2 h, upload again with the next build number |
| **Missing Compliance** next to the build | Export compliance question | `ITSAppUsesNonExemptEncryption = false` is in `Info.plist`, so it should not appear. If it does: **Manage** → "None of the algorithms mentioned above" |
| Upload refused: "bundle version must be higher" | Same build number twice | Run the script again: it increases the number |
| Upload refused: wrong bundle id | Archive made from an old checkout | Check `PRODUCT_BUNDLE_IDENTIFIER = com.qatys.app` and build again |
| Tester gets **no invite** | Not accepted as an App Store Connect user yet, or other Apple ID | Users and Access → check the status is not "Invitation pending"; the e-mail must be the Apple ID of the phone |
| TestFlight says "not available" | The build is not in the group | Internal Testing → UniHub demo → Builds ＋ |
| **No push** on a TestFlight phone | Plist from `kz.kbtu.qatys`, APNs key not uploaded for `com.qatys.app`, or notifications not allowed | Step 0; iPhone Settings → Notifications → Qatys; log out and in again (sends the token) |
| No push after a reseed | `seed.py` deleted every device token | Log out and log in on every phone (`docs/demo-runbook.md`) |
| Red **DEMO DATA** strip on the screen | Built without `API_BASE_URL` | Build with the script |
| Icon is the old Flutter logo | iOS icon cache | Delete the app, restart the phone, install again |

TestFlight builds expire after **90 days**: a build uploaded in Week 11 is valid through the
defence.
