#!/usr/bin/env bash
# Builds the TestFlight .ipa of Qatys against the live server (W11-2).
#
#   API_BASE_URL=https://qatys-api.onrender.com/api/v1 tool/build_ios_release.sh
#   tool/build_ios_release.sh --check     # every check, no version bump, no build
#
# Why a script and not Xcode's Product > Archive: without
# --dart-define=API_BASE_URL the app silently runs on mock data. The script
# also stops when tests fail, bumps the build number (TestFlight rejects a
# repeated one) and proves the push entitlement is "production".
# Upload the .ipa with Transporter or Xcode Organizer: docs/testflight.md.
set -euo pipefail

DEFAULT_API_BASE_URL="https://qatys-api.onrender.com/api/v1"
CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

cd "$(dirname "$0")/.."   # the qatys/ folder

fail() { printf '\n\033[31mSTOP:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------- 1. Server URL ----------
step "Server URL"
if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "API_BASE_URL is not set. Without it the build would run on DEMO DATA."
  echo "Default: $DEFAULT_API_BASE_URL"
  read -r -p "Build against the default? Type 'yes' to confirm: " answer
  [[ "$answer" == "yes" ]] || fail "set API_BASE_URL=https://<host>/api/v1 and run again"
  API_BASE_URL="$DEFAULT_API_BASE_URL"
fi
[[ "$API_BASE_URL" == https://*/api/v1 ]] \
  || fail "API_BASE_URL must look like https://<host>/api/v1 (got: $API_BASE_URL)"
echo "API_BASE_URL=$API_BASE_URL"

# ---------- 2. Firebase config belongs to this bundle id ----------
step "Bundle id and Firebase config"
bundle_id=$(grep -m1 -E 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;' ios/Runner.xcodeproj/project.pbxproj \
  | sed -E 's/.*= ([^;]+);.*/\1/')
plist=ios/Runner/GoogleService-Info.plist
[[ -f "$plist" ]] || fail "$plist is missing: download it from Firebase (iOS app $bundle_id)"
firebase_bundle=$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$plist")
[[ "$firebase_bundle" == "$bundle_id" ]] || fail "$plist is for '$firebase_bundle', the app is \
'$bundle_id'. Pushes would never arrive. Firebase > Project settings > Add app > iOS \
'$bundle_id', download the new GoogleService-Info.plist, upload the APNs key for it."
echo "bundle id $bundle_id, Firebase config matches"

# ---------- 3. Analyze and test ----------
step "flutter analyze"
flutter analyze || fail "flutter analyze found problems"
step "flutter test"
flutter test || fail "tests failed"

current=$(grep -m1 -E '^version: ' pubspec.yaml | sed -E 's/^version: //')
[[ "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]] \
  || fail "pubspec.yaml version must look like 1.0.0+3 (got: $current)"
name="${BASH_REMATCH[1]}"
build=$((BASH_REMATCH[2] + 1))

if $CHECK_ONLY; then
  step "Check only: all good. The next build would be $name+$build."
  exit 0
fi

# ---------- 4. Build number ----------
step "Build number $current -> $name+$build"
sed -i '' -E "s/^version: .*/version: $name+$build/" pubspec.yaml

# ---------- 5. Build ----------
step "flutter build ipa"
flutter build ipa --release --dart-define=API_BASE_URL="$API_BASE_URL"

ipa=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1)
[[ -n "$ipa" ]] || fail "no .ipa in build/ios/ipa"

# ---------- 6. Push entitlement of the built app ----------
step "Push entitlement"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -q "$ipa" -d "$tmp"
codesign -d --entitlements :- "$tmp"/Payload/*.app > "$tmp/entitlements.plist" 2>/dev/null
aps=$(plutil -extract aps-environment raw -o - "$tmp/entitlements.plist" 2>/dev/null || echo "missing")
echo "aps-environment = $aps"
[[ "$aps" == "production" ]] || fail "aps-environment is '$aps', not 'production': TestFlight \
phones would get no push. Check that the App Store distribution profile includes Push \
Notifications (Xcode > Runner > Signing & Capabilities)."

printf '\n\033[32mDone.\033[0m %s (version %s+%s, %s)\n' "$ipa" "$name" "$build" "$API_BASE_URL"
echo "Next: upload with Transporter (docs/testflight.md, step 3)."
