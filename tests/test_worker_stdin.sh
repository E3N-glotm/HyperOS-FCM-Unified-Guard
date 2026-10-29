#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin" "$T/module/bin" "$T/run"
export FCM_UNIFIED_RUNTIME="$T/run" STDIN_AUDIT="$T/result"
export PATH="$T/bin:$PATH"
# Run the real dispatch loops with finite event producers and Binder probes.
# Only Android executable/runtime paths are adapted for the Linux test host.
for worker in settings_worker unified_event_worker; do
  sed -e "s@^RUNDIR=/data/adb/fcm_unified_guard@RUNDIR=\$FCM_UNIFIED_RUNTIME@" \
      -e 's@/system/bin/sh@/bin/sh@g' \
      "$ROOT/module/bin/$worker.sh" > "$T/module/bin/$worker.sh"
done
cp "$ROOT/module/bin/runtime_workers.sh" "$T/module/bin/"
cat > "$T/bin/busybox" <<'MOCK'
#!/bin/sh
[ "$1" = inotifyd ] || exit 3
printf 'w /data/system/users/0 settings_system.xml\n'
printf 'w %s packages.list\n' "$FCM_UNIFIED_RUNTIME"
MOCK
cat > "$T/bin/logcat" <<'MOCK'
#!/bin/sh
case "$1" in --help) echo --regex; exit 0;; esac
echo 'I/am_kill(1): stop com.example.app due to SwipeUpClean'
echo 'I/whetstone.activity(1): sourcePkg=com.google.android.gms targetPkg=com.example.app'
while [ ! -e "$FCM_UNIFIED_RUNTIME/alarm-handled" ]; do /bin/sleep 0.01; done
MOCK
cat > "$T/bin/sleep" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$T/module/bin/reconcile.sh" <<'PROBE'
#!/bin/sh
if python -c 'import os,stat,sys; sys.exit(not stat.S_ISCHR(os.fstat(0).st_mode))'; then
  echo "PASS $1" >> "$STDIN_AUDIT"
else
  echo "FAIL inherited FIFO: $1" >> "$STDIN_AUDIT"
fi
case "$1" in
  config-event) touch "${0%/*}/../disable";;
  alarm-event) touch "${0%/*}/../disable" "$FCM_UNIFIED_RUNTIME/alarm-handled";;
esac
PROBE
cp "$T/module/bin/reconcile.sh" "$T/module/bin/swipe_unstop_worker.sh"
cp "$T/module/bin/reconcile.sh" "$T/module/bin/fcm_guard.sh"
chmod +x "$T/bin/"*
printf 'com.google.android.gms\n' > "$T/run/packages.list"
timeout 10 sh "$T/module/bin/settings_worker.sh"
rm -f "$T/module/disable"
timeout 10 sh "$T/module/bin/unified_event_worker.sh"
! grep -q '^FAIL' "$T/result"
grep -q '^PASS inotify:' "$T/result"
grep -qx 'PASS config-event' "$T/result"
grep -qx 'PASS --handle-line' "$T/result"
grep -qx 'PASS alarm-event' "$T/result"
echo 'PASS: all four event dispatch paths isolate Binder stdin from private FIFOs'
