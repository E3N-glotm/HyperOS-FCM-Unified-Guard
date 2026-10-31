#!/bin/sh
# An existing GMS gtalk_connection event must reach the merged, single
# logcat reader and run one opportunistic FCM check. No new process/wakeup.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module/bin" "$T/runtime" "$T/bin"
# MSYS /proc/uptime may be unavailable. Inject a deterministic host-only
# uptime stream; production still uses the real Android /proc/uptime.
printf '%s\n' '10000.00 12345.00' > "$T/runtime/uptime"
sed -e "s|^RUNDIR=/data/adb/fcm_unified_guard|RUNDIR=$T/runtime|" \
    -e "s|/proc/uptime|$T/runtime/uptime|g" \
    -e 's|/system/bin/sh|/bin/sh|g' \
    "$ROOT/module/bin/unified_event_worker.sh" > "$T/module/bin/unified_event_worker.sh"
cp "$ROOT/module/bin/runtime_workers.sh" "$T/module/bin/runtime_workers.sh"
printf '%s\n' com.google.android.gms > "$T/runtime/packages.list"
cat > "$T/module/bin/fcm_guard.sh" <<'GUARD'
#!/bin/sh
printf '%s\n' "${1:-none}" >> "$FCM_TEST_EVENTS"
GUARD
cat > "$T/module/bin/swipe_unstop_worker.sh" <<'SWIPE'
#!/bin/sh
exit 0
SWIPE
cat > "$T/bin/logcat" <<'MOCK'
#!/bin/sh
if [ "${1:-}" = --help ]; then echo 'logcat --regex supported'; exit 0; fi
printf '%s\n' "$*" > "$FCM_TEST_LOGCAT_ARGS"
printf '%s\n' 'I/gtalk_connection(123): [gms 0 UNKNOWN_HOST]'
sleep 6
MOCK
chmod +x "$T/bin/logcat"
export FCM_TEST_EVENTS="$T/events.txt" FCM_TEST_LOGCAT_ARGS="$T/logcat_args.txt"
PATH="$T/bin:$PATH" /bin/sh "$T/module/bin/unified_event_worker.sh" > "$T/worker.stdout" 2> "$T/worker.stderr" &
worker=$!
sleep 2
kill "$worker" 2>/dev/null || true
wait "$worker" 2>/dev/null || true
[ -s "$FCM_TEST_EVENTS" ] || {
  echo 'FAIL: event did not invoke guard' >&2
  cat "$T/worker.stderr" "$T/worker.stdout" "$T/logcat_args.txt" 2>/dev/null || :
  ls -la "$T" "$T/runtime" "$T/module/bin" >&2
  exit 1
}
[ "$(wc -l < "$FCM_TEST_EVENTS")" -eq 1 ] || { echo 'FAIL: unexpectedly repeated guard calls' >&2; exit 1; }
grep -qx 'alarm-event' "$FCM_TEST_EVENTS"
grep -Fq -- '-b main -b events' "$FCM_TEST_LOGCAT_ARGS"
grep -Fq -- 'gtalk_connection:I' "$FCM_TEST_LOGCAT_ARGS"
grep -Fq -- '--regex=' "$FCM_TEST_LOGCAT_ARGS"
grep -Fq -- 'whetstone.activity:I am_kill:I gtalk_connection:I' "$FCM_TEST_LOGCAT_ARGS"
[ ! -e "$T/runtime/events.$worker.fifo" ] || { echo 'FAIL: fifo leak' >&2; exit 1; }
echo 'PASS: existing logcat/one FIFO dispatches GMS connection attempts with no new watchdog/wakeups'
