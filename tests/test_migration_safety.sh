#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/tools/migrate_device.sh"
grep -Fq 'actual=$(ps -A -o PID,ARGS' "$SCRIPT"
grep -Fq 'if [ -f ' "$SCRIPT" || true
grep -Fq '[ "$pid" -gt 2 ]' "$SCRIPT"
grep -Fq 'fail "old worker pid=' "$SCRIPT"
! grep -q 'old-worker-pids.txt' "$SCRIPT"
! grep -q 'selected\[parent\[p\]\]' "$SCRIPT"
! grep -q 'kill -STOP' "$SCRIPT"
! grep -q 'kill -KILL' "$SCRIPT"
echo 'PASS: migration limits process signals to verified original workers'
