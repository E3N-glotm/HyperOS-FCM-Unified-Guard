#!/bin/sh
# alpha12: root/TProxy TCP success must NOT authorize a GMS process restart.
# The probe must use the GMS UID and never issue active MCS heartbeat while
# healthy. Runs fully isolated; no GMS process or live firewall is changed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
export FCM_UNIFIED_RUNTIME="$T/run" TEST_TMP="$T"
mkdir -p "$T/run"
awk '/^# Polling and the event worker/{exit} {print}' "$ROOT/module/bin/fcm_guard.sh" \
  | sed "s|^MODDIR=.*|MODDIR=$ROOT/module|" > "$T/functions.sh"
. "$T/functions.sh"
cat > "$T/mockbb" <<'MOCK'
#!/bin/sh
[ "$1" = timeout ] || exit 72
shift 2
[ "$1" = su ] || exit 73
printf '%s\n' "$*" >> "$TEST_TMP/uid-probes.log"
[ "$TEST_TCP" = ok ]
MOCK
chmod 700 "$T/mockbb"
BB="$T/mockbb"
android_resolve_mtalk() { echo 74.125.142.188; }
gms_uid_for_probe() { echo 10139; }
run_timeout() { echo '    connected=mtalk.google.com/74.125.142.188,port=5228'; }
log_msg() { printf '%s\n' "$*" >> "$T/health-log"; }
TEST_TCP=fail
export TEST_TCP
# A root/TProxy route would appear healthy, but all UID-bound probes fail.
got=$(fcm_path_ready || true)
[ -z "$got" ] || { echo "FAIL: root-only route incorrectly authorized a restart: $got"; exit 1; }
[ "$(wc -l < "$T/uid-probes.log" | tr -d ' ')" -eq 3 ] || { echo 'FAIL: did not try UID-bound ports 5228-5230'; exit 1; }
grep -q '10139 -c /system/bin/toybox nc' "$T/uid-probes.log" || { echo 'FAIL: probe not bound to GMS UID'; exit 1; }
TEST_TCP=ok
export TEST_TCP
got=$(fcm_path_ready)
[ "$got" = 'gms-uid 74.125.142.188 5228' ] || { echo "FAIL: UID network success misreported: $got"; exit 1; }
previous=$(wc -l < "$T/uid-probes.log" | tr -d ' ')
KEEPALIVE_FILE="$T/run/fcm_keepalive.epoch"
connected_keepalive 4000
[ "$KEEPALIVE_PROBED" = 0 ] || { echo 'FAIL: passive check triggered extra GMS read'; exit 1; }
[ "$(wc -l < "$T/uid-probes.log" | tr -d ' ')" -eq "$previous" ] || { echo 'FAIL: healthy state made an active network probe'; exit 1; }
body=$(sed -n '/^connected_keepalive() {/,/^}/p' "$ROOT/module/bin/fcm_guard.sh")
if printf '%s\n' "$body" | grep -Eq 'am broadcast| -a com.google.android.intent.action.MCS_HEARTBEAT'; then
  echo 'FAIL: healthy state still forces MCS_HEARTBEAT'
  exit 1
fi
echo 'PASS alpha12: UID-bound 5228 route proof; root false-positive blocked; passive health checks only'
