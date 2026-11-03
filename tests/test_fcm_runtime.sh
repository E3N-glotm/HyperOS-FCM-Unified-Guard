#!/bin/sh
# Exercise actual health/recovery control flow with mocked OS endpoints.
# alpha12 deliberately does not provoke a new MCS reconnect when healthy.
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
    disconnected:*) echo disconnected;;
    healthy:*) echo connected;;
    *) echo unknown;;
  esac
}
connected_keepalive() { KEEPALIVE_PROBED=0; }
pidof() { echo 12345; }
MOCK
awk 'f || /^# Polling and the event worker/ {f=1; print}' "$ROOT/module/bin/fcm_guard.sh" >> "$T/harness.sh"
export TEST_TMP="$T"
for TEST_CASE in healthy disconnected unknown; do
  export TEST_CASE
  rm -f "$T/reads" "$T/run/fcm_down_since.epoch"
  sh "$T/harness.sh" poll
  case "$TEST_CASE" in
    healthy) [ "$(cat "$T/reads")" -eq 1 ]; [ ! -e "$T/run/fcm_down_since.epoch" ];;
    disconnected) [ "$(cat "$T/reads")" -eq 1 ]; [ -s "$T/run/fcm_down_since.epoch" ];;
    unknown) [ "$(cat "$T/reads")" -eq 1 ]; [ ! -e "$T/run/fcm_down_since.epoch" ];;
  esac
done
echo 'PASS: healthy FCM remains passive; direct disconnection starts outage; unknown never intervenes'
