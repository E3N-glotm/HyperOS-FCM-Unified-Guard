#!/bin/sh
# Exercise real control flow with mocked OS endpoints, including stale-MCS.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
export FCM_UNIFIED_RUNTIME="$T/run"
mkdir -p "$T/bin" "$T/run"
awk '/^# Polling and the event worker/{exit} {print}' "$ROOT/module/bin/fcm_guard.sh" \
  | sed "s|MODDIR=\${0%/\*}/..|MODDIR=$ROOT/module|" > "$T/harness.sh"
cat >> "$T/harness.sh" <<'MOCK'
ensure_fcm_uid_bypass() { :; }
acquire_guard_lock() { return 0; }
release_guard_lock() { :; }
fcm_state() {
  n=$(cat "$TEST_TMP/reads" 2>/dev/null || echo 0)
  n=$((n+1))
  echo "$n" > "$TEST_TMP/reads"
  case "$TEST_CASE:$n" in
    unknown:*) echo unknown;;
    stale:1|healthy:*) echo connected;;
    *) echo disconnected;;
  esac
}
connected_keepalive() {
  KEEPALIVE_PROBED=0
  [ "$TEST_CASE" != stale ] || KEEPALIVE_PROBED=1
}
pidof() { echo 12345; }
MOCK
awk 'f || /^# Polling and the event worker/ {f=1; print}' "$ROOT/module/bin/fcm_guard.sh" >> "$T/harness.sh"
export TEST_TMP="$T"
for TEST_CASE in healthy stale unknown; do
  export TEST_CASE
  rm -f "$T/reads" "$T/run/fcm_down_since.epoch"
  sh "$T/harness.sh" poll
  case "$TEST_CASE" in
    healthy) [ "$(cat "$T/reads")" -eq 1 ]; [ ! -e "$T/run/fcm_down_since.epoch" ];;
    stale) [ "$(cat "$T/reads")" -eq 2 ]; [ -s "$T/run/fcm_down_since.epoch" ];;
    unknown) [ "$(cat "$T/reads")" -eq 1 ]; [ ! -e "$T/run/fcm_down_since.epoch" ];;
  esac
done
echo 'PASS: one healthy state read; heartbeat-discovered outage retained; unknown never intervenes'
