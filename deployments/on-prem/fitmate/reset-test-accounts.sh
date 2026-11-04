#!/usr/bin/env bash
# reset-test-accounts.sh — wipe social test accounts so a signup can be retried clean.
#
# WHY THIS EXISTS: Keycloak links a social login to an existing user BY EMAIL on first
# broker login. Once you have signed in with Google once, every later attempt with the same
# address takes the "account exists" path instead of the signup path, so the thing you are
# trying to test becomes unreachable. Deleting the user is the only way back to first-run.
#
# 🔴 DEFAULTS TO DRY RUN. It prints what it WOULD delete and exits. Pass --apply to act.
# 🔴 REFUSES to run against any realm whose name does not end in -dev.

set -euo pipefail

REALM="${REALM:-fitmate-dev}"
NS="${NS:-keycloak}"
POD="${POD:-keycloak-0}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/Projects/Infrastrutures/devops-tools/vagrant/vagrant-files/k3s/kubeconfig}"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

# Guard: never let this point at stg or prod. The whole script is a mass delete.
case "$REALM" in
  *-dev) ;;
  *) echo "REFUSING: realm '$REALM' is not a *-dev realm. This script mass-deletes users." >&2; exit 2 ;;
esac

KC="kubectl --kubeconfig $KUBECONFIG_PATH -n $NS exec $POD --"

PW=$(kubectl --kubeconfig "$KUBECONFIG_PATH" -n "$NS" get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d)
$KC /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password "$PW" >/dev/null

# KEEP LIST — accounts that must survive, or you lose your own fixtures and lock yourself out.
# service-account-* are CLIENT service accounts: deleting one silently breaks that client's
# machine-to-machine auth, and nothing will point at this script as the cause.
# EXPORTED deliberately: the python filters below read it via os.environ, and a plain
# assignment is invisible to a child process. Without the export this script dies with
# KeyError: 'KEEP_REGEX' — which is the safe failure, but still a failure.
# 🔴 THE (@|$) IS LOAD-BEARING. This realm sets registration_email_as_username = true, so a
# username IS an email address: the fixture is `trainee1@fitmate.local`, not `trainee1`.
# An earlier version anchored on `trainee1$` and the dry run listed every fixture for deletion
# — a keep-list that silently keeps nothing looks identical to one that works, right up until
# you pass --apply and lose the accounts you test with.
# 🔴 `admin(@|$)` NOT `admin1(@|$)`. The first run of this script deleted
# admin@fitmate.local because the keep-list named admin1 — one character off, and an
# off-by-one in a keep-list is invisible: the script reports a clean, successful run either
# way. Prefix-match the admin family rather than enumerating exact names.
export KEEP_REGEX="${KEEP_REGEX:-^(service-account-|admin|trainee1(@|$)|trainer1(@|$)|pilot\\.|qa\\.)}"

echo "realm:   $REALM"
echo "keeping: /$KEEP_REGEX/"
echo

USERS_JSON=$($KC /opt/keycloak/bin/kcadm.sh get users -r "$REALM" --query 'max=1000' 2>/dev/null)

TARGETS=$(printf '%s' "$USERS_JSON" | python3 -c "
import json,sys,re,os
keep = re.compile(os.environ['KEEP_REGEX'])
for u in json.load(sys.stdin):
    name = u.get('username') or ''
    if keep.search(name):
        continue
    print(u['id'], name, u.get('email') or '-')
")

COUNT=$(printf '%s' "$TARGETS" | grep -c . || true)

if [[ -z "$TARGETS" ]]; then echo "Nothing to delete."; exit 0; fi

printf '%s\n' "$TARGETS" | awk '{printf "  %-38s %-22s %s\n", $1, $2, $3}'
echo
# Print what is being KEPT as well. A keep-list that silently matches nothing produces the
# same confident output as one that works; showing both sides makes an off-by-one visible
# in the dry run instead of after --apply.
echo "KEEPING:"
printf '%s' "$USERS_JSON" | python3 -c "
import json,sys,re,os
keep = re.compile(os.environ['KEEP_REGEX'])
k=[u.get('username') or '' for u in json.load(sys.stdin) if keep.search(u.get('username') or '')]
print('\n'.join('  '+x for x in k) if k else '  (NOTHING — check KEEP_REGEX before --apply)')
"
echo

if [[ "$APPLY" -ne 1 ]]; then
  echo "DRY RUN — $COUNT user(s) would be deleted. Re-run with --apply to actually delete."
  exit 0
fi

echo "Deleting $COUNT user(s)..."
while read -r ID NAME EMAIL; do
  [[ -z "$ID" ]] && continue
  $KC /opt/keycloak/bin/kcadm.sh delete "users/$ID" -r "$REALM" >/dev/null 2>&1 \
    && echo "  deleted $NAME ($EMAIL)" \
    || echo "  FAILED  $NAME ($EMAIL)"
done <<< "$TARGETS"

# VERIFY BY PAYLOAD, not by the delete command exiting 0. A kcadm delete can report success
# while the user survives (wrong realm, stale session). Re-read and count.
echo
REMAIN=$($KC /opt/keycloak/bin/kcadm.sh get users -r "$REALM" --query 'max=1000' 2>/dev/null | python3 -c "
import json,sys,re,os
keep = re.compile(os.environ['KEEP_REGEX'])
print(sum(1 for u in json.load(sys.stdin) if not keep.search(u.get('username') or '')))
")
echo "VERIFY: $REMAIN deletable user(s) remain (expected 0)."
[[ "$REMAIN" == "0" ]] || { echo "🔴 Some users survived the delete — investigate before testing." >&2; exit 1; }
echo "Clean. A social login with any address will now take the FIRST-TIME signup path."

# NOTE — this clears KEYCLOAK ONLY. Profile rows in the trainee/trainer service databases are
# NOT touched, because they are keyed by their own ids and a dangling profile is harmless for
# a signup retry. If a test needs those gone too, that is a separate script against those DBs
# and it must not be bolted on here: one script that silently deletes across five databases is
# how a "test reset" becomes a production incident.
