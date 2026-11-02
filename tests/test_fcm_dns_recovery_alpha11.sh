#!/bin/sh
# alpha11 isolated regression: GMS UNKNOWN_HOST alone must never indefinitely
# hold GMS recovery after two independent, time-separated DNS successes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
GUARD=$ROOT/module/bin/fcm_guard.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
export FCM_UNIFIED_RUNTIME="$T/run" TEST_TMP="$T"
mkdir -p "$T/run"
awk '/^# Polling and the event worker/{exit} {print}' "$GUARD" | sed "s|^MODDIR=.*|MODDIR=$ROOT/module|" > "$T/harness.sh"
cat >> "$T/harness.sh" <<'MOCK'
date() { if [ "${1:-}" = '+%s' ]; then printf '%s\n' "$TEST_NOW"; else command date "$@"; fi; }
acquire_guard_lock() { return 0; }
release_guard_lock() { return 0; }
ensure_fcm_uid_bypass() { return 0; }
fcm_state() { echo disconnected; }
pidof() { echo 12345; }
recent_gms_unknown_host_epoch() { echo $((TEST_NOW-8)); }
android_resolve_mtalk() { [ "$TEST_DNS" = ok ] || return 1; echo '142.250.99.188'; }
soft_reconnect_if_stalled() { printf 'soft %s\n' "$TEST_NOW" >> "$TEST_TMP/soft.log"; return 1; }
fcm_path_ready() { printf 'android 142.250.99.188 5228\n'; }
flush_android_dns() { :; }
kill() { echo "kill $TEST_NOW $*" >> "$TEST_TMP/kills.log"; return 0; }
sleep() { :; }
run_timeout() { return 0; }
MOCK
awk 'f || /^# Polling and the event worker/ {f=1;print}' "$GUARD" >> "$T/harness.sh"
printf '%s\n' 1000 > "$T/run/fcm_down_since.epoch"
run_case() { TEST_NOW=$1 TEST_DNS=$2 /bin/sh "$T/harness.sh" poll; }
count_kills() { if [ -f "$T/kills.log" ]; then wc -l < "$T/kills.log" | tr -d ' '; else printf 0; fi; }
run_case 1400 fail
[ -e "$T/run/fcm_dns_fail.epoch" ] || { echo 'FAIL: DNS failure not recorded'; exit 1; }
[ "$(count_kills)" -eq 0 ] || { echo 'FAIL: restarted while DNS failed'; exit 1; }
run_case 1500 ok
[ -s "$T/run/fcm_dns_recovered_since.epoch" ] || { echo 'FAIL: no DNS stability timer'; exit 1; }
[ "$(count_kills)" -eq 0 ] || { echo 'FAIL: restart before stable DNS'; exit 1; }
run_case 1550 ok
[ "$(count_kills)" -eq 0 ] || { echo 'FAIL: restart inside 90-second grace'; exit 1; }
run_case 1591 ok
[ "$(count_kills)" -eq 1 ] || { echo 'FAIL: repeated historical UNKNOWN_HOST still blocks healthy 5228 path'; exit 1; }
[ ! -e "$T/run/fcm_dns_fail.epoch" ] || { echo 'FAIL: stale failure not cleared'; exit 1; }
run_case 1800 fail
[ "$(count_kills)" -eq 1 ] || { echo 'FAIL: restarted despite new DNS outage'; exit 1; }
[ ! -e "$T/run/fcm_dns_recovered_since.epoch" ] || { echo 'FAIL: recovery timer not reset after DNS failed'; exit 1; }
run_case 1900 ok
[ "$(count_kills)" -eq 1 ] || { echo 'FAIL: restarted after first recovered sample'; exit 1; }
echo 'PASS alpha11: current DNS overrides stale UNKNOWN_HOST; 90s stability; DNS failure blocks GMS restart'
