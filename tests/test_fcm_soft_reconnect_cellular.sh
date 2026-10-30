#!/bin/sh
# Real shell control flow: a scheduled but deferred GCM reconnect alarm must
# permit bounded native soft recovery when Android DNS works, even if the raw
# 5228 path probe fails. Never restart GMS for this incident.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
export FCM_UNIFIED_RUNTIME="$T/run" TEST_BROADCAST="$T/broadcasts.log"
mkdir -p "$T/run"
: > "$TEST_BROADCAST"
awk '/^# Polling and the event worker/{exit} {print}' "$ROOT/module/bin/fcm_guard.sh" \
  | sed "s|^MODDIR=.*|MODDIR=$ROOT/module|" > "$T/functions.sh"
. "$T/functions.sh"

cat > "$T/mockbb" <<'MOCK'
#!/bin/sh
[ "$1" = timeout ] || exit 4
shift 2
[ "$1" = am ] || exit 5
printf '%s\n' "$*" >> "$TEST_BROADCAST"
exit 0
MOCK
chmod 700 "$T/mockbb"
BB=$T/mockbb
TEST_DNS=fail
TEST_SCHEDULER=scheduled
gcm_reconnect_scheduler_state() { printf '%s\n' "$TEST_SCHEDULER"; }
android_resolve_mtalk() {
  [ "$TEST_DNS" = ok ] && { echo 142.250.99.188; return 0; }
  return 1
}
fcm_path_ready() {
  echo 'FAIL: raw TCP path probe must not block safe soft reconnect' >&2
  exit 99
}
fcm_state() { echo disconnected; }
run_timeout() { :; }
sleep() { :; }
log_msg() { printf '%s\n' "$*" >> "$T/guard.log"; }
count() { wc -l < "$TEST_BROADCAST" | tr -d ' '; }

soft_reconnect_if_stalled 1000 599 >/dev/null 2>&1 && exit 21 || :
[ "$(count)" = 0 ] || { echo 'broadcast before 10 minutes' >&2; exit 1; }

soft_reconnect_if_stalled 1000 600 >/dev/null 2>&1 && exit 22 || :
[ "$(count)" = 0 ] || { echo 'broadcast despite bad DNS' >&2; exit 1; }

TEST_DNS=ok
soft_reconnect_if_stalled 1000 600 >/dev/null 2>&1 && exit 23 || :
[ "$(count)" = 1 ] || { echo 'failed to send soft reconnect with DNS OK' >&2; exit 1; }
grep -q 'GCM_RECONNECT' "$TEST_BROADCAST"
[ "$(cat "$SOFT_RECONNECT_FILE")" -eq 1000 ]

soft_reconnect_if_stalled 1300 900 >/dev/null 2>&1 && exit 24 || :
[ "$(count)" = 1 ] || { echo 'soft reconnect bypassed 15m cooldown' >&2; exit 1; }

soft_reconnect_if_stalled 1901 1500 >/dev/null 2>&1 && exit 25 || :
[ "$(count)" = 2 ] || { echo 'soft retry after 15m did not occur' >&2; exit 1; }

# The old overdue and missing-alarm paths remain independent of the
# scheduled-alarm DNS check. They only act after their own age/cooldown.
TEST_DNS=fail
TEST_SCHEDULER=missing
soft_reconnect_if_stalled 2302 300 >/dev/null 2>&1 && exit 26 || :
[ "$(count)" = 3 ] || { echo 'missing-alarm fallback regressed' >&2; exit 1; }
grep -q 'scheduled-alarm-stalled-dns-ok' "$T/guard.log"
if grep -Eq 'kill -TERM|iptables|setuiddnsrule' "$TEST_BROADCAST"; then
  echo 'dangerous operation during soft reconnect' >&2
  exit 1
fi
echo 'PASS: stalled cellular MCS soft reconnect at 10m, DNS validated, 15m cooldown, no 5228 dependency or GMS restart'
