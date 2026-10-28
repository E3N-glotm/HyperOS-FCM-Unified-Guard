#!/system/bin/sh
MODDIR=${0%/*}
echo '=== FCM Unified Guard static candidate ==='
/system/bin/sh "$MODDIR/bin/static_status.sh" || exit 0
/system/bin/sh "$MODDIR/bin/milletctl" status
/system/bin/sh "$MODDIR/bin/deviceidle_policy.sh" status
cat /data/adb/fcm_unified_guard/startup-status.txt 2>/dev/null
tail -n 35 /data/adb/fcm_unified_guard/module.log 2>/dev/null
