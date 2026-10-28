#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GUARD="$ROOT/module/bin/fcm_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

grep -q 'acquire_guard_lock || exit 0' "$GUARD" \
  || fail "FCM guard is not serialized"
grep -q 'recent_gms_unknown_host_epoch' "$GUARD" \
  || fail "GMS UNKNOWN_HOST evidence is not inspected"
grep -q 'android_resolve_mtalk' "$GUARD" \
  || fail "Android resolver path is not checked"
grep -q 'flush_android_dns' "$GUARD" \
  || fail "DNS remediation is missing"
grep -q 'IPTABLES_WAIT_SECONDS=5' "$GUARD" \
  || fail "iptables lock wait is missing"
grep -q 'iptables -w "$IPTABLES_WAIT_SECONDS" -t mangle -S BOX_LOCAL' "$GUARD" \
  || fail "FCM bypass reads do not wait for the xtables lock"
grep -q 'installed missing Box FCM-only bypass' "$GUARD" \
  || fail "FCM bypass self-heal is missing"
grep -q 'box_manages_fcm_bypass' "$GUARD" \
  || fail "native Box rule ownership is not detected"
grep -q 'connected_keepalive' "$GUARD" \
  || fail "connected-but-stale MCS liveness probe is missing"
grep -q 'KEEPALIVE_INTERVAL=900' "$GUARD" \
  || fail "MCS proactive heartbeat interval must remain 15 minutes"
grep -q 'com.google.android.intent.action.MCS_HEARTBEAT' "$GUARD" \
  || fail "native MCS heartbeat action is missing"
grep -q 'connected_keepalive "$now"' "$GUARD" \
  || fail "healthy-state branch does not invoke the proactive MCS heartbeat"
grep -q 'state=$(fcm_state)' "$GUARD" \
  || fail "heartbeat result is not re-read before clearing outage state"
grep -q 'keepalive exposed disconnected MCS; entering recovery path' "$GUARD" \
  || fail "heartbeat-discovered disconnect does not enter recovery"
grep -q 'pidof com.google.android.gms 2>/dev/null' "$GUARD" \
  || fail "modern GMS main-process fallback is missing"
grep -q 'soft_reconnect_if_stalled' "$GUARD" \
  || fail "lost GMS reconnect-alarm recovery is missing"
grep -q 'com.google.android.intent.action.GCM_RECONNECT' "$GUARD" \
  || fail "soft GCM reconnect broadcast is missing"
grep -q "'in PT-'" "$GUARD" \
  || fail "overdue GMS reconnect scheduler detection is missing"
grep -q 'Command not recognized' "$GUARD" \
  || fail "Android 16 ndc false-success output is not rejected"
grep -q 'Failure calling service' "$GUARD" \
  || fail "failed cmd resolver transactions are not rejected"
grep -q 'ip=$(android_resolve_mtalk' "$GUARD" \
  || fail "FCM path probe does not use Android resolver parity"
if grep -q '61[.]139[.]2[.]69' "$GUARD"; then
  fail "carrier-specific FCM DNS must not be hard-coded in the guard"
fi

heartbeat_line=$(grep -n 'connected_keepalive "$now"' "$GUARD" | head -n1 | cut -d: -f1)
[ -n "$heartbeat_line" ] || fail "cannot locate connected keepalive call"
sed -n "${heartbeat_line},$((heartbeat_line+12))p" "$GUARD" | grep -q 'state=$(fcm_state)' \
  || fail "heartbeat probe must be followed by a fresh GcmService state read"
sed -n "${heartbeat_line},$((heartbeat_line+12))p" "$GUARD" | grep -q 'exit 0' \
  || fail "healthy state must still exit without entering recovery"

unknown_line=$(grep -n 'GMS reported UNKNOWN_HOST' "$GUARD" | head -n1 | cut -d: -f1)
resolver_line=$(grep -n 'Android resolver cannot resolve mtalk.google.com' "$GUARD" | head -n1 | cut -d: -f1)
restart_line=$(grep -n 'kill -TERM "$gpid"' "$GUARD" | head -n1 | cut -d: -f1)
soft_line=$(grep -n 'soft_reconnect_if_stalled "$now" "$outage"' "$GUARD" | tail -n1 | cut -d: -f1)
[ -n "$unknown_line" ] && [ -n "$resolver_line" ] && [ -n "$restart_line" ] \
  || fail "cannot locate DNS/restart policy branches"
[ "$unknown_line" -lt "$restart_line" ] \
  || fail "UNKNOWN_HOST gate must run before GMS restart"
[ "$resolver_line" -lt "$restart_line" ] \
  || fail "Android resolver gate must run before GMS restart"
[ -n "$soft_line" ] && [ "$soft_line" -lt "$restart_line" ] \
  || fail "soft reconnect must run before hard GMS restart"

kill_count=$(grep -c 'kill -TERM "$gpid"' "$GUARD" || true)
[ "$kill_count" -eq 1 ] \
  || fail "GMS SIGTERM must remain one explicit last-resort site"

# Regression for the actual event observed on the device:
# 16777984 packs connection_error=3 (UNKNOWN_HOST) in bits 8..15.
status=16777984
err=$(( (status / 256) % 256 ))
[ "$err" -eq 3 ] || fail "gtalk_connection UNKNOWN_HOST decoder regression"

echo "FCM guard policy regression checks passed"
