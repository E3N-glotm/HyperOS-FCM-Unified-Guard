#!/system/bin/sh
MODDIR=${0%/*}
RUNDIR=/data/adb/fcm_unified_guard
LOG=$RUNDIR/module.log
BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB=/system/xbin/busybox
[ -x "$BB" ] || BB=busybox
mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
if [ -d /data/adb/modules/gms_millet_guard ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/disable ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/remove ]; then
  echo "CONFLICT: Millet Guard still enabled; Unified Guard refuses to start duplicate writers" > "$RUNDIR/startup-status.txt"
  exit 0
fi
echo "ACTIVE: standalone Magisk mode (LSPosed hooks not replicated)" > "$RUNDIR/startup-status.txt"
chmod 0755 "$MODDIR/bin/inotify_handler.sh" "$MODDIR/bin/reconcile.sh" "$MODDIR/bin/milletctl" "$MODDIR/bin/fcm_guard.sh" "$MODDIR/bin/fcm_event_worker.sh" "$MODDIR/bin/swipe_unstop_worker.sh" 2>/dev/null || true
# v2.0.2 and newer use owner metadata for the reconcile lock. An ownerless
# lock left by v2.0.1 can otherwise survive an in-place module upgrade until
# its first safety pass. Reap only the legacy ownerless form here, before any
# new reconciliation process can exist.
if [ -d "$RUNDIR/reconcile.lock" ] && [ ! -f "$RUNDIR/reconcile.lock/owner" ]; then
  rm -rf "$RUNDIR/reconcile.lock" 2>/dev/null || true
fi
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
  lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  if [ "$lines" -gt 500 ] 2>/dev/null; then
    tail -n 300 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
  fi
}
# Wait for SettingsProvider/system_server.
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 180 ]; do
  sleep 2
  i=$((i+1))
done
sleep 8
/system/bin/sh "$MODDIR/bin/reconcile.sh" boot
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" apply >/dev/null 2>&1 || true
# Stop stale module-owned workers.
for f in inotifyd.pid safety.pid fcm.pid fcm_event.pid swipe_unstop.pid; do
  if [ -f "$RUNDIR/$f" ]; then
    old=$(cat "$RUNDIR/$f" 2>/dev/null)
    [ -n "$old" ] && kill "$old" 2>/dev/null || true
  fi
done
# Primary path: event-driven SettingsProvider watcher.
"$BB" inotifyd "$MODDIR/bin/inotify_handler.sh" /data/system/users/0:wymnD >/dev/null 2>&1 &
echo $! > "$RUNDIR/inotifyd.pid"
# Low-frequency fallback for missed events and runtime Xiaomi policy changes.
(
  while true; do
    sleep 300
    /system/bin/sh "$MODDIR/bin/reconcile.sh" safety
  done
) >/dev/null 2>&1 &
echo $! > "$RUNDIR/safety.pid"
# FCM health is deliberately independent of reconcile.sh. A SettingsProvider
# failure or reconciliation lock must not disable push recovery again. This is
# only a fallback: deep suspend can defer shell sleeps, so the event worker
# below also piggybacks on GMS's own AlarmManager wakeups.
(
  while true; do
    sleep 120
    grep -Fxq 'com.google.android.gms' "$RUNDIR/packages.list" 2>/dev/null || continue
    /system/bin/sh "$MODDIR/bin/fcm_guard.sh" poll
  done
) >/dev/null 2>&1 &
echo $! > "$RUNDIR/fcm.pid"
# No new timer/wakelock: observe existing GMS alarm deliveries and check FCM
# when HyperOS has already woken the push stack.
/system/bin/sh "$MODDIR/bin/fcm_event_worker.sh" >/dev/null 2>&1 &
echo $! > "$RUNDIR/fcm_event.pid"
# HyperOS Recents swipe may force-stop a managed package. On Android 16,
# clear only that stopped bit so FCM remains eligible to wake the dead process.
/system/bin/sh "$MODDIR/bin/swipe_unstop_worker.sh" >/dev/null 2>&1 &
echo $! > "$RUNDIR/swipe_unstop.pid"
log "started inotify=$(cat "$RUNDIR/inotifyd.pid") safety=$(cat "$RUNDIR/safety.pid") fcm=$(cat "$RUNDIR/fcm.pid") fcm_event=$(cat "$RUNDIR/fcm_event.pid") swipe_unstop=$(cat "$RUNDIR/swipe_unstop.pid")"
