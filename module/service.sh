#!/system/bin/sh
MODDIR=${0%/*}
RUNDIR=/data/adb/fcm_unified_guard
LOG=$RUNDIR/module.log
BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=/system/xbin/busybox
[ -x "$BB" ] || BB=busybox
mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
. "$MODDIR/bin/runtime_workers.sh"
# Serialize starts and reject stale lock owners using /proc start ticks.
START_LOCK=$RUNDIR/startup.lock
if ! mkdir "$START_LOCK" 2>/dev/null; then
  read -r previous_pid previous_ticks < "$START_LOCK/owner" 2>/dev/null || exit 0
  [ "$(worker_ticks "$previous_pid")" != "$previous_ticks" ] || exit 0
  rm -f "$START_LOCK/owner"
  rmdir "$START_LOCK" 2>/dev/null || exit 0
  mkdir "$START_LOCK" 2>/dev/null || exit 0
fi
printf '%s %s\n' "$$" "$(worker_ticks $$)" > "$START_LOCK/owner"
trap 'rm -f "$START_LOCK/owner"; rmdir "$START_LOCK" 2>/dev/null' EXIT
trap 'exit 0' HUP INT TERM
stop_workers
if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
  echo 'DISABLED: workers not started' > "$RUNDIR/startup-status.txt"
  exit 0
fi
if [ -d /data/adb/modules/gms_millet_guard ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/disable ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/remove ]; then
  echo 'CONFLICT: Millet Guard still enabled; Unified Guard refuses duplicate writers' > "$RUNDIR/startup-status.txt"
  exit 0
fi
if [ -d "$RUNDIR/reconcile.lock" ] && [ ! -f "$RUNDIR/reconcile.lock/owner" ]; then
  rmdir "$RUNDIR/reconcile.lock" 2>/dev/null || true
fi
i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 180 ]; do
  sleep 2
  i=$((i+1))
done
[ "$(getprop sys.boot_completed)" = 1 ] || exit 0
sleep 8
/system/bin/sh "$MODDIR/bin/reconcile.sh" boot
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" apply >/dev/null 2>&1 || true
/system/bin/sh "$MODDIR/bin/bridge_status.sh" > "$RUNDIR/bridge-status.txt" 2>&1 || true
/system/bin/sh "$MODDIR/bin/settings_worker.sh" >/dev/null 2>&1 &
record_worker settings $!
/system/bin/sh "$MODDIR/bin/maintenance_worker.sh" >/dev/null 2>&1 &
record_worker maintenance $!
/system/bin/sh "$MODDIR/bin/unified_event_worker.sh" >/dev/null 2>&1 &
record_worker events $!
echo 'ACTIVE: unified core; bridge registration tracked separately in bridge-status.txt' > "$RUNDIR/startup-status.txt"
echo "$(date '+%Y-%m-%d %H:%M:%S') started unified maintenance + single event stream" >> "$LOG"
