#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RECONCILE="$ROOT/module/bin/reconcile.sh"

# The production regression was an external Toybox reader spinning forever on
# ESRCH after the lock owner disappeared. Keep this lock path free of cmdline
# translation entirely.
if grep -nE '/proc/\$owner_pid/cmdline|tr .*\\000' "$RECONCILE"; then
  echo "reconcile lock validation must not read cmdline through tr" >&2
  exit 1
fi

# Exercise the actual production helper functions without sourcing the full
# reconcile entrypoint (which would touch Android settings).
eval "$(sed -n '/^proc_start_ticks() {$/,/^}$/p' "$RECONCILE")"
eval "$(sed -n '/^lock_owner_alive() {$/,/^}$/p' "$RECONCILE")"

expected=$(awk '{print $22}' "/proc/$$/stat")
actual=$(proc_start_ticks $$)
[ "$actual" = "$expected" ] || {
  echo "proc_start_ticks mismatch: expected=$expected actual=$actual" >&2
  exit 1
}

tmp=${TMPDIR:-/tmp}/millet-guard-lock-test.$$
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/reconcile.lock"
LOCK="$tmp/reconcile.lock"
LOCK_OWNER="$LOCK/owner"
printf '%s %s\n' "$$" "$actual" > "$LOCK_OWNER"
lock_owner_alive || {
  echo "live PID/start-time owner was rejected" >&2
  exit 1
}

printf '%s %s\n' "$$" "$((actual + 1))" > "$LOCK_OWNER"
if lock_owner_alive; then
  echo "PID-reuse/start-time mismatch was accepted" >&2
  exit 1
fi

# A process that has exited must fail promptly and must not leave any external
# cmdline translator behind.
sleep 0.01 &
dead_pid=$!
wait "$dead_pid"
if proc_start_ticks "$dead_pid" >/dev/null 2>&1; then
  echo "dead process unexpectedly reported a start time" >&2
  exit 1
fi

echo "reconcile lock regression: PASS"
