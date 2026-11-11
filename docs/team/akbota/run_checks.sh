#!/usr/bin/env bash
# Qatys security checks against the live API — Akbota Nurkasymova (Architecture & Security).
#
#   bash docs/team/akbota/run_checks.sh                 # live server
#   API=http://localhost:8000 bash docs/team/akbota/run_checks.sh
#
# Read only and safe to run twice: nothing is created or changed, except the
# optional lockout check, which locks zhanel@kbtu.kz (and only her) for 15 minutes.
# The demo password is asked at run time and never stored or printed.
# One line per check: ID | security decision | Pass/Fail/Info | evidence.
# Full answers are saved in my_evidence/ next to where you run the script.
set -u

API="${API:-https://qatys-api.onrender.com}"
STUDENT="aru@kbtu.kz"        # a student who is NOT a community admin
LOCK_ACCOUNT="zhanel@kbtu.kz" # the only account the lockout check may lock
OUT="my_evidence"
mkdir -p "$OUT"
RESULTS=()

# Forged on purpose: signed with a wrong key, and unsigned (alg=none). Both must be refused.
FORGED=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMCIsImlhdCI6MTc5MzgwMDAwMCwiZXhwIjoxOTI0OTkyMDAwfQ.oKjN1jk3TrN4kfMCZOuGGj-z1P3XwDIQtErTP3byNng
UNSIGNED=eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMCIsImV4cCI6MTkyNDk5MjAwMH0.

result() { # result <id> <decision> <Pass|Fail|Info> <evidence>
  RESULTS+=("$(printf '%-5s | %-34s | %-4s | %s' "$1" "$2" "$3" "$4")")
}
save() { # save <file> <title>  (stdin = content)
  { echo "# $2"; echo "# $API — $(date '+%Y-%m-%d %H:%M:%S %Z')"; echo; cat; } > "$OUT/$1"
}
call() { # call <method> <path> [curl args...]  -> prints "<body> <status>"
  local method=$1 path=$2; shift 2
  curl -s -m 30 -w ' %{http_code}' -X "$method" "$@" "$API$path"
}
status_of() { echo "${1##* }"; }
body_of() { echo "${1% *}"; }
json_field() { # json_field <json> <field>  (no python needed)
  echo "$1" | sed -nE "s/.*\"$2\" *: *\"?([^\",}]*)\"?.*/\1/p"
}

echo "Qatys security checks against $API"
echo "Waking the server (up to 1 minute)..."
curl -s -m 70 "$API/api/v1/health" > /dev/null
read -r -s -p "Demo password (seeded accounts, see server/README.md): " PASSWORD; echo

# ---------- S-01 HTTPS only (decision 7) ----------
if [[ "$API" == https://* ]]; then
  http_url="http://${API#https://}/api/v1/health"
  head=$(curl -s -m 20 -o /dev/null -D - "$http_url")
  echo "$head" | save S-01_https_only.txt "Plain HTTP is redirected to HTTPS"
  code=$(echo "$head" | awk 'NR==1{print $2}')
  location=$(echo "$head" | grep -i '^location:' | tr -d '\r' | awk '{print $2}')
  if [[ "$code" =~ ^30[178]$ && "$location" == https://* ]]; then
    result S-01 "7: HTTPS only" Pass "http -> $code $location"
  else
    result S-01 "7: HTTPS only" Fail "http answered $code without a redirect to https"
  fi
  if curl -s -m 20 -o /dev/null -D - "$API/api/v1/health" | grep -qi '^strict-transport-security'; then
    result S-01b "7: HSTS header (A-04)" Pass "strict-transport-security present"
  else
    result S-01b "7: HSTS header (A-04)" Info "no strict-transport-security header (finding A-04, open)"
  fi
else
  result S-01 "7: HTTPS only" Info "local http API, skipped"
fi

# ---------- S-02 a token is required (decision 5) ----------
fails=0; lines=""
for p in "GET /api/v1/feed" "GET /api/v1/events/1" "POST /api/v1/events/1/registrations" \
         "POST /api/v1/communities/1/events" "GET /api/v1/admin/data-checks"; do
  set -- $p
  answer=$(call "$1" "$2" -H 'Content-Type: application/json' -d '{}')
  lines+="$1 $2 -> $answer"$'\n'
  [[ "$(status_of "$answer")" == 401 && "$answer" == *'"unauthorized"'* ]] || fails=$((fails + 1))
done
echo -n "$lines" | save S-02_token_required.txt "Protected endpoints without a token answer 401"
[[ $fails == 0 ]] && result S-02 "5: token required" Pass "5 of 5 endpoints -> 401 unauthorized" \
                  || result S-02 "5: token required" Fail "$fails endpoint(s) did not answer 401"

# ---------- S-03 forged tokens are refused (decision 7) ----------
a=$(call GET /api/v1/feed -H "Authorization: Bearer $FORGED")
b=$(call GET /api/v1/feed -H "Authorization: Bearer $UNSIGNED")
printf 'wrong key -> %s\nalg=none  -> %s\n' "$a" "$b" | save S-03_forged_token.txt "Forged tokens answer 401"
[[ "$(status_of "$a")" == 401 && "$(status_of "$b")" == 401 ]] \
  && result S-03 "7: token cannot be forged" Pass "wrong key -> 401, alg=none -> 401" \
  || result S-03 "7: token cannot be forged" Fail "wrong key -> $(status_of "$a"), alg=none -> $(status_of "$b")"

# ---------- S-04 a student cannot publish (decision 2, BR-01) ----------
login=$(call POST /api/v1/auth/login -H 'Content-Type: application/json' \
        -d "{\"email\":\"$STUDENT\",\"password\":\"$PASSWORD\"}")
token=$(json_field "$(body_of "$login")" token)
if [[ -z "$token" ]]; then
  result S-04 "2: only confirmed admins publish" Fail "could not log in as $STUDENT ($(status_of "$login"))"
else
  publish=$(call POST /api/v1/communities/1/events -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d '{"title":"Security check S-04","starts_at":"2030-01-02T10:00:00+05:00","registration_deadline":"2030-01-01T10:00:00+05:00","participant_limit":1}')
  echo "POST /api/v1/communities/1/events as $STUDENT -> $publish" | save S-04_student_publish.txt "A student cannot publish"
  [[ "$(status_of "$publish")" == 403 && "$publish" == *'"not_a_confirmed_admin"'* ]] \
    && result S-04 "2: only confirmed admins publish" Pass "student -> 403 not_a_confirmed_admin, nothing created" \
    || result S-04 "2: only confirmed admins publish" Fail "student got $(status_of "$publish")"
fi

# ---------- S-05 body size limit (hardening) ----------
big="$OUT/.big.json"
{ printf '{"email":"x@kbtu.kz","password":"'; head -c 70000 /dev/zero | tr '\0' a; printf '"}'; } > "$big"
answer=$(call POST /api/v1/auth/login -H 'Content-Type: application/json' --data-binary @"$big")
rm -f "$big"
echo "70 KB body -> $answer" | save S-05_body_limit.txt "A 70 KB body is refused"
[[ "$(status_of "$answer")" == 413 ]] && result S-05 "5: 64 KB body limit" Pass "70 KB -> 413 payload_too_large" \
                                      || result S-05 "5: 64 KB body limit" Fail "70 KB -> $(status_of "$answer")"

# ---------- S-06 CORS closed (hardening) ----------
cors=$(curl -s -m 20 -i -X OPTIONS -H 'Origin: https://evil.example' \
       -H 'Access-Control-Request-Method: GET' "$API/api/v1/feed" | grep -i -E '^HTTP|access-control')
echo "$cors" | save S-06_cors.txt "A foreign website gets no CORS permission"
echo "$cors" | grep -qi 'access-control-allow-origin' \
  && result S-06 "5: CORS closed" Fail "access-control-allow-origin sent to a foreign site" \
  || result S-06 "5: CORS closed" Pass "no access-control-allow-origin for https://evil.example"

# ---------- S-07 no stack trace in errors (decision 5) ----------
m=$(call POST /api/v1/auth/register -H 'Content-Type: application/json' -d '{bad json')
s=$(call POST /api/v1/auth/login -H 'Content-Type: application/json' \
    -d "{\"email\":\"x'OR'1'='1'--@kbtu.kz\",\"password\":\"not-a-password\"}")
printf 'malformed JSON -> %s\nSQL injection  -> %s\n' "$m" "$s" | save S-07_errors.txt "Errors without a stack trace"
if [[ "$m$s" == *Traceback* || "$m$s" == *'File "'* || "$m$s" == *psycopg* ]]; then
  result S-07 "5: no stack trace in errors" Fail "a server detail leaked (see S-07_errors.txt)"
else
  result S-07 "5: no stack trace in errors" Pass "malformed -> $(status_of "$m"), injection -> $(status_of "$s"); short codes only"
fi

# ---------- S-08 a password never comes back (decisions 3 and 6) ----------
schema=$(curl -s -m 30 "$API/openapi.json")
leaks=""
if [[ -n "$token" ]]; then
  feed=$(call GET /api/v1/feed -H "Authorization: Bearer $token")
  for body in "$(body_of "$login")" "$(body_of "$feed")"; do
    [[ "$body" == *'"password'* || "$body" == *'$2b$'* ]] && leaks+="response "
  done
fi
echo "$schema" | grep -q '"password_hash"' && leaks+="openapi "
{ echo "login response keys: $(body_of "$login" | grep -oE '"[a-z_]+":' | sort -u | tr '\n' ' ')"
  echo "password or bcrypt hash found in: ${leaks:-nothing}"; } | save S-08_no_password.txt "No password in any answer"
[[ -z "$leaks" ]] && result S-08 "3, 6: password never returned" Pass "login, feed and API schema contain no password or hash" \
                  || result S-08 "3, 6: password never returned" Fail "found in: $leaks"

# ---------- S-09 lockout after 5 failed logins (decision 4) — optional ----------
echo
echo "S-09 checks the lockout: it LOCKS $LOCK_ACCOUNT for 15 minutes (never your own account)."
read -r -p "Run it now? [y/N] " answer
if [[ "$answer" =~ ^[yY]$ ]]; then
  lines=""
  for i in 1 2 3 4 5; do
    r=$(call POST /api/v1/auth/login -H 'Content-Type: application/json' \
        -d "{\"email\":\"$LOCK_ACCOUNT\",\"password\":\"wrong-password-$i\"}")
    lines+="wrong password $i -> $r"$'\n'
  done
  r=$(call POST /api/v1/auth/login -H 'Content-Type: application/json' \
      -d "{\"email\":\"$LOCK_ACCOUNT\",\"password\":\"$PASSWORD\"}")
  lines+="correct password -> ${r//\"token\":\"*\"/\"token\":\"<hidden>\"}"$'\n'
  echo -n "$lines" | save S-09_lockout.txt "Lockout after 5 failed logins"
  if [[ "$(status_of "$r")" == 423 && "$r" == *retry_after_minutes* ]]; then
    result S-09 "4: lockout 15 min after 5 failures" Pass "correct password after 5 failures -> 423, retry_after_minutes=$(json_field "$(body_of "$r")" retry_after_minutes)"
  else
    result S-09 "4: lockout 15 min after 5 failures" Fail "correct password after 5 failures -> $(status_of "$r")"
  fi
else
  result S-09 "4: lockout 15 min after 5 failures" Info "skipped by the user"
fi
unset PASSWORD token

echo
echo "ID    | Security decision                  | Res. | Evidence"
echo "------+------------------------------------+------+---------------------------------------"
printf '%s\n' "${RESULTS[@]}" | tee "$OUT/summary.txt"
echo
echo "Saved in $OUT/ (summary.txt and one file per check)."
