#!/bin/sh
# Exercises the real settings event loop with two same-second rewrites.
# No Android service, root access, SettingsProvider or network is touched.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/module/bin" "$T/run"
export FCM_UNIFIED_RUNTIME="$T/run"
export SETTINGS_EVENT_RESULT="$T/events.log"
export PATH="$T/bin:$PATH"

sed -e "s@^RUNDIR=/data/adb/fcm_unified_guard@RUNDIR=\$FCM_UNIFIED_RUNTIME@" \
    -e 's@/system/bin/sh@/bin/sh@g' \
    "$ROOT/module/bin/settings_worker.sh" > "$T/module/bin/settings_worker.sh"
cat > "$T/bin/busybox" <<'MOCK'
#!/bin/sh
[ "$1" = inotifyd ] || exit 3
printf 'w /data/system/users/0 settings_system.xml\n'
printf 'w /data/system/users/0 settings_system.xml\n'
sleep 2
MOCK
cat > "$T/module/bin/reconcile.sh" <<'RECONCILE'
#!/bin/sh
# cmd must not inherit the private FIFO as Binder stdin.
[ -c /dev/stdin ] || exit 91
printf '%s\n' "$1" >> "$SETTINGS_EVENT_RESULT"
RECONCILE
chmod +x "$T/bin/busybox" "$T/module/bin/reconcile.sh"

# The worker is intentionally long-lived; timeout stops the harness once
# both the immediate and delayed events have been observed.
timeout 4 /bin/sh "$T/module/bin/settings_worker.sh" >/dev/null 2>&1 || rc=$?
[ "${rc:-0}" -eq 0 ] || [ "$rc" -eq 124 ]
grep -q '^inotify:' "$T/events.log"
grep -qx 'inotify-deferred' "$T/events.log"
count=$(wc -l < "$T/events.log")
[ "$count" -ge 2 ] && [ "$count" -le 3 ] || {
    echo "unexpected event coalescing count=$count" >&2
    exit 1
}
echo 'PASS: Settings events within throttle window receive trailing reconciliation, no FIFO leak'
