#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
export FCM_UNIFIED_RUNTIME="$T"
. "$ROOT/module/bin/runtime_workers.sh"
sleep 60 &
child=$!
start=$(worker_ticks "$child")
printf '%s %s\n' "$child" "$((start+1))" > "$T/events.pid"
stop_workers
kill -0 "$child" # mismatched start time must survive
printf '%s\n' "$child" > "$T/events.pid"
stop_workers
kill -0 "$child" # bare legacy PID must survive
printf '%s %s\n' "$child" "$start" > "$T/events.pid"
stop_workers
wait "$child" 2>/dev/null || true
! kill -0 "$child" 2>/dev/null
echo 'PASS: no kills for reused or legacy PID; verified worker stops'
