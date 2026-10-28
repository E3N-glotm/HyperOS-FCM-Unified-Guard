#!/system/bin/sh
MODDIR=${0%/*}
RUNDIR=/data/adb/fcm_unified_guard
if [ -d /data/adb/modules/gms_millet_guard ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/disable ] &&
   [ ! -e /data/adb/modules/gms_millet_guard/remove ]; then
  echo 'CONFLICT: Original Millet Guard is active. Refusing to write the same whitelist.'
  echo 'Disable the original module and reboot before enabling Unified Guard.'
  cat "$RUNDIR/startup-status.txt" 2>/dev/null || true
  exit 0
fi
/system/bin/sh "$MODDIR/bin/reconcile.sh" action
echo '=== FCM Unified Guard diagnostics ==='
/system/bin/sh "$MODDIR/bin/milletctl" status
/system/bin/sh "$MODDIR/bin/capability_report.sh" 2>/dev/null || true
echo 'Native DeviceIdle policy:'
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status 2>/dev/null || true
echo 'Startup status:'
cat "$RUNDIR/startup-status.txt" 2>/dev/null || true
echo 'Watchers:'
for f in "$RUNDIR/inotifyd.pid" "$RUNDIR/safety.pid" \
         "$RUNDIR/fcm.pid" "$RUNDIR/fcm_event.pid" \
         "$RUNDIR/swipe_unstop.pid"; do
  [ -f "$f" ] && echo "$(basename "$f"): $(cat "$f")"
done
echo 'Recent log:'
tail -n 80 "$RUNDIR/module.log" 2>/dev/null || true
